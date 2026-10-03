// Saba's own pages for categories, Home banners and brands (the user's call,
// 2026-10-01), and what shoppers and stores see of them at once.
import assert from 'node:assert/strict'
import { after, before, describe, test } from 'node:test'
import { one } from '../src/db/sql.js'
import { t } from '../src/lib/i18n.js'
import { PNG, startHarness, type Harness } from './api.js'

let h: Harness
let admin: string
before(async () => {
  h = await startHarness()
  admin = await h.signInAdmin()
})
after(() => h.close())

const as = (method: string, path: string, body?: unknown) => h.call(method, path, { token: admin, ...(body !== undefined && { body }) })

let stores = 0
async function approvedStore() {
  stores += 1
  const store = await h.signUpStore(`Catalogue Store ${stores}`)
  assert.equal((await as('POST', `/admin/stores/${store.storeId}/approve`)).status, 200)
  return store
}
type Store = Awaited<ReturnType<typeof approvedStore>>

async function upload(token: string) {
  const form = new FormData()
  form.append('file', new Blob([new Uint8Array(PNG)]), 'picture.png')
  form.append('kind', 'IMAGE')
  const reply = await h.call('POST', '/media/upload', { token, form })
  assert.equal(reply.status, 200, JSON.stringify(reply.body))
  return reply.body.data.url as string
}

let names = 0
async function category(parentId: string | null = null, extra: Record<string, unknown> = {}) {
  names += 1
  const reply = await as('POST', '/admin/categories', { name: `Gadgets ${names}`, nameAr: `أجهزة ${names}`, parentId, imageUrl: null, ...extra })
  assert.equal(reply.status, 200, JSON.stringify(reply.body))
  return reply.body.data as { id: string; name: string; nameAr: string; parentId: string | null; hidden: boolean; productCount: number; imageUrl: string | null }
}

function save(store: Store, categoryId: string, name: string, extra: Record<string, unknown> = {}) {
  return h.call('POST', '/merchants/me/products', {
    token: store.token,
    body: { name, nameAr: 'منتج للتجربة', categoryId, price: 100_000, stock: 5, ...extra },
  })
}

/** A product of [store] in [categoryId], approved by Saba unless told not to. */
async function product(store: Store, categoryId: string, name: string, extra: Record<string, unknown> = {}, approve = true) {
  const made = await save(store, categoryId, name, extra)
  assert.equal(made.status, 200, JSON.stringify(made.body))
  if (approve) assert.equal((await as('POST', `/admin/products/${made.body.data.id}/approve`)).status, 200)
  return made.body.data as { id: string; brand: { id: string; name: string } | null }
}

const tree = async (lang?: string) =>
  (await h.call('GET', '/categories', lang ? { lang } : {})).body.data as { id: string; name: string; imageUrl: string | null; children: { id: string }[] }[]
const everyId = (found: Awaited<ReturnType<typeof tree>>) => [...found.map((c) => c.id), ...found.flatMap((c) => c.children.map((k) => k.id))]
const search = async (q: string) => ((await h.call('GET', `/products?perPage=100&q=${encodeURIComponent(q)}`)).body.data as { id: string }[]).map((p) => p.id)
const productRow = (id: string) =>
  one<{ category_id: number; brand_id: number | null; status: string; updated_at: Date }>(h.pool, 'SELECT category_id, brand_id, status, updated_at FROM products WHERE id = ?', [id])

// ------------------------------------------------------------ categories ---

