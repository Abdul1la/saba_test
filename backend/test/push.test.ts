// S10 Push (BACKEND_PLAN.md §7, §2.0 "S10"): each phone's push address; only
// what needs action or touches money is pushed, after its commit, in the
// phone's language, opening what the list opens; nobody who shouldn't gets one;
// and the Firebase sender, against a stand-in for Google.
import assert from 'node:assert/strict'
import { generateKeyPairSync } from 'node:crypto'
import { createServer, type IncomingMessage } from 'node:http'
import type { AddressInfo } from 'node:net'
import { after, before, describe, test } from 'node:test'
import { importSPKI, jwtVerify } from 'jose'
import { one } from '../src/db/sql.js'
import { withTransaction } from '../src/db/tx.js'
import { notify } from '../src/lib/notify.js'
import { fcmPush, pushesDone, type PushMessage } from '../src/lib/push.js'
import { startHarness, type Harness } from './api.js'

const sent: PushMessage[] = []
let answer: (message: PushMessage) => Promise<'sent' | 'gone'> = async () => 'sent'

let h: Harness
let admin: string
before(async () => {
  h = await startHarness({
    push: async (message) => {
      sent.push(message)
      return answer(message)
    },
  })
  admin = await h.signInAdmin()
})
after(() => h.close())

/** The pushes sent since the last look, once every one under way has finished. */
async function pushed(): Promise<PushMessage[]> {
  await pushesDone()
  return sent.splice(0)
}

const SMARTPHONES = '8'
let stores = 0
async function openStore() {
  stores += 1
  const name = `Push Store ${stores}`
  const store = await h.signUpStore(name)
  assert.equal((await h.call('POST', `/admin/stores/${store.storeId}/approve`, { token: admin })).status, 200)
  const saved = await h.call('PUT', '/merchants/me/store', {
    token: store.token,
    body: { storeName: name, governorate: 'BAGHDAD', logoUrl: null, delivery: { governorates: [], feeInside: 3000, timeInside: '1_2_DAYS' } },
  })
  assert.equal(saved.status, 200, JSON.stringify(saved.body))
  const made = await h.call('POST', '/merchants/me/products', {
    token: store.token,
    body: { name: 'Kite Studio Headphones', nameAr: 'سماعات كايت ستوديو', categoryId: SMARTPHONES, price: 145_000, stock: 50 },
  })
  assert.equal(made.status, 200, JSON.stringify(made.body))
  assert.equal((await h.call('POST', `/admin/products/${made.body.data.id}/approve`, { token: admin })).status, 200)
  return { ...store, productId: made.body.data.id as string }
}
type Store = Awaited<ReturnType<typeof openStore>>

async function shopper() {
  const account = await h.signUpShopper()
  const address = await h.call('POST', '/customers/me/addresses', {
    token: account.token,
    body: { fullName: 'Amina Saleh', phone: account.phone, governorate: 'BAGHDAD', area: 'Karrada', landmark: 'Near the park' },
  })
  assert.equal(address.status, 200, JSON.stringify(address.body))
  return { ...account, id: Number(account.user.id), addressId: address.body.data.id as string }
}
type Shopper = Awaited<ReturnType<typeof shopper>>

async function phone(who: { token: string }, token: string, language: 'en' | 'ar' = 'en') {
  const reply = await h.call('PUT', '/devices', { token: who.token, body: { token, platform: 'ANDROID', language } })
  assert.equal(reply.status, 200, JSON.stringify(reply.body))
}

let keys = 0
/** A placed order of one [store] item; its id and the store's part. */
async function order(who: Shopper, store: Store) {
  assert.equal((await h.call('POST', '/cart/items', { token: who.token, body: { productId: store.productId, quantity: 1 } })).status, 200)
  const placed = await h.call('POST', '/checkout/place-order', {
    token: who.token,
    headers: { 'idempotency-key': `push-${++keys}` },
    body: { addressId: who.addressId, paymentMethodId: 'pm-cod' },
  })
  assert.equal(placed.status, 200, JSON.stringify(placed.body))
  const part = (await h.call('GET', '/merchants/me/orders', { token: store.token })).body.data[0].id as string
  return { id: placed.body.data.order.id as string, part }
}

