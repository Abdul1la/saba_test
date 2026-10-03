// S3 Catalogue (BACKEND_PLAN.md §7): the store's products, stock and flash
// sales; the one "listed" rule; search, Home, the wishlist; Saba's answers.
import assert from 'node:assert/strict'
import { after, before, describe, test } from 'node:test'
import { exec, one, rows } from '../src/db/sql.js'
import { PNG, startHarness, type Harness } from './api.js'

let h: Harness
let admin: string
before(async () => {
  h = await startHarness()
  admin = await h.signInAdmin()
})
after(() => h.close())

const PHONES = '1'
const SMARTPHONES = '8'
const HEADPHONES = '3'

let stores = 0
/** An approved, open store that delivers in its own city. */
async function openStore(governorate = 'BAGHDAD') {
  stores += 1
  const store = await h.signUpStore(`Catalog Store ${stores}`, governorate)
  assert.equal((await h.call('POST', `/admin/stores/${store.storeId}/approve`, { token: admin })).status, 200)
  const saved = await h.call('PUT', '/merchants/me/store', {
    token: store.token,
    body: { storeName: `Catalog Store ${stores}`, governorate, logoUrl: null, delivery: { governorates: [], feeInside: 3000, timeInside: 'SAME_DAY' } },
  })
  assert.equal(saved.status, 200, JSON.stringify(saved.body))
  return store
}

type Store = Awaited<ReturnType<typeof openStore>>

function draft(extra: Record<string, unknown> = {}) {
  return { name: 'Nova Phone', nameAr: 'هاتف نوفا', categoryId: SMARTPHONES, price: 250_000, stock: 10, ...extra }
}

async function create(store: Store, extra: Record<string, unknown> = {}) {
  const reply = await h.call('POST', '/merchants/me/products', { token: store.token, body: draft(extra) })
  assert.equal(reply.status, 200, JSON.stringify(reply.body))
  return reply.body.data
}

/** A product shoppers can see: made, then approved by Saba. */
async function listed(store: Store, extra: Record<string, unknown> = {}) {
  const product = await create(store, extra)
  const approved = await h.call('POST', `/admin/products/${product.id}/approve`, { token: admin })
  assert.equal(approved.status, 200, JSON.stringify(approved.body))
  return product
}

const ledger = (productId: string) =>
  rows<{ delta: number; reason: string }>(
    h.pool,
    'SELECT m.delta, m.reason FROM stock_movements m JOIN product_skus k ON k.id = m.sku_id WHERE k.product_id = ? ORDER BY m.id',
    [productId],
  )

const listIds = async (query = '', token?: string) =>
  (await h.call('GET', `/products?perPage=100${query}`, { token })).body.data.map((p: any) => p.id) as string[]

// ------------------------------------------------------------- the product form ---

