// The shown prices (DATABASE_DESIGN.md §3.3), against the demo's own numbers.
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { optionPrice, productPrice, saleIsOn, stockStatus } from '../src/lib/pricing.js'

const now = new Date('2026-09-26T12:00:00Z')
const later = new Date('2026-09-26T15:00:00Z')
const earlier = new Date('2026-09-26T11:59:59.999Z')

test('no sale, no markdown: the price alone', () => {
  const p = { base_price: 145_000, compare_at_price: null, sale_price: null, sale_ends_at: null }
  assert.deepEqual(productPrice(p, now), { price: 145_000, originalPrice: null, discountPercentage: null })
})

test('a lasting markdown shows the original beside the price', () => {
  const p = { base_price: 90_000, compare_at_price: 120_000, sale_price: null, sale_ends_at: null }
  assert.deepEqual(productPrice(p, now), { price: 90_000, originalPrice: 120_000, discountPercentage: 25 })
  // An option priced 100,000 carries the same 30,000 markdown.
  assert.deepEqual(optionPrice(p, 100_000, now), { price: 100_000, originalPrice: 130_000, discountPercentage: 23 })
})

test('during a flash sale: the sale price, the normal price as the original; each option down by the same amount', () => {
  const p = { base_price: 200_000, compare_at_price: 240_000, sale_price: 170_000, sale_ends_at: later }
  assert.equal(saleIsOn(p, now), true)
  assert.deepEqual(productPrice(p, now), { price: 170_000, originalPrice: 200_000, discountPercentage: 15 })
  assert.deepEqual(optionPrice(p, 250_000, now), { price: 220_000, originalPrice: 250_000, discountPercentage: 12 })
})

test('an ended sale is not a sale, to the millisecond', () => {
  const p = { base_price: 200_000, compare_at_price: null, sale_price: 170_000, sale_ends_at: earlier }
  assert.equal(saleIsOn(p, now), false)
  assert.deepEqual(productPrice(p, now), { price: 200_000, originalPrice: null, discountPercentage: null })
  assert.deepEqual(optionPrice(p, 250_000, now).price, 250_000)
  const exactly = { ...p, sale_ends_at: now }
  assert.equal(saleIsOn(exactly, now), false)
})

test('stock status: 0 out, 1–5 low, 6 in', () => {
  assert.deepEqual([0, 1, 5, 6].map(stockStatus), ['OUT_OF_STOCK', 'LOW_STOCK', 'LOW_STOCK', 'IN_STOCK'])
})
