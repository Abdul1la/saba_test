// S5 Returns and people (BACKEND_PLAN.md §7): a return asked for, answered and
// refunded; Saba's cancellations and returns, customers and their suspension,
// and the dashboard. One return per line, even at the same moment; refunds at
// the paid price; the 7-day window; a suspended shopper can't sign in or order.
import assert from 'node:assert/strict'
import { after, before, describe, test } from 'node:test'
import { exec, one, rows } from '../src/db/sql.js'
import { billingMonth } from '../src/lib/money.js'
import { PASSWORD, startHarness, type Harness } from './api.js'

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
async function openStore(governorate = 'BAGHDAD') {
  stores += 1
  const name = `Returns Store ${stores}`
  const store = await h.signUpStore(name, governorate)
  assert.equal((await h.call('POST', `/admin/stores/${store.storeId}/approve`, { token: admin })).status, 200)
  const saved = await h.call('PUT', '/merchants/me/store', {
    token: store.token,
    body: { storeName: name, governorate, logoUrl: null, delivery: { governorates: [], feeInside: 3000, timeInside: '1_2_DAYS' } },
  })
  assert.equal(saved.status, 200, JSON.stringify(saved.body))
  return { ...store, name, id: Number(store.storeId) }
}
type Store = Awaited<ReturnType<typeof openStore>>