describe("the store's product form", () => {
  test('a new product waits for Saba; its stock is written to the ledger', async () => {
    const store = await openStore()
    const product = await create(store)
    assert.equal(product.status, 'PENDING')
    assert.equal(product.availableQuantity, 10)
    assert.equal(product.isListed, false)
    assert.deepEqual(await ledger(product.id), [{ delta: 10, reason: 'PRODUCT_SAVED' }])
  })

  test('refused: no Arabic name, a price off the 250 steps, an original not above the price, an unknown category', async () => {
    const store = await openStore()
    const cases: [Record<string, unknown>, string][] = [
      [{ nameAr: 'Phone' }, 'nameAr'],
      [{ nameAr: 'اب' }, 'nameAr'],
      [{ price: 250_100 }, 'price'],
      [{ originalPrice: 250_000 }, 'originalPrice'],
      [{ categoryId: '999' }, 'categoryId'],
    ]
    for (const [extra, field] of cases) {
      const reply = await h.call('POST', '/merchants/me/products', { token: store.token, body: draft(extra) })
      assert.equal(reply.status, 422, JSON.stringify(extra))
      assert.ok(reply.body.errors[field], `${field}: ${JSON.stringify(reply.body.errors)}`)
    }
  })

  test('the Arabic name: one with no Arabic letter asks for Arabic; one too short says so (M3)', async () => {
    const store = await openStore()
    const english = await h.call('POST', '/merchants/me/products', { token: store.token, body: draft({ nameAr: 'Phone' }) })
    assert.equal(english.body.errors.nameAr, 'Write the product name in Arabic.')
    const short = await h.call('POST', '/merchants/me/products', { token: store.token, body: draft({ nameAr: 'اب' }), lang: 'ar' })
    assert.equal(short.body.errors.nameAr, 'استخدم 3 أحرف على الأقل.')
  })

  test('options: each its own stock and id; matched by id on save; a new one gets a new id; one left out is gone', async () => {
    const store = await openStore()
    const product = await create(store, {
      variants: [
        { price: 250_000, stock: 3, options: [{ name: 'Color', value: 'Black' }] },
        { price: 275_000, stock: 4, options: [{ name: 'Color', value: 'Blue' }] },
      ],
    })
    assert.equal(product.availableQuantity, 7)
    assert.equal(product.hasVariants, true)
    const [black, blue] = product.variants
    assert.deepEqual(black.options, { Color: 'Black' })

    const saved = await h.call('PUT', `/merchants/me/products/${product.id}`, {
      token: store.token,
      body: draft({
        variants: [
          { id: black.id, price: 250_000, stock: 5, stockBefore: 3, options: [{ name: 'Color', value: 'Black' }] },
          { price: 260_000, stock: 2, options: [{ name: 'Color', value: 'Red' }] },
        ],
      }),
    })
    assert.equal(saved.status, 200, JSON.stringify(saved.body))
    const ids = saved.body.data.variants.map((v: any) => v.id)
    assert.equal(ids[0], black.id)
    assert.ok(!ids.includes(blue.id))
    assert.notEqual(ids[1], blue.id)
    assert.equal(saved.body.data.availableQuantity, 7)
    const gone = await one<{ deleted_at: Date | null }>(h.pool, 'SELECT deleted_at FROM product_skus WHERE id = ?', [blue.id])
    assert.ok(gone?.deleted_at)
    assert.deepEqual(await ledger(product.id), [
      { delta: 3, reason: 'PRODUCT_SAVED' },
      { delta: 4, reason: 'PRODUCT_SAVED' },
      { delta: 2, reason: 'PRODUCT_SAVED' },
      { delta: 2, reason: 'PRODUCT_SAVED' },
    ])
    const same = await h.call('PUT', `/merchants/me/products/${product.id}`, {
      token: store.token,
      body: draft({
        variants: [
          { price: 250_000, options: [{ name: 'Color', value: 'Black' }] },
          { price: 250_000, options: [{ name: 'Color', value: 'Black' }] },
        ],
      }),
    })
    assert.equal(same.status, 422)
    assert.ok(same.body.errors.variants)
  })

  test('a save changes a stock only when the store changed it: units sold while the form was open stay sold', async () => {
    const store = await openStore()
    const product = await listed(store, { stock: 5 })
    const stockNow = async () => (await h.call('GET', `/merchants/me/products/${product.id}`, { token: store.token })).body.data.availableQuantity
    // Three sold while the form was open, still showing 5.
    await exec(h.pool, 'UPDATE product_skus SET stock = 2 WHERE product_id = ?', [product.id])
    const moves = (await ledger(product.id)).length

    // A typo fixed; the stock box untouched. Sent without what the form showed, or unchanged: the stock stays.
    for (const body of [draft({ stock: 5, name: 'Nova Phone 5G' }), draft({ stock: 5, stockBefore: 5, name: 'Nova Phone 5G' })]) {
      const saved = await h.call('PUT', `/merchants/me/products/${product.id}`, { token: store.token, body })
      assert.equal(saved.status, 200, JSON.stringify(saved.body))
      assert.equal(await stockNow(), 2)
    }
    // Changed while stock moved underneath: refused, saying what is left now.
    const moved = await h.call('PUT', `/merchants/me/products/${product.id}`, { token: store.token, body: draft({ stock: 9, stockBefore: 5 }) })
    assert.deepEqual([moved.status, moved.body.message], [409, 'Stock changed while you were editing: 2 left now. Check it and save again.'])
    assert.equal(await stockNow(), 2)
    assert.equal((await ledger(product.id)).length, moves)
    // Changed from what it is: set, with its ledger row.
    const counted = await h.call('PUT', `/merchants/me/products/${product.id}`, { token: store.token, body: draft({ stock: 9, stockBefore: 2 }) })
    assert.equal(counted.status, 200, JSON.stringify(counted.body))
    assert.equal(await stockNow(), 9)
    assert.deepEqual((await ledger(product.id)).slice(moves), [{ delta: 7, reason: 'PRODUCT_SAVED' }])
  })

  test('an option keeps its stock the same way; a new option starts at the stock sent', async () => {
    const store = await openStore()
    const product = await create(store, { variants: [{ price: 250_000, stock: 3, options: [{ name: 'Color', value: 'Black' }] }] })
    const [black] = product.variants
    await exec(h.pool, 'UPDATE product_skus SET stock = 1 WHERE id = ?', [black.id])
    const save = (variant: Record<string, unknown>, extra: Record<string, unknown>[] = []) =>
      h.call('PUT', `/merchants/me/products/${product.id}`, {
        token: store.token,
        body: draft({ variants: [{ id: black.id, price: 250_000, options: [{ name: 'Color', value: 'Black' }], ...variant }, ...extra] }),
      })
    const stocks = async () =>
      (await rows<{ stock: number }>(h.pool, 'SELECT stock FROM product_skus WHERE product_id = ? AND deleted_at IS NULL ORDER BY id', [product.id])).map((r) => r.stock)

    for (const variant of [{ stock: 3 }, { stock: 3, stockBefore: 3 }]) {
      assert.equal((await save(variant)).status, 200)
      assert.deepEqual(await stocks(), [1])
    }
    const moved = await save({ stock: 6, stockBefore: 3 })
    assert.deepEqual([moved.status, moved.body.message], [409, 'The stock of Black changed while you were editing: 1 left now. Check it and save again.'])
    assert.deepEqual(await stocks(), [1])
    const added = await save({ stock: 6, stockBefore: 1 }, [{ price: 250_000, stock: 2, options: [{ name: 'Color', value: 'Red' }] }])
    assert.equal(added.status, 200, JSON.stringify(added.body))
    assert.deepEqual(await stocks(), [6, 2])
  })

  test("an approved product whose name, words or photos change goes back to Saba and leaves the shop; a price or stock change doesn't", async () => {
    const store = await openStore()
    const product = await listed(store, { description: 'Fast' })
    const status = async () => (await one<{ status: string }>(h.pool, 'SELECT status FROM products WHERE id = ?', [product.id]))!.status
    const inShop = async () => (await h.call('GET', `/products/${product.id}`)).status
    const save = (extra: Record<string, unknown>) =>
      h.call('PUT', `/merchants/me/products/${product.id}`, { token: store.token, body: draft({ description: 'Fast', ...extra }) })

    // A new price and a counted stock: no review.
    assert.equal((await save({ price: 240_000, stock: 12, stockBefore: 10 })).status, 200)
    assert.deepEqual([await status(), await inShop()], ['APPROVED', 200])
    // The same words sent again: nothing changed.
    assert.equal((await save({ price: 240_000 })).status, 200)
    assert.equal(await status(), 'APPROVED')

    // A new name: back in Saba's queue, out of the shop until approved again.
    assert.equal((await save({ price: 240_000, name: 'Nova Phone Pro' })).status, 200)
    assert.deepEqual([await status(), await inShop()], ['PENDING', 404])
    const queue = (await h.call('GET', '/admin/queue', { token: admin })).body.data.products
    assert.ok(queue.some((item: { id: string }) => item.id === product.id))
    assert.equal((await h.call('POST', `/admin/products/${product.id}/approve`, { token: admin })).status, 200)
    assert.deepEqual([await status(), await inShop()], ['APPROVED', 200])

    // New words, and a new option name: the same.
    assert.equal((await save({ price: 240_000, name: 'Nova Phone Pro', description: 'Faster than ever' })).status, 200)
    assert.equal(await status(), 'PENDING')
    assert.equal((await h.call('POST', `/admin/products/${product.id}/approve`, { token: admin })).status, 200)
    const withOption = await save({
      price: 240_000,
      name: 'Nova Phone Pro',
      description: 'Faster than ever',
      variants: [{ price: 240_000, stock: 3, options: [{ name: 'Color', value: 'Black' }] }],
    })
    assert.equal(withOption.status, 200, JSON.stringify(withOption.body))
    assert.equal(await status(), 'PENDING')
  })

  test('words sent back as the form showed them, and no brand sent, change nothing: the Arabic copies, the brand and the approval stay', async () => {
    const store = await openStore()
    const product = await listed(store, { description: 'Fast', warranty: '12 months' })
    const brand = (await exec(h.pool, "INSERT INTO brands (name) VALUES ('Kept Brand')")).insertId
    // As the demo's products have them.
    await exec(h.pool, "UPDATE products SET description_ar = 'سريع', warranty_ar = '12 شهراً', brand_id = ? WHERE id = ?", [brand, product.id])
    const row = () =>
      one<{ status: string; description_ar: string | null; warranty_ar: string | null; brand_id: number | null }>(
        h.pool,
        'SELECT status, description_ar, warranty_ar, brand_id FROM products WHERE id = ?',
        [product.id],
      )
    // A new price, the words as shown in English, then as shown in Arabic.
    for (const [lang, words] of [['en', { description: 'Fast', warranty: '12 months' }], ['ar', { description: 'سريع', warranty: '12 شهراً' }]] as const) {
      const saved = await h.call('PUT', `/merchants/me/products/${product.id}`, { token: store.token, lang, body: draft({ price: 240_000, ...words }) })
      assert.equal(saved.status, 200, JSON.stringify(saved.body))
      assert.deepEqual(await row(), { status: 'APPROVED', description_ar: 'سريع', warranty_ar: '12 شهراً', brand_id: brand })
    }
  })

  test('a save keeps the status; a field left out stays, one sent replaces both languages', async () => {
    const store = await openStore()
    const product = await listed(store, { description: 'Fast' })
    await exec(h.pool, "UPDATE products SET description_ar = 'سريع' WHERE id = ?", [product.id])
    let saved = await h.call('PUT', `/merchants/me/products/${product.id}`, { token: store.token, body: draft({ price: 240_000 }) })
    assert.equal(saved.body.data.status, 'APPROVED')
    assert.equal(saved.body.data.descriptionAr, 'سريع')
    saved = await h.call('PUT', `/merchants/me/products/${product.id}`, {
      token: store.token,
      body: draft({ price: 240_000, description: 'Faster' }),
    })
    assert.equal(saved.body.data.description, 'Faster')
    assert.equal(saved.body.data.descriptionAr, null)
  })

  test("photos: its own uploads only; left out on a save, they stay", async () => {
    const store = await openStore()
    const other = await openStore()
    const form = new FormData()
    form.append('file', new Blob([new Uint8Array(PNG)]), 'p.png')
    const upload = (await h.call('POST', '/media/upload', { token: store.token, form })).body.data
    const stolen = await h.call('POST', '/merchants/me/products', { token: other.token, body: draft({ images: [upload.url] }) })
    assert.equal(stolen.status, 422)
    // Says what is wrong, not just "Not valid." (M3).
    assert.equal(stolen.body.errors.images, "This photo didn't upload. Add it again.")
    const product = await create(store, { images: [upload.url] })
    assert.equal(product.images.length, 1)
    assert.equal(product.imageUrl, upload.url)
    const saved = await h.call('PUT', `/merchants/me/products/${product.id}`, { token: store.token, body: draft() })
    assert.equal(saved.body.data.imageUrl, upload.url)
    // In use: the photo can't be deleted.
    assert.equal((await h.call('DELETE', `/media/${upload.id}`, { token: store.token })).status, 409)
  })

  test("another store's product is not found", async () => {
    const store = await openStore()
    const other = await openStore()
    const product = await create(store)
    assert.equal((await h.call('GET', `/merchants/me/products/${product.id}`, { token: other.token })).status, 404)
    assert.equal((await h.call('PUT', `/merchants/me/products/${product.id}`, { token: other.token, body: draft() })).status, 404)
    assert.equal((await h.call('PATCH', `/merchants/me/products/${product.id}/stock`, { token: other.token, body: { stock: 1 } })).status, 404)
  })

  test('submit: a rejected product goes back to Saba; an approved one is 409', async () => {
    const store = await openStore()
    const product = await create(store)
    await h.call('POST', `/admin/products/${product.id}/reject`, { token: admin, body: { reason: 'Blurry photos' } })
    assert.equal((await h.call('POST', `/merchants/me/products/${product.id}/submit`, { token: store.token })).status, 200)
    const row = await one<{ status: string; rejection_reason: string | null }>(
      h.pool,
      'SELECT status, rejection_reason FROM products WHERE id = ?',
      [product.id],
    )
    assert.deepEqual(row, { status: 'PENDING', rejection_reason: null })
    await h.call('POST', `/admin/products/${product.id}/approve`, { token: admin })
    assert.equal((await h.call('POST', `/merchants/me/products/${product.id}/submit`, { token: store.token })).status, 409)
  })

  test('deleting a product takes it out of every wishlist', async () => {
    const store = await openStore()
    const product = await listed(store)
    const shopper = await h.signUpShopper()
    await h.call('POST', '/wishlist/items', { token: shopper.token, body: { productId: product.id } })
    assert.equal((await h.call('DELETE', `/merchants/me/products/${product.id}`, { token: store.token })).status, 200)
    assert.equal((await h.call('GET', '/wishlist/items', { token: shopper.token })).body.data.length, 0)
    // Gone from the table too, not only hidden from the list.
    const left = await one<{ n: number }>(h.pool, 'SELECT COUNT(*) AS n FROM wishlist_items WHERE product_id = ?', [product.id])
    assert.equal(left?.n, 0)
    assert.equal((await h.call('GET', `/merchants/me/products/${product.id}`, { token: store.token })).status, 404)
  })
})

