// S4 Buying (BACKEND_PLAN.md §7): the cart and its coupon, checkout, placing
// an order under its locks, the store's steps, cancelling, rating, and Saba's
// view. Every formula of DATABASE_DESIGN.md §6 against the demo's numbers.
import assert from 'node:assert/strict'
import { after, before, describe, test } from 'node:test'
import { one, rows } from '../src/db/sql.js'
import { billingMonth } from '../src/lib/money.js'
import { PNG, startHarness, type Harness } from './api.js'

let h: Harness
let admin: string
before(async () => {
  h = await startHarness()
  admin = await h.signInAdmin()
})
after(() => h.close())

const SMARTPHONES = '8'
const NOW = () => Date.now()
const yesterday = () => new Date(NOW() - 86_400_000).toISOString()

let stores = 0
/** An approved, open store with delivery terms (its own city always included). */
async function openStore(governorate = 'BAGHDAD', delivery: Record<string, unknown> = {}) {
  stores += 1
  const name = `Buying Store ${stores}`
  const store = await h.signUpStore(name, governorate)
  assert.equal((await h.call('POST', `/admin/stores/${store.storeId}/approve`, { token: admin })).status, 200)
  const saved = await h.call('PUT', '/merchants/me/store', {
    token: store.token,
    body: { storeName: name, governorate, logoUrl: null, delivery: { governorates: [], feeInside: 3000, timeInside: '1_2_DAYS', ...delivery } },
  })
  assert.equal(saved.status, 200, JSON.stringify(saved.body))
  return { ...store, name, id: Number(store.storeId) }
}
type Store = Awaited<ReturnType<typeof openStore>>

/** A product shoppers can buy: made by [store], approved by Saba. */
async function listed(store: Store, extra: Record<string, unknown> = {}) {
  const made = await h.call('POST', '/merchants/me/products', {
    token: store.token,
    body: { name: 'Kite Studio Headphones', nameAr: 'سماعات كايت ستوديو', categoryId: SMARTPHONES, price: 145_000, stock: 10, ...extra },
  })
  assert.equal(made.status, 200, JSON.stringify(made.body))
  assert.equal((await h.call('POST', `/admin/products/${made.body.data.id}/approve`, { token: admin })).status, 200)
  return made.body.data as { id: string; variants: { id: string }[] }
}

/** A shopper with a default address in [governorate]. */
async function shopper(governorate = 'BAGHDAD') {
  const account = await h.signUpShopper(governorate)
  const address = await h.call('POST', '/customers/me/addresses', {
    token: account.token,
    body: { fullName: 'Amina Saleh', phone: account.phone, governorate, area: 'Karrada', landmark: 'Near the park' },
  })
  assert.equal(address.status, 200, JSON.stringify(address.body))
  return { ...account, id: Number(account.user.id), addressId: address.body.data.id as string }
}
type Shopper = Awaited<ReturnType<typeof shopper>>

async function add(who: { token: string }, productId: string, quantity = 1, variantId?: string) {
  const reply = await h.call('POST', '/cart/items', { token: who.token, body: { productId, quantity, ...(variantId && { variantId }) } })
  assert.equal(reply.status, 200, JSON.stringify(reply.body))
  return reply.body.data
}

let keys = 0
function place(who: Shopper, extra: Record<string, unknown> = {}, key = `key-${++keys}`) {
  return h.call('POST', '/checkout/place-order', {
    token: who.token,
    headers: { 'idempotency-key': key },
    body: { addressId: who.addressId, paymentMethodId: 'pm-cod', ...extra },
  })
}

async function placed(who: Shopper, extra: Record<string, unknown> = {}) {
  const reply = await place(who, extra)
  assert.equal(reply.status, 200, JSON.stringify(reply.body))
  return reply.body.data.order
}

let codes = 0
async function coupon(store: Store, body: Record<string, unknown>) {
  codes += 1
  const reply = await h.call('POST', '/merchants/me/coupons', {
    token: store.token,
    body: { code: `CODE${codes}`, discountType: 'PERCENTAGE', value: 10, startsAt: yesterday(), ...body },
  })
  assert.equal(reply.status, 200, JSON.stringify(reply.body))
  return reply.body.data as { id: string; code: string }
}

async function apply(who: { token: string }, code: string) {
  const reply = await h.call('POST', '/cart/coupon', { token: who.token, body: { code } })
  assert.equal(reply.status, 200, JSON.stringify(reply.body))
  return reply.body.data
}

const partOf = async (orderId: string, store: Store) =>
  (await one<{ id: number }>(h.pool, 'SELECT id FROM order_store_parts WHERE order_id = ? AND store_id = ?', [orderId, store.id]))!.id

function step(store: Store, partId: number, status: string, extra: Record<string, unknown> = {}) {
  return h.call('PATCH', `/merchants/me/orders/${partId}/status`, { token: store.token, body: { status, ...extra } })
}

/** Moves a part along every step to [until]. */
async function walk(store: Store, partId: number, until: 'CONFIRMED' | 'PROCESSING' | 'SHIPPED' | 'DELIVERED') {
  const path = ['CONFIRMED', 'PROCESSING', 'SHIPPED', 'DELIVERED']
  for (const status of path.slice(0, path.indexOf(until) + 1)) {
    const extra = status === 'SHIPPED' ? { courierName: 'Haider Salim', courierPhone: '0770 555 0311' } : {}
    const reply = await step(store, partId, status, extra)
    assert.equal(reply.status, 200, JSON.stringify(reply.body))
  }
}

const stockOf = async (productId: string) =>
  Number((await one<{ n: number }>(h.pool, 'SELECT SUM(stock) AS n FROM product_skus WHERE product_id = ? AND deleted_at IS NULL', [productId]))!.n)

const ledger = (productId: string) =>
  rows<{ delta: number; reason: string; part_id: number | null }>(
    h.pool,
    `SELECT m.delta, m.reason, m.part_id FROM stock_movements m JOIN product_skus k ON k.id = m.sku_id
      WHERE k.product_id = ? AND m.reason NOT IN ('PRODUCT_SAVED') ORDER BY m.id`,
    [productId],
  )

const order = async (who: Shopper, id: string) => (await h.call('GET', `/orders/${id}`, { token: who.token })).body.data

// -------------------------------------------------------------- the numbers ---

