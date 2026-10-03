// S6 Money (BACKEND_PLAN.md §7): what each store owes Saba, month by month;
// Saba's Finance, a store's bills, marking a month paid and not paid; the
// store's dashboard and Analytics. A delivery on the first moment of a Baghdad
// month is that month's; a refund comes off the month it was handed back,
// never carried over; OPEN, NONE, DUE, PAID; the paid day's range (422);
// paying twice (409), even at the same moment.
import assert from 'node:assert/strict'
import { after, before, describe, test } from 'node:test'
import { access } from 'node:fs/promises'
import path from 'node:path'
import { exec, one, rows } from '../src/db/sql.js'
import { addDays, addMonths, baghdadDay, billingMonth, dayStart } from '../src/lib/money.js'
import type { SendText } from '../src/lib/sms.js'
import { diskStore, keyOf } from '../src/lib/storage.js'
import { finishStoreDeletions } from '../src/modules/store-deletion.js'
import { PASSWORD, PNG, startHarness, type Harness } from './api.js'
import { memoryLogger } from './helpers.js'

let h: Harness
let admin: string
before(async () => {
  h = await startHarness()
  admin = await h.signInAdmin()
})
after(() => h.close())

const SMARTPHONES = '8'
const HOUR = 3_600_000
const DAY = 24 * HOUR

let stores = 0
/** An approved, open store delivering in its own city at 3,000. */
async function openStore() {
  stores += 1
  const name = `Bills Store ${stores}`
  const store = await h.signUpStore(name, 'BAGHDAD')
  assert.equal((await h.call('POST', `/admin/stores/${store.storeId}/approve`, { token: admin })).status, 200)
  const saved = await h.call('PUT', '/merchants/me/store', {
    token: store.token,
    body: { storeName: name, governorate: 'BAGHDAD', logoUrl: null, delivery: { governorates: [], feeInside: 3000, timeInside: '1_2_DAYS' } },
  })
  assert.equal(saved.status, 200, JSON.stringify(saved.body))
  return { ...store, name, id: Number(store.storeId) }
}
type Store = Awaited<ReturnType<typeof openStore>>

async function product(store: Store, extra: Record<string, unknown> = {}, approve = true) {
  const made = await h.call('POST', '/merchants/me/products', {
    token: store.token,
    body: { name: 'Kite Studio Headphones', nameAr: 'سماعات كايت ستوديو', categoryId: SMARTPHONES, price: 145_000, stock: 20, ...extra },
  })
  assert.equal(made.status, 200, JSON.stringify(made.body))
  if (approve) assert.equal((await h.call('POST', `/admin/products/${made.body.data.id}/approve`, { token: admin })).status, 200)
  return made.body.data as { id: string }
}

async function shopper() {
  const account = await h.signUpShopper('BAGHDAD')
  const address = await h.call('POST', '/customers/me/addresses', {
    token: account.token,
    body: { fullName: 'Amina Saleh', phone: account.phone, governorate: 'BAGHDAD', area: 'Karrada', landmark: 'Near the park' },
  })
  assert.equal(address.status, 200, JSON.stringify(address.body))
  return { ...account, id: Number(account.user.id), addressId: address.body.data.id as string }
}
type Shopper = Awaited<ReturnType<typeof shopper>>

let keys = 0
let codes = 0
/** [lines] ordered from [store] by a new shopper, with 10% off when [withCode]; the store's part id. */
async function placed(store: Store, lines: [productId: string, quantity: number][], withCode = false) {
  const who = await shopper()
  for (const [productId, quantity] of lines) {
    assert.equal((await h.call('POST', '/cart/items', { token: who.token, body: { productId, quantity } })).status, 200)
  }
  if (withCode) {
    codes += 1
    const code = `BILL${codes}`
    const made = await h.call('POST', '/merchants/me/coupons', {
      token: store.token,
      body: { code, discountType: 'PERCENTAGE', value: 10, startsAt: new Date(Date.now() - DAY).toISOString() },
    })
    assert.equal(made.status, 200, JSON.stringify(made.body))
    assert.equal((await h.call('POST', '/cart/coupon', { token: who.token, body: { code } })).status, 200)
  }
  const reply = await h.call('POST', '/checkout/place-order', {
    token: who.token,
    headers: { 'idempotency-key': `bill-key-${++keys}` },
    body: { addressId: who.addressId, paymentMethodId: 'pm-cod' },
  })
  assert.equal(reply.status, 200, JSON.stringify(reply.body))
  const order = reply.body.data.order as { id: string; items: { id: string; productId: string }[] }
  const part = (await one<{ id: number }>(h.pool, 'SELECT id FROM order_store_parts WHERE order_id = ? AND store_id = ?', [order.id, store.id]))!.id
  return { who, order, part }
}

/** As [placed], carried to the door and delivered now. */
async function delivered(store: Store, lines: [string, number][], withCode = false) {
  const made = await placed(store, lines, withCode)
  for (const status of ['CONFIRMED', 'PROCESSING', 'SHIPPED', 'DELIVERED']) {
    const extra = status === 'SHIPPED' ? { courierName: 'Haider Salim', courierPhone: '0770 555 0311' } : {}
    const reply = await h.call('PATCH', `/merchants/me/orders/${made.part}/status`, { token: store.token, body: { status, ...extra } })
    assert.equal(reply.status, 200, JSON.stringify(reply.body))
  }
  return made
}

/** A return of [quantity] of the order's first line, approved and handed back now; its id. */
async function refunded(store: Store, sale: Awaited<ReturnType<typeof delivered>>, quantity = 1) {
  const asked = await h.call('POST', '/returns', {
    token: sale.who.token,
    body: { orderId: sale.order.id, reason: 'DAMAGED', items: [{ orderItemId: sale.order.items[0]!.id, quantity }] },
  })
  assert.equal(asked.status, 200, JSON.stringify(asked.body))
  for (const status of ['APPROVED', 'REFUNDED']) {
    assert.equal((await h.call('PATCH', `/merchants/me/returns/${asked.body.data.id}`, { token: store.token, body: { status } })).status, 200)
  }
  return asked.body.data.id as string
}