// ------------------------------------------------------------------- stock ---

describe('stock', () => {
  test('setting the stock of a product without options: saved and in the ledger', async () => {
    const store = await openStore()
    const product = await create(store)
    const set = await h.call('PATCH', `/merchants/me/products/${product.id}/stock`, { token: store.token, body: { stock: 3 } })
    assert.equal(set.status, 200)
    assert.deepEqual((await ledger(product.id)).at(-1), { delta: -7, reason: 'SET' })
    assert.equal((await h.call('GET', `/merchants/me/products/${product.id}`, { token: store.token })).body.data.availableQuantity, 3)
    assert.equal((await h.call('PATCH', `/merchants/me/products/${product.id}/stock`, { token: store.token, body: { stock: -1 } })).status, 422)
  })

  test('a product with options has no stock of its own to set', async () => {
    const store = await openStore()
    const product = await create(store, { variants: [{ price: 250_000, stock: 1, options: [{ name: 'Size', value: 'M' }] }] })
    const set = await h.call('PATCH', `/merchants/me/products/${product.id}/stock`, { token: store.token, body: { stock: 3 } })
    assert.equal(set.status, 422)
    assert.equal(set.body.code, 'BUSINESS_RULE_ERROR')
  })

  test('the inventory: a row per thing sold; an adjustment never goes below 0, and the ledger holds what moved', async () => {
    const store = await openStore()
    const product = await create(store, {
      variants: [
        { price: 250_000, stock: 4, options: [{ name: 'Size', value: 'M' }] },
        { price: 250_000, stock: 6, options: [{ name: 'Size', value: 'L' }] },
      ],
    })
    const inventory = (await h.call('GET', '/merchants/me/inventory', { token: store.token })).body.data
    assert.deepEqual(
      inventory.map((r: any) => [r.variantLabel, r.available, r.reserved, r.sold]),
      [
        ['M', 4, 0, 0],
        ['L', 6, 0, 0],
      ],
    )
    const m = inventory[0].id
    assert.deepEqual((await h.call('POST', `/merchants/me/inventory/${m}/adjust`, { token: store.token, body: { quantity: 5 } })).body.data, {
      available: 9,
    })
    assert.deepEqual((await h.call('POST', `/merchants/me/inventory/${m}/adjust`, { token: store.token, body: { quantity: -100 } })).body.data, {
      available: 0,
    })
    const moves = (await ledger(product.id)).slice(2)
    assert.deepEqual(moves, [
      { delta: 5, reason: 'ADJUSTED' },
      { delta: -9, reason: 'ADJUSTED' },
    ])
    const other = await openStore()
    assert.equal((await h.call('POST', `/merchants/me/inventory/${m}/adjust`, { token: other.token, body: { quantity: 1 } })).status, 404)
  })

  test("the shelf's tabs: waiting, low (1–5), out, hidden; and q", async () => {
    const store = await openStore()
    const low = await listed(store, { name: 'Low One', stock: 5 })
    const out = await listed(store, { name: 'Out One', stock: 0 })
    const hidden = await listed(store, { name: 'Hidden One', stock: 50 })
    const waiting = await create(store, { name: 'Waiting One', stock: 50 })
    await h.call('POST', `/merchants/me/products/${hidden.id}/visibility`, { token: store.token, body: { isActive: false } })
    const counts = (await h.call('GET', '/merchants/me/products/counts', { token: store.token })).body.data
    assert.deepEqual(counts, { all: 4, waiting: 1, low: 1, out: 1, hidden: 1 })
    const tab = async (filter: string) =>
      (await h.call('GET', `/merchants/me/products?filter=${filter}`, { token: store.token })).body.data.map((r: any) => r.id)
    assert.deepEqual(await tab('low'), [low.id])
    assert.deepEqual(await tab('out'), [out.id])
    assert.deepEqual(await tab('hidden'), [hidden.id])
    assert.deepEqual(await tab('waiting'), [waiting.id])
    const found = (await h.call('GET', '/merchants/me/products?q=hidden', { token: store.token })).body.data
    assert.deepEqual(
      found.map((r: any) => r.id),
      [hidden.id],
    )
  })

  test('each shelf row says whether it is sold in options, so the app shows its stock stepper only without them', async () => {
    const store = await openStore()
    const plain = await create(store, { name: 'Plain One' })
    const options = await create(store, {
      name: 'Options One',
      variants: [{ price: 250_000, stock: 3, options: [{ name: 'Color', value: 'Black' }] }],
    })
    const shelf = (await h.call('GET', '/merchants/me/products', { token: store.token })).body.data
    const flag = (id: string) => shelf.find((row: any) => row.id === id).hasVariants
    assert.equal(flag(plain.id), false)
    assert.equal(flag(options.id), true)
    // The stepper it hides is refused for such a product.
    const stepped = await h.call('PATCH', `/merchants/me/products/${options.id}/stock`, { token: store.token, body: { stock: 5 } })
    assert.equal(stepped.status, 422)
  })
})

