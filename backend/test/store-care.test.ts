// The user's calls of 2026-10-05: Saba's switch that approves products at once,
// the store's phone on its public page, a part left "on its way" for 5 days
// marked delivered for its store, and the store's own list of returns.
import assert from 'node:assert/strict'
import { after, before, describe, test } from 'node:test'
import { exec, one } from '../src/db/sql.js'
import { autoDeliver } from '../src/modules/store-orders.js'
import { startHarness, type Harness } from './api.js'

let h: Harness
let admin: string
before(async () => {
  h = await startHarness()
  admin = await h.signInAdmin()
})
after(() => h.close())

const SMARTPHONES = '8'
const DAY = 24 * 3_600_000

let stores = 0
/** An approved, open store delivering in its own city at 3,000. */
async function openStore() {
  stores += 1
  const name = `Care Store ${stores}`
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

const product = (store: Store, name = 'Kite Studio Headphones') =>
  h.call('POST', '/merchants/me/products', {
    token: store.token,
    body: { name, nameAr: 'سماعات كايت ستوديو', categoryId: SMARTPHONES, price: 145_000, stock: 10 },
  })

const statusOf = async (productId: string) => (await one<{ status: string }>(h.pool, 'SELECT status FROM products WHERE id = ?', [productId]))!.status

const autoApprove = (on: boolean) => h.call('PATCH', '/admin/settings', { token: admin, body: { autoApproveProducts: on } })

/** An approved product of [store], through the queue. */
async function listed(store: Store) {
  const made = await product(store)
  assert.equal(made.status, 200, JSON.stringify(made.body))
  if ((await statusOf(made.body.data.id)) === 'PENDING') {
    assert.equal((await h.call('POST', `/admin/products/${made.body.data.id}/approve`, { token: admin })).status, 200)
  }
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

let keys = 0
/** A new shopper's order of one [productId] from [store], walked by the store up to [until]. */
async function ordered(store: Store, productId: string, until: 'SHIPPED' | 'DELIVERED') {
  const who = await shopper()
  assert.equal((await h.call('POST', '/cart/items', { token: who.token, body: { productId, quantity: 1 } })).status, 200)
  const reply = await h.call('POST', '/checkout/place-order', {
    token: who.token,
    headers: { 'idempotency-key': `care-key-${++keys}` },
    body: { addressId: who.addressId, paymentMethodId: 'pm-cod' },
  })
  assert.equal(reply.status, 200, JSON.stringify(reply.body))
  const order = reply.body.data.order as { id: string; orderNumber: string; items: { id: string }[] }
  const partId = (await one<{ id: number }>(h.pool, 'SELECT id FROM order_store_parts WHERE order_id = ? AND store_id = ?', [order.id, store.id]))!.id
  const path = ['CONFIRMED', 'PROCESSING', 'SHIPPED', 'DELIVERED']
  for (const status of path.slice(0, path.indexOf(until) + 1)) {
    const extra = status === 'SHIPPED' ? { courierName: 'Haider Salim', courierPhone: '0770 555 0311' } : {}
    const moved = await h.call('PATCH', `/merchants/me/orders/${partId}/status`, { token: store.token, body: { status, ...extra } })
    assert.equal(moved.status, 200, JSON.stringify(moved.body))
  }
  return { who, order, partId }
}

const lastNotice = (userId: number) =>
  one<{ type: string; title_en: string; body_en: string; title_ar: string; entity_type: string; entity_id: string }>(
    h.pool,
    'SELECT type, title_en, body_en, title_ar, entity_type, entity_id FROM notifications WHERE user_id = ? ORDER BY id DESC LIMIT 1',
    [userId],
  )

describe("Saba's switch: products approved at once", () => {
  test('only an admin reads and turns it; each turn is in the admin log', async () => {
    const store = await openStore()
    assert.equal((await h.call('GET', '/admin/settings', { token: store.token })).status, 403)
    assert.equal((await h.call('PATCH', '/admin/settings', { token: store.token, body: { autoApproveProducts: true } })).status, 403)
    assert.deepEqual((await h.call('GET', '/admin/settings', { token: admin })).body.data, { autoApproveProducts: false })

    const on = await autoApprove(true)
    assert.equal(on.status, 200, JSON.stringify(on.body))
    assert.deepEqual(on.body.data, { autoApproveProducts: true })
    assert.deepEqual((await h.call('GET', '/admin/settings', { token: admin })).body.data, { autoApproveProducts: true })
    const logged = await one<{ n: number }>(
      h.pool,
      "SELECT COUNT(*) AS n FROM admin_actions WHERE action = 'SETTING_CHANGE' AND entity_id = 'auto_approve_products'",
    )
    assert.ok(Number(logged!.n) >= 1)
    await autoApprove(false)
  })

  test('on: a new product is live at once, and a change keeps it live; off: it waits as before', async () => {
    const store = await openStore()
    await autoApprove(true)
    try {
      const made = await product(store)
      assert.equal(made.status, 200, JSON.stringify(made.body))
      assert.equal(await statusOf(made.body.data.id), 'APPROVED')
      // Shoppers find it straight away.
      assert.equal((await h.call('GET', `/products/${made.body.data.id}`)).status, 200)

      // What shoppers read changes: still live, no trip back to the queue.
      const changed = await h.call('PUT', `/merchants/me/products/${made.body.data.id}`, {
        token: store.token,
        body: { name: 'Kite Studio Headphones II', nameAr: 'سماعات كايت ستوديو 2', categoryId: SMARTPHONES, price: 145_000, stock: 10 },
      })
      assert.equal(changed.status, 200, JSON.stringify(changed.body))
      assert.equal(await statusOf(made.body.data.id), 'APPROVED')
    } finally {
      await autoApprove(false)
    }
    const waiting = await product(store, 'Kite Mini')
    assert.equal(await statusOf(waiting.body.data.id), 'PENDING')
  })
})

test("a store's public page carries its owner's number", async () => {
  const store = await openStore()
  const page = await h.call('GET', `/merchants/${store.storeId}/store`)
  assert.equal(page.status, 200)
  assert.equal(page.body.data.phone, store.phone)
})

describe('a part left on its way for 5 days is delivered for its store', () => {
  test('marked delivered as the store would: status, bill, step, both sides told; a newer one is left alone', async () => {
    const store = await openStore()
    const { id: productId } = await listed(store)
    const old = await ordered(store, productId, 'SHIPPED')
    const recent = await ordered(store, productId, 'SHIPPED')

    // While on its way, the store sees the day it will be marked.
    const seen = await h.call('GET', `/merchants/me/orders/${old.partId}`, { token: store.token })
    assert.equal(seen.status, 200)
    const sentAt = (await one<{ shipped_at: Date }>(h.pool, 'SELECT shipped_at FROM order_store_parts WHERE id = ?', [old.partId]))!.shipped_at
    assert.equal(seen.body.data.autoDeliverAt, new Date(sentAt.getTime() + 5 * DAY).toISOString())

    await exec(h.pool, 'UPDATE order_store_parts SET shipped_at = ? WHERE id = ?', [new Date(Date.now() - 5 * DAY - 60_000), old.partId])
    await exec(h.pool, 'UPDATE order_store_parts SET shipped_at = ? WHERE id = ?', [new Date(Date.now() - 4 * DAY), recent.partId])

    const run = await autoDeliver(h.pool)
    assert.deepEqual(run, { delivered: 1, failed: 0 })

    const part = await one<{ status: string; delivered_at: Date | null; billing_month: string | null }>(
      h.pool,
      'SELECT status, delivered_at, billing_month FROM order_store_parts WHERE id = ?',
      [old.partId],
    )
    assert.equal(part!.status, 'DELIVERED')
    assert.ok(part!.delivered_at)
    assert.ok(part!.billing_month)
    assert.equal((await one<{ status: string }>(h.pool, 'SELECT status FROM orders WHERE id = ?', [old.order.id]))!.status, 'DELIVERED')
    const step = await one<{ status: string; note_code: string | null }>(
      h.pool,
      'SELECT status, note_code FROM order_events WHERE part_id = ? ORDER BY id DESC LIMIT 1',
      [old.partId],
    )
    assert.deepEqual({ ...step }, { status: 'DELIVERED', note_code: 'AUTO_DELIVERED' })

    // The shopper: marked delivered, and who to contact if it never came.
    const toShopper = await lastNotice(old.who.id)
    assert.equal(toShopper!.type, 'DELIVERY')
    assert.equal(toShopper!.title_en, `Order ${old.order.orderNumber} is marked delivered`)
    assert.match(toShopper!.body_en, new RegExp(`${store.name} sent it 5 days ago`))
    assert.equal(toShopper!.entity_type, 'ORDER')
    // The store: why.
    const toStore = await lastNotice(store.ownerId)
    assert.equal(toStore!.title_en, `Order ${old.order.orderNumber} is marked delivered`)
    assert.equal(toStore!.entity_type, 'STORE_ORDER')
    assert.equal(toStore!.entity_id, String(old.partId))

    // Its timeline says so, to the shopper and to Saba.
    const mine = await h.call('GET', `/orders/${old.order.id}`, { token: old.who.token })
    assert.ok(mine.body.data.timeline.some((entry: { noteCode: string | null }) => entry.noteCode === 'AUTO_DELIVERED'))
    const saba = await h.call('GET', `/admin/orders/${old.order.id}`, { token: admin })
    assert.ok(saba.body.data.timeline.some((entry: { noteCode?: string }) => entry.noteCode === 'AUTO_DELIVERED'))

    // Delivered, so the return window is open.
    const asked = await h.call('POST', '/returns', {
      token: old.who.token,
      body: { orderId: old.order.id, reason: 'DAMAGED', items: [{ orderItemId: old.order.items[0]!.id, quantity: 1 }] },
    })
    assert.equal(asked.status, 200, JSON.stringify(asked.body))

    // Four days out: still the store's to mark. Run again: nothing more.
    assert.equal((await one<{ status: string }>(h.pool, 'SELECT status FROM order_store_parts WHERE id = ?', [recent.partId]))!.status, 'SHIPPED')
    assert.deepEqual(await autoDeliver(h.pool), { delivered: 0, failed: 0 })
    const after = await h.call('GET', `/merchants/me/orders/${old.partId}`, { token: store.token })
    assert.equal(after.body.data.autoDeliverAt, null)
  })
})

describe("the store's returns", () => {
  test('listed for the store with its order, counted while they wait on it, and nobody else sees them', async () => {
    const store = await openStore()
    const other = await openStore()
    const { id: productId } = await listed(store)
    const { who, order, partId } = await ordered(store, productId, 'DELIVERED')

    const empty = await h.call('GET', '/merchants/me/returns', { token: store.token })
    assert.equal(empty.status, 200)
    assert.deepEqual(empty.body.data, [])

    const asked = await h.call('POST', '/returns', {
      token: who.token,
      body: { orderId: order.id, reason: 'DAMAGED', items: [{ orderItemId: order.items[0]!.id, quantity: 1 }] },
    })
    assert.equal(asked.status, 200, JSON.stringify(asked.body))
    const returnId = asked.body.data.id as string

    const list = await h.call('GET', '/merchants/me/returns', { token: store.token })
    assert.equal(list.status, 200)
    assert.equal(list.body.data.length, 1)
    assert.equal(list.body.data[0].id, returnId)
    assert.equal(list.body.data[0].storeOrderId, String(partId))
    assert.equal(list.body.data[0].status, 'REQUESTED')
    assert.equal(list.body.data[0].orderNumber, order.orderNumber)
    assert.equal((await h.call('GET', '/merchants/me/orders/counts', { token: store.token })).body.data.RETURNS, 1)
    assert.equal((await h.call('GET', '/merchants/me/returns?status=OPEN', { token: store.token })).body.data.length, 1)

    // Another store: none of it.
    assert.deepEqual((await h.call('GET', '/merchants/me/returns', { token: other.token })).body.data, [])
    assert.equal((await h.call('GET', '/merchants/me/orders/counts', { token: other.token })).body.data.RETURNS, 0)
    assert.equal((await h.call('GET', '/merchants/me/returns', { token: who.token })).status, 403)

    // Approved: still waiting on the store (the cash). Refunded: done.
    const approved = await h.call('PATCH', `/merchants/me/returns/${returnId}`, { token: store.token, body: { status: 'APPROVED' } })
    assert.equal(approved.status, 200, JSON.stringify(approved.body))
    assert.equal((await h.call('GET', '/merchants/me/orders/counts', { token: store.token })).body.data.RETURNS, 1)
    const refunded = await h.call('PATCH', `/merchants/me/returns/${returnId}`, { token: store.token, body: { status: 'REFUNDED' } })
    assert.equal(refunded.status, 200, JSON.stringify(refunded.body))
    assert.equal((await h.call('GET', '/merchants/me/orders/counts', { token: store.token })).body.data.RETURNS, 0)
    assert.deepEqual((await h.call('GET', '/merchants/me/returns?status=OPEN', { token: store.token })).body.data, [])
    const all = await h.call('GET', '/merchants/me/returns', { token: store.token })
    assert.equal(all.body.data.length, 1)
    assert.equal(all.body.data[0].status, 'REFUNDED')
  })
})
