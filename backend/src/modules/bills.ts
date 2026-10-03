import type { Request } from 'express'
import { z } from 'zod'
import type { Context } from '../app.js'
import type { Connection, Pool } from '../db/pool.js'
import { duplicateKey, exec, one, rows } from '../db/sql.js'
import { withTransaction } from '../db/tx.js'
import { me } from '../http/auth.js'
import { AppError } from '../http/errors.js'
import { route, type Api } from '../http/route.js'
import { publish } from '../lib/events.js'
import { GOVERNORATES, type Governorate } from '../lib/governorates.js'
import { addDays, addMonths, baghdadDay, billingMonth, billOwed } from '../lib/money.js'
import { urlOf } from '../lib/storage.js'
import { BAGHDAD_OFFSET, COMMISSION_PERCENT } from '../rules.js'

// What each store owes Saba (API_CONTRACT.md §3.7, DATABASE_DESIGN.md §3.7).
// Every bill is worked out when read, from the delivered parts (their
// billing_month) and the refunded returns (their refund_month), never stored.
// Only a month Saba marks paid is written down, in bill_payments.

export const BILL_STATUSES = ['OPEN', 'DUE', 'PAID', 'NONE'] as const

export const Bill = z
  .object({
    month: z.string(),
    orderCount: z.number(),
    sales: z.number(),
    returned: z.number(),
    owed: z.number(),
    status: z.enum(BILL_STATUSES),
    paidAt: z.string().optional(),
  })
  .meta({ id: 'Bill' })
export type Bill = z.infer<typeof Bill>

const FinanceStore = z
  .object({
    id: z.string(),
    storeName: z.string(),
    logoUrl: z.string().optional(),
    governorate: z.enum(GOVERNORATES),
    status: z.enum(['APPROVED', 'SUSPENDED', 'CLOSED']),
  })
  .meta({ id: 'FinanceStore' })
type FinanceStore = z.infer<typeof FinanceStore>

const FinanceRow = z
  .object({
    store: FinanceStore,
    orderCount: z.number(),
    sales: z.number(),
    returned: z.number(),
    owed: z.number(),
    paid: z.number(),
    stillOwed: z.number(),
    status: z.enum(BILL_STATUSES),
    paidAt: z.string().optional(),
  })
  .meta({ id: 'FinanceRow' })
type FinanceRow = z.infer<typeof FinanceRow>

/** One store's month: what it delivered, what it handed back, and the day Saba marked it paid. */
interface MonthFigures {
  orderCount: number
  sales: number
  returned: number
  paidOn?: string
}

/**
 * Each store's months with a delivery or a refund, and the months marked
 * paid: store → month ("2026-08-01") → figures. [storeId] null reads them all.
 */
async function ledger(db: Pool | Connection, storeId: number | null): Promise<Map<number, Map<string, MonthFigures>>> {
  const [and, where, params] = storeId === null ? ['', '', []] : [' AND store_id = ?', ' WHERE store_id = ?', [storeId]]
  const found = new Map<number, Map<string, MonthFigures>>()
  const at = (store: number, month: string): MonthFigures => {
    const months = found.get(store) ?? found.set(store, new Map()).get(store)!
    return months.get(month) ?? months.set(month, { orderCount: 0, sales: 0, returned: 0 }).get(month)!
  }
  // Sums come back from MySQL as DECIMAL: read through Number().
  const sold = await rows<{ store_id: number; month: string; parts: number; sales: number }>(
    db,
    `SELECT store_id, DATE_FORMAT(billing_month, '%Y-%m-%d') AS month, COUNT(*) AS parts, SUM(subtotal - discount) AS sales
       FROM order_store_parts WHERE status = 'DELIVERED'${and} GROUP BY store_id, billing_month`,
    params,
  )
  for (const row of sold) Object.assign(at(row.store_id, row.month), { orderCount: Number(row.parts), sales: Number(row.sales) })
  const refunded = await rows<{ store_id: number; month: string; returned: number }>(
    db,
    `SELECT store_id, DATE_FORMAT(refund_month, '%Y-%m-%d') AS month, SUM(refund_amount) AS returned
       FROM returns WHERE status = 'REFUNDED'${and} GROUP BY store_id, refund_month`,
    params,
  )
  for (const row of refunded) at(row.store_id, row.month).returned = Number(row.returned)
  const paid = await rows<{ store_id: number; month: string; paid_on: string }>(
    db,
    `SELECT store_id, DATE_FORMAT(month, '%Y-%m-%d') AS month, DATE_FORMAT(paid_on, '%Y-%m-%d') AS paid_on FROM bill_payments${where}`,
    params,
  )
  for (const row of paid) at(row.store_id, row.month).paidOn = row.paid_on
  return found
}

