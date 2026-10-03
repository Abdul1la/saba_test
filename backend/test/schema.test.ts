import assert from 'node:assert/strict'
import { after, before, describe, test } from 'node:test'
import mysql from 'mysql2/promise'
import { freshDatabase, testDatabaseUrl } from './helpers.js'

// The rules the database holds by itself (DATABASE_DESIGN.md §4): each test
// tries a write the rules forbid and expects MySQL to refuse it by the
// constraint's name. A service bug or a race can then never store it.
//
// test/prove-schema.ts runs this file once per constraint with that one
// constraint removed (SCHEMA_DROP), and expects it to fail every time.

const url = testDatabaseUrl()
let db: mysql.Connection
let counter = 0

before(async () => {
  await freshDatabase(url)
  db = await mysql.createConnection({ uri: url, timezone: 'Z' })
  await db.query("SET time_zone = '+00:00'")
  const drop = process.env.SCHEMA_DROP
  if (drop) await dropConstraint(drop)
})
after(async () => {
  await db.end()
})

async function dropConstraint(name: string): Promise<void> {
  const [rows] = await db.query<mysql.RowDataPacket[]>(
    `SELECT TABLE_NAME AS tableName, CONSTRAINT_TYPE AS type FROM information_schema.TABLE_CONSTRAINTS
     WHERE TABLE_SCHEMA = DATABASE() AND CONSTRAINT_NAME = ?`,
    [name],
  )
  const found = rows[0]
  if (!found) throw new Error(`No constraint named ${name}`)
  const how = found.type === 'CHECK' ? 'DROP CHECK' : 'DROP INDEX'
  await db.query(`ALTER TABLE \`${found.tableName}\` ${how} \`${name}\``)
}

type Row = Record<string, unknown>

async function insert(table: string, row: Row): Promise<number> {
  const [result] = await db.query<mysql.ResultSetHeader>(`INSERT INTO \`${table}\` SET ?`, [row])
  return result.insertId
}

/** MySQL refused the write because of [constraint]. */
function refusedBy(constraint: string) {
  return (error: unknown) => {
    const { errno, message } = error as { errno?: number; message?: string }
    assert.ok(errno === 3819 || errno === 1062, `expected a check or unique refusal, got ${errno}: ${message}`)
    assert.match(message ?? '', new RegExp(constraint))
    return true
  }
}

function nextPhone(): string {
  counter += 1
  return `+96477${String(counter).padStart(8, '0')}`
}

async function customer(over: Row = {}): Promise<number> {
  return insert('users', { role: 'CUSTOMER', full_name: 'Test Shopper', phone: nextPhone(), ...over })
}

async function store(over: Row = {}): Promise<number> {
  const owner = await insert('users', { role: 'MERCHANT', full_name: 'Test Owner', phone: nextPhone() })
  counter += 1
  return insert('stores', {
    owner_user_id: owner,
    store_name: `Store ${counter}`,
    name_key: `store ${counter}`,
    submitted_at: new Date(),
    governorate: 'BAGHDAD',
    ...over,
  })
}

async function product(storeId: number, over: Row = {}): Promise<number> {
  return insert('products', { store_id: storeId, category_id: 8, name_ar: 'هاتف تجريبي', base_price: 100_000, ...over })
}

async function sku(productId: number, over: Row = {}): Promise<number> {
  return insert('product_skus', { product_id: productId, stock: 3, ...over })
}

const ORDER: Row = {
  subtotal: 100_000,
  discount: 0,
  shipping: 3_000,
  total: 103_000,
  item_count: 1,
  customer_name: 'Test Shopper',
  customer_phone: '+9647700000001',
  ship_governorate: 'BAGHDAD',
  ship_area: 'Karrada',
  ship_landmark: 'Near the park',
  placed_at: new Date(),
  search_text: '',
}

async function order(over: Row = {}): Promise<number> {
  return insert('orders', { customer_id: await customer(), ...ORDER, ...over })
}