async function step(store: Store, part: string, status: string, extra: Record<string, unknown> = {}) {
  const reply = await h.call('PATCH', `/merchants/me/orders/${part}/status`, { token: store.token, body: { status, ...extra } })
  assert.equal(reply.status, 200, JSON.stringify(reply.body))
}
const ship = (store: Store, part: string) => step(store, part, 'SHIPPED', { courierName: 'Ali', courierPhone: '07701112222' })

/** The push's words and target are its notification's, in the phone's language. */
async function sameAsList(message: PushMessage, language: 'en' | 'ar') {
  const row = await one<{ title_en: string; title_ar: string; body_en: string; body_ar: string; entity_type: string; entity_id: string }>(
    h.pool,
    'SELECT title_en, title_ar, body_en, body_ar, entity_type, entity_id FROM notifications WHERE id = ?',
    [message.data.notificationId],
  )
  assert.ok(row, 'a push names its notification')
  assert.equal(message.title, language === 'ar' ? row.title_ar : row.title_en)
  assert.equal(message.body, language === 'ar' ? row.body_ar : row.body_en)
  assert.deepEqual([message.data.targetType, message.data.targetId], [row.entity_type, row.entity_id])
}

// ------------------------------------------------------------- the phones ---

describe('a phone’s push address', () => {
  test('kept per token, and moved to whoever signs in on that phone; forgotten only by its own account', async () => {
    const a = await shopper()
    const b = await shopper()
    await phone(a, 'shared-phone-token')
    const owner = () => one<{ user_id: number; language: string }>(h.pool, 'SELECT user_id, language FROM device_tokens WHERE token = ?', ['shared-phone-token'])
    assert.equal((await owner())!.user_id, a.id)
    // The next person to sign in on it takes it over, with the phone's language.
    await phone(b, 'shared-phone-token', 'ar')
    assert.deepEqual({ ...(await owner()) }, { user_id: b.id, language: 'ar' })
    assert.equal((await h.call('DELETE', '/devices', { token: a.token, body: { token: 'shared-phone-token' } })).status, 200)
    assert.equal((await owner())!.user_id, b.id)
    assert.equal((await h.call('DELETE', '/devices', { token: b.token, body: { token: 'shared-phone-token' } })).status, 200)
    assert.equal(await owner(), undefined)
  })

  test('refused: a token with a space, an unknown platform or language; an admin has no phone here', async () => {
    const a = await shopper()
    for (const body of [
      { token: 'has space', platform: 'ANDROID', language: 'en' },
      { token: 'ok-token', platform: 'WINDOWS', language: 'en' },
      { token: 'ok-token', platform: 'IOS', language: 'fr' },
    ]) {
      assert.equal((await h.call('PUT', '/devices', { token: a.token, body })).status, 422, JSON.stringify(body))
    }
    assert.equal((await h.call('PUT', '/devices', { token: admin, body: { token: 'admin-token', platform: 'IOS', language: 'en' } })).status, 403)
  })

  test('deleting an account forgets its phones', async () => {
    const a = await shopper()
    await phone(a, 'soon-gone-token')
    assert.equal((await h.call('DELETE', '/customers/me', { token: a.token })).status, 200)
    assert.equal(await one(h.pool, 'SELECT id FROM device_tokens WHERE token = ?', ['soon-gone-token']), undefined)
  })
})

// ---------------------------------------------------------- what pushes ---

