// S1 Accounts (BACKEND_PLAN.md §7): SMS codes, sign-up, sign-in, refresh,
// sign-out, reset, the account and its addresses. Against a real saba_test.
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { after, before, beforeEach, describe, test } from 'node:test'
import { SignJWT } from 'jose'
import { createPool, type Pool } from '../src/db/pool.js'
import { exec, one } from '../src/db/sql.js'
import { hashPassword } from '../src/lib/password.js'
import { freshDatabase, memoryLogger, startApp, testConfig, testDatabaseUrl } from './helpers.js'

const url = testDatabaseUrl()
const config = testConfig({ DATABASE_URL: url })
let pool: Pool
let base: string
let close: () => Promise<void>
/** The last SMS code "sent" to each number. */
const inbox = new Map<string, string>()

before(async () => {
  await freshDatabase(url)
  pool = createPool(url, 4)
  const app = await startApp({
    config,
    pool,
    logger: memoryLogger().logger,
    sms: async (phone, code) => void inbox.set(phone, code),
  })
  base = app.url
  close = app.close
})

after(async () => {
  await close()
  await pool.end()
})

// Codes are limited per number and per address (all tests come from 127.0.0.1).
beforeEach(() => exec(pool, 'DELETE FROM otp_challenges'))

interface Reply {
  status: number
  body: any
  headers: Headers
}

async function call(
  method: string,
  path: string,
  options: { body?: unknown; token?: string; lang?: string } = {},
): Promise<Reply> {
  const response = await fetch(`${base}/api/v1${path}`, {
    method,
    headers: {
      ...(options.body !== undefined && { 'content-type': 'application/json' }),
      ...(options.token && { authorization: `Bearer ${options.token}` }),
      ...(options.lang && { 'accept-language': options.lang }),
    },
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  })
  return { status: response.status, body: await response.json(), headers: response.headers }
}

/** Lets a test ask again for a number that just had a code (the 60-second wait is tested on its own). */
const forgetCodes = (phone: string) => exec(pool, 'DELETE FROM otp_challenges WHERE phone = ?', [phone])

let next = 0
/** A number no other test uses, as the app sends it (E.164). */
function freshPhone(): string {
  next += 1
  return `+964770${String(10_000_000 + next).slice(1)}`
}

async function proofFor(phone: string, typed: string = phone): Promise<string> {
  const sent = await call('POST', '/auth/otp/send', { body: { phone: typed, purpose: 'SIGN_UP' } })
  assert.equal(sent.status, 200, JSON.stringify(sent.body))
  const verified = await call('POST', '/auth/otp/verify', { body: { phone: typed, code: inbox.get(phone) } })
  assert.equal(verified.status, 200, JSON.stringify(verified.body))
  return verified.body.data.verificationToken
}

const PASSWORD = 'correct horse'

async function signUpShopper(phone = freshPhone(), extra: Record<string, unknown> = {}) {
  const reply = await call('POST', '/auth/register/customer', {
    body: {
      fullName: 'Amina Saleh',
      password: PASSWORD,
      phone,
      phoneVerificationToken: await proofFor(phone),
      governorate: 'BAGHDAD',
      ...extra,
    },
  })
  assert.equal(reply.status, 200, JSON.stringify(reply.body))
  return { phone, ...(reply.body.data as { user: any; accessToken: string; refreshToken: string }) }
}

// ---------------------------------------------------------------- SMS codes ---

