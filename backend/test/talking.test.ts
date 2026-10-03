// S7 Talking (BACKEND_PLAN.md §7): chats between a shopper and a store, and
// support tickets on both sides. Only the two sides of a chat can read it; a
// reply reopens a waiting ticket; a closed one takes none; the opener is told.
import assert from 'node:assert/strict'
import { after, before, describe, test } from 'node:test'
import { one, rows } from '../src/db/sql.js'
import { diskStore, photoSignature } from '../src/lib/storage.js'
import { deleteRemovedChatPhotos } from '../src/modules/account.js'
import { PNG, startHarness, type Harness } from './api.js'

let h: Harness
let admin: string
before(async () => {
  h = await startHarness()
  admin = await h.signInAdmin()
})
after(() => h.close())

let stores = 0
async function approvedStore() {
  stores += 1
  const name = `Talking Store ${stores}`
  const store = await h.signUpStore(name)
  assert.equal((await h.call('POST', `/admin/stores/${store.storeId}/approve`, { token: admin })).status, 200)
  return { ...store, name }
}

const lastNotice = (userId: number) =>
  one<{ type: string; title_en: string; body_en: string; title_ar: string; body_ar: string; entity_type: string; entity_id: string }>(
    h.pool,
    'SELECT type, title_en, body_en, title_ar, body_ar, entity_type, entity_id FROM notifications WHERE user_id = ? ORDER BY id DESC LIMIT 1',
    [userId],
  )

// ------------------------------------------------------------------ chats ---

