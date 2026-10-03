// Saba's lists paged in the database (the reviewer's item 7): always one page
// and its meta; page 1 of 50 when none is asked (contract §1.3).
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import { startHarness, type Harness } from './api.js'

let h: Harness
let admin: string
before(async () => {
  h = await startHarness()
  admin = await h.signInAdmin()
})
after(() => h.close())

const get = async (path: string) => {
  const reply = await h.call('GET', path, { token: admin })
  assert.equal(reply.status, 200, JSON.stringify(reply.body))
  return reply.body as { data: { items: { id: string }[]; counts: Record<string, number> }; meta: Record<string, number> }
}

/** Page 1 and page 2 of [path] (2 a page) are the first four of the whole list, in order, with the total. */
async function pagesMatch(path: string, total: (all: { counts: Record<string, number> }) => number) {
  const join = path.includes('?') ? '&' : '?'
  const whole = (await get(path)).data
  assert.ok(whole.items.length >= 3, `${path}: needs at least 3 rows, has ${whole.items.length}`)
  const first = await get(`${path}${join}page=1&perPage=2`)
  const second = await get(`${path}${join}page=2&perPage=2`)
  assert.deepEqual(
    [...first.data.items, ...second.data.items].map((item) => item.id),
    whole.items.slice(0, 4).map((item) => item.id),
    path,
  )
  assert.deepEqual(first.meta, { page: 1, perPage: 2, total: total(whole), totalPages: Math.ceil(total(whole) / 2) }, path)
  assert.equal(total(whole), whole.items.length, path)
  // The counts are the whole list's, whatever the page.
  assert.deepEqual(first.data.counts, whole.counts, path)
}

test('every list: a page of it, its total, and the same order and counts as the whole list', async () => {
  // Three stores, one of them selling; three shoppers who each order, open a ticket, and two cancel.
  const stores = [await h.signUpStore('Paging Store A'), await h.signUpStore('Paging Store B'), await h.signUpStore('Paging Store C')]
  const [seller] = stores
  assert.equal((await h.call('POST', `/admin/stores/${seller!.storeId}/approve`, { token: admin })).status, 200)
  const saved = await h.call('PUT', '/merchants/me/store', {
    token: seller!.token,
    body: { storeName: 'Paging Store A', governorate: 'BAGHDAD', logoUrl: null, delivery: { governorates: [], feeInside: 3000, timeInside: '1_2_DAYS' } },
  })
  assert.equal(saved.status, 200, JSON.stringify(saved.body))
  const products: string[] = []
  for (const name of ['Paging Phone One', 'Paging Phone Two', 'Paging Phone Three']) {
    const made = await h.call('POST', '/merchants/me/products', {
      token: seller!.token,
      body: { name, nameAr: 'هاتف للصفحات', categoryId: '8', price: 100_000, stock: 20 },
    })
    assert.equal(made.status, 200, JSON.stringify(made.body))
    products.push(made.body.data.id)
  }
  assert.equal((await h.call('POST', `/admin/products/${products[0]}/approve`, { token: admin })).status, 200)
  for (let i = 0; i < 3; i++) {
    const who = await h.signUpShopper('BAGHDAD')
    const address = await h.call('POST', '/customers/me/addresses', {
      token: who.token,
      body: { fullName: 'Amina Saleh', phone: who.phone, governorate: 'BAGHDAD', area: 'Karrada', landmark: 'Near the park' },
    })
    assert.equal((await h.call('POST', '/cart/items', { token: who.token, body: { productId: products[0], quantity: 1 } })).status, 200)
    const placed = await h.call('POST', '/checkout/place-order', {
      token: who.token,
      headers: { 'idempotency-key': `paging-${i}` },
      body: { addressId: address.body.data.id, paymentMethodId: 'pm-cod' },
    })
    assert.equal(placed.status, 200, JSON.stringify(placed.body))
    const ticket = await h.call('POST', '/support/tickets', {
      token: who.token,
      body: { subject: `Question ${i}`, category: 'ORDER', description: 'Where is my order?' },
    })
    assert.equal(ticket.status, 200, JSON.stringify(ticket.body))
    if (i < 3) {
      const cancelled = await h.call('POST', `/orders/${placed.body.data.order.id}/cancel`, { token: who.token, body: { reason: 'CHANGED_MIND' } })
      assert.equal(cancelled.status, 200, JSON.stringify(cancelled.body))
    }
  }

  await pagesMatch('/admin/orders', (all) => all.counts.all!)
  await pagesMatch('/admin/orders?status=CANCELLED', (all) => all.counts.CANCELLED!)
  await pagesMatch('/admin/customers', (all) => all.counts.all!)
  await pagesMatch('/admin/stores', (all) => all.counts.all!)
  await pagesMatch('/admin/products', (all) => all.counts.all!)
  await pagesMatch('/admin/tickets', (all) => all.counts.all!)
  await pagesMatch('/admin/after-sales', (all) => all.counts.all!)

  // No page asked: page 1, 50 a page, never the whole list at once.
  const unasked = await get('/admin/orders')
  assert.deepEqual([unasked.meta.page, unasked.meta.perPage, unasked.meta.total], [1, 50, unasked.data.counts.all])
  // A page past the end is empty, with the same total.
  const past = await get('/admin/customers?page=9&perPage=2')
  assert.deepEqual([past.data.items.length, past.meta.total], [0, (await get('/admin/customers')).data.counts.all])
  // perPage is 1 to 100.
  assert.equal((await h.call('GET', '/admin/orders?page=1&perPage=101', { token: admin })).status, 422)
  // Searching still works on a page: the store's name in its orders.
  const found = await get('/admin/orders?q=paging%20store%20a&page=1&perPage=2')
  assert.equal(found.meta.total, 3)
})
