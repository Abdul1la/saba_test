// SMS codes through OTPIQ (Q11), against a stand-in for its API, and what the
// sign-up route does when a code can't be sent.
import assert from 'node:assert/strict'
import { once } from 'node:events'
import { createServer, type IncomingMessage } from 'node:http'
import type { AddressInfo } from 'node:net'
import { after, before, describe, test, type TestContext } from 'node:test'
import { createPool, type Pool } from '../src/db/pool.js'
import { one } from '../src/db/sql.js'
import { otpiqSms, otpiqText, SmsError } from '../src/lib/sms.js'
import { freshDatabase, memoryLogger, startApp, testConfig, testDatabaseUrl } from './helpers.js'

const KEY = 'sk_dev_0123456789abcdef'

/** OTPIQ's API, answering [reply] and keeping what it was sent. */
async function fakeOtpiq(t: TestContext, reply: { status: number; body: unknown }) {
  const seen: { path: string; auth: string | undefined; body: any }[] = []
  const server = createServer(async (req: IncomingMessage, res) => {
    let text = ''
    for await (const chunk of req) text += chunk
    seen.push({ path: req.url ?? '', auth: req.headers.authorization, body: JSON.parse(text) })
    res.writeHead(reply.status, { 'content-type': 'application/json' }).end(JSON.stringify(reply.body))
  })
  server.listen(0, '127.0.0.1')
  await once(server, 'listening')
  const { port } = server.address() as AddressInfo
  // Closed even when a test fails: an open server keeps the test process alive for ever.
  t.after(() => {
    server.closeAllConnections()
    server.close()
  })
  return { baseUrl: `http://127.0.0.1:${port}/api`, seen }
}

describe('the OTPIQ sender', () => {
  test('sends a verification code: the key as Bearer, the number without +, the channel', async (t) => {
    const otpiq = await fakeOtpiq(t, { status: 200, body: { message: 'SMS task created successfully', smsId: 'sms-1', remainingCredit: 14800 } })
    const { logger, lines } = memoryLogger()
    await otpiqSms({ apiKey: KEY, baseUrl: otpiq.baseUrl, channel: 'whatsapp-sms', logger })('+9647701234567', '482913')
    assert.deepEqual(otpiq.seen, [
      {
        path: '/api/sms',
        auth: `Bearer ${KEY}`,
        body: { phoneNumber: '9647701234567', smsType: 'verification', verificationCode: '482913', provider: 'whatsapp-sms' },
      },
    ])
    // Neither the key nor the code is ever written to the log.
    assert.ok(!lines.join('').includes(KEY))
    assert.ok(!lines.join('').includes('482913'))
  })

  test("sends a notice in Saba's own words as a custom message, from the sender ID when there is one", async (t) => {
    const otpiq = await fakeOtpiq(t, { status: 200, body: { message: 'SMS task created successfully', smsId: 'sms-2', remainingCredit: 14700 } })
    const logger = memoryLogger().logger
    await otpiqText({ apiKey: KEY, baseUrl: otpiq.baseUrl, channel: 'sms', senderId: 'Saba', logger })('+9647701234567', 'Saba: done.')
    assert.deepEqual(otpiq.seen, [
      {
        path: '/api/sms',
        auth: `Bearer ${KEY}`,
        body: { phoneNumber: '9647701234567', smsType: 'custom', customMessage: 'Saba: done.', provider: 'sms', senderId: 'Saba' },
      },
    ])
  })

  test('its 429 is "wait", with its own wait; anything else refused is a failure, logged for whoever runs the server', async (t) => {
    const limited = await fakeOtpiq(t, { status: 429, body: { message: 'Rate limit exceeded', waitMinutes: 8 } })
    await assert.rejects(
      otpiqSms({ apiKey: KEY, baseUrl: limited.baseUrl, channel: 'auto', logger: memoryLogger().logger })('+9647701234567', '1'),
      (error: unknown) => error instanceof SmsError && error.kind === 'rate-limited' && error.waitSeconds === 480,
    )

    const broke = await fakeOtpiq(t, { status: 400, body: { error: 'Insufficient credit, please add more credit' } })
    const { logger, lines } = memoryLogger()
    await assert.rejects(
      otpiqSms({ apiKey: KEY, baseUrl: broke.baseUrl, channel: 'auto', logger })('+9647701234567', '1'),
      (error: unknown) => error instanceof SmsError && error.kind === 'failed',
    )
    assert.match(lines.join(''), /Insufficient credit/)
  })

  test('no answer at all is a failure', async () => {
    await assert.rejects(
      otpiqSms({ apiKey: KEY, baseUrl: 'http://127.0.0.1:1/api', channel: 'auto', logger: memoryLogger().logger })('+9647701234567', '1'),
      (error: unknown) => error instanceof SmsError && error.kind === 'failed',
    )
  })
})

describe('a code that could not be sent', () => {
  const url = testDatabaseUrl()
  let pool: Pool
  let base: string
  let close: () => Promise<void>
  let failing = true

  before(async () => {
    await freshDatabase(url)
    pool = createPool(url, 2)
    const app = await startApp({
      config: testConfig({ DATABASE_URL: url }),
      pool,
      logger: memoryLogger().logger,
      sms: async () => {
        if (failing) throw new SmsError('failed')
      },
    })
    base = app.url
    close = app.close
  })
  after(async () => {
    await close()
    await pool.end()
  })

  const send = (lang = 'en') =>
    fetch(`${base}/api/v1/auth/otp/send`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'accept-language': lang },
      body: JSON.stringify({ phone: '0770 111 2222', purpose: 'SIGN_UP' }),
    })

  test('is 503 in the shopper\'s language, is withdrawn, and can be asked for again at once', async () => {
    const failed = await send('ar')
    assert.equal(failed.status, 503)
    const body = await failed.json()
    assert.equal(body.code, 'EXTERNAL_SERVICE_ERROR')
    assert.equal(body.message, 'تعذّر إرسال الرمز. حاول مرة أخرى بعد قليل.')
    const left = await one<{ n: number }>(pool, 'SELECT COUNT(*) AS n FROM otp_challenges')
    assert.equal(left?.n, 0)
    failing = false
    assert.equal((await send()).status, 200)
  })
})