/** Moves a delivery to [at], and so to its Baghdad month's bill, as if it had arrived then. */
const deliveredAt = (part: number, at: Date) =>
  exec(h.pool, 'UPDATE order_store_parts SET delivered_at = ?, billing_month = ? WHERE id = ?', [at, billingMonth(at), part])
const refundedAt = (returnId: string, at: Date) =>
  exec(h.pool, 'UPDATE returns SET refunded_at = ?, refund_month = ? WHERE id = ?', [at, billingMonth(at), returnId])

const thisMonth = () => billingMonth(new Date())
/** The 15th of [month], at midnight in Baghdad. */
const midst = (month: string) => new Date(dayStart(month).getTime() + 14 * DAY)
const billsOf = async (store: Store) => (await h.call('GET', '/merchants/me/bills', { token: store.token })).body.data
const markPaid = (store: Store, month: string, paidAt: string) =>
  h.call('POST', `/admin/stores/${store.id}/bills/${month.slice(0, 7)}/paid`, { token: admin, body: { paidAt } })
const markNotPaid = (store: Store, month: string) => h.call('DELETE', `/admin/stores/${store.id}/bills/${month.slice(0, 7)}/paid`, { token: admin })

/** A store with one DUE month two months back: one headphone delivered then (145,000, owing 11,600 → 11,500). */
async function owingStore() {
  const store = await openStore()
  const headphones = await product(store)
  const sale = await delivered(store, [[headphones.id, 1]])
  await deliveredAt(sale.part, midst(addMonths(thisMonth(), -2)))
  return { store, headphones }
}

// ------------------------------------------------------------- the store ---

describe("the store's bills", () => {
  test('each month on its own; a refund comes off the month it was handed back and is never carried over; OPEN, NONE, DUE', async () => {
    const store = await openStore()
    const headphones = await product(store)
    const [now, last, twoBack] = [thisMonth(), addMonths(thisMonth(), -1), addMonths(thisMonth(), -2)]

    // Two months back: one headphone with 10% off (130,500) and one without (145,000).
    const coded = await delivered(store, [[headphones.id, 1]], true)
    const plain = await delivered(store, [[headphones.id, 1]])
    // Last month: only the cash for the plain one, handed back.
    const back = await refunded(store, plain)
    await deliveredAt(coded.part, midst(twoBack))
    await deliveredAt(plain.part, midst(twoBack))
    await refundedAt(back, midst(last))
    // This month: two headphones delivered, one handed back.
    const pair = await delivered(store, [[headphones.id, 2]])
    await refunded(store, pair)

    const bills = await billsOf(store)
    assert.equal(bills.currencyCode, 'IQD')
    assert.equal(bills.ratePercent, 8)
    // 8% of 290,000 less 145,000 is 11,600: 11,500.
    assert.deepEqual(bills.current, { month: now, orderCount: 1, sales: 290_000, returned: 145_000, owed: 11_500, status: 'OPEN' })
    assert.deepEqual(bills.past, [
      // More handed back than sold: nothing owed, and nothing taken off another month.
      { month: last, orderCount: 0, sales: 0, returned: 145_000, owed: 0, status: 'NONE' },
      // 8% of 275,500 is 22,040: 22,000. The later refund does not touch it.
      { month: twoBack, orderCount: 2, sales: 275_500, returned: 0, owed: 22_000, status: 'DUE' },
    ])

    // Saba sees the same months, newest first; still owed is the one DUE month.
    const sheet = (await h.call('GET', `/admin/stores/${store.id}/bills`, { token: admin })).body.data
    assert.deepEqual(sheet.bills, [bills.current, ...bills.past])
    assert.equal(sheet.stillOwed, 22_000)
    assert.deepEqual(sheet.store, { id: String(store.id), storeName: store.name, governorate: 'BAGHDAD', status: 'APPROVED' })
    assert.equal(sheet.ratePercent, 8)

    // Closing the store says what it owes: this month so far and every month due.
    const closing = await h.call('PATCH', '/merchants/me/store/open', { token: store.token, body: { isOpen: false } })
    assert.equal(closing.status, 200, JSON.stringify(closing.body))
    assert.equal(closing.body.data.owed, 11_500 + 22_000)
    assert.equal(closing.body.data.openOrders, 0)
  })

  test('a store that has sold nothing has this month, open and empty, and no past', async () => {
    const store = await openStore()
    const bills = await billsOf(store)
    assert.deepEqual(bills.current, { month: thisMonth(), orderCount: 0, sales: 0, returned: 0, owed: 0, status: 'OPEN' })
    assert.deepEqual(bills.past, [])
    assert.equal((await h.call('PATCH', '/merchants/me/store/open', { token: store.token, body: { isOpen: false } })).body.data.owed, 0)
    const who = await shopper()
    assert.equal((await h.call('GET', '/merchants/me/bills', { token: who.token })).status, 403)
  })

  test("the first moment of a Baghdad month is that month's, on the bill and the dashboard alike", async () => {
    const store = await openStore()
    const headphones = await product(store)
    const charger = await product(store, { name: 'Nova Fast Charger 65W', nameAr: 'شاحن نوفا', price: 25_000 })
    const first = await delivered(store, [[headphones.id, 1]])
    const lastMoment = await delivered(store, [[charger.id, 1]])
    // 21:00 UTC the evening before is midnight in Baghdad: this month.
    await deliveredAt(first.part, dayStart(thisMonth()))
    await deliveredAt(lastMoment.part, new Date(dayStart(thisMonth()).getTime() - 1))

    const bills = await billsOf(store)
    assert.deepEqual([bills.current.sales, bills.current.orderCount], [145_000, 1])
    assert.deepEqual([bills.past[0].month, bills.past[0].sales, bills.past[0].owed], [addMonths(thisMonth(), -1), 25_000, 2_000])
    const board = (await h.call('GET', '/merchants/me/dashboard', { token: store.token })).body.data
    assert.deepEqual([board.revenue, board.orderCount], [145_000, 1])
    assert.deepEqual(
      board.salesSeries.slice(-2).map((point: { value: number }) => point.value),
      [25_000, 145_000],
    )
  })
})

// ------------------------------------------------------------ Saba's side ---

