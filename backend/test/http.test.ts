import assert from 'node:assert/strict'
import { after, before, describe, test } from 'node:test'
import type { Request, Response } from 'express'
import { z } from 'zod'
import { createPool } from '../src/db/pool.js'
import { errorHandler } from '../src/http/error-handler.js'
import { AppError } from '../src/http/errors.js'
import { parseInput } from '../src/http/validate.js'
import { DEAD_DATABASE_URL, memoryLogger, startApp, testConfig } from './helpers.js'

// The app with a database that is down: everything here works without MySQL.
describe('the HTTP layer', () => {
  const { logger, lines } = memoryLogger()
  const pool = createPool(DEAD_DATABASE_URL, 1)
  let app: Awaited<ReturnType<typeof startApp>>

  before(async () => {
    app = await startApp({ config: testConfig(), pool, logger })
  })
  after(async () => {
    await app.close()
    await pool.end()
  })

  test('an unknown route is a 404 in the contract shape, in the asked language', async () => {
    const english = await fetch(`${app.url}/api/v1/nothing-here`)
    assert.equal(english.status, 404)
    assert.deepEqual(await english.json(), {
      success: false,
      code: 'NOT_FOUND_ERROR',
      message: 'Not found.',
    })
    const arabic = await fetch(`${app.url}/api/v1/nothing-here`, { headers: { 'Accept-Language': 'ar' } })
    assert.equal((await arabic.json()).message, 'غير موجود.')
  })

  test("Google Play's account-deletion page: public, a web page in both languages", async () => {
    const page = await fetch(`${app.url}/delete-account`)
    assert.equal(page.status, 200)
    assert.match(page.headers.get('content-type') ?? '', /^text\/html/)
    const text = await page.text()
    assert.match(text, /Delete your Saba account/)
    assert.match(text, /حذف حسابك في سبأ/)
  })

  test("the privacy policy the app stores link to: public, both languages, pointing at the deletion page (the reviewer's item 20)", async () => {
    const page = await fetch(`${app.url}/privacy`)
    assert.equal(page.status, 200)
    assert.match(page.headers.get('content-type') ?? '', /^text\/html/)
    const text = await page.text()
    assert.match(text, /Saba privacy policy/)
    assert.match(text, /سياسة الخصوصية في سبأ/)
    assert.ok(text.includes('href="/delete-account"'))
  })

  test('a body that is not JSON is a 400 VALIDATION_ERROR', async () => {
    const response = await fetch(`${app.url}/api/v1/health`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: '{"broken": ',
    })
    assert.equal(response.status, 400)
    assert.deepEqual(await response.json(), {
      success: false,
      code: 'VALIDATION_ERROR',
      message: 'The request could not be read.',
    })
  })

  test('a body over 1 MB is refused with 413', async () => {
    const response = await fetch(`${app.url}/api/v1/health`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: 'x'.repeat(1024 * 1024 + 10) }),
    })
    assert.equal(response.status, 413)
    assert.equal((await response.json()).code, 'VALIDATION_ERROR')
  })

  test('health says 503 when the database does not answer, in the asked language', async () => {
    const response = await fetch(`${app.url}/api/v1/health`, { headers: { 'Accept-Language': 'ar' } })
    assert.equal(response.status, 503)
    assert.deepEqual(await response.json(), {
      success: false,
      code: 'EXTERNAL_SERVICE_ERROR',
      message: 'الخدمة غير متاحة الآن. حاول مرة أخرى.',
    })
  })

  test('a token never reaches the log', async () => {
    lines.length = 0
    await fetch(`${app.url}/api/v1/nothing-here`, {
      headers: { Authorization: 'Bearer secret-token-123', Cookie: 'session=secret-cookie-456' },
    })
    const logged = lines.join('')
    assert.match(logged, /nothing-here/, 'the request was logged')
    assert.doesNotMatch(logged, /secret-token-123/)
    assert.doesNotMatch(logged, /secret-cookie-456/)
    assert.match(logged, /\[Redacted\]/)
  })

  test('every answer carries a request id: the app\'s own, or a new one', async () => {
    const theirs = await fetch(`${app.url}/api/v1/nothing-here`, {
      headers: { 'X-Request-Id': 'app-request-0001' },
    })
    assert.equal(theirs.headers.get('x-request-id'), 'app-request-0001')
    const made = await fetch(`${app.url}/api/v1/nothing-here`)
    assert.match(made.headers.get('x-request-id') ?? '', /^[0-9a-f-]{36}$/)
    const odd = await fetch(`${app.url}/api/v1/nothing-here`, { headers: { 'X-Request-Id': 'x"><script>' } })
    assert.match(odd.headers.get('x-request-id') ?? '', /^[0-9a-f-]{36}$/)
  })

  test('security headers are set, and nothing names the server software', async () => {
    const response = await fetch(`${app.url}/api/v1/nothing-here`)
    assert.equal(response.headers.get('x-content-type-options'), 'nosniff')
    assert.equal(response.headers.get('x-powered-by'), null)
  })

  test('while developing, any localhost port may call (Flutter web picks a new one each run)', async () => {
    const response = await fetch(`${app.url}/api/v1/nothing-here`, { headers: { Origin: 'http://localhost:61234' } })
    assert.equal(response.headers.get('access-control-allow-origin'), 'http://localhost:61234')
    const stranger = await fetch(`${app.url}/api/v1/nothing-here`, { headers: { Origin: 'https://evil.example' } })
    assert.equal(stranger.headers.get('access-control-allow-origin'), null)
  })

  test('a browser on another origin may read Retry-After (how long a 429 waits) and the request id', async () => {
    const response = await fetch(`${app.url}/api/v1/nothing-here`, { headers: { Origin: 'http://localhost:5174' } })
    const exposed = (response.headers.get('access-control-expose-headers') ?? '').split(',').map((name) => name.trim().toLowerCase())
    assert.ok(exposed.includes('retry-after'), `exposed: ${exposed.join(', ')}`)
    assert.ok(exposed.includes('x-request-id'), `exposed: ${exposed.join(', ')}`)
  })

  test('the OpenAPI document lists the routes, and the docs page is served', async () => {
    const document = await (await fetch(`${app.url}/api/v1/openapi.json`)).json()
    assert.equal(document.openapi, '3.1.0')
    assert.ok(document.paths['/health']?.get, 'GET /health is documented')
    const docs = await fetch(`${app.url}/api/v1/docs/`)
    assert.equal(docs.status, 200)
    assert.match(await docs.text(), /swagger-ui/i)
  })
})