// ------------------------------------------------------------- flash sales ---

describe('flash sales', () => {
  const inAnHour = () => new Date(Date.now() + 3_600_000).toISOString()

  test('only a listed product; below the normal price, in steps of 250, ending later; no option below 250', async () => {
    const store = await openStore()
    const waiting = await create(store)
    assert.equal(
      (await h.call('POST', `/merchants/me/products/${waiting.id}/flash-sale`, { token: store.token, body: { salePrice: 200_000, saleEndsAt: inAnHour() } }))
        .status,
      409,
    )
    const product = await listed(store, {
      price: 10_000,
      variants: [
        { price: 10_000, stock: 1, options: [{ name: 'Size', value: 'S' }] },
        { price: 1_000, stock: 1, options: [{ name: 'Size', value: 'XS' }] },
      ],
    })
    const sale = (body: Record<string, unknown>) =>
      h.call('POST', `/merchants/me/products/${product.id}/flash-sale`, { token: store.token, body })
    assert.ok((await sale({ salePrice: 10_000, saleEndsAt: inAnHour() })).body.errors.salePrice)
    assert.ok((await sale({ salePrice: 9_100, saleEndsAt: inAnHour() })).body.errors.salePrice)
    assert.ok((await sale({ salePrice: 9_000, saleEndsAt: new Date(Date.now() - 1000).toISOString() })).body.errors.saleEndsAt)
    // 10,000 → 9,000 takes 1,000 off every option: the 1,000 option would be free.
    const deep = await sale({ salePrice: 9_000, saleEndsAt: inAnHour() })
    assert.equal(deep.body.errors.salePrice, 'That takes more off than one of its options costs.')
    assert.equal((await sale({ salePrice: 9_500, saleEndsAt: inAnHour() })).status, 200)
  })

  test('during a sale every read shows the sale price; once it ends, the normal price everywhere', async () => {
    const store = await openStore()
    const product = await listed(store, {
      price: 200_000,
      variants: [
        { price: 200_000, stock: 2, options: [{ name: 'Storage', value: '128GB' }] },
        { price: 250_000, stock: 2, options: [{ name: 'Storage', value: '256GB' }] },
      ],
    })
    await h.call('POST', `/merchants/me/products/${product.id}/flash-sale`, {
      token: store.token,
      body: { salePrice: 170_000, saleEndsAt: inAnHour() },
    })
    let page = (await h.call('GET', `/products/${product.id}`)).body.data
    assert.equal(page.price, 170_000)
    assert.equal(page.originalPrice, 200_000)
    assert.equal(page.discountPercentage, 15)
    assert.equal(page.isFlashSale, true)
    assert.deepEqual(
      page.variants.map((v: any) => [v.price, v.originalPrice]),
      [
        [170_000, 200_000],
        [220_000, 250_000],
      ],
    )
    const home = (await h.call('GET', '/home/sections')).body.data
    const flash = home.find((s: any) => s.type === 'FLASH_SALE')
    assert.ok(flash.items.some((p: any) => p.id === product.id))

    // The end is honoured when the price is read, to the millisecond.
    await exec(h.pool, 'UPDATE products SET sale_ends_at = NOW(3) - INTERVAL 1 SECOND WHERE id = ?', [product.id])
    page = (await h.call('GET', `/products/${product.id}`)).body.data
    assert.equal(page.price, 200_000)
    assert.equal(page.originalPrice, null)
    assert.equal(page.isFlashSale, false)
    assert.deepEqual(
      page.variants.map((v: any) => v.price),
      [200_000, 250_000],
    )
    const card = (await h.call('GET', `/products?merchantId=${store.storeId}`)).body.data[0]
    assert.equal(card.price, 200_000)
    const again = (await h.call('GET', '/home/sections')).body.data.find((s: any) => s.type === 'FLASH_SALE')
    assert.ok(!again?.items.some((p: any) => p.id === product.id))
  })

  test('a save during a sale reads the form back: the sale stays, and ending it restores the normal prices', async () => {
    const store = await openStore()
    const product = await listed(store, {
      price: 200_000,
      variants: [{ price: 250_000, stock: 2, options: [{ name: 'Storage', value: '256GB' }] }],
    })
    await h.call('POST', `/merchants/me/products/${product.id}/flash-sale`, {
      token: store.token,
      body: { salePrice: 170_000, saleEndsAt: inAnHour() },
    })
    const variant = (await h.call('GET', `/merchants/me/products/${product.id}`, { token: store.token })).body.data.variants[0]
    // The form sends what it showed: the sale price as price, the normal as originalPrice, the option at its sale price.
    const saved = await h.call('PUT', `/merchants/me/products/${product.id}`, {
      token: store.token,
      body: draft({
        price: 170_000,
        originalPrice: 200_000,
        variants: [{ id: variant.id, price: 220_000, stock: 5, stockBefore: 2, options: [{ name: 'Storage', value: '256GB' }] }],
      }),
    })
    assert.equal(saved.status, 200, JSON.stringify(saved.body))
    assert.equal(saved.body.data.price, 170_000)
    assert.equal(saved.body.data.variants[0].price, 220_000)
    await h.call('DELETE', `/merchants/me/products/${product.id}/flash-sale`, { token: store.token })
    const after = (await h.call('GET', `/products/${product.id}`)).body.data
    assert.equal(after.price, 200_000)
    assert.equal(after.variants[0].price, 250_000)
    assert.equal(after.variants[0].availableQuantity, 5)
  })
})

