// DATABASE_DESIGN.md §6, the arithmetic alone, against the demo's own numbers.
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { addDays, addMonths, billingMonth, billOwed, cashSteps, couponDiscount, dayStart, paidUnitPrice } from '../src/lib/money.js'

test('NOVA10 on 145,000 takes 14,500 off: 130,500 paid (the design example)', () => {
  assert.equal(couponDiscount('PERCENTAGE', 10, 145_000), 14_500)
  assert.equal(paidUnitPrice(145_000, 145_000, 14_500), 130_500)
})

test('a percentage rounds down to 250: 10% of 129,000 is 12,750, not 12,900', () => {
  assert.equal(couponDiscount('PERCENTAGE', 10, 129_000), 12_750)
  assert.equal(couponDiscount('PERCENTAGE', 15, 10_000), 1_500)
  assert.equal(couponDiscount('PERCENTAGE', 90, 250), 0)
})

test('a fixed amount never takes more than the base', () => {
  assert.equal(couponDiscount('FIXED', 5_000, 4_000), 4_000)
  assert.equal(couponDiscount('FIXED', 5_000, 20_000), 5_000)
  assert.equal(couponDiscount('FIXED', 5_000, 0), 0)
})

test("a store's coupon is shared over its lines by price, each unit rounded down (BUGS 161, 175)", () => {
  // 329,000 + 100,000 with 10% off: 42,750 off 429,000.
  const discount = couponDiscount('PERCENTAGE', 10, 429_000)
  assert.equal(discount, 42_750)
  assert.equal(paidUnitPrice(329_000, 429_000, discount), 296_000)
  assert.equal(paidUnitPrice(100_000, 429_000, discount), 90_000)
  // Rounded down, a store never hands back more than it took.
  assert.ok(296_000 + 90_000 <= 429_000 - discount)
  // No coupon: the price as sold.
  assert.equal(paidUnitPrice(95_000, 95_000, 0), 95_000)
  // Big numbers stay whole.
  assert.equal(paidUnitPrice(999_999_750, 1_999_999_500, 199_999_750), 899_999_750)
})

test('cash steps are the smallest note, 250', () => {
  assert.equal(cashSteps(130_565), 130_500)
  assert.equal(cashSteps(170_185), 170_000)
  assert.equal(cashSteps(250), 250)
})

test("a sale is on the bill of its month on Iraq's calendar: 22:00 UTC on 31 August is September", () => {
  assert.equal(billingMonth(new Date('2026-08-31T22:00:00.000Z')), '2026-09-01')
  assert.equal(billingMonth(new Date('2026-08-31T20:59:59.999Z')), '2026-08-01')
  assert.equal(billingMonth(new Date('2026-12-31T21:00:00.000Z')), '2027-01-01')
})

test("a month's bill is 8% of its sales less its refunds, to the nearest 250; refunds as big as the sales owe nothing", () => {
  assert.equal(billOwed(1_000_000, 0, 8), 80_000)
  // 11,600 is nearer 11,500 than 11,750; 10,440 is nearer 10,500 than 10,250.
  assert.equal(billOwed(145_000, 0, 8), 11_500)
  assert.equal(billOwed(130_500, 0, 8), 10_500)
  // 8% of 1,000,000 less 283,500 is 57,320: 57,250.
  assert.equal(billOwed(1_000_000, 283_500, 8), 57_250)
  assert.equal(billOwed(283_500, 283_500, 8), 0)
  // More handed back than sold: nothing, and nothing carried over.
  assert.equal(billOwed(145_000, 290_000, 8), 0)
  assert.equal(billOwed(0, 0, 8), 0)
  // Big numbers stay whole: 7,999,999,980 to the nearest 250.
  assert.equal(billOwed(99_999_999_750, 0, 8), 8_000_000_000)
})

test("Iraq's calendar: a day and a month begin at 21:00 UTC the evening before; months step across the year", () => {
  assert.equal(dayStart('2026-09-01').toISOString(), '2026-08-31T21:00:00.000Z')
  assert.equal(addDays('2026-09-01', -1), '2026-08-31')
  assert.equal(addDays('2026-12-28', 6), '2027-01-03')
  assert.equal(addMonths('2026-01-01', -1), '2025-12-01')
  assert.equal(addMonths('2026-09-27', 1), '2026-10-01')
  assert.equal(addMonths('2026-03-01', -5), '2025-10-01')
})
