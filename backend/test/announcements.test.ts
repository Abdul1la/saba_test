// Saba's announcements (the user's call, 2026-10-08): from the admin website,
// one notification to every customer, every store owner, or both, in their
// list and on their phones; suspended accounts get nothing; a second click
// within two minutes is refused; each send is listed.
import assert from 'node:assert/strict'
import { after, before, describe, test } from 'node:test'
import { rows } from '../src/db/sql.js'
import { pushesDone, type PushMessage } from '../src/lib/push.js'
import { startHarness, type Harness } from './api.js'

const sent: PushMessage[] = []

let h: Harness
let admin: string
before(async () => {
  h = await startHarness({
    push: async (message) => {
      sent.push(message)
      return 'sent'
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

async function phone(who: { token: string }, token: string) {
  const reply = await h.call('PUT', '/devices', { token: who.token, body: { token, platform: 'ANDROID', language: 'ar' } })
  assert.equal(reply.status, 200, JSON.stringify(reply.body))
}

const announcementsOf = (userId: number) =>
  rows<{ title_en: string; title_ar: string; body_en: string; body_ar: string; entity_type: string | null }>(
    h.pool,
    "SELECT title_en, title_ar, body_en, body_ar, entity_type FROM notifications WHERE user_id = ? AND type = 'ANNOUNCEMENT' ORDER BY id",
    [userId],
  )

const send = (audience: string, title: string, body: string, token = admin) =>
  h.call('POST', '/admin/announcements', { token, body: { audience, title, body } })

describe("Saba's announcements", () => {
  test('to the chosen people, in their list and on their phones; the suspended get nothing; each send is listed', async () => {
    const amina = await h.signUpShopper()
    const omar = await h.signUpShopper()
    const away = await h.signUpShopper()
    const suspended = await h.call('POST', `/admin/customers/${away.user.id}/suspend`, { token: admin, body: { reason: 'Test' } })
    assert.equal(suspended.status, 200, JSON.stringify(suspended.body))
    const store = await h.signUpStore('Announce Store')
    await phone(amina, 'amina-phone')
    await phone(store, 'store-phone')
    await pushed()

    // Only Saba's staff.
    assert.equal((await h.call('GET', '/admin/announcements', { token: amina.token })).status, 403)
    assert.equal((await send('EVERYONE', 'Hi', 'Hello', amina.token)).status, 403)

    const before = await h.call('GET', '/admin/announcements', { token: admin })
    assert.equal(before.status, 200, JSON.stringify(before.body))
    assert.deepEqual(before.body.data.recipients, { EVERYONE: 3, CUSTOMERS: 2, MERCHANTS: 1 })
    assert.deepEqual(before.body.data.sent, [])

    // Every customer: the two in use, as typed in both languages, opening nothing.
    const sale = await send('CUSTOMERS', 'خصم ٢٠٪ هذا الأسبوع', 'على كل الهواتف حتى الجمعة.')
    assert.equal(sale.status, 200, JSON.stringify(sale.body))
    assert.equal(sale.body.data.recipients, 2)
    for (const who of [amina, omar]) {
      assert.deepEqual(await announcementsOf(Number(who.user.id)), [
        { title_en: 'خصم ٢٠٪ هذا الأسبوع', title_ar: 'خصم ٢٠٪ هذا الأسبوع', body_en: 'على كل الهواتف حتى الجمعة.', body_ar: 'على كل الهواتف حتى الجمعة.', entity_type: null },
      ])
    }
    assert.deepEqual(await announcementsOf(Number(away.user.id)), [])
    assert.deepEqual(await announcementsOf(store.ownerId), [])
    const phones = await pushed()
    assert.deepEqual(
      phones.map((message) => [message.token, message.title, message.body]),
      [['amina-phone', 'خصم ٢٠٪ هذا الأسبوع', 'على كل الهواتف حتى الجمعة.']],
    )
    // In the shopper's own list.
    const list = await h.call('GET', '/notifications', { token: amina.token })
    assert.equal(list.body.data[0].title, 'خصم ٢٠٪ هذا الأسبوع')

    // A second click: refused, nothing sent twice. Other words: sent.
    const again = await send('CUSTOMERS', 'خصم ٢٠٪ هذا الأسبوع', 'على كل الهواتف حتى الجمعة.')
    assert.equal(again.status, 409)
    assert.equal((await announcementsOf(Number(amina.user.id))).length, 1)
    assert.equal((await send('MERCHANTS', 'New: free delivery', 'Turn it on in Settings.')).body.data.recipients, 1)
    assert.deepEqual((await pushed()).map((message) => message.token), ['store-phone'])
    assert.equal((await send('EVERYONE', 'Eid hours', 'Support answers until 6 pm.')).body.data.recipients, 3)

    // The list of what was sent, newest first, with who sent it.
    const after = (await h.call('GET', '/admin/announcements', { token: admin })).body.data
    assert.deepEqual(
      after.sent.map((one: { audience: string; title: string; recipients: number }) => [one.audience, one.title, one.recipients]),
      [
        ['EVERYONE', 'Eid hours', 3],
        ['MERCHANTS', 'New: free delivery', 1],
        ['CUSTOMERS', 'خصم ٢٠٪ هذا الأسبوع', 2],
      ],
    )
    assert.ok(after.sent[0].sentBy.length > 0)
  })

  test('a title and a message are needed, within their lengths; only the three audiences', async () => {
    assert.equal((await send('EVERYONE', '  ', 'Hello')).status, 422)
    assert.equal((await send('EVERYONE', 'Hi', '')).status, 422)
    assert.equal((await send('EVERYONE', 'x'.repeat(121), 'Hello')).status, 422)
    assert.equal((await send('EVERYONE', 'Hi', 'x'.repeat(1001))).status, 422)
    assert.equal((await send('SOME_CUSTOMERS', 'Hi', 'Hello')).status, 422)
  })
})