// --------------------------------------------------------------- listed ---

describe('the one "listed" rule', () => {
  test('waiting, hidden, taken down, a suspended store: out of the shop; a closed store: out of browsing, its page still opens', async () => {
    const store = await openStore()
    const shown = await listed(store, { name: 'Shown' })
    const waiting = await create(store, { name: 'Waiting' })
    const hidden = await listed(store, { name: 'Hidden' })
    const down = await listed(store, { name: 'Down' })
    await h.call('POST', `/merchants/me/products/${hidden.id}/visibility`, { token: store.token, body: { isActive: false } })
    await h.call('POST', `/admin/products/${down.id}/hide`, { token: admin, body: { reason: 'Counterfeit' } })

    let ids = await listIds(`&merchantId=${store.storeId}`)
    assert.deepEqual(ids, [shown.id])
    for (const id of [waiting.id, hidden.id, down.id]) {
      const page = await h.call('GET', `/products/${id}`)
      assert.equal(page.status, 404)
      assert.equal(page.body.message, 'This product is not available.')
    }
    // Its own store opens it, not listed.
    const own = await h.call('GET', `/products/${hidden.id}`, { token: store.token })
    assert.equal(own.status, 200)
    assert.equal(own.body.data.isListed, false)

    // Saba's takedown: the store's switch can't bring it back.
    const back = await h.call('POST', `/merchants/me/products/${down.id}/visibility`, { token: store.token, body: { isActive: true } })
    assert.equal(back.status, 409)

    await h.call('PATCH', '/merchants/me/store/open', { token: store.token, body: { isOpen: false } })
    assert.deepEqual(await listIds(`&merchantId=${store.storeId}`), [])
    const closedPage = await h.call('GET', `/products/${shown.id}`)
    assert.equal(closedPage.status, 200)
    assert.equal(closedPage.body.data.merchant.isOpen, false)
    await h.call('PATCH', '/merchants/me/store/open', { token: store.token, body: { isOpen: true } })

    await h.call('POST', `/admin/stores/${store.storeId}/suspend`, { token: admin, body: { reason: 'x' } })
    assert.deepEqual(await listIds(`&merchantId=${store.storeId}`), [])
    assert.equal((await h.call('GET', `/products/${shown.id}`)).status, 404)
    await h.call('POST', `/admin/stores/${store.storeId}/unsuspend`, { token: admin })
    ids = await listIds(`&merchantId=${store.storeId}`)
    assert.deepEqual(ids, [shown.id])
  })
})

