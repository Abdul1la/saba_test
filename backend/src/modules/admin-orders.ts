import type { Request } from 'express'
import { z } from 'zod'
import type { Context } from '../app.js'
import { rows } from '../db/sql.js'
import { AppError } from '../http/errors.js'
import { IdParams } from '../http/inputs.js'
import { route, type Api } from '../http/route.js'
import { GOVERNORATES } from '../lib/governorates.js'
import { urlOf } from '../lib/storage.js'
import { anyOf, cityWhere, likeFolded, ListQuery, pageSql, paged, phoneWhere } from './admin-lists.js'
import { loadOrders, PART_STATUSES, partStoreName, type OrderData } from './orders.js'
import { DELIVERY_TIMES } from './stores.js'

// Saba's view of every order (API_CONTRACT.md §3.6): read-only, both
// languages, every part with its own money and driver (Q7, BACKEND_PLAN.md §6.7).

const Status = z.enum(PART_STATUSES)

export const AdminOrder = z
  .object({
    id: z.string(),
    orderNumber: z.string(),
    placedAt: z.string(),
    deliveredAt: z.string().optional(),
    status: Status,
    paymentStatus: z.enum(['PENDING', 'PAID', 'CANCELLED']),
    isCashOnDelivery: z.literal(true),
    paymentMethodLabel: z.string(),
    paymentMethodType: z.literal('COD'),
    subtotal: z.number(),
    shipping: z.number(),
    discount: z.number(),
    total: z.number(),
    currencyCode: z.literal('IQD'),
    itemCount: z.number(),
    couponCode: z.string().optional(),
    customerId: z.string(),
    customerName: z.string(),
    customerNameAr: z.string().optional(),
    customerPhone: z.string(),
    shippingAddress: z.object({
      fullName: z.string(),
      fullNameAr: z.string().optional(),
      phone: z.string(),
      governorate: z.enum(GOVERNORATES),
      area: z.string(),
      areaAr: z.string().optional(),
      street: z.string().optional(),
      streetAr: z.string().optional(),
      landmark: z.string(),
      landmarkAr: z.string().optional(),
      instructions: z.string().optional(),
    }),
    instructions: z.string().optional(),
    storeParts: z.array(
      z.object({
        merchantId: z.string(),
        merchantName: z.string(),
        amountDue: z.number(),
        status: Status,
        subtotal: z.number(),
        shipping: z.number(),
        discount: z.number(),
        deliveryTime: z.enum(DELIVERY_TIMES),
        courierName: z.string().optional(),
        courierNameAr: z.string().optional(),
        courierPhone: z.string().optional(),
        received: z.boolean().optional(),
        cancellationReason: z.string().optional(),
      }),
    ),
    timeline: z.array(
      z.object({
        status: Status,
        occurredAt: z.string(),
        noteCode: z.string().optional(),
        reasonCode: z.string().optional(),
        note: z.string().optional(),
        storeName: z.string().optional(),
      }),
    ),
    cancelledAt: z.string().optional(),
    cancelledBy: z.enum(['SHOPPER', 'STORE']).optional(),
    cancelReason: z.string().optional(),
    cancelNote: z.string().optional(),
    merchantNames: z.array(z.string()),
    items: z.array(
      z.object({
        id: z.string(),
        productId: z.string(),
        productName: z.string(),
        productNameAr: z.string().optional(),
        imageUrl: z.string().optional(),
        quantity: z.number(),
        unitPrice: z.number(),
        lineTotal: z.number(),
        merchantId: z.string(),
        merchantName: z.string(),
        variantLabel: z.string().optional(),
        sku: z.string().optional(),
      }),
    ),
  })
  .meta({ id: 'AdminOrder' })
export type AdminOrder = z.infer<typeof AdminOrder>

/** A field the contract marks optional: left out when there is nothing, never null. */
export const some = <K extends string, V>(key: K, value: V | null | undefined) =>
  (value === null || value === undefined ? {} : { [key]: value }) as Partial<Record<K, V>>

