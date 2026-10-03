import type { Request } from 'express'
import { z } from 'zod'
import type { Context } from '../app.js'
import type { Connection, Pool } from '../db/pool.js'
import { exec, one, rows } from '../db/sql.js'
import { withTransaction } from '../db/tx.js'
import { me } from '../http/auth.js'
import { AppError } from '../http/errors.js'
import { IdParams } from '../http/inputs.js'
import { Page, PageQuery, route, type Api } from '../http/route.js'
import { GOVERNORATES } from '../lib/governorates.js'
import { t, type Lang, type MessageKey } from '../lib/i18n.js'
import { publish } from '../lib/events.js'
import { notify, type NotificationType } from '../lib/notify.js'
import { billingMonth } from '../lib/money.js'
import { normalizePhone } from '../lib/phone.js'
import {
  addressJson,
  addStep,
  loadOrders,
  orderWords,
  PART_STATUSES,
  releaseCoupon,
  restock,
  rollUp,
  type OrderData,
  type PartRow,
  type PartStatus,
} from './orders.js'
import { Return, returnsOfPart } from './returns.js'
import { DELIVERY_TIMES } from './stores.js'

// The store's orders (BACKEND_PLAN.md §6.5): its own parts only, and the one
// way each moves on (DATABASE_DESIGN.md §5.3). A part declined or refused at
// the door puts its stock back; a delivered one is on that month's bill.

/** The steps the server allows, and nothing else: DELIVERED, CANCELLED and REFUSED are ends. */
const NEXT: Partial<Record<PartStatus, readonly PartStatus[]>> = {
  PENDING: ['CONFIRMED', 'CANCELLED'],
  CONFIRMED: ['PROCESSING'],
  PROCESSING: ['SHIPPED'],
  SHIPPED: ['DELIVERED', 'REFUSED'],
}

const DECLINE_REASONS = ['OUT_OF_STOCK', 'CANNOT_FULFIL', 'ADDRESS_PROBLEM', 'CUSTOMER_ASKED'] as const

/** The steps the shopper is pushed (S10): confirmed, shipped, delivered, declined. Preparing and refused wait in the list. */
const PUSHED: readonly PartStatus[] = ['CONFIRMED', 'SHIPPED', 'DELIVERED', 'CANCELLED']

const Status = z.enum(PART_STATUSES)

const StoreOrder = z
  .object({
    id: z.string(),
    merchantId: z.string(),
    customerOrderId: z.string(),
    customerId: z.string(),
    orderNumber: z.string(),
    placedAt: z.string(),
    status: Status,
    subtotal: z.number(),
    discount: z.number(),
    shipping: z.number(),
    total: z.number(),
    currencyCode: z.literal('IQD'),
    itemCount: z.number(),
    customerName: z.string(),
    customerArea: z.string(),
    customerGovernorate: z.enum(GOVERNORATES),
    customerPhone: z.string(),
    deliveryTime: z.enum(DELIVERY_TIMES),
    shippingAddress: z.object({
      fullName: z.string(),
      phone: z.string(),
      governorate: z.enum(GOVERNORATES),
      area: z.string(),
      street: z.string().nullable(),
      landmark: z.string(),
      instructions: z.string().nullable(),
    }),
    paymentMethodLabel: z.string(),
    previewImageUrl: z.string().nullable(),
    items: z.array(
      z.object({
        id: z.string(),
        productId: z.string(),
        variantId: z.string().nullable(),
        name: z.string(),
        imageUrl: z.string().nullable(),
        sku: z.string().nullable(),
        variantLabel: z.string().nullable(),
        quantity: z.number(),
        price: z.number(),
        paidUnitPrice: z.number(),
      }),
    ),
    courierType: z.literal('DRIVER').nullable(),
    courierName: z.string().nullable(),
    courierPhone: z.string().nullable(),
    cancellationReason: z.string().nullable(),
    received: z.boolean().nullable(),
    deliveredAt: z.string().nullable(),
  })
  .meta({ id: 'StoreOrder' })

