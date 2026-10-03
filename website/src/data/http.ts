import { savedLang } from '@/lib/i18n'
import { ApiError, PER_PAGE, type ErrorCode } from './mock'
import type { PageAsk, Paged } from './types'

// The real server (BACKEND_PLAN.md §8.2). Every live data function calls
// `http`; the mock ones keep calling `reply`. The screens see the same
// ErrorCodes either way.

/** The real server, unless VITE_USE_MOCK is exactly "true": the demo build (`npm run dev:demo`, `build:demo`). */
export const USE_MOCK = import.meta.env.VITE_USE_MOCK === 'true'
/** localhost only while developing: a build without VITE_API_BASE_URL is refused (vite.config.ts). */
const BASE = import.meta.env.VITE_API_BASE_URL || (import.meta.env.DEV ? 'http://localhost:3000/api/v1' : '')

export interface Tokens {
  accessToken: string
  refreshToken: string
  expiresIn: number
}

// The access token lives in memory only (15 minutes). The refresh token is
// kept in localStorage (Q3, 12 hours), shared by every tab.
const REFRESH_KEY = 'saba-admin-refresh'
let accessToken: string | null = null
let refreshMemory: string | null = null // private mode, where localStorage throws

/** The refresh token as kept now: a renewal, here or in another tab, may have replaced it. */
export function savedRefresh(): string | null {
  try {
    return localStorage.getItem(REFRESH_KEY)
  } catch {
    return refreshMemory
  }
}

export function keepTokens(tokens: Tokens): void {
  accessToken = tokens.accessToken
  refreshMemory = tokens.refreshToken
  try {
    localStorage.setItem(REFRESH_KEY, tokens.refreshToken)
  } catch {
    // Private mode: kept for this page only.
  }
}

export function forgetTokens(): void {
  accessToken = null
  refreshMemory = null
  try {
    localStorage.removeItem(REFRESH_KEY)
  } catch {
    // Nothing kept, nothing to drop.
  }
}

type Method = 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE'

/** A query string of the filled fields only: an empty status or search is left out. */
export const searchOf = (query: Record<string, string | undefined>) =>
  new URLSearchParams(Object.entries(query).filter((entry): entry is [string, string] => !!entry[1])).toString()

/**
 * One request to the server; resolves to the envelope's `data`.
 * `signIn`: a sign-in call, sent with no token, never refreshed, and its
 * errors read as sign-in's (a 401 is a wrong login there, not an expired token).
 * `serverWords`: a refusal (409, or a 422 on a field) keeps the server's own
 * words, for those that name what the web can't know (which orders are still
 * open, how many products a category still has, which name is taken).
 */
export async function http<T>(method: Method, path: string, body?: unknown, options: { signIn?: boolean; serverWords?: boolean } = {}): Promise<T> {
  if (options.signIn) return read<T>(await send(method, path, body, null), true)
  return read<T>(await authed(method, path, body), false, options.serverWords)
}

/**
 * One page of an admin list (API_CONTRACT.md §1.3): the list's usual object,
 * with the server's `meta` beside the rows.
 */
export async function httpPage<R>(path: string, query: Record<string, string | undefined>, ask: PageAsk): Promise<Paged<R>> {
  const page = { page: String(ask.page), perPage: String(ask.perPage ?? PER_PAGE) }
  return read<Paged<R>>(await authed('GET', `${path}?${searchOf({ ...query, ...page })}`, undefined), false, false, true)
}

/**
 * The live-updates stream (GET /events): signed in like any call, then left
 * open for its caller to read. Throws when it can't be opened.
 */
export async function openStream(path: string, signal: AbortSignal): Promise<ReadableStream<Uint8Array>> {
  const res = await authed('GET', path, undefined, signal)
  if (!res.ok || !res.body) throw new ApiError(res.status >= 500 ? 'NETWORK' : 'UNEXPECTED')
  return res.body
}

/** A signed-in request: a 401 renews once and asks again; a failed renewal is the end of the sign-in. */
async function authed(method: Method, path: string, body: unknown, signal?: AbortSignal): Promise<Response> {
  // After a reload only the refresh token is left: renew before the first call.
  if (!accessToken && !(await renew())) return sessionOver()
  const sent = accessToken
  let res = await send(method, path, body, sent, signal)
  if (res.status === 401) {
    // Another call may have renewed while this one was out: then just retry.
    if (accessToken === sent && !(await renew())) return sessionOver()
    res = await send(method, path, body, accessToken, signal)
    if (res.status === 401) return sessionOver()
  }
  return res
}

