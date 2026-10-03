// The stand-in for the network. Every data function awaits `reply`, so the
// screens see the latency and failures a real server has. Replacing the mock
// means replacing the bodies in src/data/*.ts; nothing above them changes.

import type { PageAsk, PageMeta } from './types'

/** A code, not a sentence: the screens say it in the admin's language. */
export type ErrorCode =
  | 'NETWORK'
  | 'NOT_FOUND'
  | 'WRONG_STATE'
  | 'REASON_REQUIRED'
  | 'ARABIC_NAME_REQUIRED'
  | 'ADMINS_ONLY'
  | 'BAD_DATE'
  | 'MESSAGE_REQUIRED'
  | 'WRONG_LOGIN'
  | 'SUSPENDED'
  | 'TOO_MANY_TRIES'
  | 'UNEXPECTED'

export class ApiError extends Error {
  readonly code: ErrorCode
  /** With TOO_MANY_TRIES: the seconds to wait, when the server's Retry-After can be read. */
  readonly retryAfter?: number
  /** The server's own words, kept only where they name what the web can't know (which orders are still open). */
  readonly detail?: string
  constructor(code: ErrorCode, retryAfter?: number, detail?: string) {
    super(code)
    this.code = code
    this.retryAfter = retryAfter
    this.detail = detail
  }
}

/** A short wait, then a copy of the answer so no screen can edit the "server". */
export async function reply<T>(answer: () => T): Promise<T> {
  await new Promise((done) => setTimeout(done, 350 + Math.random() * 350))
  // Open any page with ?mockError to see its error state.
  if (new URLSearchParams(window.location.search).has('mockError')) {
    throw new ApiError('NETWORK')
  }
  return structuredClone(answer())
}

/** A reason is required: blank or spaces-only is refused, as a server would. */
export function requireReason(reason: string): string {
  const trimmed = reason.trim()
  if (!trimmed) throw new ApiError('REASON_REQUIRED')
  return trimmed
}

export function daysAgo(days: number, hours = 0): string {
  return new Date(Date.now() - (days * 24 + hours) * 3_600_000).toISOString()
}

/** Case- and accent-insensitive "contains", good enough for Arabic and English. */
export function matches(query: string, ...fields: (string | undefined)[]): boolean {
  const q = fold(query)
  return !q || fields.some((field) => field !== undefined && fold(field).includes(q))
}

// ponytail: folds the common Arabic letter variants only; the mobile app's
// full search folding (core/utils) belongs on the server.
function fold(text: string): string {
  return text
    .toLowerCase()
    .trim()
    .replace(/[أإآ]/g, 'ا')
    .replace(/ة/g, 'ه')
    .replace(/ى/g, 'ي')
    .replace(/[ً-ْ]/g, '')
}

/** Rows a list page holds (API_CONTRACT.md §1.3). */
export const PER_PAGE = 50

/** One page of the rows, cut as the server cuts it (§1.3). */
export function pageOf<T>(rows: T[], ask: PageAsk): { items: T[]; meta: PageMeta } {
  const perPage = ask.perPage ?? PER_PAGE
  return {
    items: rows.slice((ask.page - 1) * perPage, ask.page * perPage),
    meta: { page: ask.page, perPage, total: rows.length, totalPages: Math.ceil(rows.length / perPage) },
  }
}

export function countBy<T, S extends string>(
  items: T[],
  keysOf: (item: T) => S[],
): Partial<Record<S, number>> & { all: number } {
  const counts: Record<string, number> = {}
  for (const item of items) {
    for (const key of keysOf(item)) counts[key] = (counts[key] ?? 0) + 1
  }
  return { ...counts, all: items.length } as Partial<Record<S, number>> & { all: number }
}