/** The paid day as a moment: noon in Baghdad, so the web shows the same day in any time zone (§2.2). */
const paidAtOf = (day: string) => new Date(`${day}T12:00:00.000${BAGHDAD_OFFSET}`).toISOString()

/** [month]'s bill from its figures. The month under way is OPEN; a closed one PAID, NONE or DUE. */
function billOf(month: string, figures: MonthFigures | undefined, thisMonth: string): Bill {
  const sales = figures?.sales ?? 0
  const returned = figures?.returned ?? 0
  const owed = billOwed(sales, returned, COMMISSION_PERCENT)
  const status = month === thisMonth ? 'OPEN' : figures?.paidOn ? 'PAID' : owed === 0 ? 'NONE' : 'DUE'
  return {
    month,
    orderCount: figures?.orderCount ?? 0,
    sales,
    returned,
    owed,
    status,
    ...(status === 'PAID' && { paidAt: paidAtOf(figures!.paidOn!) }),
  }
}

/** [storeId]'s bills: this month, and every month with a delivery or a refund (D4), newest first. */
export async function storeBills(db: Pool | Connection, storeId: number, now = new Date()): Promise<Bill[]> {
  const thisMonth = billingMonth(now)
  const months = (await ledger(db, storeId)).get(storeId) ?? new Map<string, MonthFigures>()
  return [...new Set([thisMonth, ...months.keys()])]
    .sort()
    .reverse()
    .map((month) => billOf(month, months.get(month), thisMonth))
}

/** What a store owes Saba now: this month so far and every month still due ("Close my store"). */
export const owedNow = (bills: Bill[]) =>
  bills.filter((bill) => bill.status === 'OPEN' || bill.status === 'DUE').reduce((sum, bill) => sum + bill.owed, 0)

const stillOwedOf = (bill: Bill) => (bill.status === 'DUE' ? bill.owed : 0)
const paidOf = (bill: Bill) => (bill.status === 'PAID' ? bill.owed : 0)

/** One store's line in Finance: one month's bill, or several added up (web's `rowFor`). */
function rowFor(store: FinanceStore, bills: Bill[]): FinanceRow {
  const sum = (pick: (bill: Bill) => number) => bills.reduce((total, bill) => total + pick(bill), 0)
  const owed = sum((bill) => bill.owed)
  const stillOwed = sum(stillOwedOf)
  const single = bills.length === 1 ? bills[0] : undefined
  return {
    store,
    orderCount: sum((bill) => bill.orderCount),
    sales: sum((bill) => bill.sales),
    returned: sum((bill) => bill.returned),
    owed,
    paid: sum(paidOf),
    stillOwed,
    status: single ? single.status : stillOwed > 0 ? 'DUE' : owed > 0 ? 'PAID' : 'NONE',
    ...(single?.paidAt && { paidAt: single.paidAt }),
  }
}

interface StoreRow {
  id: number
  store_name: string
  logo_url: string | null
  governorate: Governorate
  status: 'APPROVED' | 'SUSPENDED' | 'CLOSED'
}

/** A month in a path or a query: "2026-08". */
const MONTH = /^\d{4}-(0[1-9]|1[0-2])$/

