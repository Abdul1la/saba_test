import { http, searchOf, USE_MOCK } from './http'
import { ApiError, reply } from './mock'
import { allOrders } from './orders'
import { allReturns } from './returns'
import { allStores } from './stores'
import type { Governorate, StoreStatus } from './types'

// What each store owes Saba, by the app's own rule (MockApiInterceptor._bill,
// the "What you owe Saba" screen): per calendar month, 8% of the store's
// delivered sales (goods less its own discount; the delivery fee is the
// store's) less the cash it handed back on refunded returns, to the nearest
// 250 IQD. The month under way is OPEN; each earlier one is DUE until Saba
// marks it PAID here.

export const RATE_PERCENT = 8

/** OPEN: this month, still building up. NONE: a closed month with nothing to pay. */
export type BillStatus = 'OPEN' | 'DUE' | 'PAID' | 'NONE'

/**
 * "2026-09". The API writes a month as its first day, "2026-09-01": keep
 * its first 7 characters (API_CONTRACT.md §6.3).
 */
export type Month = string

export interface Bill {
  month: Month
  orderCount: number
  sales: number
  returned: number
  owed: number
  status: BillStatus
  /** web-only: the day Saba marked it paid. */
  paidAt?: string
}

export interface FinanceStore {
  id: string
  storeName: string
  logoUrl?: string
  governorate: Governorate
  status: StoreStatus
}

/** One store's line in the table: one month's bill, or all closed months added up. */
export interface FinanceRow extends Omit<Bill, 'month'> {
  store: FinanceStore
  paid: number
  stillOwed: number
}

export type PaidFilter = 'PAID' | 'DUE'

export interface Finance {
  ratePercent: number
  /** Newest first; the first is this month. */
  months: Month[]
  thisMonth: { month: Month; orderCount: number; sales: number; owed: number }
  lastMonth: { month: Month; owed: number; collected: number; stillOwed: number }
  rows: FinanceRow[]
  counts: { all: number; PAID: number; DUE: number }
  totals: { owed: number; paid: number; stillOwed: number }
}

// The server writes a month as its first day ("2026-08-01"); the web keeps "2026-08".
const ym = (month: string): Month => month.slice(0, 7)
const asMonth = (bill: Bill): Bill => ({ ...bill, month: ym(bill.month) })
const billsPath = (storeId: string) => `/admin/stores/${encodeURIComponent(storeId)}/bills`

const monthOf = (date: Date): Month => `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`
const startOf = (month: Month) => {
  const [year, m] = month.split('-').map(Number)
  return new Date(year, m - 1, 1)
}
const nextMonth = (month: Month) => {
  const start = startOf(month)
  return new Date(start.getFullYear(), start.getMonth() + 1, 1)
}
const thisMonth = () => monthOf(new Date())

/** Payments Saba has recorded: "m-1:2026-08" -> "2026-09-03". */
const PAID = new Map<string, string>()

/** The rule, for one store and one month. */
function bill(storeId: string, month: Month): Bill {
  const from = startOf(month).getTime()
  const to = nextMonth(month).getTime()
  const within = (at?: string) => !!at && Date.parse(at) >= from && Date.parse(at) < to
  const delivered = allOrders().filter(
    (o) => o.status === 'DELIVERED' && within(o.deliveredAt) && o.items.some((item) => item.merchantId === storeId),
  )
  // Every demo order is one store's, so its goods less its discount are that store's.
  const sales = delivered.reduce((sum, o) => sum + o.subtotal - o.discount, 0)
  const returned = allReturns()
    .filter((r) => r.merchantId === storeId && r.status === 'REFUNDED' && within(r.refundedAt))
    .reduce((sum, r) => sum + r.refundAmount, 0)
  const base = sales - returned
  const owed = base <= 0 ? 0 : Math.round((base * RATE_PERCENT) / 100 / 250) * 250
  const paidAt = PAID.get(`${storeId}:${month}`)
  const status: BillStatus = month === thisMonth() ? 'OPEN' : owed === 0 ? 'NONE' : paidAt ? 'PAID' : 'DUE'
  return { month, orderCount: delivered.length, sales, returned, owed, status, paidAt: status === 'PAID' ? paidAt : undefined }
}

/** Stores that can sell, or did: approved or suspended. */
function financeStores(): FinanceStore[] {
  return allStores()
    .filter((s) => s.status === 'APPROVED' || s.status === 'SUSPENDED')
    .map(({ id, storeName, logoUrl, governorate, status }) => ({ id, storeName, logoUrl, governorate, status }))
}

/** From the first month anything was delivered to this one, newest first. */
function months(): Month[] {
  const first = allOrders().reduce((min, o) => (o.deliveredAt && o.deliveredAt < min ? o.deliveredAt : min), new Date().toISOString())
  const out: Month[] = []
  for (let at = new Date(); monthOf(at) >= monthOf(new Date(first)); at = new Date(at.getFullYear(), at.getMonth() - 1, 1)) {
    out.push(monthOf(at))
  }
  return out
}

const paidOf = (b: Bill) => (b.status === 'PAID' ? b.owed : 0)
const stillOwedOf = (b: Bill) => (b.status === 'DUE' ? b.owed : 0)

function rowFor(store: FinanceStore, bills: Bill[]): FinanceRow {
  const sum = (pick: (b: Bill) => number) => bills.reduce((total, b) => total + pick(b), 0)
  const owed = sum((b) => b.owed)
  const stillOwed = sum(stillOwedOf)
  const one = bills.length === 1 ? bills[0] : undefined
  return {
    store,
    orderCount: sum((b) => b.orderCount),
    sales: sum((b) => b.sales),
    returned: sum((b) => b.returned),
    owed,
    paid: sum(paidOf),
    stillOwed,
    status: one ? one.status : stillOwed > 0 ? 'DUE' : owed > 0 ? 'PAID' : 'NONE',
    paidAt: one?.paidAt,
  }
}