describe('the numbers (DATABASE_DESIGN.md §6)', () => {
  test('NOVA10 on 145,000: 14,500 off, 130,500 paid for the unit, the driver collects 133,500', async () => {
    const nova = await openStore()
    const headphones = await listed(nova)
    const code = await coupon(nova, { value: 10, minOrderAmount: 100_000 })
    const amina = await shopper()
    await add(amina, headphones.id)
    const cart = await apply(amina, code.code)
    assert.deepEqual(cart.totals, { subtotal: 145_000, discount: 0, couponDiscount: 14_500, shipping: 3000, total: 133_500, currencyCode: 'IQD' })
    assert.equal(cart.coupon.applies, true)
    assert.equal(cart.groups[0].discount, 14_500)
    assert.equal(cart.groups[0].amountDue, 133_500)

    const made = await placed(amina)
    assert.equal(made.subtotal, 145_000)
    assert.equal(made.discount, 14_500)
    assert.equal(made.shipping, 3000)
    assert.equal(made.total, 133_500)
    assert.equal(made.couponCode, code.code)
    assert.equal(made.items[0].unitPrice, 145_000)
    assert.equal(made.items[0].paidUnitPrice, 130_500)
    assert.equal(made.storeParts[0].amountDue, 133_500)
    assert.match(made.orderNumber, /^SB-1\d{5,}$/)
    assert.equal(made.status, 'PENDING')
    assert.equal(made.paymentStatus, 'PENDING')
    assert.equal(made.canCancel, true)
    assert.equal(made.timeline[0].noteCode, 'ORDER_RECEIVED')

    // One use counted; the cart is empty and the code is off it.
    assert.equal((await one<{ used_count: number }>(h.pool, 'SELECT used_count FROM coupons WHERE id = ?', [code.id]))!.used_count, 1)
    const after = (await h.call('GET', '/cart', { token: amina.token })).body.data
    assert.equal(after.groups.length, 0)
    assert.equal(after.coupon, undefined)
    // The stock came off, and the ledger says which order took it.
    assert.equal(await stockOf(headphones.id), 9)
    assert.deepEqual(await ledger(headphones.id), [{ delta: -1, reason: 'ORDER_PLACED', part_id: await partOf(made.id, nova) }])
  })

  test('a percentage rounds down to 250: 10% of 129,000 is 12,750', async () => {
    const store = await openStore()
    const phone = await listed(store, { price: 129_000 })
    const code = await coupon(store, { value: 10 })
    const who = await shopper()
    await add(who, phone.id)
    const cart = await apply(who, code.code)
    assert.equal(cart.totals.couponDiscount, 12_750)
    const made = await placed(who)
    assert.equal(made.discount, 12_750)
    assert.equal(made.items[0].paidUnitPrice, 116_250)
  })

  test('a fixed amount takes at most what its store sells: 5,000 off 4,000 is 4,000', async () => {
    const store = await openStore()
    const cheap = await listed(store, { price: 4000 })
    const code = await coupon(store, { discountType: 'FIXED', value: 5000 })
    const who = await shopper()
    await add(who, cheap.id)
    assert.equal((await apply(who, code.code)).totals.couponDiscount, 4000)
    await add(who, cheap.id, 4)
    const cart = (await h.call('GET', '/cart', { token: who.token })).body.data
    assert.equal(cart.totals.subtotal, 20_000)
    assert.equal(cart.totals.couponDiscount, 5000)
    assert.equal(cart.totals.total, 20_000 - 5000 + 3000)
  })

  test('under its minimum a code takes nothing and says so; it is refused at first', async () => {
    const store = await openStore()
    const cheap = await listed(store, { price: 50_000 })
    const dear = await listed(store, { price: 60_000 })
    const code = await coupon(store, { value: 10, minOrderAmount: 100_000 })
    const who = await shopper()
    await add(who, cheap.id)
    const refused = await h.call('POST', '/cart/coupon', { token: who.token, body: { code: code.code } })
    assert.equal(refused.status, 422)
    assert.match(refused.body.errors.code, /100,000/)
    const line = await add(who, dear.id)
    assert.equal((await apply(who, code.code)).totals.couponDiscount, 11_000)
    // The dear one leaves: 50,000 is under the minimum again.
    const itemId = line.groups[0].items.find((i: any) => i.productId === dear.id).id
    const cart = (await h.call('DELETE', `/cart/items/${itemId}`, { token: who.token })).body.data
    assert.equal(cart.totals.couponDiscount, 0)
    assert.equal(cart.coupon.applies, false)
    assert.equal(cart.coupon.minOrderAmount, 100_000)
    // Ordered like that, nothing comes off and no use is counted.
    const made = await placed(who)
    assert.equal(made.discount, 0)
    assert.equal(made.couponCode, null)
    assert.equal((await one<{ used_count: number }>(h.pool, 'SELECT used_count FROM coupons WHERE id = ?', [code.id]))!.used_count, 0)
  })

  test("two lines share their store's coupon by price, each unit rounded down", async () => {
    const store = await openStore()
    const phone = await listed(store, { price: 329_000 })
    const watch = await listed(store, { price: 100_000 })
    const code = await coupon(store, { value: 10 })
    const who = await shopper()
    await add(who, phone.id)
    await add(who, watch.id)
    await apply(who, code.code)
    const made = await placed(who)
    assert.equal(made.discount, 42_750)
    assert.deepEqual(
      made.items.map((i: any) => i.paidUnitPrice),
      [296_000, 90_000],
    )
  })

  test("two stores: the code comes off its own store's part only; each store sees only its part", async () => {
    const nova = await openStore('BAGHDAD')
    const atlas = await openStore('BASRA', { governorates: ['BAGHDAD'], feeInside: 2000, timeInside: 'SAME_DAY', feeOutside: 5000, timeOutside: '2_3_DAYS' })
    const headphones = await listed(nova)
    const fryer = await listed(atlas, { name: 'Atlas Air Fryer 5L', nameAr: 'قلاية هوائية أطلس', price: 95_000 })
    const code = await coupon(nova, { value: 10 })
    const who = await shopper('BAGHDAD')
    await add(who, headphones.id)
    await add(who, fryer.id)
    const cart = await apply(who, code.code)
    const [novaPart, atlasPart] = cart.groups
    assert.equal(novaPart.discount, 14_500)
    assert.equal(novaPart.amountDue, 145_000 - 14_500 + 3000)
    assert.equal(atlasPart.discount, 0)
    // Baghdad is another city for Atlas: its outside fee and time.
    assert.equal(atlasPart.shippingFee, 5000)
    assert.equal(atlasPart.deliveryTime, '2_3_DAYS')
    assert.equal(atlasPart.amountDue, 100_000)
    assert.equal(cart.totals.total, 133_500 + 100_000)

    const made = await placed(who)
    assert.equal(made.total, 233_500)
    assert.deepEqual(
      made.items.map((i: any) => i.paidUnitPrice),
      [130_500, 95_000],
    )
    assert.equal(made.estimatedDelivery, '2–3 days')
    const atlasOrders = (await h.call('GET', '/merchants/me/orders', { token: atlas.token })).body.data
    assert.equal(atlasOrders.length, 1)
    assert.equal(atlasOrders[0].total, 100_000)
    assert.equal(atlasOrders[0].discount, 0)
    assert.deepEqual(
      atlasOrders[0].items.map((i: any) => i.productId),
      [fryer.id],
    )
    assert.equal(atlasOrders[0].customerOrderId, made.id)
  })

  test("a store that doesn't deliver there, or is closed, is not in the total and can't be ordered from", async () => {
    const atlas = await openStore('BASRA', { governorates: ['BAGHDAD'], feeOutside: 5000, timeOutside: '2_3_DAYS' })
    const fryer = await listed(atlas, { price: 95_000 })
    const erbil = await shopper('ERBIL')
    await add(erbil, fryer.id)
    const cart = (await h.call('GET', '/cart', { token: erbil.token })).body.data
    assert.equal(cart.groups[0].deliversHere, false)
    assert.equal(cart.groups[0].estimatedDelivery, "Doesn't deliver to Erbil")
    assert.equal(cart.groups[0].amountDue, undefined)
    assert.equal(cart.totals.total, 0)
    const review = await h.call('POST', '/checkout/review', { token: erbil.token, body: { addressId: erbil.addressId } })
    assert.equal(review.body.data.canPlaceOrder, false)
    const refused = await place(erbil)
    assert.equal(refused.status, 422)
    assert.equal(refused.body.code, 'BUSINESS_RULE_ERROR')
    // A sentence, with its full stop like every other message (M4).
    assert.equal(refused.body.message, `${atlas.name} can't take this order: Doesn't deliver to Erbil.`)

    const basra = await shopper('BASRA')
    await add(basra, fryer.id)
    await h.call('PATCH', '/merchants/me/store/open', { token: atlas.token, body: { isOpen: false } })
    const closed = (await h.call('GET', '/cart', { token: basra.token })).body.data
    assert.equal(closed.groups[0].estimatedDelivery, 'Closed right now')
    assert.equal(closed.totals.total, 0)
    const shut = await place(basra)
    assert.equal(shut.status, 422)
    assert.equal(shut.body.message, `${atlas.name} can't take this order: Closed right now.`)
    assert.equal(await stockOf(fryer.id), 10)
  })

  test('something run out or taken off sale is shown, not charged, and stops the order', async () => {
    const store = await openStore()
    const phone = await listed(store, { price: 100_000, stock: 2 })
    const case_ = await listed(store, { price: 10_000 })
    const who = await shopper()
    await add(who, phone.id, 3)
    await add(who, case_.id)
    const review = (await h.call('POST', '/checkout/review', { token: who.token, body: { addressId: who.addressId } })).body.data
    assert.equal(review.canPlaceOrder, false)
    assert.deepEqual(review.warnings, ['Only 2 of Kite Studio Headphones left.'])
    const short = await place(who)
    assert.equal(short.status, 422)
    assert.equal(short.body.code, 'INVENTORY_ERROR')

    // The store hides the case: in the cart as sold out, and out of the total.
    await h.call('POST', `/merchants/me/products/${case_.id}/visibility`, { token: store.token, body: { isActive: false } })
    const cart = (await h.call('GET', '/cart', { token: who.token })).body.data
    const hidden = cart.groups[0].items.find((i: any) => i.productId === case_.id)
    assert.equal(hidden.stockStatus, 'OUT_OF_STOCK')
    assert.equal(cart.totals.subtotal, 300_000)
    const gone = await place(who)
    assert.equal(gone.status, 422)
    assert.equal(gone.body.code, 'INVENTORY_ERROR')
    assert.equal(await stockOf(phone.id), 2)
  })

  test('an option is sold at its own price, and its stock is the one taken', async () => {
    const store = await openStore()
    const phone = await listed(store, {
      variants: [
        { price: 329_000, stock: 3, options: [{ name: 'Storage', value: '128GB' }] },
        { price: 409_000, stock: 2, options: [{ name: 'Storage', value: '256GB' }] },
      ],
    })
    const big = phone.variants[1]!.id
    const who = await shopper()
    const noOption = await h.call('POST', '/cart/items', { token: who.token, body: { productId: phone.id, quantity: 1 } })
    assert.equal(noOption.status, 422)
    const cart = await add(who, phone.id, 2, big)
    assert.equal(cart.groups[0].items[0].unitPrice, 409_000)
    assert.equal(cart.groups[0].items[0].variantLabel, '256GB')
    const made = await placed(who)
    assert.equal(made.items[0].variantId, big)
    assert.equal((await one<{ stock: number }>(h.pool, 'SELECT stock FROM product_skus WHERE id = ?', [big]))!.stock, 0)
    assert.equal((await one<{ stock: number }>(h.pool, 'SELECT stock FROM product_skus WHERE id = ?', [phone.variants[0]!.id]))!.stock, 3)
  })
})

// ------------------------------------------------------------------- the cart ---