/** The shopper's words for a store's step: [title, body, notification type]. */
const TOLD: Partial<Record<PartStatus, [MessageKey, MessageKey, NotificationType]>> = {
  CONFIRMED: ['notify.partConfirmed.title', 'notify.partConfirmed.body', 'ORDER'],
  PROCESSING: ['notify.partProcessing.title', 'notify.partProcessing.body', 'ORDER'],
  SHIPPED: ['notify.partShipped.title', 'notify.partShipped.body', 'SHIPPING'],
  DELIVERED: ['notify.partDelivered.title', 'notify.partDelivered.body', 'DELIVERY'],
  REFUSED: ['notify.partRefused.title', 'notify.partRefused.body', 'ORDER'],
  CANCELLED: ['notify.partDeclined.title', 'notify.partDeclined.body', 'ORDER'],
}

/** +9647701112222 as "+964 770 111 2222", kept left to right inside Arabic words. */
function phoneWords(phone: string): Record<Lang, string> {
  const shown = phone.replace(/^\+964(\d{3})(\d{3})(\d{4})$/, '+964 $1 $2 $3')
  return { en: shown, ar: `⁦${shown}⁩` }
}

export function storeOrderRoutes(api: Api, ctx: Context): void {
  const { pool } = ctx
  const STORE = ['MERCHANT'] as const
  const TAG = 'Store: orders'

  async function storeOf(db: Pool | Connection, req: Request): Promise<{ id: number; name: string }> {
    const store = await one<{ id: number; store_name: string }>(db, 'SELECT id, store_name FROM stores WHERE owner_user_id = ?', [me(req).id])
    if (!store) throw notFound()
    return { id: store.id, name: store.store_name }
  }

  /** One store's part of an order, as the store's screens read it (MerchantMappers.orderRow, orderDetail). */
  function partJson(req: Request, data: OrderData, part: PartRow): z.infer<typeof StoreOrder> {
    const { lang, url, inLang } = orderWords(req, ctx)
    const { order } = data
    const items = data.items.filter((item) => item.part_id === part.id)
    return {
      id: String(part.id),
      merchantId: String(part.store_id),
      customerOrderId: String(order.id),
      customerId: String(order.customer_id),
      orderNumber: order.order_number,
      placedAt: order.placed_at.toISOString(),
      status: part.status,
      subtotal: part.subtotal,
      discount: part.discount,
      shipping: part.shipping_fee,
      // What its driver collects at the door.
      total: part.amount_due,
      currencyCode: 'IQD',
      itemCount: part.item_count,
      customerName: inLang(order.customer_name, order.customer_name_ar),
      customerArea: inLang(order.ship_area, order.ship_area_ar),
      customerGovernorate: order.ship_governorate,
      customerPhone: order.customer_phone,
      deliveryTime: part.delivery_time,
      shippingAddress: addressJson(req, ctx, order),
      paymentMethodLabel: t(lang, 'payment.cod'),
      previewImageUrl: url(items[0]?.image_url ?? null),
      items: items.map((item) => ({
        id: String(item.id),
        productId: String(item.product_id),
        variantId: item.variant_label === null ? null : String(item.sku_id),
        name: inLang(item.product_name, item.product_name_ar),
        imageUrl: url(item.image_url),
        sku: item.sku_code,
        variantLabel: item.variant_label,
        quantity: item.quantity,
        price: item.unit_price,
        paidUnitPrice: item.paid_unit_price,
      })),
      courierType: part.courier_name === null ? null : 'DRIVER',
      courierName: inLang(part.courier_name, part.courier_name_ar),
      courierPhone: part.courier_phone,
      cancellationReason: part.cancellation_reason,
      received: part.received === null ? null : part.received === 1,
      deliveredAt: part.delivered_at?.toISOString() ?? null,
    }
  }

  /** The store's part [partId] as it reads now. */
  async function reread(db: Pool | Connection, req: Request, orderId: number, partId: number) {
    const [data] = await loadOrders(db, [orderId])
    return partJson(req, data!, data!.parts.find((part) => part.id === partId)!)
  }

  route(api, {
    method: 'get',
    path: '/merchants/me/orders',
    tag: TAG,
    summary: "The store's parts of orders, newest first; status is a comma list",
    who: STORE,
    query: PageQuery.extend({ status: z.string().max(200).optional() }),
    response: z.array(StoreOrder),
    async handle({ req, query }) {
      const store = await storeOf(pool, req)
      const wanted = (query.status ?? '')
        .split(',')
        .map((status) => status.trim().toUpperCase())
        .filter(Boolean)
      const where = `op.store_id = ?${wanted.length > 0 ? ' AND op.status IN (?)' : ''}`
      const params: unknown[] = wanted.length > 0 ? [store.id, wanted] : [store.id]
      const total = await one<{ n: number }>(pool, `SELECT COUNT(*) AS n FROM order_store_parts op WHERE ${where}`, params)
      const found = await rows<{ id: number; order_id: number }>(
        pool,
        `SELECT op.id, op.order_id FROM order_store_parts op JOIN orders o ON o.id = op.order_id
          WHERE ${where} ORDER BY o.placed_at DESC, op.id DESC LIMIT ? OFFSET ?`,
        [...params, query.perPage, (query.page - 1) * query.perPage],
      )
      const orders = new Map((await loadOrders(pool, [...new Set(found.map((row) => row.order_id))])).map((data) => [data.order.id, data]))
      return new Page(
        found.map((row) => {
          const data = orders.get(row.order_id)!
          return partJson(req, data, data.parts.find((part) => part.id === row.id)!)
        }),
        query,
        Number(total?.n ?? 0),
      )
    },
  })

  route(api, {
    method: 'get',
    path: '/merchants/me/orders/counts',
    tag: TAG,
    summary: "How many of the store's parts are at each step",
    who: STORE,
    response: z.record(z.string(), z.number()),
    async handle({ req }) {
      const store = await storeOf(pool, req)
      const found = await rows<{ status: string; n: number }>(
        pool,
        'SELECT status, COUNT(*) AS n FROM order_store_parts WHERE store_id = ? GROUP BY status',
        [store.id],
      )
      return Object.fromEntries(found.map((row) => [row.status, Number(row.n)]))
    },
  })

  route(api, {
    method: 'get',
    path: '/merchants/me/orders/:id',
    tag: TAG,
    summary: "One of the store's parts: its lines, the shopper's name, address and phone, its returns",
    who: STORE,
    params: IdParams,
    response: StoreOrder.extend({ returns: z.array(Return) }),
    async handle({ req, params }) {
      const store = await storeOf(pool, req)
      const part = await one<{ id: number; order_id: number }>(pool, 'SELECT id, order_id FROM order_store_parts WHERE id = ? AND store_id = ?', [
        idOf(params.id),
        store.id,
      ])
      if (!part) throw notFound()
      return { ...(await reread(pool, req, part.order_id, part.id)), returns: await returnsOfPart(pool, req, ctx, part.id) }
    },
  })

  route(api, {
    method: 'patch',
    path: '/merchants/me/orders/:id/status',
    tag: TAG,
    summary: 'Move a part one step (DATABASE_DESIGN.md §5.3); a decline needs its reason, shipping its driver',
    who: STORE,
    params: IdParams,
    body: z.object({
      status: Status,
      reason: z.string().trim().max(40).nullish(),
      courierName: z.string().trim().max(50).nullish(),
      courierPhone: z.string().max(30).nullish(),
    }),
    response: StoreOrder,
    async handle({ req, params, body }) {
      const store = await storeOf(pool, req)
      const actor = me(req).id
      return withTransaction(pool, async (conn) => {
        const found = await one<{ id: number; order_id: number }>(conn, 'SELECT id, order_id FROM order_store_parts WHERE id = ? AND store_id = ?', [
          idOf(params.id),
          store.id,
        ])
        if (!found) throw notFound()
        // The order, then its part (DATABASE_DESIGN.md §5.1).
        const order = await one<{ id: number; customer_id: number; order_number: string }>(
          conn,
          'SELECT id, customer_id, order_number FROM orders WHERE id = ? FOR UPDATE',
          [found.order_id],
        )
        const part = await one<{ id: number; status: PartStatus }>(conn, 'SELECT id, status FROM order_store_parts WHERE id = ? FOR UPDATE', [found.id])
        const next = body.status
        if (!NEXT[part!.status]?.includes(next)) throw new AppError(409, 'CONFLICT_ERROR', 'order.wrongStep')

        let reason: (typeof DECLINE_REASONS)[number] | null = null
        let driver: { name: string; phone: string } | null = null
        switch (next) {
          case 'CONFIRMED':
            await exec(conn, "UPDATE order_store_parts SET status = 'CONFIRMED', confirmed_at = NOW(3) WHERE id = ?", [part!.id])
            break
          case 'PROCESSING':
            await exec(conn, "UPDATE order_store_parts SET status = 'PROCESSING' WHERE id = ?", [part!.id])
            break
          case 'SHIPPED': {
            // The shopper is told who is coming and how to reach them.
            const name = body.courierName ?? ''
            const phone = normalizePhone(body.courierPhone ?? '')
            if (!name) throw fieldError('courierName', 'order.courier')
            if (!phone) throw fieldError('courierPhone', body.courierPhone ? 'field.phone' : 'order.courier')
            driver = { name, phone }
            await exec(
              conn,
              "UPDATE order_store_parts SET status = 'SHIPPED', courier_name = ?, courier_name_ar = NULL, courier_phone = ?, shipped_at = NOW(3) WHERE id = ?",
              [name, phone, part!.id],
            )
            break
          }
          case 'DELIVERED': {
            // On the bill of the month it arrived, on Iraq's calendar.
            const at = new Date()
            await exec(conn, "UPDATE order_store_parts SET status = 'DELIVERED', delivered_at = ?, billing_month = ? WHERE id = ?", [
              at,
              billingMonth(at),
              part!.id,
            ])
            break
          }
          case 'CANCELLED':
            reason = DECLINE_REASONS.find((code) => code === body.reason) ?? null
            if (!reason) throw fieldError('reason', 'order.declineReason')
            await exec(conn, "UPDATE order_store_parts SET status = 'CANCELLED', cancellation_reason = ?, cancelled_at = NOW(3) WHERE id = ?", [
              reason,
              part!.id,
            ])
            await releaseCoupon(conn, order!.id, [part!.id])
            await restock(conn, [part!.id], 'PART_DECLINED', actor)
            break
          case 'REFUSED':
            await exec(conn, "UPDATE order_store_parts SET status = 'REFUSED', cancelled_at = NOW(3) WHERE id = ?", [part!.id])
            await releaseCoupon(conn, order!.id, [part!.id])
            await restock(conn, [part!.id], 'PART_REFUSED', actor)
            break
        }
        await rollUp(conn, order!.id, reason)
        await addStep(conn, order!.id, part!.id, next, { storeName: store.name, reasonCode: reason })

        const [title, text, type] = TOLD[next]!
        const words = {
          store: store.name,
          number: order!.order_number,
          ...(driver && { driver: driver.name, phone: phoneWords(driver.phone) }),
          ...(reason && { reason: { en: t('en', `reason.${reason}` as const), ar: t('ar', `reason.${reason}` as const) } }),
        }
        await notify(
          conn,
          order!.customer_id,
          type,
          {
            en: { title: t('en', title, words), body: t('en', text, words) },
            ar: { title: t('ar', title, words), body: t('ar', text, words) },
          },
          { type: 'ORDER', id: order!.id },
          { push: PUSHED.includes(next) },
        )
        publish(conn, [order!.customer_id, me(req).id, 'ADMINS'], 'orders', order!.id)
        // Delivered goods are this month's sales: Finance changes (W8).
        if (next === 'DELIVERED') publish(conn, 'ADMINS', 'bills')
        return reread(conn, req, order!.id, part!.id)
      })
    },
  })
}

function fieldError(field: string, key: MessageKey): AppError {
  return new AppError(422, 'VALIDATION_ERROR', key, undefined, { [field]: { key } })
}

function idOf(text: string): number {
  if (!/^\d{1,15}$/.test(text)) throw notFound()
  return Number(text)
}

function notFound(): AppError {
  return new AppError(404, 'NOT_FOUND_ERROR', 'error.notFound')
}