describe('SMS codes and sign-up', () => {
  test('0751…, +964 751… and Arabic digits are one number (BUGS 108)', async () => {
    const { phone } = await signUpShopper('+9647512345678')
    assert.equal(phone, '+9647512345678')
    for (const typed of ['0751 234 5678', '+964 751 234 5678', '00964 751 234 5678', '٠٧٥١٢٣٤٥٦٧٨']) {
      const login = await call('POST', '/auth/login', { body: { phone: typed, password: PASSWORD } })
      assert.equal(login.status, 200, typed)
      assert.equal(login.body.data.user.phone, '+9647512345678')
    }
    const again = await call('POST', '/auth/otp/send', { body: { phone: '964 751 234 5678', purpose: 'SIGN_UP' } })
    assert.equal(again.status, 409)
    assert.equal(again.body.code, 'CONFLICT_ERROR')
  })

  test('a code is never in the answer; the resend wait is', async () => {
    const reply = await call('POST', '/auth/otp/send', { body: { phone: freshPhone() } })
    assert.deepEqual(reply.body.data, { expiresInSeconds: 60 })
  })

  test('a number that is not an Iraqi mobile is refused on the phone field', async () => {
    const reply = await call('POST', '/auth/otp/send', { body: { phone: '0612345678' }, lang: 'ar' })
    assert.equal(reply.status, 422)
    assert.equal(reply.body.errors.phone, 'أدخل رقم هاتف عراقي، مثل 0770 123 4567.')
  })

  test('a reset code for a number with no account is refused on the phone field', async () => {
    const reply = await call('POST', '/auth/otp/send', { body: { phone: freshPhone(), purpose: 'PASSWORD_RESET' } })
    assert.equal(reply.status, 422)
    assert.equal(reply.body.errors.phone, 'No account uses this number.')
  })

  test('a second code within 60 seconds is refused, with Retry-After', async () => {
    const phone = freshPhone()
    assert.equal((await call('POST', '/auth/otp/send', { body: { phone } })).status, 200)
    const again = await call('POST', '/auth/otp/send', { body: { phone } })
    assert.equal(again.status, 429)
    const wait = Number(again.headers.get('retry-after'))
    assert.ok(wait > 0 && wait <= 60, String(wait))
  })

  test('at most 5 codes a number an hour', async () => {
    const phone = freshPhone()
    for (let i = 0; i < 5; i++) {
      await exec(
        pool,
        `INSERT INTO otp_challenges (phone, purpose, code_hash, expires_at, created_at)
         VALUES (?, 'OTHER', REPEAT('x', 32), NOW(3), NOW(3) - INTERVAL 10 MINUTE)`,
        [phone],
      )
    }
    const reply = await call('POST', '/auth/otp/send', { body: { phone } })
    assert.equal(reply.status, 429)
    assert.equal(reply.body.message, 'Too many codes were asked for. Try again in an hour.')
  })

  test('a wrong code is 400 on the code field; the fifth wrong try uses the code up', async () => {
    const phone = freshPhone()
    await call('POST', '/auth/otp/send', { body: { phone, purpose: 'SIGN_UP' } })
    const right = inbox.get(phone)!
    const wrong = right === '000000' ? '111111' : '000000'
    for (let i = 1; i <= 4; i++) {
      const reply = await call('POST', '/auth/otp/verify', { body: { phone, code: wrong } })
      assert.equal(reply.status, 400)
      assert.equal(reply.body.errors.code, 'That code is not right.')
    }
    const fifth = await call('POST', '/auth/otp/verify', { body: { phone, code: wrong } })
    assert.equal(fifth.body.errors.code, 'Too many wrong tries. Ask for a new code.')
    const late = await call('POST', '/auth/otp/verify', { body: { phone, code: right } })
    assert.equal(late.status, 400)
    assert.equal(late.body.errors.code, 'Too many wrong tries. Ask for a new code.')
  })

  test('only a sign-up code proves a number for sign-up', async () => {
    const phone = freshPhone()
    await call('POST', '/auth/otp/send', { body: { phone } })
    const reply = await call('POST', '/auth/otp/verify', { body: { phone, code: inbox.get(phone) } })
    assert.equal(reply.status, 400)
    assert.equal(reply.body.errors.code, 'This code has expired. Ask for a new one.')
  })

  test('a code older than 5 minutes has expired', async () => {
    const phone = freshPhone()
    await call('POST', '/auth/otp/send', { body: { phone, purpose: 'SIGN_UP' } })
    await exec(pool, 'UPDATE otp_challenges SET expires_at = NOW(3) - INTERVAL 1 SECOND WHERE phone = ?', [phone])
    const reply = await call('POST', '/auth/otp/verify', { body: { phone, code: inbox.get(phone) } })
    assert.equal(reply.status, 400)
    assert.equal(reply.body.errors.code, 'This code has expired. Ask for a new one.')
  })

  test('a made-up verification token makes no account', async () => {
    const phone = freshPhone()
    const forged = await new SignJWT({ typ: 'phone', phone })
      .setProtectedHeader({ alg: 'HS256' })
      .setSubject('1')
      .setExpirationTime('15m')
      .sign(new TextEncoder().encode('not-the-server-secret-but-long-enough'))
    for (const token of ['otp-' + phone, forged]) {
      const reply = await call('POST', '/auth/register/customer', {
        body: { fullName: 'X', password: PASSWORD, phone, phoneVerificationToken: token, governorate: 'BAGHDAD' },
      })
      assert.equal(reply.status, 422)
      assert.equal(reply.body.errors.phone, 'Verify this number with an SMS code first.')
    }
    assert.equal(await one(pool, 'SELECT id FROM users WHERE phone = ?', [phone]), undefined)
  })

  test("one number's proof can't sign up another number (BUGS 168)", async () => {
    const proof = await proofFor(freshPhone())
    const other = freshPhone()
    const reply = await call('POST', '/auth/register/customer', {
      body: { fullName: 'X', password: PASSWORD, phone: other, phoneVerificationToken: proof, governorate: 'BAGHDAD' },
    })
    assert.equal(reply.status, 422)
    assert.equal(reply.body.errors.phone, 'Verify this number with an SMS code first.')
  })

  test('one proof makes one account, even when sent twice at once', async () => {
    const phone = freshPhone()
    const proof = await proofFor(phone)
    const body = { fullName: 'Twice', password: PASSWORD, phone, phoneVerificationToken: proof, governorate: 'BAGHDAD' }
    const replies = await Promise.all([
      call('POST', '/auth/register/customer', { body }),
      call('POST', '/auth/register/customer', { body }),
    ])
    assert.deepEqual(replies.map((r) => r.status).sort(), [200, 422])
    const count = await one<{ n: number }>(pool, 'SELECT COUNT(*) AS n FROM users WHERE phone = ?', [phone])
    assert.equal(count?.n, 1)
  })

  test('an access token is not a phone proof', async () => {
    const { accessToken } = await signUpShopper()
    const phone = freshPhone()
    const reply = await call('POST', '/auth/register/customer', {
      body: { fullName: 'X', password: PASSWORD, phone, phoneVerificationToken: accessToken, governorate: 'BAGHDAD' },
    })
    assert.equal(reply.status, 422)
  })

  test('nobody can sign up as an admin', async () => {
    const { user } = await signUpShopper(freshPhone(), { role: 'ADMIN' })
    assert.equal(user.role, 'CUSTOMER')
    const row = await one<{ role: string }>(pool, 'SELECT role FROM users WHERE id = ?', [user.id])
    assert.equal(row?.role, 'CUSTOMER')
  })

  test('a shopper signs up with the fields the app reads', async () => {
    const { user, accessToken, refreshToken } = await signUpShopper(freshPhone())
    assert.equal(user.fullName, 'Amina Saleh')
    assert.equal(user.status, 'ACTIVE')
    assert.equal(user.governorate, 'BAGHDAD')
    assert.equal(user.isPhoneVerified, true)
    assert.equal(user.merchant, undefined)
    assert.ok(accessToken && refreshToken)
    const stored = await one<{ password_hash: string }>(pool, 'SELECT password_hash FROM users WHERE id = ?', [user.id])
    assert.match(stored!.password_hash, /^scrypt\$/)
    assert.ok(!stored!.password_hash.includes(PASSWORD))
  })

  test("an email given at sign-up is not kept: nobody can take another person's email, and none counts as checked (the reviewer's item 13)", async () => {
    // Two sign-ups naming the same email both go through; neither keeps it.
    for (const email of ['owner@example.com', 'OWNER@example.com']) {
      const { user } = await signUpShopper(freshPhone(), { email })
      assert.deepEqual([user.email, user.isEmailVerified], [null, false])
      const stored = await one<{ email: string | null }>(pool, 'SELECT email FROM users WHERE id = ?', [user.id])
      assert.equal(stored!.email, null)
    }
    // So it can't be used to sign in either.
    const reply = await call('POST', '/auth/login', { body: { email: 'owner@example.com', password: PASSWORD } })
    assert.equal(reply.status, 401)
  })

  test('a password under 8 characters and a name over 50 are refused on their fields', async () => {
    const phone = freshPhone()
    const reply = await call('POST', '/auth/register/customer', {
      body: {
        fullName: 'x'.repeat(51),
        password: 'short',
        phone,
        phoneVerificationToken: 'anything',
        governorate: 'BAGHDAD',
      },
    })
    assert.equal(reply.status, 422)
    assert.equal(reply.body.errors.password, 'Use at least 8 characters.')
    assert.equal(reply.body.errors.fullName, 'Use at most 50 characters.')
  })
})

