import { createHash, createHmac, randomBytes, randomInt, timingSafeEqual } from 'node:crypto'
import type { Request } from 'express'
import { z } from 'zod'
import type { Context } from '../app.js'
import type { Connection, Pool } from '../db/pool.js'
import { duplicateKey, exec, one } from '../db/sql.js'
import { withTransaction } from '../db/tx.js'
import { me } from '../http/auth.js'
import { AppError, tooManyTries } from '../http/errors.js'
import { governorate, iraqiPhone, optionalEmail, optionalText, password, requiredText } from '../http/inputs.js'
import { route, type Api } from '../http/route.js'
import { parseInput } from '../http/validate.js'
import type { MessageKey } from '../lib/i18n.js'
import { hashPassword, verifyPassword } from '../lib/password.js'
import { publish } from '../lib/events.js'
import { SmsError } from '../lib/sms.js'
import { westernDigits } from '../lib/phone.js'
import type { Role } from '../lib/tokens.js'
import { ACCESS_TOKEN_SECONDS, NAME_MAX, OTP, REFRESH_TOKEN_SECONDS } from '../rules.js'
import { nameKey, storeSearchText } from './stores.js'
import { loadUser, User, userSearchText } from './users.js'

// Sign-in and sign-up (BACKEND_PLAN.md §6.1, DATABASE_DESIGN.md §3.1).

const TAG = 'Sign-in'

const Tokens = z.object({ accessToken: z.string(), refreshToken: z.string(), expiresIn: z.number() })

/** The app reads the user under `user` and the tokens beside it; the web reads data.user. */
const AuthPayload = Tokens.extend({ user: User }).meta({ id: 'AuthPayload' })

const Empty = z.object({})

const code = z.string().transform((value) => westernDigits(value).replace(/\s/g, ''))