describe('what is pushed', () => {
  test('orders and returns: the store its new orders, cancels, returns and "never came"; the shopper confirmed, shipped, delivered, declined and each return answer', async () => {
    const store = await openStore()
    const amina = await shopper()
    await phone(store, 'store-phone', 'en')
    await phone(amina, 'amina-phone', 'ar')
    await pushed()

    // A new order: the store, in English.
    const first = await order(amina, store)
    let got = await pushed()
    assert.deepEqual(got.map((one) => one.token), ['store-phone'])
    await sameAsList(got[0]!, 'en')
    assert.equal(got[0]!.data.targetType, 'STORE_ORDER')

    // Its steps: confirmed, shipped, delivered reach Amina, in Arabic; preparing waits in the list.
    await step(store, first.part, 'CONFIRMED')
    got = await pushed()
    assert.deepEqual(got.map((one) => one.token), ['amina-phone'])
    await sameAsList(got[0]!, 'ar')
    assert.deepEqual([got[0]!.data.targetType, got[0]!.data.targetId], ['ORDER', first.id])
    await step(store, first.part, 'PROCESSING')
    assert.deepEqual(await pushed(), [])
    await ship(store, first.part)
    assert.equal((await pushed()).length, 1)
    await step(store, first.part, 'DELIVERED')
    assert.deepEqual((await pushed()).map((one) => one.token), ['amina-phone'])

    // A return: asked reaches the store; approved and refunded reach Amina.
    const item = (await h.call('GET', `/orders/${first.id}`, { token: amina.token })).body.data.items[0].id
    const asked = await h.call('POST', '/returns', { token: amina.token, body: { orderId: first.id, reason: 'DAMAGED', items: [{ orderItemId: item, quantity: 1 }] } })
    assert.equal(asked.status, 200, JSON.stringify(asked.body))
    assert.deepEqual((await pushed()).map((one) => one.token), ['store-phone'])
    for (const status of ['APPROVED', 'REFUNDED']) {
      assert.equal((await h.call('PATCH', `/merchants/me/returns/${asked.body.data.id}`, { token: store.token, body: { status } })).status, 200)
      const answered = await pushed()
      assert.deepEqual(answered.map((one) => one.token), ['amina-phone'])
      assert.equal(answered[0]!.data.targetType, 'RETURN')
    }

    // "Never came" on a delivered part reaches the store.
    const second = await order(amina, store)
    await pushed()
    await step(store, second.part, 'CONFIRMED')
    await step(store, second.part, 'PROCESSING')
    await ship(store, second.part)
    await step(store, second.part, 'DELIVERED')
    await pushed()
    const no = await h.call('POST', `/orders/${second.id}/received`, { token: amina.token, body: { merchantId: store.storeId, received: false } })
    assert.equal(no.status, 200, JSON.stringify(no.body))
    assert.deepEqual((await pushed()).map((one) => one.token), ['store-phone'])

    // Declined by the store reaches Amina; refused at the door doesn't.
    const declined = await order(amina, store)
    await pushed()
    await step(store, declined.part, 'CANCELLED', { reason: 'OUT_OF_STOCK' })
    assert.deepEqual((await pushed()).map((one) => one.token), ['amina-phone'])
    const refused = await order(amina, store)
    await step(store, refused.part, 'CONFIRMED')
    await step(store, refused.part, 'PROCESSING')
    await ship(store, refused.part)
    await pushed()
    await step(store, refused.part, 'REFUSED')
    assert.deepEqual(await pushed(), [])

    // Cancelled by Amina reaches the store.
    const cancelled = await order(amina, store)
    await pushed()
    const out = await h.call('POST', `/orders/${cancelled.id}/cancel`, { token: amina.token, body: { reason: 'CHANGED_MIND' } })
    assert.equal(out.status, 200, JSON.stringify(out.body))
    assert.deepEqual((await pushed()).map((one) => one.token), ['store-phone'])
  })

  test("chat messages both ways; Saba's answers on products, stores and tickets wait in the list", async () => {
    const store = await openStore()
    const amina = await shopper()
    await phone(store, 'chat-store-phone')
    await phone(amina, 'chat-amina-phone')
    await pushed()

    const chat = (await h.call('POST', '/messages/conversations', { token: amina.token, body: { merchantId: store.storeId } })).body.data.id
    assert.equal((await h.call('POST', `/messages/conversations/${chat}/messages`, { token: amina.token, body: { body: 'Is it in stock?' } })).status, 200)
    const toStore = await pushed()
    assert.deepEqual(toStore.map((one) => one.token), ['chat-store-phone'])
    assert.deepEqual([toStore[0]!.data.targetType, toStore[0]!.data.targetId], ['CONVERSATION', String(chat)])
    assert.equal((await h.call('POST', `/messages/conversations/${chat}/messages`, { token: store.token, body: { body: 'Yes, 50.' } })).status, 200)
    assert.deepEqual((await pushed()).map((one) => one.token), ['chat-amina-phone'])

    // A product approved, a store suspended and back, a ticket answered: notified, not pushed.
    const made = await h.call('POST', '/merchants/me/products', {
      token: store.token,
      body: { name: 'Nova Case', nameAr: 'غطاء نوفا', categoryId: SMARTPHONES, price: 10_000, stock: 5 },
    })
    assert.equal((await h.call('POST', `/admin/products/${made.body.data.id}/approve`, { token: admin })).status, 200)
    assert.equal((await h.call('POST', `/admin/stores/${store.storeId}/suspend`, { token: admin, body: { reason: 'Checking.' } })).status, 200)
    assert.equal((await h.call('POST', `/admin/stores/${store.storeId}/unsuspend`, { token: admin })).status, 200)
    const ticket = await h.call('POST', '/support/tickets', {
      token: amina.token,
      body: { subject: 'Where is it?', category: 'DELIVERY', description: 'My order has not come yet.' },
    })
    assert.equal(ticket.status, 200, JSON.stringify(ticket.body))
    assert.equal((await h.call('POST', `/admin/tickets/${ticket.body.data.id}/messages`, { token: admin, body: { body: 'On its way.' } })).status, 200)
    assert.deepEqual(await pushed(), [])
    const told = await one<{ n: number }>(h.pool, "SELECT COUNT(*) AS n FROM notifications WHERE user_id = ? AND type IN ('PRODUCT_APPROVAL', 'STORE')", [store.ownerId])
    assert.ok(Number(told!.n) >= 3, 'they are still in the list')
  })

  test("nobody who shouldn't: a suspended shopper gets none; a suspended store's owner still does", async () => {
    const store = await openStore()
    const amina = await shopper()
    await phone(store, 'suspended-store-phone')
    await phone(amina, 'suspended-amina-phone')
    const chat = (await h.call('POST', '/messages/conversations', { token: amina.token, body: { merchantId: store.storeId } })).body.data.id
    const placed = await order(amina, store)
    await pushed()

    // The store is suspended: its owner still works its open orders and chats (Q4).
    assert.equal((await h.call('POST', `/admin/stores/${store.storeId}/suspend`, { token: admin, body: { reason: 'Checking.' } })).status, 200)
    await pushed()
    assert.equal((await h.call('POST', `/messages/conversations/${chat}/messages`, { token: amina.token, body: { body: 'Still there?' } })).status, 200)
    assert.deepEqual((await pushed()).map((one) => one.token), ['suspended-store-phone'])

    // The shopper is suspended: the store's step is written to her list, and pushed to nobody.
    assert.equal((await h.call('POST', `/admin/customers/${amina.id}/suspend`, { token: admin, body: { reason: 'Refused three orders.' } })).status, 200)
    await step(store, placed.part, 'CONFIRMED')
    assert.deepEqual(await pushed(), [])
    const kept = await one(h.pool, "SELECT id FROM notifications WHERE user_id = ? AND entity_type = 'ORDER' ORDER BY id DESC LIMIT 1", [amina.id])
    assert.ok(kept, 'the notification itself is written')
  })
})

