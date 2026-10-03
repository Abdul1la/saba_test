import { http, httpPage, USE_MOCK } from './http'
import { ApiError, pageOf, reply } from './mock'
import { allOrders } from './orders'
import type { AdminOrder, OrderItem, PageAsk, Paged } from './types'

// A shopper's return, as the app keeps it (features/returns and
// MockApiInterceptor's return requests): one store's items at a time, asked
// for within 7 days of delivery, and refunded in cash by the store when it
// collects them. The order itself stays DELIVERED.

/** `ReturnReason`. */
export type ReturnReason = 'DAMAGED' | 'WRONG_ITEM' | 'NOT_AS_DESCRIBED' | 'MISSING_PARTS' | 'CHANGED_MIND' | 'OTHER'

/** The steps the app's return requests take. */
export type ReturnStatus = 'REQUESTED' | 'APPROVED' | 'REJECTED' | 'REFUNDED'

export interface AdminReturn {
  id: string
  orderId: string
  orderNumber: string
  status: ReturnStatus
  requestedAt: string
  reason: ReturnReason
  merchantId: string
  merchantName: string
  customerName: string
  items: Pick<OrderItem, 'productName' | 'productNameAr' | 'imageUrl' | 'quantity' | 'unitPrice'>[]
  refundAmount: number
  /** When the store approved or declined it. */
  answeredAt?: string
  /** When the store handed the cash back; set only once REFUNDED. */
  refundedAt?: string
  /** The server's (D19): the shopper's own words, their photos, and why the store declined. */
  description?: string
  photos?: string[]
  rejectionReason?: 'USED' | 'INCOMPLETE' | 'NOT_AS_SAID' | 'OTHER'
}

const REASONS: ReturnReason[] = ['DAMAGED', 'WRONG_ITEM', 'NOT_AS_DESCRIBED', 'MISSING_PARTS', 'CHANGED_MIND', 'OTHER']
const DAY = 86_400_000

/**
 * web-only demo: a return on every ninth delivered order. Most are long
 * refunded; the newest are still being answered, and one was declined.
 */
function seedReturns(): AdminReturn[] {
  const delivered = allOrders()
    .filter((o): o is AdminOrder & { deliveredAt: string } => o.status === 'DELIVERED' && !!o.deliveredAt)
    .sort((a, b) => a.deliveredAt.localeCompare(b.deliveredAt))
  const now = Date.now()
  return delivered
    .filter((_, i) => i % 9 === 4)
    .map((order, i) => {
      const line = order.items[0]
      // Asked for two days after delivery, or an hour ago if that is still to come.
      const asked = Date.parse(order.deliveredAt) + 2 * DAY
      const requestedAt = new Date(Math.min(asked, now - 3_600_000))
      const refundedAt = new Date(asked + 3 * DAY)
      const status: ReturnStatus =
        asked > now ? 'REQUESTED' : i === 3 ? 'REJECTED' : refundedAt.getTime() > now ? 'APPROVED' : 'REFUNDED'
      return {
        id: `ret-${i + 1}`,
        orderId: order.id,
        orderNumber: order.orderNumber,
        status,
        requestedAt: requestedAt.toISOString(),
        reason: REASONS[i % REASONS.length],
        merchantId: line.merchantId,
        merchantName: line.merchantName,
        customerName: order.customerName,
        items: [{ productName: line.productName, productNameAr: line.productNameAr, imageUrl: line.imageUrl, quantity: 1, unitPrice: line.unitPrice }],
        refundAmount: line.unitPrice,
        // The store answered a day later, or half an hour ago if that is still to come.
        answeredAt: status === 'REQUESTED' ? undefined : new Date(Math.min(asked + DAY, now - 1_800_000)).toISOString(),
        refundedAt: status === 'REFUNDED' ? refundedAt.toISOString() : undefined,
      }
    })
}

const RETURNS = seedReturns()

