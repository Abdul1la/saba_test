// S8 Live updates (BACKEND_PLAN.md §10): GET /events. A store's step reaches
// the shopper's open stream; one store never hears another's; a change is
// told only once it has committed; Saba's admins hear their pages' topics; a
// suspended shopper's stream ends at once.
import assert from 'node:assert/strict'
import { after, before, describe, test } from 'node:test'
import { SignJWT } from 'jose'
import { one } from '../src/db/sql.js'
import { withTransaction } from '../src/db/tx.js'
import { listen, publish, type Topic } from '../src/lib/events.js'
import { startHarness, type Harness } from './api.js'
import { testConfig } from './helpers.js'

let h: Harness
let admin: string
const open: AbortController[] = []
before(async () => {
  h = await startHarness()
  admin = await h.signInAdmin()
})
// Every stream is ended first: an open one would keep the server from closing.
after(async () => {
  for (const controller of open) controller.abort()
  await h.close()
})

interface Heard {
  topic: Topic
  id?: string
}

/** An open stream for [token]: what it has heard so far, and a wait for what it should hear. */
async function stream(token: string) {
  const controller = new AbortController()
  open.push(controller)
  const response = await fetch(`${h.url}/events`, { headers: { authorization: `Bearer ${token}` }, signal: controller.signal })
  assert.equal(response.status, 200)
  assert.match(response.headers.get('content-type') ?? '', /^text\/event-stream/)
  const heard: Heard[] = []
  const waiting: (() => void)[] = []
  let ended = false
  const reader = response.body!.getReader()
  const decoder = new TextDecoder()
  const done = (async () => {
    let buffer = ''
    try {
      for (;;) {
        const { value, done: finished } = await reader.read()
        if (finished) break
        buffer += decoder.decode(value, { stream: true })
        let cut: number
        while ((cut = buffer.indexOf('\n\n')) >= 0) {
          const block = buffer.slice(0, cut)
          buffer = buffer.slice(cut + 2)
          for (const line of block.split('\n')) if (line.startsWith('data: ')) heard.push(JSON.parse(line.slice(6)) as Heard)
          for (const wake of waiting.splice(0)) wake()
        }
      }
    } catch {
      // Aborted by the test.
    }
    ended = true
    for (const wake of waiting.splice(0)) wake()
  })()
  return {
    heard,
    done,
    get ended() {
      return ended
    },
    /** Waits until [topics] have all been heard (each at least once), or fails after 3 seconds. */
    async until(...topics: Topic[]) {
      const deadline = Date.now() + 3000
      while (!topics.every((topic) => heard.some((one) => one.topic === topic))) {
        if (ended || Date.now() > deadline) assert.fail(`heard ${JSON.stringify(heard)}, waiting for ${topics.join(', ')}`)
        await new Promise<void>((resolve) => {
          waiting.push(resolve)
          setTimeout(resolve, 100)
        })
      }
    },
  }
}

let stores = 0
/** An approved, open store delivering in Baghdad, with one product on sale. */
async function sellingStore() {
  stores += 1
  const name = `Live Store ${stores}`
  const store = await h.signUpStore(name)
  assert.equal((await h.call('POST', `/admin/stores/${store.storeId}/approve`, { token: admin })).status, 200)
  await h.call('PUT', '/merchants/me/store', {
    token: store.token,
    body: { storeName: name, governorate: 'BAGHDAD', logoUrl: null, delivery: { governorates: [], feeInside: 3000, timeInside: '1_2_DAYS' } },
  })
  const made = await h.call('POST', '/merchants/me/products', {
    token: store.token,
    body: { name: 'Kite Studio Headphones', nameAr: 'سماعات كايت ستوديو', categoryId: '8', price: 145_000, stock: 10 },
  })
  assert.equal((await h.call('POST', `/admin/products/${made.body.data.id}/approve`, { token: admin })).status, 200)
  return { ...store, productId: made.body.data.id as string }
}

