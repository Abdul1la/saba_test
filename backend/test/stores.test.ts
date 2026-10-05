// S2 Stores and Saba's answers (BACKEND_PLAN.md §7): store settings, the open
// switch, the public page, cities, notifications, uploads, the admin's
// stores, queue and featured rail.
import assert from 'node:assert/strict'
import { existsSync } from 'node:fs'
import path from 'node:path'
import { after, before, describe, test } from 'node:test'
import { exec, one, rows } from '../src/db/sql.js'
import { PNG, startHarness, type Harness } from './api.js'

let h: Harness
before(async () => {
  h = await startHarness()
})
after(() => h.close())

const delivery = (extra: Record<string, unknown> = {}) => ({
  governorates: ['BAGHDAD'],
  feeInside: 3000,
  timeInside: '1_2_DAYS',
  ...extra,
})

const settings = (extra: Record<string, unknown> = {}) => ({
  storeName: 'Nova Electronics',
  governorate: 'BAGHDAD',
  logoUrl: null,
  delivery: delivery(),
  ...extra,
})

async function upload(token: string, bytes: Buffer = PNG, name = 'logo.png') {
  const form = new FormData()
  form.append('file', new Blob([new Uint8Array(bytes)]), name)
  form.append('kind', 'IMAGE')
  return h.call('POST', '/media/upload', { token, form })
}

// ------------------------------------------------------------ the admin side ---

