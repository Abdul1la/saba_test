import type { Request } from 'express'
import { z } from 'zod'
import type { Context } from '../app.js'
import type { Connection, Pool } from '../db/pool.js'
import { duplicateKey, exec, one, rows } from '../db/sql.js'
import { withTransaction } from '../db/tx.js'
import { me } from '../http/auth.js'
import { AppError } from '../http/errors.js'
import { IdParams, optionalText } from '../http/inputs.js'
import { Page, PageQuery, route, type Api } from '../http/route.js'
import { GOVERNORATES, type Governorate } from '../lib/governorates.js'
import { t, type Lang } from '../lib/i18n.js'
import { publish } from '../lib/events.js'
import { notify } from '../lib/notify.js'
import { urlOf } from '../lib/storage.js'
import { RATING_ASKS, RETURN_WINDOW_DAYS } from '../rules.js'
import { DELIVERY_TIMES } from './stores.js'

// The shopper's orders (BACKEND_PLAN.md §6.4): the list and each order, the
// invoice, cancelling, "did it arrive?", rating the stores, and store reviews.
// Also what the store's and Saba's order routes share: the rows, an order's
// status worked out from its parts, stock going back, the timeline.

export const PART_STATUSES = ['PENDING', 'CONFIRMED', 'PROCESSING', 'SHIPPED', 'DELIVERED', 'CANCELLED', 'REFUSED'] as const
export type PartStatus = (typeof PART_STATUSES)[number]
type DeliveryTime = (typeof DELIVERY_TIMES)[number]

/** A part its store won't deliver: declined or cancelled, or refused at the door. */
export const isOff = (status: PartStatus): boolean => status === 'CANCELLED' || status === 'REFUSED'

/** How far a live part has got; the order is as far as its slowest (the app's `_stage`). */
const STAGE: Record<PartStatus, number> = { PENDING: 0, CONFIRMED: 1, PROCESSING: 2, SHIPPED: 3, DELIVERED: 4, CANCELLED: 5, REFUSED: 5 }

const DAY_MS = 86_400_000

export interface OrderRow {
  id: number
  order_number: string
  customer_id: number
  status: PartStatus
  payment_status: 'PENDING' | 'PAID' | 'CANCELLED'
  subtotal: number
  discount: number
  shipping: number
  total: number
  item_count: number
  coupon_code: string | null
  customer_name: string
  customer_name_ar: string | null
  customer_phone: string
  ship_governorate: Governorate
  ship_area: string
  ship_area_ar: string | null
  ship_street: string | null
  ship_street_ar: string | null
  ship_landmark: string
  ship_landmark_ar: string | null
  instructions: string | null
  placed_at: Date
  delivered_at: Date | null
  cancelled_at: Date | null
  cancelled_by: 'SHOPPER' | 'STORE' | null
  cancel_reason: string | null
  cancel_note: string | null
  rated_at: Date | null
}

export interface PartRow {
  id: number
  order_id: number
  store_id: number
  status: PartStatus
  subtotal: number
  discount: number
  shipping_fee: number
  amount_due: number
  item_count: number
  delivery_time: DeliveryTime
  courier_name: string | null
  courier_name_ar: string | null
  courier_phone: string | null
  cancellation_reason: string | null
  received: number | null
  confirmed_at: Date | null
  shipped_at: Date | null
  delivered_at: Date | null
  cancelled_at: Date | null
}

export interface ItemRow {
  id: number
  order_id: number
  part_id: number
  product_id: number
  sku_id: number
  product_name: string
  product_name_ar: string | null
  variant_label: string | null
  sku_code: string | null
  image_url: string | null
  store_name: string
  unit_price: number
  paid_unit_price: number
  quantity: number
  line_total: number
  /** It has a return already, answered or not (BUGS 160). */
  returned: number
}

export interface EventRow {
  id: number
  order_id: number
  part_id: number | null
  status: PartStatus
  note_code: string | null
  reason_code: string | null
  note: string | null
  store_name: string | null
  occurred_at: Date
}

export interface OrderData {
  order: OrderRow
  parts: PartRow[]
  items: ItemRow[]
  events: EventRow[]
}

const ORDER_COLUMNS = `id, order_number, customer_id, status, payment_status, subtotal, discount, shipping, total, item_count,
  coupon_code, customer_name, customer_name_ar, customer_phone, ship_governorate, ship_area, ship_area_ar, ship_street,
  ship_street_ar, ship_landmark, ship_landmark_ar, instructions, placed_at, delivered_at, cancelled_at, cancelled_by,
  cancel_reason, cancel_note, rated_at`

function groupBy<T>(list: T[], key: (item: T) => number): Map<number, T[]> {
  const groups = new Map<number, T[]>()
  for (const item of list) {
    const id = key(item)
    const group = groups.get(id)
    if (group) group.push(item)
    else groups.set(id, [item])
  }
  return groups
}