describe('the cart', () => {
  test('the same option again adds to its line; saved lines are kept out of the total and stay after an order', async () => {
    const store = await openStore()
    const phone = await listed(store, { price: 100_000 })
    const watch = await listed(store, { price: 50_000 })
    const who = await shopper()
    await add(who, phone.id)
    const twice = await add(who, phone.id, 2)
    assert.equal(twice.groups[0].items[0].quantity, 3)
    const withWatch = await add(who, watch.id)
    const watchLine = withWatch.groups[0].items.find((i: any) => i.productId === watch.id).id
    const saved = (await h.call('POST', `/cart/items/${watchLine}/save-for-later`, { token: who.token })).body.data
    assert.equal(saved.savedForLater.length, 1)
    assert.equal(saved.totals.subtotal, 300_000)
    // Moving onto a line already there adds the quantities.
    await add(who, watch.id, 2)
    const inCart = (await h.call('GET', '/cart', { token: who.token })).body.data
    const moved = (await h.call('POST', `/cart/items/${inCart.savedForLater[0].id}/move-to-cart`, { token: who.token })).body.data
    assert.equal(moved.savedForLater.length, 0)
    assert.equal(moved.groups[0].items.find((i: any) => i.productId === watch.id).quantity, 3)

    // Save it again, order the rest: the saved line stays.
    const again = moved.groups[0].items.find((i: any) => i.productId === watch.id).id
    await h.call('POST', `/cart/items/${again}/save-for-later`, { token: who.token })
    await placed(who)
    const left = (await h.call('GET', '/cart', { token: who.token })).body.data
    assert.equal(left.groups.length, 0)
    assert.equal(left.savedForLater[0].quantity, 3)
  })

  test("a line is its shopper's own; a product not for sale can't go in", async () => {
    const store = await openStore()
    const phone = await listed(store)
    const who = await shopper()
    const other = await shopper()
    const line = (await add(who, phone.id)).groups[0].items[0].id
    assert.equal((await h.call('PATCH', `/cart/items/${line}`, { token: other.token, body: { quantity: 5 } })).status, 404)
    assert.equal((await h.call('POST', `/cart/items/${line}/save-for-later`, { token: other.token })).status, 404)
    await h.call('POST', `/merchants/me/products/${phone.id}/visibility`, { token: store.token, body: { isActive: false } })
    assert.equal((await h.call('POST', '/cart/items', { token: other.token, body: { productId: phone.id } })).status, 404)
    assert.equal((await h.call('GET', '/cart', { token: store.token })).status, 403)
  })

  test('something with none left is refused at the cart; more than is left still goes in (M4)', async () => {
    const store = await openStore()
    const gone = await listed(store, { name: 'Gone One', stock: 0 })
    const phone = await listed(store, {
      variants: [
        { price: 329_000, stock: 0, options: [{ name: 'Storage', value: '128GB' }] },
        { price: 409_000, stock: 2, options: [{ name: 'Storage', value: '256GB' }] },
      ],
    })
    const who = await shopper()
    const refused = await h.call('POST', '/cart/items', { token: who.token, body: { productId: gone.id, quantity: 1 } })
    assert.equal(refused.status, 422)
    assert.equal(refused.body.code, 'INVENTORY_ERROR')
    assert.equal(refused.body.message, "This has run out, so it can't go in the cart.")
    const option = await h.call('POST', '/cart/items', {
      token: who.token,
      body: { productId: phone.id, variantId: phone.variants[0]!.id },
      lang: 'ar',
    })
    assert.equal(option.status, 422)
    assert.equal(option.body.message, 'نفد هذا من المخزون، فلا يمكن إضافته إلى السلة.')
    // More than is left still goes in: the review then says how many are left.
    const cart = await add(who, phone.id, 3, phone.variants[1]!.id)
    assert.equal(cart.groups[0].items[0].quantity, 3)
  })

  test('Buy now leaves the cart and its code alone, and takes no coupon', async () => {
    const store = await openStore()
    const phone = await listed(store, { price: 100_000 })
    const watch = await listed(store, { price: 50_000 })
    const code = await coupon(store, { value: 10 })
    const who = await shopper()
    await add(who, phone.id)
    await apply(who, code.code)
    const made = await placed(who, { items: [{ productId: watch.id, quantity: 2 }] })
    assert.equal(made.subtotal, 100_000)
    assert.equal(made.discount, 0)
    assert.equal(await stockOf(watch.id), 8)
    const cart = (await h.call('GET', '/cart', { token: who.token })).body.data
    assert.equal(cart.groups[0].items[0].productId, phone.id)
    assert.equal(cart.coupon.code, code.code)
  })

  test("Buy now's refusals don't speak of the cart (M9)", async () => {
    const store = await openStore()
    const gone = await listed(store, { name: 'Gone Phone', price: 100_000, stock: 1 })
    const dear = await listed(store, { name: 'Dear Phone', price: 600_000, stock: 5 })
    const who = await shopper()
    await h.call('PATCH', `/merchants/me/products/${gone.id}/stock`, { token: store.token, body: { stock: 0 } })
    const review = async (items: unknown[]) =>
      (await h.call('POST', '/checkout/review', { token: who.token, body: { addressId: who.addressId, items } })).body.data.warnings
    assert.deepEqual(await review([{ productId: gone.id, quantity: 1 }]), ['Gone Phone has run out.'])
    assert.deepEqual(await review([{ productId: dear.id, quantity: 2 }]), [
      'Your first order can be up to 1,000,000 IQD. Choose fewer, or buy more once this order has arrived.',
    ])
    const refused = await place(who, { items: [{ productId: gone.id, quantity: 1 }] })
    assert.equal(refused.status, 422)
    assert.equal(refused.body.message, 'Gone Phone has run out.')
    // The cart's own words stay the cart's.
    await add(who, dear.id, 2)
    assert.deepEqual((await h.call('POST', '/checkout/review', { token: who.token, body: { addressId: who.addressId } })).body.data.warnings, [
      'Your first order can be up to 1,000,000 IQD. Take something out, or buy the rest once this order has arrived.',
    ])
  })
})

// ------------------------------------------------------------ placing orders ---