describe("Saba's answers on stores", () => {
  test('approve: from PENDING only; the store is told; the audit row is written', async () => {
    const admin = await h.signInAdmin()
    const store = await h.signUpStore('Answer Me')
    const approved = await h.call('POST', `/admin/stores/${store.storeId}/approve`, { token: admin })
    assert.equal(approved.status, 200, JSON.stringify(approved.body))
    assert.equal(approved.body.data.status, 'APPROVED')
    assert.ok(approved.body.data.answeredAt)
    const again = await h.call('POST', `/admin/stores/${store.storeId}/approve`, { token: admin })
    assert.equal(again.status, 409)
    assert.equal(again.body.code, 'CONFLICT_ERROR')

    const told = await h.call('GET', '/notifications', { token: store.token, lang: 'ar' })
    assert.equal(told.body.data[0].title, 'تمت الموافقة على متجرك')
    assert.equal(told.body.data[0].type, 'STORE')
    assert.equal(told.body.data[0].entityType, 'STORE')
    assert.equal(told.body.data[0].entityId, store.storeId)
    const audit = await rows<{ action: string }>(
      h.pool,
      "SELECT action FROM admin_actions WHERE entity_type = 'STORE' AND entity_id = ?",
      [store.storeId],
    )
    assert.deepEqual(
      audit.map((row) => row.action),
      ['STORE_APPROVE'],
    )
    // The owner's account now says so.
    const me = await h.call('GET', '/customers/me', { token: store.token })
    assert.equal(me.body.data.merchant.status, 'APPROVED')
  })

  test('reject needs a reason (422 on reason, blank is not a reason); the store is told why', async () => {
    const admin = await h.signInAdmin()
    const store = await h.signUpStore('Reject Me')
    const blank = await h.call('POST', `/admin/stores/${store.storeId}/reject`, { token: admin, body: { reason: '   ' } })
    assert.equal(blank.status, 422)
    assert.ok(blank.body.errors.reason)
    const rejected = await h.call('POST', `/admin/stores/${store.storeId}/reject`, {
      token: admin,
      body: { reason: '  No licence photo. ' },
    })
    assert.equal(rejected.status, 200)
    assert.equal(rejected.body.data.rejectionReason, 'No licence photo.')
    const told = await h.call('GET', '/notifications', { token: store.token })
    assert.equal(told.body.data[0].body, 'Reason: No licence photo.')
    assert.equal((await h.call('POST', `/admin/stores/${store.storeId}/suspend`, { token: admin, body: { reason: 'x' } })).status, 409)
  })

  test('suspend from APPROVED with a reason; unsuspend from SUSPENDED, told in its own words, not "approved" again', async () => {
    const admin = await h.signInAdmin()
    const store = await h.signUpStore('Suspend Me')
    assert.equal((await h.call('POST', `/admin/stores/${store.storeId}/suspend`, { token: admin, body: { reason: 'x' } })).status, 409)
    await h.call('POST', `/admin/stores/${store.storeId}/approve`, { token: admin })
    assert.equal((await h.call('POST', `/admin/stores/${store.storeId}/suspend`, { token: admin, body: {} })).status, 422)
    const suspended = await h.call('POST', `/admin/stores/${store.storeId}/suspend`, {
      token: admin,
      body: { reason: 'Fake products' },
    })
    assert.equal(suspended.body.data.status, 'SUSPENDED')
    assert.equal(suspended.body.data.suspensionReason, 'Fake products')
    // The owner still signs in (Q4).
    assert.equal((await h.call('GET', '/customers/me', { token: store.token })).status, 200)
    const back = await h.call('POST', `/admin/stores/${store.storeId}/unsuspend`, { token: admin })
    assert.equal(back.body.data.status, 'APPROVED')
    assert.equal(back.body.data.suspensionReason, undefined)
    const told = await h.call('GET', '/notifications', { token: store.token })
    assert.deepEqual(
      told.body.data.map((n: any) => n.title),
      ['Your store is active again', 'Your store is suspended', 'Your store is approved'],
    )
    assert.equal((await h.call('POST', `/admin/stores/${store.storeId}/unsuspend`, { token: admin })).status, 409)
  })

  test('an unknown store is 404; a store owner or a shopper gets 403; nobody 401', async () => {
    const admin = await h.signInAdmin()
    assert.equal((await h.call('POST', '/admin/stores/999999/approve', { token: admin })).status, 404)
    assert.equal((await h.call('GET', '/admin/stores/abc', { token: admin })).status, 404)
    const store = await h.signUpStore('Not An Admin')
    assert.equal((await h.call('GET', '/admin/stores', { token: store.token })).status, 403)
    const shopper = await h.signUpShopper()
    assert.equal((await h.call('POST', `/admin/stores/${store.storeId}/approve`, { token: shopper.token })).status, 403)
    assert.equal((await h.call('GET', '/admin/queue')).status, 401)
  })

  test('the queue: waiting stores, oldest first', async () => {
    const admin = await h.signInAdmin()
    const first = await h.signUpStore('Queue One')
    const second = await h.signUpStore('Queue Two')
    await exec(h.pool, 'UPDATE stores SET submitted_at = NOW(3) - INTERVAL 1 DAY WHERE id = ?', [second.storeId])
    const queue = await h.call('GET', '/admin/queue', { token: admin })
    const ids = queue.body.data.stores.map((s: any) => s.id)
    assert.ok(ids.indexOf(second.storeId) < ids.indexOf(first.storeId))
    assert.deepEqual(queue.body.data.products, [])
  })

  test('the list: newest first, counts per status for the search, the filter after the counts', async () => {
    const admin = await h.signInAdmin()
    const store = await h.signUpStore('Searchable Sweets', 'ERBIL')
    const all = await h.call('GET', '/admin/stores?q=searchable', { token: admin })
    assert.equal(all.body.data.items.length, 1)
    assert.equal(all.body.data.counts.all, 1)
    assert.equal(all.body.data.counts.PENDING, 1)
    const approvedOnly = await h.call('GET', '/admin/stores?q=searchable&status=APPROVED', { token: admin })
    assert.equal(approvedOnly.body.data.items.length, 0)
    assert.equal(approvedOnly.body.data.counts.PENDING, 1)
    // The owner's phone however it is typed; the city in either language.
    const local = store.phone.replace('+964', '0')
    const national = store.phone.replace('+964', '')
    const spaced = `+964 ${national.slice(0, 3)} ${national.slice(3, 6)} ${national.slice(6)}`
    for (const q of [local, local.slice(-4), store.phone.slice(1), spaced, 'أربيل']) {
      const found = await h.call('GET', `/admin/stores?q=${encodeURIComponent(q)}`, { token: admin })
      assert.ok(
        found.body.data.items.some((s: any) => s.id === store.storeId),
        q,
      )
    }
    const three = await h.call('GET', `/admin/stores?q=${local.slice(-3)}`, { token: admin })
    assert.ok(!three.body.data.items.some((s: any) => s.id === store.storeId))
  })
})