/** Orders [ids] with their parts, lines and steps, in the order given; missing ids are left out. */
export async function loadOrders(db: Pool | Connection, ids: number[]): Promise<OrderData[]> {
  if (ids.length === 0) return []
  const orders = await rows<OrderRow>(db, `SELECT ${ORDER_COLUMNS} FROM orders WHERE id IN (?)`, [ids])
  const parts = await rows<PartRow>(
    db,
    `SELECT id, order_id, store_id, status, subtotal, discount, shipping_fee, amount_due, item_count, delivery_time, courier_name,
            courier_name_ar, courier_phone, cancellation_reason, received, confirmed_at, shipped_at, delivered_at, cancelled_at
       FROM order_store_parts WHERE order_id IN (?) ORDER BY id`,
    [ids],
  )
  const items = await rows<ItemRow>(
    db,
    `SELECT oi.id, oi.order_id, oi.part_id, oi.product_id, oi.sku_id, oi.product_name, oi.product_name_ar, oi.variant_label,
            oi.sku_code, oi.image_url, oi.store_name, oi.unit_price, oi.paid_unit_price, oi.quantity, oi.line_total,
            EXISTS (SELECT 1 FROM return_items ri WHERE ri.order_item_id = oi.id) AS returned
       FROM order_items oi WHERE oi.order_id IN (?) ORDER BY oi.id`,
    [ids],
  )
  const events = await rows<EventRow>(
    db,
    `SELECT id, order_id, part_id, status, note_code, reason_code, note, store_name, occurred_at
       FROM order_events WHERE order_id IN (?) ORDER BY occurred_at, id`,
    [ids],
  )
  const byId = new Map(orders.map((order) => [order.id, order]))
  const partsOf = groupBy(parts, (part) => part.order_id)
  const itemsOf = groupBy(items, (item) => item.order_id)
  const eventsOf = groupBy(events, (event) => event.order_id)
  return ids.flatMap((id) => {
    const order = byId.get(id)
    if (!order) return []
    return [{ order, parts: partsOf.get(id) ?? [], items: itemsOf.get(id) ?? [], events: eventsOf.get(id) ?? [] }]
  })
}

// ------------------------------------------------------------ what changes ---

/**
 * The order as far as its slowest live part (the app's `_storeMoved`): a part
 * declined or refused is left out and the others decide. Paid once every live
 * part is delivered (cash at the door); nothing to pay when none is coming.
 * An order the stores called off is marked theirs, with [storeReason].
 */
export async function rollUp(conn: Connection, orderId: number, storeReason: string | null = null): Promise<void> {
  const parts = await rows<{ status: PartStatus; delivered_at: Date | null }>(
    conn,
    'SELECT status, delivered_at FROM order_store_parts WHERE order_id = ?',
    [orderId],
  )
  const live = parts.filter((part) => !isOff(part.status))
  let status: PartStatus
  let payment: 'PENDING' | 'PAID' | 'CANCELLED'
  let deliveredAt: Date | null = null
  if (live.length === 0) {
    status = parts.every((part) => part.status === 'REFUSED') ? 'REFUSED' : 'CANCELLED'
    payment = 'CANCELLED'
  } else {
    status = live.reduce((slowest, part) => (STAGE[part.status] < STAGE[slowest] ? part.status : slowest), live[0]!.status)
    payment = live.every((part) => part.status === 'DELIVERED') ? 'PAID' : 'PENDING'
    // When the last live part arrived.
    if (status === 'DELIVERED') deliveredAt = new Date(Math.max(...live.map((part) => part.delivered_at!.getTime())))
  }
  // MySQL sets these left to right, so cancelled_at is tested before it is set.
  await exec(
    conn,
    `UPDATE orders SET status = ?, payment_status = ?, delivered_at = ?,
            cancelled_by = IF(? = 'CANCELLED' AND cancelled_at IS NULL, 'STORE', cancelled_by),
            cancel_reason = IF(? = 'CANCELLED' AND cancelled_at IS NULL, ?, cancel_reason),
            cancelled_at = IF(? = 'CANCELLED' AND cancelled_at IS NULL, NOW(3), cancelled_at)
      WHERE id = ?`,
    [status, payment, deliveredAt, status, status, storeReason, status, orderId],
  )
}

/**
 * A code's use comes back when the store part it took money off ends without
 * a sale: declined, cancelled or refused at the door (the reviewer's item 10).
 * Called as [partIds] turn, which each part does once, so it comes back once.
 * Called before restock: checkout locks the code, then the stock, and a
 * call-off taking them the other way round can deadlock with it.
 */
export async function releaseCoupon(conn: Connection, orderId: number, partIds: number[]): Promise<void> {
  if (partIds.length === 0) return
  await exec(
    conn,
    `UPDATE coupons c JOIN orders o ON o.coupon_id = c.id JOIN order_store_parts p ON p.order_id = o.id AND p.store_id = c.store_id
        SET c.used_count = c.used_count - 1
      WHERE o.id = ? AND p.id IN (?)`,
    [orderId, partIds],
  )
}