// ------------------------------------------------------------------ search ---

describe('search and the product list', () => {
  test('search folds like the app: أ/ا, ة/ه, ى/ي, marks, ال; every word; a name match before a category match', async () => {
    const store = await openStore('NINEVEH')
    const book = await listed(store, { name: 'Library Lamp', nameAr: 'مصباح المكتبة', categoryId: HEADPHONES })
    const phone = await listed(store, { name: 'Nokia 3310', nameAr: 'نوكيا ٣٣١٠', categoryId: SMARTPHONES })
    const named = await listed(store, { name: 'Phone Stand', nameAr: 'حامل هاتف', categoryId: HEADPHONES })
    const q = async (text: string) => listIds(`&governorate=NINEVEH&q=${encodeURIComponent(text)}`)
    assert.deepEqual(await q('مكتبه'), [book.id])
    assert.deepEqual(await q('مِصْبَاح'), [book.id])
    assert.deepEqual(await q('3310'), [phone.id])
    assert.deepEqual(await q('lamp library'), [book.id])
    assert.deepEqual(await q('lamp nokia'), [])
    // "phone" names one product and is in the category of two others (Smartphones,
    // Headphones): the named one first, then the rest newest first.
    assert.deepEqual(await q('phone'), [named.id, phone.id, book.id])
  })

  test('filters: a category with its sub-categories, a city, the shown price, in stock, on sale; sorted by price', async () => {
    const store = await openStore('BABYLON')
    const cheap = await listed(store, { name: 'Cheap', price: 10_000, stock: 0 })
    const dear = await listed(store, { name: 'Dear', price: 90_000, originalPrice: 100_000 })
    const other = await listed(store, { name: 'Other', price: 50_000, categoryId: HEADPHONES })
    const base = '&governorate=BABYLON'
    assert.deepEqual((await listIds(`${base}&categoryId=${PHONES}`)).sort(), [cheap.id, dear.id].sort())
    assert.deepEqual(await listIds(`${base}&minPrice=40000&maxPrice=60000`), [other.id])
    assert.deepEqual((await listIds(`${base}&inStock=true`)).sort(), [dear.id, other.id].sort())
    assert.deepEqual(await listIds(`${base}&onSale=true`), [dear.id])
    assert.deepEqual(await listIds(`${base}&sort=price_asc`), [cheap.id, other.id, dear.id])
    assert.deepEqual(await listIds(`${base}&sort=price_desc`), [dear.id, other.id, cheap.id])
  })

  test('deliverTo says on each card whether its store delivers there', async () => {
    const store = await openStore('MAYSAN')
    await listed(store)
    const cards = (await h.call('GET', '/products?governorate=MAYSAN&deliverTo=MAYSAN')).body.data
    assert.equal(cards[0].deliveryAvailable, true)
    const far = (await h.call('GET', '/products?governorate=MAYSAN&deliverTo=DUHOK')).body.data
    assert.equal(far[0].deliveryAvailable, false)
  })

  test('paging: 20 a page by default; meta says how many', async () => {
    const reply = await h.call('GET', '/products?perPage=2&page=1')
    assert.equal(reply.body.data.length, 2)
    assert.equal(reply.body.meta.page, 1)
    assert.equal(reply.body.meta.perPage, 2)
    assert.ok(reply.body.meta.total >= 2)
  })

  test('popular searches: one that found something counts once, on its first page', async () => {
    const store = await openStore()
    await listed(store, { name: 'Zebra Speaker', nameAr: 'سماعة زيبرا' })
    await h.call('GET', '/products?q=zebra')
    await h.call('GET', '/products?q=Zebra&page=2')
    await h.call('GET', '/products?q=nothingmatchesthis')
    const row = await one<{ hits: number }>(h.pool, "SELECT hits FROM search_terms WHERE term_key = 'zebra'")
    assert.equal(row?.hits, 1)
    assert.equal(await one(h.pool, "SELECT 1 FROM search_terms WHERE term_key = 'nothingmatchesthis'"), undefined)
    const popular = (await h.call('GET', '/search/popular')).body.data
    assert.ok(popular.some((p: any) => p.text === 'zebra'))
    const suggestions = (await h.call('GET', '/search/suggestions?q=zeb', { lang: 'ar' })).body.data
    assert.equal(suggestions[0].text, 'سماعة زيبرا')
  })

  test('categories: in Arabic for a shopper, both names for an admin; one with its children; 404 for none', async () => {
    const tree = (await h.call('GET', '/categories', { lang: 'ar' })).body.data
    assert.equal(tree[0].name, 'هواتف')
    assert.equal(tree[0].children[0].name, 'هواتف ذكية')
    const forAdmin = (await h.call('GET', '/categories', { lang: 'ar', token: admin })).body.data
    assert.equal(forAdmin[0].name, 'Phones')
    assert.equal(forAdmin[0].nameAr, 'هواتف')
    assert.equal((await h.call('GET', `/categories/${PHONES}`)).body.data.children.length, 2)
    assert.equal((await h.call('GET', '/categories/999')).status, 404)
  })
})