// -------------------------------------------------------------- featured rail ---

describe('the featured rail', () => {
  test('saves in order; refuses repeats and stores not approved; a suspended one drops off and comes back at the end', async () => {
    const admin = await h.signInAdmin()
    const [a, b, c] = [await h.signUpStore('Rail A'), await h.signUpStore('Rail B'), await h.signUpStore('Rail C')]
    const pending = await h.signUpStore('Rail Pending')
    for (const s of [a, b, c]) await h.call('POST', `/admin/stores/${s.storeId}/approve`, { token: admin })

    assert.equal(
      (await h.call('PUT', '/admin/featured-stores', { token: admin, body: { storeIds: [a.storeId, a.storeId] } })).status,
      409,
    )
    assert.equal(
      (await h.call('PUT', '/admin/featured-stores', { token: admin, body: { storeIds: [a.storeId, pending.storeId] } }))
        .status,
      409,
    )
    const saved = await h.call('PUT', '/admin/featured-stores', {
      token: admin,
      body: { storeIds: [b.storeId, a.storeId, c.storeId] },
    })
    assert.deepEqual(saved.body.data.featured, [b.storeId, a.storeId, c.storeId])

    await h.call('POST', `/admin/stores/${a.storeId}/suspend`, { token: admin, body: { reason: 'x' } })
    let rail = await h.call('GET', '/admin/featured-stores', { token: admin })
    assert.deepEqual(rail.body.data.featured, [b.storeId, c.storeId])
    assert.ok(!rail.body.data.stores.some((s: any) => s.id === a.storeId))

    // Saved while it is suspended: it keeps its place, at the end.
    await h.call('PUT', '/admin/featured-stores', { token: admin, body: { storeIds: [c.storeId, b.storeId] } })
    await h.call('POST', `/admin/stores/${a.storeId}/unsuspend`, { token: admin })
    rail = await h.call('GET', '/admin/featured-stores', { token: admin })
    assert.deepEqual(rail.body.data.featured, [c.storeId, b.storeId, a.storeId])

    const empty = await h.call('PUT', '/admin/featured-stores', { token: admin, body: { storeIds: [] } })
    assert.deepEqual(empty.body.data.featured, [])
  })
})

// --------------------------------------------------------- the store's own side ---