describe('placing an order', () => {
  test('two shoppers, one unit left: exactly one order (DATABASE_DESIGN.md §5.4)', async () => {
    const store = await openStore()
    const last = await listed(store, { stock: 1 })
    const first = await shopper()
    const second = await shopper()
    await add(first, last.id)
    await add(second, last.id)
    const replies = await Promise.all([place(first), place(second)])
    assert.deepEqual(replies.map((reply) => reply.status).sort(), [200, 422])
    assert.equal(replies.find((reply) => reply.status === 422)!.body.code, 'INVENTORY_ERROR')
    assert.equal(await stockOf(last.id), 0)
    assert.equal((await ledger(last.id)).length, 1)
    assert.equal(Number((await one<{ n: number }>(h.pool, 'SELECT COUNT(*) AS n FROM order_store_parts WHERE store_id = ?', [store.id]))!.n), 1)
  })

  test('a coupon with one use left, two shoppers at once: one discount, the other told', async () => {
    const store = await openStore()
    const phone = await listed(store)
    const code = await coupon(store, { value: 10, usageLimit: 1 })
    const first = await shopper()
    const second = await shopper()
    for (const who of [first, second]) {
      await add(who, phone.id)
      await apply(who, code.code)
    }
    const replies = await Promise.all([place(first), place(second)])
    assert.deepEqual(replies.map((reply) => reply.status).sort(), [200, 422])
    assert.equal(replies.find((reply) => reply.status === 200)!.body.data.order.discount, 14_500)
    assert.match(replies.find((reply) => reply.status === 422)!.body.message, new RegExp(code.code))
    assert.equal((await one<{ used_count: number }>(h.pool, 'SELECT used_count FROM coupons WHERE id = ?', [code.id]))!.used_count, 1)
    // The second shopper sees why: the code is still on the cart, taking nothing off.
    const late = replies[0]!.status === 422 ? first : second
    const cart = (await h.call('GET', '/cart', { token: late.token })).body.data
    assert.equal(cart.totals.couponDiscount, 0)
    assert.equal(cart.coupon.applies, false)
    const review = (await h.call('POST', '/checkout/review', { token: late.token, body: {} })).body.data
    assert.equal(review.canPlaceOrder, false)
    assert.match(review.warnings[0], new RegExp(code.code))
    await h.call('DELETE', '/cart/coupon', { token: late.token })
    assert.equal((await placed(late)).discount, 0)
  })

  test("a code's use comes back when its store's part ends without a sale: declined, cancelled, refused; never after a delivery, never for another store", async () => {
    const store = await openStore()
    const other = await openStore()
    const phone = await listed(store, { stock: 50 })
    const otherPhone = await listed(other, { stock: 50 })
    const code = await coupon(store, { value: 10, usageLimit: 1 })
    const used = async () => (await one<{ used_count: number }>(h.pool, 'SELECT used_count FROM coupons WHERE id = ?', [code.id]))!.used_count
    /** An order that used the code: from its store, and from [also] too when given. */
    async function withCode(also?: string) {
      const who = await shopper()
      await add(who, phone.id)
      if (also) await add(who, also)
      await apply(who, code.code)
      const made = await placed(who)
      assert.equal(made.discount, 14_500)
      assert.equal(await used(), 1)
      return { who, order: made as { id: string } }
    }

    // Declined by its store.
    let { order } = await withCode()
    assert.equal((await step(store, await partOf(order.id, store), 'CANCELLED', { reason: 'OUT_OF_STOCK' })).status, 200)
    assert.equal(await used(), 0)
    // Cancelled by the shopper.
    const cancelled = await withCode()
    const called = await h.call('POST', `/orders/${cancelled.order.id}/cancel`, { token: cancelled.who.token, body: { reason: 'CHANGED_MIND' } })
    assert.equal(called.status, 200, JSON.stringify(called.body))
    assert.equal(await used(), 0)
    // Refused at the door.
    ;({ order } = await withCode())
    const part = await partOf(order.id, store)
    await walk(store, part, 'SHIPPED')
    assert.equal((await step(store, part, 'REFUSED')).status, 200)
    assert.equal(await used(), 0)
    // Two stores: the other store's part called off keeps the use; its own store's gives it back.
    ;({ order } = await withCode(otherPhone.id))
    assert.equal((await step(other, await partOf(order.id, other), 'CANCELLED', { reason: 'OUT_OF_STOCK' })).status, 200)
    assert.equal(await used(), 1)
    assert.equal((await step(store, await partOf(order.id, store), 'CANCELLED', { reason: 'OUT_OF_STOCK' })).status, 200)
    assert.equal(await used(), 0)
    // Delivered: the use stays spent, and the limit holds for the next shopper.
    ;({ order } = await withCode())
    await walk(store, await partOf(order.id, store), 'DELIVERED')
    assert.equal(await used(), 1)
    const late = await shopper()
    await add(late, phone.id)
    const refused = await h.call('POST', '/cart/coupon', { token: late.token, body: { code: code.code } })
    assert.notEqual(refused.status, 200)
  })

  test("a call-off takes the code before the stock, in checkout's order, so the two never deadlock", async () => {
    const store = await openStore()
    const phone = await listed(store, { stock: 50 })
    const code = await coupon(store, { value: 10 })
    const sku = (await one<{ id: number }>(h.pool, 'SELECT id FROM product_skus WHERE product_id = ?', [phone.id]))!.id
    async function withCode() {
      const who = await shopper()
      await add(who, phone.id)
      await apply(who, code.code)
      return { who, order: (await placed(who)) as { id: string } }
    }
    /**
     * Runs [callOff] while the test holds the code's row, as a checkout does before it takes the
     * stock. True when the call-off, waiting for the code, already holds the stock: the other half
     * of a deadlock with that checkout.
     */
    async function holdsStockWaitingForCode(callOff: () => ReturnType<Harness['call']>): Promise<boolean> {
      const holder = await h.pool.getConnection()
      try {
        await holder.beginTransaction()
        await holder.query('SELECT id FROM coupons WHERE id = ? FOR UPDATE', [code.id])
        const pending = callOff()
        let held = false
        for (const started = Date.now(); !held && Date.now() - started < 1500; ) {
          await new Promise((resolve) => setTimeout(resolve, 50))
          try {
            await h.pool.query('SELECT id FROM product_skus WHERE id = ? FOR UPDATE NOWAIT', [sku])
          } catch (error) {
            if ((error as { errno?: number }).errno !== 3572) throw error // ER_LOCK_NOWAIT
            held = true
          }
        }
        await holder.commit()
        const reply = await pending
        assert.equal(reply.status, 200, JSON.stringify(reply.body))
        return held
      } finally {
        holder.release()
      }
    }

    const cancelled = await withCode()
    const cancel = () => h.call('POST', `/orders/${cancelled.order.id}/cancel`, { token: cancelled.who.token, body: { reason: 'CHANGED_MIND' } })
    assert.equal(await holdsStockWaitingForCode(cancel), false, 'the shopper cancelling')
    const declined = await partOf((await withCode()).order.id, store)
    assert.equal(await holdsStockWaitingForCode(() => step(store, declined, 'CANCELLED', { reason: 'OUT_OF_STOCK' })), false, 'the store declining')
    const refused = await partOf((await withCode()).order.id, store)
    await walk(store, refused, 'SHIPPED')
    assert.equal(await holdsStockWaitingForCode(() => step(store, refused, 'REFUSED')), false, 'refused at the door')
    assert.equal(await stockOf(phone.id), 50)
  })

  test('the same key twice is one order, even at the same moment; the key with another body is refused', async () => {
    const store = await openStore()
    const phone = await listed(store)
    const who = await shopper()
    await add(who, phone.id)
    const [a, b] = await Promise.all([place(who, {}, 'same-key'), place(who, {}, 'same-key')])
    assert.equal(a.status, 200, JSON.stringify(a.body))
    assert.equal(b.status, 200, JSON.stringify(b.body))
    assert.equal(a.body.data.order.id, b.body.data.order.id)
    const retry = await place(who, {}, 'same-key')
    assert.equal(retry.body.data.order.id, a.body.data.order.id)
    assert.equal(await stockOf(phone.id), 9)
    assert.equal(Number((await one<{ n: number }>(h.pool, 'SELECT COUNT(*) AS n FROM orders WHERE customer_id = ?', [who.id]))!.n), 1)
    const other = await place(who, { deliveryInstructions: 'Call first' }, 'same-key')
    assert.equal(other.status, 422)
  })

  test('the first order can be up to 1,000,000 IQD, until one has been delivered and paid', async () => {
    const store = await openStore()
    const laptop = await listed(store, { price: 998_000 })
    const who = await shopper()
    await add(who, laptop.id)
    const review = (await h.call('POST', '/checkout/review', { token: who.token, body: { addressId: who.addressId } })).body.data
    assert.equal(review.totals.total, 1_001_000)
    assert.equal(review.canPlaceOrder, false)
    assert.match(review.warnings[0], /1,000,000 IQD/)
    const refused = await place(who)
    assert.equal(refused.status, 422)
    assert.equal(refused.body.code, 'BUSINESS_RULE_ERROR')

    // A small order first, delivered and so paid: then the big one goes.
    const small = await listed(store, { price: 10_000 })
    const saved = (await h.call('GET', '/cart', { token: who.token })).body.data.groups[0].items[0].id
    await h.call('POST', `/cart/items/${saved}/save-for-later`, { token: who.token })
    await add(who, small.id)
    const first = await placed(who)
    const moved = (await h.call('GET', '/cart', { token: who.token })).body.data.savedForLater[0].id
    await h.call('POST', `/cart/items/${moved}/move-to-cart`, { token: who.token })
    // Placed is not enough: it has to have arrived and been paid.
    const part = await partOf(first.id, store)
    await walk(store, part, 'SHIPPED')
    assert.equal((await place(who)).status, 422)
    assert.equal((await step(store, part, 'DELIVERED')).status, 200)
    assert.equal((await place(who)).status, 200)
  })

  test('refused: no key, not cash, no address, another shopper\'s address, an empty cart', async () => {
    const store = await openStore()
    const phone = await listed(store)
    const who = await shopper()
    const other = await shopper()
    await add(who, phone.id)
    const noKey = await h.call('POST', '/checkout/place-order', { token: who.token, body: { addressId: who.addressId } })
    assert.equal(noKey.status, 422)
    assert.ok(noKey.body.errors.idempotencyKey)
    assert.equal((await place(who, { paymentMethodId: 'pm-card' })).status, 422)
    assert.ok((await place(who, { addressId: null })).body.errors.addressId)
    assert.ok((await place(who, { addressId: other.addressId })).body.errors.addressId)
    const empty = await place(other)
    assert.equal(empty.status, 422)
    assert.equal(empty.body.code, 'BUSINESS_RULE_ERROR')
    assert.equal(await stockOf(phone.id), 10)
  })

  test("the store is told of a new order, in both languages; the shopper's open order blocks deleting the account", async () => {
    const store = await openStore()
    const phone = await listed(store)
    const who = await shopper()
    await add(who, phone.id, 2)
    const made = await placed(who)
    const told = await one<{ title_en: string; body_en: string; title_ar: string; entity_type: string; entity_id: string }>(
      h.pool,
      "SELECT title_en, body_en, title_ar, entity_type, entity_id FROM notifications WHERE user_id = ? AND type = 'ORDER' ORDER BY id DESC LIMIT 1",
      [store.ownerId],
    )
    assert.equal(told!.title_en, `New order ${made.orderNumber}`)
    assert.equal(told!.body_en, 'Amina Saleh ordered 2 items. Confirm it to start.')
    assert.equal(told!.title_ar, `طلب جديد ${made.orderNumber}`)
    assert.equal(told!.entity_type, 'STORE_ORDER')
    assert.equal(Number(told!.entity_id), await partOf(made.id, store))
    const deleting = await h.call('DELETE', '/customers/me', { token: who.token })
    assert.equal(deleting.status, 409)
    assert.match(deleting.body.message, new RegExp(made.orderNumber))
  })
})

// ----------------------------------------------------------- the store's steps ---