describe('chats', () => {
  const start = (token: string, merchantId: string) => h.call('POST', '/messages/conversations', { token, body: { merchantId } })
  const write = (token: string, id: string, body: string) => h.call('POST', `/messages/conversations/${id}/messages`, { token, body: { body } })
  const inbox = async (token: string) => (await h.call('GET', '/messages/conversations', { token })).body.data

  test('the shopper starts it, both sides write and each is told; unread until read; newest first', async () => {
    const store = await approvedStore()
    const shopper = await h.signUpShopper()
    const shopperId = Number(shopper.user.id)

    const started = await start(shopper.token, store.storeId)
    assert.equal(started.status, 200, JSON.stringify(started.body))
    const chat = started.body.data
    assert.deepEqual(
      { ...chat, updatedAt: undefined },
      { id: chat.id, title: store.name, lastMessage: null, lastMessageIsPhoto: false, updatedAt: undefined, unreadCount: 0, blocked: false, blockedByMe: false },
    )
    // The same chat again; not listed until someone writes.
    assert.equal((await start(shopper.token, store.storeId)).body.data.id, chat.id)
    assert.deepEqual(await inbox(shopper.token), [])
    assert.deepEqual(await inbox(store.token), [])

    const asked = await write(shopper.token, chat.id, '  Is this phone in stock in blue?  ')
    assert.equal(asked.status, 200, JSON.stringify(asked.body))
    assert.deepEqual({ ...asked.body.data, id: undefined, sentAt: undefined }, {
      id: undefined,
      body: 'Is this phone in stock in blue?',
      sentAt: undefined,
      isMine: true,
      senderName: 'Amina Saleh',
    })
    // The store is told, and the notice opens the chat.
    let notice = await lastNotice(store.ownerId)
    assert.deepEqual(
      [notice!.type, notice!.title_en, notice!.body_en, notice!.title_ar, notice!.entity_type, notice!.entity_id],
      ['MESSAGE', 'Message from Amina Saleh', 'Is this phone in stock in blue?', 'رسالة من Amina Saleh', 'CONVERSATION', chat.id],
    )
    // Unread for the store, not for the shopper who wrote it.
    const [storeCard] = await inbox(store.token)
    assert.deepEqual([storeCard.id, storeCard.title, storeCard.lastMessage, storeCard.unreadCount], [chat.id, 'Amina Saleh', 'Is this phone in stock in blue?', 1])
    assert.equal((await inbox(shopper.token))[0].unreadCount, 0)
    assert.equal((await h.call('POST', `/messages/conversations/${chat.id}/read`, { token: store.token })).status, 200)
    assert.equal((await inbox(store.token))[0].unreadCount, 0)

    const answered = await write(store.token, chat.id, `Yes, in blue and black. ${'We deliver across Baghdad the same day. '.repeat(3)}`)
    assert.equal(answered.status, 200)
    assert.equal(answered.body.data.senderName, store.name)
    notice = await lastNotice(shopperId)
    assert.equal(notice!.title_en, `Message from ${store.name}`)
    // A long message is cut in the notice, not in the chat.
    assert.equal(notice!.body_en.length, 80)
    assert.ok(notice!.body_en.endsWith('…'))
    const [shopperCard] = await inbox(shopper.token)
    assert.equal(shopperCard.unreadCount, 1)
    assert.ok(shopperCard.lastMessage.startsWith('Yes, in blue and black.'))

    // Newest first, paged; each side reads its own as its own.
    const page = await h.call('GET', `/messages/conversations/${chat.id}/messages?perPage=1`, { token: shopper.token })
    assert.equal(page.body.meta.total, 2)
    assert.equal(page.body.data.length, 1)
    assert.equal(page.body.data[0].isMine, false)
    const all = (await h.call('GET', `/messages/conversations/${chat.id}/messages`, { token: store.token })).body.data
    assert.deepEqual(
      all.map((m: { isMine: boolean; senderName: string }) => [m.isMine, m.senderName]),
      [[true, store.name], [false, 'Amina Saleh']],
    )
    assert.equal((await h.call('GET', `/messages/conversations/${chat.id}`, { token: store.token })).body.data.title, 'Amina Saleh')
  })

  test('only its two sides: anyone else gets 404; Saba and the store owner cannot start one', async () => {
    const store = await approvedStore()
    const other = await approvedStore()
    const shopper = await h.signUpShopper()
    const stranger = await h.signUpShopper()
    const chat = (await start(shopper.token, store.storeId)).body.data
    assert.equal((await write(shopper.token, chat.id, 'Hello')).status, 200)

    for (const token of [stranger.token, other.token]) {
      assert.equal((await h.call('GET', `/messages/conversations/${chat.id}`, { token })).status, 404)
      assert.equal((await h.call('GET', `/messages/conversations/${chat.id}/messages`, { token })).status, 404)
      assert.equal((await write(token, chat.id, 'Let me in')).status, 404)
      assert.equal((await h.call('POST', `/messages/conversations/${chat.id}/read`, { token })).status, 404)
    }
    assert.deepEqual(await inbox(stranger.token), [])
    assert.deepEqual(await inbox(other.token), [])
    assert.equal((await h.call('GET', '/messages/conversations', { token: admin })).status, 403)
    assert.equal((await start(store.token, other.storeId)).status, 403)
    assert.equal(Number((await one<{ n: number }>(h.pool, 'SELECT COUNT(*) AS n FROM messages WHERE conversation_id = ?', [chat.id]))!.n), 1)
  })

  test('starting: an approved store only, once even four at a time; a message is not blank or too long', async () => {
    const store = await approvedStore()
    const waiting = await h.signUpStore('Talking Waiting Store')
    const shopper = await h.signUpShopper()
    assert.equal((await start(shopper.token, waiting.storeId)).status, 404)
    assert.equal((await start(shopper.token, '999999')).status, 404)
    const blank = await start(shopper.token, '  ')
    assert.equal(blank.status, 422)
    assert.equal(blank.body.errors.merchantId, 'Choose a store to message.')

    const replies = await Promise.all([1, 2, 3, 4].map(() => start(shopper.token, store.storeId)))
    assert.deepEqual(replies.map((reply) => reply.status), [200, 200, 200, 200])
    assert.equal(new Set(replies.map((reply) => reply.body.data.id)).size, 1)
    const chat = replies[0]!.body.data.id
    assert.equal((await write(shopper.token, chat, '   ')).status, 422)
    assert.equal((await write(shopper.token, chat, 'x'.repeat(2001))).status, 422)
    assert.equal((await write(shopper.token, chat, 'x'.repeat(2000))).status, 200)
  })

  test("a deleted shopper's chat stays with the store, with no name left", async () => {
    const store = await approvedStore()
    const shopper = await h.signUpShopper()
    const chat = (await start(shopper.token, store.storeId)).body.data
    await write(shopper.token, chat.id, 'Do you deliver to Erbil?')
    assert.equal((await h.call('DELETE', '/customers/me', { token: shopper.token })).status, 200)
    const card = (await inbox(store.token)).find((one: { id: string }) => one.id === chat.id)
    assert.equal(card.title, 'Deleted account')
    assert.equal((await h.call('GET', '/messages/conversations', { token: store.token, lang: 'ar' })).body.data[0].title, 'حساب محذوف')
  })

  test('blocking: either side blocks; nobody writes while it is blocked; only the blocker unblocks its own block', async () => {
    const store = await approvedStore()
    const shopper = await h.signUpShopper()
    const chat = (await start(shopper.token, store.storeId)).body.data
    assert.equal((await write(shopper.token, chat.id, 'Hello')).status, 200)
    const blockAs = (token: string) => h.call('POST', `/messages/conversations/${chat.id}/block`, { token })
    const unblockAs = (token: string) => h.call('DELETE', `/messages/conversations/${chat.id}/block`, { token })
    const view = async (token: string) => {
      const { blocked, blockedByMe } = (await h.call('GET', `/messages/conversations/${chat.id}`, { token })).body.data
      return { blocked, blockedByMe }
    }

    const blocked = await blockAs(store.token)
    assert.equal(blocked.status, 200, JSON.stringify(blocked.body))
    assert.deepEqual([blocked.body.data.blocked, blocked.body.data.blockedByMe], [true, true])
    assert.deepEqual(await view(shopper.token), { blocked: true, blockedByMe: false })
    for (const token of [shopper.token, store.token]) {
      const refused = await write(token, chat.id, 'Are you there?')
      assert.deepEqual([refused.status, refused.body.message], [409, "Messages are off in this chat: it's blocked."])
    }
    // The shopper's unblock is not the store's: still blocked.
    assert.equal((await unblockAs(shopper.token)).status, 200)
    assert.equal((await write(shopper.token, chat.id, 'Hello?')).status, 409)
    // Both blocked; the store lifts its own; the shopper's still stands.
    assert.equal((await blockAs(shopper.token)).status, 200)
    assert.equal((await unblockAs(store.token)).status, 200)
    assert.deepEqual(await view(store.token), { blocked: true, blockedByMe: false })
    assert.equal((await write(store.token, chat.id, 'Sorry')).status, 409)
    assert.equal((await unblockAs(shopper.token)).status, 200)
    assert.deepEqual(await view(shopper.token), { blocked: false, blockedByMe: false })
    assert.equal((await write(store.token, chat.id, 'Welcome back')).status, 200)
    // Only its two sides.
    const stranger = await h.signUpShopper()
    assert.equal((await blockAs(stranger.token)).status, 404)
  })
})

