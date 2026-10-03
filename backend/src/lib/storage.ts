import { createHmac, randomBytes } from 'node:crypto'
import { mkdir, readFile, rm, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { AwsClient } from 'aws4fetch'
import type { Request } from 'express'
import type { Config } from '../config.js'

// Uploaded files. On this laptop: a folder on disk (MEDIA_DIR), served at
// /uploads/<key>. Hosted: object storage (DigitalOcean Spaces, decided
// 2026-09-30), through its S3 API, served from MEDIA_BASE_URL (its CDN). The
// database keeps only the key (DATABASE_DESIGN.md §3.3); the full address is
// made per request, because an Android emulator reaches this laptop as
// 10.0.2.2 and a browser as localhost (BACKEND_PLAN.md §9 item 8).

export const UPLOADS_PATH = '/uploads'

/** Where uploaded files are kept. */
export interface MediaStore {
  /** 'private': never public, read back with read() and served by the API (a chat's photos). */
  save(key: string, bytes: Buffer, contentType: string, visibility?: 'public' | 'private'): Promise<void>
  /** Gone, or never there: both are fine. */
  remove(key: string): Promise<void>
  /** A file's bytes, or null when it isn't there. */
  read(key: string): Promise<Buffer | null>
}

/** A folder on this machine's disk: development only (production refuses it). Only images/ is served (app.ts). */
export function diskStore(root: string): MediaStore {
  return {
    async save(key, bytes) {
      const file = path.join(root, key)
      await mkdir(path.dirname(file), { recursive: true })
      await writeFile(file, bytes, { flag: 'wx' })
    },
    async remove(key) {
      await rm(path.join(root, key), { force: true })
    },
    async read(key) {
      try {
        return await readFile(path.join(root, key))
      } catch (error) {
        if ((error as { code?: string }).code === 'ENOENT') return null
        throw error
      }
    },
  }
}

export interface S3Options {
  endpoint: string
  region: string
  bucket: string
  accessKeyId: string
  secretAccessKey: string
  /** false: a private bucket (Railway): no ACL is sent, and the API serves images/ itself (app.ts). */
  publicRead?: boolean
}

/**
 * An S3 bucket (DigitalOcean Spaces): each file public to read, cached for
 * good (its name is random and never reused), but a private one, which only
 * the API reads. The keys are never logged.
 */
export function s3Store(options: S3Options): MediaStore {
  const client = new AwsClient({ accessKeyId: options.accessKeyId, secretAccessKey: options.secretAccessKey, service: 's3', region: options.region })
  const address = (key: string) => `${options.endpoint}/${options.bucket}/${key}`
  return {
    async save(key, bytes, contentType, visibility = 'public') {
      const response = await client.fetch(address(key), {
        method: 'PUT',
        body: new Uint8Array(bytes),
        headers:
          options.publicRead === false
            ? { 'content-type': contentType, ...(visibility === 'public' && { 'cache-control': 'public, max-age=31536000, immutable' }) }
            : visibility === 'public'
              ? { 'content-type': contentType, 'cache-control': 'public, max-age=31536000, immutable', 'x-amz-acl': 'public-read' }
              : { 'content-type': contentType, 'x-amz-acl': 'private' },
      })
      if (!response.ok) throw new Error(`object storage refused the upload: ${response.status}`)
    },
    async remove(key) {
      const response = await client.fetch(address(key), { method: 'DELETE' })
      if (!response.ok && response.status !== 404) throw new Error(`object storage refused the delete: ${response.status}`)
    },
    async read(key) {
      const response = await client.fetch(address(key), { method: 'GET' })
      if (response.status === 404) return null
      if (!response.ok) throw new Error(`object storage refused the read: ${response.status}`)
      return Buffer.from(await response.arrayBuffer())
    },
  }
}

/** A public photo's key (images/…), as /uploads links carry it. */
export const IMAGE_KEY = /^images\/\d{4}\/\d{2}\/[0-9a-f]{32}\.(jpg|png|webp)$/

/** The store the settings name. */
export function mediaStoreOf(config: Pick<Config, 'media' | 'mediaDir'>): MediaStore {
  return config.media.storage === 's3' ? s3Store(config.media) : diskStore(config.mediaDir)
}

/** Photos only, told by their first bytes, never by what the client says (spec §56). */
export function imageTypeOf(bytes: Buffer): 'image/jpeg' | 'image/png' | 'image/webp' | null {
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return 'image/jpeg'
  if (bytes.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'image/png'
  if (bytes.subarray(0, 4).toString('latin1') === 'RIFF' && bytes.subarray(8, 12).toString('latin1') === 'WEBP') {
    return 'image/webp'
  }
  return null
}

const EXTENSION = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' } as const

/** A new key the server made up: `images/2026/09/<random>.jpg` (public), `chats/…` (private). Never the client's file name. */
export function newKey(contentType: keyof typeof EXTENSION, now = new Date(), folder: 'images' | 'chats' = 'images'): string {
  const month = `${now.getUTCFullYear()}/${String(now.getUTCMonth() + 1).padStart(2, '0')}`
  return `${folder}/${month}/${randomBytes(16).toString('hex')}.${EXTENSION[contentType]}`
}

/** A chat photo's key, as chat-photo links carry it. */
export const CHAT_PHOTO_KEY = /^chats\/\d{4}\/\d{2}\/[0-9a-f]{32}\.(jpg|png|webp)$/

/**
 * Who a chat photo's link is for: a side of its chat ('chat'), or Saba reading
 * a report's evidence ('evidence'). It opens until the end of the next whole
 * hour, so a forwarded link soon stops working, and stays the same within an
 * hour, so a phone's cache keeps it.
 */
export function photoLink(apiBase: string, secret: string, kind: 'chat' | 'evidence', key: string, now = Date.now()): string {
  const expires = (Math.floor(now / 3_600_000) + 2) * 3600
  return `${apiBase}/chat-photos/${key.slice('chats/'.length)}?for=${kind}&e=${expires}&s=${photoSignature(secret, kind, key, expires)}`
}

export function photoSignature(secret: string, kind: string, key: string, expires: number): string {
  return createHmac('sha256', secret).update(`chat-photo|${kind}|${key}|${expires}`).digest('base64url')
}

const TIFF_SIZES: Record<number, number> = { 1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8, 11: 4, 12: 8 }

/**
 * A JPEG without the place it was taken: phones write it in the photo's Exif
 * GPS block, which a resize may keep. That block is emptied (its entries and
 * their values zeroed, its count 0); everything else, the orientation among it,
 * stays. Any other file comes back as it was.
 */
export function withoutLocation(bytes: Buffer): Buffer {
  if (bytes[0] !== 0xff || bytes[1] !== 0xd8) return bytes
  const out = Buffer.from(bytes)
  let at = 2
  while (at + 4 <= out.length && out[at] === 0xff) {
    const marker = out[at + 1]!
    // The image data starts: no metadata after it.
    if (marker === 0xda || marker === 0xd9) break
    const length = out.readUInt16BE(at + 2)
    if (marker === 0xe1 && out.toString('latin1', at + 4, at + 10) === 'Exif\0\0') emptyGps(out, at + 10, Math.min(out.length, at + 2 + length))
    at += 2 + length
  }
  return out
}

function emptyGps(b: Buffer, tiff: number, end: number): void {
  if (tiff + 8 > end) return
  const little = b.toString('latin1', tiff, tiff + 2) === 'II'
  const u16 = (o: number) => (little ? b.readUInt16LE(o) : b.readUInt16BE(o))
  const u32 = (o: number) => (little ? b.readUInt32LE(o) : b.readUInt32BE(o))
  const ifd0 = tiff + u32(tiff + 4)
  if (ifd0 + 2 > end) return
  for (let i = 0; i < u16(ifd0); i++) {
    const entry = ifd0 + 2 + i * 12
    if (entry + 12 > end || u16(entry) !== 0x8825) continue
    const gps = tiff + u32(entry + 8)
    if (gps + 2 > end) return
    const count = u16(gps)
    for (let j = 0; j < count; j++) {
      const field = gps + 2 + j * 12
      if (field + 12 > end) break
      const size = (TIFF_SIZES[u16(field + 2)] ?? 1) * u32(field + 4)
      const value = tiff + u32(field + 8)
      if (size > 4 && value + size <= end) b.fill(0, value, value + size)
    }
    b.fill(0, gps, Math.min(end, gps + 2 + count * 12))
    return
  }
}

/** The address a client loads [key] from: MEDIA_BASE_URL when set, else the address this request came to. */
export function urlOf(req: Request, mediaBaseUrl: string | undefined, key: string): string {
  const base = mediaBaseUrl ?? `${req.protocol}://${req.get('host')}${UPLOADS_PATH}`
  return `${base}/${key}`
}

/**
 * The key inside an address this server gave out, whichever host it was
 * given for (10.0.2.2 or localhost), or null for anything else.
 */
export function keyOf(url: string, mediaBaseUrl: string | undefined): string | null {
  let pathname: string
  if (mediaBaseUrl && url.startsWith(`${mediaBaseUrl}/`)) {
    pathname = url.slice(mediaBaseUrl.length + 1)
  } else {
    try {
      pathname = new URL(url).pathname
    } catch {
      return null
    }
    if (!pathname.startsWith(`${UPLOADS_PATH}/`)) return null
    pathname = pathname.slice(UPLOADS_PATH.length + 1)
  }
  return IMAGE_KEY.test(pathname) ? pathname : null
}