describe("the store's steps (DATABASE_DESIGN.md §5.3)", () => {
  test('only the table: each step in turn, anything else 409; delivered is on its Baghdad month and paid', async () => {
    const store = await openStore()
    const phone = await listed(store)
    const who = await shopper()
    await add(who, phone.id)
    const made = await placed(who)
    const part = await partOf(made.id, store)
    const tries: [string, string, number][] = [
      ['SHIPPED', 'PENDING', 409],
      ['DELIVERED', 'PENDING', 409],
      ['CONFIRMED', 'PENDING', 200],
      ['CONFIRMED', 'CONFIRMED', 409],
      ['CANCELLED', 'CONFIRMED', 409],
      ['DELIVERED', 'CONFIRMED', 409],
      ['PROCESSING', 'CONFIRMED', 200],
      ['REFUSED', 'PROCESSING', 409],
    ]
    for (const [to, from, status] of tries) {
      const reply = await step(store, part, to, { reason: 'OUT_OF_STOCK' })
      assert.equal(reply.status, status, `${from} → ${to}: ${JSON.stringify(reply.body)}`)
    }
    assert.equal((await order(who, made.id)).status, 'PROCESSING')
    assert.equal((await step(store, part, 'SHIPPED', { courierName: 'Haider Salim', courierPhone: '0770 555 0311' })).status, 200)
    assert.equal((await step(store, part, 'CONFIRMED')).status, 409)
    // With the driver: declined now, its stock would come back while the goods are on the road.
    assert.equal((await step(store, part, 'CANCELLED', { reason: 'OUT_OF_STOCK' })).status, 409)
    const shipped = await order(who, made.id)
    assert.equal(shipped.status, 'SHIPPED')
    assert.equal(shipped.paymentStatus, 'PENDING')
    assert.equal(shipped.canCancel, false)
    assert.equal(shipped.storeParts[0].courierPhone, '+9647705550311')

    const delivered = await step(store, part, 'DELIVERED')
    assert.equal(delivered.status, 200)
    assert.equal(delivered.body.data.status, 'DELIVERED')
    for (const to of ['REFUSED', 'CANCELLED', 'SHIPPED']) assert.equal((await step(store, part, to, { reason: 'OUT_OF_STOCK' })).status, 409)
    const row = await one<{ month: string; delivered_at: Date }>(
      h.pool,
      "SELECT DATE_FORMAT(billing_month, '%Y-%m-%d') AS month, delivered_at FROM order_store_parts WHERE id = ?",
      [part],
    )
    assert.equal(row!.month, billingMonth(row!.delivered_at))
    const done = await order(who, made.id)
    assert.equal(done.status, 'DELIVERED')
    assert.equal(done.paymentStatus, 'PAID')
    assert.ok(done.deliveredAt)
    assert.equal(done.items[0].canReturn, true)
    // The shopper was told each step.
    const told = await rows<{ title_en: string }>(h.pool, 'SELECT title_en FROM notifications WHERE user_id = ? ORDER BY id', [who.id])
    assert.equal(told.length, 4)
    assert.match(told[2]!.title_en, /on its way/)
  })

  test('a decline needs its reason; its stock goes back once; the order is called off by the store', async () => {
    const store = await openStore()
    const phone = await listed(store)
    const who = await shopper()
    await add(who, phone.id, 3)
    const made = await placed(who)
    const part = await partOf(made.id, store)
    assert.equal(await stockOf(phone.id), 7)
    const noReason = await step(store, part, 'CANCELLED')
    assert.equal(noReason.status, 422)
    assert.ok(noReason.body.errors.reason)
    assert.equal((await step(store, part, 'CANCELLED', { reason: 'MADE_UP' })).status, 422)
    assert.equal((await step(store, part, 'CANCELLED', { reason: 'OUT_OF_STOCK' })).status, 200)
    assert.equal(await stockOf(phone.id), 10)
    assert.deepEqual((await ledger(phone.id)).at(-1), { delta: 3, reason: 'PART_DECLINED', part_id: part })
    assert.equal((await step(store, part, 'CANCELLED', { reason: 'OUT_OF_STOCK' })).status, 409)
    assert.equal(await stockOf(phone.id), 10)
    const off = await order(who, made.id)
    assert.equal(off.status, 'CANCELLED')
    assert.equal(off.paymentStatus, 'CANCELLED')
    assert.equal(off.cancelReason, 'OUT_OF_STOCK')
    assert.equal(off.canCancel, false)
    const told = await one<{ body_en: string }>(h.pool, 'SELECT body_en FROM notifications WHERE user_id = ? ORDER BY id DESC LIMIT 1', [who.id])
    assert.equal(told!.body_en, `Order ${made.orderNumber}: Out of stock. Nothing is charged for it.`)
  })

  test('refused at the door: stock back, nothing to pay', async () => {
    const store = await openStore()
    const phone = await listed(store)
    const who = await shopper()
    await add(who, phone.id, 2)
    const made = await placed(who)
    const part = await partOf(made.id, store)
    await walk(store, part, 'SHIPPED')
    assert.equal((await step(store, part, 'REFUSED')).status, 200)
    assert.equal(await stockOf(phone.id), 10)
    assert.deepEqual((await ledger(phone.id)).at(-1), { delta: 2, reason: 'PART_REFUSED', part_id: part })
    assert.equal((await step(store, part, 'REFUSED')).status, 409)
    const off = await order(who, made.id)
    assert.equal(off.status, 'REFUSED')
    assert.equal(off.paymentStatus, 'CANCELLED')
  })

  test('shipping names the driver: a name and an Iraqi phone, 422 on the missing one', async () => {
    const store = await openStore()
    const phone = await listed(store)
    const who = await shopper()
    await add(who, phone.id)
    const part = await partOf((await placed(who)).id, store)
    await walk(store, part, 'PROCESSING')
    assert.ok((await step(store, part, 'SHIPPED', { courierPhone: '07701112222' })).body.errors.courierName)
    assert.ok((await step(store, part, 'SHIPPED', { courierName: 'Haider' })).body.errors.courierPhone)
    assert.ok((await step(store, part, 'SHIPPED', { courierName: 'Haider', courierPhone: '12345' })).body.errors.courierPhone)
    const shipped = await step(store, part, 'SHIPPED', { courierName: 'Haider', courierPhone: '+964 770 111 2222' })
    assert.equal(shipped.status, 200)
    assert.equal(shipped.body.data.courierPhone, '+9647701112222')
    const told = await one<{ body_en: string }>(h.pool, 'SELECT body_en FROM notifications WHERE user_id = ? ORDER BY id DESC LIMIT 1', [who.id])
    assert.match(told!.body_en, /Haider brings it, \+964 770 111 2222$/)
  })

  test('two stores: the order is as far as its slowest live part, and paid only when every live part has arrived', async () => {
    const nova = await openStore('BAGHDAD')
    const atlas = await openStore('BAGHDAD')
    const phone = await listed(nova)
    const fryer = await listed(atlas, { price: 95_000 })
    const who = await shopper()
    await add(who, phone.id)
    await add(who, fryer.id)
    const made = await placed(who)
    const novaPart = await partOf(made.id, nova)
    const atlasPart = await partOf(made.id, atlas)
    await walk(nova, novaPart, 'DELIVERED')
    let now = await order(who, made.id)
    assert.equal(now.status, 'PENDING')
    assert.equal(now.paymentStatus, 'PENDING')
    assert.equal(now.canCancel, false)
    await walk(atlas, atlasPart, 'SHIPPED')
    now = await order(who, made.id)
    assert.equal(now.status, 'SHIPPED')
    assert.deepEqual(
      now.items.map((i: any) => i.status),
      ['DELIVERED', 'SHIPPED'],
    )
    assert.equal((await step(atlas, atlasPart, 'DELIVERED')).status, 200)
    now = await order(who, made.id)
    assert.equal(now.status, 'DELIVERED')
    assert.equal(now.paymentStatus, 'PAID')

    // One declined, the other delivered: delivered and paid.
    await add(who, phone.id)
    await add(who, fryer.id)
    const second = await placed(who)
    assert.equal((await step(atlas, await partOf(second.id, atlas), 'CANCELLED', { reason: 'CANNOT_FULFIL' })).status, 200)
    let mixed = await order(who, second.id)
    assert.equal(mixed.status, 'PENDING')
    assert.equal(mixed.paymentStatus, 'PENDING')
    await walk(nova, await partOf(second.id, nova), 'DELIVERED')
    mixed = await order(who, second.id)
    assert.equal(mixed.status, 'DELIVERED')
    assert.equal(mixed.paymentStatus, 'PAID')
    assert.equal(mixed.items.find((i: any) => i.productId === fryer.id).status, 'CANCELLED')
  })

  test("another store's part is not found; a shopper can't move parts", async () => {
    const store = await openStore()
    const stranger = await openStore()
    const phone = await listed(store)
    const who = await shopper()
    await add(who, phone.id)
    const part = await partOf((await placed(who)).id, store)
    assert.equal((await step(stranger, part, 'CONFIRMED')).status, 404)
    assert.equal((await h.call('GET', `/merchants/me/orders/${part}`, { token: stranger.token })).status, 404)
    assert.equal((await h.call('PATCH', `/merchants/me/orders/${part}/status`, { token: who.token, body: { status: 'CONFIRMED' } })).status, 403)
    const counts = (await h.call('GET', '/merchants/me/orders/counts', { token: store.token })).body.data
    assert.deepEqual(counts, { PENDING: 1 })
    const detail = (await h.call('GET', `/merchants/me/orders/${part}`, { token: store.token })).body.data
    assert.equal(detail.customerPhone, who.phone)
    assert.deepEqual(detail.returns, [])
    const pending = (await h.call('GET', '/merchants/me/orders?status=PENDING,CONFIRMED', { token: store.token })).body
    assert.equal(pending.meta.total, 1)
    assert.equal((await h.call('GET', '/merchants/me/orders?status=SHIPPED', { token: store.token })).body.meta.total, 0)
  })
})