// -------------------------------------------------------------------- Home ---

describe('Home and the wishlist', () => {
  test('Home: no banners section without banners; categories; featured stores in order, suspended ones left out', async () => {
    const a = await openStore()
    const b = await openStore()
    await h.call('PUT', '/admin/featured-stores', { token: admin, body: { storeIds: [b.storeId, a.storeId] } })
    let sections = (await h.call('GET', '/home/sections')).body.data
    assert.ok(!sections.some((s: any) => s.type === 'BANNER'))
    assert.ok(sections.some((s: any) => s.type === 'CATEGORY'))
    const rail = sections.find((s: any) => s.type === 'MERCHANT')
    assert.deepEqual(
      rail.items.map((s: any) => s.id),
      [b.storeId, a.storeId],
    )
    await h.call('POST', `/admin/stores/${b.storeId}/suspend`, { token: admin, body: { reason: 'x' } })
    sections = (await h.call('GET', '/home/sections')).body.data
    assert.deepEqual(
      sections.find((s: any) => s.type === 'MERCHANT').items.map((s: any) => s.id),
      [a.storeId],
    )
    await h.call('PUT', '/admin/featured-stores', { token: admin, body: { storeIds: [] } })
    await h.call('POST', `/admin/stores/${b.storeId}/unsuspend`, { token: admin })
  })

  test('the wishlist: listed products only; the heart on the product; removed', async () => {
    const store = await openStore()
    const product = await listed(store)
    const waiting = await create(store)
    const shopper = await h.signUpShopper()
    assert.equal((await h.call('POST', '/wishlist/items', { token: shopper.token, body: { productId: waiting.id } })).status, 404)
    assert.equal((await h.call('POST', '/wishlist/items', { token: shopper.token, body: { productId: product.id } })).status, 200)
    assert.equal((await h.call('POST', '/wishlist/items', { token: shopper.token, body: { productId: product.id } })).status, 200)
    const list = (await h.call('GET', '/wishlist/items', { token: shopper.token })).body.data
    assert.deepEqual(
      list.map((p: any) => [p.id, p.isWishlisted]),
      [[product.id, true]],
    )
    assert.equal((await h.call('GET', `/products/${product.id}`, { token: shopper.token })).body.data.isWishlisted, true)
    assert.equal((await h.call('GET', `/products/${product.id}`)).body.data.isWishlisted, false)
    await h.call('DELETE', `/wishlist/items/${product.id}`, { token: shopper.token })
    assert.equal((await h.call('GET', '/wishlist/items', { token: shopper.token })).body.data.length, 0)
    assert.equal((await h.call('GET', '/wishlist/items', { token: store.token })).status, 403)
  })
})