// ------------------------------------------------------------ store owners ---

describe('store owners', () => {
  async function signUpStore(storeName: string, governorate: string) {
    const phone = freshPhone()
    return call('POST', '/auth/register/merchant', {
      body: {
        fullName: 'Omar Al-Sayed',
        password: PASSWORD,
        phone,
        phoneVerificationToken: await proofFor(phone),
        governorate,
        storeName,
        businessType: 'INDIVIDUAL',
        businessAddress: 'Karrada',
      },
    })
  }

  test('a new store waits for Saba: PENDING, on the account as merchant', async () => {
    const reply = await signUpStore('Nova Electronics', 'BAGHDAD')
    assert.equal(reply.status, 200, JSON.stringify(reply.body))
    const { user } = reply.body.data
    assert.equal(user.role, 'MERCHANT')
    assert.equal(user.merchant.storeName, 'Nova Electronics')
    assert.equal(user.merchant.status, 'PENDING')
    assert.equal(user.merchant.rating, null)
  })

  test('a store name taken in the same city is refused; in another city it is fine (BUGS 120)', async () => {
    assert.equal((await signUpStore('Tech Hub', 'BASRA')).status, 200)
    const same = await signUpStore('  tech   HUB ', 'BASRA')
    assert.equal(same.status, 422)
    assert.equal(same.body.errors.storeName, 'A store in this city already has this name. Choose another.')
    assert.equal((await signUpStore('Tech Hub', 'ERBIL')).status, 200)
  })

  test('a refused store name leaves no account behind, and the number can try again', async () => {
    assert.equal((await signUpStore('Only One', 'NAJAF')).status, 200)
    const phone = freshPhone()
    const proof = await proofFor(phone)
    const body = {
      fullName: 'Z',
      password: PASSWORD,
      phone,
      phoneVerificationToken: proof,
      governorate: 'NAJAF',
      storeName: 'only one',
    }
    assert.equal((await call('POST', '/auth/register/merchant', { body })).status, 422)
    assert.equal(await one(pool, 'SELECT id FROM users WHERE phone = ?', [phone]), undefined)
    const retry = await call('POST', '/auth/register/merchant', { body: { ...body, storeName: 'Only Two' } })
    assert.equal(retry.status, 200, JSON.stringify(retry.body))
  })
})

// ----------------------------------------------------------------- sign-in ---

