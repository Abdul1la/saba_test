import type { Request } from 'express'
import type { Pool } from '../db/pool.js'
import { one } from '../db/sql.js'
import type { Role, Tokens } from '../lib/tokens.js'
import { AppError } from './errors.js'

export interface SessionUser {
  id: number
  role: Role
}

declare global {
  namespace Express {
    interface Request {
      /** The signed-in account; set on every route that isn't public. */
      user?: SessionUser
    }
  }
}

/** Who may call a route: anyone, any signed-in account, or only these roles. */
export type Who = 'public' | 'signedIn' | readonly Role[]

/**
 * The active account behind the request's Bearer token, or null. Read on
 * every request (BACKEND_PLAN.md §5.1), with the token's sign-in: a suspended
 * or deleted account, or a sign-in that has ended (signed out, suspended,
 * password reset), is out at its next request, not when its token runs out
 * 15 minutes later.
 */
async function liveAccount(pool: Pool, tokens: Tokens, req: Request): Promise<SessionUser | null> {
  const token = /^Bearer\s+(\S+)$/i.exec(req.headers.authorization ?? '')?.[1]
  const claims = token ? await tokens.verifyAccess(token) : null
  if (claims === null) return null
  const account = await one<{ role: Role; status: string }>(
    pool,
    `SELECT u.role, u.status FROM users u
      WHERE u.id = ? AND EXISTS (SELECT 1 FROM refresh_tokens r
        WHERE r.family_id = ? AND r.user_id = u.id AND r.revoked_at IS NULL AND r.expires_at > NOW(3))`,
    [claims.id, claims.session],
  )
  return account?.status === 'ACTIVE' ? { id: claims.id, role: account.role } : null
}

export function authenticator(pool: Pool, tokens: Tokens) {
  return async (req: Request, who: Exclude<Who, 'public'>): Promise<void> => {
    const account = await liveAccount(pool, tokens, req)
    if (!account) throw new AppError(401, 'AUTHENTICATION_ERROR', 'error.signInAgain')
    if (who !== 'signedIn' && !who.includes(account.role)) {
      throw new AppError(403, 'AUTHORIZATION_ERROR', 'error.forbidden')
    }
    req.user = account
  }
}

/**
 * Who is calling a public route, when it matters (a shopper's wishlist hearts,
 * a store's own product, an admin's untranslated names): the live account
 * behind a valid token, or null. A bad token is simply a stranger here.
 */
export function identifier(pool: Pool, tokens: Tokens) {
  return (req: Request): Promise<SessionUser | null> => liveAccount(pool, tokens, req)
}

/** The signed-in account of a route that isn't public. */
export function me(req: Request): SessionUser {
  if (!req.user) throw new AppError(401, 'AUTHENTICATION_ERROR', 'error.signInAgain')
  return req.user
}
