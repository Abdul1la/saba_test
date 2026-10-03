import { createHash } from 'node:crypto'
import { z } from 'zod'
import type { Context } from '../app.js'
import type { Connection } from '../db/pool.js'
import { exec, one } from '../db/sql.js'
import { withTransaction } from '../db/tx.js'
import { me } from '../http/auth.js'
import { AppError } from '../http/errors.js'
import { route, type Api } from '../http/route.js'
import { fold } from '../lib/fold.js'
import { governorateNames } from '../lib/governorates.js'
import { t, type Lang } from '../lib/i18n.js'
import { paidUnitPrice } from '../lib/money.js'
import { publish } from '../lib/events.js'
import { notify } from '../lib/notify.js'
import {
  addressOf,
  buyNowLines,
  cartCoupon,
  cartLines,
  CheckoutBody,
  loadWorld,
  priceLines,
  problemsOf,
  type AddressRow,
  type Part,
  type Priced,
} from './cart.js'
import { addStep, bothNames, loadOrders, Order, orderJson } from './orders.js'

// Placing an order (BACKEND_PLAN.md §6.3): money and stock in one transaction,
// under the locks of DATABASE_DESIGN.md §5.2. Priced by the same function as
// the cart and the review, so the three can't disagree.

const PlacedOrder = z.object({ order: Order, requiresPaymentAction: z.literal(false) }).meta({ id: 'PlacedOrder' })
type PlacedOrder = z.input<typeof PlacedOrder>

/** The same body, whatever order its keys came in, hashes the same. */
function canonical(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`
  if (value !== null && typeof value === 'object') {
    const object = value as Record<string, unknown>
    return `{${Object.keys(object)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonical(object[key])}`)
      .join(',')}}`
  }
  return JSON.stringify(value ?? null)
}

export function checkoutRoutes(api: Api, ctx: Context): void {
  const { pool } = ctx

  route(api, {
    method: 'post',
    path: '/checkout/place-order',
    tag: 'Checkout',
    summary: 'Place the order, cash on delivery. Idempotency-Key required: the same key again answers the same order',
    who: ['CUSTOMER'],
    body: CheckoutBody,
    response: PlacedOrder,
    async handle({ req, body }) {
      const key = String(req.headers['idempotency-key'] ?? '').trim()
      if (!/^[\x21-\x7e]{1,64}$/.test(key)) {
        throw new AppError(422, 'VALIDATION_ERROR', 'error.validation', undefined, { idempotencyKey: { key: 'field.required' } })
      }
      if (body.paymentMethodId && body.paymentMethodId !== 'pm-cod') {
        throw new AppError(422, 'BUSINESS_RULE_ERROR', 'cart.codOnly', undefined, { paymentMethodId: { key: 'cart.codOnly' } })
      }
      const userId = me(req).id
      const hash = createHash('sha256').update(canonical(req.body)).digest()
      const cities = await governorateNames(pool)

      return withTransaction(pool, async (conn): Promise<PlacedOrder> => {
        // One checkout per shopper at a time: everything below runs under this lock.
        await one(conn, 'SELECT id FROM users WHERE id = ? FOR UPDATE', [userId])
        // Read after the lock: a checkout with this key that finished meanwhile is seen.
        const done = await one<{ request_hash: Buffer; response: PlacedOrder }>(
          conn,
          'SELECT request_hash, response FROM idempotency_keys WHERE user_id = ? AND idem_key = ?',
          [userId, key],
        )
        if (done) {
          // A retry of this checkout gets the order it made; the same key for anything else is refused.
          if (!hash.equals(done.request_hash)) throw new AppError(422, 'VALIDATION_ERROR', 'order.keyReused')
          return done.response
        }

        const address = await addressOf(conn, userId, body.addressId)
        const buyNow = (body.items?.length ?? 0) > 0
        const lines = buyNow ? await buyNowLines(conn, body.items!) : (await cartLines(conn, userId, true)).filter((line) => !line.saved)
        if (lines.length === 0) throw new AppError(422, 'BUSINESS_RULE_ERROR', 'cart.empty')
        const world = await loadWorld(conn, lines, buyNow ? null : await cartCoupon(conn, userId, true), true)
        const priced = priceLines(world, lines, address.governorate, new Date(), !buyNow)

        const [problem] = await problemsOf(conn, userId, priced, buyNow)
        if (problem) throw new AppError(422, problem.code, problem.key, problem.params)
        const away = priced.parts.find((part) => part.reach === null)
        if (away) {
          const why = (lang: Lang) =>
            !away.store.approved || !away.store.open
              ? t(lang, 'cart.closed')
              : t(lang, 'cart.noDelivery', { city: cities.get(address.governorate)?.[lang] ?? address.governorate })
          throw new AppError(422, 'BUSINESS_RULE_ERROR', 'cart.storeCantDeliver', { store: away.store.name, why: { en: why('en'), ar: why('ar') } })
        }

        const orderId = await write(conn, userId, address, body, priced)
        if (!buyNow) {
          // What was ordered leaves the cart, and so does the code; anything added meanwhile stays.
          await exec(conn, 'DELETE FROM cart_items WHERE user_id = ? AND id IN (?)', [userId, lines.map((line) => line.id)])
          await exec(conn, 'UPDATE carts SET coupon_id = NULL WHERE user_id = ?', [userId])
        }
        const response: PlacedOrder = {
          order: orderJson(req, ctx, (await loadOrders(conn, [orderId]))[0]!),
          // Cash is paid at the door: there is nothing to pay now.
          requiresPaymentAction: false,
        }
        await exec(conn, 'INSERT INTO idempotency_keys (user_id, idem_key, request_hash, response) VALUES (?, ?, ?, ?)', [
          userId,
          key,
          hash,
          JSON.stringify(response),
        ])
        return response
      })
    },
  })
}