export function authRoutes(api: Api, ctx: Context): void {
  const { pool } = ctx

  route(api, {
    method: 'post',
    path: '/auth/otp/send',
    tag: TAG,
    summary:
      'Send an SMS code to a number. With PHONE_VERIFICATION=off, a sign-up gets no SMS: its proof comes back at once (verificationToken), under the same limits',
    who: 'public',
    body: z.object({
      phone: iraqiPhone,
      // VERIFY_PHONE: the code an account never checked is asked for at sign-in (POST /auth/login with code).
      purpose: z.enum(['SIGN_UP', 'PASSWORD_RESET', 'VERIFY_PHONE', 'OTHER']).nullish(),
    }),
    response: z.object({ expiresInSeconds: z.number(), verificationToken: z.string().optional() }),
    async handle({ req, body }) {
      const { phone } = body
      const purpose = body.purpose ?? 'OTHER'
      const account = await one(pool, 'SELECT id FROM users WHERE phone = ?', [phone])
      if (purpose === 'SIGN_UP' && account) throw new AppError(409, 'CONFLICT_ERROR', 'auth.phoneTaken')
      if ((purpose === 'PASSWORD_RESET' || purpose === 'VERIFY_PHONE') && !account) {
        throw new AppError(422, 'VALIDATION_ERROR', 'auth.noAccount', undefined, { phone: { key: 'auth.noAccount' } })
      }

      // A number's own limits count the SMS it was sent; a sign-up let through without one sent none.
      const recent = await one<{ sent: number; since: number | null }>(
        pool,
        `SELECT COUNT(*) AS sent, TIMESTAMPDIFF(SECOND, MAX(created_at), NOW(3)) AS since
           FROM otp_challenges WHERE phone = ? AND purpose <> 'SIGN_UP_NO_CODE' AND created_at > NOW(3) - INTERVAL 1 HOUR`,
        [phone],
      )
      if (recent?.since != null && recent.since < OTP.resendSeconds) {
        const seconds = OTP.resendSeconds - recent.since
        throw tooManyTries(seconds, 'auth.codeWait', { seconds })
      }
      if ((recent?.sent ?? 0) >= OTP.perPhonePerHour) throw tooManyTries(3600, 'auth.tooManyCodes')
      const fromHere = await one<{ sent: number }>(
        pool,
        'SELECT COUNT(*) AS sent FROM otp_challenges WHERE ip = ? AND created_at > NOW(3) - INTERVAL 1 HOUR',
        [req.ip ?? ''],
      )
      if ((fromHere?.sent ?? 0) >= OTP.perIpPerHour) throw tooManyTries(3600, 'auth.tooManyCodes')

      // Sign-up without a code: no SMS, the proof at once, the account left unchecked. The same
      // limits as a code, so at most 20 sign-ups an hour from one address (the user's call).
      if (purpose === 'SIGN_UP' && ctx.config.phoneVerification === 'off') {
        const unchecked = await exec(
          pool,
          `INSERT INTO otp_challenges (phone, purpose, code_hash, expires_at, verified_at, ip)
           VALUES (?, 'SIGN_UP_NO_CODE', ?, NOW(3) + INTERVAL ? SECOND, NOW(3), ?)`,
          [phone, codeHash(ctx.config.otpSecret, phone, randomBytes(16).toString('hex')), OTP.validSeconds, req.ip ?? null],
        )
        return { expiresInSeconds: 0, verificationToken: await ctx.tokens.signPhoneProof(unchecked.insertId, phone) }
      }

      const sms = String(randomInt(0, 1_000_000)).padStart(6, '0')
      const challenge = await exec(
        pool,
        `INSERT INTO otp_challenges (phone, purpose, code_hash, expires_at, ip)
         VALUES (?, ?, ?, NOW(3) + INTERVAL ? SECOND, ?)`,
        [phone, purpose, codeHash(ctx.config.otpSecret, phone, sms), OTP.validSeconds, req.ip ?? null],
      )
      try {
        await ctx.sms(phone, sms)
      } catch (error) {
        // A code that never left isn't one: withdrawn, so neither the 60-second
        // wait nor the hourly count holds the shopper back from trying again.
        await exec(pool, 'DELETE FROM otp_challenges WHERE id = ?', [challenge.insertId])
        if (error instanceof SmsError && error.kind === 'rate-limited') throw tooManyTries(error.waitSeconds)
        if (!(error instanceof SmsError)) req.log.error({ err: error }, 'SMS sender failed')
        throw new AppError(503, 'EXTERNAL_SERVICE_ERROR', 'auth.smsFailed')
      }
      // The resend wait, as the app's timer reads it. Never the code (the demo's demoCode).
      return { expiresInSeconds: OTP.resendSeconds }
    },
  })

  route(api, {
    method: 'post',
    path: '/auth/otp/verify',
    tag: TAG,
    summary: 'Check an SMS code; returns the proof sign-up needs',
    who: 'public',
    body: z.object({ phone: iraqiPhone, code }),
    response: z.object({ verificationToken: z.string() }),
    async handle({ body }) {
      // Sign-up codes only: the code screen's resend asks for one too (app 077fe92).
      const check = await withTransaction(pool, async (conn) => {
        const result = await checkCode(conn, ctx.config.otpSecret, body.phone, ['SIGN_UP'], body.code)
        if (result.ok) {
          await exec(conn, 'UPDATE otp_challenges SET verified_at = COALESCE(verified_at, NOW(3)) WHERE id = ?', [
            result.id,
          ])
        }
        return result
      })
      // 400, as the demo answers a wrong code here (BACKEND_PLAN.md §5.4).
      if (!check.ok) throw codeError(400, check.key)
      return { verificationToken: await ctx.tokens.signPhoneProof(check.id, body.phone) }
    },
  })

  const registration = {
    fullName: requiredText(NAME_MAX.person),
    email: optionalEmail,
    password,
    phone: iraqiPhone,
    phoneVerificationToken: z.string().min(1, { error: 'auth.verifyFirst' }),
    governorate,
  }

  route(api, {
    method: 'post',
    path: '/auth/register/customer',
    tag: TAG,
    summary: 'Sign up as a shopper',
    who: 'public',
    body: z.object(registration),
    response: AuthPayload,
    handle: ({ req, body }) => register(ctx, req, 'CUSTOMER', body),
  })

  route(api, {
    method: 'post',
    path: '/auth/register/merchant',
    tag: TAG,
    summary: 'Sign up as a store owner; the store waits for Saba (PENDING)',
    who: 'public',
    body: z.object({
      ...registration,
      storeName: requiredText(NAME_MAX.store),
      businessType: optionalText(20),
      businessAddress: optionalText(200),
      businessDescription: optionalText(1000),
    }),
    response: AuthPayload,
    handle: ({ req, body }) =>
      register(ctx, req, 'MERCHANT', body, {
        storeName: body.storeName,
        businessType: body.businessType,
        businessAddress: body.businessAddress,
        description: body.businessDescription,
      }),
  })

  route(api, {
    method: 'post',
    path: '/auth/login',
    tag: TAG,
    summary:
      'Sign in with a phone number or an email, and a password (any role). With PHONE_VERIFICATION=on, an account never checked answers 403 PHONE_NOT_VERIFIED until it sends the VERIFY_PHONE code too',
    who: 'public',
    body: z.object({
      phone: z.string().nullish(),
      email: z.string().nullish(),
      password: z.string().min(1, { error: 'field.required' }),
      /** The VERIFY_PHONE code, when the server asked for one (403 PHONE_NOT_VERIFIED). */
      code: code.nullish(),
    }),
    response: AuthPayload,
    async handle({ req, body }) {
      const email = body.email?.trim().toLowerCase()
      const phone = body.phone?.trim() ? parseInput(z.object({ phone: iraqiPhone }), body).phone : null
      if (!phone && !email) {
        throw new AppError(422, 'VALIDATION_ERROR', 'error.validation', undefined, { phone: { key: 'field.required' } })
      }
      const login = phone ?? email!
      const wait = ctx.signInLimiter.take(`${req.ip}|${login}`)
      if (wait) throw tooManyTries(wait)

      const account = await one<{ id: number; role: Role; status: string; password_hash: string | null; phone: string | null; checked: number }>(
        pool,
        phone
          ? 'SELECT id, role, status, password_hash, phone, phone_verified_at IS NOT NULL AS checked FROM users WHERE phone = ?'
          : "SELECT id, role, status, password_hash, phone, phone_verified_at IS NOT NULL AS checked FROM users WHERE email = ? AND status <> 'DELETED'",
        [login],
      )
      // An unknown number is said on the phone field, as the app shows it (BUGS 107, 121).
      if (!account && phone) {
        throw new AppError(422, 'VALIDATION_ERROR', 'auth.noAccountSignUp', undefined, {
          phone: { key: 'auth.noAccountSignUp' },
        })
      }
      if (!account?.password_hash || !(await verifyPassword(body.password, account.password_hash))) {
        throw new AppError(401, 'AUTHENTICATION_ERROR', phone ? 'auth.wrongPassword' : 'auth.wrongLogin')
      }
      // Only after the password: a stranger doesn't learn an account is suspended.
      if (account.status !== 'ACTIVE') throw new AppError(403, 'AUTHORIZATION_ERROR', 'auth.suspended')
      // Never checked (signed up while codes were off), and codes are on again: its number first.
      if (mustCheckPhone(ctx, account)) {
        if (!body.code) throw new AppError(403, 'PHONE_NOT_VERIFIED', 'auth.checkPhone')
        const check = await withTransaction(pool, async (conn) => {
          const result = await checkCode(conn, ctx.config.otpSecret, account.phone!, ['VERIFY_PHONE'], body.code!)
          if (!result.ok) return result
          await exec(conn, 'UPDATE otp_challenges SET verified_at = NOW(3), consumed_at = NOW(3) WHERE id = ?', [result.id])
          await exec(conn, 'UPDATE users SET phone_verified_at = NOW(3) WHERE id = ?', [account.id])
          return result
        })
        if (!check.ok) throw codeError(422, check.key)
      }

      const session = await startSession(pool, ctx, req, account)
      return { user: await loadUser(pool, account.id, req, ctx), ...session.tokens }
    },
  })

  route(api, {
    method: 'post',
    path: '/auth/refresh',
    tag: TAG,
    summary: 'A new token pair for a refresh token; the old one stops working',
    who: 'public',
    body: z.object({ refreshToken: z.string().min(1) }),
    response: Tokens,
    async handle({ req, body }) {
      const tokens = await withTransaction(pool, async (conn) => {
        const row = await one<{
          id: number
          user_id: number
          family_id: Buffer
          revoked: number
          replaced_by_id: number | null
          live: number
        }>(
          conn,
          `SELECT id, user_id, family_id, revoked_at IS NOT NULL AS revoked, replaced_by_id,
                  expires_at > NOW(3) AS live
             FROM refresh_tokens WHERE token_hash = ? FOR UPDATE`,
          [sha256(body.refreshToken)],
        )
        if (!row) return null
        if (row.revoked) {
          // Used again after it was swapped for a new one: someone has a copy.
          // Everything from that sign-in stops working (DATABASE_DESIGN.md §3.1).
          if (row.replaced_by_id !== null) await revokeFamily(conn, row.family_id)
          return null
        }
        if (!row.live) return null
        const account = await one<{ role: Role; status: string; checked: number }>(
          conn,
          'SELECT role, status, phone_verified_at IS NOT NULL AS checked FROM users WHERE id = ?',
          [row.user_id],
        )
        if (account?.status !== 'ACTIVE') return null
        // Codes back on and this number never checked: signed out, so its next sign-in asks for one.
        if (mustCheckPhone(ctx, account)) return null
        const next = await startSession(conn, ctx, req, { id: row.user_id, role: account.role }, row.family_id)
        await exec(conn, 'UPDATE refresh_tokens SET revoked_at = NOW(3), replaced_by_id = ? WHERE id = ?', [
          next.tokenId,
          row.id,
        ])
        return next.tokens
      })
      if (!tokens) throw new AppError(401, 'AUTHENTICATION_ERROR', 'error.signInAgain')
      return tokens
    },
  })

  route(api, {
    method: 'post',
    path: '/auth/logout',
    tag: TAG,
    summary: 'Sign out: the refresh token, and every token from the same sign-in, stop working',
    who: 'signedIn',
    body: z.object({ refreshToken: z.string().min(1) }),
    response: Empty,
    async handle({ req, body }) {
      // The whole sign-in, not just this token: the app may have swapped it for
      // a new pair on the way here (a 401, then a refresh, then this request again).
      const row = await one<{ family_id: Buffer }>(
        pool,
        'SELECT family_id FROM refresh_tokens WHERE token_hash = ? AND user_id = ?',
        [sha256(body.refreshToken), me(req).id],
      )
      if (row) await revokeFamily(pool, row.family_id)
      return {}
    },
  })

  route(api, {
    method: 'post',
    path: '/auth/reset-password',
    tag: TAG,
    summary: 'A new password with the SMS code sent to the number; signs every device out',
    who: 'public',
    body: z.object({ phone: iraqiPhone, token: code, password }),
    response: Empty,
    async handle({ body }) {
      const account = await one<{ id: number }>(pool, 'SELECT id FROM users WHERE phone = ?', [body.phone])
      if (!account) {
        throw new AppError(422, 'VALIDATION_ERROR', 'auth.noAccount', undefined, { phone: { key: 'auth.noAccount' } })
      }
      const hash = await hashPassword(body.password)
      const check = await withTransaction(pool, async (conn) => {
        const result = await checkCode(conn, ctx.config.otpSecret, body.phone, ['PASSWORD_RESET'], body.token)
        if (!result.ok) return result
        await exec(conn, 'UPDATE otp_challenges SET verified_at = NOW(3), consumed_at = NOW(3) WHERE id = ?', [result.id])
        await exec(conn, 'UPDATE users SET password_hash = ? WHERE id = ?', [hash, account.id])
        await exec(conn, 'UPDATE refresh_tokens SET revoked_at = NOW(3) WHERE user_id = ? AND revoked_at IS NULL', [
          account.id,
        ])
        return result
      })
      // 422, as the demo answers a wrong code here.
      if (!check.ok) throw codeError(422, check.key)
      return {}
    },
  })
}