/** [lines] go back on the shelf, each with its ledger row; options locked in id order. */
export async function putBack(
  conn: Connection,
  lines: { part_id: number; sku_id: number; quantity: number }[],
  reason: 'ORDER_CANCELLED' | 'PART_DECLINED' | 'PART_REFUSED' | 'RETURN_REFUNDED',
  actor: number,
  returnId: number | null = null,
): Promise<void> {
  if (lines.length === 0) return
  await rows(conn, 'SELECT id FROM product_skus WHERE id IN (?) ORDER BY id FOR UPDATE', [[...new Set(lines.map((line) => line.sku_id))]])
  for (const line of lines) {
    await exec(conn, 'UPDATE product_skus SET stock = stock + ? WHERE id = ?', [line.quantity, line.sku_id])
    await exec(conn, 'INSERT INTO stock_movements (sku_id, delta, reason, part_id, return_id, actor_user_id) VALUES (?, ?, ?, ?, ?, ?)', [
      line.sku_id,
      line.quantity,
      reason,
      line.part_id,
      returnId,
      actor,
    ])
  }
}

/** Everything parts [partIds] held goes back on the shelf. */
export async function restock(
  conn: Connection,
  partIds: number[],
  reason: 'ORDER_CANCELLED' | 'PART_DECLINED' | 'PART_REFUSED',
  actor: number,
): Promise<void> {
  if (partIds.length === 0) return
  const items = await rows<{ part_id: number; sku_id: number; quantity: number }>(
    conn,
    'SELECT part_id, sku_id, quantity FROM order_items WHERE part_id IN (?) ORDER BY sku_id, id',
    [partIds],
  )
  await putBack(conn, items, reason, actor)
}

/** A step of the order's timeline: codes, never sentences (BUGS 51). */
export async function addStep(
  conn: Connection,
  orderId: number,
  partId: number | null,
  status: PartStatus,
  extra: { noteCode?: string; reasonCode?: string | null; note?: string | null; storeName?: string } = {},
): Promise<void> {
  await exec(
    conn,
    'INSERT INTO order_events (order_id, part_id, status, note_code, reason_code, note, store_name, occurred_at) VALUES (?, ?, ?, ?, ?, ?, ?, NOW(3))',
    [orderId, partId, status, extra.noteCode ?? null, extra.reasonCode ?? null, extra.note ?? null, extra.storeName ?? null],
  )
}

/** A name in both languages, for a message: the Arabic twin when there is one. */
export const bothNames = (text: string, arabic: string | null): Record<Lang, string> => ({ en: text, ar: arabic ?? text })

// ------------------------------------------------------------------ shapes ---

const Status = z.enum(PART_STATUSES)

const OrderAddress = z.object({
  fullName: z.string(),
  phone: z.string(),
  governorate: z.enum(GOVERNORATES),
  area: z.string(),
  street: z.string().nullable(),
  landmark: z.string(),
  instructions: z.string().nullable(),
})

const Step = z.object({
  status: Status,
  occurredAt: z.string(),
  noteCode: z.string().nullable(),
  reasonCode: z.string().nullable(),
  note: z.string().nullable(),
  storeName: z.string().nullable(),
})

export const Order = z
  .object({
    id: z.string(),
    orderNumber: z.string(),
    customerId: z.string(),
    placedAt: z.string(),
    deliveredAt: z.string().nullable(),
    status: Status,
    paymentStatus: z.enum(['PENDING', 'PAID', 'CANCELLED']),
    items: z.array(
      z.object({
        id: z.string(),
        productId: z.string(),
        variantId: z.string().nullable(),
        productName: z.string(),
        productNameAr: z.string().nullable(),
        sku: z.string().nullable(),
        variantLabel: z.string().nullable(),
        imageUrl: z.string().nullable(),
        merchantId: z.string(),
        merchantName: z.string(),
        unitPrice: z.number(),
        paidUnitPrice: z.number(),
        quantity: z.number(),
        lineTotal: z.number(),
        currencyCode: z.literal('IQD'),
        // Its part's, as the app reads them (D9).
        status: Status,
        deliveredAt: z.string().nullable(),
        canReturn: z.boolean(),
      }),
    ),
    itemCount: z.number(),
    subtotal: z.number(),
    discount: z.number(),
    shipping: z.number(),
    total: z.number(),
    currencyCode: z.literal('IQD'),
    couponCode: z.string().nullable(),
    storeParts: z.array(
      z.object({
        merchantId: z.string(),
        merchantName: z.string(),
        status: Status,
        subtotal: z.number(),
        discount: z.number(),
        shipping: z.number(),
        amountDue: z.number(),
        deliveryTime: z.enum(DELIVERY_TIMES),
        courierName: z.string().nullable(),
        courierPhone: z.string().nullable(),
        received: z.boolean().nullable(),
        cancellationReason: z.string().nullable(),
      }),
    ),
    previewImageUrl: z.string().nullable(),
    merchantNames: z.array(z.string()),
    shippingAddress: OrderAddress,
    paymentMethodLabel: z.string(),
    paymentMethodType: z.literal('COD'),
    estimatedDelivery: z.string(),
    canCancel: z.boolean(),
    canReturn: z.boolean(),
    timeline: z.array(Step),
    cancelledAt: z.string().nullable(),
    cancelReason: z.string().nullable(),
    cancelNote: z.string().nullable(),
  })
  .meta({ id: 'Order' })