/**
 * GET /admin/finance?month=&paid= (web-only route, TODO.md). `month` is one
 * month, or "past" for every closed month added up.
 */
export function getFinance(query: { month: Month | 'past'; paid?: PaidFilter }): Promise<Finance> {
  if (!USE_MOCK)
    return http<Finance>('GET', `/admin/finance?${searchOf(query)}`).then((f) => ({
      ...f,
      months: f.months.map(ym),
      thisMonth: { ...f.thisMonth, month: ym(f.thisMonth.month) },
      lastMonth: { ...f.lastMonth, month: ym(f.lastMonth.month) },
    }))
  return reply(() => {
    const all = months()
    const [current, last] = all
    const stores = financeStores()
    const chosen = query.month === 'past' ? all.slice(1) : [query.month]
    const found = stores.map((store) => rowFor(store, chosen.map((m) => bill(store.id, m))))
    const rows = found
      .filter((r) => !query.paid || (query.paid === 'DUE' ? r.stillOwed > 0 : r.status === 'PAID'))
      .sort((a, b) => b.stillOwed - a.stillOwed || b.owed - a.owed)
    const now = stores.map((s) => bill(s.id, current))
    const before = last ? stores.map((s) => bill(s.id, last)) : []
    const add = (bills: Bill[], pick: (b: Bill) => number) => bills.reduce((total, b) => total + pick(b), 0)
    return {
      ratePercent: RATE_PERCENT,
      months: all,
      thisMonth: {
        month: current,
        orderCount: add(now, (b) => b.orderCount),
        sales: add(now, (b) => b.sales),
        owed: add(now, (b) => b.owed),
      },
      lastMonth: { month: last ?? current, owed: add(before, (b) => b.owed), collected: add(before, paidOf), stillOwed: add(before, stillOwedOf) },
      rows,
      counts: {
        all: found.length,
        PAID: found.filter((r) => r.status === 'PAID').length,
        DUE: found.filter((r) => r.stillOwed > 0).length,
      },
      totals: {
        owed: rows.reduce((t, r) => t + r.owed, 0),
        paid: rows.reduce((t, r) => t + r.paid, 0),
        stillOwed: rows.reduce((t, r) => t + r.stillOwed, 0),
      },
    }
  })
}

/** GET /admin/stores/{id}/bills (web-only route, TODO.md): every month, newest first. */
export function getStoreBills(storeId: string): Promise<{ store: FinanceStore; ratePercent: number; bills: Bill[]; stillOwed: number }> {
  if (!USE_MOCK)
    return http<Awaited<ReturnType<typeof getStoreBills>>>('GET', `${billsPath(storeId)}`).then((r) => ({ ...r, bills: r.bills.map(asMonth) }))
  return reply(() => {
    const store = financeStores().find((s) => s.id === storeId)
    if (!store) throw new ApiError('NOT_FOUND')
    const bills = months().map((m) => bill(storeId, m))
    return { store, ratePercent: RATE_PERCENT, bills, stillOwed: bills.reduce((t, b) => t + stillOwedOf(b), 0) }
  })
}

/**
 * POST /admin/stores/{id}/bills/{month}/paid { paidAt } (web-only route,
 * TODO.md). The whole month; paid on a day after it ended, and not later
 * than today.
 */
export function markBillPaid(storeId: string, month: Month, paidAt: string): Promise<Bill> {
  if (!USE_MOCK) return http<Bill>('POST', `${billsPath(storeId)}/${month}/paid`, { paidAt }).then(asMonth)
  return reply(() => {
    if (bill(storeId, month).status !== 'DUE') throw new ApiError('WRONG_STATE')
    const day = new Date(`${paidAt}T12:00:00`)
    // By the calendar day: today counts at any hour, noon included.
    const now = new Date()
    const tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1)
    if (Number.isNaN(day.getTime()) || day < nextMonth(month) || day >= tomorrow) throw new ApiError('BAD_DATE')
    PAID.set(`${storeId}:${month}`, day.toISOString())
    return bill(storeId, month)
  })
}

/**
 * DELETE /admin/stores/{id}/bills/{month}/paid (web-only route, TODO.md):
 * a month marked paid by mistake is due again.
 */
export function unmarkBillPaid(storeId: string, month: Month): Promise<Bill> {
  if (!USE_MOCK) return http<Bill>('DELETE', `${billsPath(storeId)}/${month}/paid`).then(asMonth)
  return reply(() => {
    if (bill(storeId, month).status !== 'PAID') throw new ApiError('WRONG_STATE')
    PAID.delete(`${storeId}:${month}`)
    return bill(storeId, month)
  })
}

// web-only demo: the two oldest months are paid by everyone, early in the
// month after; last month by every other store, so some are still owed.
{
  const [, last, ...older] = months()
  financeStores().forEach((store, s) => {
    for (const month of older) PAID.set(`${store.id}:${month}`, new Date(nextMonth(month).getTime() + (2 + (s % 5)) * 86_400_000).toISOString())
    if (last && s % 2 === 0) {
      const at = new Date(nextMonth(last).getTime() + (1 + (s % 4)) * 86_400_000)
      if (at < new Date()) PAID.set(`${store.id}:${last}`, at.toISOString())
    }
  })
}