describe('categories', () => {
  test("Saba's new category: its picture, last on its level, shown to shoppers and pickable by stores at once; two levels; a name used on its level", async () => {
    const picture = await upload(admin)
    const top = await category(null, { imageUrl: picture })
    assert.equal(top.imageUrl, picture)
    const shown = await tree()
    assert.equal(shown.at(-1)!.id, top.id)
    const sub = await category(top.id)
    assert.deepEqual((await tree()).at(-1)!.children.map((c) => c.id), [sub.id])
    // Two levels: nothing under a sub-category.
    const deep = await as('POST', '/admin/categories', { name: 'Too deep', nameAr: 'عميق جداً', parentId: sub.id, imageUrl: null })
    assert.deepEqual([deep.status, deep.body.errors?.parentId], [422, t('en', 'category.twoLevels')])
    // A name its level already has, whatever its case.
    const twin = await as('POST', '/admin/categories', { name: top.name.toUpperCase(), nameAr: 'اسم آخر', parentId: null, imageUrl: null })
    assert.deepEqual([twin.status, twin.body.errors?.name], [422, t('en', 'category.nameTaken')])
    // A store's picture is not Saba's to use.
    const store = await approvedStore()
    const theirs = await as('POST', '/admin/categories', { name: 'Borrowed', nameAr: 'مستعار', parentId: null, imageUrl: await upload(store.token) })
    assert.deepEqual([theirs.status, theirs.body.errors?.imageUrl], [422, t('en', 'media.notUploaded')])
    // A store puts a product in it straight away.
    await product(store, sub.id, 'First Gadget In It')
    assert.equal((await as('GET', '/admin/categories')).body.data.find((c: { id: string }) => c.id === top.id).children[0].productCount, 1)
    assert.equal((await h.call('GET', '/admin/categories', { token: store.token })).status, 403)
  })

  test("a level's new order, and the whole level each time", async () => {
    const [a, b] = [await category(), await category()]
    const level = (await tree()).map((c) => c.id)
    const wanted = [...level.filter((id) => id !== a.id && id !== b.id), b.id, a.id]
    const ordered = await as('POST', '/admin/categories/order', { parentId: null, ids: wanted })
    assert.equal(ordered.status, 200, JSON.stringify(ordered.body))
    assert.deepEqual((await tree()).map((c) => c.id), wanted)
    const short = await as('POST', '/admin/categories/order', { parentId: null, ids: wanted.slice(1) })
    assert.deepEqual([short.status, short.body.message], [409, 'The list changed while you were ordering it. Refresh and try again.'])
    const twice = await as('POST', '/admin/categories/order', { parentId: null, ids: [...wanted.slice(1), wanted[1]] })
    assert.equal(twice.status, 409)
  })

  test('hidden: off the tree and the picker; its products stay on sale and may keep it; shown again', async () => {
    const top = await category()
    const sub = await category(top.id)
    const store = await approvedStore()
    const kept = await product(store, sub.id, 'Hidden Aisle Speaker')
    assert.equal((await as('PATCH', `/admin/categories/${top.id}`, { hidden: true })).status, 200)
    // Its sub-categories go with it.
    assert.ok(!everyId(await tree()).includes(top.id) && !everyId(await tree()).includes(sub.id))
    assert.equal((await h.call('GET', `/categories/${sub.id}`)).status, 404)
    // Still on sale, still found.
    assert.ok((await search('Hidden Aisle Speaker')).includes(kept.id))
    // Not for a new product; the product already in it keeps it on a save.
    const refused = await save(store, sub.id, 'Late Speaker')
    assert.deepEqual([refused.status, refused.body.errors?.categoryId], [422, t('en', 'category.hidden')])
    const edited = await h.call('PUT', `/merchants/me/products/${kept.id}`, {
      token: store.token,
      body: { name: 'Hidden Aisle Speaker', nameAr: 'منتج للتجربة', categoryId: sub.id, price: 100_000, stock: 5 },
    })
    assert.equal(edited.status, 200, JSON.stringify(edited.body))
    assert.equal((await as('PATCH', `/admin/categories/${top.id}`, { hidden: false })).status, 200)
    assert.ok(everyId(await tree()).includes(sub.id))
    assert.equal((await save(store, sub.id, 'Late Speaker')).status, 200)
  })

  test("renamed or moved: its products are found by the new names, their parent's too", async () => {
    const top = await category()
    const sub = await category(top.id)
    const store = await approvedStore()
    const made = await product(store, sub.id, 'Plain Box')
    const before = (await productRow(made.id))!.updated_at
    assert.equal((await as('PATCH', `/admin/categories/${sub.id}`, { name: 'Zircon Shelf', nameAr: 'رف الزركون' })).status, 200)
    assert.ok((await search('zircon')).includes(made.id))
    assert.ok((await search('الزركون')).includes(made.id))
    assert.equal((await as('PATCH', `/admin/categories/${top.id}`, { name: 'Quartz Hall', nameAr: 'قاعة الكوارتز' })).status, 200)
    assert.ok((await search('quartz')).includes(made.id))
    // Moved to the top level: no parent's names any more.
    assert.equal((await as('PATCH', `/admin/categories/${sub.id}`, { parentId: null })).status, 200)
    assert.ok(!(await search('quartz')).includes(made.id))
    // The store changed nothing: its product's updated_at stays.
    assert.deepEqual((await productRow(made.id))!.updated_at, before)
  })

  test('deleted: refused while it has sub-categories or products; moveTo moves them first, as they are; gone for all', async () => {
    const top = await category()
    const sub = await category(top.id)
    const target = await category()
    const store = await approvedStore()
    const approved = await product(store, sub.id, 'Moved Lamp')
    const waiting = await product(store, sub.id, 'Moved Fan', {}, false)
    const before = (await productRow(approved.id))!.updated_at

    const parent = await as('DELETE', `/admin/categories/${top.id}`)
    assert.deepEqual([parent.status, parent.body.message], [409, 'It still has sub-categories. Delete or move them first.'])
    const full = await as('DELETE', `/admin/categories/${sub.id}`)
    assert.deepEqual([full.status, full.body.message], [409, 'It still has 2 products. Choose a category to move them to.'])
    assert.equal((await as('DELETE', `/admin/categories/${sub.id}?moveTo=${sub.id}`)).status, 422)
    assert.equal((await as('DELETE', `/admin/categories/${sub.id}?moveTo=999999`)).status, 422)

    const moved = await as('DELETE', `/admin/categories/${sub.id}?moveTo=${target.id}`)
    assert.deepEqual([moved.status, moved.body.data], [200, { moved: 2 }])
    const [a, w] = [(await productRow(approved.id))!, (await productRow(waiting.id))!]
    assert.deepEqual([String(a.category_id), a.status, String(w.category_id), w.status], [target.id, 'APPROVED', target.id, 'PENDING'])
    assert.deepEqual(a.updated_at, before)
    assert.ok((await search(target.name)).includes(approved.id))
    // Gone for shoppers and for Saba's page; now empty, its parent goes too.
    assert.ok(!everyId(await tree()).includes(sub.id))
    assert.ok(!JSON.stringify((await as('GET', '/admin/categories')).body.data).includes(`"id":"${sub.id}"`))
    assert.deepEqual((await as('DELETE', `/admin/categories/${top.id}`)).body.data, { moved: 0 })
    assert.equal((await as('DELETE', `/admin/categories/${top.id}`)).status, 404)
    assert.equal((await save(store, sub.id, 'Too Late Lamp')).status, 422)
  })
})

