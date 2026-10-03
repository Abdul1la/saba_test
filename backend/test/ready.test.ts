// S9 Ready to host (BACKEND_PLAN.md §7, §12): every route the server answers
// is in its OpenAPI document; a production start with a secret missing refuses
// to run, and with everything present it listens; housekeeping deletes only
// what nothing reads any more.
import assert from 'node:assert/strict'
import { spawn, spawnSync } from 'node:child_process'
import { once } from 'node:events'
import { createServer, type AddressInfo } from 'node:net'
import { tmpdir } from 'node:os'
import { fileURLToPath } from 'node:url'
import { after, before, describe, test } from 'node:test'
import type { Express } from 'express'
import { createApp } from '../src/app.js'
import { createPool } from '../src/db/pool.js'
import { exec, rows } from '../src/db/sql.js'
import { housekeeping } from '../src/lib/housekeeping.js'
import { startHarness, type Harness } from './api.js'
import { DEAD_DATABASE_URL, memoryLogger, testConfig } from './helpers.js'

/** Every method and path the API's router answers, written as the OpenAPI document writes them. */
function servedRoutes(app: Express): string[] {
  type Layer = { route?: { path: string; methods: Record<string, boolean> }; handle?: { stack?: Layer[] } }
  const routes: string[] = []
  for (const mounted of (app.router as unknown as { stack: Layer[] }).stack) {
    for (const layer of mounted.handle?.stack ?? []) {
      if (!layer.route) continue
      for (const method of Object.keys(layer.route.methods)) {
        routes.push(`${method.toUpperCase()} ${layer.route.path.replace(/:(\w+)/g, '{$1}')}`)
      }
    }
  }
  return routes
}

test('every route the server answers is in its OpenAPI document, and every documented one is answered', async () => {
  const pool = createPool(DEAD_DATABASE_URL, 1)
  const app = createApp({ config: testConfig(), pool, logger: memoryLogger().logger })
  const server = app.listen(0, '127.0.0.1')
  try {
    await once(server, 'listening')
    const { port } = server.address() as AddressInfo
    const document = (await (await fetch(`http://127.0.0.1:${port}/api/v1/openapi.json`)).json()) as { paths: Record<string, Record<string, unknown>> }
    const documented = Object.entries(document.paths).flatMap(([path, operations]) => Object.keys(operations).map((method) => `${method.toUpperCase()} ${path}`))
    const served = servedRoutes(app)
    assert.ok(served.length > 130, `found ${served.length} routes`)
    assert.deepEqual([...served].sort(), [...documented].sort())
    // No path answered twice by accident.
    assert.equal(new Set(served).size, served.length)
  } finally {
    server.close()
    await pool.end()
  }
})

// ----------------------------------------------------------- production ---