export type Order = z.infer<typeof Order>

/** The store's name on a part: the one its lines were sold under. */
export const partStoreName = (data: OrderData, part: PartRow): string =>
  data.items.find((item) => item.part_id === part.id)?.store_name ?? ''

/** Can this line still go back: its part delivered within the window, and no return yet. */
export function returnable(part: PartRow, item: ItemRow, now: Date): boolean {
  return (
    part.status === 'DELIVERED' &&
    part.delivered_at !== null &&
    now.getTime() - part.delivered_at.getTime() <= RETURN_WINDOW_DAYS * DAY_MS &&
    item.returned !== 1
  )
}

/** The words of one request: its language, and full addresses for stored photos. */
export function orderWords(req: Request, ctx: Context) {
  const lang: Lang = req.lang
  return {
    lang,
    url: (key: string | null) => (key === null ? null : urlOf(req, ctx.config.mediaBaseUrl, key)),
    inLang: <T extends string | null>(text: T, arabic: string | null): T => (lang === 'ar' && arabic ? (arabic as T) : text),
  }
}

export function addressJson(req: Request, ctx: Context, order: OrderRow): z.infer<typeof OrderAddress> {
  const { inLang } = orderWords(req, ctx)
  return {
    fullName: inLang(order.customer_name, order.customer_name_ar),
    phone: order.customer_phone,
    governorate: order.ship_governorate,
    area: inLang(order.ship_area, order.ship_area_ar),
    street: inLang(order.ship_street, order.ship_street_ar),
    landmark: inLang(order.ship_landmark, order.ship_landmark_ar),
    instructions: order.instructions,
  }
}

/** The shopper's order as the app reads it (orders_repository_impl.dart, OrderMappers.order). */
export function orderJson(req: Request, ctx: Context, data: OrderData, now = new Date()): Order {
  const { lang, url, inLang } = orderWords(req, ctx)
  const { order, parts, items, events } = data
  const partOf = new Map(parts.map((part) => [part.id, part]))
  const live = parts.filter((part) => !isOff(part.status))
  const lines = items.map((item) => {
    const part = partOf.get(item.part_id)!
    return {
      id: String(item.id),
      productId: String(item.product_id),
      variantId: item.variant_label === null ? null : String(item.sku_id),
      productName: inLang(item.product_name, item.product_name_ar),
      productNameAr: item.product_name_ar,
      sku: item.sku_code,
      variantLabel: item.variant_label,
      imageUrl: url(item.image_url),
      merchantId: String(part.store_id),
      merchantName: item.store_name,
      unitPrice: item.unit_price,
      paidUnitPrice: item.paid_unit_price,
      quantity: item.quantity,
      lineTotal: item.line_total,
      currencyCode: 'IQD' as const,
      status: part.status,
      deliveredAt: part.delivered_at?.toISOString() ?? null,
      canReturn: returnable(part, item, now),
    }
  })
  // The slowest store's time: when the whole order will have come.
  const slowest = parts.reduce<DeliveryTime | null>(
    (time, part) => (time === null || DELIVERY_TIMES.indexOf(part.delivery_time) > DELIVERY_TIMES.indexOf(time) ? part.delivery_time : time),
    null,
  )
  return {
    id: String(order.id),
    orderNumber: order.order_number,
    customerId: String(order.customer_id),
    placedAt: order.placed_at.toISOString(),
    deliveredAt: order.delivered_at?.toISOString() ?? null,
    status: order.status,
    paymentStatus: order.payment_status,
    items: lines,
    itemCount: order.item_count,
    subtotal: order.subtotal,
    discount: order.discount,
    shipping: order.shipping,
    total: order.total,
    currencyCode: 'IQD',
    couponCode: order.coupon_code,
    storeParts: parts.map((part) => ({
      merchantId: String(part.store_id),
      merchantName: partStoreName(data, part),
      status: part.status,
      subtotal: part.subtotal,
      discount: part.discount,
      shipping: part.shipping_fee,
      amountDue: part.amount_due,
      deliveryTime: part.delivery_time,
      courierName: inLang(part.courier_name, part.courier_name_ar),
      courierPhone: part.courier_phone,
      received: part.received === null ? null : part.received === 1,
      cancellationReason: part.cancellation_reason,
    })),
    previewImageUrl: url(items[0]?.image_url ?? null),
    merchantNames: [...new Set(items.map((item) => item.store_name))],
    shippingAddress: addressJson(req, ctx, order),
    paymentMethodLabel: t(lang, 'payment.cod'),
    paymentMethodType: 'COD',
    estimatedDelivery: slowest === null ? '' : t(lang, `delivery.${slowest}` as const),
    canCancel: live.length > 0 && live.every((part) => STAGE[part.status] <= STAGE.CONFIRMED),
    canReturn: lines.some((line) => line.canReturn),
    timeline: events.map((event) => ({
      status: event.status,
      occurredAt: event.occurred_at.toISOString(),
      noteCode: event.note_code,
      reasonCode: event.reason_code,
      note: event.note,
      storeName: event.store_name,
    })),
    cancelledAt: order.cancelled_at?.toISOString() ?? null,
    cancelReason: order.cancel_reason,
    cancelNote: order.cancel_note,
  }
}