// ------------------------------------------------------------- the shopper ---

describe("the shopper's orders", () => {
  test('cancel while no store is past Confirmed: every live part off, stock back, each store told', async () => {
    const nova = await openStore()
    const atlas = await openStore()
    const phone = await listed(nova)
    const fryer = await listed(atlas, { price: 95_000 })
    const who = await shopper()
    await add(who, phone.id, 2)
    await add(who, fryer.id)
    const made = await placed(who)
    await step(nova, await partOf(made.id, nova), 'CONFIRMED')
    const noReason = await h.call('POST', `/orders/${made.id}/cancel`, { token: who.token, body: {} })
    assert.equal(noReason.status, 422)
    const cancelled = await h.call('POST', `/orders/${made.id}/cancel`, { token: who.token, body: { reason: 'OTHER', note: 'Bought it in town' } })
    assert.equal(cancelled.status, 200, JSON.stringify(cancelled.body))
    const off = cancelled.body.data
    assert.equal(off.status, 'CANCELLED')
    assert.equal(off.paymentStatus, 'CANCELLED')
    assert.equal(off.cancelReason, 'OTHER')
    assert.equal(off.cancelNote, 'Bought it in town')
    assert.equal(off.canCancel, false)
    assert.deepEqual(
      off.storeParts.map((p: any) => p.cancellationReason),
      ['CUSTOMER_CANCELLED', 'CUSTOMER_CANCELLED'],
    )
    assert.equal(await stockOf(phone.id), 10)
    assert.equal(await stockOf(fryer.id), 10)
    assert.deepEqual((await ledger(phone.id)).at(-1), { delta: 2, reason: 'ORDER_CANCELLED', part_id: await partOf(made.id, nova) })
    for (const store of [nova, atlas]) {
      const told = await one<{ title_en: string }>(h.pool, 'SELECT title_en FROM notifications WHERE user_id = ? ORDER BY id DESC LIMIT 1', [
        store.ownerId,
      ])
      assert.equal(told!.title_en, `Order ${made.orderNumber} was cancelled`)
    }
    assert.equal((await h.call('POST', `/orders/${made.id}/cancel`, { token: who.token, body: { reason: 'OTHER' } })).status, 409)
    assert.equal(await stockOf(phone.id), 10)
  })

  test('no cancelling once a store is preparing it; nothing changes', async () => {
    const store = await openStore()
    const phone = await listed(store)
    const who = await shopper()
    await add(who, phone.id)
    const made = await placed(who)
    await walk(store, await partOf(made.id, store), 'PROCESSING')
    const refused = await h.call('POST', `/orders/${made.id}/cancel`, { token: who.token, body: { reason: 'CHANGED_MIND' } })
    assert.equal(refused.status, 409)
    assert.equal(await stockOf(phone.id), 9)
    assert.equal((await order(who, made.id)).status, 'PROCESSING')
    const stranger = await shopper()
    assert.equal((await h.call('GET', `/orders/${made.id}`, { token: stranger.token })).status, 404)
    assert.equal((await h.call('POST', `/orders/${made.id}/cancel`, { token: stranger.token, body: { reason: 'OTHER' } })).status, 404)
  })

  test('the list, newest first and by status; the invoice from the order\'s own figures', async () => {
    const store = await openStore()
    const phone = await listed(store)
    const who = await shopper()
    await add(who, phone.id)
    const first = await placed(who)
    await add(who, phone.id)
    const second = await placed(who)
    await h.call('POST', `/orders/${first.id}/cancel`, { token: who.token, body: { reason: 'CHANGED_MIND' } })
    const list = (await h.call('GET', '/orders', { token: who.token })).body
    assert.deepEqual(
      list.data.map((o: any) => o.id),
      [second.id, first.id],
    )
    assert.equal(list.meta.total, 2)
    const cancelled = (await h.call('GET', '/orders?status=CANCELLED', { token: who.token })).body.data
    assert.deepEqual(
      cancelled.map((o: any) => o.id),
      [first.id],
    )
    const invoice = (await h.call('GET', `/orders/${second.id}/invoice`, { token: who.token })).body.data
    assert.equal(invoice.invoiceNumber, `INV-${second.orderNumber}`)
    assert.equal(invoice.total, 148_000)
    assert.equal(invoice.sellerName, store.name)
    assert.equal(invoice.lines[0].unitPrice, 145_000)
    const arabic = (await h.call('GET', `/orders/${second.id}`, { token: who.token, lang: 'ar' })).body.data
    assert.equal(arabic.items[0].productName, 'سماعات كايت ستوديو')
    assert.equal(arabic.paymentMethodLabel, 'الدفع عند الاستلام')
  })

  test('rating: asked once delivered; stars add to the store once per order; "not received" tells the store', async () => {
    const store = await openStore()
    const phone = await listed(store)
    const who = await shopper()
    await add(who, phone.id)
    const made = await placed(who)
    const part = await partOf(made.id, store)
    assert.deepEqual((await h.call('GET', '/orders/rating-due', { token: who.token })).body.data, {})
    assert.equal((await h.call('POST', `/orders/${made.id}/rating`, { token: who.token, body: { received: true } })).status, 409)
    await walk(store, part, 'DELIVERED')
    const due = (await h.call('GET', '/orders/rating-due', { token: who.token })).body.data
    assert.deepEqual(due, { orderId: made.id, orderNumber: made.orderNumber, stores: [{ id: String(store.id), storeName: store.name }] })

    // "Yes, it arrived" first, then the stars (rate_order_providers.dart).
    assert.equal((await h.call('POST', `/orders/${made.id}/rating`, { token: who.token, body: { received: true } })).status, 200)
    assert.deepEqual((await h.call('GET', '/orders/rating-due', { token: who.token })).body.data, {})
    const rated = await h.call('POST', `/orders/${made.id}/rating`, {
      token: who.token,
      body: { received: true, ratings: { [store.id]: 4 }, comment: 'Quick and well packed' },
    })
    assert.equal(rated.status, 200, JSON.stringify(rated.body))
    assert.equal(rated.body.data.storeParts[0].received, true)
    const page = (await h.call('GET', `/merchants/${store.id}/store`)).body.data
    assert.equal(page.rating, 4)
    assert.equal(page.reviewCount, 1)
    const again = await h.call('POST', `/orders/${made.id}/rating`, { token: who.token, body: { received: true, ratings: { [store.id]: 1 } } })
    assert.equal(again.status, 409)
    assert.equal((await h.call('GET', `/merchants/${store.id}/store`)).body.data.rating, 4)
    const stranger = await openStore()
    assert.equal(
      (await h.call('POST', `/orders/${made.id}/rating`, { token: who.token, body: { received: true, ratings: { [stranger.id]: 5 } } })).status,
      422,
    )
    const reviews = (await h.call('GET', `/merchants/${store.id}/reviews`)).body
    assert.equal(reviews.meta.total, 1)
    assert.equal(reviews.data[0].rating, 4)
    assert.equal(reviews.data[0].body, 'Quick and well packed')
    assert.equal(reviews.data[0].authorName, 'Amina S.')

    // Reported: kept once per shopper.
    for (let i = 0; i < 2; i++) {
      const reported = await h.call('POST', `/reviews/${reviews.data[0].id}/report`, { token: who.token, body: { reason: 'SPAM' } })
      assert.equal(reported.status, 200)
    }
    assert.equal(Number((await one<{ n: number }>(h.pool, 'SELECT COUNT(*) AS n FROM review_reports'))!.n), 1)
    assert.equal((await h.call('POST', '/reviews/999999/report', { token: who.token, body: { reason: 'SPAM' } })).status, 404)
  })

  test('a reported review reaches Saba: removed off the page and out of the rating, or dismissed and kept (before launch)', async () => {
    const store = await openStore()
    const phone = await listed(store)
    const rate = async (stars: number, comment: string) => {
      const who = await shopper()
      await add(who, phone.id)
      const made = await placed(who)
      await walk(store, await partOf(made.id, store), 'DELIVERED')
      const rated = await h.call('POST', `/orders/${made.id}/rating`, { token: who.token, body: { received: true, ratings: { [store.id]: stars }, comment } })
      assert.equal(rated.status, 200, JSON.stringify(rated.body))
      return who
    }
    const kind = await rate(4, 'Quick and well packed')
    await rate(2, 'Rude words here')
    const reviewOf = async (body: string) =>
      (await h.call('GET', `/merchants/${store.id}/reviews`)).body.data.find((review: any) => review.body === body).id as string
    const rudeId = await reviewOf('Rude words here')
    const kindId = await reviewOf('Quick and well packed')
    assert.equal((await h.call('GET', `/merchants/${store.id}/store`)).body.data.rating, 3)

    // Reported, the shopper's words kept.
    const reporter = await shopper()
    const report = (id: string, body: Record<string, unknown>) => h.call('POST', `/reviews/${id}/report`, { token: reporter.token, body })
    assert.equal((await report(rudeId, { reason: 'OFFENSIVE', description: 'Insults the driver.' })).status, 200)
    assert.equal((await report(kindId, { reason: 'SPAM' })).status, 200)
    const open = (await h.call('GET', '/admin/review-reports?status=OPEN', { token: admin })).body.data
    const rude = open.items.find((row: any) => row.id === rudeId)
    assert.deepEqual([rude.status, rude.rating, rude.body, rude.store.id], ['OPEN', 2, 'Rude words here', String(store.id)])
    assert.deepEqual(
      rude.reports.map((one: any) => [one.reason, one.description, one.status]),
      [['OFFENSIVE', 'Insults the driver.', 'OPEN']],
    )
    assert.equal((await h.call('GET', '/admin/review-reports', { token: kind.token })).status, 403)

    // Removed: off the store's page, out of its rating, its reports closed; not twice; no more reports.
    const removed = await h.call('POST', `/admin/review-reports/${rudeId}/remove`, { token: admin })
    assert.equal(removed.status, 200, JSON.stringify(removed.body))
    assert.deepEqual([removed.body.data.status, removed.body.data.reports[0].status], ['REMOVED', 'REMOVED'])
    const page = (await h.call('GET', `/merchants/${store.id}/store`)).body.data
    assert.deepEqual([page.rating, page.reviewCount], [4, 1])
    const left = (await h.call('GET', `/merchants/${store.id}/reviews`)).body
    assert.deepEqual([left.meta.total, left.data.map((review: any) => review.id)], [1, [kindId]])
    assert.equal((await h.call('POST', `/admin/review-reports/${rudeId}/remove`, { token: admin })).status, 409)
    assert.equal((await h.call('POST', `/reviews/${rudeId}/report`, { token: kind.token, body: { reason: 'SPAM' } })).status, 404)

    // Dismissed: the review stays; with nothing left to dismiss, 409.
    const dismissed = await h.call('POST', `/admin/review-reports/${kindId}/dismiss`, { token: admin })
    assert.equal(dismissed.status, 200, JSON.stringify(dismissed.body))
    assert.equal(dismissed.body.data.status, 'DISMISSED')
    assert.equal((await h.call('POST', `/admin/review-reports/${kindId}/dismiss`, { token: admin })).status, 409)
    assert.equal((await h.call('GET', `/merchants/${store.id}/reviews`)).body.meta.total, 1)
    const done = (await h.call('GET', '/admin/review-reports?status=DISMISSED', { token: admin })).body.data.items
    assert.ok(done.some((row: any) => row.id === kindId))
    const audit = await rows<{ action: string }>(
      h.pool,
      "SELECT action FROM admin_actions WHERE entity_type = 'REVIEW' AND entity_id IN (?, ?) ORDER BY id",
      [rudeId, kindId],
    )
    assert.deepEqual(audit.map((row) => row.action), ['REVIEW_REMOVE', 'REVIEW_REPORTS_DISMISS'])
  })

  test("a store reports a review, one about itself too; sent again after Saba closed it, it opens again; Saba's list a page at a time (final review 2, 3, 12)", async () => {
    const store = await openStore()
    const phone = await listed(store)
    const who = await shopper()
    await add(who, phone.id)
    const made = await placed(who)
    await walk(store, await partOf(made.id, store), 'DELIVERED')
    const rated = await h.call('POST', `/orders/${made.id}/rating`, { token: who.token, body: { received: true, ratings: { [store.id]: 1 }, comment: 'Abusive words' } })
    assert.equal(rated.status, 200, JSON.stringify(rated.body))
    const reviewId = (await h.call('GET', `/merchants/${store.id}/reviews`)).body.data[0].id as string
    const report = (body: Record<string, unknown>) => h.call('POST', `/reviews/${reviewId}/report`, { token: store.token, body })
    const itemOf = async (query = '') =>
      (await h.call('GET', `/admin/review-reports?perPage=100${query}`, { token: admin })).body.data.items.find((row: any) => row.id === reviewId)

    // The store reports the review about itself.
    assert.equal((await report({ reason: 'OFFENSIVE', description: 'Insults our staff.' })).status, 200)
    assert.deepEqual((await itemOf()).reports.map((r: any) => [r.reporterRole, r.status, r.description]), [['MERCHANT', 'OPEN', 'Insults our staff.']])
    // Saba dismisses it; sent again, it opens again with the new words, still one report.
    assert.equal((await h.call('POST', `/admin/review-reports/${reviewId}/dismiss`, { token: admin })).status, 200)
    assert.equal((await report({ reason: 'SPAM', description: 'Still abusive.' })).status, 200)
    const reopened = await itemOf('&status=OPEN')
    assert.deepEqual([reopened.status, reopened.reports.map((r: any) => [r.reason, r.description, r.status])], ['OPEN', [['SPAM', 'Still abusive.', 'OPEN']]])
    assert.equal(Number((await one<{ n: number }>(h.pool, 'SELECT COUNT(*) AS n FROM review_reports WHERE review_id = ?', [reviewId]))!.n), 1)
    // Sent again while open: kept as it was.
    assert.equal((await report({ reason: 'OTHER' })).status, 200)
    assert.equal((await itemOf()).reports[0].reason, 'SPAM')

    // A page at a time, newest first, the whole list's counts on every page.
    const whole = (await h.call('GET', '/admin/review-reports?perPage=100', { token: admin })).body
    const first = (await h.call('GET', '/admin/review-reports?page=1&perPage=1', { token: admin })).body
    assert.deepEqual(first.meta, { page: 1, perPage: 1, total: whole.data.counts.all, totalPages: whole.data.counts.all })
    assert.deepEqual([first.data.items.map((r: any) => r.id), first.data.counts], [[reviewId], whole.data.counts])
    assert.equal((await h.call('GET', '/admin/review-reports?status=OPEN&page=1&perPage=1', { token: admin })).body.meta.total, whole.data.counts.OPEN)
    // A guest is asked to sign in.
    assert.equal((await h.call('POST', `/reviews/${reviewId}/report`, { body: { reason: 'SPAM' } })).status, 401)
  })

  test("a photo past orders show can't be deleted, even once its product dropped it (final review 7)", async () => {
    const store = await openStore()
    const form = new FormData()
    form.append('file', new Blob([new Uint8Array(PNG)]), 'p.png')
    const photo = (await h.call('POST', '/media/upload', { token: store.token, form })).body.data
    const phone = await listed(store, { images: [photo.url] })
    const who = await shopper()
    await add(who, phone.id)
    await placed(who)
    const dropped = await h.call('PUT', `/merchants/me/products/${phone.id}`, {
      token: store.token,
      body: { name: 'Kite Studio Headphones', nameAr: 'سماعات كايت ستوديو', categoryId: SMARTPHONES, price: 145_000, stock: 9, images: [] },
    })
    assert.equal(dropped.status, 200, JSON.stringify(dropped.body))
    const refused = await h.call('DELETE', `/media/${photo.id}`, { token: store.token })
    assert.deepEqual([refused.status, refused.body.message], [409, "Past orders show this photo, so it can't be deleted."])
  })

  test('"not received" tells the store; "not now" three times and the sheet stops asking', async () => {
    const store = await openStore()
    const phone = await listed(store)
    const who = await shopper()
    await add(who, phone.id)
    const first = await placed(who)
    await walk(store, await partOf(first.id, store), 'DELIVERED')
    const no = await h.call('POST', `/orders/${first.id}/received`, { token: who.token, body: { merchantId: String(store.id), received: false } })
    assert.equal(no.status, 200)
    assert.equal(no.body.data.storeParts[0].received, false)
    const told = await one<{ title_en: string }>(h.pool, 'SELECT title_en FROM notifications WHERE user_id = ? ORDER BY id DESC LIMIT 1', [
      store.ownerId,
    ])
    assert.equal(told!.title_en, `Order ${first.orderNumber}: not received`)

    await add(who, phone.id)
    const second = await placed(who)
    assert.equal(
      (await h.call('POST', `/orders/${second.id}/received`, { token: who.token, body: { merchantId: String(store.id), received: true } })).status,
      409,
    )
    await walk(store, await partOf(second.id, store), 'DELIVERED')
    for (let skip = 0; skip < 3; skip++) {
      assert.equal((await h.call('GET', '/orders/rating-due', { token: who.token })).body.data.orderId, second.id)
      await h.call('POST', `/orders/${second.id}/rating-skipped`, { token: who.token })
    }
    assert.deepEqual((await h.call('GET', '/orders/rating-due', { token: who.token })).body.data, {})
  })
})