describe('Saba marks a month paid', () => {
  test('only a due month, on a day after it ended and not after today; the whole month, once, even four at a time', async () => {
    const { store } = await owingStore()
    const [now, last, twoBack] = [thisMonth(), addMonths(thisMonth(), -1), addMonths(thisMonth(), -2)]
    const today = baghdadDay(new Date())

    // Not a bill that can be paid: this month is still open, last month owes nothing.
    assert.equal((await markPaid(store, now, today)).status, 409)
    assert.equal((await markPaid(store, last, today)).status, 409)
    assert.equal((await markPaid(store, addMonths(now, 1), today)).status, 404)
    assert.equal((await h.call('POST', `/admin/stores/${store.id}/bills/2026-13/paid`, { token: admin, body: { paidAt: today } })).status, 404)
    assert.equal((await h.call('POST', `/admin/stores/${store.id}/bills/soon/paid`, { token: admin, body: { paidAt: today } })).status, 404)
    const waiting = await h.signUpStore('Bills Waiting Store', 'BASRA')
    assert.equal((await h.call('POST', `/admin/stores/${waiting.storeId}/bills/${twoBack.slice(0, 7)}/paid`, { token: admin, body: { paidAt: today } })).status, 404)

    // The day: after the month ended, not after today, a real day.
    for (const day of [addDays(last, -1), addDays(today, 1), `${last.slice(0, 8)}32`, '', 'yesterday']) {
      const refused = await markPaid(store, twoBack, day)
      assert.equal(refused.status, 422, day)
      assert.equal(refused.body.errors.paidAt, 'Pick a day after the month ended, and not after today.')
    }
    assert.equal(Number((await one<{ n: number }>(h.pool, 'SELECT COUNT(*) AS n FROM bill_payments WHERE store_id = ?', [store.id]))!.n), 0)

    // Four at the same moment: one pays it, three are told it is already paid.
    const replies = await Promise.all([1, 2, 3, 4].map(() => markPaid(store, twoBack, last)))
    assert.deepEqual(replies.map((reply) => reply.status).sort(), [200, 409, 409, 409])
    const paid = replies.find((reply) => reply.status === 200)!.body.data
    // The day, at noon in Baghdad.
    assert.deepEqual(paid, { month: twoBack, orderCount: 1, sales: 145_000, returned: 0, owed: 11_500, status: 'PAID', paidAt: `${last}T09:00:00.000Z` })
    const row = await one<{ owed: number; rate_percent: number; paid_on: string }>(
      h.pool,
      "SELECT owed, rate_percent, DATE_FORMAT(paid_on, '%Y-%m-%d') AS paid_on FROM bill_payments WHERE store_id = ?",
      [store.id],
    )
    assert.deepEqual({ ...row }, { owed: 11_500, rate_percent: 8, paid_on: last })
    const audit = await rows<{ action: string; entity_id: string; details: unknown }>(
      h.pool,
      "SELECT action, entity_id, details FROM admin_actions WHERE entity_type = 'BILL' AND entity_id = ?",
      [`${store.id}:${twoBack.slice(0, 7)}`],
    )
    assert.deepEqual(audit, [{ action: 'BILL_PAID', entity_id: `${store.id}:${twoBack.slice(0, 7)}`, details: { owed: 11_500, ratePercent: 8, paidOn: last } }])

    // Paid twice: refused. The store sees it paid, and owes nothing more.
    assert.equal((await markPaid(store, twoBack, today)).status, 409)
    assert.equal((await billsOf(store)).past[0].status, 'PAID')
    const sheet = (await h.call('GET', `/admin/stores/${store.id}/bills`, { token: admin })).body.data
    assert.equal(sheet.stillOwed, 0)
    assert.equal((await h.call('PATCH', '/merchants/me/store/open', { token: store.token, body: { isOpen: false } })).body.data.owed, 0)
  })

  test('marked paid by mistake: due again, once, even four at a time; what the payment said is kept', async () => {
    const { store } = await owingStore()
    const [last, twoBack] = [addMonths(thisMonth(), -1), addMonths(thisMonth(), -2)]
    assert.equal((await markNotPaid(store, twoBack)).status, 409)
    assert.equal((await markPaid(store, twoBack, addDays(last, 2))).status, 200)

    const replies = await Promise.all([1, 2, 3, 4].map(() => markNotPaid(store, twoBack)))
    assert.deepEqual(replies.map((reply) => reply.status).sort(), [200, 409, 409, 409])
    assert.deepEqual(replies.find((reply) => reply.status === 200)!.body.data, {
      month: twoBack,
      orderCount: 1,
      sales: 145_000,
      returned: 0,
      owed: 11_500,
      status: 'DUE',
    })
    const undone = await rows<{ details: { owed: number; paidOn: string; ratePercent: number } }>(
      h.pool,
      "SELECT details FROM admin_actions WHERE entity_type = 'BILL' AND action = 'BILL_UNPAID' AND entity_id = ?",
      [`${store.id}:${twoBack.slice(0, 7)}`],
    )
    assert.equal(undone.length, 1)
    assert.deepEqual([undone[0]!.details.owed, undone[0]!.details.paidOn, undone[0]!.details.ratePercent], [11_500, addDays(last, 2), 8])
    assert.equal((await billsOf(store)).past[0].status, 'DUE')
    assert.equal((await markNotPaid(store, thisMonth())).status, 409)
    // Paid again, as it should have been.
    assert.equal((await markPaid(store, twoBack, last)).status, 200)
    // Only Saba's admins.
    assert.equal((await h.call('DELETE', `/admin/stores/${store.id}/bills/${twoBack.slice(0, 7)}/paid`, { token: store.token })).status, 403)
    assert.equal((await h.call('GET', `/admin/stores/${store.id}/bills`, { token: store.token })).status, 403)
  })
})