const Invoice = z
  .object({
    orderId: z.string(),
    orderNumber: z.string(),
    invoiceNumber: z.string(),
    issuedAt: z.string(),
    lines: z.array(
      z.object({
        description: z.string(),
        descriptionAr: z.string().nullable(),
        merchantName: z.string(),
        quantity: z.number(),
        unitPrice: z.number(),
        total: z.number(),
      }),
    ),
    subtotal: z.number(),
    discount: z.number(),
    shipping: z.number(),
    total: z.number(),
    currencyCode: z.literal('IQD'),
    paymentMethodLabel: z.string(),
    paymentStatus: z.enum(['PENDING', 'PAID', 'CANCELLED']),
    billedTo: OrderAddress,
    sellerName: z.string().nullable(),
  })
  .meta({ id: 'Invoice' })

const Review = z
  .object({
    id: z.string(),
    rating: z.number(),
    title: z.null(),
    body: z.string().nullable(),
    authorName: z.string().nullable(),
    createdAt: z.string(),
    isVerifiedPurchase: z.literal(true),
    photos: z.array(z.string()),
  })
  .meta({ id: 'StoreReview' })

/** "Amina S.": a reviewer's first name and the first letter of the last, on a public page. */
export function shortName(fullName: string): string | null {
  const words = fullName.trim().split(/\s+/).filter(Boolean)
  if (words.length === 0) return null
  return words.length === 1 ? words[0]! : `${words[0]} ${[...words.at(-1)!][0]}.`
}

// ------------------------------------------------------------------ routes ---

const CANCEL_REASONS = ['CHANGED_MIND', 'FOUND_CHEAPER', 'DELIVERY_TOO_SLOW', 'ORDERED_BY_MISTAKE', 'OTHER'] as const
export const REPORT_REASONS = ['COUNTERFEIT', 'PROHIBITED', 'MISLEADING', 'OFFENSIVE', 'SPAM', 'OTHER'] as const