describe("the store's settings", () => {
  test('a new store delivers nowhere until its owner says where (BUGS 88)', async () => {
    const store = await h.signUpStore('Fresh Store')
    const got = await h.call('GET', '/merchants/me/store', { token: store.token })
    assert.equal(got.status, 200)
    assert.equal(got.body.data.storeName, 'Fresh Store')
    assert.equal(got.body.data.delivery, undefined)
  })

  test('saving: its own city is always included; fees in steps of 250; other cities need their own terms', async () => {
    const store = await h.signUpStore('Delivery Store')
    const odd = await h.call('PUT', '/merchants/me/store', {
      token: store.token,
      body: settings({ storeName: 'Delivery Store', delivery: delivery({ feeInside: 3100 }) }),
    })
    assert.equal(odd.status, 422)
    // Named as the store's form names its box (merchant_store_settings_screen.dart), as feeOutside is.
    assert.deepEqual(odd.body.errors, { feeInside: 'Use steps of 250 IQD, like 12,250 or 12,500.' })
    const noTerms = await h.call('PUT', '/merchants/me/store', {
      token: store.token,
      body: settings({ storeName: 'Delivery Store', delivery: delivery({ governorates: ['BASRA'] }) }),
    })
    assert.equal(noTerms.status, 422)
    assert.ok(noTerms.body.errors.feeOutside)
    const saved = await h.call('PUT', '/merchants/me/store', {
      token: store.token,
      body: settings({
        storeName: 'Delivery Store',
        delivery: delivery({ governorates: ['BASRA'], feeOutside: 6000, timeOutside: '3_5_DAYS' }),
      }),
    })
    assert.equal(saved.status, 200, JSON.stringify(saved.body))
    assert.deepEqual(saved.body.data.delivery, {
      governorates: ['BAGHDAD', 'BASRA'],
      feeInside: 3000,
      timeInside: '1_2_DAYS',
      feeOutside: 6000,
      timeOutside: '3_5_DAYS',
    })
    // Only its own city again: the outside terms go.
    const home = await h.call('PUT', '/merchants/me/store', {
      token: store.token,
      body: settings({ storeName: 'Delivery Store', delivery: delivery({ feeOutside: 6000, timeOutside: '3_5_DAYS' }) }),
    })
    assert.deepEqual(home.body.data.delivery, { governorates: ['BAGHDAD'], feeInside: 3000, timeInside: '1_2_DAYS' })
  })

  test('a name taken in the same city is refused; in another city it is fine', async () => {
    await h.signUpStore('Same Name', 'BASRA')
    const store = await h.signUpStore('Other Name', 'BASRA')
    const clash = await h.call('PUT', '/merchants/me/store', {
      token: store.token,
      body: settings({ storeName: ' SAME  name ', governorate: 'BASRA', delivery: delivery({ governorates: [] }) }),
    })
    assert.equal(clash.status, 422)
    assert.equal(clash.body.errors.storeName, 'A store in this city already has this name. Choose another.')
    const moved = await h.call('PUT', '/merchants/me/store', {
      token: store.token,
      body: settings({ storeName: 'Same Name', governorate: 'NAJAF', delivery: delivery({ governorates: [] }) }),
    })
    assert.equal(moved.status, 200, JSON.stringify(moved.body))
    assert.deepEqual(moved.body.data.delivery.governorates, ['NAJAF'])
  })

  test('the logo: its own upload only; kept when sent back as it is; null takes it away', async () => {
    const store = await h.signUpStore('Logo Store')
    const other = await h.signUpStore('Logo Thief')
    const uploaded = await upload(store.token)
    assert.equal(uploaded.status, 200, JSON.stringify(uploaded.body))
    const url: string = uploaded.body.data.url
    assert.match(url, /\/uploads\/images\/\d{4}\/\d{2}\/[0-9a-f]{32}\.png$/)

    const stolen = await h.call('PUT', '/merchants/me/store', { token: other.token, body: settings({ storeName: 'Logo Thief', logoUrl: url }) })
    assert.equal(stolen.status, 422)
    // Says what is wrong, not just "Not valid." (M3).
    assert.equal(stolen.body.errors.logoUrl, "This photo didn't upload. Add it again.")
    const foreign = await h.call('PUT', '/merchants/me/store', {
      token: store.token,
      body: settings({ storeName: 'Logo Store', logoUrl: 'https://evil.example/x.png' }),
    })
    assert.equal(foreign.status, 422)
    assert.equal(foreign.body.errors.logoUrl, "This photo didn't upload. Add it again.")

    const saved = await h.call('PUT', '/merchants/me/store', { token: store.token, body: settings({ storeName: 'Logo Store', logoUrl: url }) })
    assert.equal(saved.body.data.logoUrl, url)
    // The address as another device reaches this laptop: the same file.
    const viaEmulator = url.replace('127.0.0.1', '10.0.2.2')
    const kept = await h.call('PUT', '/merchants/me/store', {
      token: store.token,
      body: settings({ storeName: 'Logo Store', logoUrl: viaEmulator }),
    })
    assert.equal(kept.status, 200)
    assert.equal(kept.body.data.logoUrl, url)
    // The account reads the same full address, not the stored key.
    assert.equal((await h.call('GET', '/customers/me', { token: store.token })).body.data.merchant.logoUrl, url)
    // In use: it can't be deleted.
    assert.equal((await h.call('DELETE', `/media/${uploaded.body.data.id}`, { token: store.token })).status, 409)
    const gone = await h.call('PUT', '/merchants/me/store', { token: store.token, body: settings({ storeName: 'Logo Store' }) })
    assert.equal(gone.body.data.logoUrl, null)
  })

  test('an edited field replaces both languages; one sent back unchanged keeps both', async () => {
    const store = await h.signUpStore('Twin Store')
    await exec(h.pool, "UPDATE stores SET description = 'Phones', description_ar = 'هواتف' WHERE id = ?", [store.storeId])
    const inArabic = await h.call('GET', '/merchants/me/store', { token: store.token, lang: 'ar' })
    assert.equal(inArabic.body.data.description, 'هواتف')
    await h.call('PUT', '/merchants/me/store', {
      token: store.token,
      lang: 'ar',
      body: settings({ storeName: 'Twin Store', description: 'هواتف' }),
    })
    let row = await one<{ description: string; description_ar: string | null }>(
      h.pool,
      'SELECT description, description_ar FROM stores WHERE id = ?',
      [store.storeId],
    )
    assert.deepEqual(row, { description: 'Phones', description_ar: 'هواتف' })
    await h.call('PUT', '/merchants/me/store', {
      token: store.token,
      lang: 'ar',
      body: settings({ storeName: 'Twin Store', description: 'هواتف وإكسسوارات' }),
    })
    row = await one(h.pool, 'SELECT description, description_ar FROM stores WHERE id = ?', [store.storeId])
    assert.deepEqual(row, { description: 'هواتف وإكسسوارات', description_ar: null })
  })

  test('closing: the switch is saved, and says what is left (no orders yet)', async () => {
    const store = await h.signUpStore('Closing Store')
    const closed = await h.call('PATCH', '/merchants/me/store/open', { token: store.token, body: { isOpen: false } })
    assert.equal(closed.status, 200)
    assert.deepEqual(closed.body.data, { isOpen: false, currencyCode: 'IQD', openOrders: 0, owed: 0, returnsOpenUntil: null })
    assert.equal((await h.call('GET', '/merchants/me/store', { token: store.token })).body.data.isOpen, false)
  })

  test("a shopper can't reach a store's own routes", async () => {
    const shopper = await h.signUpShopper()
    assert.equal((await h.call('GET', '/merchants/me/store', { token: shopper.token })).status, 403)
    assert.equal((await upload(shopper.token)).status, 403)
  })
})

