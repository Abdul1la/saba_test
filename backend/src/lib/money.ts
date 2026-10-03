// The numbers of DATABASE_DESIGN.md §6, in whole IQD. Money never passes
// through a fraction: products go through BigInt, so a large order can't lose
// a dinar to floating point. Every result is a multiple of 250, the smallest note.
import { BAGHDAD_OFFSET } from '../rules.js'

/** [amount] down to a multiple of 250 (`_cashSteps`). */
export function cashSteps(amount: number): number {
  return Math.floor(amount / 250) * 250
}

/** What a coupon takes off [base], its store's buyable lines (`_buildCart`). */
export function couponDiscount(type: 'PERCENTAGE' | 'FIXED', value: number, base: number): number {
  if (base <= 0) return 0
  if (type === 'PERCENTAGE') return Number((BigInt(base) * BigInt(value)) / 25_000n) * 250
  return cashSteps(Math.min(value, base))
}

/**
 * What one unit really cost after its store's coupon, shared over the part's
 * lines by price and rounded down, so a store never hands back more than it
 * took (BUGS 161, 175). What a return gives back.
 */
export function paidUnitPrice(unit: number, partSubtotal: number, partDiscount: number): number {
  if (partSubtotal <= 0) return unit
  return Number((BigInt(unit) * BigInt(partSubtotal - partDiscount)) / (BigInt(partSubtotal) * 250n)) * 250
}

/**
 * What one month's bill owes Saba (§6, `_bill`): [ratePercent]% of its sales
 * less the cash handed back that month, to the nearest 250. Refunds as big as
 * the sales make it 0, and nothing carries over to another month (the user's
 * call, 2026-09-27).
 */
export function billOwed(sales: number, returned: number, ratePercent: number): number {
  const base = sales - returned
  if (base <= 0) return 0
  return Number((BigInt(base) * BigInt(ratePercent) + 12_500n) / 25_000n) * 250
}

/** [at]'s day on Iraq's calendar: "2026-09-27". */
export function baghdadDay(at: Date): string {
  return new Date(at.getTime() + Number(BAGHDAD_OFFSET.slice(0, 3)) * 3_600_000).toISOString().slice(0, 10)
}

/** The first day of [at]'s month on Iraq's calendar: which month's bill a sale or a refund is on (§3.5). */
export function billingMonth(at: Date): string {
  return `${baghdadDay(at).slice(0, 7)}-01`
}

/** The moment [day] ("2026-09-01") begins in Baghdad. */
export function dayStart(day: string): Date {
  return new Date(`${day}T00:00:00.000${BAGHDAD_OFFSET}`)
}

/** [day] moved [days] along the calendar. */
export function addDays(day: string, days: number): string {
  return new Date(Date.parse(`${day}T00:00:00.000Z`) + days * 86_400_000).toISOString().slice(0, 10)
}

/** The first day of the month [months] after [day]'s; before it, when negative. */
export function addMonths(day: string, months: number): string {
  const [year, month] = day.split('-').map(Number)
  return new Date(Date.UTC(year!, month! - 1 + months, 1)).toISOString().slice(0, 10)
}

/** 100000 as "100,000", in either language (Western digits, BUGS 28). */
export function grouped(amount: number): string {
  return amount.toLocaleString('en-US')
}