describe('Finance', () => {
  const finance = async (query: string) => (await h.call('GET', `/admin/finance${query}`, { token: admin })).body.data
  const rowOf = (data: { rows: { store: { id: string } }[] }, store: Store) => data.rows.find((row) => row.store.id === String(store.id)) as any

  test("one month: each store's bill, the most still owed first; paid and due; the totals are the rows'", async () => {
    const paid = await owingStore()
    const due = await owingStore()
    // Due also owes for a second headphone, and sold one this month.
    const more = await delivered(due.store, [[due.headphones.id, 1]])
    await deliveredAt(more.part, midst(addMonths(thisMonth(), -2)))
    await delivered(due.store, [[due.headphones.id, 1]])
    const [last, twoBack] = [addMonths(thisMonth(), -1), addMonths(thisMonth(), -2)]
    assert.equal((await markPaid(paid.store, twoBack, last)).status, 200)

    const month = await finance(`?month=${twoBack.slice(0, 7)}`)
    assert.equal(month.ratePercent, 8)
    assert.deepEqual(
      (({ orderCount, sales, returned, owed, paid: taken, stillOwed, status, paidAt }) => ({ orderCount, sales, returned, owed, taken, stillOwed, status, paidAt }))(rowOf(month, paid.store)),
      { orderCount: 1, sales: 145_000, returned: 0, owed: 11_500, taken: 11_500, stillOwed: 0, status: 'PAID', paidAt: `${last}T09:00:00.000Z` },
    )
    // 8% of 290,000 is 23,200: 23,250.
    const owing = rowOf(month, due.store)
    assert.deepEqual([owing.orderCount, owing.sales, owing.owed, owing.paid, owing.stillOwed, owing.status], [2, 290_000, 23_250, 0, 23_250, 'DUE'])
    assert.equal(owing.paidAt, undefined)
    assert.deepEqual(owing.store, { id: String(due.store.id), storeName: due.store.name, governorate: 'BAGHDAD', status: 'APPROVED' })
    // The most still owed first, then the most owed.
    assert.ok(month.rows.every((row: any, i: number) => i === 0 || month.rows[i - 1].stillOwed > row.stillOwed || (month.rows[i - 1].stillOwed === row.stillOwed && month.rows[i - 1].owed >= row.owed)))
    const sum = (list: any[], key: string) => list.reduce((total, row) => total + row[key], 0)
    assert.deepEqual(month.totals, { owed: sum(month.rows, 'owed'), paid: sum(month.rows, 'paid'), stillOwed: sum(month.rows, 'stillOwed') })
    // Every store that can sell, or did.
    const selling = Number((await one<{ n: number }>(h.pool, "SELECT COUNT(*) AS n FROM stores WHERE status IN ('APPROVED', 'SUSPENDED')"))!.n)
    assert.equal(month.counts.all, selling)
    assert.equal(month.rows.length, selling)
    assert.equal(month.counts.PAID, month.rows.filter((row: any) => row.status === 'PAID').length)
    assert.equal(month.counts.DUE, month.rows.filter((row: any) => row.stillOwed > 0).length)

    // Filtered: the counts stay every store's; the totals are what is shown.
    const dueOnly = await finance(`?month=${twoBack.slice(0, 7)}&paid=DUE`)
    assert.ok(dueOnly.rows.length > 0 && dueOnly.rows.every((row: any) => row.stillOwed > 0))
    assert.ok(rowOf(dueOnly, due.store) && !rowOf(dueOnly, paid.store))
    assert.deepEqual(dueOnly.counts, month.counts)
    assert.equal(dueOnly.totals.stillOwed, month.totals.stillOwed)
    assert.equal(dueOnly.totals.paid, 0)
    const paidOnly = await finance(`?month=${twoBack.slice(0, 7)}&paid=PAID`)
    assert.ok(paidOnly.rows.every((row: any) => row.status === 'PAID'))
    assert.ok(rowOf(paidOnly, paid.store) && !rowOf(paidOnly, due.store))
  })

  test('every closed month added up; the months; this month and last month over every store', async () => {
    const { store, headphones } = await owingStore()
    const [now, last, twoBack] = [thisMonth(), addMonths(thisMonth(), -1), addMonths(thisMonth(), -2)]
    // Another headphone last month, and a charger this month.
    const lastSale = await delivered(store, [[headphones.id, 1]])
    await deliveredAt(lastSale.part, midst(last))
    await delivered(store, [[(await product(store, { name: 'Nova Fast Charger 65W', nameAr: 'شاحن نوفا', price: 25_000 })).id, 1]])

    const past = await finance('?month=past')
    const current = await finance(`?month=${now.slice(0, 7)}`)
    const before = await finance(`?month=${last.slice(0, 7)}`)
    const row = rowOf(past, store)
    // The two closed months; this month is not closed.
    assert.deepEqual([row.orderCount, row.sales, row.owed, row.paid, row.stillOwed, row.status, row.paidAt], [2, 290_000, 23_000, 0, 23_000, 'DUE', undefined])

    // This month and last month add up every store's bill.
    const sum = (list: any[], key: string) => list.reduce((total, one) => total + one[key], 0)
    assert.deepEqual(past.thisMonth, { month: now, orderCount: sum(current.rows, 'orderCount'), sales: sum(current.rows, 'sales'), owed: sum(current.rows, 'owed') })
    assert.ok(current.rows.every((one: any) => one.status === 'OPEN'))
    assert.equal(rowOf(current, store).sales, 25_000)
    assert.deepEqual(past.lastMonth, { month: last, owed: sum(before.rows, 'owed'), collected: sum(before.rows, 'paid'), stillOwed: sum(before.rows, 'stillOwed') })
    assert.ok(past.lastMonth.stillOwed >= 11_500)

    // Due while any month is; paid once every month is.
    assert.equal((await markPaid(store, twoBack, last)).status, 200)
    const partly = rowOf(await finance('?month=past'), store)
    assert.deepEqual([partly.paid, partly.stillOwed, partly.status], [11_500, 11_500, 'DUE'])
    assert.equal((await markPaid(store, last, now)).status, 200)
    const settled = rowOf(await finance('?month=past'), store)
    assert.deepEqual([settled.paid, settled.stillOwed, settled.status, settled.paidAt], [23_000, 0, 'PAID', undefined])
    assert.equal((await finance('?month=past')).lastMonth.collected, sum((await finance(`?month=${last.slice(0, 7)}`)).rows, 'paid'))

    // Newest first, month by month, from the first delivery to this month.
    assert.equal(past.months[0], now)
    assert.ok(past.months.includes(twoBack))
    assert.ok(past.months.every((month: string, i: number) => i === 0 || month === addMonths(past.months[i - 1], -1)))
    const first = (await one<{ month: string }>(h.pool, "SELECT DATE_FORMAT(MIN(billing_month), '%Y-%m-%d') AS month FROM order_store_parts"))!.month
    assert.equal(past.months.at(-1), first)

    // A suspended store stays in Finance.
    assert.equal((await h.call('POST', `/admin/stores/${store.id}/suspend`, { token: admin, body: { reason: 'Unpaid bills.' } })).status, 200)
    assert.equal(rowOf(await finance('?month=past'), store).store.status, 'SUSPENDED')
    assert.equal((await h.call('GET', `/admin/stores/${store.id}/bills`, { token: admin })).status, 200)

    for (const bad of ['?month=2099-01', '?month=2026-13', '?month=soon', '']) {
      assert.equal((await h.call('GET', `/admin/finance${bad}`, { token: admin })).status, 422, bad)
    }
    assert.equal((await h.call('GET', '/admin/finance?month=past', { token: store.token })).status, 403)
  })
})