// ---------------------------------------------------------- Saba's answers ---

describe("Saba's answers on products", () => {
  test('approve: from PENDING only, with its Arabic name; the store is told; the audit row', async () => {
    const store = await openStore()
    const product = await create(store)
    await exec(h.pool, "UPDATE products SET name_ar = 'abc' WHERE id = ?", [product.id])
    const noArabic = await h.call('POST', `/admin/products/${product.id}/approve`, { token: admin })
    assert.equal(noArabic.status, 422)
    assert.equal(noArabic.body.code, 'BUSINESS_RULE_ERROR')
    assert.ok(noArabic.body.errors.nameAr)
    await exec(h.pool, "UPDATE products SET name_ar = 'هاتف نوفا' WHERE id = ?", [product.id])
    const approved = await h.call('POST', `/admin/products/${product.id}/approve`, { token: admin })
    assert.equal(approved.body.data.status, 'APPROVED')
    assert.equal(approved.body.data.inShop, true)
    assert.equal((await h.call('POST', `/admin/products/${product.id}/approve`, { token: admin })).status, 409)
    const told = (await h.call('GET', '/notifications', { token: store.token, lang: 'ar' })).body.data[0]
    assert.equal(told.title, 'تمت الموافقة على هاتف نوفا')
    assert.deepEqual([told.entityType, told.entityId], ['STORE_PRODUCT', product.id])
    const audit = await one<{ action: string }>(h.pool, "SELECT action FROM admin_actions WHERE entity_type = 'PRODUCT' AND entity_id = ?", [
      product.id,
    ])
    assert.equal(audit?.action, 'PRODUCT_APPROVE')
  })

  test('take down and put back: its own counts bucket, inShop with the reason, the store told both times', async () => {
    const store = await openStore()
    const product = await listed(store, { name: 'Takedown Target' })
    const down = await h.call('POST', `/admin/products/${product.id}/hide`, { token: admin, body: { reason: 'Counterfeit' } })
    assert.equal(down.body.data.takenDown, true)
    assert.equal(down.body.data.inShop, false)
    assert.equal(down.body.data.notInShopReason, 'TAKEN_DOWN')
    assert.equal((await h.call('POST', `/admin/products/${product.id}/hide`, { token: admin, body: { reason: 'again' } })).status, 409)
    const list = (await h.call('GET', `/admin/products?storeId=${store.storeId}`, { token: admin })).body.data
    assert.equal(list.counts.TAKEN_DOWN, 1)
    assert.equal(list.counts.APPROVED ?? 0, 0)
    const back = await h.call('POST', `/admin/products/${product.id}/unhide`, { token: admin })
    assert.equal(back.body.data.inShop, true)
    const titles = (await h.call('GET', '/notifications', { token: store.token })).body.data.map((n: any) => n.title)
    assert.deepEqual(titles.slice(0, 2), ['Takedown Target is back in the shop', 'Takedown Target was taken down by Saba'])
  })

  test('the admin list: no drafts; q on names and the store; the queue holds waiting products, oldest first', async () => {
    const store = await openStore()
    const first = await create(store, { name: 'Queue First' })
    const second = await create(store, { name: 'Queue Second' })
    await exec(h.pool, 'UPDATE products SET submitted_at = NOW(3) - INTERVAL 1 DAY WHERE id = ?', [second.id])
    await exec(h.pool, "UPDATE products SET status = 'DRAFT' WHERE id = ?", [first.id])
    const listed = (await h.call('GET', `/admin/products?storeId=${store.storeId}`, { token: admin })).body.data
    assert.deepEqual(
      listed.items.map((p: any) => p.id),
      [second.id],
    )
    const byStore = (await h.call('GET', `/admin/products?q=${encodeURIComponent(store.user.merchant.storeName)}`, { token: admin })).body.data
    assert.ok(byStore.items.some((p: any) => p.id === second.id))
    const queue = (await h.call('GET', '/admin/queue', { token: admin })).body.data.products.map((p: any) => p.id)
    assert.ok(queue.includes(second.id))
    assert.ok(!queue.includes(first.id))
  })
})