const PART: Row = { subtotal: 100_000, discount: 0, shipping_fee: 3_000, amount_due: 103_000, item_count: 1, delivery_time: '1_2_DAYS' }

async function part(over: Row = {}) {
  const storeId = await store()
  const orderId = await order()
  const partId = await insert('order_store_parts', { order_id: orderId, store_id: storeId, ...PART, ...over })
  return { storeId, orderId, partId }
}

async function item(over: Row = {}) {
  const { storeId, orderId, partId } = await part()
  const productId = await product(storeId)
  const skuId = await sku(productId)
  const itemId = await insert('order_items', {
    order_id: orderId,
    part_id: partId,
    product_id: productId,
    sku_id: skuId,
    product_name: 'Test phone',
    store_name: 'Test store',
    unit_price: 100_000,
    paid_unit_price: 100_000,
    quantity: 1,
    line_total: 100_000,
    ...over,
  })
  return { storeId, orderId, partId, itemId }
}

describe('accounts', () => {
  test('a phone number is an Iraqi mobile in E.164', async () => {
    await assert.rejects(customer({ phone: '07701234567' }), refusedBy('ck_users_phone'))
  })
  test('a live account always has its number', async () => {
    await assert.rejects(customer({ phone: null }), refusedBy('ck_users_live_phone'))
  })
  test('one account per number', async () => {
    const phone = nextPhone()
    await customer({ phone })
    await assert.rejects(customer({ phone }), refusedBy('uq_users_phone'))
  })
  test('deleted accounts free their numbers: two can have none', async () => {
    await customer({ status: 'DELETED', phone: null })
    await customer({ status: 'DELETED', phone: null })
  })
  test('a suspension keeps its reason', async () => {
    await assert.rejects(customer({ status: 'SUSPENDED' }), refusedBy('ck_users_suspension'))
  })
  test('codes are exact: a lowercase role is refused', async () => {
    await assert.rejects(customer({ role: 'customer' }), refusedBy('ck_users_role'))
  })
})

describe('stores', () => {
  test('two stores in one city cannot share a name; another city may', async () => {
    await store({ name_key: 'nova electronics', governorate: 'BAGHDAD' })
    await assert.rejects(store({ name_key: 'nova electronics', governorate: 'BAGHDAD' }), refusedBy('uq_stores_governorate_name_key'))
    await store({ name_key: 'nova electronics', governorate: 'BASRA' })
  })
  test('a delivery fee is in steps of 250 IQD', async () => {
    await assert.rejects(store({ fee_inside: 3100, time_inside: 'SAME_DAY' }), refusedBy('ck_stores_fee_inside'))
  })
  test('a fee always has its delivery time', async () => {
    await assert.rejects(store({ fee_inside: 3000 }), refusedBy('ck_stores_inside_pair'))
  })
  test('a rejection keeps its reason', async () => {
    await assert.rejects(store({ status: 'REJECTED' }), refusedBy('ck_stores_rejection'))
  })
  test('a deleted store (CLOSED) has its day, was asked for by its owner, and stays shut', async () => {
    const asked = new Date()
    await store({ status: 'CLOSED', closed_at: asked, deletion_requested_at: asked, is_open: 0 })
    await assert.rejects(store({ status: 'CLOSED', deletion_requested_at: asked, is_open: 0 }), refusedBy('ck_stores_closed'))
    await assert.rejects(store({ status: 'APPROVED', closed_at: asked, deletion_requested_at: asked, is_open: 0 }), refusedBy('ck_stores_closed'))
    await assert.rejects(store({ status: 'CLOSED', closed_at: asked, is_open: 0 }), refusedBy('ck_stores_closed'))
    await assert.rejects(store({ status: 'CLOSED', closed_at: asked, deletion_requested_at: asked }), refusedBy('ck_stores_closed'))
  })
})