// ------------------------------------------------------------------ sign-up ---

interface Registration {
  fullName: string
  email: string | null
  password: string
  phone: string
  phoneVerificationToken: string
  governorate: string
}

interface NewStore {
  storeName: string
  businessType: string | null
  businessAddress: string | null
  description: string | null
}

async function register(ctx: Context, req: Request, role: Role, body: Registration, store?: NewStore) {
  // A made-up token fails the signature; one for another number fails here (BUGS 108, 168).
  const proof = await ctx.tokens.verifyPhoneProof(body.phoneVerificationToken)
  if (!proof || proof.phone !== body.phone) {
    throw new AppError(422, 'VALIDATION_ERROR', 'auth.verifyFirst', undefined, { phone: { key: 'auth.verifyFirst' } })
  }
  const hash = await hashPassword(body.password)

  return withTransaction(ctx.pool, async (conn) => {
    // One check, one account: 0 rows means this proof already made one.
    const used = await exec(
      conn,
      `UPDATE otp_challenges SET consumed_at = NOW(3)
        WHERE id = ? AND phone = ? AND verified_at IS NOT NULL AND consumed_at IS NULL`,
      [proof.challengeId, proof.phone],
    )
    if (used.affectedRows !== 1) {
      throw new AppError(422, 'VALIDATION_ERROR', 'auth.verificationUsed', undefined, {
        phone: { key: 'auth.verificationUsed' },
      })
    }
    // Proven by its code, or let through without one (PHONE_VERIFICATION=off): kept, so it can be asked later.
    const proven = (await one<{ purpose: string }>(conn, 'SELECT purpose FROM otp_challenges WHERE id = ?', [proof.challengeId]))!.purpose === 'SIGN_UP'

    let userId: number
    try {
      const inserted = await exec(
        conn,
        `INSERT INTO users (role, full_name, phone, email, password_hash, governorate, search_text, phone_verified_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, IF(?, NOW(3), NULL))`,
        // No email: v1 has no way to check one is its owner's, and an unchecked email could
        // take another person's (the reviewer's item 13). Shoppers and stores sign in by phone.
        [role, body.fullName, body.phone, null, hash, body.governorate, userSearchText(body.fullName), proven],
      )
      userId = inserted.insertId
    } catch (error) {
      const key = duplicateKey(error)
      if (key === 'uq_users_phone') {
        throw new AppError(409, 'CONFLICT_ERROR', 'auth.phoneTaken', undefined, { phone: { key: 'auth.phoneTaken' } })
      }
      throw error
    }

    if (store) {
      try {
        await exec(
          conn,
          `INSERT INTO stores (owner_user_id, store_name, name_key, submitted_at, governorate,
                               business_type, business_address, description, search_text)
           VALUES (?, ?, ?, NOW(3), ?, ?, ?, ?, ?)`,
          [
            userId,
            store.storeName,
            nameKey(store.storeName),
            body.governorate,
            store.businessType,
            store.businessAddress,
            store.description,
            storeSearchText(store.storeName, store.businessAddress),
          ],
        )
      } catch (error) {
        // Two stores in one city can't share a name; other cities may (BUGS 120).
        if (duplicateKey(error) === 'uq_stores_governorate_name_key') {
          throw new AppError(422, 'VALIDATION_ERROR', 'auth.storeNameTaken', undefined, {
            storeName: { key: 'auth.storeNameTaken' },
          })
        }
        throw error
      }
    }
    // A new store waits in Saba's queue; a new shopper is on its customer list.
    publish(conn, 'ADMINS', store ? 'stores' : 'customers', userId)

    const session = await startSession(conn, ctx, req, { id: userId, role })
    return { user: await loadUser(conn, userId, req, ctx), ...session.tokens }
  })
}