// ----------------------------------------------------- dashboard, Analytics ---

describe("the store's dashboard and Analytics", () => {
  test('this month so far against the same days of last month; what waits; six months of sales', async () => {
    const store = await openStore()
    const headphones = await product(store)
    await product(store, { name: 'Nova Cable', nameAr: 'كابل نوفا', price: 5_000, stock: 3 })
    await product(store, { name: 'Nova Case', nameAr: 'غطاء نوفا', price: 10_000, stock: 0 }, false)
    const refused = await product(store, { name: 'Nova Copy', nameAr: 'نسخة نوفا', price: 10_000, stock: 10 }, false)
    assert.equal((await h.call('POST', `/admin/products/${refused.id}/reject`, { token: admin, body: { reason: 'Photos missing.' } })).status, 200)

    // This month: 130,500 with the code, 145,000, and 145,000 of which the cash came back.
    const coded = await delivered(store, [[headphones.id, 1]], true)
    await delivered(store, [[headphones.id, 1]])
    const returned = await delivered(store, [[headphones.id, 1]])
    await refunded(store, returned)
    // One return waiting for an answer; one order waiting to be confirmed, placed five hours ago.
    const asked = await h.call('POST', '/returns', {
      token: coded.who.token,
      body: { orderId: coded.order.id, reason: 'DAMAGED', items: [{ orderItemId: coded.order.items[0]!.id, quantity: 1 }] },
    })
    assert.equal(asked.status, 200)
    const waiting = await placed(store, [[headphones.id, 1]])
    await exec(h.pool, 'UPDATE orders SET placed_at = ? WHERE id = ?', [new Date(Date.now() - 5 * HOUR - 60_000), waiting.order.id])
    // Last month, on its first moment: inside the same stretch whatever today is.
    const earlier = await delivered(store, [[headphones.id, 1]])
    const lastMonth = addMonths(thisMonth(), -1)
    await deliveredAt(earlier.part, dayStart(lastMonth))
    // The shopper's stars.
    assert.equal((await h.call('POST', `/orders/${coded.order.id}/rating`, { token: coded.who.token, body: { ratings: { [store.storeId]: 4 } } })).status, 200)

    const board = (await h.call('GET', '/merchants/me/dashboard', { token: store.token })).body.data
    const day = Number(baghdadDay(new Date()).slice(8))
    const lastMonthDays = Math.round((dayStart(thisMonth()).getTime() - dayStart(lastMonth).getTime()) / DAY)
    assert.deepEqual(
      (({ salesSeries, ...rest }) => rest)(board),
      {
        currencyCode: 'IQD',
        revenue: 130_500 + 145_000 + 145_000,
        orderCount: 3,
        productCount: 4,
        pendingOrders: 1,
        lowStockCount: 1,
        outOfStockCount: 1,
        rejectedCount: 1,
        returnCount: 1,
        refundTotal: 145_000,
        isOpen: true,
        previousRevenue: 145_000,
        comparisonDays: Math.min(day, lastMonthDays),
        orderCountDelta: 2,
        oldestPendingHours: 5,
        rating: 4,
        ratingCount: 1,
      },
    )
    // Six months, this one last, each named by the Baghdad day it starts.
    assert.deepEqual(
      board.salesSeries,
      [5, 4, 3, 2, 1, 0].map((back) => ({
        label: `M-${back}`,
        from: addMonths(thisMonth(), -back),
        unit: 'MONTH',
        value: back === 0 ? 420_500 : back === 1 ? 145_000 : 0,
      })),
    )
    // The bill counts the same sales.
    assert.equal((await billsOf(store)).current.sales, board.revenue)
  })

  test('a store that has sold nothing: no chart, nothing to compare, no rating', async () => {
    const store = await openStore()
    const board = (await h.call('GET', '/merchants/me/dashboard', { token: store.token })).body.data
    assert.deepEqual([board.revenue, board.orderCount, board.salesSeries], [0, 0, []])
    assert.equal(board.previousRevenue, undefined)
    assert.equal(board.rating, undefined)
    assert.equal(board.oldestPendingHours, undefined)
    const week = (await h.call('GET', '/merchants/me/analytics?period=week', { token: store.token })).body.data
    assert.deepEqual([week.revenue, week.series, week.topProducts, week.averageOrderValue], [0, [], [], 0])
  })

  test('Analytics: this week by day, this month by week, this year by month; best sellers; cancellations', async () => {
    const store = await openStore()
    const headphones = await product(store)
    const charger = await product(store, { name: 'Nova Fast Charger 65W', nameAr: 'شاحن نوفا', price: 25_000 })
    await delivered(store, [[headphones.id, 2]])
    const plug = await delivered(store, [[charger.id, 1]])
    await refunded(store, plug)
    const declined = await placed(store, [[charger.id, 1]])
    assert.equal(
      (await h.call('PATCH', `/merchants/me/orders/${declined.part}/status`, { token: store.token, body: { status: 'CANCELLED', reason: 'OUT_OF_STOCK' } })).status,
      200,
    )
    // Two weeks back, at the start of last week's same stretch.
    const today = baghdadDay(new Date())
    const old = await delivered(store, [[charger.id, 1]])
    const oldAt = dayStart(addDays(today, -13))
    await deliveredAt(old.part, oldAt)
    const oldThisMonth = oldAt >= dayStart(thisMonth())
    const oldThisYear = oldAt >= dayStart(`${today.slice(0, 4)}-01-01`)
    const analytics = async (period: string) => (await h.call('GET', `/merchants/me/analytics?period=${period}`, { token: store.token })).body.data

    const week = await analytics('week')
    assert.deepEqual(
      [week.revenue, week.previousRevenue, week.orderCount, week.productsSold, week.averageOrderValue, week.refundTotal, week.cancellationCount],
      [315_000, 25_000, 2, 3, 157_500, 25_000, 1],
    )
    assert.deepEqual(
      week.series,
      [0, 1, 2, 3, 4, 5, 6].map((i) => ({ label: `D${i + 1}`, from: addDays(today, i - 6), unit: 'DAY', value: i === 6 ? 315_000 : 0 })),
    )
    assert.deepEqual(
      week.topProducts.map((row: { id: string; name: string; stock: number }) => [row.id, row.name]),
      [[headphones.id, 'Kite Studio Headphones'], [charger.id, 'Nova Fast Charger 65W']],
    )
    // In Arabic, the shelf's own names.
    assert.equal((await h.call('GET', '/merchants/me/analytics?period=week', { token: store.token, lang: 'ar' })).body.data.topProducts[0].name, 'سماعات كايت ستوديو')

    const month = await analytics('month')
    assert.equal(month.revenue, 315_000 + (oldThisMonth ? 25_000 : 0))
    assert.equal(month.series.length, Math.ceil(Number(today.slice(8)) / 7))
    assert.ok(month.series.every((point: { label: string; from: string; unit: string }, i: number) => point.label === `W${i + 1}` && point.from === addDays(thisMonth(), 7 * i) && point.unit === 'WEEK'))
    assert.equal(month.series.reduce((sum: number, point: { value: number }) => sum + point.value, 0), month.revenue)

    const year = await analytics('year')
    assert.equal(year.revenue, 315_000 + (oldThisYear ? 25_000 : 0))
    assert.equal(year.series.length, Number(today.slice(5, 7)))
    assert.ok(year.series.every((point: { label: string; from: string; unit: string }, i: number) => point.label === `M${i + 1}` && point.from === addMonths(`${today.slice(0, 4)}-01-01`, i) && point.unit === 'MONTH'))
    assert.equal(year.series.reduce((sum: number, point: { value: number }) => sum + point.value, 0), year.revenue)

    assert.equal((await h.call('GET', '/merchants/me/analytics?period=decade', { token: store.token })).status, 422)
  })
})

