import { forgetTokens, http, keepTokens, savedRefresh, USE_MOCK, type Tokens } from './http'
import { ApiError, reply } from './mock'
import type { Admin } from './types'

// Sign-in. The mock does it as the app's demo does: the admin account signs
// in with its email or phone, and the password is not checked. The live
// version asks the server (BACKEND_PLAN.md §8.2, W1).

/** POST /auth/login */
export const signIn: (login: string, password: string) => Promise<Admin> = USE_MOCK ? mockSignIn : liveSignIn
/** POST /auth/logout, then nothing kept, even if the call fails. */
export const signOut: () => Promise<void> = USE_MOCK ? mockSignOut : liveSignOut

/** The signed-in admin, or null. */
export function currentAdmin(): Admin | null {
  return USE_MOCK ? mockAdmin() : liveAdmin
}

// ------------------------------------------------------------------ live ---

/** The fields of the server's `User` the web reads. */
interface User {
  id: string
  fullName: string
  email: string | null
  phone: string | null
  role: 'CUSTOMER' | 'MERCHANT' | 'ADMIN'
}

let liveAdmin: Admin | null = null

const toAdmin = (user: User): Admin => ({
  id: user.id,
  fullName: user.fullName,
  email: user.email ?? '',
  phone: user.phone ?? '',
})

async function liveSignIn(login: string, password: string): Promise<Admin> {
  const text = login.trim()
  // The server reads any Iraqi form of a number: 0770…, +964 770…, 964770….
  const body = text.includes('@') ? { email: text, password } : { phone: text, password }
  const { user, ...tokens } = await http<Tokens & { user: User }>('POST', '/auth/login', body, { signIn: true })
  keepTokens(tokens)
  // Any role may sign in on the server (D1); the web takes admins only.
  if (user.role !== 'ADMIN') {
    await liveSignOut()
    throw new ApiError('ADMINS_ONLY')
  }
  liveAdmin = toAdmin(user)
  return liveAdmin
}

async function liveSignOut(): Promise<void> {
  try {
    const refreshToken = savedRefresh()
    if (refreshToken) await http('POST', '/auth/logout', { refreshToken })
  } catch {
    // Signed out here all the same.
  } finally {
    liveAdmin = null
    forgetTokens()
  }
}

/**
 * On page load: who is signed in, from the kept refresh token. Signed out if
 * the account is not an admin or the sign-in has ended. With no answer, it
 * stays signed out for this load and the token is tried again on the next.
 */
export async function restoreSession(): Promise<void> {
  if (USE_MOCK || !savedRefresh()) return
  try {
    const user = await http<User>('GET', '/customers/me')
    if (user.role === 'ADMIN') liveAdmin = toAdmin(user)
    else await liveSignOut()
  } catch {
    // No answer, or the sign-in ended (http has forgotten it).
  }
}

// ------------------------------------------------------------------ mock ---

const ADMIN: Admin = {
  id: 'u-admin',
  fullName: 'Saba admin',
  email: 'admin@saba.app',
  phone: '+9647709999999',
}

const SESSION_KEY = 'saba-admin-session'

/** "0770 999 9999", "964770...", "+964 770..." all become "+9647709999999". */
function normalise(login: string): string {
  const text = login.trim().toLowerCase()
  if (text.includes('@')) return text
  const digits = text.replace(/\D/g, '')
  if (digits.startsWith('964')) return `+${digits}`
  if (digits.startsWith('0')) return `+964${digits.slice(1)}`
  return digits
}

function mockSignIn(login: string, _password: string): Promise<Admin> {
  return reply(() => {
    const who = normalise(login)
    if (who !== ADMIN.email && who !== ADMIN.phone) throw new ApiError('ADMINS_ONLY')
    try {
      localStorage.setItem(SESSION_KEY, JSON.stringify(ADMIN))
    } catch {
      // Private mode: signed in for this page only.
    }
    return ADMIN
  })
}

async function mockSignOut(): Promise<void> {
  try {
    localStorage.removeItem(SESSION_KEY)
  } catch {
    // Nothing kept, nothing to drop.
  }
}

function mockAdmin(): Admin | null {
  try {
    const saved = localStorage.getItem(SESSION_KEY)
    return saved ? (JSON.parse(saved) as Admin) : null
  } catch {
    return null
  }
}