// ------------------------------------------------------------------ coupons ---

describe("a store's coupons", () => {
  test('made, listed, changed, paused and deleted by their own store only', async () => {
    const store = await openStore()
    const other = await openStore()
    const made = await coupon(store, { code: ' nova10x ', value: 10, minOrderAmount: 100_000, usageLimit: 50 })
    assert.equal(made.code, 'NOVA10X')
    const list = (await h.call('GET', '/merchants/me/coupons', { token: store.token })).body.data
    assert.deepEqual(
      list.map((c: any) => c.code),
      ['NOVA10X'],
    )
    assert.equal((await h.call('GET', '/merchants/me/coupons', { token: other.token })).body.data.length, 0)
    assert.equal((await h.call('PATCH', `/merchants/me/coupons/${made.id}`, { token: other.token, body: { isActive: false } })).status, 404)

    const paused = await h.call('PATCH', `/merchants/me/coupons/${made.id}`, { token: store.token, body: { isActive: false } })
    assert.equal(paused.body.data.isActive, false)
    const offers = (await h.call('GET', `/merchants/${store.id}/coupons`)).body.data
    assert.equal(offers.length, 0)
    const changed = await h.call('PUT', `/merchants/me/coupons/${made.id}`, {
      token: store.token,
      body: { code: 'NOVA15X', discountType: 'PERCENTAGE', value: 15, startsAt: yesterday(), isActive: true },
    })
    assert.equal(changed.status, 200, JSON.stringify(changed.body))
    assert.equal(changed.body.data.value, 15)
    assert.equal(changed.body.data.minOrderAmount, null)
    assert.equal((await h.call('GET', `/merchants/${store.id}/coupons`)).body.data[0].code, 'NOVA15X')
    assert.equal((await h.call('DELETE', `/merchants/me/coupons/${made.id}`, { token: store.token })).status, 200)
    assert.equal((await h.call('GET', '/merchants/me/coupons', { token: store.token })).body.data.length, 0)
  })

  test("the rules: a code once across Saba, 3–15 letters or digits; fixed in steps of 250; at most 90%; the end after the start", async () => {
    const store = await openStore()
    const other = await openStore()
    await coupon(store, { code: 'TAKEN1' })
    const cases: [Record<string, unknown>, string][] = [
      [{ code: 'TAKEN1' }, 'code'],
      [{ code: 'AB' }, 'code'],
      [{ code: 'NO-DASH' }, 'code'],
      [{ discountType: 'FIXED', value: 1100 }, 'value'],
      [{ discountType: 'PERCENTAGE', value: 95 }, 'value'],
      [{ value: 0 }, 'value'],
      [{ endsAt: new Date(NOW() - 2 * 86_400_000).toISOString() }, 'endsAt'],
    ]
    for (const [body, field] of cases) {
      const reply = await h.call('POST', '/merchants/me/coupons', {
        token: other.token,
        body: { code: 'FRESH1', discountType: 'PERCENTAGE', value: 10, startsAt: yesterday(), ...body },
      })
      assert.equal(reply.status, 422, JSON.stringify(body))
      assert.ok(reply.body.errors[field], `${field}: ${JSON.stringify(reply.body.errors)}`)
    }
    const fixed = await coupon(other, { code: 'FIXED5000', discountType: 'FIXED', value: 5000 })
    assert.equal(fixed.code, 'FIXED5000')
  })

  test('a limit never goes below the uses so far', async () => {
    const store = await openStore()
    const phone = await listed(store)
    const code = await coupon(store, { value: 10, usageLimit: 5 })
    for (let i = 0; i < 2; i++) {
      const who = await shopper()
      await add(who, phone.id)
      await apply(who, code.code)
      await placed(who)
    }
    const lower = await h.call('PUT', `/merchants/me/coupons/${code.id}`, {
      token: store.token,
      body: { code: code.code, value: 10, usageLimit: 1, startsAt: yesterday() },
    })
    assert.equal(lower.status, 422)
    assert.match(lower.body.errors.usageLimit, /2/)
    // 0 is not "no limit" (that is an empty box): refused, so a store typing 0 to stop it isn't given the opposite (M9).
    const zero = await h.call('PUT', `/merchants/me/coupons/${code.id}`, {
      token: store.token,
      body: { code: code.code, value: 10, usageLimit: 0, startsAt: yesterday() },
    })
    assert.equal(zero.status, 422)
    assert.equal(zero.body.errors.usageLimit, 'Use at least 1.')
    const kept = await h.call('PUT', `/merchants/me/coupons/${code.id}`, {
      token: store.token,
      body: { code: code.code, value: 10, usageLimit: 2, startsAt: yesterday() },
    })
    assert.equal(kept.body.data.usedCount, 2)
    // Used up: no longer offered.
    assert.equal((await h.call('GET', `/merchants/${store.id}/coupons`)).body.data.length, 0)
  })

  test("a day picked on the phone is Iraq's day: 2026-10-01T00:00:00.000 starts at 21:00 UTC the day before", async () => {
    const store = await openStore()
    const made = await coupon(store, { startsAt: '2026-10-01T00:00:00.000', endsAt: '2026-10-31T23:59:59.000' })
    const list = (await h.call('GET', '/merchants/me/coupons', { token: store.token })).body.data
    const row = list.find((c: any) => c.id === made.id)
    assert.equal(row.startsAt, '2026-09-30T21:00:00.000Z')
    assert.equal(row.endsAt, '2026-10-31T20:59:59.000Z')
  })

  test('applying: unknown, not started (says when), for another store, paused', async () => {
    const store = await openStore()
    const phone = await listed(store)
    const elsewhere = await openStore()
    const who = await shopper()
    await add(who, phone.id)
    const unknown = await h.call('POST', '/cart/coupon', { token: who.token, body: { code: 'NOPE99' } })
    assert.equal(unknown.status, 422)
    assert.equal(unknown.body.errors.code, 'This code is not valid or has expired.')
    const ended = await coupon(store, { startsAt: new Date(NOW() - 3 * 86_400_000).toISOString(), endsAt: yesterday() })
    assert.equal((await h.call('POST', '/cart/coupon', { token: who.token, body: { code: ended.code } })).status, 422)
    const later = await coupon(store, { startsAt: new Date(NOW() + 5 * 86_400_000).toISOString() })
    assert.match((await h.call('POST', '/cart/coupon', { token: who.token, body: { code: later.code } })).body.errors.code, /^This code starts on /)
    const theirs = await coupon(elsewhere, {})
    assert.match((await h.call('POST', '/cart/coupon', { token: who.token, body: { code: theirs.code } })).body.errors.code, /Add something from that store/)
    const mine = await coupon(store, {})
    await h.call('PATCH', `/merchants/me/coupons/${mine.id}`, { token: store.token, body: { isActive: false } })
    const paused = await h.call('POST', '/cart/coupon', { token: who.token, body: { code: mine.code.toLowerCase() } })
    assert.equal(paused.status, 422)
    // Paused says paused, not "not valid or has expired" (the user, after M9).
    assert.equal(paused.body.errors.code, 'Its store has paused this code for now.')
    const pausedAr = await h.call('POST', '/cart/coupon', { token: who.token, body: { code: mine.code }, lang: 'ar' })
    assert.equal(pausedAr.body.errors.code, 'أوقف المتجر هذا الرمز مؤقتاً.')
  })
})