export function adminOrderOf(req: Request, ctx: Context, data: OrderData): AdminOrder {
  const { order, parts, items, events } = data
  const url = (key: string) => urlOf(req, ctx.config.mediaBaseUrl, key)
  const storeOf = new Map(parts.map((part) => [part.id, part.store_id]))
  return {
    id: String(order.id),
    orderNumber: order.order_number,
    placedAt: order.placed_at.toISOString(),
    ...some('deliveredAt', order.delivered_at?.toISOString()),
    status: order.status,
    paymentStatus: order.payment_status,
    isCashOnDelivery: true,
    paymentMethodLabel: 'Cash on delivery',
    paymentMethodType: 'COD',
    subtotal: order.subtotal,
    shipping: order.shipping,
    discount: order.discount,
    total: order.total,
    currencyCode: 'IQD',
    itemCount: order.item_count,
    ...some('couponCode', order.coupon_code),
    customerId: String(order.customer_id),
    customerName: order.customer_name,
    ...some('customerNameAr', order.customer_name_ar),
    customerPhone: order.customer_phone,
    shippingAddress: {
      fullName: order.customer_name,
      ...some('fullNameAr', order.customer_name_ar),
      phone: order.customer_phone,
      governorate: order.ship_governorate,
      area: order.ship_area,
      ...some('areaAr', order.ship_area_ar),
      ...some('street', order.ship_street),
      ...some('streetAr', order.ship_street_ar),
      landmark: order.ship_landmark,
      ...some('landmarkAr', order.ship_landmark_ar),
      ...some('instructions', order.instructions),
    },
    ...some('instructions', order.instructions),
    storeParts: parts.map((part) => ({
      merchantId: String(part.store_id),
      merchantName: partStoreName(data, part),
      amountDue: part.amount_due,
      status: part.status,
      subtotal: part.subtotal,
      shipping: part.shipping_fee,
      discount: part.discount,
      deliveryTime: part.delivery_time,
      ...some('courierName', part.courier_name),
      ...some('courierNameAr', part.courier_name_ar),
      ...some('courierPhone', part.courier_phone),
      ...some('received', part.received === null ? null : part.received === 1),
      ...some('cancellationReason', part.cancellation_reason),
    })),
    timeline: events.map((event) => ({
      status: event.status,
      occurredAt: event.occurred_at.toISOString(),
      ...some('noteCode', event.note_code),
      ...some('reasonCode', event.reason_code),
      ...some('note', event.note),
      ...some('storeName', event.store_name),
    })),
    ...some('cancelledAt', order.cancelled_at?.toISOString()),
    ...some('cancelledBy', order.cancelled_by),
    ...some('cancelReason', order.cancel_reason),
    ...some('cancelNote', order.cancel_note),
    merchantNames: [...new Set(items.map((item) => item.store_name))],
    items: items.map((item) => ({
      id: String(item.id),
      productId: String(item.product_id),
      productName: item.product_name,
      ...some('productNameAr', item.product_name_ar),
      ...some('imageUrl', item.image_url === null ? null : url(item.image_url)),
      quantity: item.quantity,
      unitPrice: item.unit_price,
      lineTotal: item.line_total,
      merchantId: String(storeOf.get(item.part_id)),
      merchantName: item.store_name,
      ...some('variantLabel', item.variant_label),
      ...some('sku', item.sku_code),
    })),
  }
}

export function adminOrderRoutes(api: Api, ctx: Context): void {
  const { pool } = ctx
  const ADMIN = ['ADMIN'] as const

  route(api, {
    method: 'get',
    path: '/admin/orders',
    tag: 'Admin: orders',
    summary: 'Every order, newest first; status is a comma list; counts per status and all',
    who: ADMIN,
    query: z.object({ status: z.string().max(200).optional(), q: z.string().max(100).optional(), ...ListQuery }),
    response: z.object({ items: z.array(AdminOrder), counts: z.record(z.string(), z.number()) }),
    async handle({ req, query }) {
      // The web's `matches`, in the database: the number, the names, the stores
      // and the products (orders.search_text, folded), the city in either
      // language, the phone however it is typed (contract §1.7, §3.6).
      const q = query.q ?? ''
      const [search, searchParams] = anyOf(q, [
        ['o.search_text LIKE ?', [likeFolded(q)]],
        await cityWhere(pool, 'o.ship_governorate', q),
        phoneWhere('o.customer_phone_digits', q),
      ])
      const counts: Record<string, number> = { all: 0 }
      for (const row of await rows<{ status: string; n: number }>(pool, `SELECT o.status, COUNT(*) AS n FROM orders o WHERE 1 = 1${search} GROUP BY o.status`, searchParams)) {
        counts[row.status] = Number(row.n)
        counts.all! += Number(row.n)
      }
      const wanted = [...new Set((query.status ?? '').split(',').map((status) => status.trim().toUpperCase()).filter(Boolean))]
      const ids = await rows<{ id: number }>(
        pool,
        `SELECT o.id FROM orders o WHERE 1 = 1${search}${wanted.length ? ' AND o.status IN (?)' : ''} ORDER BY o.placed_at DESC, o.id DESC${pageSql(query)}`,
        [...searchParams, ...(wanted.length ? [wanted] : [])],
      )
      const items = (await loadOrders(pool, ids.map((row) => row.id))).map((data) => adminOrderOf(req, ctx, data))
      const total = wanted.length ? wanted.reduce((sum, status) => sum + (counts[status] ?? 0), 0) : counts.all!
      return paged({ items, counts }, query, total)
    },
  })

  route(api, {
    method: 'get',
    path: '/admin/orders/:id',
    tag: 'Admin: orders',
    summary: 'One order, with every step and each store\'s driver',
    who: ADMIN,
    params: IdParams,
    response: AdminOrder,
    async handle({ req, params }) {
      const [data] = await loadOrders(pool, [/^\d{1,15}$/.test(params.id) ? Number(params.id) : 0])
      if (!data) throw new AppError(404, 'NOT_FOUND_ERROR', 'error.notFound')
      return adminOrderOf(req, ctx, data)
    },
  })
}
