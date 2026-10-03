import assert from 'node:assert/strict'
import { mkdtemp, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'
import { ConfigError, loadConfig } from '../src/config.js'
import { testDatabaseUrl } from './helpers.js'

const minimal = {
  DATABASE_URL: 'mysql://saba:pw@127.0.0.1:3306/saba',
  JWT_SECRET: 'a-jwt-secret-of-at-least-32-characters',
  OTP_SECRET: 'an-otp-secret-of-at-least-32-characters',
}

test('the two secrets are required, and short ones are refused without printing them', () => {
  for (const name of ['JWT_SECRET', 'OTP_SECRET'] as const) {
    assert.throws(() => loadConfig({ ...minimal, [name]: undefined }), new RegExp(name))
    assert.throws(
      () => loadConfig({ ...minimal, [name]: 'short-secret-value' }),
      (error: unknown) => {
        assert.ok(error instanceof ConfigError)
        assert.match(error.message, new RegExp(name))
        assert.doesNotMatch(error.message, /short-secret-value/)
        return true
      },
    )
  }
})

test('the defaults are what the app expects: port 3000, /api/v1', () => {
  const config = loadConfig(minimal)
  assert.equal(config.env, 'development')
  assert.equal(config.port, 3000)
  assert.equal(config.apiPrefix, '/api/v1')
  assert.equal(config.dbPoolSize, 10)
  assert.equal(config.docsEnabled, true)
  assert.equal(config.trustProxy, false)
  assert.deepEqual(config.corsOrigins, [])
})

test('a missing database address stops the start, naming the variable', () => {
  assert.throws(() => loadConfig({}), (error: unknown) => {
    assert.ok(error instanceof ConfigError)
    assert.match(error.message, /DATABASE_URL/)
    return true
  })
})

test('a bad value is named, but its value is never printed', () => {
  assert.throws(
    () => loadConfig({ DATABASE_URL: 'postgres://user:hunter2-secret@host/db' }),
    (error: unknown) => {
      assert.ok(error instanceof ConfigError)
      assert.match(error.message, /DATABASE_URL/)
      assert.doesNotMatch(error.message, /hunter2-secret/)
      return true
    },
  )
  assert.throws(() => loadConfig({ ...minimal, PORT: 'abc' }), /PORT/)
  assert.throws(() => loadConfig({ ...minimal, TRUST_PROXY: 'yes' }), /TRUST_PROXY/)
  assert.throws(() => loadConfig({ ...minimal, API_PREFIX: 'api/v1' }), /API_PREFIX/)
})

const otpiq = { SMS_PROVIDER: 'otpiq', OTPIQ_API_KEY: 'sk_live_0123456789abcdef' }
// Photos in production: object storage (the reviewer's item 5).
const s3 = { MEDIA_STORAGE: 's3', S3_ENDPOINT: 'https://fra1.digitaloceanspaces.com', S3_REGION: 'fra1', S3_BUCKET: 'saba-media', S3_ACCESS_KEY_ID: 'DO00EXAMPLEKEY', S3_SECRET_ACCESS_KEY: 'spaces-secret-for-tests-0000', MEDIA_BASE_URL: 'https://saba-media.fra1.cdn.digitaloceanspaces.com' }

test('push never stops a start: the log while developing, Firebase from its file, else off and why (S10)', async (t) => {
  const production = { ...minimal, ...otpiq, NODE_ENV: 'production', CORS_ORIGINS: 'https://saba.iq', TRUST_PROXY: '1', ...s3 }
  assert.deepEqual(loadConfig(minimal).push, { provider: 'log' })
  assert.deepEqual(loadConfig(production).push, { provider: 'off', why: 'PUSH_PROVIDER is not set' })
  assert.deepEqual(loadConfig({ ...production, PUSH_PROVIDER: 'log' }).push, { provider: 'off', why: 'PUSH_PROVIDER=log is for development' })
  assert.deepEqual(loadConfig({ ...production, PUSH_PROVIDER: 'fcm' }).push, { provider: 'off', why: 'FCM_SERVICE_ACCOUNT_FILE is not set' })

  const dir = await mkdtemp(join(tmpdir(), 'saba-fcm-'))
  t.after(() => rm(dir, { recursive: true, force: true }))
  const broken = join(dir, 'broken.json')
  await writeFile(broken, JSON.stringify({ project_id: 'saba-app', client_email: 'push@saba-app.iam.gserviceaccount.com' }))
  const missing = join(dir, 'missing.json')
  for (const file of [broken, missing]) {
    assert.deepEqual(loadConfig({ ...production, PUSH_PROVIDER: 'fcm', FCM_SERVICE_ACCOUNT_FILE: file }).push, {
      provider: 'off',
      why: 'FCM_SERVICE_ACCOUNT_FILE is not a readable Firebase service-account file',
    })
  }
  const key = '-----BEGIN PRIVATE KEY-----\nMIIEvQ\n-----END PRIVATE KEY-----\n'
  const account = join(dir, 'account.json')
  await writeFile(account, JSON.stringify({ project_id: 'saba-app', client_email: 'push@saba-app.iam.gserviceaccount.com', private_key: key }))
  assert.deepEqual(loadConfig({ ...production, PUSH_PROVIDER: 'fcm', FCM_SERVICE_ACCOUNT_FILE: account }).push, {
    provider: 'fcm',
    projectId: 'saba-app',
    clientEmail: 'push@saba-app.iam.gserviceaccount.com',
    privateKey: key,
    tokenUrl: 'https://oauth2.googleapis.com/token',
  })
  // SMS stays required: a code sent nowhere is a real failure.
  assert.throws(() => loadConfig({ ...production, SMS_PROVIDER: 'log' }), /SMS_PROVIDER: must be otpiq in production/)
})

test('SMS: the log while developing; OTPIQ needs its key, and production needs OTPIQ', () => {
  assert.deepEqual(loadConfig(minimal).sms, { provider: 'log' })
  assert.throws(() => loadConfig({ ...minimal, SMS_PROVIDER: 'otpiq' }), /OTPIQ_API_KEY/)
  assert.throws(
    () => loadConfig({ ...minimal, SMS_PROVIDER: 'otpiq', OTPIQ_API_KEY: 'not-a-key-secret' }),
    (error: unknown) => error instanceof ConfigError && /OTPIQ_API_KEY/.test(error.message) && !/not-a-key-secret/.test(error.message),
  )
  assert.deepEqual(loadConfig({ ...minimal, ...otpiq, OTPIQ_CHANNEL: 'whatsapp-sms' }).sms, {
    provider: 'otpiq',
    apiKey: 'sk_live_0123456789abcdef',
    channel: 'whatsapp-sms',
    senderId: undefined,
    baseUrl: 'https://api.otpiq.com/api',
  })
  assert.throws(
    () => loadConfig({ ...minimal, NODE_ENV: 'production', CORS_ORIGINS: 'https://saba.iq' }),
    /SMS_PROVIDER: must be otpiq in production/,
  )
})

test('production needs its CORS list, and keeps the docs off unless asked', () => {
  assert.throws(() => loadConfig({ ...minimal, ...otpiq, NODE_ENV: 'production' }), /CORS_ORIGINS/)
  const config = loadConfig({
    ...minimal,
    ...otpiq,
    NODE_ENV: 'production',
    CORS_ORIGINS: 'https://admin.saba.iq, https://saba.iq',
    TRUST_PROXY: '1',
    ...s3,
  })
  assert.deepEqual(config.corsOrigins, ['https://admin.saba.iq', 'https://saba.iq'])
  assert.equal(config.docsEnabled, false)
  assert.equal(
    loadConfig({ ...minimal, ...otpiq, NODE_ENV: 'production', CORS_ORIGINS: 'https://saba.iq', TRUST_PROXY: '1', ...s3, DOCS_ENABLED: 'true' })
      .docsEnabled,
    true,
  )
})

test('production needs two different secrets, and says so without printing them', () => {
  const same = 'the-same-secret-of-at-least-32-characters'
  const production = { ...minimal, ...otpiq, NODE_ENV: 'production', CORS_ORIGINS: 'https://saba.iq', TRUST_PROXY: '1', ...s3 }
  assert.throws(
    () => loadConfig({ ...production, JWT_SECRET: same, OTP_SECRET: same }),
    (error: unknown) => error instanceof ConfigError && /OTP_SECRET: must differ/.test(error.message) && !error.message.includes(same),
  )
  assert.equal(loadConfig(production).env, 'production')
  // While developing, the same value still starts.
  assert.equal(loadConfig({ ...minimal, JWT_SECRET: same, OTP_SECRET: same }).env, 'development')
})

test("TRUST_PROXY: the number of proxies in front; required in production, and never 'true' there (the reviewer's item 4)", () => {
  assert.equal(loadConfig(minimal).trustProxy, false)
  assert.equal(loadConfig({ ...minimal, TRUST_PROXY: '1' }).trustProxy, 1)
  assert.equal(loadConfig({ ...minimal, TRUST_PROXY: 'true' }).trustProxy, true)
  assert.equal(loadConfig({ ...minimal, TRUST_PROXY: 'false' }).trustProxy, false)
  const production = { ...minimal, ...otpiq, NODE_ENV: 'production', CORS_ORIGINS: 'https://saba.iq' }
  assert.throws(() => loadConfig(production), /TRUST_PROXY: required in production/)
  assert.throws(() => loadConfig({ ...production, TRUST_PROXY: 'true' }), /TRUST_PROXY: true trusts any address/)
  assert.equal(loadConfig({ ...production, ...s3, TRUST_PROXY: '1' }).trustProxy, 1)
  assert.equal(loadConfig({ ...production, ...s3, TRUST_PROXY: 'false' }).trustProxy, false)
})

test("DATABASE_CA_FILE: a managed database's certificate is read at start; one that isn't there stops it", async (t) => {
  const dir = await mkdtemp(join(tmpdir(), 'saba-ca-'))
  t.after(() => rm(dir, { recursive: true, force: true }))
  const pem = '-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\n'
  const file = join(dir, 'ca.pem')
  await writeFile(file, pem)
  const text = join(dir, 'notes.txt')
  await writeFile(text, 'not a certificate')
  assert.equal(loadConfig(minimal).databaseCa, undefined)
  assert.equal(loadConfig({ ...minimal, DATABASE_CA_FILE: file }).databaseCa, pem)
  for (const bad of [join(dir, 'missing.pem'), text]) {
    assert.throws(() => loadConfig({ ...minimal, DATABASE_CA_FILE: bad }), /DATABASE_CA_FILE: not a readable certificate file/)
  }
})

test("photos: the disk while developing; object storage required in production, with every setting it needs (the reviewer's item 5)", () => {
  assert.deepEqual(loadConfig(minimal).media, { storage: 'disk' })
  // The empty lines .env.example ships with are "not set": a laptop starts.
  const empty = { S3_ENDPOINT: '', S3_REGION: '', S3_BUCKET: '', S3_ACCESS_KEY_ID: '', S3_SECRET_ACCESS_KEY: '' }
  assert.deepEqual(loadConfig({ ...minimal, ...empty, MEDIA_STORAGE: 'disk' }).media, { storage: 'disk' })
  assert.throws(() => loadConfig({ ...minimal, ...empty, MEDIA_STORAGE: 's3' }), /S3_ENDPOINT: required when MEDIA_STORAGE is s3/)
  const production = { ...minimal, ...otpiq, NODE_ENV: 'production', CORS_ORIGINS: 'https://saba.iq', TRUST_PROXY: '1' }
  assert.throws(() => loadConfig(production), /MEDIA_STORAGE: must be s3 in production/)
  assert.deepEqual(loadConfig({ ...production, ...s3 }).media, {
    storage: 's3',
    endpoint: 'https://fra1.digitaloceanspaces.com',
    region: 'fra1',
    bucket: 'saba-media',
    accessKeyId: 'DO00EXAMPLEKEY',
    secretAccessKey: 'spaces-secret-for-tests-0000',
  })
  for (const name of ['S3_ENDPOINT', 'S3_REGION', 'S3_BUCKET', 'S3_ACCESS_KEY_ID', 'S3_SECRET_ACCESS_KEY', 'MEDIA_BASE_URL']) {
    assert.throws(
      () => loadConfig({ ...minimal, ...s3, [name]: undefined }),
      (error: unknown) =>
        error instanceof ConfigError && error.message.includes(`${name}: required when MEDIA_STORAGE is s3`) && !error.message.includes(s3.S3_SECRET_ACCESS_KEY),
    )
  }
  assert.throws(() => loadConfig({ ...minimal, ...s3, S3_ENDPOINT: 'https://fra1.digitaloceanspaces.com/saba-media' }), /S3_ENDPOINT/)
})

test('the tests refuse a database whose name does not end in _test', () => {
  assert.throws(
    () => testDatabaseUrl({ DATABASE_URL_TEST: 'mysql://saba:pw@127.0.0.1:3306/saba' }),
    /must end in _test/,
  )
  assert.throws(() => testDatabaseUrl({}), /DATABASE_URL_TEST is not set/)
  assert.equal(
    testDatabaseUrl({ DATABASE_URL_TEST: 'mysql://saba:pw@127.0.0.1:3306/saba_test' }),
    'mysql://saba:pw@127.0.0.1:3306/saba_test',
  )
})
