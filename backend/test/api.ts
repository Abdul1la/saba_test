// A running API on a fresh saba_test, and the calls a test makes against it.
import assert from 'node:assert/strict'
import { mkdtemp, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { createPool, type Pool } from '../src/db/pool.js'
import { exec } from '../src/db/sql.js'
import { hashPassword } from '../src/lib/password.js'
import type { SendPush } from '../src/lib/push.js'
import { freshDatabase, memoryLogger, startApp, testConfig, testDatabaseUrl } from './helpers.js'

export interface Reply {
  status: number
  body: any
  headers: Headers
}

export interface CallOptions {
  body?: unknown
  form?: FormData
  token?: string
  lang?: string
  headers?: Record<string, string>
}

export const PASSWORD = 'correct horse'

export async function startHarness(options: { push?: SendPush | null } = {}) {
  const url = testDatabaseUrl()
  await freshDatabase(url)
  const mediaDir = await mkdtemp(path.join(tmpdir(), 'saba-test-'))
  const config = testConfig({ DATABASE_URL: url, MEDIA_DIR: mediaDir })
  const pool: Pool = createPool(url, 4)
  // Products wait in Saba's queue, as the tests were written for; the switch
  // that skips it (migration 0013, on in production) has its own test.
  await exec(pool, "UPDATE app_settings SET value = 'false' WHERE name = 'auto_approve_products'")
  const inbox = new Map<string, string>()
  const app = await startApp({
    config,
    pool,
    logger: memoryLogger().logger,
    sms: async (phone, code) => void inbox.set(phone, code),
    ...(options.push !== undefined && { push: options.push }),
  })

  async function call(method: string, route: string, options: CallOptions = {}): Promise<Reply> {
    const response = await fetch(`${app.url}/api/v1${route}`, {
      method,
      headers: {
        ...(options.body !== undefined && { 'content-type': 'application/json' }),
        ...(options.token && { authorization: `Bearer ${options.token}` }),
        ...(options.lang && { 'accept-language': options.lang }),
        ...options.headers,
      },
      body: options.form ?? (options.body === undefined ? undefined : JSON.stringify(options.body)),
    })
    return { status: response.status, body: await response.json(), headers: response.headers }
  }

  let next = 0
  function freshPhone(): string {
    next += 1
    return `+964780${String(10_000_000 + next).slice(1)}`
  }

  async function proofFor(phone: string): Promise<string> {
    await exec(pool, 'DELETE FROM otp_challenges')
    const sent = await call('POST', '/auth/otp/send', { body: { phone, purpose: 'SIGN_UP' } })
    assert.equal(sent.status, 200, JSON.stringify(sent.body))
    const verified = await call('POST', '/auth/otp/verify', { body: { phone, code: inbox.get(phone) } })
    return verified.body.data.verificationToken
  }

  async function signUpShopper(governorate = 'BAGHDAD') {
    const phone = freshPhone()
    const reply = await call('POST', '/auth/register/customer', {
      body: { fullName: 'Amina Saleh', password: PASSWORD, phone, phoneVerificationToken: await proofFor(phone), governorate },
    })
    assert.equal(reply.status, 200, JSON.stringify(reply.body))
    return { phone, token: reply.body.data.accessToken as string, user: reply.body.data.user }
  }

  async function signUpStore(storeName: string, governorate = 'BAGHDAD', extra: Record<string, unknown> = {}) {
    const phone = freshPhone()
    const reply = await call('POST', '/auth/register/merchant', {
      body: {
        fullName: 'Omar Al-Sayed',
        password: PASSWORD,
        phone,
        phoneVerificationToken: await proofFor(phone),
        governorate,
        storeName,
        businessAddress: 'Karrada',
        ...extra,
      },
    })
    assert.equal(reply.status, 200, JSON.stringify(reply.body))
    return {
      phone,
      token: reply.body.data.accessToken as string,
      user: reply.body.data.user,
      storeId: reply.body.data.user.merchant.id as string,
      ownerId: Number(reply.body.data.user.id),
    }
  }

  let admins = 0
  async function signInAdmin(): Promise<string> {
    admins += 1
    const email = `admin${admins}@saba.app`
    await exec(pool, "INSERT INTO users (role, full_name, phone, email, password_hash) VALUES ('ADMIN', 'Saba admin', ?, ?, ?)", [
      freshPhone(),
      email,
      await hashPassword(PASSWORD),
    ])
    const reply = await call('POST', '/auth/login', { body: { email, password: PASSWORD } })
    assert.equal(reply.status, 200, JSON.stringify(reply.body))
    return reply.body.data.accessToken
  }

  return {
    pool,
    mediaDir,
    /** The API's own address, for what `call` can't do (a live stream). */
    url: `${app.url}/api/v1`,
    call,
    freshPhone,
    signUpShopper,
    signUpStore,
    signInAdmin,
    async close() {
      await app.close()
      await pool.end()
      await rm(mediaDir, { recursive: true, force: true })
    },
  }
}

export type Harness = Awaited<ReturnType<typeof startHarness>>

/** The smallest real PNG: a 1×1 pixel. */
export const PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  'base64',
)