/** One line of the Cancellations and returns list: a cancelled order, or a return. */
export interface AfterSale {
  id: string
  kind: 'CANCELLED' | 'RETURNED'
  orderId: string
  orderNumber: string
  item: { productName: string; productNameAr?: string; imageUrl?: string }
  more: number
  storeId: string
  storeName: string
  buyer: string
  /** The reason's code: the app's cancel, decline or return codes. */
  reason: string
  /** Who cancelled; a return is always the shopper's. */
  by: 'SHOPPER' | 'STORE'
  /** A return's step. */
  returnStatus?: ReturnStatus
  /** The goods: what was cancelled, or what is (or was) handed back. */
  value: number
  at: string
}

function afterSales(): AfterSale[] {
  const cancelled: AfterSale[] = allOrders()
    .filter((o) => o.status === 'CANCELLED')
    .map((o) => ({
      id: o.id,
      kind: 'CANCELLED',
      orderId: o.id,
      orderNumber: o.orderNumber,
      item: o.items[0],
      more: o.items.length - 1,
      storeId: o.items[0].merchantId,
      storeName: o.merchantNames[0],
      buyer: o.customerName,
      reason: o.cancelReason ?? 'OTHER',
      by: o.cancelledBy ?? 'SHOPPER',
      value: o.subtotal - o.discount,
      at: o.cancelledAt ?? o.placedAt,
    }))
  const returned: AfterSale[] = RETURNS.map((r) => ({
    id: r.id,
    kind: 'RETURNED',
    orderId: r.orderId,
    orderNumber: r.orderNumber,
    item: r.items[0],
    more: r.items.length - 1,
    storeId: r.merchantId,
    storeName: r.merchantName,
    buyer: r.customerName,
    reason: r.reason,
    by: 'SHOPPER',
    returnStatus: r.status,
    value: r.refundAmount,
    at: r.requestedAt,
  }))
  return [...cancelled, ...returned].sort((a, b) => b.at.localeCompare(a.at))
}

export type AfterSaleKind = AfterSale['kind']

/**
 * GET /admin/after-sales?kind=&days= (web-only route, TODO.md): cancelled
 * orders and returns, newest first. The counts and value are for the period,
 * whatever the kind.
 */
export function listAfterSales(query: { kind?: AfterSaleKind; days?: number } & PageAsk): Promise<
  Paged<{
    items: AfterSale[]
    counts: { all: number; CANCELLED: number; RETURNED: number; openReturns: number }
    value: number
  }>
> {
  if (!USE_MOCK) return httpPage('/admin/after-sales', { kind: query.kind, days: query.days?.toString() }, query)
  return reply(() => {
    const since = query.days ? Date.now() - query.days * 86_400_000 : 0
    const found = afterSales().filter((a) => Date.parse(a.at) >= since)
    return {
      ...pageOf(
        found.filter((a) => !query.kind || a.kind === query.kind),
        query,
      ),
      counts: {
        all: found.length,
        CANCELLED: found.filter((a) => a.kind === 'CANCELLED').length,
        RETURNED: found.filter((a) => a.kind === 'RETURNED').length,
        openReturns: found.filter((a) => a.returnStatus === 'REQUESTED' || a.returnStatus === 'APPROVED').length,
      },
      // A return the store turned down lost nothing: the shopper kept the item.
      value: found.filter((a) => a.returnStatus !== 'REJECTED').reduce((sum, a) => sum + a.value, 0),
    }
  })
}

/** GET /admin/returns/{id} (web-only route, TODO.md) */
export function getReturn(id: string): Promise<AdminReturn> {
  if (!USE_MOCK) return http('GET', `/admin/returns/${encodeURIComponent(id)}`)
  return reply(() => {
    const found = RETURNS.find((r) => r.id === id)
    if (!found) throw new ApiError('NOT_FOUND')
    return found
  })
}

// Read by the other mock files, never by a screen.
export function allReturns(): AdminReturn[] {
  return RETURNS
}