async function send(method: Method, path: string, body: unknown, token: string | null, signal?: AbortSignal): Promise<Response> {
  try {
    return await fetch(BASE + path, {
      method,
      signal,
      headers: {
        // A file goes as a form, its type and boundary set by the browser.
        ...(body !== undefined && !(body instanceof FormData) && { 'Content-Type': 'application/json' }),
        // The server's words (the few the web shows) come in the admin's language.
        'Accept-Language': savedLang(),
        ...(token && { Authorization: `Bearer ${token}` }),
      },
      body: body === undefined || body instanceof FormData ? body : JSON.stringify(body),
    })
  } catch {
    throw new ApiError('NETWORK')
  }
}

interface ErrorBody {
  success: false
  code?: string
  message: string
  errors?: Record<string, string>
}

async function read<T>(res: Response, signIn: boolean, serverWords = false, withMeta = false): Promise<T> {
  const body = (await res.json().catch(() => null)) as { success: true; data: T; meta?: unknown } | ErrorBody | null
  if (res.ok && body?.success) return withMeta ? ({ ...body.data, meta: body.meta } as T) : body.data
  const retryAfter = Number(res.headers.get('Retry-After')) || undefined
  const error = body as ErrorBody | null
  const detail = serverWords && (res.status === 409 || res.status === 422) ? (Object.values(error?.errors ?? {})[0] ?? error?.message) : undefined
  throw new ApiError(codeOf(res.status, error?.errors ?? {}, signIn), retryAfter, detail)
}

/** A 422's field, as the contract names it (§1.4). */
const FIELD_CODES: Record<string, ErrorCode> = {
  reason: 'REASON_REQUIRED',
  nameAr: 'ARABIC_NAME_REQUIRED',
  paidAt: 'BAD_DATE',
  body: 'MESSAGE_REQUIRED',
}

function codeOf(status: number, errors: Record<string, string>, signIn: boolean): ErrorCode {
  if (status === 429) return 'TOO_MANY_TRIES'
  if (signIn) {
    // An unknown number is a 422 on `phone`: still just "wrong login" (§2.1 row 2).
    if (status === 401 || (status === 422 && errors.phone !== undefined)) return 'WRONG_LOGIN'
    if (status === 403) return 'SUSPENDED'
  }
  if (status >= 500) return 'NETWORK'
  if (status === 403) return 'ADMINS_ONLY'
  if (status === 404) return 'NOT_FOUND'
  if (status === 409) return 'WRONG_STATE'
  if (status === 422) {
    const field = Object.keys(errors).find((key) => key in FIELD_CODES)
    if (field) return FIELD_CODES[field]
  }
  return 'UNEXPECTED'
}

let renewing: Promise<boolean> | null = null

/**
 * A new token pair for the kept refresh token: false when the server says the
 * sign-in is over. One at a time, in this tab and across tabs: the server
 * swaps the refresh token on every use, and an old one used again ends the
 * whole sign-in. So calls that hit 401 together wait for the same renewal,
 * and each renewal reads the token another tab may have just replaced.
 */
function renew(): Promise<boolean> {
  renewing ??= oneAtATime(async () => {
    const refreshToken = savedRefresh()
    if (!refreshToken) return false
    const res = await send('POST', '/auth/refresh', { refreshToken }, null)
    if (res.status >= 500) throw new ApiError('NETWORK')
    if (!res.ok) return false
    keepTokens(await read<Tokens>(res, false))
    return true
  }).finally(() => {
    renewing = null
  })
  return renewing
}

/** Across tabs with Web Locks; only this tab where they're missing (plain http off localhost). */
function oneAtATime<T>(task: () => Promise<T>): Promise<T> {
  return navigator.locks ? navigator.locks.request('saba-admin-refresh', task) : task()
}

/** The sign-in has ended: nothing kept, and back to sign-in. */
function sessionOver(): never {
  forgetTokens()
  // Once the app is on screen. While the page loads (restoreSession), nothing
  // is drawn yet, and the router sends a signed-out admin to sign-in itself;
  // a reload as well would load sign-in twice.
  const started = !!document.getElementById('root')?.hasChildNodes()
  if (started && window.location.pathname !== '/login') window.location.replace('/login')
  throw new ApiError('NETWORK')
}