// ----------------------------------------------------------------- uploads ---

describe('uploads', () => {
  test('a photo is told by its bytes: a text file named .png is refused', async () => {
    const store = await h.signUpStore('Upload Store')
    const fake = await upload(store.token, Buffer.from('<?php echo 1; ?>'), 'photo.png')
    assert.equal(fake.status, 422)
    assert.equal(fake.body.errors.file, 'Upload a JPEG, PNG or WebP photo.')
  })

  test('over 5 MB is refused', async () => {
    const store = await h.signUpStore('Big Upload Store')
    const big = Buffer.concat([PNG, Buffer.alloc(5 * 1024 * 1024)])
    const reply = await upload(store.token, big)
    assert.equal(reply.status, 422)
    assert.equal(reply.body.errors.file, 'The photo is larger than 5 MB.')
  })

  test('the file is served at its address; its owner deletes it; nobody else can', async () => {
    const store = await h.signUpStore('Owner Store')
    const other = await h.signUpStore('Other Store')
    const uploaded = await upload(store.token)
    const served = await fetch(uploaded.body.data.url)
    assert.equal(served.status, 200)
    assert.deepEqual(Buffer.from(await served.arrayBuffer()), PNG)
    assert.equal((await h.call('DELETE', `/media/${uploaded.body.data.id}`, { token: other.token })).status, 404)
    assert.equal((await h.call('DELETE', `/media/${uploaded.body.data.id}`, { token: store.token })).status, 200)
    const key = new URL(uploaded.body.data.url).pathname.replace('/uploads/', '')
    assert.equal(existsSync(path.join(h.mediaDir, key)), false)
  })
})

// ------------------------------------------------------------ the shopper side ---