describe('prices and stock', () => {
  test('a price is in steps of 250 IQD', async () => {
    await assert.rejects(product(await store(), { base_price: 100_100 }), refusedBy('ck_products_base_price'))
  })
  test('a price before a discount is above the price', async () => {
    await assert.rejects(product(await store(), { compare_at_price: 100_000 }), refusedBy('ck_products_compare_at'))
  })
  test('a flash sale is below the normal price', async () => {
    await assert.rejects(
      product(await store(), { sale_price: 100_000, sale_ends_at: new Date(Date.now() + 3_600_000) }),
      refusedBy('ck_products_sale_price'),
    )
  })
  test('a flash sale always has its end', async () => {
    await assert.rejects(product(await store(), { sale_price: 90_000 }), refusedBy('ck_products_sale_pair'))
  })
  test('stock can never go below zero, even by a subtraction', async () => {
    const skuId = await sku(await product(await store()), { stock: 3 })
    await assert.rejects(db.query('UPDATE product_skus SET stock = stock - 5 WHERE id = ?', [skuId]), refusedBy('ck_product_skus_stock'))
    const [rows] = await db.query<mysql.RowDataPacket[]>('SELECT stock FROM product_skus WHERE id = ?', [skuId])
    assert.equal(rows[0]?.stock, 3)
  })
  test('an option always has its own price', async () => {
    await assert.rejects(
      sku(await product(await store()), { options: JSON.stringify({ Color: 'Black' }), option_label: 'Black' }),
      refusedBy('ck_product_skus_options_price'),
    )
  })
})

describe('addresses', () => {
  test('one default address per shopper', async () => {
    const user = await customer()
    const address = { user_id: user, label: 'Home', full_name: 'Test', phone: '+9647700000001', governorate: 'BAGHDAD', area: 'Karrada', landmark: 'Park' }
    await insert('addresses', { ...address, is_default: 1 })
    await insert('addresses', { ...address, is_default: 0 })
    await insert('addresses', { ...address, is_default: 0 })
    await assert.rejects(insert('addresses', { ...address, is_default: 1 }), refusedBy('uq_addresses_default_for'))
  })
})

describe('coupons', () => {
  const coupon = async (over: Row) =>
    insert('coupons', { store_id: await store(), code: `C${++counter}`, discount_type: 'PERCENTAGE', value: 10, starts_at: new Date(), ...over })

  test('a code is upper-case letters and digits', async () => {
    await assert.rejects(coupon({ code: 'nova10' }), refusedBy('ck_coupons_code'))
  })
  test('a code exists once across Saba', async () => {
    await coupon({ code: 'ONCEONLY' })
    await assert.rejects(coupon({ code: 'ONCEONLY' }), refusedBy('uq_coupons_code'))
  })
  test('a percentage is at most 90', async () => {
    await assert.rejects(coupon({ value: 95 }), refusedBy('ck_coupons_percentage'))
  })
  test('a fixed amount is in steps of 250 IQD', async () => {
    await assert.rejects(coupon({ discount_type: 'FIXED', value: 5_100 }), refusedBy('ck_coupons_fixed'))
  })
  test('a coupon is never used more than its limit', async () => {
    const id = await coupon({ usage_limit: 1, used_count: 1 })
    await assert.rejects(db.query('UPDATE coupons SET used_count = used_count + 1 WHERE id = ?', [id]), refusedBy('ck_coupons_usage'))
  })
})