async function shopper() {
  const account = await h.signUpShopper()
  const address = await h.call('POST', '/customers/me/addresses', {
    token: account.token,
    body: { fullName: 'Amina Saleh', phone: account.phone, governorate: 'BAGHDAD', area: 'Karrada', landmark: 'Near the park' },
  })
  return { ...account, id: Number(account.user.id), addressId: address.body.data.id as string }
}

let keys = 0

describe('the live stream', () => {
  test('only with a live access token', async () => {
    assert.equal((await fetch(`${h.url}/events`)).status, 401)
    const bad = await fetch(`${h.url}/events`, { headers: { authorization: 'Bearer not-a-token' } })
    assert.equal(bad.status, 401)
    assert.equal(((await bad.json()) as { code: string }).code, 'AUTHENTICATION_ERROR')
    const who = await h.signUpShopper()
    const live = await stream(who.token)
    assert.deepEqual(live.heard, [])
  })

  test('a stream ends when its access token does', async () => {
    const who = await h.signUpShopper()
    // An access token like the server's own, of the same sign-in, lasting 3 seconds (whole seconds: 2 to 3 from now).
    const signIn = await one<{ family_id: Buffer }>(h.pool, 'SELECT family_id FROM refresh_tokens WHERE user_id = ? ORDER BY id DESC LIMIT 1', [
      who.user.id,
    ])
    const short = await new SignJWT({ typ: 'access', role: 'CUSTOMER', sid: signIn!.family_id.toString('base64url') })
      .setProtectedHeader({ alg: 'HS256' })
      .setSubject(String(who.user.id))
      .setIssuedAt()
      .setExpirationTime('3s')
      .sign(new TextEncoder().encode(testConfig().jwtSecret))
    const started = Date.now()
    const live = await stream(short)
    await live.done
    assert.equal(live.ended, true)
    assert.ok(Date.now() - started >= 1500, 'it lasted until the token ran out')
  })

  test("a store's step reaches the shopper's open stream; one store never hears another's; Saba hears the orders", async () => {
    const nova = await sellingStore()
    const atlas = await sellingStore()
    const amina = await shopper()
    const other = await shopper()
    const [aminaHears, novaHears, atlasHears, otherHears, sabaHears] = await Promise.all([
      stream(amina.token),
      stream(nova.token),
      stream(atlas.token),
      stream(other.token),
      stream(admin),
    ])

    assert.equal((await h.call('POST', '/cart/items', { token: amina.token, body: { productId: nova.productId, quantity: 1 } })).status, 200)
    const placed = await h.call('POST', '/checkout/place-order', {
      token: amina.token,
      headers: { 'idempotency-key': `live-${++keys}` },
      body: { addressId: amina.addressId, paymentMethodId: 'pm-cod' },
    })
    assert.equal(placed.status, 200, JSON.stringify(placed.body))
    const orderId = placed.body.data.order.id as string
    // The store: a new order and its notice. The shopper's other screens: the order. Saba: the order.
    await novaHears.until('orders', 'notifications')
    await aminaHears.until('orders')
    await sabaHears.until('orders')
    assert.ok(sabaHears.heard.some((one) => one.topic === 'orders' && one.id === orderId))
    assert.equal(aminaHears.heard.some((one) => one.topic === 'notifications'), false)

    // The store confirms: the shopper's open screen hears of it, with its notice.
    const part = (await h.call('GET', '/merchants/me/orders', { token: nova.token })).body.data[0].id
    aminaHears.heard.length = 0
    assert.equal((await h.call('PATCH', `/merchants/me/orders/${part}/status`, { token: nova.token, body: { status: 'CONFIRMED' } })).status, 200)
    await aminaHears.until('orders', 'notifications')
    assert.ok(aminaHears.heard.every((one) => one.topic !== 'orders' || one.id === orderId))

    // Nobody else heard a thing. (Each message is written before its request answers.)
    await new Promise((resolve) => setTimeout(resolve, 200))
    assert.deepEqual(atlasHears.heard, [])
    assert.deepEqual(otherHears.heard, [])
    // Saba's topics never reach a shopper or a store.
    assert.ok([...aminaHears.heard, ...novaHears.heard].every((one) => one.topic === 'orders' || one.topic === 'notifications'))
  })

  test("a delivery tells Saba's Finance (bills); the steps before it don't (W8)", async () => {
    const nova = await sellingStore()
    const amina = await shopper()
    const saba = await stream(admin)
    assert.equal((await h.call('POST', '/cart/items', { token: amina.token, body: { productId: nova.productId, quantity: 1 } })).status, 200)
    const placed = await h.call('POST', '/checkout/place-order', {
      token: amina.token,
      headers: { 'idempotency-key': `live-${++keys}` },
      body: { addressId: amina.addressId, paymentMethodId: 'pm-cod' },
    })
    assert.equal(placed.status, 200, JSON.stringify(placed.body))
    const part = (await h.call('GET', '/merchants/me/orders', { token: nova.token })).body.data[0].id
    const step = async (body: Record<string, unknown>) =>
      assert.equal((await h.call('PATCH', `/merchants/me/orders/${part}/status`, { token: nova.token, body })).status, 200)
    await step({ status: 'CONFIRMED' })
    await step({ status: 'PROCESSING' })
    await step({ status: 'SHIPPED', courierName: 'Ali', courierPhone: '07701112222' })
    await new Promise((resolve) => setTimeout(resolve, 200))
    assert.equal(saba.heard.some((one) => one.topic === 'bills'), false)
    // Delivered: this month's sales and owed change.
    await step({ status: 'DELIVERED' })
    await saba.until('bills')
  })

  test('told only once the change has committed, each change once; a rolled-back one tells nobody', async () => {
    const heard: Topic[] = []
    const stop = listen({ userId: 987_654, role: 'CUSTOMER', send: (topic) => void heard.push(topic), close() {} })
    try {
      await assert.rejects(
        withTransaction(h.pool, async (conn) => {
          publish(conn, 987_654, 'orders')
          throw new Error('refused')
        }),
      )
      assert.deepEqual(heard, [])
      await withTransaction(h.pool, async (conn) => {
        publish(conn, 987_654, 'orders', 1)
        publish(conn, [987_654, 987_654], 'orders', 1)
        // Not yet: the change is not committed.
        assert.deepEqual(heard, [])
      })
      assert.deepEqual(heard, ['orders'])
      // Outside a transaction the write has already been committed: told at once.
      publish(h.pool, 987_654, 'notifications')
      assert.deepEqual(heard, ['orders', 'notifications'])
    } finally {
      stop()
    }
    publish(h.pool, 987_654, 'orders')
    assert.deepEqual(heard, ['orders', 'notifications'])
  })

  test("Saba hears its pages' topics; a suspended shopper's stream ends at once", async () => {
    const sabaHears = await stream(admin)
    const store = await sellingStore()
    await sabaHears.until('stores', 'products')

    const who = await shopper()
    const whoHears = await stream(who.token)
    const ticket = await h.call('POST', '/support/tickets', {
      token: who.token,
      body: { subject: 'My order still says waiting', category: 'ORDER', description: 'I ordered this morning and it still says waiting.' },
    })
    assert.equal(ticket.status, 200)
    await sabaHears.until('tickets')
    assert.equal((await h.call('POST', `/admin/tickets/${ticket.body.data.id}/messages`, { token: admin, body: { body: 'Looking into it.' } })).status, 200)
    await whoHears.until('notifications')

    // A chat message: the other side's bell.
    const storeHears = await stream(store.token)
    const chat = (await h.call('POST', '/messages/conversations', { token: who.token, body: { merchantId: store.storeId } })).body.data
    assert.equal((await h.call('POST', `/messages/conversations/${chat.id}/messages`, { token: who.token, body: { body: 'Hello' } })).status, 200)
    await storeHears.until('notifications')

    assert.equal((await h.call('POST', `/admin/customers/${who.id}/suspend`, { token: admin, body: { reason: 'Refused three orders.' } })).status, 200)
    await sabaHears.until('customers')
    await whoHears.done
    assert.equal(whoHears.ended, true)
    // And it can't open another.
    assert.equal((await fetch(`${h.url}/events`, { headers: { authorization: `Bearer ${who.token}` } })).status, 401)
  })
})