// ------------------------------------------------------------------- Saba ---

describe("Saba's orders", () => {
  test('every order, counted by status; found by number, phone, product in Arabic, city in Arabic; one order in full', async () => {
    const store = await openStore()
    const phone = await listed(store)
    const who = await shopper()
    await add(who, phone.id)
    const made = await placed(who)
    await add(who, phone.id)
    const second = await placed(who)
    await walk(store, await partOf(second.id, store), 'SHIPPED')
    const all = (await h.call('GET', '/admin/orders', { token: admin })).body.data
    assert.ok(all.counts.all >= 2)
    assert.ok(all.items.some((o: any) => o.id === made.id))
    const q = async (text: string) =>
      (await h.call('GET', `/admin/orders?q=${encodeURIComponent(text)}`, { token: admin })).body.data.items.map((o: any) => o.id) as string[]
    assert.deepEqual(await q(made.orderNumber), [made.id])
    const national = who.phone.slice(4)
    assert.ok((await q(`0${national}`)).includes(made.id))
    assert.ok((await q('كايت')).includes(made.id))
    assert.ok((await q('بغداد')).includes(made.id))
    const shipped = (await h.call('GET', '/admin/orders?status=SHIPPED,DELIVERED', { token: admin })).body.data.items
    assert.ok(shipped.every((o: any) => o.status === 'SHIPPED' || o.status === 'DELIVERED'))
    assert.ok(shipped.some((o: any) => o.id === second.id))
    const one_ = (await h.call('GET', `/admin/orders/${second.id}`, { token: admin })).body.data
    assert.equal(one_.storeParts[0].courierName, 'Haider Salim')
    assert.equal(one_.storeParts[0].subtotal, 145_000)
    assert.equal(one_.items[0].productNameAr, 'سماعات كايت ستوديو')
    assert.equal(one_.timeline[0].status, 'PENDING')
    assert.equal((await h.call('GET', '/admin/orders/999999', { token: admin })).status, 404)
    assert.equal((await h.call('GET', '/admin/orders', { token: who.token })).status, 403)
  })
})
