import type { Request } from 'express'
import { z } from 'zod'
import type { Context } from '../app.js'
import { one, rows } from '../db/sql.js'
import { AppError } from '../http/errors.js'
import { IdParams } from '../http/inputs.js'
import { route, type Api } from '../http/route.js'
import { urlOf } from '../lib/storage.js'
import { ListQuery, pageSql, paged } from './admin-lists.js'
import { some } from './admin-orders.js'
import { loadReturns, RETURN_STATUSES, returnSteps, type ReturnStatus } from './returns.js'

// Saba's view of cancellations and returns (API_CONTRACT.md §3.10): read-only,
// as the shoppers and stores handle them in the app. One row per cancelled
// store part (Q7), one per return.

const DAY_MS = 86_400_000

const AfterSale = z
  .object({
    id: z.string(),
    kind: z.enum(['CANCELLED', 'RETURNED']),
    orderId: z.string(),
    orderNumber: z.string(),
    item: z.object({ productName: z.string(), productNameAr: z.string().optional(), imageUrl: z.string().optional() }),
    more: z.number(),
    storeId: z.string(),
    storeName: z.string(),
    buyer: z.string(),
    reason: z.string(),
    by: z.enum(['SHOPPER', 'STORE']),
    returnStatus: z.enum(RETURN_STATUSES).optional(),
    value: z.number(),
    at: z.string(),
  })
  .meta({ id: 'AfterSale' })
type AfterSale = z.infer<typeof AfterSale>

const AdminReturn = z
  .object({
    id: z.string(),
    orderId: z.string(),
    orderNumber: z.string(),
    status: z.enum(RETURN_STATUSES),
    requestedAt: z.string(),
    reason: z.string(),
    merchantId: z.string(),
    merchantName: z.string(),
    customerName: z.string(),
    customerNameAr: z.string().optional(),
    items: z.array(
      z.object({
        productName: z.string(),
        productNameAr: z.string().optional(),
        imageUrl: z.string().optional(),
        quantity: z.number(),
        unitPrice: z.number(),
        variantLabel: z.string().optional(),
      }),
    ),
    refundAmount: z.number(),
    answeredAt: z.string().optional(),
    refundedAt: z.string().optional(),
    // D19: what support needs to judge a dispute.
    description: z.string().optional(),
    rejectionReason: z.string().optional(),
    timeline: z.array(z.object({ status: z.enum(RETURN_STATUSES), occurredAt: z.string() })),
    photos: z.array(z.string()),
    // D6: the refund's own block; none for a declined return.
    refund: z.object({ amount: z.number(), status: z.enum(['PENDING', 'COMPLETED']), processedAt: z.string().optional() }).optional(),
  })
  .meta({ id: 'AdminReturn' })

interface FirstLine {
  product_name: string
  product_name_ar: string | null
  image_url: string | null
  store_name: string
}