// --------------------------------------------------------------- banners ---

describe('banners', () => {
  test("Home shows Saba's banners that are on, in Saba's order, with their link; a gone link leaves it off and Saba's list says so; none, no section", async () => {
    const store = await approvedStore()
    const top = await category()
    const lamp = await product(store, top.id, 'Banner Lamp')
    const picture = await upload(admin)
    const banner = (extra: Record<string, unknown>) =>
      as('POST', '/admin/banners', { imageUrl: picture, titleEn: null, titleAr: null, subtitleEn: null, subtitleAr: null, link: null, isActive: true, ...extra })

    // Words in both languages or neither; a picture of Saba's; a link that opens something.
    const half = await banner({ titleEn: 'Big sale' })
    assert.deepEqual([half.status, half.body.errors?.titleAr], [422, t('en', 'field.required')])
    assert.deepEqual((await banner({ imageUrl: await upload(store.token) })).body.errors?.imageUrl, t('en', 'media.notUploaded'))
    const nowhere = await banner({ link: { type: 'PRODUCT', id: '999999' } })
    assert.deepEqual([nowhere.status, nowhere.body.errors?.link], [422, t('en', 'banner.linkGone')])

    const first = (await banner({ titleEn: 'Lamps', titleAr: 'مصابيح', link: { type: 'PRODUCT', id: lamp.id } })).body.data
    const second = (await banner({ link: { type: 'CATEGORY', id: top.id } })).body.data
    const off = (await banner({ isActive: false, link: { type: 'STORE', id: store.storeId } })).body.data
    assert.deepEqual(first.link, { type: 'PRODUCT', id: lamp.id, name: 'Banner Lamp' })

    const home = async (lang?: string) => {
      const sections = (await h.call('GET', '/home/sections', lang ? { lang } : {})).body.data as { type: string; items?: any[] }[]
      return sections.find((s) => s.type === 'BANNER')?.items
    }
    assert.deepEqual((await home())!.map((b) => [b.id, b.title, b.link]), [
      [first.id, 'Lamps', { type: 'PRODUCT', id: lamp.id }],
      [second.id, undefined, { type: 'CATEGORY', id: top.id }],
    ])
    assert.equal((await home('ar'))![0].title, 'مصابيح')

    // Saba's order.
    const ordered = await as('POST', '/admin/banners/order', { ids: [second.id, off.id, first.id] })
    assert.deepEqual(ordered.body.data.map((b: { id: string }) => b.id), [second.id, off.id, first.id])
    assert.deepEqual((await home())!.map((b) => b.id), [second.id, first.id])
    assert.equal((await as('POST', '/admin/banners/order', { ids: [second.id, first.id] })).status, 409)

    // Its product taken down: off Home, marked in Saba's list.
    assert.equal((await as('POST', `/admin/products/${lamp.id}/hide`, { reason: 'Checking the listing' })).status, 200)
    assert.deepEqual((await home())!.map((b) => b.id), [second.id])
    const listed = (await as('GET', '/admin/banners')).body.data as { id: string; linkBroken: boolean }[]
    assert.deepEqual(listed.map((b) => [b.id, b.linkBroken]), [[second.id, false], [off.id, false], [first.id, true]])
    // Its category hidden: off too.
    assert.equal((await as('PATCH', `/admin/categories/${top.id}`, { hidden: true })).status, 200)
    assert.equal(await home(), undefined)

    // Edited back on, then removed: no banner, no section.
    const edited = await as('PUT', `/admin/banners/${off.id}`, { imageUrl: picture, titleEn: null, titleAr: null, subtitleEn: null, subtitleAr: null, link: null, isActive: true })
    assert.equal(edited.status, 200, JSON.stringify(edited.body))
    assert.deepEqual((await home())!.map((b) => [b.id, b.link]), [[off.id, null]])
    for (const id of [first.id, second.id, off.id]) assert.equal((await as('DELETE', `/admin/banners/${id}`)).status, 200)
    assert.equal(await home(), undefined)
    assert.equal((await h.call('GET', '/admin/banners', { token: store.token })).status, 403)
  })
})