describe('orders and money', () => {
  test('an order adds up: total = subtotal − discount + shipping', async () => {
    await assert.rejects(order({ total: 100_000 }), refusedBy('ck_orders_total'))
  })
  test('an order is paid only when it is delivered', async () => {
    await assert.rejects(order({ payment_status: 'PAID' }), refusedBy('ck_orders_paid'))
  })
  test('an order nothing is coming for is not waiting for payment', async () => {
    await assert.rejects(order({ status: 'CANCELLED', cancelled_at: new Date() }), refusedBy('ck_orders_payment_cancelled'))
  })
  test('a store\'s part adds up: amount due = subtotal − discount + fee', async () => {
    await assert.rejects(part({ amount_due: 100_000 }), refusedBy('ck_order_store_parts_amount_due'))
  })
  test('a delivered part is on a bill month, and only a delivered one', async () => {
    await assert.rejects(
      part({ status: 'DELIVERED', delivered_at: new Date(), courier_name: 'Driver', courier_phone: '+9647700000002' }),
      refusedBy('ck_order_store_parts_billing_month'),
    )
    await assert.rejects(part({ billing_month: '2026-09-01' }), refusedBy('ck_order_store_parts_billing_month'))
  })
  test('a bill month is written as its first day', async () => {
    await assert.rejects(
      part({ status: 'DELIVERED', delivered_at: new Date(), billing_month: '2026-09-15', courier_name: 'Driver', courier_phone: '+9647700000002' }),
      refusedBy('ck_order_store_parts_billing_first_day'),
    )
  })
  test('a shipped part always has its driver', async () => {
    await assert.rejects(part({ status: 'SHIPPED' }), refusedBy('ck_order_store_parts_courier'))
  })
  test('a cancelled part always says why', async () => {
    await assert.rejects(part({ status: 'CANCELLED' }), refusedBy('ck_order_store_parts_cancellation'))
  })
  test('a line adds up: line total = unit price × quantity', async () => {
    await assert.rejects(item({ quantity: 2 }), refusedBy('ck_order_items_line_total'))
  })
  test('a line never gives back more than it cost', async () => {
    await assert.rejects(item({ paid_unit_price: 100_250 }), refusedBy('ck_order_items_paid_unit_price'))
  })
})

describe('returns and bills', () => {
  test('an order line takes one return', async () => {
    const { storeId, orderId, partId, itemId } = await item()
    const ret = { order_id: orderId, part_id: partId, store_id: storeId, customer_id: await customer(), reason: 'DAMAGED', refund_amount: 100_000, requested_at: new Date() }
    const first = await insert('returns', ret)
    await insert('return_items', { return_id: first, order_item_id: itemId, quantity: 1, refund_amount: 100_000 })
    const second = await insert('returns', ret)
    await assert.rejects(
      insert('return_items', { return_id: second, order_item_id: itemId, quantity: 1, refund_amount: 100_000 }),
      refusedBy('uq_return_items_order_item'),
    )
  })
  test('a refunded return is on a refund month', async () => {
    const { storeId, orderId, partId } = await item()
    await assert.rejects(
      insert('returns', {
        order_id: orderId, part_id: partId, store_id: storeId, customer_id: await customer(),
        reason: 'DAMAGED', refund_amount: 100_000, requested_at: new Date(), answered_at: new Date(),
        status: 'REFUNDED', refunded_at: new Date(),
      }),
      refusedBy('ck_returns_refund_month'),
    )
  })
  test('a month is marked paid once', async () => {
    const storeId = await store()
    const admin = await insert('users', { role: 'ADMIN', full_name: 'Admin', phone: nextPhone() })
    const payment = { store_id: storeId, month: '2026-08-01', paid_on: '2026-09-03', owed: 12_250, rate_percent: 8, recorded_by: admin }
    await insert('bill_payments', payment)
    await assert.rejects(insert('bill_payments', payment), refusedBy('uq_bill_payments_store_month'))
  })
  test('a month can\'t be paid before it has ended', async () => {
    const storeId = await store()
    const admin = await insert('users', { role: 'ADMIN', full_name: 'Admin', phone: nextPhone() })
    await assert.rejects(
      insert('bill_payments', { store_id: storeId, month: '2026-08-01', paid_on: '2026-08-31', owed: 12_250, rate_percent: 8, recorded_by: admin }),
      refusedBy('ck_bill_payments_paid_on'),
    )
  })
})

describe('notifications', () => {
  test('a notification always has its Arabic', async () => {
    await assert.rejects(
      insert('notifications', { user_id: await customer(), type: 'ORDER', title_en: 'Hello', title_ar: ' ', body_en: 'x', body_ar: 'x' }),
      refusedBy('ck_notifications_both_languages'),
    )
  })
})