// ------------------------------------------------ a store owner deletes the account ---

describe('a store owner deletes their account', () => {
  const sent: [phone: string, text: string][] = []
  const run = (sendText: SendText = async (phone, text) => void sent.push([phone, text])) =>
    finishStoreDeletions({ pool: h.pool, media: diskStore(h.mediaDir), sendText, logger: memoryLogger().logger })
  const statusOf = async (store: { storeId: string }) =>
    (await one<{ status: string }>(h.pool, 'SELECT status FROM stores WHERE id = ?', [store.storeId]))!.status
  const ask = async (store: { token: string }) => {
    const asked = await h.call('POST', '/merchants/me/deletion', { token: store.token })
    assert.equal(asked.status, 200, JSON.stringify(asked.body))
    return asked.body.data
  }
  /** What is left, without the day it was asked. */
  const left = async (store: Store) => {
    const { requestedAt, currencyCode, ...figures } = (await h.call('GET', '/merchants/me/deletion', { token: store.token })).body.data
    return figures
  }
  /** Long enough ago that its month is closed and its return window long past. */
  const lastMonth = () => new Date(Date.now() - 40 * DAY)
  const pay = (store: Store) =>
    h.call('POST', `/admin/stores/${store.id}/bills/${billingMonth(lastMonth()).slice(0, 7)}/paid`, {
      token: admin,
      body: { paidAt: baghdadDay(new Date()) },
    })
  async function upload(token: string): Promise<string> {
    const form = new FormData()
    form.append('file', new Blob([new Uint8Array(PNG)]), 'p.png')
    const reply = await h.call('POST', '/media/upload', { token, form })
    assert.equal(reply.status, 200, JSON.stringify(reply.body))
    return reply.body.data.url
  }

  test('asking closes the store at once; the switch stays shut until the owner cancels; asked twice, the first day stands', async () => {
    const store = await openStore()
    await delivered(store, [[(await product(store)).id, 1]])
    const { requestedAt, returnsOpenUntil, ...rest } = await ask(store)
    assert.ok(requestedAt && returnsOpenUntil)
    // 8% of 145,000, to the nearest 250: 11,500.
    assert.deepEqual(rest, { openOrders: 0, openReturns: 0, owed: 11_500, currencyCode: 'IQD' })
    assert.equal((await h.call('GET', '/merchants/me/store', { token: store.token })).body.data.isOpen, false)
    assert.equal((await ask(store)).requestedAt, requestedAt)
    assert.equal((await h.call('GET', '/merchants/me/deletion', { token: store.token })).body.data.requestedAt, requestedAt)
    assert.equal((await h.call('GET', '/customers/me', { token: store.token })).body.data.merchant.deletionRequestedAt, requestedAt)
    assert.equal((await h.call('GET', `/admin/stores/${store.id}`, { token: admin })).body.data.deletionRequestedAt, requestedAt)

    const reopen = await h.call('PATCH', '/merchants/me/store/open', { token: store.token, body: { isOpen: true } })
    assert.equal(reopen.status, 409)
    assert.equal(reopen.body.message, "Your store's account is being deleted. Cancel the deletion to open it again.")
    assert.equal((await h.call('PATCH', '/merchants/me/store/open', { token: store.token, body: { isOpen: false } })).status, 200)

    assert.deepEqual((await h.call('DELETE', '/merchants/me/deletion', { token: store.token })).body.data, {})
    assert.equal((await h.call('GET', '/merchants/me/deletion', { token: store.token })).body.data.requestedAt, null)
    assert.equal((await h.call('GET', '/customers/me', { token: store.token })).body.data.merchant.deletionRequestedAt, null)
    // Still closed: its owner opens it.
    assert.equal((await h.call('GET', '/merchants/me/store', { token: store.token })).body.data.isOpen, false)
    assert.equal((await h.call('PATCH', '/merchants/me/store/open', { token: store.token, body: { isOpen: true } })).status, 200)
    await run()
    assert.equal(await statusOf(store), 'APPROVED')
  })

  test('the hourly run waits for open orders, open returns, the last return window and every bill paid; then the store goes', async () => {
    // Each store waits on one thing only.
    const ordering = await openStore()
    const open = await placed(ordering, [[(await product(ordering)).id, 1]])

    const returning = await openStore()
    const sold = await delivered(returning, [[(await product(returning)).id, 1]])
    const asked = await h.call('POST', '/returns', {
      token: sold.who.token,
      body: { orderId: sold.order.id, reason: 'DAMAGED', items: [{ orderItemId: sold.order.items[0]!.id, quantity: 1 }] },
    })
    assert.equal(asked.status, 200, JSON.stringify(asked.body))
    await deliveredAt(sold.part, lastMonth())
    assert.equal((await pay(returning)).status, 200)

    // 8% of 1,000 rounds to nothing: only its return window keeps it.
    const recent = await openStore()
    const small = await delivered(recent, [[(await product(recent, { price: 1000 })).id, 1]])

    const owing = await openStore()
    await deliveredAt((await delivered(owing, [[(await product(owing)).id, 1]])).part, lastMonth())

    for (const store of [ordering, returning, recent, owing]) await ask(store)
    assert.deepEqual(await left(ordering), { openOrders: 1, openReturns: 0, returnsOpenUntil: null, owed: 0 })
    assert.deepEqual(await left(returning), { openOrders: 0, openReturns: 1, returnsOpenUntil: null, owed: 0 })
    const window = await left(recent)
    assert.ok(window.returnsOpenUntil)
    assert.deepEqual({ ...window, returnsOpenUntil: null }, { openOrders: 0, openReturns: 0, returnsOpenUntil: null, owed: 0 })
    assert.deepEqual(await left(owing), { openOrders: 0, openReturns: 0, returnsOpenUntil: null, owed: 11_500 })

    await run()
    for (const store of [ordering, returning, recent, owing]) assert.equal(await statusOf(store), 'APPROVED')

    // Each finished: the order cancelled, the return refunded, the window passed, the bill paid.
    const cancelled = await h.call('PATCH', `/merchants/me/orders/${open.part}/status`, {
      token: ordering.token,
      body: { status: 'CANCELLED', reason: 'OUT_OF_STOCK' },
    })
    assert.equal(cancelled.status, 200, JSON.stringify(cancelled.body))
    for (const status of ['APPROVED', 'REFUNDED']) {
      assert.equal((await h.call('PATCH', `/merchants/me/returns/${asked.body.data.id}`, { token: returning.token, body: { status } })).status, 200)
    }
    await exec(h.pool, 'UPDATE order_store_parts SET delivered_at = ? WHERE id = ?', [new Date(Date.now() - 8 * DAY), small.part])
    assert.equal((await pay(owing)).status, 200)

    await run()
    for (const store of [ordering, returning, recent, owing]) assert.equal(await statusOf(store), 'CLOSED')
  })

  test('what goes and what stays: the page, products, codes, logo and account go; orders, bills and product photos stay; the owner is told', async () => {
    const store = await openStore()
    const logo = await upload(store.token)
    const saved = await h.call('PUT', '/merchants/me/store', {
      token: store.token,
      body: {
        storeName: store.name,
        businessAddress: 'Karrada, near the park',
        governorate: 'BAGHDAD',
        logoUrl: logo,
        delivery: { governorates: [], feeInside: 3000, timeInside: '1_2_DAYS' },
      },
    })
    assert.equal(saved.status, 200, JSON.stringify(saved.body))
    assert.equal(saved.body.data.businessAddress, 'Karrada, near the park')
    const photo = await upload(store.token)
    const made = await product(store, { images: [photo] })
    const waiting = await product(store, {}, false)
    // A banner that is also a product's photo (a seeded store can have one).
    await exec(h.pool, 'UPDATE stores SET banner_url = ? WHERE id = ?', [keyOf(photo, undefined), store.id])
    assert.equal((await h.call('PUT', '/admin/featured-stores', { token: admin, body: { storeIds: [store.storeId] } })).status, 200)
    const queued = (await h.call('GET', '/admin/queue', { token: admin })).body.data
    assert.ok(queued.products.some((item: { id: string }) => item.id === waiting.id))
    const sale = await delivered(store, [[made.id, 1]], true)
    await deliveredAt(sale.part, lastMonth())
    assert.equal((await pay(store)).status, 200)
    // Another shopper still has it in the cart and the wishlist.
    const other = await shopper()
    assert.equal((await h.call('POST', '/cart/items', { token: other.token, body: { productId: made.id, quantity: 1 } })).status, 200)
    assert.equal((await h.call('POST', '/wishlist/items', { token: other.token, body: { productId: made.id } })).status, 200)

    await ask(store)
    const told = sent.length
    await run()
    assert.equal(await statusOf(store), 'CLOSED')

    // Gone.
    assert.equal((await h.call('GET', `/merchants/${store.id}/store`)).status, 404)
    assert.equal((await h.call('GET', `/products/${made.id}`)).status, 404)
    assert.equal(Number((await one<{ n: number }>(h.pool, 'SELECT COUNT(*) AS n FROM cart_items WHERE user_id = ?', [other.id]))!.n), 0)
    assert.equal(Number((await one<{ n: number }>(h.pool, 'SELECT COUNT(*) AS n FROM wishlist_items WHERE user_id = ?', [other.id]))!.n), 0)
    assert.equal(Number((await one<{ n: number }>(h.pool, 'SELECT COUNT(*) AS n FROM coupons WHERE store_id = ?', [store.id]))!.n), 0)
    assert.equal(Number((await one<{ n: number }>(h.pool, 'SELECT COUNT(*) AS n FROM featured_stores WHERE store_id = ?', [store.id]))!.n), 0)
    const queue = (await h.call('GET', '/admin/queue', { token: admin })).body.data
    assert.ok(!queue.products.some((item: { id: string }) => item.id === waiting.id))
    assert.deepEqual(await one(h.pool, 'SELECT status, phone, email, full_name, password_hash FROM users WHERE id = ?', [store.ownerId]), {
      status: 'DELETED',
      phone: null,
      email: null,
      full_name: '',
      password_hash: null,
    })
    assert.equal((await h.call('GET', '/customers/me', { token: store.token })).status, 401)
    // The number has no account any more: free to sign up again.
    const signIn = await h.call('POST', '/auth/login', { body: { phone: store.phone, password: PASSWORD } })
    assert.deepEqual([signIn.status, signIn.body.code], [422, 'VALIDATION_ERROR'])
    const logoKey = keyOf(logo, undefined)!
    await assert.rejects(access(path.join(h.mediaDir, logoKey)))
    assert.ok((await one<{ deleted_at: Date | null }>(h.pool, 'SELECT deleted_at FROM media_files WHERE storage_key = ?', [logoKey]))!.deleted_at)
    // Told once, in both languages, on the number it had.
    assert.deepEqual(sent.slice(told), [
      [
        store.phone,
        `سبأ: حُذف حساب متجرك «${store.name}». نحتفظ بسجلات الطلبات والفواتير كما يطلب القانون.\n` +
          `Saba: your store's account (${store.name}) has been deleted. Order, invoice and bill records are kept as the law requires.`,
      ],
    ])

    // Kept: the order with its code, its photo and the store's name; the paid bill in Finance.
    const order = await h.call('GET', `/orders/${sale.order.id}`, { token: sale.who.token })
    assert.equal(order.status, 200, JSON.stringify(order.body))
    assert.equal((await one<{ coupon_code: string | null }>(h.pool, 'SELECT coupon_code FROM orders WHERE id = ?', [sale.order.id]))!.coupon_code, `BILL${codes}`)
    await access(path.join(h.mediaDir, keyOf(photo, undefined)!))
    assert.equal((await one<{ store_name: string }>(h.pool, 'SELECT store_name FROM order_items WHERE order_id = ?', [sale.order.id]))!.store_name, store.name)
    const record = (await h.call('GET', `/admin/stores/${store.id}`, { token: admin })).body.data
    assert.equal(record.status, 'CLOSED')
    assert.ok(record.closedAt && record.deletionRequestedAt)
    assert.deepEqual([record.phone, record.businessAddress, record.logoUrl, record.bannerUrl], ['', undefined, undefined, undefined])
    const finance = await h.call('GET', `/admin/finance?month=${billingMonth(lastMonth()).slice(0, 7)}`, { token: admin })
    assert.equal(finance.status, 200, JSON.stringify(finance.body))
    const row = finance.body.data.rows.find((line: { store: { id: string } }) => line.store.id === store.storeId)
    // 8% of 130,500 (145,000 less its 10% code), to the nearest 250: 10,500.
    assert.deepEqual([row?.store.status, row?.status, row?.paid], ['CLOSED', 'PAID', 10_500])
  })

  test("Saba starts it at the owner's request (support): the store closes, the owner is told and can cancel; twice is 409; then the hourly run as usual", async () => {
    const store = await openStore()
    const started = await h.call('POST', `/admin/stores/${store.id}/deletion`, { token: admin })
    assert.equal(started.status, 200, JSON.stringify(started.body))
    const { deletionRequestedAt, isOpen } = started.body.data
    assert.ok(deletionRequestedAt)
    assert.equal(isOpen, false)
    assert.equal((await h.call('GET', '/merchants/me/deletion', { token: store.token })).body.data.requestedAt, deletionRequestedAt)
    const told = (await h.call('GET', '/notifications', { token: store.token })).body.data[0]
    assert.deepEqual([told.title, told.body], [
      "Your store's account is being deleted",
      "Saba started it at your request, and your store is closed. If you didn't ask, cancel it in the app.",
    ])
    assert.equal((await h.call('POST', `/admin/stores/${store.id}/deletion`, { token: admin })).status, 409)
    assert.equal((await h.call('POST', '/admin/stores/999999/deletion', { token: admin })).status, 404)
    const audits = await rows<{ action: string }>(h.pool, "SELECT action FROM admin_actions WHERE entity_type = 'STORE' AND entity_id = ? AND action = 'STORE_DELETION'", [
      String(store.id),
    ])
    assert.equal(audits.length, 1)

    // The owner never asked: they cancel in the app.
    assert.equal((await h.call('DELETE', '/merchants/me/deletion', { token: store.token })).status, 200)
    assert.equal((await h.call('GET', '/merchants/me/deletion', { token: store.token })).body.data.requestedAt, null)
    // Asked again through Saba; nothing is left, so the hourly run deletes it; then there is nothing to start.
    assert.equal((await h.call('POST', `/admin/stores/${store.id}/deletion`, { token: admin })).status, 200)
    await run()
    assert.equal(await statusOf(store), 'CLOSED')
    assert.equal((await h.call('POST', `/admin/stores/${store.id}/deletion`, { token: admin })).status, 409)
  })

  test('a store that never sold goes at the next run, even one still waiting for an answer; an SMS that fails does not stop it', async () => {
    const store = await h.signUpStore('Never Sold')
    // Nothing left to finish either, but its owner changed their mind.
    const staying = await h.signUpStore('Never Sold Either')
    await ask(store)
    await ask(staying)
    assert.equal((await h.call('DELETE', '/merchants/me/deletion', { token: staying.token })).status, 200)
    const { logger, lines } = memoryLogger()
    const sendText: SendText = async () => {
      throw new Error('the gateway is down')
    }
    await finishStoreDeletions({ pool: h.pool, media: diskStore(h.mediaDir), sendText, logger })
    assert.equal(await statusOf(store), 'CLOSED')
    assert.equal(await statusOf(staying), 'PENDING')
    // Only the SMS went wrong: no store's deletion failed.
    const logged = lines.join('\n')
    assert.match(logged, /the store-deleted SMS was not sent/)
    assert.doesNotMatch(logged, /store deletion failed/)
  })
})