describe("a store's public page and the city chips", () => {
  test('only an approved store has a page; it is in the asked language', async () => {
    const admin = await h.signInAdmin()
    const store = await h.signUpStore('Public Store', 'KARBALA')
    assert.equal((await h.call('GET', `/merchants/${store.storeId}/store`)).status, 404)
    await h.call('POST', `/admin/stores/${store.storeId}/approve`, { token: admin })
    await exec(h.pool, "UPDATE stores SET description = 'Books', description_ar = 'كتب' WHERE id = ?", [store.storeId])
    const page = await h.call('GET', `/merchants/${store.storeId}/store`, { lang: 'ar' })
    assert.equal(page.status, 200)
    assert.equal(page.body.data.description, 'كتب')
    assert.equal(page.body.data.governorate, 'KARBALA')
    assert.equal(page.body.data.rating, 0)
    assert.equal(page.body.data.isOpen, true)
    // Shoppers can call the store: its owner's number.
    assert.match(page.body.data.phone, /^\+964\d{10}$/)
    await h.call('POST', `/admin/stores/${store.storeId}/suspend`, { token: admin, body: { reason: 'x' } })
    assert.equal((await h.call('GET', `/merchants/${store.storeId}/store`)).status, 404)
  })

  test('cities: governorates with an open, approved store, in the app order', async () => {
    const admin = await h.signInAdmin()
    const erbil = await h.signUpStore('Chip Erbil', 'HALABJA')
    await h.signUpStore('Chip Pending', 'MUTHANNA')
    await h.call('POST', `/admin/stores/${erbil.storeId}/approve`, { token: admin })
    let cities: string[] = (await h.call('GET', '/stores/cities')).body.data
    assert.ok(cities.includes('HALABJA'))
    assert.ok(!cities.includes('MUTHANNA'))
    assert.deepEqual(
      cities,
      ['BAGHDAD', 'BASRA', 'NINEVEH', 'ERBIL', 'SULAYMANIYAH', 'DUHOK', 'KIRKUK', 'NAJAF', 'KARBALA', 'BABYLON', 'ANBAR', 'DHI_QAR', 'DIYALA', 'SALAH_AL_DIN', 'WASIT', 'MAYSAN', 'QADISIYAH', 'MUTHANNA', 'HALABJA'].filter((c) =>
        cities.includes(c),
      ),
    )
    await h.call('PATCH', '/merchants/me/store/open', { token: erbil.token, body: { isOpen: false } })
    cities = (await h.call('GET', '/stores/cities')).body.data
    assert.ok(!cities.includes('HALABJA'))
  })
})

// ------------------------------------------------------------- notifications ---

describe('notifications', () => {
  test('own only; paged newest first; the unread count; one read; all read', async () => {
    const admin = await h.signInAdmin()
    const store = await h.signUpStore('Bell Store')
    const other = await h.signUpStore('Other Bell Store')
    await h.call('POST', `/admin/stores/${store.storeId}/approve`, { token: admin })
    await h.call('POST', `/admin/stores/${store.storeId}/suspend`, { token: admin, body: { reason: 'x' } })
    await h.call('POST', `/admin/stores/${store.storeId}/unsuspend`, { token: admin })
    await h.call('POST', `/admin/stores/${store.storeId}/suspend`, { token: admin, body: { reason: 'y' } })

    const page1 = await h.call('GET', '/notifications?page=1&perPage=2', { token: store.token })
    assert.equal(page1.body.data.length, 2)
    assert.deepEqual(page1.body.meta, { page: 1, perPage: 2, total: 4, totalPages: 2 })
    assert.equal(page1.body.data[0].body, 'Reason: y')
    assert.equal((await h.call('GET', '/notifications/unread-count', { token: store.token })).body.data.count, 4)

    const id = page1.body.data[0].id
    assert.equal((await h.call('PATCH', `/notifications/${id}`, { token: other.token, body: { isRead: true } })).status, 404)
    assert.equal((await h.call('PATCH', `/notifications/${id}`, { token: store.token, body: { isRead: true } })).status, 200)
    // Marking it read twice is still fine.
    assert.equal((await h.call('PATCH', `/notifications/${id}`, { token: store.token, body: { isRead: true } })).status, 200)
    assert.equal((await h.call('GET', '/notifications/unread-count', { token: store.token })).body.data.count, 3)
    await h.call('POST', '/notifications/read-all', { token: store.token })
    assert.equal((await h.call('GET', '/notifications/unread-count', { token: store.token })).body.data.count, 0)
    assert.equal((await h.call('GET', '/notifications', { token: other.token })).body.data.length, 0)
  })
})