async function listed(store: Store, extra: Record<string, unknown> = {}) {
  const made = await h.call('POST', '/merchants/me/products', {
    token: store.token,
    body: { name: 'Kite Studio Headphones', nameAr: 'سماعات كايت ستوديو', categoryId: SMARTPHONES, price: 145_000, stock: 10, ...extra },
  })
  assert.equal(made.status, 200, JSON.stringify(made.body))
  assert.equal((await h.call('POST', `/admin/products/${made.body.data.id}/approve`, { token: admin })).status, 200)
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

async function add(who: Shopper, productId: string, quantity = 1) {
  assert.equal((await h.call('POST', '/cart/items', { token: who.token, body: { productId, quantity } })).status, 200)
}

let keys = 0
async function placed(who: Shopper) {
  const reply = await h.call('POST', '/checkout/place-order', {
    token: who.token,
    headers: { 'idempotency-key': `return-key-${++keys}` },
    body: { addressId: who.addressId, paymentMethodId: 'pm-cod' },
  })
  assert.equal(reply.status, 200, JSON.stringify(reply.body))
  return reply.body.data.order as { id: string; orderNumber: string; items: { id: string; productId: string; quantity: number }[] }
}

let codes = 0
async function tenPercent(store: Store, who: Shopper) {
  codes += 1
  const code = `BACK${codes}`
  const made = await h.call('POST', '/merchants/me/coupons', {
    token: store.token,
    body: { code, discountType: 'PERCENTAGE', value: 10, startsAt: new Date(Date.now() - DAY).toISOString() },
  })
  assert.equal(made.status, 200, JSON.stringify(made.body))
  assert.equal((await h.call('POST', '/cart/coupon', { token: who.token, body: { code } })).status, 200)
}

const partOf = async (orderId: string, store: Store) =>
  (await one<{ id: number }>(h.pool, 'SELECT id FROM order_store_parts WHERE order_id = ? AND store_id = ?', [orderId, store.id]))!.id

async function walk(store: Store, partId: number, until: 'SHIPPED' | 'DELIVERED' = 'DELIVERED') {
  const path = ['CONFIRMED', 'PROCESSING', 'SHIPPED', 'DELIVERED']
  for (const status of path.slice(0, path.indexOf(until) + 1)) {
    const extra = status === 'SHIPPED' ? { courierName: 'Haider Salim', courierPhone: '0770 555 0311' } : {}
    const reply = await h.call('PATCH', `/merchants/me/orders/${partId}/status`, { token: store.token, body: { status, ...extra } })
    assert.equal(reply.status, 200, JSON.stringify(reply.body))
  }
}

/** A delivered order of [lines] from [store], for a new shopper. */
async function delivered(store: Store, lines: [productId: string, quantity: number][], withCode = false) {
  const who = await shopper()
  for (const [productId, quantity] of lines) await add(who, productId, quantity)
  if (withCode) await tenPercent(store, who)
  const order = await placed(who)
  const partId = await partOf(order.id, store)
  await walk(store, partId)
  return { who, order, partId }
}

const ask = (who: Shopper, orderId: string, items: [orderItemId: string, quantity: number][], extra: Record<string, unknown> = {}) =>
  h.call('POST', '/returns', {
    token: who.token,
    body: { orderId, reason: 'DAMAGED', items: items.map(([orderItemId, quantity]) => ({ orderItemId, quantity })), ...extra },
  })

async function asked(who: Shopper, orderId: string, items: [string, number][], extra: Record<string, unknown> = {}) {
  const reply = await ask(who, orderId, items, extra)
  assert.equal(reply.status, 200, JSON.stringify(reply.body))
  return reply.body.data
}

const answer = (store: Store, returnId: string, status: string, reason?: string) =>
  h.call('PATCH', `/merchants/me/returns/${returnId}`, { token: store.token, body: { status, ...(reason && { reason }) } })

const stockOf = async (productId: string) =>
  Number((await one<{ n: number }>(h.pool, 'SELECT SUM(stock) AS n FROM product_skus WHERE product_id = ? AND deleted_at IS NULL', [productId]))!.n)

const returnLedger = (productId: string) =>
  rows<{ delta: number; part_id: number; return_id: number }>(
    h.pool,
    `SELECT m.delta, m.part_id, m.return_id FROM stock_movements m JOIN product_skus k ON k.id = m.sku_id
      WHERE k.product_id = ? AND m.reason = 'RETURN_REFUNDED' ORDER BY m.id`,
    [productId],
  )

const lastNotice = (userId: number) =>
  one<{ title_en: string; body_en: string; title_ar: string; entity_type: string; entity_id: string }>(
    h.pool,
    'SELECT title_en, body_en, title_ar, entity_type, entity_id FROM notifications WHERE user_id = ? ORDER BY id DESC LIMIT 1',
    [userId],
  )

// ---------------------------------------------------------- asking for one ---

describe('asking for a return', () => {
  test('the refund is what was paid: 2 of 3 NOVA10 headphones and a charger come back at 283,500; nothing moves yet', async () => {
    const store = await openStore()
    const headphones = await listed(store)
    const charger = await listed(store, { name: 'Nova Fast Charger 65W', nameAr: 'شاحن نوفا', price: 25_000 })
    const { who, order, partId } = await delivered(store, [[headphones.id, 3], [charger.id, 1]], true)
    const [phones, plug] = [order.items.find((i) => i.productId === headphones.id)!, order.items.find((i) => i.productId === charger.id)!]

    const made = await asked(who, order.id, [[phones.id, 2], [plug.id, 1]], { description: 'The left ear crackles.' })
    // 460,000 less 10% is 414,000: a headphone was paid 130,500, the charger 22,500.
    assert.equal(made.refundAmount, 2 * 130_500 + 22_500)
    assert.deepEqual(
      made.items.map((item: { quantity: number; refundAmount: number }) => [item.quantity, item.refundAmount]),
      [[2, 261_000], [1, 22_500]],
    )
    assert.equal(made.status, 'REQUESTED')
    assert.equal(made.itemCount, 3)
    assert.equal(made.merchantName, store.name)
    assert.equal(made.description, 'The left ear crackles.')
    assert.deepEqual(made.refund, { amount: 283_500, currencyCode: 'IQD', status: 'PENDING', method: 'Cash, from the store', processedAt: null })
    assert.deepEqual(
      made.timeline.map((step: { status: string; noteCode: string | null }) => [step.status, step.noteCode]),
      [['REQUESTED', 'RETURN_REQUESTED']],
    )
    // No stock moves until the cash is handed back.
    assert.equal(await stockOf(headphones.id), 7)
    // The order stays delivered (Q8); its lines can't go back again.
    const now = (await h.call('GET', `/orders/${order.id}`, { token: who.token })).body.data
    assert.equal(now.status, 'DELIVERED')
    assert.equal(now.canReturn, false)
    // The store is told, and the notice opens its order.
    const notice = await lastNotice(store.ownerId)
    assert.equal(notice!.title_en, `Return request, order ${order.orderNumber}`)
    assert.equal(notice!.body_en, 'Amina Saleh wants to return 3 items. Approve it to pick it up.')
    assert.deepEqual([notice!.entity_type, notice!.entity_id], ['STORE_ORDER', String(partId)])
    // The shopper's list and the return itself; nobody else's.
    const list = await h.call('GET', '/returns', { token: who.token })
    assert.deepEqual(
      list.body.data.map((ret: { id: string }) => ret.id),
      [made.id],
    )
    assert.equal((await h.call('GET', '/returns?status=REFUNDED', { token: who.token })).body.data.length, 0)
    assert.equal((await h.call('GET', `/returns/${made.id}`, { token: who.token })).body.data.refundAmount, 283_500)
    const stranger = await shopper()
    assert.equal((await h.call('GET', `/returns/${made.id}`, { token: stranger.token })).status, 404)
    assert.equal((await ask(stranger, order.id, [[plug.id, 1]])).status, 404)
  })

  test('each line once, even four requests at the same moment', async () => {
    const store = await openStore()
    const headphones = await listed(store)
    const { who, order } = await delivered(store, [[headphones.id, 1]])
    const line = order.items[0]!.id
    const replies = await Promise.all([1, 2, 3, 4].map(() => ask(who, order.id, [[line, 1]])))
    assert.deepEqual(replies.map((reply) => reply.status).sort(), [200, 422, 422, 422])
    for (const reply of replies.filter((reply) => reply.status === 422)) assert.equal(reply.body.message, 'This item already has a return.')
    const again = await ask(who, order.id, [[line, 1]])
    assert.equal(again.status, 422)
    assert.equal(again.body.code, 'BUSINESS_RULE_ERROR')
    assert.equal(again.body.message, 'This item already has a return.')
    assert.equal(Number((await one<{ n: number }>(h.pool, 'SELECT COUNT(*) AS n FROM returns WHERE order_id = ?', [order.id]))!.n), 1)
  })

  test('within 7 days of delivery, delivered lines only, at most what was bought, one store at a time', async () => {
    const nova = await openStore()
    const atlas = await openStore()
    const phone = await listed(nova)
    const fryer = await listed(atlas, { name: 'Atlas Air Fryer 5L', nameAr: 'قلاية هوائية أطلس', price: 95_000 })
    const who = await shopper()
    await add(who, phone.id, 2)
    await add(who, fryer.id)
    const order = await placed(who)
    const [phones, fry] = [order.items.find((i) => i.productId === phone.id)!.id, order.items.find((i) => i.productId === fryer.id)!.id]
    const novaPart = await partOf(order.id, nova)
    const atlasPart = await partOf(order.id, atlas)

    // Not delivered yet: said as that, not as the 7-day window (M5).
    await walk(nova, novaPart, 'SHIPPED')
    const early = await ask(who, order.id, [[phones, 1]])
    assert.equal(early.status, 422)
    assert.equal(early.body.message, 'Only delivered items can be returned.')
    await h.call('PATCH', `/merchants/me/orders/${novaPart}/status`, { token: nova.token, body: { status: 'DELIVERED' } })
    await walk(atlas, atlasPart)

    const tooMany = await ask(who, order.id, [[phones, 3]])
    assert.equal(tooMany.status, 422)
    assert.equal(tooMany.body.errors.items, 'You can return at most the number you bought.')
    const twoStores = await ask(who, order.id, [[phones, 1], [fry, 1]])
    assert.equal(twoStores.status, 422)
    assert.equal(twoStores.body.message, "Return one store's items at a time.")
    assert.equal((await ask(who, order.id, [['999999', 1]])).status, 422)
    assert.equal((await ask(who, order.id, [[phones, 1], [phones, 1]])).status, 422)
    assert.equal((await ask(who, order.id, [], {})).status, 422)
    assert.equal((await ask(who, order.id, [[phones, 1]], { reason: 'BORED' })).status, 422)

    // Seven days after delivery and an hour: too late. Six days and 23 hours: still in time.
    await exec(h.pool, 'UPDATE order_store_parts SET delivered_at = ? WHERE id = ?', [new Date(Date.now() - 7 * DAY - HOUR), novaPart])
    const late = await ask(who, order.id, [[phones, 1]])
    assert.equal(late.status, 422)
    assert.equal(late.body.message, 'You can return it within 7 days of delivery.')
    await exec(h.pool, 'UPDATE order_store_parts SET delivered_at = ? WHERE id = ?', [new Date(Date.now() - 7 * DAY + HOUR), novaPart])
    assert.equal((await asked(who, order.id, [[phones, 2]])).refundAmount, 290_000)
    // Nothing was refused into a half-made return.
    assert.equal(Number((await one<{ n: number }>(h.pool, 'SELECT COUNT(*) AS n FROM returns WHERE order_id = ?', [order.id]))!.n), 1)
  })
})

// -------------------------------------------------------- the store answers ---

describe("the store's answer", () => {
  test('approved, then the cash handed back: the returned things are back on the shelf once, on its Baghdad month', async () => {
    const store = await openStore()
    const headphones = await listed(store)
    const { who, order, partId } = await delivered(store, [[headphones.id, 3]])
    const made = await asked(who, order.id, [[order.items[0]!.id, 2]])
    assert.equal(await stockOf(headphones.id), 7)

    const approved = await answer(store, made.id, 'APPROVED')
    assert.equal(approved.status, 200, JSON.stringify(approved.body))
    assert.equal(approved.body.data.status, 'APPROVED')
    assert.equal(await stockOf(headphones.id), 7)
    let notice = await lastNotice(who.id)
    assert.equal(notice!.title_en, `${store.name} will pick up your return`)
    assert.deepEqual([notice!.entity_type, notice!.entity_id], ['RETURN', made.id])

    const refunded = await answer(store, made.id, 'REFUNDED')
    assert.equal(refunded.status, 200, JSON.stringify(refunded.body))
    const done = refunded.body.data
    assert.equal(done.status, 'REFUNDED')
    assert.equal(done.refund.status, 'COMPLETED')
    assert.ok(done.refund.processedAt)
    assert.deepEqual(
      done.timeline.map((step: { status: string }) => step.status),
      ['REQUESTED', 'APPROVED', 'REFUNDED'],
    )
    // The two that came back, not the whole line; one ledger row naming the return.
    assert.equal(await stockOf(headphones.id), 9)
    assert.deepEqual(await returnLedger(headphones.id), [{ delta: 2, part_id: partId, return_id: Number(made.id) }])
    const row = await one<{ refunded_at: Date; refund_month: string }>(
      h.pool,
      "SELECT refunded_at, DATE_FORMAT(refund_month, '%Y-%m-%d') AS refund_month FROM returns WHERE id = ?",
      [made.id],
    )
    assert.equal(row!.refund_month, billingMonth(row!.refunded_at))
    notice = await lastNotice(who.id)
    assert.equal(notice!.title_en, `${store.name} gave your cash back`)

    // Handed back twice is refused, and nothing moves.
    assert.equal((await answer(store, made.id, 'REFUNDED')).status, 409)
    assert.equal(await stockOf(headphones.id), 9)
  })

  test('the cash only after approval; four answers at once hand it back once', async () => {
    const store = await openStore()
    const headphones = await listed(store)
    const { who, order } = await delivered(store, [[headphones.id, 2]])
    const made = await asked(who, order.id, [[order.items[0]!.id, 2]])
    const early = await answer(store, made.id, 'REFUNDED')
    assert.equal(early.status, 409)
    assert.equal(early.body.message, "This return can't go to that step from where it is.")
    assert.equal(await stockOf(headphones.id), 8)

    assert.equal((await answer(store, made.id, 'APPROVED')).status, 200)
    const replies = await Promise.all([1, 2, 3, 4].map(() => answer(store, made.id, 'REFUNDED')))
    assert.deepEqual(replies.map((reply) => reply.status).sort(), [200, 409, 409, 409])
    assert.equal(await stockOf(headphones.id), 10)
    assert.equal((await returnLedger(headphones.id)).length, 1)
  })

  test('a decline needs its reason and hands nothing back; it is an end', async () => {
    const store = await openStore()
    const headphones = await listed(store)
    const { who, order } = await delivered(store, [[headphones.id, 1]])
    const made = await asked(who, order.id, [[order.items[0]!.id, 1]])
    const bare = await answer(store, made.id, 'REJECTED')
    assert.equal(bare.status, 422)
    assert.equal(bare.body.errors.reason, 'Choose why you are declining.')
    assert.equal((await answer(store, made.id, 'REJECTED', 'BECAUSE')).status, 422)

    const declined = await answer(store, made.id, 'REJECTED', 'USED')
    assert.equal(declined.status, 200, JSON.stringify(declined.body))
    assert.equal(declined.body.data.rejectionReason, 'USED')
    assert.equal(declined.body.data.refund, null)
    const notice = await lastNotice(who.id)
    assert.equal(notice!.body_en, `Order ${order.orderNumber}: It has been used.`)
    assert.equal(notice!.title_ar, `رفض ${store.name} الإرجاع`)
    assert.equal((await answer(store, made.id, 'APPROVED')).status, 409)
    assert.equal((await answer(store, made.id, 'REFUNDED')).status, 409)
    assert.equal(await stockOf(headphones.id), 9)
    assert.equal((await returnLedger(headphones.id)).length, 0)
    // The line had its one return.
    assert.equal((await ask(who, order.id, [[order.items[0]!.id, 1]])).body.message, 'This item already has a return.')
  })

  test("another store's return is not found; the store's order shows its returns; a shopper can't answer", async () => {
    const store = await openStore()
    const other = await openStore()
    const headphones = await listed(store)
    const { who, order, partId } = await delivered(store, [[headphones.id, 1]])
    const made = await asked(who, order.id, [[order.items[0]!.id, 1]])
    assert.equal((await answer(other, made.id, 'APPROVED')).status, 404)
    assert.equal((await h.call('PATCH', `/merchants/me/returns/${made.id}`, { token: who.token, body: { status: 'APPROVED' } })).status, 403)
    const detail = (await h.call('GET', `/merchants/me/orders/${partId}`, { token: store.token, lang: 'ar' })).body.data
    assert.equal(detail.returns.length, 1)
    assert.equal(detail.returns[0].id, made.id)
    assert.equal(detail.returns[0].items[0].name, 'سماعات كايت ستوديو')
    assert.equal(detail.returns[0].refund.method, 'نقداً، يعيده لك المتجر')
  })
})

// ------------------------------------------------------------- Saba's view ---

describe("Saba's view", () => {
  const afterSales = async (query = '') => (await h.call('GET', `/admin/after-sales${query}`, { token: admin })).body.data

  test('cancellations and returns: one row per cancelled store part, one per return; the value leaves declined returns out', async () => {
    const before = await afterSales()
    const nova = await openStore()
    const atlas = await openStore()
    const phone = await listed(nova)
    const fryer = await listed(atlas, { name: 'Atlas Air Fryer 5L', nameAr: 'قلاية هوائية أطلس', price: 95_000 })

    // A two-store order the shopper cancels, with Nova's code on it: two rows, each its own value.
    const who = await shopper()
    await add(who, phone.id)
    await add(who, fryer.id)
    await tenPercent(nova, who)
    const both = await placed(who)
    assert.equal((await h.call('POST', `/orders/${both.id}/cancel`, { token: who.token, body: { reason: 'FOUND_CHEAPER' } })).status, 200)
    // A store declines one.
    const buyer = await shopper()
    await add(buyer, fryer.id)
    const declined = await placed(buyer)
    const declinedPart = await partOf(declined.id, atlas)
    await h.call('PATCH', `/merchants/me/orders/${declinedPart}/status`, { token: atlas.token, body: { status: 'CANCELLED', reason: 'OUT_OF_STOCK' } })
    // One return waiting, one declined.
    const first = await delivered(nova, [[phone.id, 1]])
    const open = await asked(first.who, first.order.id, [[first.order.items[0]!.id, 1]])
    const second = await delivered(nova, [[phone.id, 1]])
    const turnedDown = await asked(second.who, second.order.id, [[second.order.items[0]!.id, 1]])
    assert.equal((await answer(nova, turnedDown.id, 'REJECTED', 'USED')).status, 200)

    const now = await afterSales()
    const rowOf = (kind: string, id: string | number) => now.items.find((row: { kind: string; id: string }) => row.kind === kind && row.id === String(id))
    const novaRow = rowOf('CANCELLED', await partOf(both.id, nova))
    assert.deepEqual(
      [novaRow.by, novaRow.reason, novaRow.value, novaRow.storeName, novaRow.orderId, novaRow.more],
      ['SHOPPER', 'FOUND_CHEAPER', 145_000 - 14_500, nova.name, both.id, 0],
    )
    const atlasRow = rowOf('CANCELLED', await partOf(both.id, atlas))
    assert.deepEqual([atlasRow.by, atlasRow.reason, atlasRow.value], ['SHOPPER', 'FOUND_CHEAPER', 95_000])
    const storeRow = rowOf('CANCELLED', declinedPart)
    assert.deepEqual([storeRow.by, storeRow.reason, storeRow.value, storeRow.buyer], ['STORE', 'OUT_OF_STOCK', 95_000, 'Amina Saleh'])
    const openRow = rowOf('RETURNED', open.id)
    assert.deepEqual([openRow.returnStatus, openRow.value, openRow.by, openRow.item.productName], ['REQUESTED', 145_000, 'SHOPPER', 'Kite Studio Headphones'])
    assert.equal(rowOf('RETURNED', turnedDown.id).returnStatus, 'REJECTED')
    assert.deepEqual(now.counts, {
      all: before.counts.all + 5,
      CANCELLED: before.counts.CANCELLED + 3,
      RETURNED: before.counts.RETURNED + 2,
      openReturns: before.counts.openReturns + 1,
    })
    // The declined return lost nothing: the shopper kept the item.
    assert.equal(now.value, before.value + 130_500 + 95_000 + 95_000 + 145_000)
    // Newest first; by kind; by period.
    assert.ok(now.items.every((row: { at: string }, i: number) => i === 0 || now.items[i - 1].at >= row.at))
    assert.ok((await afterSales('?kind=RETURNED')).items.every((row: { kind: string }) => row.kind === 'RETURNED'))
    await exec(h.pool, 'UPDATE order_store_parts SET cancelled_at = ? WHERE id = ?', [new Date(Date.now() - 40 * DAY), declinedPart])
    const month = await afterSales('?days=30')
    assert.equal(month.items.some((row: { kind: string; id: string }) => row.kind === 'CANCELLED' && row.id === String(declinedPart)), false)
    assert.equal(month.value, now.value - 95_000)
    assert.ok((await afterSales('?days=90')).items.some((row: { id: string }) => row.id === String(declinedPart)))
    assert.equal((await h.call('GET', '/admin/after-sales?days=12', { token: admin })).status, 422)
  })

  test("a return in full: the shopper's words, the store's answer, its steps, each item at the price paid", async () => {
    const store = await openStore()
    const headphones = await listed(store)
    const { who, order } = await delivered(store, [[headphones.id, 2]], true)
    const made = await asked(who, order.id, [[order.items[0]!.id, 2]], { description: 'Both crackle.' })
    await answer(store, made.id, 'APPROVED')
    await answer(store, made.id, 'REFUNDED')
    const sheet = (await h.call('GET', `/admin/returns/${made.id}`, { token: admin })).body.data
    assert.equal(sheet.refundAmount, 261_000)
    assert.deepEqual(sheet.items, [{ productName: 'Kite Studio Headphones', productNameAr: 'سماعات كايت ستوديو', quantity: 2, unitPrice: 130_500 }])
    assert.equal(sheet.description, 'Both crackle.')
    assert.equal(sheet.merchantName, store.name)
    assert.ok(sheet.answeredAt && sheet.refundedAt)
    assert.deepEqual(
      sheet.timeline.map((step: { status: string }) => step.status),
      ['REQUESTED', 'APPROVED', 'REFUNDED'],
    )
    assert.deepEqual(sheet.refund, { amount: 261_000, status: 'COMPLETED', processedAt: sheet.refundedAt })
    assert.equal((await h.call('GET', '/admin/returns/999999', { token: admin })).status, 404)
    assert.equal((await h.call('GET', `/admin/returns/${made.id}`, { token: who.token })).status, 403)
  })

  test("customers: found by name, phone and city; spent is their delivered parts less what was handed back", async () => {
    const store = await openStore()
    const headphones = await listed(store)
    const charger = await listed(store, { name: 'Nova Fast Charger 65W', nameAr: 'شاحن نوفا', price: 25_000 })
    const { who, order } = await delivered(store, [[headphones.id, 1], [charger.id, 1]])
    const [phones, plug] = [order.items.find((i) => i.productId === headphones.id)!.id, order.items.find((i) => i.productId === charger.id)!.id]
    // One return refunded, one still waiting: only the refunded one comes off.
    const refunded = await asked(who, order.id, [[plug, 1]])
    await answer(store, refunded.id, 'APPROVED')
    await answer(store, refunded.id, 'REFUNDED')
    await asked(who, order.id, [[phones, 1]])
    // An order still on its way is not spent yet.
    await add(who, charger.id)
    await placed(who)
    await h.call('PATCH', '/customers/me', { token: who.token, body: { fullName: 'Rana Salman' } })

    const list = async (query: string) => (await h.call('GET', `/admin/customers${query}`, { token: admin })).body.data
    const found = await list(`?q=${encodeURIComponent(who.phone.replace('+964', '0'))}`)
    assert.equal(found.items.length, 1)
    const customer = found.items[0]
    assert.equal(customer.id, String(who.id))
    assert.equal(customer.orderCount, 2)
    assert.equal(customer.spent, 145_000 + 25_000 + 3000 - 25_000)
    assert.equal(customer.status, 'ACTIVE')
    assert.equal(customer.governorate, 'BAGHDAD')
    assert.deepEqual(found.counts, { all: 1, ACTIVE: 1 })
    assert.ok((await list('?q=rana%20salman')).items.some((row: { id: string }) => row.id === String(who.id)))
    assert.ok((await list(`?q=${encodeURIComponent('بغداد')}`)).items.some((row: { id: string }) => row.id === String(who.id)))
    assert.ok((await list('?q=karrada')).items.some((row: { id: string }) => row.id === String(who.id)))
    const all = await list('')
    assert.ok(all.items.every((row: { joinedAt: string }, i: number) => i === 0 || all.items[i - 1].joinedAt >= row.joinedAt))

    const detail = (await h.call('GET', `/admin/customers/${who.id}`, { token: admin })).body.data
    assert.equal(detail.addresses.length, 1)
    assert.deepEqual([detail.addresses[0].area, detail.addresses[0].isDefault], ['Karrada', true])
    assert.equal(detail.orders.length, 2)
    assert.ok(detail.orders[0].placedAt >= detail.orders[1].placedAt)

    // A deleted account has nothing left to show (the user's call, 2026-09-27).
    const gone = await shopper()
    assert.equal((await h.call('DELETE', '/customers/me', { token: gone.token })).status, 200)
    assert.equal((await list('')).items.some((row: { id: string }) => row.id === String(gone.id)), false)
    assert.equal((await h.call('GET', `/admin/customers/${gone.id}`, { token: admin })).status, 404)
    assert.equal((await h.call('GET', `/admin/customers/${store.ownerId}`, { token: admin })).status, 404)
  })

  test("suspending a shopper: out at once, can't sign in or order, every sign-in ended; lifting it lets them sign in again", async () => {
    const who = await shopper()
    const signIn = () => h.call('POST', '/auth/login', { body: { phone: who.phone, password: PASSWORD } })
    const session = (await signIn()).body.data
    assert.equal((await h.call('POST', `/admin/customers/${who.id}/suspend`, { token: admin, body: { reason: '  ' } })).status, 422)

    const suspended = await h.call('POST', `/admin/customers/${who.id}/suspend`, {
      token: admin,
      body: { reason: 'Refused three cash orders at the door in one month.' },
    })
    assert.equal(suspended.status, 200, JSON.stringify(suspended.body))
    assert.deepEqual([suspended.body.data.status, suspended.body.data.suspensionReason], ['SUSPENDED', 'Refused three cash orders at the door in one month.'])
    assert.equal((await h.call('GET', '/cart', { token: session.accessToken })).status, 401)
    assert.equal(
      (await h.call('POST', '/checkout/place-order', { token: who.token, headers: { 'idempotency-key': 'suspended' }, body: { addressId: who.addressId } })).status,
      401,
    )
    const refused = await signIn()
    assert.deepEqual([refused.status, refused.body.message], [403, 'This account is suspended.'])
    assert.equal((await h.call('POST', '/auth/refresh', { body: { refreshToken: session.refreshToken } })).status, 401)
    assert.equal((await h.call('POST', `/admin/customers/${who.id}/suspend`, { token: admin, body: { reason: 'Again' } })).status, 409)
    const audit = await one<{ action: string; reason: string }>(
      h.pool,
      "SELECT action, reason FROM admin_actions WHERE entity_type = 'CUSTOMER' AND entity_id = ? ORDER BY id DESC LIMIT 1",
      [String(who.id)],
    )
    assert.deepEqual([audit!.action, audit!.reason], ['CUSTOMER_SUSPEND', 'Refused three cash orders at the door in one month.'])
    assert.equal((await h.call('GET', '/admin/customers?status=SUSPENDED', { token: admin })).body.data.items.some((row: { id: string }) => row.id === String(who.id)), true)

    const lifted = await h.call('POST', `/admin/customers/${who.id}/unsuspend`, { token: admin })
    assert.equal(lifted.status, 200)
    assert.equal(lifted.body.data.status, 'ACTIVE')
    assert.equal(lifted.body.data.suspensionReason, undefined)
    // The sign-in the suspension ended stays ended, its access tokens too (M5); a new one works.
    assert.equal((await h.call('POST', '/auth/refresh', { body: { refreshToken: session.refreshToken } })).status, 401)
    assert.equal((await h.call('GET', '/cart', { token: session.accessToken })).status, 401)
    assert.equal((await h.call('GET', '/cart', { token: who.token })).status, 401)
    assert.equal((await signIn()).status, 200)
    assert.equal((await h.call('POST', `/admin/customers/${who.id}/unsuspend`, { token: admin })).status, 409)
    assert.equal((await h.call('POST', '/admin/customers/999999/suspend', { token: admin, body: { reason: 'x' } })).status, 404)
  })

  test("deleting a shopper at their request: refused while an order is open, then gone at once, as their own delete; a shopper's only", async () => {
    const store = await openStore()
    const product = await listed(store)
    const who = await shopper()
    await add(who, product.id)
    const order = await placed(who)
    const signIn = () => h.call('POST', '/auth/login', { body: { phone: who.phone, password: PASSWORD } })

    const refused = await h.call('DELETE', `/admin/customers/${who.id}`, { token: admin })
    assert.deepEqual([refused.status, refused.body.message], [409, `Order ${order.orderNumber} is still open. The account can be deleted once it is finished.`])
    assert.equal((await signIn()).status, 200)

    const cancelled = await h.call('PATCH', `/merchants/me/orders/${await partOf(order.id, store)}/status`, {
      token: store.token,
      body: { status: 'CANCELLED', reason: 'OUT_OF_STOCK' },
    })
    assert.equal(cancelled.status, 200, JSON.stringify(cancelled.body))
    const deleted = await h.call('DELETE', `/admin/customers/${who.id}`, { token: admin })
    assert.deepEqual([deleted.status, deleted.body.data], [200, {}])
    assert.equal((await h.call('GET', '/cart', { token: who.token })).status, 401)
    // The number has no account any more: free to sign up again.
    assert.equal((await signIn()).status, 422)
    assert.equal((await h.call('GET', `/admin/customers/${who.id}`, { token: admin })).status, 404)
    assert.equal((await h.call('DELETE', `/admin/customers/${who.id}`, { token: admin })).status, 404)
    const audit = await one<{ action: string; admin_user_id: number }>(
      h.pool,
      "SELECT action, admin_user_id FROM admin_actions WHERE entity_type = 'CUSTOMER' AND entity_id = ? ORDER BY id DESC LIMIT 1",
      [String(who.id)],
    )
    assert.equal(audit?.action, 'CUSTOMER_DELETE')
    // The order keeps its own copy of the name and number it went to.
    assert.deepEqual(await one(h.pool, 'SELECT customer_name, customer_phone FROM orders WHERE id = ?', [order.id]), {
      customer_name: 'Amina Saleh',
      customer_phone: who.phone,
    })
    // A store owner's account goes with its store (POST /admin/stores/:id/deletion), never here.
    assert.equal((await h.call('DELETE', `/admin/customers/${store.ownerId}`, { token: admin })).status, 404)
  })

  test('the dashboard: what waits, the longest first; the counts; the 5 newest orders', async () => {
    const waiting = await h.signUpStore('Dashboard Waiting Store', 'BASRA')
    const board = (await h.call('GET', '/admin/dashboard', { token: admin })).body.data
    const count = async (sql: string) => Number((await one<{ n: number }>(h.pool, sql))!.n)
    assert.equal(board.storesWaiting, await count("SELECT COUNT(*) AS n FROM stores WHERE status = 'PENDING'"))
    assert.equal(board.stores, await count('SELECT COUNT(*) AS n FROM stores'))
    assert.equal(board.orders, await count('SELECT COUNT(*) AS n FROM orders'))
    assert.equal(
      Object.values(board.ordersByStatus as Record<string, number>).reduce((sum, n) => sum + n, 0),
      board.orders,
    )
    const queue = (await h.call('GET', '/admin/queue', { token: admin })).body.data
    assert.equal(board.productsWaiting, queue.products.length)
    assert.ok(board.waitingLongest.some((row: { kind: string; id: string }) => row.kind === 'store' && row.id === waiting.storeId))
    assert.ok(board.waitingLongest.length <= 4)
    assert.ok(board.waitingLongest.every((row: { since: string }, i: number) => i === 0 || board.waitingLongest[i - 1].since <= row.since))
    assert.equal(board.recentOrders.length, Math.min(5, board.orders))
    const newest = await rows<{ id: number }>(h.pool, 'SELECT id FROM orders ORDER BY placed_at DESC, id DESC LIMIT 5')
    assert.deepEqual(
      board.recentOrders.map((order: { id: string }) => order.id),
      newest.map((row) => String(row.id)),
    )
  })
})