describe('sign-in and sessions', () => {
  test('an unknown number is 422 on the phone field; a wrong password is 401', async () => {
    const unknown = await call('POST', '/auth/login', { body: { phone: freshPhone(), password: PASSWORD } })
    assert.equal(unknown.status, 422)
    assert.equal(unknown.body.errors.phone, 'No account uses this number. Sign up first.')
    const { phone } = await signUpShopper()
    const wrong = await call('POST', '/auth/login', { body: { phone, password: 'not the password' } })
    assert.equal(wrong.status, 401)
    assert.equal(wrong.body.code, 'AUTHENTICATION_ERROR')
  })

  test('an admin signs in by email; its refresh token lasts 12 hours, a shopper’s 30 days', async () => {
    const phone = freshPhone()
    await exec(
      pool,
      `INSERT INTO users (role, full_name, phone, email, password_hash) VALUES ('ADMIN', 'Saba admin', ?, 'boss@saba.app', ?)`,
      [phone, await hashPassword(PASSWORD)],
    )
    const reply = await call('POST', '/auth/login', { body: { email: 'Boss@Saba.app', password: PASSWORD } })
    assert.equal(reply.status, 200, JSON.stringify(reply.body))
    assert.equal(reply.body.data.user.role, 'ADMIN')
    // Saba's staff: the only email that counts as checked.
    assert.equal(reply.body.data.user.isEmailVerified, true)
    const lives = async (userId: string) =>
      (await one<{ s: number }>(
        pool,
        'SELECT TIMESTAMPDIFF(SECOND, created_at, expires_at) AS s FROM refresh_tokens WHERE user_id = ? ORDER BY id DESC LIMIT 1',
        [userId],
      ))!.s
    assert.ok(Math.abs((await lives(reply.body.data.user.id)) - 12 * 3600) <= 2)
    const shopper = await signUpShopper()
    assert.ok(Math.abs((await lives(shopper.user.id)) - 30 * 86400) <= 2)
  })

  test('a store owner signs in too (D1): the web, not the server, refuses non-admins', async () => {
    const phone = freshPhone()
    await call('POST', '/auth/register/merchant', {
      body: {
        fullName: 'Layla',
        password: PASSWORD,
        phone,
        phoneVerificationToken: await proofFor(phone),
        governorate: 'KIRKUK',
        storeName: 'Layla Store',
      },
    })
    const reply = await call('POST', '/auth/login', { body: { phone, password: PASSWORD } })
    assert.equal(reply.status, 200)
    assert.equal(reply.body.data.user.role, 'MERCHANT')
  })

  test('11 tries in 15 minutes from one address for one number: the 11th is 429', async () => {
    const { phone } = await signUpShopper()
    for (let i = 0; i < 10; i++) {
      assert.equal((await call('POST', '/auth/login', { body: { phone, password: 'wrong password' } })).status, 401)
    }
    const eleventh = await call('POST', '/auth/login', { body: { phone, password: PASSWORD } })
    assert.equal(eleventh.status, 429)
    assert.ok(Number(eleventh.headers.get('retry-after')) > 0)
  })

  test('refresh gives a new pair; the old refresh token used again ends the whole sign-in', async () => {
    const first = await signUpShopper()
    const rotated = await call('POST', '/auth/refresh', { body: { refreshToken: first.refreshToken } })
    assert.equal(rotated.status, 200)
    const second = rotated.body.data.refreshToken
    assert.notEqual(second, first.refreshToken)
    assert.equal(rotated.body.data.expiresIn, 900)
    // Someone replays the copied old token: refused, and the family goes with it.
    const replay = await call('POST', '/auth/refresh', { body: { refreshToken: first.refreshToken } })
    assert.equal(replay.status, 401)
    const legit = await call('POST', '/auth/refresh', { body: { refreshToken: second } })
    assert.equal(legit.status, 401)
  })

  test('another sign-in of the same account is not touched by one family being revoked', async () => {
    const a = await signUpShopper()
    const b = await call('POST', '/auth/login', { body: { phone: a.phone, password: PASSWORD } })
    await call('POST', '/auth/refresh', { body: { refreshToken: a.refreshToken } })
    await call('POST', '/auth/refresh', { body: { refreshToken: a.refreshToken } })
    const other = await call('POST', '/auth/refresh', { body: { refreshToken: b.body.data.refreshToken } })
    assert.equal(other.status, 200)
  })

  test('an expired refresh token is refused', async () => {
    const { refreshToken, user } = await signUpShopper()
    await exec(pool, 'UPDATE refresh_tokens SET expires_at = NOW(3) - INTERVAL 1 SECOND WHERE user_id = ?', [user.id])
    assert.equal((await call('POST', '/auth/refresh', { body: { refreshToken } })).status, 401)
  })

  test('sign-out ends the sign-in, even if the app refreshed on the way', async () => {
    const { accessToken, refreshToken, phone } = await signUpShopper()
    const elsewhere = (await call('POST', '/auth/login', { body: { phone, password: PASSWORD } })).body.data
    const rotated = await call('POST', '/auth/refresh', { body: { refreshToken } })
    const out = await call('POST', '/auth/logout', { token: accessToken, body: { refreshToken } })
    assert.equal(out.status, 200)
    const after = await call('POST', '/auth/refresh', { body: { refreshToken: rotated.body.data.refreshToken } })
    assert.equal(after.status, 401)
    // Its access tokens end with it at once, not up to 15 minutes later (the user's call, 2026-09-28).
    assert.equal((await call('GET', '/customers/me', { token: accessToken })).status, 401)
    assert.equal((await call('GET', '/customers/me', { token: rotated.body.data.accessToken })).status, 401)
    // The account's other sign-in goes on.
    assert.equal((await call('GET', '/customers/me', { token: elsewhere.accessToken })).status, 200)
  })

  test('a suspended account is out at its next request, and sign-in says why', async () => {
    const { user, phone, accessToken, refreshToken } = await signUpShopper()
    assert.equal((await call('GET', '/customers/me', { token: accessToken })).status, 200)
    await exec(pool, "UPDATE users SET status = 'SUSPENDED', suspension_reason = 'test' WHERE id = ?", [user.id])
    const me = await call('GET', '/customers/me', { token: accessToken })
    assert.equal(me.status, 401)
    assert.equal(me.body.code, 'AUTHENTICATION_ERROR')
    assert.equal((await call('POST', '/auth/refresh', { body: { refreshToken } })).status, 401)
    const login = await call('POST', '/auth/login', { body: { phone, password: PASSWORD }, lang: 'ar' })
    assert.equal(login.status, 403)
    assert.equal(login.body.code, 'AUTHORIZATION_ERROR')
    assert.equal(login.body.message, 'هذا الحساب موقوف.')
  })

  test('each kind of token works only as itself, even signed with the real secret', async () => {
    const key = new TextEncoder().encode(config.jwtSecret)
    const { user } = await signUpShopper()
    // A phone proof naming a real account id is not an access token.
    const proofShaped = await new SignJWT({ typ: 'phone', phone: user.phone })
      .setProtectedHeader({ alg: 'HS256' })
      .setSubject(user.id)
      .setExpirationTime('15m')
      .sign(key)
    assert.equal((await call('GET', '/customers/me', { token: proofShaped })).status, 401)
    // An access token that happens to carry a phone and a challenge id is not a phone proof.
    const phone = freshPhone()
    await proofFor(phone)
    const challenge = await one<{ id: number }>(pool, 'SELECT id FROM otp_challenges WHERE phone = ?', [phone])
    const accessShaped = await new SignJWT({ typ: 'access', role: 'CUSTOMER', phone })
      .setProtectedHeader({ alg: 'HS256' })
      .setSubject(String(challenge!.id))
      .setExpirationTime('15m')
      .sign(key)
    const reply = await call('POST', '/auth/register/customer', {
      body: { fullName: 'X', password: PASSWORD, phone, phoneVerificationToken: accessShaped, governorate: 'BAGHDAD' },
    })
    assert.equal(reply.status, 422)
  })

  test('a token signed with another secret, or of the wrong kind, is 401', async () => {
    const forged = await new SignJWT({ typ: 'access', role: 'ADMIN' })
      .setProtectedHeader({ alg: 'HS256' })
      .setSubject('1')
      .setExpirationTime('15m')
      .sign(new TextEncoder().encode('not-the-server-secret-but-long-enough'))
    assert.equal((await call('GET', '/customers/me', { token: forged })).status, 401)
    const proof = await proofFor(freshPhone())
    assert.equal((await call('GET', '/customers/me', { token: proof })).status, 401)
    assert.equal((await call('GET', '/customers/me')).status, 401)
  })

  test("an access token counts only with its own live sign-in, even signed with the real secret", async () => {
    const key = new TextEncoder().encode(config.jwtSecret)
    const access = (sub: string, claims: Record<string, unknown>) =>
      new SignJWT({ typ: 'access', role: 'CUSTOMER', ...claims }).setProtectedHeader({ alg: 'HS256' }).setSubject(sub).setExpirationTime('15m').sign(key)
    const a = await signUpShopper()
    const b = await signUpShopper()
    const familyOf = async (userId: string) =>
      (await one<{ family_id: Buffer }>(pool, 'SELECT family_id FROM refresh_tokens WHERE user_id = ? ORDER BY id DESC LIMIT 1', [userId]))!.family_id.toString('base64url')
    // Its own sign-in: in.
    assert.equal((await call('GET', '/customers/me', { token: await access(a.user.id, { sid: await familyOf(a.user.id) }) })).status, 200)
    // No sign-in named, as tokens were made before: out.
    assert.equal((await call('GET', '/customers/me', { token: await access(a.user.id, {}) })).status, 401)
    // Another account's live sign-in: out.
    assert.equal((await call('GET', '/customers/me', { token: await access(a.user.id, { sid: await familyOf(b.user.id) }) })).status, 401)
    // Its own sign-in, run out: out.
    const own = await access(a.user.id, { sid: await familyOf(a.user.id) })
    await exec(pool, 'UPDATE refresh_tokens SET expires_at = NOW(3) - INTERVAL 1 SECOND WHERE user_id = ?', [a.user.id])
    assert.equal((await call('GET', '/customers/me', { token: own })).status, 401)
  })

  test('a forgotten password: the code resets it, signs every device out, and the old one stops working', async () => {
    const { phone, refreshToken } = await signUpShopper()
    await forgetCodes(phone)
    await call('POST', '/auth/otp/send', { body: { phone, purpose: 'PASSWORD_RESET' } })
    const code = inbox.get(phone)!
    const wrong = await call('POST', '/auth/reset-password', {
      body: { phone, token: code === '000000' ? '111111' : '000000', password: 'brand new pass' },
    })
    assert.equal(wrong.status, 422)
    assert.equal(wrong.body.errors.code, 'That code is not right.')
    const reset = await call('POST', '/auth/reset-password', { body: { phone, token: code, password: 'brand new pass' } })
    assert.equal(reset.status, 200)
    assert.equal((await call('POST', '/auth/refresh', { body: { refreshToken } })).status, 401)
    assert.equal((await call('POST', '/auth/login', { body: { phone, password: PASSWORD } })).status, 401)
    assert.equal((await call('POST', '/auth/login', { body: { phone, password: 'brand new pass' } })).status, 200)
    // The code is used up.
    const again = await call('POST', '/auth/reset-password', { body: { phone, token: code, password: 'another one!' } })
    assert.equal(again.status, 422)
  })

  test('a sign-up code does not reset a password', async () => {
    const { phone } = await signUpShopper()
    await forgetCodes(phone)
    await call('POST', '/auth/otp/send', { body: { phone, purpose: 'SIGN_UP' } })
    const reply = await call('POST', '/auth/reset-password', {
      body: { phone, token: inbox.get(phone), password: 'brand new pass' },
    })
    assert.equal(reply.status, 422)
  })
})