export function billRoutes(api: Api, ctx: Context): void {
  const { pool } = ctx
  const ADMIN = ['ADMIN'] as const

  /**
   * Stores that can sell, or did (contract §3.7): approved or suspended, and a
   * deleted store (CLOSED) that delivered, so its paid months stay in the totals. [id] picks one.
   */
  async function financeStores(req: Request, id?: number): Promise<FinanceStore[]> {
    const found = await rows<StoreRow>(
      pool,
      `SELECT id, store_name, logo_url, governorate, status FROM stores
        WHERE (status IN ('APPROVED', 'SUSPENDED')
               OR (status = 'CLOSED' AND EXISTS (SELECT 1 FROM order_store_parts p WHERE p.store_id = stores.id AND p.status = 'DELIVERED')))
              ${id === undefined ? '' : ' AND id = ?'} ORDER BY id`,
      id === undefined ? [] : [id],
    )
    return found.map((row) => ({
      id: String(row.id),
      storeName: row.store_name,
      ...(row.logo_url !== null && { logoUrl: urlOf(req, ctx.config.mediaBaseUrl, row.logo_url) }),
      governorate: row.governorate,
      status: row.status,
    }))
  }

  /** The store in the path; 404 unless it is approved or suspended. */
  async function financeStore(req: Request, text: string): Promise<FinanceStore> {
    const store = /^\d{1,15}$/.test(text) ? (await financeStores(req, Number(text)))[0] : undefined
    if (!store) throw notFound()
    return store
  }

  /** The month in the path, as its first day; 404 unless it is a month up to this one. */
  function pathMonth(text: string, thisMonth: string): string {
    const month = `${text}-01`
    if (!MONTH.test(text) || month > thisMonth) throw notFound()
    return month
  }

  async function billAt(storeId: number, month: string): Promise<Bill> {
    return billOf(month, (await ledger(pool, storeId)).get(storeId)?.get(month), billingMonth(new Date()))
  }

  route(api, {
    method: 'get',
    path: '/merchants/me/bills',
    tag: 'Store: money',
    summary: "What the store owes Saba: this month so far, and every month since with a delivery or a refund (D4)",
    who: ['MERCHANT'],
    response: z.object({ currencyCode: z.literal('IQD'), ratePercent: z.number(), current: Bill, past: z.array(Bill) }),
    async handle({ req }) {
      const store = await one<{ id: number }>(pool, 'SELECT id FROM stores WHERE owner_user_id = ?', [me(req).id])
      if (!store) throw notFound()
      const [current, ...past] = await storeBills(pool, store.id)
      return { currencyCode: 'IQD' as const, ratePercent: COMMISSION_PERCENT, current: current!, past }
    },
  })

  route(api, {
    method: 'get',
    path: '/admin/finance',
    tag: 'Admin: finance',
    summary: "Every store's bill for one month, or every closed month added up (month=past)",
    who: ADMIN,
    query: z.object({
      month: z.string().refine((text) => text === 'past' || MONTH.test(text), { error: 'field.invalid' }),
      paid: z.enum(['PAID', 'DUE']).optional(),
    }),
    response: z.object({
      ratePercent: z.number(),
      months: z.array(z.string()),
      thisMonth: z.object({ month: z.string(), orderCount: z.number(), sales: z.number(), owed: z.number() }),
      lastMonth: z.object({ month: z.string(), owed: z.number(), collected: z.number(), stillOwed: z.number() }),
      rows: z.array(FinanceRow),
      counts: z.object({ all: z.number(), PAID: z.number(), DUE: z.number() }),
      totals: z.object({ owed: z.number(), paid: z.number(), stillOwed: z.number() }),
    }),
    async handle({ req, query }) {
      const thisMonth = billingMonth(new Date())
      if (query.month !== 'past' && `${query.month}-01` > thisMonth) {
        throw new AppError(422, 'VALIDATION_ERROR', 'error.validation', undefined, { month: { key: 'field.invalid' } })
      }
      const figures = await ledger(pool, null)
      const stores = await financeStores(req)
      const billFor = (store: FinanceStore, month: string) => billOf(month, figures.get(Number(store.id))?.get(month), thisMonth)

      // From the first month anything was delivered, up to this one, newest first.
      const first = [...figures.values()].flatMap((months) => [...months.keys()]).reduce((min, month) => (month < min ? month : min), thisMonth)
      const months: string[] = []
      for (let month = thisMonth; month >= first; month = addMonths(month, -1)) months.push(month)

      const chosen = query.month === 'past' ? months.slice(1) : [`${query.month}-01`]
      const found = stores.map((store) =>
        rowFor(
          store,
          chosen.map((month) => billFor(store, month)),
        ),
      )
      const shown = found
        .filter((row) => !query.paid || (query.paid === 'DUE' ? row.stillOwed > 0 : row.status === 'PAID'))
        .sort((a, b) => b.stillOwed - a.stillOwed || b.owed - a.owed || Number(a.store.id) - Number(b.store.id))
      const lastMonth = addMonths(thisMonth, -1)
      const now = stores.map((store) => billFor(store, thisMonth))
      const before = stores.map((store) => billFor(store, lastMonth))
      const add = (bills: Bill[], pick: (bill: Bill) => number) => bills.reduce((total, bill) => total + pick(bill), 0)
      return {
        ratePercent: COMMISSION_PERCENT,
        months,
        thisMonth: {
          month: thisMonth,
          orderCount: add(now, (bill) => bill.orderCount),
          sales: add(now, (bill) => bill.sales),
          owed: add(now, (bill) => bill.owed),
        },
        lastMonth: { month: lastMonth, owed: add(before, (one) => one.owed), collected: add(before, paidOf), stillOwed: add(before, stillOwedOf) },
        rows: shown,
        counts: {
          all: found.length,
          PAID: found.filter((row) => row.status === 'PAID').length,
          DUE: found.filter((row) => row.stillOwed > 0).length,
        },
        totals: {
          owed: shown.reduce((total, row) => total + row.owed, 0),
          paid: shown.reduce((total, row) => total + row.paid, 0),
          stillOwed: shown.reduce((total, row) => total + row.stillOwed, 0),
        },
      }
    },
  })

  route(api, {
    method: 'get',
    path: '/admin/stores/:id/bills',
    tag: 'Admin: finance',
    summary: "One store's bills: this month, and every month with a delivery or a refund since it was approved (D4)",
    who: ADMIN,
    params: z.object({ id: z.string() }),
    response: z.object({ store: FinanceStore, ratePercent: z.number(), bills: z.array(Bill), stillOwed: z.number() }),
    async handle({ req, params }) {
      const store = await financeStore(req, params.id)
      const bills = await storeBills(pool, Number(store.id))
      return { store, ratePercent: COMMISSION_PERCENT, bills, stillOwed: bills.reduce((total, bill) => total + stillOwedOf(bill), 0) }
    },
  })

  route(api, {
    method: 'post',
    path: '/admin/stores/:id/bills/:month/paid',
    tag: 'Admin: finance',
    summary: 'Mark a due month paid, the whole of it, on the day the cash came in',
    who: ADMIN,
    params: z.object({ id: z.string(), month: z.string() }),
    body: z.object({ paidAt: z.string() }),
    response: Bill,
    async handle({ req, params, body }) {
      const store = await financeStore(req, params.id)
      const today = baghdadDay(new Date())
      const month = pathMonth(params.month, billingMonth(new Date()))
      const bill = await billAt(Number(store.id), month)
      if (bill.status !== 'DUE') throw new AppError(409, 'CONFLICT_ERROR', 'admin.wrongState')
      // A day on the calendar, after the month ended and not after today.
      const day = body.paidAt
      const real = /^\d{4}-\d{2}-\d{2}$/.test(day) && !Number.isNaN(Date.parse(`${day}T00:00:00.000Z`)) && addDays(day, 0) === day
      if (!real || day < addMonths(month, 1) || day > today) {
        throw new AppError(422, 'VALIDATION_ERROR', 'bill.paidDay', undefined, { paidAt: { key: 'bill.paidDay' } })
      }
      await withTransaction(pool, async (conn) => {
        try {
          await exec(conn, 'INSERT INTO bill_payments (store_id, month, paid_on, owed, rate_percent, recorded_by) VALUES (?, ?, ?, ?, ?, ?)', [
            store.id,
            month,
            day,
            bill.owed,
            COMMISSION_PERCENT,
            me(req).id,
          ])
        } catch (error) {
          // Marked by someone else a moment ago: the month is paid once.
          if (duplicateKey(error) === 'uq_bill_payments_store_month') throw new AppError(409, 'CONFLICT_ERROR', 'admin.wrongState')
          throw error
        }
        await audit(conn, req, 'BILL_PAID', store, month, { owed: bill.owed, ratePercent: COMMISSION_PERCENT, paidOn: day })
      })
      return billAt(Number(store.id), month)
    },
  })

  route(api, {
    method: 'delete',
    path: '/admin/stores/:id/bills/:month/paid',
    tag: 'Admin: finance',
    summary: 'Mark a month paid by mistake as not paid: it is due again',
    who: ADMIN,
    params: z.object({ id: z.string(), month: z.string() }),
    response: Bill,
    async handle({ req, params }) {
      const store = await financeStore(req, params.id)
      const month = pathMonth(params.month, billingMonth(new Date()))
      await withTransaction(pool, async (conn) => {
        const paid = await one<{ id: number; paid_on: string; owed: number; rate_percent: number; recorded_by: number }>(
          conn,
          `SELECT id, DATE_FORMAT(paid_on, '%Y-%m-%d') AS paid_on, owed, rate_percent, recorded_by FROM bill_payments
            WHERE store_id = ? AND month = ? FOR UPDATE`,
          [store.id, month],
        )
        if (!paid) throw new AppError(409, 'CONFLICT_ERROR', 'admin.wrongState')
        await exec(conn, 'DELETE FROM bill_payments WHERE id = ?', [paid.id])
        // What the row said, since the row itself is gone (DATABASE_DESIGN.md §3.7).
        await audit(conn, req, 'BILL_UNPAID', store, month, {
          owed: paid.owed,
          ratePercent: paid.rate_percent,
          paidOn: paid.paid_on,
          recordedBy: paid.recorded_by,
        })
      })
      return billAt(Number(store.id), month)
    },
  })
}

/** Who marked which month, when, and what the payment said; Finance reloads for every admin. */
async function audit(conn: Connection, req: Request, action: string, store: FinanceStore, month: string, details: object): Promise<void> {
  await exec(
    conn,
    `INSERT INTO admin_actions (admin_user_id, action, entity_type, entity_id, details, ip)
     VALUES (?, ?, 'BILL', ?, ?, ?)`,
    [me(req).id, action, `${store.id}:${month.slice(0, 7)}`, JSON.stringify(details), req.ip ?? null],
  )
  publish(conn, 'ADMINS', 'bills', store.id)
}

function notFound(): AppError {
  return new AppError(404, 'NOT_FOUND_ERROR', 'error.notFound')
}