// ---------------------------------------------------------------- brands ---

describe('brands', () => {
  const brand = async (name: string, nameAr: string) => {
    const reply = await as('POST', '/admin/brands', { name, nameAr })
    assert.equal(reply.status, 200, JSON.stringify(reply.body))
    return reply.body.data as { id: string; name: string; nameAr: string | null; status: string; productCount: number }
  }
  const brandRow = (id: string | number) => one<{ name: string; status: string }>(h.pool, 'SELECT name, status FROM brands WHERE id = ?', [id])

  test("Saba's brands in both languages: add, rename, a name taken in either language; new ones first; paged", async () => {
    const lumo = await brand('Lumo', 'لومو')
    assert.deepEqual([lumo.status, lumo.productCount], ['APPROVED', 0])
    const taken = await as('POST', '/admin/brands', { name: 'LUMO', nameAr: 'شيء آخر' })
    assert.deepEqual([taken.status, taken.body.errors?.name], [422, t('en', 'brand.nameTaken')])
    const takenAr = await as('POST', '/admin/brands', { name: 'Other', nameAr: 'لومو' })
    assert.deepEqual([takenAr.status, takenAr.body.errors?.nameAr], [422, t('en', 'brand.nameTaken')])
    const renamed = await as('PUT', `/admin/brands/${lumo.id}`, { name: 'Lumo Home', nameAr: 'لومو هوم' })
    assert.deepEqual([renamed.status, renamed.body.data.name, renamed.body.data.nameAr], [200, 'Lumo Home', 'لومو هوم'])

    const store = await approvedStore()
    const top = await category()
    await product(store, top.id, 'Typed Brand Kettle', { brandName: 'Kettlo' }, false)
    const page = (await as('GET', '/admin/brands?page=1&perPage=1')).body
    assert.deepEqual([page.data.items[0].name, page.data.items[0].status], ['Kettlo', 'PENDING'])
    assert.deepEqual(page.meta, { page: 1, perPage: 1, total: page.data.counts.all, totalPages: page.data.counts.all })
    assert.equal((await as('GET', '/admin/brands?status=PENDING')).body.meta.total, page.data.counts.PENDING)
    assert.deepEqual((await as('GET', '/admin/brands?q=lumo')).body.data.items.map((b: { name: string }) => b.name), ['Lumo Home'])
    assert.equal((await h.call('GET', '/admin/brands', { token: store.token })).status, 403)
  })

  test("a typed brand: a new one waits for Saba, the same name in any case or in Arabic is that brand; approving the product approves it", async () => {
    const store = await approvedStore()
    const top = await category()
    const samsung = await brand('Samsang', 'سامسانج')
    const first = await product(store, top.id, 'Nokio Phone', { brandName: 'Nokio' }, false)
    const again = await product(store, top.id, 'Nokio Phone Two', { brandName: '  nokio ' }, false)
    assert.equal(again.brand!.id, first.brand!.id)
    assert.equal((await brandRow(first.brand!.id))!.status, 'PENDING')
    assert.equal((await product(store, top.id, 'Samsang Tab', { brandName: 'سامسانج' }, false)).brand!.id, samsung.id)
    // The store's picker: Saba's checked brands and those its own products use; not another store's new one.
    const picker = async (who: Store) => ((await h.call('GET', '/merchants/me/brands', { token: who.token })).body.data as { id: string }[]).map((b) => b.id)
    assert.deepEqual([(await picker(store)).includes(samsung.id), (await picker(store)).includes(first.brand!.id)], [true, true])
    const other = await approvedStore()
    assert.deepEqual([(await picker(other)).includes(samsung.id), (await picker(other)).includes(first.brand!.id)], [true, false])
    // Saba's review shows it is new.
    const review = (await as('GET', `/admin/products/${first.id}`)).body.data
    assert.deepEqual(review.brand, { id: first.brand!.id, name: 'Nokio', nameAr: null, isNew: true })
    // Not in the shoppers' filter until then.
    const filter = async () => ((await h.call('GET', '/brands')).body.data as { id: string }[]).map((b) => b.id)
    assert.ok(!(await filter()).includes(first.brand!.id))
    assert.equal((await as('POST', `/admin/products/${first.id}/approve`)).status, 200)
    assert.equal((await brandRow(first.brand!.id))!.status, 'APPROVED')
    assert.ok((await filter()).includes(first.brand!.id))
  })

  test('deleted: its products move to another checked brand or to none, as they are; refused without a choice', async () => {
    const store = await approvedStore()
    const top = await category()
    const old = await brand('Oldbrand', 'أولدبراند')
    const next = await brand('Newbrand', 'نيوبراند')
    const sold = await product(store, top.id, 'Old Brand Iron', { brandId: old.id })
    const waiting = await product(store, top.id, 'Old Brand Mixer', { brandId: old.id }, false)
    const pending = (await product(store, top.id, 'Pending Brand Toaster', { brandName: 'Toastly' }, false)).brand!
    const before = (await productRow(sold.id))!.updated_at

    const refused = await as('DELETE', `/admin/brands/${old.id}`)
    assert.deepEqual([refused.status, refused.body.message], [409, 'It still has 2 products. Choose a brand to move them to, or none.'])
    assert.equal((await as('DELETE', `/admin/brands/${old.id}?moveTo=${pending.id}`)).status, 422)
    const moved = await as('DELETE', `/admin/brands/${old.id}?moveTo=${next.id}`)
    assert.deepEqual([moved.status, moved.body.data], [200, { moved: 2 }])
    const [s, w] = [(await productRow(sold.id))!, (await productRow(waiting.id))!]
    assert.deepEqual([String(s.brand_id), s.status, String(w.brand_id), w.status], [next.id, 'APPROVED', next.id, 'PENDING'])
    assert.deepEqual(s.updated_at, before)
    assert.equal(await brandRow(old.id), undefined)
    // To no brand.
    assert.deepEqual((await as('DELETE', `/admin/brands/${next.id}?moveTo=none`)).body.data, { moved: 2 })
    assert.equal((await productRow(sold.id))!.brand_id, null)
  })
})