// ----------------------------------------------------------------- account ---

describe('the account', () => {
  test('PATCH changes the name and governorate only; the phone is ignored', async () => {
    const { accessToken, phone } = await signUpShopper()
    const reply = await call('PATCH', '/customers/me', {
      token: accessToken,
      body: { fullName: '  Amina K. ', governorate: 'BASRA', phone: freshPhone(), role: 'ADMIN' },
    })
    assert.equal(reply.status, 200)
    assert.equal(reply.body.data.fullName, 'Amina K.')
    assert.equal(reply.body.data.governorate, 'BASRA')
    assert.equal(reply.body.data.phone, phone)
    assert.equal(reply.body.data.role, 'CUSTOMER')
  })

  async function placeOrder(customerId: string, status: string) {
    const delivered = status === 'DELIVERED'
    const inserted = await exec(
      pool,
      `INSERT INTO orders (customer_id, status, payment_status, subtotal, shipping, total, item_count, customer_name,
                           customer_phone, ship_governorate, ship_area, ship_landmark, placed_at, delivered_at, search_text)
       VALUES (?, ?, ?, 10000, 0, 10000, 1, 'Amina', '+9647700000000', 'BAGHDAD', 'Karrada', 'Mosque', NOW(3), ?, '')`,
      [customerId, status, delivered ? 'PAID' : 'PENDING', delivered ? new Date() : null],
    )
    return `SB-${100000 + inserted.insertId}`
  }

  test('deleting an account with open orders is refused, naming them (Q9)', async () => {
    const { user, accessToken } = await signUpShopper()
    const first = await placeOrder(user.id, 'PENDING')
    const second = await placeOrder(user.id, 'SHIPPED')
    await placeOrder(user.id, 'DELIVERED')
    const en = await call('DELETE', '/customers/me', { token: accessToken })
    assert.equal(en.status, 409)
    assert.equal(en.body.code, 'CONFLICT_ERROR')
    assert.equal(en.body.message, `Orders ${first} and ${second} are still open. The account can be deleted once they are finished.`)
    const ar = await call('DELETE', '/customers/me', { token: accessToken, lang: 'ar' })
    assert.equal(ar.body.message, `الطلبات ${first} و${second} ما زالت مفتوحة. يمكن حذف الحساب بعد انتهائها.`)
    const still = await one<{ status: string }>(pool, 'SELECT status FROM users WHERE id = ?', [user.id])
    assert.equal(still?.status, 'ACTIVE')
  })

  test('deleting an account: the number is freed, sessions end, addresses go, orders stay', async () => {
    const { user, phone, accessToken, refreshToken } = await signUpShopper()
    await placeOrder(user.id, 'DELIVERED')
    await call('POST', '/customers/me/addresses', { token: accessToken, body: address() })
    const reply = await call('DELETE', '/customers/me', { token: accessToken })
    assert.equal(reply.status, 200)
    assert.equal((await call('GET', '/customers/me', { token: accessToken })).status, 401)
    assert.equal((await call('POST', '/auth/refresh', { body: { refreshToken } })).status, 401)
    const live = await one<{ n: number }>(
      pool,
      'SELECT COUNT(*) AS n FROM refresh_tokens WHERE user_id = ? AND revoked_at IS NULL',
      [user.id],
    )
    assert.equal(live?.n, 0)
    const login = await call('POST', '/auth/login', { body: { phone, password: PASSWORD } })
    assert.equal(login.status, 422)
    const row = await one<{ n: number }>(pool, 'SELECT COUNT(*) AS n FROM addresses WHERE user_id = ?', [user.id])
    assert.equal(row?.n, 0)
    const orders = await one<{ n: number }>(pool, 'SELECT COUNT(*) AS n FROM orders WHERE customer_id = ?', [user.id])
    assert.equal(orders?.n, 1)
    // The number is free again (BUGS 79).
    await forgetCodes(phone)
    const again = await signUpShopper(phone)
    assert.notEqual(again.user.id, user.id)
  })

  test('a store owner closes the store instead: deleting is 403', async () => {
    const phone = freshPhone()
    const reply = await call('POST', '/auth/register/merchant', {
      body: {
        fullName: 'Owner',
        password: PASSWORD,
        phone,
        phoneVerificationToken: await proofFor(phone),
        governorate: 'DUHOK',
        storeName: 'Duhok Shop',
      },
    })
    const del = await call('DELETE', '/customers/me', { token: reply.body.data.accessToken })
    assert.equal(del.status, 403)
    assert.equal(del.body.code, 'AUTHORIZATION_ERROR')
  })
})