// ------------------------------------------------------------- failures ---

describe('when pushing goes wrong', () => {
  test('a rolled-back change pushes nothing', async () => {
    const amina = await shopper()
    await phone(amina, 'rollback-phone')
    await pushed()
    const words = { en: { title: 'Never', body: 'Never sent.' }, ar: { title: 'أبداً', body: 'لن يُرسل.' } }
    await assert.rejects(
      withTransaction(h.pool, async (conn) => {
        await notify(conn, amina.id, 'ORDER', words, undefined, { push: true })
        throw new Error('rolled back')
      }),
      /rolled back/,
    )
    assert.deepEqual(await pushed(), [])
    // The same, committed: pushed once.
    await withTransaction(h.pool, (conn) => notify(conn, amina.id, 'ORDER', words, undefined, { push: true }))
    assert.deepEqual((await pushed()).map((one) => one.title), ['Never'])
  })

  test("a push that fails undoes nothing; a token Firebase calls gone is forgotten", async (t) => {
    t.after(() => {
      answer = async () => 'sent'
    })
    const store = await openStore()
    const amina = await shopper()
    await phone(amina, 'broken-phone')
    const placed = await order(amina, store)
    await pushed()

    answer = async () => {
      throw new Error('Firebase is down')
    }
    await step(store, placed.part, 'CONFIRMED')
    assert.equal((await pushed()).length, 1)
    const part = await one<{ status: string }>(h.pool, 'SELECT status FROM order_store_parts WHERE id = ?', [placed.part])
    assert.equal(part!.status, 'CONFIRMED')
    assert.ok(await one(h.pool, 'SELECT id FROM device_tokens WHERE token = ?', ['broken-phone']), 'kept: it may work next time')

    answer = async () => 'gone'
    await step(store, placed.part, 'PROCESSING')
    await ship(store, placed.part)
    assert.equal((await pushed()).length, 1)
    assert.equal(await one(h.pool, 'SELECT id FROM device_tokens WHERE token = ?', ['broken-phone']), undefined)
  })
})