export function orderRoutes(api: Api, ctx: Context): void {
  const { pool } = ctx
  const SHOPPER = ['CUSTOMER'] as const
  const TAG = 'Orders'

  /** The shopper's own order [idText]; another's is not found (BACKEND_PLAN.md §5.2). */
  async function own(db: Pool | Connection, req: Request, idText: string, lock = false): Promise<OrderRow> {
    const order = await one<OrderRow>(
      db,
      `SELECT ${ORDER_COLUMNS} FROM orders WHERE id = ? AND customer_id = ?${lock ? ' FOR UPDATE' : ''}`,
      [/^\d{1,15}$/.test(idText) ? Number(idText) : 0, me(req).id],
    )
    if (!order) throw new AppError(404, 'NOT_FOUND_ERROR', 'order.notFound')
    return order
  }

  const reread = async (db: Pool | Connection, req: Request, orderId: number) =>
    orderJson(req, ctx, (await loadOrders(db, [orderId]))[0]!)

  route(api, {
    method: 'get',
    path: '/orders',
    tag: TAG,
    summary: "The shopper's orders, newest first; each with its stores' parts",
    who: SHOPPER,
    query: PageQuery.extend({ status: z.string().max(20).optional() }),
    response: z.array(Order),
    async handle({ req, query }) {
      const where = ['customer_id = ?']
      const params: unknown[] = [me(req).id]
      if (query.status) {
        where.push('status = ?')
        params.push(query.status.toUpperCase())
      }
      const total = await one<{ n: number }>(pool, `SELECT COUNT(*) AS n FROM orders WHERE ${where.join(' AND ')}`, params)
      const ids = await rows<{ id: number }>(
        pool,
        `SELECT id FROM orders WHERE ${where.join(' AND ')} ORDER BY placed_at DESC, id DESC LIMIT ? OFFSET ?`,
        [...params, query.perPage, (query.page - 1) * query.perPage],
      )
      const found = await loadOrders(
        pool,
        ids.map((row) => row.id),
      )
      const now = new Date()
      return new Page(
        found.map((data) => orderJson(req, ctx, data, now)),
        query,
        Number(total?.n ?? 0),
      )
    },
  })

  route(api, {
    method: 'get',
    path: '/orders/rating-due',
    tag: TAG,
    summary: 'The oldest delivered order still to answer, with its stores; {} when none',
    who: SHOPPER,
    response: z.object({
      orderId: z.string().optional(),
      orderNumber: z.string().optional(),
      stores: z.array(z.object({ id: z.string(), storeName: z.string() })).optional(),
    }),
    async handle({ req }) {
      const order = await one<{ id: number; order_number: string }>(
        pool,
        `SELECT o.id, o.order_number FROM orders o
          WHERE o.customer_id = ? AND o.rated_at IS NULL AND o.rating_skips < ?
            AND EXISTS (SELECT 1 FROM order_store_parts op WHERE op.order_id = o.id AND op.status = 'DELIVERED' AND op.received IS NULL)
          ORDER BY o.placed_at, o.id LIMIT 1`,
        [me(req).id, RATING_ASKS],
      )
      if (!order) return {}
      const stores = await rows<{ store_id: number; store_name: string }>(
        pool,
        `SELECT op.store_id, s.store_name FROM order_store_parts op JOIN stores s ON s.id = op.store_id
          WHERE op.order_id = ? AND op.status = 'DELIVERED' AND op.received IS NULL ORDER BY op.id`,
        [order.id],
      )
      return {
        orderId: String(order.id),
        orderNumber: order.order_number,
        stores: stores.map((store) => ({ id: String(store.store_id), storeName: store.store_name })),
      }
    },
  })

  route(api, {
    method: 'get',
    path: '/orders/:id',
    tag: TAG,
    summary: 'One of the shopper\'s orders: canCancel, canReturn per line, the timeline',
    who: SHOPPER,
    params: IdParams,
    response: Order,
    async handle({ req, params }) {
      return reread(pool, req, (await own(pool, req, params.id)).id)
    },
  })

  route(api, {
    method: 'get',
    path: '/orders/:id/invoice',
    tag: TAG,
    summary: "The invoice, from the order's own figures: never worked out again",
    who: SHOPPER,
    params: IdParams,
    response: Invoice,
    async handle({ req, params }) {
      const [data] = await loadOrders(pool, [(await own(pool, req, params.id)).id])
      const order = orderJson(req, ctx, data!)
      return {
        orderId: order.id,
        orderNumber: order.orderNumber,
        invoiceNumber: `INV-${order.orderNumber}`,
        issuedAt: order.placedAt,
        lines: order.items.map((item) => ({
          description: item.productName,
          descriptionAr: item.productNameAr,
          merchantName: item.merchantName,
          quantity: item.quantity,
          unitPrice: item.unitPrice,
          total: item.lineTotal,
        })),
        subtotal: order.subtotal,
        discount: order.discount,
        shipping: order.shipping,
        total: order.total,
        currencyCode: 'IQD' as const,
        paymentMethodLabel: order.paymentMethodLabel,
        paymentStatus: order.paymentStatus,
        billedTo: order.shippingAddress,
        // One seller only when there is one (BUGS 165).
        sellerName: order.merchantNames.length === 1 ? order.merchantNames[0]! : null,
      }
    },
  })

  route(api, {
    method: 'post',
    path: '/orders/:id/cancel',
    tag: TAG,
    summary: 'Cancel: only while no store is past Confirmed. Stock goes back; each store is told',
    who: SHOPPER,
    params: IdParams,
    body: z.object({ reason: z.enum(CANCEL_REASONS, { error: 'order.chooseReason' }), note: optionalText(500) }),
    response: Order,
    async handle({ req, params, body }) {
      const userId = me(req).id
      return withTransaction(pool, async (conn) => {
        const order = await own(conn, req, params.id, true)
        const parts = await rows<{ id: number; store_id: number; status: PartStatus }>(
          conn,
          'SELECT id, store_id, status FROM order_store_parts WHERE order_id = ? ORDER BY id FOR UPDATE',
          [order.id],
        )
        const live = parts.filter((part) => !isOff(part.status))
        if (live.length === 0 || live.some((part) => STAGE[part.status] > STAGE.CONFIRMED)) {
          throw new AppError(409, 'CONFLICT_ERROR', 'order.cantCancel')
        }
        const liveIds = live.map((part) => part.id)
        await exec(
          conn,
          "UPDATE order_store_parts SET status = 'CANCELLED', cancellation_reason = 'CUSTOMER_CANCELLED', cancelled_at = NOW(3) WHERE id IN (?)",
          [liveIds],
        )
        await releaseCoupon(conn, order.id, liveIds)
        await restock(conn, liveIds, 'ORDER_CANCELLED', userId)
        await exec(conn, "UPDATE orders SET cancelled_at = NOW(3), cancelled_by = 'SHOPPER', cancel_reason = ?, cancel_note = ? WHERE id = ?", [
          body.reason,
          body.note,
          order.id,
        ])
        await rollUp(conn, order.id)
        await addStep(conn, order.id, null, 'CANCELLED', { reasonCode: body.reason, note: body.note })
        const owners = await rows<{ id: number; owner_user_id: number }>(conn, 'SELECT id, owner_user_id FROM stores WHERE id IN (?)', [
          live.map((part) => part.store_id),
        ])
        for (const part of live) {
          const words = { number: order.order_number, customer: bothNames(order.customer_name, order.customer_name_ar) }
          await notify(
            conn,
            owners.find((owner) => owner.id === part.store_id)!.owner_user_id,
            'ORDER',
            {
              en: { title: t('en', 'notify.orderCancelled.title', words), body: t('en', 'notify.orderCancelled.body', words) },
              ar: { title: t('ar', 'notify.orderCancelled.title', words), body: t('ar', 'notify.orderCancelled.body', words) },
            },
            { type: 'STORE_ORDER', id: part.id },
            { push: true },
          )
        }
        publish(conn, [userId, ...owners.map((owner) => owner.owner_user_id), 'ADMINS'], 'orders', order.id)
        return reread(conn, req, order.id)
      })
    },
  })

  /** Tells [storeId]'s owner that the shopper says its parcel never came. */
  async function tellNotReceived(conn: Connection, order: OrderRow, storeId: number, partId: number): Promise<void> {
    const owner = await one<{ owner_user_id: number }>(conn, 'SELECT owner_user_id FROM stores WHERE id = ?', [storeId])
    const words = { number: order.order_number, customer: bothNames(order.customer_name, order.customer_name_ar) }
    await notify(
      conn,
      owner!.owner_user_id,
      'ORDER',
      {
        en: { title: t('en', 'notify.notReceived.title', words), body: t('en', 'notify.notReceived.body', words) },
        ar: { title: t('ar', 'notify.notReceived.title', words), body: t('ar', 'notify.notReceived.body', words) },
      },
      { type: 'STORE_ORDER', id: partId },
      { push: true },
    )
    publish(conn, owner!.owner_user_id, 'orders', partId)
  }

  route(api, {
    method: 'post',
    path: '/orders/:id/received',
    tag: TAG,
    summary: '"Did you receive it?" for one store\'s delivered part; a no tells the store',
    who: SHOPPER,
    params: IdParams,
    body: z.object({ merchantId: z.string(), received: z.boolean() }),
    response: Order,
    async handle({ req, params, body }) {
      return withTransaction(pool, async (conn) => {
        const order = await own(conn, req, params.id)
        const part = await one<{ id: number; store_id: number; status: PartStatus }>(
          conn,
          'SELECT id, store_id, status FROM order_store_parts WHERE order_id = ? AND store_id = ? FOR UPDATE',
          [order.id, /^\d{1,15}$/.test(body.merchantId) ? Number(body.merchantId) : 0],
        )
        if (!part) throw new AppError(404, 'NOT_FOUND_ERROR', 'error.notFound')
        if (part.status !== 'DELIVERED') throw new AppError(409, 'CONFLICT_ERROR', 'order.notDelivered')
        await exec(conn, 'UPDATE order_store_parts SET received = ? WHERE id = ?', [body.received, part.id])
        if (!body.received) await tellNotReceived(conn, order, part.store_id, part.id)
        return reread(conn, req, order.id)
      })
    },
  })

  route(api, {
    method: 'post',
    path: '/orders/:id/rating',
    tag: TAG,
    summary: 'The rating sheet: stars per delivered store (one each), one comment; or "not received"',
    who: SHOPPER,
    params: IdParams,
    body: z.object({
      received: z.boolean().default(true),
      ratings: z.record(z.string(), z.number().int().min(1).max(5)).optional(),
      comment: optionalText(1000),
    }),
    response: Order,
    async handle({ req, params, body }) {
      const userId = me(req).id
      return withTransaction(pool, async (conn) => {
        const order = await own(conn, req, params.id)
        const delivered = await rows<{ id: number; store_id: number }>(
          conn,
          "SELECT id, store_id FROM order_store_parts WHERE order_id = ? AND status = 'DELIVERED' ORDER BY id",
          [order.id],
        )
        if (delivered.length === 0) throw new AppError(409, 'CONFLICT_ERROR', 'order.notDelivered')

        if (!body.received) {
          const unanswered = await rows<{ id: number; store_id: number }>(
            conn,
            "SELECT id, store_id FROM order_store_parts WHERE order_id = ? AND status = 'DELIVERED' AND received IS NULL",
            [order.id],
          )
          await exec(conn, "UPDATE order_store_parts SET received = 0 WHERE order_id = ? AND status = 'DELIVERED' AND received IS NULL", [
            order.id,
          ])
          await exec(conn, 'UPDATE orders SET rated_at = COALESCE(rated_at, NOW(3)) WHERE id = ?', [order.id])
          for (const part of unanswered) await tellNotReceived(conn, order, part.store_id, part.id)
          return reread(conn, req, order.id)
        }

        const stars = Object.entries(body.ratings ?? {})
          .map(([storeId, rating]) => ({ storeId: /^\d{1,15}$/.test(storeId) ? Number(storeId) : 0, rating }))
          .sort((a, b) => a.storeId - b.storeId)
        for (const { storeId } of stars) {
          if (!delivered.some((part) => part.store_id === storeId)) {
            throw new AppError(422, 'VALIDATION_ERROR', 'order.notInOrder', undefined, { ratings: { key: 'order.notInOrder' } })
          }
        }
        // The stores first, then the order, as the lock order says (DATABASE_DESIGN.md §5.1).
        for (const { storeId, rating } of stars) {
          await exec(conn, 'UPDATE stores SET rating_sum = rating_sum + ?, rating_count = rating_count + 1 WHERE id = ?', [rating, storeId])
        }
        await exec(conn, 'UPDATE orders SET rated_at = COALESCE(rated_at, NOW(3)) WHERE id = ?', [order.id])
        // "Yes, it arrived" is for the whole order, stars or not (BUGS 147).
        await exec(conn, "UPDATE order_store_parts SET received = 1 WHERE order_id = ? AND status = 'DELIVERED' AND received IS NULL", [order.id])
        for (const { storeId, rating } of stars) {
          try {
            await exec(conn, 'INSERT INTO store_reviews (store_id, order_id, customer_id, rating, body) VALUES (?, ?, ?, ?, ?)', [
              storeId,
              order.id,
              userId,
              rating,
              body.comment,
            ])
          } catch (error) {
            if (duplicateKey(error) === 'uq_store_reviews_order_store') throw new AppError(409, 'CONFLICT_ERROR', 'order.alreadyRated')
            throw error
          }
        }
        return reread(conn, req, order.id)
      })
    },
  })

  route(api, {
    method: 'post',
    path: '/orders/:id/rating-skipped',
    tag: TAG,
    summary: '"Not now": asked again, three times in all',
    who: SHOPPER,
    params: IdParams,
    response: z.object({}),
    async handle({ req, params }) {
      const order = await own(pool, req, params.id)
      await exec(pool, 'UPDATE orders SET rating_skips = LEAST(rating_skips + 1, 255) WHERE id = ?', [order.id])
      return {}
    },
  })

  route(api, {
    method: 'get',
    path: '/merchants/:id/reviews',
    tag: 'Stores',
    summary: "A store's reviews, newest first",
    who: 'public',
    params: IdParams,
    query: PageQuery,
    response: z.array(Review),
    async handle({ params, query }) {
      const storeId = /^\d{1,15}$/.test(params.id) ? Number(params.id) : 0
      // A review Saba removed is gone from the store's page, as from its rating.
      const total = await one<{ n: number }>(pool, 'SELECT COUNT(*) AS n FROM store_reviews WHERE store_id = ? AND removed_at IS NULL', [storeId])
      const found = await rows<{ id: number; rating: number; body: string | null; created_at: Date; full_name: string }>(
        pool,
        `SELECT r.id, r.rating, r.body, r.created_at, u.full_name FROM store_reviews r JOIN users u ON u.id = r.customer_id
          WHERE r.store_id = ? AND r.removed_at IS NULL ORDER BY r.created_at DESC, r.id DESC LIMIT ? OFFSET ?`,
        [storeId, query.perPage, (query.page - 1) * query.perPage],
      )
      return new Page(
        found.map((review) => ({
          id: String(review.id),
          rating: review.rating,
          title: null,
          body: review.body,
          authorName: shortName(review.full_name),
          createdAt: review.created_at.toISOString(),
          // Every review is of a delivered order.
          isVerifiedPurchase: true as const,
          photos: [],
        })),
        query,
        Number(total?.n ?? 0),
      )
    },
  })

  route(api, {
    method: 'post',
    path: '/reviews/:id/report',
    tag: 'Stores',
    summary:
      'Report a store review, with the reporter\'s words: a shopper, or a store (a review about itself too); once per person while open, reopened when sent again after Saba closed it',
    who: ['CUSTOMER', 'MERCHANT'],
    params: IdParams,
    body: z.object({ reason: z.enum(REPORT_REASONS, { error: 'field.invalid' }), description: optionalText(500) }),
    response: z.object({}),
    async handle({ req, params, body }) {
      const review = await one<{ id: number }>(pool, 'SELECT id FROM store_reviews WHERE id = ? AND removed_at IS NULL', [
        /^\d{1,15}$/.test(params.id) ? Number(params.id) : 0,
      ])
      if (!review) throw new AppError(404, 'NOT_FOUND_ERROR', 'error.notFound')
      // Sent again while open: kept as it was. After Saba closed it: open again, with the new words
      // (the final review's item 3). MySQL sets these left to right, so status is set last.
      const added = await exec(
        pool,
        `INSERT INTO review_reports (review_id, reporter_user_id, reason, description) VALUES (?, ?, ?, ?) AS sent
         ON DUPLICATE KEY UPDATE
           reason = IF(review_reports.status = 'OPEN', review_reports.reason, sent.reason),
           description = IF(review_reports.status = 'OPEN', review_reports.description, sent.description),
           created_at = IF(review_reports.status = 'OPEN', review_reports.created_at, NOW(3)),
           handled_at = NULL, handled_by = NULL, status = 'OPEN'`,
        [review.id, me(req).id, body.reason, body.description],
      )
      if (added.affectedRows > 0) publish(pool, 'ADMINS', 'reviews', review.id)
      return {}
    },
  })
}