// --------------------------------------------------------------- addresses ---

function address(extra: Record<string, unknown> = {}) {
  return {
    fullName: 'Amina Saleh',
    phone: '0770 555 0142',
    governorate: 'BAGHDAD',
    area: 'Al-Mansour',
    landmark: 'Next to Al-Rasheed Mosque',
    ...extra,
  }
}

describe('addresses', () => {
  test('the first address is the default; the number is kept as E.164; no nickname is null', async () => {
    const { accessToken } = await signUpShopper()
    const reply = await call('POST', '/customers/me/addresses', { token: accessToken, body: address() })
    assert.equal(reply.status, 200, JSON.stringify(reply.body))
    assert.equal(reply.body.data.isDefault, true)
    assert.equal(reply.body.data.phone, '+9647705550142')
    assert.equal(reply.body.data.label, null)
    assert.equal(reply.body.data.street, null)
  })

  test('one default at a time: a new default takes over, and PUT …/default moves it', async () => {
    const { accessToken } = await signUpShopper()
    const a = (await call('POST', '/customers/me/addresses', { token: accessToken, body: address({ label: 'Home' }) }))
      .body.data
    const b = (
      await call('POST', '/customers/me/addresses', { token: accessToken, body: address({ label: 'Work', isDefault: true }) })
    ).body.data
    let list = (await call('GET', '/customers/me/addresses', { token: accessToken })).body.data
    assert.deepEqual(
      list.map((x: any) => [x.id, x.isDefault]),
      [
        [b.id, true],
        [a.id, false],
      ],
    )
    const moved = await call('PUT', `/customers/me/addresses/${a.id}/default`, { token: accessToken })
    assert.equal(moved.status, 200)
    list = (await call('GET', '/customers/me/addresses', { token: accessToken })).body.data
    assert.deepEqual(
      list.map((x: any) => [x.id, x.isDefault]),
      [
        [a.id, true],
        [b.id, false],
      ],
    )
  })

  test('two "make default" at once still leave exactly one default', async () => {
    const { accessToken, user } = await signUpShopper()
    const ids: string[] = []
    for (let i = 0; i < 4; i++) {
      ids.push((await call('POST', '/customers/me/addresses', { token: accessToken, body: address() })).body.data.id)
    }
    const replies = await Promise.all(
      ids.map((id) => call('PUT', `/customers/me/addresses/${id}/default`, { token: accessToken })),
    )
    assert.deepEqual(
      replies.map((r) => r.status),
      [200, 200, 200, 200],
    )
    const row = await one<{ n: number }>(pool, 'SELECT COUNT(*) AS n FROM addresses WHERE user_id = ? AND is_default = 1', [
      user.id,
    ])
    assert.equal(row?.n, 1)
  })

  test('six addresses added at once: every one saved, exactly one the default', async () => {
    const { accessToken, user } = await signUpShopper()
    const replies = await Promise.all(
      Array.from({ length: 6 }, (_, i) =>
        call('POST', '/customers/me/addresses', { token: accessToken, body: address({ label: `A${i}`, isDefault: i % 2 === 0 }) }),
      ),
    )
    assert.deepEqual(
      replies.map((r) => r.status),
      [200, 200, 200, 200, 200, 200],
    )
    const row = await one<{ n: number; d: number }>(
      pool,
      'SELECT COUNT(*) AS n, SUM(is_default) AS d FROM addresses WHERE user_id = ?',
      [user.id],
    )
    assert.equal(row?.n, 6)
    assert.equal(Number(row?.d), 1)
  })

  test("another shopper's address is not found: read, replace, delete, default", async () => {
    const owner = await signUpShopper()
    const other = await signUpShopper()
    const id = (await call('POST', '/customers/me/addresses', { token: owner.accessToken, body: address() })).body.data.id
    const token = other.accessToken
    assert.equal((await call('PUT', `/customers/me/addresses/${id}`, { token, body: address() })).status, 404)
    assert.equal((await call('PUT', `/customers/me/addresses/${id}/default`, { token })).status, 404)
    assert.equal((await call('DELETE', `/customers/me/addresses/${id}`, { token })).status, 404)
    assert.equal((await call('GET', '/customers/me/addresses', { token })).body.data.length, 0)
    assert.equal((await call('DELETE', '/customers/me/addresses/not-a-number', { token })).status, 404)
    const still = await call('GET', '/customers/me/addresses', { token: owner.accessToken })
    assert.equal(still.body.data.length, 1)
  })

  test('the server checks an address: an Iraqi mobile, a known governorate, area and landmark', async () => {
    const { accessToken } = await signUpShopper()
    const reply = await call('POST', '/customers/me/addresses', {
      token: accessToken,
      body: address({ phone: '12345', governorate: 'PARIS', area: '   ', landmark: undefined }),
    })
    assert.equal(reply.status, 422)
    assert.deepEqual(Object.keys(reply.body.errors).sort(), ['area', 'governorate', 'landmark', 'phone'])
  })

  test('replacing an address keeps it the default unless it says otherwise', async () => {
    const { accessToken } = await signUpShopper()
    const a = (await call('POST', '/customers/me/addresses', { token: accessToken, body: address() })).body.data
    const put = await call('PUT', `/customers/me/addresses/${a.id}`, {
      token: accessToken,
      body: address({ area: 'Karrada', street: 'Street 52' }),
    })
    assert.equal(put.status, 200)
    assert.equal(put.body.data.area, 'Karrada')
    assert.equal(put.body.data.street, 'Street 52')
    assert.equal(put.body.data.isDefault, true)
  })

  test('addresses are for shoppers: a store owner gets 403, nobody 401', async () => {
    const phone = freshPhone()
    const store = await call('POST', '/auth/register/merchant', {
      body: {
        fullName: 'Owner',
        password: PASSWORD,
        phone,
        phoneVerificationToken: await proofFor(phone),
        governorate: 'WASIT',
        storeName: 'Wasit Shop',
      },
    })
    assert.equal((await call('GET', '/customers/me/addresses', { token: store.body.data.accessToken })).status, 403)
    assert.equal((await call('GET', '/customers/me/addresses')).status, 401)
  })
})