describe('starting in production', () => {
  const tsx = import.meta.resolve('tsx')
  const serverFile = fileURLToPath(new URL('../src/server.ts', import.meta.url))
  // Nothing from backend/.env: the server starts in a folder without one.
  const production = {
    NODE_ENV: 'production',
    DATABASE_URL: DEAD_DATABASE_URL,
    JWT_SECRET: 'jwt-secret-for-the-start-up-test-000000000',
    OTP_SECRET: 'otp-secret-for-the-start-up-test-000000000',
    CORS_ORIGINS: 'https://admin.saba.iq',
    TRUST_PROXY: '1',
    MEDIA_STORAGE: 's3',
    S3_ENDPOINT: 'https://fra1.digitaloceanspaces.com',
    S3_REGION: 'fra1',
    S3_BUCKET: 'saba-media',
    S3_ACCESS_KEY_ID: 'DO00EXAMPLEKEY',
    S3_SECRET_ACCESS_KEY: 'spaces-secret-for-tests-0000',
    MEDIA_BASE_URL: 'https://saba-media.fra1.cdn.digitaloceanspaces.com',
    SMS_PROVIDER: 'otpiq',
    OTPIQ_API_KEY: 'sk_live_startuptest0123456789',
    SystemRoot: process.env.SystemRoot,
    PATH: process.env.PATH,
  }
  const secrets = [production.JWT_SECRET, production.OTP_SECRET, production.OTPIQ_API_KEY, production.S3_SECRET_ACCESS_KEY]

  test('a secret missing: it refuses to run, naming the variable and printing no secret', () => {
    for (const missing of ['JWT_SECRET', 'OTP_SECRET', 'OTPIQ_API_KEY', 'CORS_ORIGINS', 'TRUST_PROXY', 'S3_SECRET_ACCESS_KEY'] as const) {
      const run = spawnSync(process.execPath, ['--import', tsx, serverFile], {
        cwd: tmpdir(),
        env: { ...production, [missing]: undefined },
        encoding: 'utf8',
        timeout: 60_000,
      })
      assert.equal(run.status, 1, `${missing}: ${run.stderr}`)
      assert.match(run.stderr, new RegExp(missing))
      for (const secret of secrets) assert.ok(!`${run.stdout}${run.stderr}`.includes(secret), `${missing}: a secret was printed`)
    }
  })

  test('everything present but Firebase: it listens, with the docs off, and says push is off (S10)', async () => {
    const free = createServer().listen(0, '127.0.0.1')
    await once(free, 'listening')
    const { port } = free.address() as AddressInfo
    await new Promise((resolve) => free.close(resolve))

    const child = spawn(process.execPath, ['--import', tsx, serverFile], { cwd: tmpdir(), env: { ...production, PORT: String(port) } })
    try {
      let output = ''
      await new Promise<void>((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error(`no start in 60 s: ${output}`)), 60_000)
        child.stdout.on('data', (chunk: Buffer) => {
          output += String(chunk)
          // Written just after "listening": push never stops a start, it says so.
          if (output.includes('Push notifications are OFF')) {
            clearTimeout(timer)
            resolve()
          }
        })
        child.on('exit', (code) => reject(new Error(`exited ${code}: ${output}`)))
      })
      assert.match(output, /Saba API listening/)
      assert.match(output, /"why":"PUSH_PROVIDER is not set"/)
      assert.match(output, /"env":"production"/)
      assert.equal((await fetch(`http://127.0.0.1:${port}/api/v1/openapi.json`)).status, 404)
      assert.ok(!secrets.some((secret) => output.includes(secret)), 'a secret was printed')
    } finally {
      child.kill()
    }
  })
})

// ---------------------------------------------------------- housekeeping ---

describe('housekeeping', () => {
  let h: Harness
  before(async () => {
    h = await startHarness()
  })
  after(() => h.close())

  test('deletes request keys after 24 hours, SMS codes after a day, refresh tokens once expired; nothing else', async () => {
    const who = await h.signUpShopper()
    const id = Number(who.user.id)
    const hoursAgo = (hours: number) => new Date(Date.now() - hours * 3_600_000)
    for (const [key, at] of [['old-key', hoursAgo(25)], ['new-key', hoursAgo(23)]] as const) {
      await exec(h.pool, 'INSERT INTO idempotency_keys (user_id, idem_key, request_hash, response, created_at) VALUES (?, ?, ?, ?, ?)', [
        id,
        key,
        Buffer.alloc(32),
        '{}',
        at,
      ])
    }
    await exec(h.pool, 'DELETE FROM otp_challenges')
    for (const at of [hoursAgo(25), hoursAgo(2)]) {
      await exec(h.pool, "INSERT INTO otp_challenges (phone, purpose, code_hash, expires_at, created_at) VALUES ('+9647701230000', 'SIGN_UP', ?, ?, ?)", [
        Buffer.alloc(32),
        new Date(at.getTime() + 300_000),
        at,
      ])
    }
    const live = await rows<{ id: number }>(h.pool, 'SELECT id FROM refresh_tokens WHERE user_id = ?', [id])
    await exec(h.pool, 'INSERT INTO refresh_tokens (user_id, token_hash, family_id, expires_at) VALUES (?, ?, ?, ?)', [
      id,
      Buffer.alloc(32, 7),
      Buffer.alloc(16, 7),
      hoursAgo(1),
    ])

    assert.deepEqual(await housekeeping(h.pool), { requestKeys: 1, smsCodes: 1, refreshTokens: 1 })
    assert.deepEqual(
      (await rows<{ idem_key: string }>(h.pool, 'SELECT idem_key FROM idempotency_keys WHERE user_id = ?', [id])).map((row) => row.idem_key),
      ['new-key'],
    )
    assert.equal((await rows(h.pool, 'SELECT id FROM otp_challenges')).length, 1)
    // The sign-in's own token is untouched, and still works.
    assert.deepEqual(await rows<{ id: number }>(h.pool, 'SELECT id FROM refresh_tokens WHERE user_id = ?', [id]), live)
    assert.equal((await h.call('GET', '/customers/me', { token: who.token })).status, 200)
    // A second run finds nothing.
    assert.deepEqual(await housekeeping(h.pool), { requestKeys: 0, smsCodes: 0, refreshTokens: 0 })
  })
})
