import { z } from 'zod'
import type { Connection, Pool } from '../db/pool.js'
import { Page } from '../http/route.js'
import { fold } from '../lib/fold.js'
import { governorateNames } from '../lib/governorates.js'
import { westernDigits } from '../lib/phone.js'

// Saba's lists, searched, counted and paged in the database (the reviewer's
// item 7: at 50,000 orders, reading every row on every page load took seconds
// and megabytes). Always one page: page 1 when none is asked (the web pages
// every list since 2026-09-30, contract §1.3).

export const ListQuery = {
  page: z.coerce.number().int().min(1).default(1),
  perPage: z.coerce.number().int().min(1).max(100).default(50),
}
type Paging = { page?: number | undefined; perPage: number }

/** " LIMIT … OFFSET …" for the asked page; nothing when no page was asked. */
export function pageSql(query: Paging): string {
  return query.page === undefined ? '' : ` LIMIT ${query.perPage} OFFSET ${(query.page - 1) * query.perPage}`
}

/** [data] as it goes out: with the page's meta (page, perPage, total) when a page was asked. */
export function paged<T>(data: T, query: Paging, total: number): T | Page<T> {
  return query.page === undefined ? data : new Page(data, { page: query.page, perPage: query.perPage }, total)
}

const escaped = (text: string) => text.replace(/[\\%_]/g, (c) => `\\${c}`)
/** A LIKE pattern for [text] folded as the search_text columns are: the whole phrase, anywhere. */
export const likeFolded = (text: string) => `%${escaped(fold(text))}%`
/** A LIKE pattern for a column kept as typed (its collation ignores case and accents). */
export const likeTyped = (text: string) => `%${escaped(text.trim())}%`

/**
 * SQL matching a number by its part after +964 ([national]) however it was
 * typed: 7801234567, 07801234567 or 9647801234567, once 4 digits are typed
 * (contract §1.7). Typed digits are never reshaped: a leading 0 stripped would turn
 * the last four digits 0017 into 017. Null when it can't be a number.
 */
export function phoneWhere(national: string, query: string): [string, unknown[]] | null {
  const typed = westernDigits(query).replace(/[\s()+-]/g, '').replace(/^00964/, '964')
  if (!/^\d{4,}$/.test(typed)) return null
  const like = `%${typed}%`
  return [`(${national} LIKE ? OR CONCAT('0', ${national}) LIKE ? OR CONCAT('964', ${national}) LIKE ?)`, [like, like, like]]
}

/** SQL matching a governorate column whose name, in either language, holds [q] folded. Null when none does. */
export async function cityWhere(db: Pool | Connection, column: string, q: string): Promise<[string, unknown[]] | null> {
  const folded = fold(q)
  const names = await governorateNames(db)
  const codes = [...names].filter(([, byLang]) => Object.values(byLang).some((name) => fold(name).includes(folded))).map(([code]) => code)
  return codes.length ? [`${column} IN (?)`, [codes]] : null
}

/** " AND (a OR b …)": the search box matches when any of [parts] does. Nothing for an empty box. */
export function anyOf(q: string, parts: ([string, unknown[]] | null)[]): [string, unknown[]] {
  if (!fold(q)) return ['', []]
  const found = parts.filter((part): part is [string, unknown[]] => part !== null)
  return [` AND (${found.map(([sql]) => sql).join(' OR ')})`, found.flatMap(([, params]) => params)]
}
