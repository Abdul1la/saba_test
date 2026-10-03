import type { Request } from 'express'
import { z } from 'zod'
import type { Context } from '../app.js'
import { one, rows } from '../db/sql.js'
import { me } from '../http/auth.js'
import { AppError } from '../http/errors.js'
import { route, type Api } from '../http/route.js'
import { addDays, addMonths, baghdadDay, dayStart } from '../lib/money.js'
import { shelfFilters, shelfOf, shelfRow, ShelfRow } from './merchant-products.js'
import { shaper } from './products.js'
import { ratingOf } from './stores.js'

// The store's own numbers (BACKEND_PLAN.md §6.5): its dashboard and Analytics,
// on Baghdad's calendar. A sale is a delivered part's goods less the store's
// own coupon, the delivery fee left out: the figure its bill counts
// (DATABASE_DESIGN.md §6), so the screens can't disagree with what it owes.

const TAG = 'Store: money'
const STORE = ['MERCHANT'] as const
const HOUR_MS = 3_600_000
const DAY_MS = 24 * HOUR_MS

const SalesPoint = z
  .object({
    label: z.string(),
    // The Baghdad day the point starts, a plain date: a phone in any time
    // zone names the same day or month (contract §6.3's reason).
    from: z.string(),
    unit: z.enum(['DAY', 'WEEK', 'MONTH']),
    value: z.number(),
  })
  .meta({ id: 'SalesPoint' })
type SalesPoint = z.infer<typeof SalesPoint>

interface Delivered {
  delivered_at: Date
  goods: number
}

/** What was delivered in [from, to): how many store parts, and their goods. */
function soldIn(parts: Delivered[], from: Date, to: Date): { count: number; goods: number } {
  const within = parts.filter((part) => part.delivered_at >= from && part.delivered_at < to)
  return { count: within.length, goods: within.reduce((sum, part) => sum + part.goods, 0) }
}

/** The same stretch of the period before: as long as this one has run, never past its start. */
function sameStretch(before: Date, from: Date, now: Date): Date {
  return new Date(Math.min(before.getTime() + (now.getTime() - from.getTime()), from.getTime()))
}