// ------------------------------------------------------------------ helpers ---

function sha256(text: string): Buffer {
  return createHash('sha256').update(text).digest()
}

/** HMAC, not a plain hash: six digits hashed plainly are reversed in a second. */
function codeHash(secret: string, phone: string, sms: string): Buffer {
  return createHmac('sha256', secret).update(`${phone}|${sms}`).digest()
}

type CodeCheck = { ok: true; id: number } | { ok: false; key: MessageKey }

/**
 * [sms] against the newest live code for [phone]. A wrong try is counted in
 * the caller's transaction, which commits either way; the fifth wrong try
 * uses the code up.
 */
async function checkCode(
  conn: Connection,
  secret: string,
  phone: string,
  purposes: string[],
  sms: string,
): Promise<CodeCheck> {
  const row = await one<{ id: number; code_hash: Buffer; attempts: number }>(
    conn,
    `SELECT id, code_hash, attempts FROM otp_challenges
      WHERE phone = ? AND purpose IN (?) AND consumed_at IS NULL AND expires_at > NOW(3)
      ORDER BY id DESC LIMIT 1 FOR UPDATE`,
    [phone, purposes],
  )
  if (!row) return { ok: false, key: 'auth.codeExpired' }
  if (row.attempts >= OTP.maxTries) return { ok: false, key: 'auth.codeTooManyTries' }
  if (timingSafeEqual(row.code_hash, codeHash(secret, phone, sms))) return { ok: true, id: row.id }
  await exec(conn, 'UPDATE otp_challenges SET attempts = attempts + 1 WHERE id = ?', [row.id])
  return { ok: false, key: row.attempts + 1 >= OTP.maxTries ? 'auth.codeTooManyTries' : 'auth.wrongCode' }
}