// ----------------------------------------------------- the Firebase sender ---

describe('the Firebase sender (HTTP v1), against a stand-in for Google', () => {
  test('a service-account token, kept and reused; the message as FCM takes it; UNREGISTERED is gone; anything else throws', async (t) => {
    const { privateKey, publicKey } = generateKeyPairSync('rsa', {
      modulusLength: 2048,
      privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
      publicKeyEncoding: { type: 'spki', format: 'pem' },
    })
    const tokenRequests: URLSearchParams[] = []
    const sends: { authorization: string | undefined; body: any }[] = []
    let reply: { status: number; body: unknown } = { status: 200, body: { name: 'projects/saba-app/messages/1' } }
    const read = async (req: IncomingMessage) => {
      let text = ''
      for await (const chunk of req) text += String(chunk)
      return text
    }
    const google = createServer(async (req, res) => {
      const text = await read(req)
      res.setHeader('content-type', 'application/json')
      if (req.url === '/token') {
        tokenRequests.push(new URLSearchParams(text))
        res.end(JSON.stringify({ access_token: 'ya29.stand-in', expires_in: 3600, token_type: 'Bearer' }))
        return
      }
      sends.push({ authorization: req.headers.authorization, body: JSON.parse(text) })
      res.statusCode = reply.status
      res.end(JSON.stringify(reply.body))
    }).listen(0, '127.0.0.1')
    t.after(() => new Promise((resolve) => google.close(resolve)))
    await new Promise((resolve) => google.once('listening', resolve))
    const base = `http://127.0.0.1:${(google.address() as AddressInfo).port}`

    const send = fcmPush({
      projectId: 'saba-app',
      clientEmail: 'push@saba-app.iam.gserviceaccount.com',
      privateKey,
      tokenUrl: `${base}/token`,
      sendUrl: `${base}/send`,
    })
    const message: PushMessage = {
      token: 'fcm-token-1',
      platform: 'ANDROID',
      title: 'New order SB-100012',
      body: 'Amina ordered 1 item.',
      data: { notificationId: '7', targetType: 'STORE_ORDER', targetId: '12' },
    }
    assert.equal(await send(message), 'sent')
    assert.equal(await send({ ...message, token: 'fcm-token-2' }), 'sent')

    // One token for both: signed by the service account, for FCM's scope.
    assert.equal(tokenRequests.length, 1)
    assert.equal(tokenRequests[0]!.get('grant_type'), 'urn:ietf:params:oauth:grant-type:jwt-bearer')
    const { payload } = await jwtVerify(tokenRequests[0]!.get('assertion')!, await importSPKI(publicKey, 'RS256'), {
      issuer: 'push@saba-app.iam.gserviceaccount.com',
      audience: `${base}/token`,
    })
    assert.equal(payload.scope, 'https://www.googleapis.com/auth/firebase.messaging')
    assert.deepEqual(sends[0], {
      authorization: 'Bearer ya29.stand-in',
      body: {
        message: {
          token: 'fcm-token-1',
          notification: { title: 'New order SB-100012', body: 'Amina ordered 1 item.' },
          data: { notificationId: '7', targetType: 'STORE_ORDER', targetId: '12' },
          android: { notification: { channel_id: 'saba_default' } },
        },
      },
    })

    reply = { status: 404, body: { error: { status: 'NOT_FOUND', details: [{ errorCode: 'UNREGISTERED' }] } } }
    assert.equal(await send(message), 'gone')
    reply = { status: 500, body: { error: { status: 'INTERNAL' } } }
    await assert.rejects(send(message), (error: Error) => /500/.test(error.message) && !error.message.includes('PRIVATE KEY'))
  })
})