export function adminReturnRoutes(api: Api, ctx: Context): void {
  const { pool } = ctx
  const ADMIN = ['ADMIN'] as const
  const TAG = 'Admin: after-sales'
  const url = (req: Request, key: string | null) => (key === null ? null : urlOf(req, ctx.config.mediaBaseUrl, key))
  const itemOf = (req: Request, line: FirstLine): AfterSale['item'] => ({
    productName: line.product_name,
    ...some('productNameAr', line.product_name_ar),
    ...some('imageUrl', url(req, line.image_url)),
  })

  route(api, {
    method: 'get',
    path: '/admin/after-sales',
    tag: TAG,
    summary: 'Cancelled store parts and returns, newest first; the counts and value cover the period, whatever the kind',
    who: ADMIN,
    query: z.object({ kind: z.enum(['CANCELLED', 'RETURNED']).optional(), days: z.enum(['7', '30', '90']).optional(), ...ListQuery }),
    response: z.object({
      items: z.array(AfterSale),
      counts: z.object({ all: z.number(), CANCELLED: z.number(), RETURNED: z.number(), openReturns: z.number() }),
      value: z.number(),
    }),
    async handle({ req, query }) {
      // Both kinds as one list of moments, in the database: the counts and the
      // value cover the period whatever the kind; the page is the newest first.
      const since = new Date(query.days ? Date.now() - Number(query.days) * DAY_MS : 0)
      const events = `(SELECT 'CANCELLED' AS kind, op.id, COALESCE(op.cancelled_at, o.placed_at) AS at, op.subtotal - op.discount AS value,
                              NULL AS return_status
                         FROM order_store_parts op JOIN orders o ON o.id = op.order_id WHERE op.status = 'CANCELLED'
                       UNION ALL
                       SELECT 'RETURNED', r.id, r.requested_at, r.refund_amount, r.status FROM returns r) e`
      // A return the store turned down lost nothing: the shopper kept the item.
      const sums = (await one<{ all_n: number; cancelled: number; returned: number; open_returns: number; value: number }>(
        pool,
        `SELECT COUNT(*) AS all_n, COALESCE(SUM(e.kind = 'CANCELLED'), 0) AS cancelled, COALESCE(SUM(e.kind = 'RETURNED'), 0) AS returned,
                COALESCE(SUM(e.return_status IN ('REQUESTED', 'APPROVED')), 0) AS open_returns,
                COALESCE(SUM(IF(e.return_status = 'REJECTED', 0, e.value)), 0) AS value
           FROM ${events} WHERE e.at >= ?`,
        [since],
      ))!
      const counts = { all: Number(sums.all_n), CANCELLED: Number(sums.cancelled), RETURNED: Number(sums.returned), openReturns: Number(sums.open_returns) }
      const page = await rows<{ kind: 'CANCELLED' | 'RETURNED'; id: number }>(
        pool,
        `SELECT e.kind, e.id FROM ${events} WHERE e.at >= ?${query.kind ? ' AND e.kind = ?' : ''}
          ORDER BY e.at DESC, e.kind, e.id DESC${pageSql(query)}`,
        [since, ...(query.kind ? [query.kind] : [])],
      )
      const partIds = page.filter((row) => row.kind === 'CANCELLED').map((row) => row.id)
      const returnIds = page.filter((row) => row.kind === 'RETURNED').map((row) => row.id)
      const parts = !partIds.length ? [] : await rows<{
        id: number
        order_id: number
        store_id: number
        subtotal: number
        discount: number
        cancellation_reason: string
        cancelled_at: Date | null
        order_number: string
        customer_name: string
        cancel_reason: string | null
        placed_at: Date
      }>(
        pool,
        `SELECT op.id, op.order_id, op.store_id, op.subtotal, op.discount, op.cancellation_reason, op.cancelled_at,
                o.order_number, o.customer_name, o.cancel_reason, o.placed_at
           FROM order_store_parts op JOIN orders o ON o.id = op.order_id WHERE op.id IN (?)`,
        [partIds],
      )
      const returns = !returnIds.length ? [] : await rows<{
        id: number
        order_id: number
        store_id: number
        status: ReturnStatus
        reason: string
        refund_amount: number
        requested_at: Date
        order_number: string
        customer_name: string
      }>(
        pool,
        `SELECT r.id, r.order_id, r.store_id, r.status, r.reason, r.refund_amount, r.requested_at, o.order_number, o.customer_name
           FROM returns r JOIN orders o ON o.id = r.order_id WHERE r.id IN (?)`,
        [returnIds],
      )
      const partLines = parts.length
        ? await rows<FirstLine & { part_id: number }>(
            pool,
            'SELECT part_id, product_name, product_name_ar, image_url, store_name FROM order_items WHERE part_id IN (?) ORDER BY id',
            [parts.map((part) => part.id)],
          )
        : []
      const returnLines = returns.length
        ? await rows<FirstLine & { return_id: number }>(
            pool,
            `SELECT ri.return_id, oi.product_name, oi.product_name_ar, oi.image_url, oi.store_name
               FROM return_items ri JOIN order_items oi ON oi.id = ri.order_item_id WHERE ri.return_id IN (?) ORDER BY ri.id`,
            [returns.map((ret) => ret.id)],
          )
        : []

      const rowsOf: AfterSale[] = [
        ...parts.map((part): AfterSale => {
          const lines = partLines.filter((line) => line.part_id === part.id)
          // Who cancelled comes from the part's reason: CUSTOMER_CANCELLED is the shopper (Q7).
          const byShopper = part.cancellation_reason === 'CUSTOMER_CANCELLED'
          return {
            id: String(part.id),
            kind: 'CANCELLED',
            orderId: String(part.order_id),
            orderNumber: part.order_number,
            item: itemOf(req, lines[0]!),
            more: lines.length - 1,
            storeId: String(part.store_id),
            storeName: lines[0]!.store_name,
            buyer: part.customer_name,
            // The shopper's own reason for cancelling; the store's decline code.
            reason: byShopper ? (part.cancel_reason ?? part.cancellation_reason) : part.cancellation_reason,
            by: byShopper ? 'SHOPPER' : 'STORE',
            value: part.subtotal - part.discount,
            at: (part.cancelled_at ?? part.placed_at).toISOString(),
          }
        }),
        ...returns.map((ret): AfterSale => {
          const lines = returnLines.filter((line) => line.return_id === ret.id)
          return {
            id: String(ret.id),
            kind: 'RETURNED',
            orderId: String(ret.order_id),
            orderNumber: ret.order_number,
            item: itemOf(req, lines[0]!),
            more: lines.length - 1,
            storeId: String(ret.store_id),
            storeName: lines[0]!.store_name,
            buyer: ret.customer_name,
            reason: ret.reason,
            by: 'SHOPPER',
            returnStatus: ret.status,
            value: ret.refund_amount,
            at: ret.requested_at.toISOString(),
          }
        }),
      ]
      // In the page's order.
      const byKey = new Map(rowsOf.map((row) => [`${row.kind}-${row.id}`, row]))
      const items = page.map((row) => byKey.get(`${row.kind}-${row.id}`)!)
      return paged({ items, counts, value: Number(sums.value) }, query, query.kind ? counts[query.kind] : counts.all)
    },
  })

  route(api, {
    method: 'get',
    path: '/admin/returns/:id',
    tag: TAG,
    summary: "One return: the shopper's words, the store's answer, its steps and its refund",
    who: ADMIN,
    params: IdParams,
    response: AdminReturn,
    async handle({ req, params }) {
      const [data] = await loadReturns(pool, [/^\d{1,15}$/.test(params.id) ? Number(params.id) : 0])
      if (!data) throw new AppError(404, 'NOT_FOUND_ERROR', 'error.notFound')
      const { ret, lines } = data
      return {
        id: String(ret.id),
        orderId: String(ret.order_id),
        orderNumber: ret.order_number,
        status: ret.status,
        requestedAt: ret.requested_at.toISOString(),
        reason: ret.reason,
        merchantId: String(ret.store_id),
        merchantName: lines[0]?.store_name ?? '',
        customerName: ret.customer_name,
        ...some('customerNameAr', ret.customer_name_ar),
        items: lines.map((line) => ({
          productName: line.product_name,
          ...some('productNameAr', line.product_name_ar),
          ...some('imageUrl', url(req, line.image_url)),
          quantity: line.quantity,
          // What the shopper paid for one, after the store's code, so the lines
          // add up to the refund (the user's call, 2026-09-27).
          unitPrice: line.paid_unit_price,
          ...some('variantLabel', line.variant_label),
        })),
        refundAmount: ret.refund_amount,
        ...some('answeredAt', ret.answered_at?.toISOString()),
        ...some('refundedAt', ret.refunded_at?.toISOString()),
        ...some('description', ret.description),
        ...some('rejectionReason', ret.rejection_reason),
        timeline: returnSteps(ret).map((step) => ({ status: step.status, occurredAt: step.at.toISOString() })),
        photos: [],
        ...(ret.status !== 'REJECTED' && {
          refund: {
            amount: ret.refund_amount,
            status: ret.status === 'REFUNDED' ? ('COMPLETED' as const) : ('PENDING' as const),
            ...some('processedAt', ret.refunded_at?.toISOString()),
          },
        }),
      }
    },
  })
}