// ------------------------------------------------------------ staff admins ---

describe('staff admins', () => {
  /** Runs backend/scripts/[script].ts against the test database, [input] on its stdin; with the test's own secrets, so no .env is needed. */
  const run = (script: string, args: string[], input = '') =>
    spawnSync(process.execPath, ['--import', 'tsx', `scripts/${script}.ts`, ...args], {
      input,
      encoding: 'utf8',
      env: { ...process.env, NODE_ENV: 'test', DATABASE_URL: url, JWT_SECRET: config.jwtSecret, OTP_SECRET: config.otpSecret },
    })

  test('create-admin takes a piped password without showing it; suspend-admin shuts the account out at once and ends its sign-ins; --restore lets it back (final review 6, 13)', async () => {
    const made = run('create-admin', ['--name', 'Staff Leaver', '--email', 'leaver@saba.test', '--phone', '0781 234 5678'], 'Leaver password 1\n')
    assert.equal(made.status, 0, made.stderr)
    assert.match(made.stdout, /Admin \d+ created: Staff Leaver, leaver@saba\.test, \+9647812345678/)
    assert.ok(!made.stdout.includes('Leaver password 1'))
    const signIn = () => call('POST', '/auth/login', { body: { email: 'leaver@saba.test', password: 'Leaver password 1' } })
    const session = (await signIn()).body.data
    // An admin page with no order in it: this file's own orders are written without a number.
    assert.equal((await call('GET', '/admin/categories', { token: session.accessToken })).status, 200)

    const suspended = run('suspend-admin', ['--email', 'LEAVER@saba.test', '--reason', 'Left Saba'])
    assert.equal(suspended.status, 0, suspended.stderr)
    assert.match(suspended.stdout, /is suspended; 1 sign-in\(s\) ended\./)
    // Out at its next request, its refresh token ended, and no new sign-in.
    assert.notEqual((await call('GET', '/admin/categories', { token: session.accessToken })).status, 200)
    assert.notEqual((await call('POST', '/auth/refresh', { body: { refreshToken: session.refreshToken } })).status, 200)
    assert.equal((await signIn()).status, 403)

    const restored = run('suspend-admin', ['--phone', '0781 234 5678', '--restore'])
    assert.equal(restored.status, 0, restored.stderr)
    assert.equal((await signIn()).status, 200)
    // The old sign-in stays ended.
    assert.notEqual((await call('POST', '/auth/refresh', { body: { refreshToken: session.refreshToken } })).status, 200)
    // Only an admin, and only with a reason.
    assert.equal(run('suspend-admin', ['--email', 'nobody@saba.test', '--reason', 'x']).status, 1)
    assert.equal(run('suspend-admin', ['--email', 'leaver@saba.test']).status, 1)
  })
})

// ------------------------------------------------------- phone checks off ---