describe('in production', () => {
  const pool = createPool(DEAD_DATABASE_URL, 1)
  let app: Awaited<ReturnType<typeof startApp>>

  before(async () => {
    const config = testConfig({
      NODE_ENV: 'production',
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
      OTPIQ_API_KEY: 'sk_dev_0123456789abcdef',
    })
    app = await startApp({ config, pool, logger: memoryLogger().logger })
  })
  after(async () => {
    await app.close()
    await pool.end()
  })

  test('only listed origins may call; localhost is not one of them', async () => {
    const listed = await fetch(`${app.url}/api/v1/nothing-here`, { headers: { Origin: 'https://admin.saba.iq' } })
    assert.equal(listed.headers.get('access-control-allow-origin'), 'https://admin.saba.iq')
    const local = await fetch(`${app.url}/api/v1/nothing-here`, { headers: { Origin: 'http://localhost:5173' } })
    assert.equal(local.headers.get('access-control-allow-origin'), null)
  })

  test('the docs are off', async () => {
    assert.equal((await fetch(`${app.url}/api/v1/openapi.json`)).status, 404)
    assert.equal((await fetch(`${app.url}/api/v1/docs/`)).status, 404)
  })
})

describe('input checks', () => {
  const Body = z.object({
    fullName: z.string().max(50),
    governorate: z.string({ error: 'field.invalid' }),
    count: z.number().min(1).optional(),
  })

  function fieldsOf(value: unknown): Record<string, string | undefined> {
    try {
      parseInput(Body, value)
    } catch (error) {
      assert.ok(error instanceof AppError)
      assert.equal(error.status, 422)
      assert.equal(error.code, 'VALIDATION_ERROR')
      return Object.fromEntries(Object.entries(error.fields ?? {}).map(([field, { key }]) => [field, key]))
    }
    assert.fail('expected the input to be refused')
  }

  test('a good body passes through', () => {
    assert.deepEqual(parseInput(Body, { fullName: 'Amina', governorate: 'BAGHDAD' }), {
      fullName: 'Amina',
      governorate: 'BAGHDAD',
    })
  })

  test('each wrong field is named, with a key the error handler translates', () => {
    assert.deepEqual(fieldsOf({ governorate: 'BAGHDAD' }), { fullName: 'field.required' })
    assert.deepEqual(fieldsOf({ fullName: 'x'.repeat(51), governorate: 'BAGHDAD', count: 0 }), {
      fullName: 'field.tooLong',
      count: 'field.tooSmall',
    })
    // A schema's own key wins over the generic one.
    assert.deepEqual(fieldsOf({ fullName: 'Amina', governorate: 7 }), { governorate: 'field.invalid' })
    assert.deepEqual(fieldsOf('not an object'), { _: 'field.invalid' })
  })

  test('field errors come out in Arabic for an Arabic reader, never zod\'s English', () => {
    let sent: unknown
    const res = {
      headersSent: false,
      status() {
        return this
      },
      json(body: unknown) {
        sent = body
      },
    } as unknown as Response
    let thrown: unknown
    try {
      parseInput(Body, { fullName: 'x'.repeat(51) })
    } catch (error) {
      thrown = error
    }
    errorHandler(thrown, { lang: 'ar' } as Request, res, () => {})
    assert.deepEqual(sent, {
      success: false,
      code: 'VALIDATION_ERROR',
      message: 'تحقّق من الحقول المحدّدة.',
      errors: { fullName: 'استخدم 50 حرفاً على الأكثر.', governorate: 'مطلوب.' },
    })
  })
})

test('an unexpected error is a plain 500: no message, stack or SQL leaves the server', () => {
  let status = 0
  let sent: unknown
  let logged: unknown
  const res = {
    headersSent: false,
    status(code: number) {
      status = code
      return this
    },
    json(body: unknown) {
      sent = body
    },
  } as unknown as Response
  const req = { lang: 'en', log: { error: (details: unknown) => (logged = details) } } as unknown as Request
  const error = new Error("ER_BAD_FIELD_ERROR: Unknown column 'secret_column' in SELECT * FROM users")
  errorHandler(error, req, res, () => {})
  assert.equal(status, 500)
  assert.deepEqual(sent, { success: false, message: 'Something went wrong. Please try again.' })
  assert.doesNotMatch(JSON.stringify(sent), /secret_column/)
  assert.deepEqual(logged, { err: error }, 'the details go to the log instead')
})