export function storeDashboardRoutes(api: Api, ctx: Context): void {
  const { pool } = ctx

  async function ownStore(req: Request) {
    const store = await one<{ id: number; is_open: number; rating_sum: number; rating_count: number }>(
      pool,
      'SELECT id, is_open, rating_sum, rating_count FROM stores WHERE owner_user_id = ?',
      [me(req).id],
    )
    if (!store) throw new AppError(404, 'NOT_FOUND_ERROR', 'error.notFound')
    return store
  }

  /** [storeId]'s parts delivered from [from] on. */
  async function deliveredSince(storeId: number, from: Date): Promise<Delivered[]> {
    const found = await rows<Delivered>(
      pool,
      `SELECT delivered_at, subtotal - discount AS goods FROM order_store_parts
        WHERE store_id = ? AND status = 'DELIVERED' AND delivered_at >= ?`,
      [storeId, from],
    )
    return found.map((part) => ({ delivered_at: part.delivered_at, goods: Number(part.goods) }))
  }

  /** A store that has never delivered anything has no chart: the app says "No sales yet". */
  const everDelivered = async (storeId: number) =>
    !!(await one(pool, "SELECT 1 FROM order_store_parts WHERE store_id = ? AND status = 'DELIVERED' LIMIT 1", [storeId]))

  /** The cash [storeId] handed back on returns in [from, to). */
  async function refundedIn(storeId: number, from: Date, to: Date): Promise<number> {
    const found = await one<{ total: number }>(
      pool,
      `SELECT COALESCE(SUM(refund_amount), 0) AS total FROM returns
        WHERE store_id = ? AND status = 'REFUNDED' AND refunded_at >= ? AND refunded_at < ?`,
      [storeId, from, to],
    )
    return Number(found?.total ?? 0)
  }

  route(api, {
    method: 'get',
    path: '/merchants/me/dashboard',
    tag: TAG,
    summary: "This month so far against the same days of last month, what waits for the store, and six months of sales",
    who: STORE,
    response: z.object({
      currencyCode: z.literal('IQD'),
      revenue: z.number(),
      orderCount: z.number(),
      productCount: z.number(),
      pendingOrders: z.number(),
      lowStockCount: z.number(),
      outOfStockCount: z.number(),
      rejectedCount: z.number(),
      returnCount: z.number(),
      refundTotal: z.number(),
      isOpen: z.boolean(),
      previousRevenue: z.number().optional(),
      comparisonDays: z.number().optional(),
      orderCountDelta: z.number().optional(),
      oldestPendingHours: z.number().optional(),
      rating: z.number().optional(),
      ratingCount: z.number().optional(),
      salesSeries: z.array(SalesPoint),
    }),
    async handle({ req }) {
      const store = await ownStore(req)
      const now = new Date()
      const today = baghdadDay(now)
      const month = `${today.slice(0, 7)}-01`
      const [from, to] = [dayStart(month), dayStart(addMonths(month, 1))]
      const before = dayStart(addMonths(month, -1))
      const parts = await deliveredSince(store.id, dayStart(addMonths(month, -5)))
      const sold = soldIn(parts, from, to)
      const earlier = soldIn(parts, before, sameStretch(before, from, now))

      const shelf = await shelfOf(pool, store.id)
      const pending = await one<{ n: number; oldest: Date | null }>(
        pool,
        `SELECT COUNT(*) AS n, MIN(o.placed_at) AS oldest FROM order_store_parts op JOIN orders o ON o.id = op.order_id
          WHERE op.store_id = ? AND op.status = 'PENDING'`,
        [store.id],
      )
      // Returns waiting for the store's answer.
      const asked = await one<{ n: number }>(pool, "SELECT COUNT(*) AS n FROM returns WHERE store_id = ? AND status = 'REQUESTED'", [store.id])
      const rating = ratingOf(store)
      const series: SalesPoint[] = []
      if (await everDelivered(store.id)) {
        for (let back = 5; back >= 0; back--) {
          const start = addMonths(month, -back)
          series.push({
            label: `M-${back}`,
            from: start,
            unit: 'MONTH',
            value: soldIn(parts, dayStart(start), dayStart(addMonths(start, 1))).goods,
          })
        }
      }

      return {
        currencyCode: 'IQD' as const,
        revenue: sold.goods,
        orderCount: sold.count,
        productCount: shelf.length,
        pendingOrders: Number(pending?.n ?? 0),
        lowStockCount: shelf.filter(shelfFilters.low).length,
        outOfStockCount: shelf.filter(shelfFilters.out).length,
        rejectedCount: shelf.filter((loaded) => loaded.row.status === 'REJECTED').length,
        returnCount: Number(asked?.n ?? 0),
        refundTotal: await refundedIn(store.id, from, to),
        isOpen: store.is_open === 1,
        // Only when last month has something to compare with: no "up 12%" drawn against nothing.
        ...(earlier.count > 0 && {
          previousRevenue: earlier.goods,
          comparisonDays: Math.min(Number(today.slice(8)), Math.round((from.getTime() - before.getTime()) / DAY_MS)),
          orderCountDelta: sold.count - earlier.count,
        }),
        ...(pending?.oldest && { oldestPendingHours: Math.floor((now.getTime() - pending.oldest.getTime()) / HOUR_MS) }),
        ...(rating !== undefined && { rating, ratingCount: store.rating_count }),
        salesSeries: series,
      }
    },
  })

  route(api, {
    method: 'get',
    path: '/merchants/me/analytics',
    tag: TAG,
    summary: 'This week by day, this month by week or this year by month, each against the same stretch before it',
    who: STORE,
    query: z.object({ period: z.enum(['week', 'month', 'year']).default('month') }),
    response: z.object({
      currencyCode: z.literal('IQD'),
      revenue: z.number(),
      previousRevenue: z.number().optional(),
      orderCount: z.number(),
      productsSold: z.number(),
      averageOrderValue: z.number(),
      refundTotal: z.number(),
      cancellationCount: z.number(),
      series: z.array(SalesPoint),
      topProducts: z.array(ShelfRow),
    }),
    async handle({ req, query }) {
      const store = await ownStore(req)
      const now = new Date()
      const today = baghdadDay(now)
      const month = `${today.slice(0, 7)}-01`
      const year = `${today.slice(0, 4)}-01-01`
      // Where the period and the one before it begin, where it ends, and its points.
      const period = {
        week: { first: addDays(today, -6), previous: addDays(today, -13), end: addDays(today, 1), unit: 'DAY' as const, prefix: 'D', points: 7, step: (i: number) => addDays(today, i - 6) },
        month: { first: month, previous: addMonths(month, -1), end: addMonths(month, 1), unit: 'WEEK' as const, prefix: 'W', points: Math.ceil(Number(today.slice(8)) / 7), step: (i: number) => addDays(month, 7 * i) },
        year: { first: year, previous: addMonths(year, -12), end: addMonths(year, 12), unit: 'MONTH' as const, prefix: 'M', points: Number(today.slice(5, 7)), step: (i: number) => addMonths(year, i) },
      }[query.period]
      const [from, to, before] = [dayStart(period.first), dayStart(period.end), dayStart(period.previous)]
      const parts = await deliveredSince(store.id, before)
      const sold = soldIn(parts, from, to)
      const earlier = soldIn(parts, before, sameStretch(before, from, now))

      const units = await rows<{ product_id: number; units: number }>(
        pool,
        `SELECT oi.product_id, SUM(oi.quantity) AS units FROM order_items oi JOIN order_store_parts op ON op.id = oi.part_id
          WHERE op.store_id = ? AND op.status = 'DELIVERED' AND op.delivered_at >= ? AND op.delivered_at < ?
          GROUP BY oi.product_id ORDER BY units DESC, oi.product_id`,
        [store.id, from, to],
      )
      const cancelled = await one<{ n: number }>(
        pool,
        `SELECT COUNT(*) AS n FROM order_store_parts op JOIN orders o ON o.id = op.order_id
          WHERE op.store_id = ? AND op.status IN ('CANCELLED', 'REFUSED') AND o.placed_at >= ? AND o.placed_at < ?`,
        [store.id, from, to],
      )
      // Its best sellers still on its shelf, most units first.
      // ponytail: the whole shelf is loaded to pick five; fine for hundreds of products.
      const shape = shaper(req, ctx)
      const live = new Map((await shelfOf(pool, store.id)).map((loaded) => [loaded.row.id, loaded]))
      const top = units.filter((row) => live.has(row.product_id)).slice(0, 5)

      const series: SalesPoint[] = []
      if (await everDelivered(store.id)) {
        for (let i = 0; i < period.points; i++) {
          const start = period.step(i)
          const next = period.step(i + 1) < period.end ? period.step(i + 1) : period.end
          series.push({ label: `${period.prefix}${i + 1}`, from: start, unit: period.unit, value: soldIn(parts, dayStart(start), dayStart(next)).goods })
        }
      }

      return {
        currencyCode: 'IQD' as const,
        revenue: sold.goods,
        ...(earlier.count > 0 && { previousRevenue: earlier.goods }),
        orderCount: sold.count,
        productsSold: units.reduce((sum, row) => sum + Number(row.units), 0),
        averageOrderValue: sold.count === 0 ? 0 : Math.round(sold.goods / sold.count),
        refundTotal: await refundedIn(store.id, from, to),
        cancellationCount: Number(cancelled?.n ?? 0),
        series,
        topProducts: top.map((row) => shelfRow(shape, live.get(row.product_id)!)),
      }
    },
  })
}