// ------------------------------------------------- saving while Saba deletes ---

describe('saving while Saba deletes', () => {
  /** Runs [work] while the test holds [table]'s row [id] as Saba's delete does, then [gone] deletes it and lets go. */
  async function whileDeleting(table: string, id: string, gone: string, work: () => ReturnType<Harness['call']>) {
    const holder = await h.pool.getConnection()
    try {
      await holder.beginTransaction()
      await holder.query(`SELECT id FROM ${table} WHERE id = ? FOR UPDATE`, [id])
      const pending = work()
      // Time for the save to reach the row and wait for it.
      await new Promise((resolve) => setTimeout(resolve, 1000))
      await holder.query(gone, [id])
      await holder.commit()
      return await pending
    } finally {
      holder.release()
    }
  }

  test("a store's save into a category or brand Saba is deleting waits, then is refused: never left in a deleted one", async () => {
    const store = await approvedStore()
    const doomed = await category()
    const intoCategory = await whileDeleting('categories', doomed.id, 'UPDATE categories SET deleted_at = NOW(3) WHERE id = ?', () =>
      save(store, doomed.id, 'Racing Clock'),
    )
    assert.deepEqual([intoCategory.status, intoCategory.body.errors?.categoryId], [422, t('en', 'field.invalid')])

    const live = await category()
    const brand = (await as('POST', '/admin/brands', { name: 'Doomed Brand', nameAr: 'علامة زائلة' })).body.data
    const withBrand = await whileDeleting('brands', brand.id, 'DELETE FROM brands WHERE id = ?', () => save(store, live.id, 'Racing Watch', { brandId: brand.id }))
    assert.deepEqual([withBrand.status, withBrand.body.errors?.brandId], [422, t('en', 'field.invalid')])
  })
})
