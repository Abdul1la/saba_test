import type { Lang } from './i18n'

// As the app formats (core/utils/formatters.dart): Western digits in both
// languages, and the currency mark after the number, "250,000 IQD" and
// "250,000 د.ع".

const digits = new Intl.NumberFormat('en', { maximumFractionDigits: 0 })

export const number = (value: number) => digits.format(value)

export const money = (amount: number, lang: Lang) => `${digits.format(amount)} ${lang === 'ar' ? 'د.ع' : 'IQD'}`

const locale = (lang: Lang) => (lang === 'ar' ? 'ar-IQ-u-nu-latn' : 'en-GB')

export const date = (iso: string, lang: Lang) =>
  new Intl.DateTimeFormat(locale(lang), { day: 'numeric', month: 'short', year: 'numeric' }).format(new Date(iso))

export const dateTime = (iso: string, lang: Lang) =>
  new Intl.DateTimeFormat(locale(lang), {
    day: 'numeric',
    month: 'short',
    // English reads the 24-hour clock, "00:19"; Arabic the 12-hour one, "8:39 ص".
    hour: lang === 'ar' ? 'numeric' : '2-digit',
    minute: '2-digit',
  }).format(new Date(iso))

/** "2026-08" -> "August 2026", "آب 2026". */
export const monthName = (month: string, lang: Lang) =>
  new Intl.DateTimeFormat(locale(lang), { month: 'long', year: 'numeric' }).format(new Date(`${month}-15T12:00:00`))

/** A day as a date field holds it, "2026-09-24", in local time. */
export const dayValue = (at: Date) =>
  `${at.getFullYear()}-${String(at.getMonth() + 1).padStart(2, '0')}-${String(at.getDate()).padStart(2, '0')}`

/** "3 days ago", "قبل 5 ساعات". */
export function ago(iso: string, lang: Lang): string {
  const minutes = Math.round((Date.now() - new Date(iso).getTime()) / 60_000)
  const rtf = new Intl.RelativeTimeFormat(lang === 'ar' ? 'ar-u-nu-latn' : 'en', { numeric: 'auto' })
  if (minutes < 60) return rtf.format(-Math.max(minutes, 1), 'minute')
  if (minutes < 60 * 24) return rtf.format(-Math.round(minutes / 60), 'hour')
  return rtf.format(-Math.floor(minutes / (60 * 24)), 'day')
}

/** Waiting more than two days is late: shown in the warning colour. */
export const isLate = (iso: string) => Date.now() - new Date(iso).getTime() > 2 * 24 * 3_600_000

/** "+9647711234567" -> "+964 771 123 4567". */
export function phone(value: string): string {
  const match = /^\+964(\d{3})(\d{3})(\d{4})$/.exec(value)
  return match ? `+964 ${match[1]} ${match[2]} ${match[3]}` : value
}

export function initials(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean)
  if (parts.length === 0) return '?'
  const first = [...parts[0]][0] ?? ''
  const last = parts.length > 1 ? ([...parts[parts.length - 1]][0] ?? '') : ''
  return (first + last).toUpperCase()
}
