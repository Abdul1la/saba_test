import { jwtVerify, SignJWT } from 'jose'
import { ACCESS_TOKEN_SECONDS, VERIFICATION_TOKEN_SECONDS } from '../rules.js'

// Two kinds of signed token, told apart by `typ` so one can never pass as the
// other: the access token (who is calling) and the proof that a phone passed
// its SMS check (what sign-up needs).

export type Role = 'CUSTOMER' | 'MERCHANT' | 'ADMIN'

export interface Tokens {
  /** An access token of [user]'s sign-in [session] (its refresh tokens' family). */
  signAccess(user: { id: number; role: Role }, session: Buffer): Promise<string>
  /**
   * The account id and its sign-in, or null for anything not a live access
   * token of ours. Whether that sign-in has ended is the caller's to check.
   */
  verifyAccess(token: string): Promise<{ id: number; session: Buffer } | null>
  signPhoneProof(challengeId: number, phone: string): Promise<string>
  verifyPhoneProof(token: string): Promise<{ challengeId: number; phone: string } | null>
}

export function createTokens(secret: string): Tokens {
  const key = new TextEncoder().encode(secret)

  const sign = (claims: Record<string, unknown>, subject: string, seconds: number) =>
    new SignJWT(claims)
      .setProtectedHeader({ alg: 'HS256' })
      .setSubject(subject)
      .setIssuedAt()
      .setExpirationTime(`${seconds}s`)
      .sign(key)

  const verify = async (token: string, typ: string) => {
    try {
      const { payload } = await jwtVerify(token, key, { algorithms: ['HS256'] })
      return payload.typ === typ ? payload : null
    } catch {
      return null
    }
  }

  const idOf = (subject: unknown) =>
    typeof subject === 'string' && /^\d{1,15}$/.test(subject) ? Number(subject) : null

  return {
    signAccess: (user, session) =>
      sign({ typ: 'access', role: user.role, sid: session.toString('base64url') }, String(user.id), ACCESS_TOKEN_SECONDS),
    async verifyAccess(token) {
      const payload = await verify(token, 'access')
      const id = idOf(payload?.sub)
      // A family id is 16 bytes: 22 characters. A token without one (made before sign-ins were carried) is refused.
      const sid = payload?.sid
      if (id === null || typeof sid !== 'string' || !/^[A-Za-z0-9_-]{22}$/.test(sid)) return null
      return { id, session: Buffer.from(sid, 'base64url') }
    },
    signPhoneProof: (challengeId, phone) =>
      sign({ typ: 'phone', phone }, String(challengeId), VERIFICATION_TOKEN_SECONDS),
    async verifyPhoneProof(token) {
      const payload = await verify(token, 'phone')
      const challengeId = idOf(payload?.sub)
      if (!payload || challengeId === null || typeof payload.phone !== 'string') return null
      return { challengeId, phone: payload.phone }
    },
  }
}