// ---------------------------------------------------------------- reports ---

describe('reports', () => {
  const report = (token: string, targetType: string, targetId: string, reason = 'OFFENSIVE', description?: string) =>
    h.call('POST', '/reports', { token, body: { targetType, targetId, reason, ...(description && { description }) } })
  const reported = async (query = '') => (await h.call('GET', `/admin/reports${query}`, { token: admin })).body.data

  async function listedProduct(token: string) {
    const made = await h.call('POST', '/merchants/me/products', {
      token,
      body: { name: 'Nova Phone', nameAr: 'هاتف نوفا', categoryId: '8', price: 250_000, stock: 5 },
    })
    assert.equal(made.status, 200, JSON.stringify(made.body))
    assert.equal((await h.call('POST', `/admin/products/${made.body.data.id}/approve`, { token: admin })).status, 200)
    return made.body.data.id as string
  }

  test('a product, a store and a chat: once per person; never your own; unknown or unseen is 404; the reason is from the list', async () => {
    const store = await approvedStore()
    const productId = await listedProduct(store.token)
    const shopper = await h.signUpShopper()
    const other = await h.signUpShopper()

    assert.equal((await report(shopper.token, 'PRODUCT', productId, 'COUNTERFEIT', 'Fake box')).status, 200)
    // Twice by the same person: kept once.
    assert.equal((await report(shopper.token, 'PRODUCT', productId, 'SPAM')).status, 200)
    assert.equal((await report(other.token, 'PRODUCT', productId, 'MISLEADING')).status, 200)
    assert.equal((await report(shopper.token, 'STORE', store.storeId)).status, 200)
    // Its own store and product: not found; nor a store or product nobody can see.
    assert.equal((await report(store.token, 'STORE', store.storeId)).status, 404)
    assert.equal((await report(store.token, 'PRODUCT', productId)).status, 404)
    const waiting = await h.signUpStore('Waiting Reported Store')
    assert.equal((await report(shopper.token, 'STORE', waiting.storeId)).status, 404)
    assert.equal((await report(shopper.token, 'PRODUCT', '999999')).status, 404)
    const bad = await report(shopper.token, 'PRODUCT', productId, 'BORING')
    assert.deepEqual([bad.status, Object.keys(bad.body.errors)], [422, ['reason']])
    assert.equal((await report(shopper.token, 'USER', '1')).status, 422)

    const items = (await reported('?type=PRODUCT')).items
    const item = items.find((one: { targetId: string }) => one.targetId === productId)
    assert.deepEqual([item.id, item.type, item.status, item.title, item.store.storeName], [`PRODUCT-${productId}`, 'PRODUCT', 'OPEN', 'Nova Phone', store.name])
    assert.deepEqual(
      item.reports.map((r: { reason: string; reporterRole: string }) => [r.reason, r.reporterRole]),
      [['MISLEADING', 'CUSTOMER'], ['COUNTERFEIT', 'CUSTOMER']],
    )
    assert.equal(item.reports[1].description, 'Fake box')
  })

  test('a chat report keeps its last messages; a store reports a shopper too; only a side of the chat', async () => {
    const store = await approvedStore()
    const shopper = await h.signUpShopper()
    const chat = (await h.call('POST', '/messages/conversations', { token: shopper.token, body: { merchantId: store.storeId } })).body.data
    for (let i = 1; i <= 22; i++) {
      const token = i % 2 ? shopper.token : store.token
      assert.equal((await h.call('POST', `/messages/conversations/${chat.id}/messages`, { token, body: { body: `Message ${i}` } })).status, 200)
    }
    assert.equal((await report(store.token, 'CONVERSATION', chat.id, 'OFFENSIVE', 'Insults')).status, 200)
    const stranger = await h.signUpShopper()
    assert.equal((await report(stranger.token, 'CONVERSATION', chat.id)).status, 404)
    const item = (await reported('?type=CONVERSATION')).items.find((one: { targetId: string }) => one.targetId === chat.id)
    assert.deepEqual([item.title, item.customer.fullName, item.store.storeName], [`Amina Saleh · ${store.name}`, 'Amina Saleh', store.name])
    const [only] = item.reports
    assert.equal(only.reporterRole, 'MERCHANT')
    // The last 20, oldest first, as they were.
    assert.equal(only.evidence.length, 20)
    assert.deepEqual([only.evidence[0].body, only.evidence[0].from], ['Message 3', 'CUSTOMER'])
    assert.deepEqual([only.evidence[19].body, only.evidence[19].from], ['Message 22', 'STORE'])
  })

  test("Saba dismisses a target's reports or marks them handled; once; with its audit row; counts per status", async () => {
    const store = await approvedStore()
    const productId = await listedProduct(store.token)
    const shopper = await h.signUpShopper()
    assert.equal((await report(shopper.token, 'PRODUCT', productId)).status, 200)
    assert.equal((await report(shopper.token, 'STORE', store.storeId)).status, 200)

    const dismissed = await h.call('POST', `/admin/reports/PRODUCT/${productId}/dismiss`, { token: admin })
    assert.equal(dismissed.status, 200, JSON.stringify(dismissed.body))
    assert.deepEqual([dismissed.body.data.status, dismissed.body.data.reports[0].status], ['DISMISSED', 'DISMISSED'])
    assert.equal((await h.call('POST', `/admin/reports/PRODUCT/${productId}/dismiss`, { token: admin })).status, 409)
    const resolved = await h.call('POST', `/admin/reports/STORE/${store.storeId}/resolve`, { token: admin })
    assert.equal(resolved.body.data.status, 'ACTIONED')
    // A new report opens it again.
    const other = await h.signUpShopper()
    assert.equal((await report(other.token, 'STORE', store.storeId)).status, 200)
    const item = (await reported('?status=OPEN')).items.find((one: { id: string }) => one.id === `STORE-${store.storeId}`)
    assert.deepEqual(item.reports.map((r: { status: string }) => r.status), ['OPEN', 'ACTIONED'])
    assert.equal((await h.call('POST', '/admin/reports/PRODUCT/999999/dismiss', { token: admin })).status, 404)
    assert.equal((await h.call('POST', `/admin/reports/USER/${productId}/dismiss`, { token: admin })).status, 404)
    const audit = await rows<{ action: string; entity_id: string }>(
      h.pool,
      "SELECT action, entity_id FROM admin_actions WHERE entity_type = 'REPORT' AND entity_id IN (?, ?) ORDER BY id",
      [`PRODUCT-${productId}`, `STORE-${store.storeId}`],
    )
    assert.deepEqual(audit.map((a) => [a.action, a.entity_id]), [['REPORTS_DISMISS', `PRODUCT-${productId}`], ['REPORTS_RESOLVE', `STORE-${store.storeId}`]])
    const { counts } = await reported()
    assert.ok(counts.all >= 2 && counts.OPEN >= 1 && counts.DISMISSED >= 1)
    // Shoppers and stores can't read Saba's list.
    assert.equal((await h.call('GET', '/admin/reports', { token: shopper.token })).status, 403)
  })

  test('reported again by the same person after Saba closed it: the report opens again with its new words (final review 3)', async () => {
    const store = await approvedStore()
    const productId = await listedProduct(store.token)
    const shopper = await h.signUpShopper()
    assert.equal((await report(shopper.token, 'PRODUCT', productId, 'SPAM', 'First words')).status, 200)
    assert.equal((await h.call('POST', `/admin/reports/PRODUCT/${productId}/dismiss`, { token: admin })).status, 200)
    assert.equal((await report(shopper.token, 'PRODUCT', productId, 'COUNTERFEIT', 'Fake again')).status, 200)
    const item = (await reported('?type=PRODUCT&status=OPEN&perPage=100')).items.find((one: { targetId: string }) => one.targetId === productId)
    assert.deepEqual([item.status, item.reports.map((r: any) => [r.reason, r.description, r.status])], ['OPEN', [['COUNTERFEIT', 'Fake again', 'OPEN']]])
    assert.equal(Number((await one<{ n: number }>(h.pool, "SELECT COUNT(*) AS n FROM reports WHERE target_type = 'PRODUCT' AND target_id = ?", [productId]))!.n), 1)
    // Sent again while open: kept as it was.
    assert.equal((await report(shopper.token, 'PRODUCT', productId, 'OTHER')).status, 200)
    assert.equal((await reported('?type=PRODUCT&perPage=100')).items.find((one: { targetId: string }) => one.targetId === productId).reports[0].reason, 'COUNTERFEIT')
  })

  test("Saba's list a page at a time (the app's #4): newest first, the whole list's counts, a status within it", async () => {
    const store = await approvedStore()
    const shopper = await h.signUpShopper()
    const products: string[] = []
    for (let i = 0; i < 3; i++) {
      products.push(await listedProduct(store.token))
      assert.equal((await report(shopper.token, 'PRODUCT', products[i]!)).status, 200)
    }
    assert.equal((await h.call('POST', `/admin/reports/PRODUCT/${products[0]}/dismiss`, { token: admin })).status, 200)
    const list = async (query: string) => {
      const reply = await h.call('GET', `/admin/reports${query}`, { token: admin })
      assert.equal(reply.status, 200, JSON.stringify(reply.body))
      return reply.body as { data: { items: { id: string; status: string }[]; counts: Record<string, number> }; meta: Record<string, number> }
    }
    const whole = await list('?type=PRODUCT&perPage=100')
    assert.deepEqual([whole.data.items.length, whole.meta.total], [whole.data.counts.all, whole.data.counts.all])
    assert.deepEqual(whole.data.items.slice(0, 3).map((item) => [item.id, item.status]), [
      [`PRODUCT-${products[2]}`, 'OPEN'],
      [`PRODUCT-${products[1]}`, 'OPEN'],
      [`PRODUCT-${products[0]}`, 'DISMISSED'],
    ])
    const first = await list('?type=PRODUCT&page=1&perPage=2')
    const second = await list('?type=PRODUCT&page=2&perPage=2')
    assert.deepEqual([...first.data.items, ...second.data.items].map((item) => item.id), whole.data.items.slice(0, 4).map((item) => item.id))
    assert.deepEqual(first.meta, { page: 1, perPage: 2, total: whole.data.counts.all, totalPages: Math.ceil(whole.data.counts.all! / 2) })
    assert.deepEqual(first.data.counts, whole.data.counts)
    // A status: its own total and items, the same counts.
    const open = await list('?type=PRODUCT&status=OPEN&page=1&perPage=1')
    assert.deepEqual([open.meta.total, open.data.items.map((item) => item.id)], [whole.data.counts.OPEN, [`PRODUCT-${products[2]}`]])
    assert.deepEqual(open.data.counts, whole.data.counts)
    // No page asked: page 1, 50 a page.
    const unasked = await list('')
    assert.deepEqual([unasked.meta.page, unasked.meta.perPage], [1, 50])
    assert.equal((await h.call('GET', '/admin/reports?perPage=101', { token: admin })).status, 422)
  })
})