/** Codes are on (PHONE_VERIFICATION), and this shopper's or store's number was never checked. Admins never are. */
function mustCheckPhone(ctx: Context, account: { role: Role; checked: number }): boolean {
  return ctx.config.phoneVerification === 'on' && account.role !== 'ADMIN' && !account.checked
}

function codeError(status: 400 | 422, key: MessageKey): AppError {
  return new AppError(status, 'VALIDATION_ERROR', key, undefined, { code: { key } })
}

/** A new sign-in, or the next link of [familyId]'s chain: a refresh token row and an access token. */
async function startSession(
  db: Pool | Connection,
  ctx: Context,
  req: Request,
  user: { id: number; role: Role },
  familyId: Buffer = randomBytes(16),
) {
  const refreshToken = randomBytes(48).toString('base64url')
  const seconds = user.role === 'ADMIN' ? REFRESH_TOKEN_SECONDS.admin : REFRESH_TOKEN_SECONDS.app
  const inserted = await exec(
    db,
    `INSERT INTO refresh_tokens (user_id, token_hash, family_id, expires_at, user_agent, ip)
     VALUES (?, ?, ?, NOW(3) + INTERVAL ? SECOND, ?, ?)`,
    [user.id, sha256(refreshToken), familyId, seconds, req.get('user-agent')?.slice(0, 255) ?? null, req.ip ?? null],
  )
  return {
    tokenId: inserted.insertId,
    tokens: { accessToken: await ctx.tokens.signAccess(user, familyId), refreshToken, expiresIn: ACCESS_TOKEN_SECONDS },
  }
}

async function revokeFamily(db: Pool | Connection, familyId: Buffer): Promise<void> {
  await exec(db, 'UPDATE refresh_tokens SET revoked_at = NOW(3) WHERE family_id = ? AND revoked_at IS NULL', [familyId])
}