const units = (part: Part) => part.lines.reduce((sum, line) => sum + line.line.quantity, 0)

/** Writes the order, its parts, lines and first step; takes the stock; counts the code's use; tells each store. */
async function write(conn: Connection, userId: number, address: AddressRow, body: CheckoutBody, priced: Priced): Promise<number> {
  // A use is counted only when the code took something off (BUGS 166).
  const coupon = priced.discount > 0 ? priced.coupon!.row : null
  const inserted = await exec(
    conn,
    `INSERT INTO orders (customer_id, subtotal, discount, shipping, total, item_count, coupon_id, coupon_code, customer_name,
                         customer_name_ar, customer_phone, ship_governorate, ship_area, ship_area_ar, ship_street, ship_street_ar,
                         ship_landmark, ship_landmark_ar, instructions, placed_at, search_text)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW(3), '')`,
    [
      userId,
      priced.subtotal,
      priced.discount,
      priced.shipping,
      priced.total,
      priced.parts.reduce((sum, part) => sum + units(part), 0),
      coupon?.id ?? null,
      coupon?.code ?? null,
      // The address as it is now: editing it later must not move a parcel on its way.
      address.full_name,
      address.full_name_ar,
      address.phone,
      address.governorate,
      address.area,
      address.area_ar,
      address.street,
      address.street_ar,
      address.landmark,
      address.landmark_ar,
      body.deliveryInstructions ?? address.instructions,
    ],
  )
  const orderId = inserted.insertId
  const number = `SB-${100000 + orderId}`
  const searched = [number, address.full_name, address.full_name_ar ?? '']

  for (const part of priced.parts) {
    const reach = part.reach!
    const partId = (
      await exec(
        conn,
        `INSERT INTO order_store_parts (order_id, store_id, subtotal, discount, shipping_fee, amount_due, item_count, delivery_time)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
        [orderId, part.store.id, part.subtotal, part.discount, reach.fee, part.amountDue, units(part), reach.time],
      )
    ).insertId
    searched.push(part.store.name)
    for (const line of part.lines) {
      const { row, images } = line.loaded
      const quantity = line.line.quantity
      await exec(
        conn,
        `INSERT INTO order_items (order_id, part_id, product_id, sku_id, product_name, product_name_ar, variant_label, sku_code,
                                  image_url, store_name, unit_price, paid_unit_price, quantity, line_total)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          orderId,
          partId,
          row.id,
          line.sku.id,
          row.name_en ?? row.name_ar,
          row.name_ar,
          line.sku.option_label,
          line.sku.sku_code,
          images[0]?.url ?? null,
          part.store.name,
          line.unitPrice,
          paidUnitPrice(line.unitPrice, part.subtotal, part.discount),
          quantity,
          line.lineTotal,
        ],
      )
      searched.push(row.name_en ?? '', row.name_ar)
      // Its stock was read under its lock and checked; ck_product_skus_stock holds it again.
      await exec(conn, 'UPDATE product_skus SET stock = stock - ? WHERE id = ?', [quantity, line.sku.id])
      await exec(conn, "INSERT INTO stock_movements (sku_id, delta, reason, part_id, actor_user_id) VALUES (?, ?, 'ORDER_PLACED', ?, ?)", [
        line.sku.id,
        -quantity,
        partId,
        userId,
      ])
    }
    const count = units(part)
    const words = {
      number,
      customer: bothNames(address.full_name, address.full_name_ar),
      items: `${count} ${count === 1 ? 'item' : 'items'}`,
      count,
    }
    await notify(
      conn,
      part.store.owner,
      'ORDER',
      {
        en: { title: t('en', 'notify.newOrder.title', words), body: t('en', 'notify.newOrder.body', words) },
        ar: { title: t('ar', 'notify.newOrder.title', words), body: t('ar', 'notify.newOrder.body', words) },
      },
      { type: 'STORE_ORDER', id: partId },
      { push: true },
    )
    publish(conn, part.store.owner, 'orders', partId)
  }
  publish(conn, [userId, 'ADMINS'], 'orders', orderId)

  await exec(conn, 'UPDATE orders SET order_number = ?, search_text = ? WHERE id = ?', [number, fold(searched.join(' ')), orderId])
  await addStep(conn, orderId, null, 'PENDING', { noteCode: 'ORDER_RECEIVED' })
  // Read live under its lock and checked; ck_coupons_usage holds the limit again.
  if (coupon) await exec(conn, 'UPDATE coupons SET used_count = used_count + 1 WHERE id = ?', [coupon.id])
  return orderId
}