// ---------------------------------------------------------------- tickets ---

describe('tickets', () => {
  const open = (token: string, extra: Record<string, unknown> = {}) =>
    h.call('POST', '/support/tickets', {
      token,
      body: { subject: 'My order still says waiting', category: 'ORDER', description: 'I ordered this morning and it still says waiting.', ...extra },
    })
  const reply = (token: string, id: string, body: string) => h.call('POST', `/support/tickets/${id}/messages`, { token, body: { body } })
  const answer = (id: string, body: string) => h.call('POST', `/admin/tickets/${id}/messages`, { token: admin, body: { body } })
  const move = (id: string, status: string) => h.call('POST', `/admin/tickets/${id}/status`, { token: admin, body: { status } })
  const statusOf = async (token: string, id: string) => (await h.call('GET', `/support/tickets/${id}`, { token })).body.data.status

  test("a deleted shopper's tickets keep what was said, not their name or number (the reviewer's item 14)", async () => {
    const shopper = await h.signUpShopper()
    const made = (await open(shopper.token)).body.data
    assert.equal((await reply(shopper.token, made.id, 'Any news?')).status, 200)
    assert.equal((await h.call('DELETE', '/customers/me', { token: shopper.token })).status, 200)
    const stored = await one<{ opener_name: string; opener_phone: string }>(h.pool, 'SELECT opener_name, opener_phone FROM support_tickets WHERE id = ?', [made.id])
    assert.deepEqual(stored, { opener_name: '', opener_phone: '' })
    const seen = (await h.call('GET', `/admin/tickets/${made.id}`, { token: admin })).body.data
    assert.deepEqual([seen.openedBy.name, seen.openedBy.phone], ['Deleted account', ''])
    assert.ok(seen.messages.filter((m: { isFromCustomer: boolean }) => m.isFromCustomer).every((m: { authorName: string }) => m.authorName === 'Deleted account'))
    assert.equal((await h.call('GET', `/admin/tickets/${made.id}`, { token: admin, lang: 'ar' })).body.data.openedBy.name, 'حساب محذوف')
    assert.equal(seen.messages.at(-1).body, 'Any news?')
  })

  test('opened by a shopper in their name, by a store in its name; a reference; only its opener reads it', async () => {
    const shopper = await h.signUpShopper()
    const store = await approvedStore()
    const made = await open(shopper.token)
    assert.equal(made.status, 200, JSON.stringify(made.body))
    const ticket = made.body.data
    assert.equal(ticket.reference, `T-${5000 + Number(ticket.id)}`)
    assert.deepEqual(
      [ticket.subject, ticket.category, ticket.status, ticket.lastMessage, ticket.messageCount, ticket.createdAt],
      ['My order still says waiting', 'ORDER', 'OPEN', 'I ordered this morning and it still says waiting.', 1, ticket.updatedAt],
    )
    assert.deepEqual(ticket.openedBy, { kind: 'SHOPPER', name: 'Amina Saleh', phone: shopper.phone })

    const theirs = (await open(store.token, { subject: 'How do we pay last month’s bill?', category: 'PAYMENT' })).body.data
    assert.deepEqual(theirs.openedBy, { kind: 'STORE', name: store.name, phone: store.phone, storeId: store.storeId })

    // Each sees its own.
    assert.deepEqual(
      (await h.call('GET', '/support/tickets', { token: shopper.token })).body.data.map((row: { id: string }) => row.id),
      [ticket.id],
    )
    const thread = (await h.call('GET', `/support/tickets/${ticket.id}/messages`, { token: shopper.token })).body.data
    assert.deepEqual(
      thread.map((m: { body: string; isFromCustomer: boolean; authorName: string }) => [m.body, m.isFromCustomer, m.authorName]),
      [['I ordered this morning and it still says waiting.', true, 'Amina Saleh']],
    )
    for (const path of [`/support/tickets/${ticket.id}`, `/support/tickets/${ticket.id}/messages`]) {
      assert.equal((await h.call('GET', path, { token: store.token })).status, 404)
    }
    assert.equal((await reply(store.token, ticket.id, 'Not mine')).status, 404)
    assert.equal((await h.call('GET', '/support/tickets', { token: admin })).status, 403)

    // The app's own limits: a subject of 4, a description of 10 to 2,000.
    const short = await open(shopper.token, { subject: 'Hi' })
    assert.equal(short.status, 422)
    assert.equal(short.body.errors.subject, 'Use at least 4 characters.')
    assert.equal((await open(shopper.token, { description: 'Help' })).status, 422)
    assert.equal((await open(shopper.token, { description: 'x'.repeat(2001) })).status, 422)
    assert.equal((await open(shopper.token, { category: 'COMPLAINT' })).status, 422)
  })

  test("Saba answers and the opener is told; a reply reopens a waiting or resolved ticket; a closed one takes none", async () => {
    const shopper = await h.signUpShopper()
    const shopperId = Number(shopper.user.id)
    const ticket = (await open(shopper.token)).body.data

    const answered = await answer(ticket.id, 'We have asked the store. It leaves today.')
    assert.equal(answered.status, 200, JSON.stringify(answered.body))
    const last = answered.body.data.messages.at(-1)
    assert.deepEqual([last.isFromCustomer, last.authorName, last.body], [false, undefined, 'We have asked the store. It leaves today.'])
    assert.equal(answered.body.data.lastMessage, 'We have asked the store. It leaves today.')
    assert.equal(answered.body.data.status, 'OPEN')
    let notice = await lastNotice(shopperId)
    assert.deepEqual(
      [notice!.type, notice!.title_en, notice!.body_en, notice!.title_ar, notice!.entity_type, notice!.entity_id],
      ['TICKET', 'Saba support answered you', `Ticket ${ticket.reference}: We have asked the store. It leaves today.`, 'ردّ دعم سبأ عليك', 'TICKET', ticket.id],
    )
    assert.equal((await h.call('GET', `/support/tickets/${ticket.id}/messages`, { token: shopper.token })).body.data.length, 2)

    // Waiting for them: told; their reply opens it again.
    assert.equal((await move(ticket.id, 'WAITING_FOR_CUSTOMER')).status, 200)
    notice = await lastNotice(shopperId)
    assert.deepEqual([notice!.title_en, notice!.body_en, notice!.title_ar], [`Ticket ${ticket.reference}`, 'Saba support is waiting for your answer.', `التذكرة ${ticket.reference}`])
    assert.equal((await move(ticket.id, 'WAITING_FOR_CUSTOMER')).status, 409)
    const replied = await reply(shopper.token, ticket.id, 'Here is the photo of the box.')
    assert.equal(replied.status, 200)
    assert.deepEqual([replied.body.data.isFromCustomer, replied.body.data.authorName], [true, 'Amina Saleh'])
    assert.equal(await statusOf(shopper.token, ticket.id), 'OPEN')
    // Resolved, then a reply: open again. Being worked on: it stays.
    await move(ticket.id, 'RESOLVED')
    await reply(shopper.token, ticket.id, 'It happened again.')
    assert.equal(await statusOf(shopper.token, ticket.id), 'OPEN')
    await move(ticket.id, 'IN_PROGRESS')
    await reply(shopper.token, ticket.id, 'Any news?')
    assert.equal(await statusOf(shopper.token, ticket.id), 'IN_PROGRESS')
    assert.equal((await h.call('GET', `/support/tickets/${ticket.id}`, { token: shopper.token })).body.data.lastMessage, 'Any news?')

    // Closed: neither side writes until Saba opens it again.
    assert.equal((await move(ticket.id, 'CLOSED')).status, 200)
    notice = await lastNotice(shopperId)
    assert.equal(notice!.body_en, 'It is closed. Open a new ticket if you need more help.')
    const refused = await reply(shopper.token, ticket.id, 'Hello?')
    assert.equal(refused.status, 409)
    assert.equal(refused.body.message, 'This ticket is closed. Open a new one if you need more help.')
    assert.equal((await answer(ticket.id, 'One more thing.')).status, 409)
    const count = async () => Number((await one<{ n: number }>(h.pool, 'SELECT COUNT(*) AS n FROM support_messages WHERE ticket_id = ?', [ticket.id]))!.n)
    assert.equal(await count(), 5)
    assert.equal((await move(ticket.id, 'OPEN')).status, 200)
    assert.equal((await reply(shopper.token, ticket.id, 'Thank you.')).status, 200)
    assert.equal(await count(), 6)
    // Every status change is kept.
    const audit = await rows<{ details: { status: string } }>(
      h.pool,
      "SELECT details FROM admin_actions WHERE entity_type = 'TICKET' AND entity_id = ? ORDER BY id",
      [ticket.id],
    )
    assert.deepEqual(
      audit.map((row) => row.details.status),
      ['WAITING_FOR_CUSTOMER', 'RESOLVED', 'IN_PROGRESS', 'CLOSED', 'OPEN'],
    )
    // Blank answers and unknown statuses are refused; a missing ticket is not found.
    assert.equal((await answer(ticket.id, '  ')).status, 422)
    assert.equal((await move(ticket.id, 'DONE')).status, 422)
    assert.equal((await answer('999999', 'Hello')).status, 404)
    assert.equal((await h.call('GET', '/admin/tickets/999999', { token: admin })).status, 404)
    assert.equal((await h.call('GET', `/admin/tickets/${ticket.id}`, { token: shopper.token })).status, 403)
  })

  test("Saba's list: the newest activity first; counts by status within who opened it; by opener within the status", async () => {
    const shopper = await h.signUpShopper()
    const store = await approvedStore()
    const mine = (await open(shopper.token)).body.data
    const theirs = (await open(store.token, { category: 'PRODUCT' })).body.data
    await move(theirs.id, 'IN_PROGRESS')
    await answer(mine.id, 'Looking into it.')

    const list = async (query = '') => (await h.call('GET', `/admin/tickets${query}`, { token: admin })).body.data
    const all = await list()
    assert.deepEqual(all.items.slice(0, 2).map((row: { id: string }) => row.id), [mine.id, theirs.id])
    assert.ok(all.items.every((row: { updatedAt: string }, i: number) => i === 0 || all.items[i - 1].updatedAt >= row.updatedAt))
    const rowOf = (data: any, id: string) => data.items.find((row: { id: string }) => row.id === id)
    assert.deepEqual([rowOf(all, mine.id).messageCount, rowOf(all, mine.id).lastMessage], [2, 'Looking into it.'])

    const counted = await rows<{ status: string; kind: string }>(h.pool, 'SELECT status, opened_by_kind AS kind FROM support_tickets')
    const tally = (list: { status: string }[]) => list.reduce<Record<string, number>>((counts, row) => ({ ...counts, [row.status]: (counts[row.status] ?? 0) + 1 }), { all: list.length })
    assert.deepEqual(all.counts, tally(counted))
    assert.deepEqual(all.byOpener, { SHOPPER: counted.filter((row) => row.kind === 'SHOPPER').length, STORE: counted.filter((row) => row.kind === 'STORE').length })

    const stores = await list('?openedBy=STORE')
    assert.ok(stores.items.length > 0 && stores.items.every((row: any) => row.openedBy.kind === 'STORE'))
    assert.deepEqual(stores.counts, tally(counted.filter((row) => row.kind === 'STORE')))
    const working = await list('?status=IN_PROGRESS')
    assert.ok(working.items.every((row: any) => row.status === 'IN_PROGRESS') && rowOf(working, theirs.id))
    assert.deepEqual(working.counts, all.counts)
    assert.deepEqual(working.byOpener, {
      SHOPPER: counted.filter((row) => row.kind === 'SHOPPER' && row.status === 'IN_PROGRESS').length,
      STORE: counted.filter((row) => row.kind === 'STORE' && row.status === 'IN_PROGRESS').length,
    })

    const sheet = (await h.call('GET', `/admin/tickets/${mine.id}`, { token: admin })).body.data
    assert.deepEqual(
      sheet.messages.map((m: { isFromCustomer: boolean }) => m.isFromCustomer),
      [true, false],
    )
    assert.deepEqual(sheet.openedBy, { kind: 'SHOPPER', name: 'Amina Saleh', phone: shopper.phone })
    assert.equal((await h.call('GET', '/admin/tickets?status=LOST', { token: admin })).status, 422)
  })
})