describe('phone checks switched off (PHONE_VERIFICATION=off)', () => {
  // A second server on the same database, with the setting off; `call` is the usual one, checks on.
  const offInbox = new Map<string, string>()
  let offBase: string
  let closeOff: () => Promise<void>
  before(async () => {
    const off = await startApp({
      config: testConfig({ DATABASE_URL: url, PHONE_VERIFICATION: 'off' }),
      pool,
      logger: memoryLogger().logger,
      sms: async (phone, code) => void offInbox.set(phone, code),
    })
    offBase = off.url
    closeOff = off.close
  })
  after(() => closeOff())
  // Every test here comes from 127.0.0.1, and codes are limited per address.
  beforeEach(() => exec(pool, 'DELETE FROM otp_challenges'))

  async function callOff(method: string, path: string, options: { body?: unknown; token?: string } = {}): Promise<Reply> {
    const response = await fetch(`${offBase}/api/v1${path}`, {
      method,
      headers: {
        ...(options.body !== undefined && { 'content-type': 'application/json' }),
        ...(options.token && { authorization: `Bearer ${options.token}` }),
      },
      body: options.body === undefined ? undefined : JSON.stringify(options.body),
    })
    return { status: response.status, body: await response.json(), headers: response.headers }
  }

  /** A sign-up with the setting off: no code, its proof straight back. */
  async function signUpUnchecked(role: 'customer' | 'merchant' = 'customer', phone = freshPhone()) {
    const sent = await callOff('POST', '/auth/otp/send', { body: { phone, purpose: 'SIGN_UP' } })
    assert.equal(sent.status, 200, JSON.stringify(sent.body))
    assert.equal(offInbox.has(phone), false)
    const reply = await callOff('POST', `/auth/register/${role}`, {
      body: {
        fullName: 'Unchecked Person',
        password: PASSWORD,
        phone,
        phoneVerificationToken: sent.body.data.verificationToken,
        governorate: 'BAGHDAD',
        ...(role === 'merchant' && { storeName: `Unchecked Store ${phone.slice(-4)}` }),
      },
    })
    assert.equal(reply.status, 200, JSON.stringify(reply.body))
    return { phone, ...(reply.body.data as { user: any; accessToken: string; refreshToken: string }) }
  }
  const checkedAt = async (phone: string) =>
    (await one<{ at: Date | null }>(pool, 'SELECT phone_verified_at AS at FROM users WHERE phone = ?', [phone]))?.at ?? null

  test('a sign-up needs no code and is kept unchecked; still one account a number, 20 an hour from one address; reset still sends its code', async () => {
    const made = await signUpUnchecked()
    assert.equal(await checkedAt(made.phone), null)
    // Signs in without a code while the setting is off.
    assert.equal((await callOff('POST', '/auth/login', { body: { phone: made.phone, password: PASSWORD } })).status, 200)
    // One account a number.
    assert.equal((await callOff('POST', '/auth/otp/send', { body: { phone: made.phone, purpose: 'SIGN_UP' } })).status, 409)
    // Password reset keeps its SMS code (the user's call A).
    assert.equal((await callOff('POST', '/auth/otp/send', { body: { phone: made.phone, purpose: 'PASSWORD_RESET' } })).status, 200)
    const reset = await callOff('POST', '/auth/reset-password', { body: { phone: made.phone, token: offInbox.get(made.phone), password: 'a new password' } })
    assert.equal(reset.status, 200, JSON.stringify(reset.body))
    // A sign-up with codes on still gets its code, and its number is checked.
    const checked = await signUpShopper()
    assert.notEqual(await checkedAt(checked.phone), null)

    // At most 20 sign-ups an hour from one address.
    await exec(pool, 'DELETE FROM otp_challenges')
    for (let i = 0; i < 20; i++) {
      assert.equal((await callOff('POST', '/auth/otp/send', { body: { phone: freshPhone(), purpose: 'SIGN_UP' } })).status, 200)
    }
    assert.equal((await callOff('POST', '/auth/otp/send', { body: { phone: freshPhone(), purpose: 'SIGN_UP' } })).status, 429)
  })

  test('codes back on: an unchecked account is signed out and asked for a code at sign-in; checked ones and admins sign in as before', async () => {
    const made = await signUpUnchecked()
    // Its sign-in ends at the next refresh.
    assert.equal((await call('POST', '/auth/refresh', { body: { refreshToken: made.refreshToken } })).status, 401)
    const signIn = (code?: string) => call('POST', '/auth/login', { body: { phone: made.phone, password: PASSWORD, ...(code && { code }) } })
    const asked = await signIn()
    assert.deepEqual([asked.status, asked.body.code], [403, 'PHONE_NOT_VERIFIED'])
    assert.equal((await call('POST', '/auth/otp/send', { body: { phone: made.phone, purpose: 'VERIFY_PHONE' } })).status, 200)
    const wrong = await signIn('000000' === inbox.get(made.phone) ? '111111' : '000000')
    assert.deepEqual([wrong.status, Object.keys(wrong.body.errors)], [422, ['code']])
    const right = await signIn(inbox.get(made.phone))
    assert.equal(right.status, 200, JSON.stringify(right.body))
    assert.notEqual(await checkedAt(made.phone), null)
    assert.equal((await signIn()).status, 200)
    // A code for a number with no account is refused, as a reset's is.
    assert.equal((await call('POST', '/auth/otp/send', { body: { phone: freshPhone(), purpose: 'VERIFY_PHONE' } })).status, 422)
    // An admin's number is never asked for.
    await exec(pool, "INSERT INTO users (role, full_name, phone, email, password_hash) VALUES ('ADMIN', 'Unchecked Admin', ?, 'unchecked@saba.test', ?)", [
      freshPhone(),
      await hashPassword(PASSWORD),
    ])
    assert.equal((await call('POST', '/auth/login', { body: { email: 'unchecked@saba.test', password: PASSWORD } })).status, 200)
  })

  test("Saba sees who is unchecked, and frees a number held by the wrong person; never a checked one", async () => {
    await exec(pool, "INSERT INTO users (role, full_name, phone, email, password_hash) VALUES ('ADMIN', 'Number Admin', ?, 'numbers@saba.test', ?)", [
      freshPhone(),
      await hashPassword(PASSWORD),
    ])
    const admin = (await call('POST', '/auth/login', { body: { email: 'numbers@saba.test', password: PASSWORD } })).body.data.accessToken
    const squatter = await signUpUnchecked()
    const owner = await signUpShopper()
    const unchecked = (await call('GET', '/admin/customers?phoneVerified=false&perPage=100', { token: admin })).body.data.items
    assert.ok(unchecked.some((c: any) => c.id === squatter.user.id && c.phoneVerified === false))
    assert.ok(!unchecked.some((c: any) => c.id === owner.user.id))

    // A shopper: deleted, and the number signs up again.
    const free = (id: string, path = 'customers') => call('POST', `/admin/${path}/${id}/free-number`, { token: admin, body: { reason: 'Not their number' } })
    assert.equal((await free(owner.user.id)).status, 409)
    assert.equal((await free(squatter.user.id)).status, 200)
    assert.equal((await call('POST', '/auth/otp/send', { body: { phone: squatter.phone, purpose: 'SIGN_UP' } })).status, 200)
    const audit = await one<{ reason: string }>(pool, "SELECT reason FROM admin_actions WHERE action = 'NUMBER_FREE' AND entity_id = ?", [squatter.user.id])
    assert.equal(audit?.reason, 'Not their number')

    // A store: its owner shut out at once, its deletion started.
    const store = await signUpUnchecked('merchant')
    const storeId = (await one<{ id: number }>(pool, 'SELECT id FROM stores WHERE owner_user_id = ?', [store.user.id]))!.id
    const listed = (await call('GET', '/admin/stores?phoneVerified=false&perPage=100', { token: admin })).body.data.items
    assert.ok(listed.some((s: any) => s.id === String(storeId) && s.phoneVerified === false))
    const freed = await free(String(storeId), 'stores')
    assert.equal(freed.status, 200, JSON.stringify(freed.body))
    assert.ok(freed.body.data.deletionRequestedAt)
    assert.equal((await call('POST', '/auth/login', { body: { phone: store.phone, password: PASSWORD } })).status, 403)
    assert.equal((await call('POST', '/auth/refresh', { body: { refreshToken: store.refreshToken } })).status, 401)
  })
})
