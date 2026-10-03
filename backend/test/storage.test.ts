// Photos in object storage (the reviewer's item 5; DigitalOcean Spaces,
// decided 2026-09-30), against a stand-in for its S3 API.
import assert from 'node:assert/strict'
import { once } from 'node:events'
import { createServer, type IncomingMessage } from 'node:http'
import type { AddressInfo } from 'node:net'
import { test, type TestContext } from 'node:test'
import { s3Store } from '../src/lib/storage.js'
import { PNG } from './api.js'

/** An S3 API answering [status] and keeping what it was sent. */
async function fakeS3(t: TestContext, status = 200) {
  const seen: { method: string; path: string; headers: IncomingMessage['headers']; body: Buffer }[] = []
  const server = createServer(async (req, res) => {
    const chunks: Buffer[] = []
    for await (const chunk of req) chunks.push(chunk as Buffer)
    seen.push({ method: req.method ?? '', path: req.url ?? '', headers: req.headers, body: Buffer.concat(chunks) })
    res.writeHead(status).end()
  })
  server.listen(0, '127.0.0.1')
  await once(server, 'listening')
  const { port } = server.address() as AddressInfo
  t.after(() => {
    server.closeAllConnections()
    server.close()
  })
  return { endpoint: `http://127.0.0.1:${port}`, seen }
}

const options = (endpoint: string) => ({ endpoint, region: 'fra1', bucket: 'saba-media', accessKeyId: 'DO00EXAMPLEKEY', secretAccessKey: 'spaces-secret' })

test('a photo goes to the bucket under its key: signed, public to read, cached for good; a delete removes it', async (t) => {
  const s3 = await fakeS3(t)
  const store = s3Store(options(s3.endpoint))
  await store.save('images/2026/09/abc.png', PNG, 'image/png')
  await store.remove('images/2026/09/abc.png')
  const [put, del] = s3.seen
  assert.deepEqual([put!.method, put!.path, del!.method, del!.path], ['PUT', '/saba-media/images/2026/09/abc.png', 'DELETE', '/saba-media/images/2026/09/abc.png'])
  assert.deepEqual(put!.body, PNG)
  assert.equal(put!.headers['content-type'], 'image/png')
  assert.equal(put!.headers['x-amz-acl'], 'public-read')
  assert.equal(put!.headers['cache-control'], 'public, max-age=31536000, immutable')
  // Signed with the key's id and the region; the secret itself never travels.
  assert.match(String(put!.headers.authorization), /^AWS4-HMAC-SHA256 Credential=DO00EXAMPLEKEY\/\d{8}\/fra1\/s3\/aws4_request/)
  assert.ok(!JSON.stringify(s3.seen.map((s) => s.headers)).includes('spaces-secret'))
})

test('refused by the bucket: the upload fails; a photo already gone is fine to delete', async (t) => {
  const refusing = await fakeS3(t, 403)
  await assert.rejects(s3Store(options(refusing.endpoint)).save('images/x.png', PNG, 'image/png'), /refused the upload: 403/)
  await assert.rejects(s3Store(options(refusing.endpoint)).remove('images/x.png'), /refused the delete: 403/)
  const gone = await fakeS3(t, 404)
  await s3Store(options(gone.endpoint)).remove('images/x.png')
})

test("a chat's photo is private in the bucket: no public-read, no public caching; read back by the API; missing is null", async (t) => {
  const s3 = await fakeS3(t)
  const store = s3Store(options(s3.endpoint))
  await store.save('chats/2026/10/abc.png', PNG, 'image/png', 'private')
  const [put] = s3.seen
  assert.deepEqual([put!.headers['x-amz-acl'], put!.headers['cache-control']], ['private', undefined])
  assert.deepEqual(await store.read('chats/2026/10/abc.png'), Buffer.alloc(0))
  assert.equal(s3.seen[1]!.method, 'GET')
  const gone = await fakeS3(t, 404)
  assert.equal(await s3Store(options(gone.endpoint)).read('chats/2026/10/abc.png'), null)
})