// ------------------------------------------------------------- chat photos ---

describe('chat photos', () => {
  /** A JPEG as a phone writes it: Exif with its orientation (6) and a GPS block holding a latitude. */
  function phonePhoto(): Buffer {
    const tiff = Buffer.alloc(82)
    const w16 = (value: number, at: number) => tiff.writeUInt16LE(value, at)
    const w32 = (value: number, at: number) => tiff.writeUInt32LE(value, at)
    tiff.write('II', 0, 'latin1')
    w16(42, 2)
    w32(8, 4) // IFD0 at 8
    w16(2, 8) // two entries
    w16(0x0112, 10), w16(3, 12), w32(1, 14), w16(6, 18) // orientation 6
    w16(0x8825, 22), w16(4, 24), w32(1, 26), w32(38, 30) // GPS block at 38
    w32(0, 34) // no next IFD
    w16(1, 38) // one GPS entry
    w16(0x0002, 40), w16(5, 42), w32(3, 44), w32(56, 48) // latitude: 3 rationals at 56
    w32(0, 52)
    for (let i = 0; i < 6; i++) w32(33 + i, 56 + i * 4)
    const exif = Buffer.concat([Buffer.from('Exif\0\0', 'latin1'), tiff])
    const app1 = Buffer.alloc(4)
    app1.writeUInt16BE(0xffe1, 0)
    app1.writeUInt16BE(exif.length + 2, 2)
    return Buffer.concat([Buffer.from([0xff, 0xd8]), app1, exif, Buffer.from([0xff, 0xd9])])
  }
  const form = (bytes: Buffer, name = 'photo.jpg') => {
    const data = new FormData()
    data.append('file', new Blob([new Uint8Array(bytes)]), name)
    return data
  }
  const sendPhoto = (token: string, chatId: string, bytes = phonePhoto()) =>
    h.call('POST', `/messages/conversations/${chatId}/photos`, { token, form: form(bytes) })
  async function chatBetween() {
    const store = await approvedStore()
    const shopper = await h.signUpShopper()
    const chat = (await h.call('POST', '/messages/conversations', { token: shopper.token, body: { merchantId: store.storeId } })).body.data
    return { store, shopper, chat: chat as { id: string } }
  }
  const thread = async (token: string, chatId: string) =>
    (await h.call('GET', `/messages/conversations/${chatId}/messages`, { token })).body.data as { id: string; body: string; photoUrl?: string; photoRemoved?: string }[]

  test("a photo both ways: private to its chat, its location gone, told as 'Sent a photo'; refused while blocked", async () => {
    const { store, shopper, chat } = await chatBetween()
    const sent = await sendPhoto(shopper.token, chat.id)
    assert.equal(sent.status, 200, JSON.stringify(sent.body))
    assert.equal(sent.body.data.body, '')
    const link = sent.body.data.photoUrl as string
    // The store sees it, and opens it: the orientation kept, the latitude gone.
    assert.equal((await thread(store.token, chat.id))[0]!.photoUrl, link)
    const opened = Buffer.from(await (await fetch(link)).arrayBuffer())
    const original = phonePhoto()
    assert.equal(opened.length, original.length)
    const tiff = 12 // after FFD8, the APP1 marker and length, and "Exif\0\0"
    assert.equal(opened.readUInt16LE(tiff + 18), 6)
    assert.equal(opened.readUInt16LE(tiff + 38), 0)
    assert.ok(opened.subarray(tiff + 56, tiff + 80).every((byte) => byte === 0))
    // Told, in each language; the chat list says a photo.
    const told = await lastNotice(store.ownerId)
    assert.deepEqual([told!.body_en, told!.body_ar], ['Sent a photo', 'أرسل صورة'])
    const card = (await h.call('GET', '/messages/conversations', { token: shopper.token })).body.data.find((c: { id: string }) => c.id === chat.id)
    assert.deepEqual([card.lastMessage, card.lastMessageIsPhoto], [null, true])
    // And back the other way.
    assert.equal((await sendPhoto(store.token, chat.id, PNG)).status, 200)

    // Private: no link without a good, live signature; never on the public path; no stranger in the chat.
    const tampered = link.replace(/s=[^&]+$/, 's=AAAA')
    assert.equal((await fetch(tampered)).status, 404)
    const key = new URL(link).pathname.replace('/api/v1/chat-photos/', 'chats/')
    const past = Math.floor(Date.now() / 1000) - 60
    const expired = `${h.url}/chat-photos/${key.slice(6)}?for=chat&e=${past}&s=${photoSignature('test-jwt-secret-at-least-32-characters-long', 'chat', key, past)}`
    assert.equal((await fetch(expired)).status, 404)
    assert.equal((await fetch(`${h.url.replace('/api/v1', '')}/uploads/${key}`)).status, 404)
    const stranger = await h.signUpShopper()
    assert.equal((await sendPhoto(stranger.token, chat.id)).status, 404)
    assert.equal((await h.call('POST', `/messages/conversations/${chat.id}/photos`, { form: form(phonePhoto()) })).status, 401)
    assert.equal((await sendPhoto(shopper.token, chat.id, Buffer.from('not a photo'))).status, 422)
    // Blocked: no photo either.
    assert.equal((await h.call('POST', `/messages/conversations/${chat.id}/block`, { token: store.token })).status, 200)
    assert.equal((await sendPhoto(shopper.token, chat.id)).status, 409)
  })

  test("a reported chat shows Saba its photos; a deleted account's photos go, but not while an open report shows them; Saba removes one", async () => {
    const { store, shopper, chat } = await chatBetween()
    assert.equal((await sendPhoto(shopper.token, chat.id)).status, 200)
    const storePhoto = (await sendPhoto(store.token, chat.id, PNG)).body.data as { id: string; photoUrl: string }
    const shopperLink = (await thread(store.token, chat.id)).find((m) => m.id !== storePhoto.id)!.photoUrl!
    const key = new URL(shopperLink).pathname.replace('/api/v1/chat-photos/', 'chats/')
    assert.equal((await h.call('POST', '/reports', { token: store.token, body: { targetType: 'CONVERSATION', targetId: chat.id, reason: 'OFFENSIVE' } })).status, 200)
    const evidence = async () =>
      (await h.call('GET', '/admin/reports?type=CONVERSATION&perPage=100', { token: admin })).body.data.items.find((i: { targetId: string }) => i.targetId === chat.id)
        .reports[0].evidence as { messageId: string; photoUrl?: string; photoRemoved?: string }[]
    const shown = (await evidence()).find((m) => m.messageId !== storePhoto.id)!
    assert.equal((await fetch(shown.photoUrl!)).status, 200)

    // The shopper deletes their account: the photo shows as removed to the store and its link stops,
    // but Saba still opens it while the report waits, and the file stays.
    assert.equal((await h.call('DELETE', '/customers/me', { token: shopper.token })).status, 200)
    assert.equal((await thread(store.token, chat.id)).find((m) => m.id !== storePhoto.id)!.photoRemoved, 'ACCOUNT')
    assert.equal((await fetch(shopperLink)).status, 404)
    const kept = (await evidence()).find((m) => m.messageId !== storePhoto.id)!
    assert.deepEqual([(await fetch(kept.photoUrl!)).status, kept.photoRemoved], [200, 'ACCOUNT'])
    const files = diskStore(h.mediaDir)
    await deleteRemovedChatPhotos(h.pool, files)
    assert.notEqual(await files.read(key), null)
    // Report closed: the file goes at the next run.
    assert.equal((await h.call('POST', `/admin/reports/CONVERSATION/${chat.id}/dismiss`, { token: admin })).status, 200)
    await deleteRemovedChatPhotos(h.pool, files)
    assert.equal(await files.read(key), null)

    // Saba removes the store's photo: removed for both, its file deleted at once, once.
    const removed = await h.call('POST', `/admin/messages/${storePhoto.id}/remove-photo`, { token: admin })
    assert.equal(removed.status, 200, JSON.stringify(removed.body))
    assert.equal((await thread(store.token, chat.id)).find((m) => m.id === storePhoto.id)!.photoRemoved, 'SABA')
    assert.equal((await fetch(storePhoto.photoUrl)).status, 404)
    assert.equal(await files.read(new URL(storePhoto.photoUrl).pathname.replace('/api/v1/chat-photos/', 'chats/')), null)
    assert.equal((await h.call('POST', `/admin/messages/${storePhoto.id}/remove-photo`, { token: admin })).status, 409)
    assert.equal((await h.call('POST', `/admin/messages/${storePhoto.id}/remove-photo`, { token: store.token })).status, 403)
  })
})
