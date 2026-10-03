import type { Request, Response } from 'express'
import multer from 'multer'
import { z } from 'zod'
import type { Context } from '../app.js'
import { exec, one } from '../db/sql.js'
import { me } from '../http/auth.js'
import { envelopeOf, ErrorBody, ok } from '../http/envelope.js'
import { AppError } from '../http/errors.js'
import { IdParams } from '../http/inputs.js'
import { route, type Api } from '../http/route.js'
import { imageTypeOf, newKey, urlOf, withoutLocation } from '../lib/storage.js'

// Photos a store uploads for its logo and products (BACKEND_PLAN.md §2.2
// "Uploads"): images only, told by their first bytes, at most 5 MB. The
// server names the file; the client's name and type are never trusted (spec §56).

export const MAX_UPLOAD_BYTES = 5 * 1024 * 1024

const Uploaded = z
  .object({
    id: z.string(),
    url: z.string(),
    thumbnailUrl: z.string(),
    kind: z.literal('IMAGE'),
    mimeType: z.string(),
    sizeBytes: z.number(),
  })
  .meta({ id: 'UploadedMedia' })

const parse = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_UPLOAD_BYTES, files: 1, fields: 10, fieldSize: 1024 },
}).single('file')

/**
 * The photo a multipart request carries ("file"), checked: an image by its
 * first bytes, at most 5 MB, and without the place it was taken (a phone's GPS
 * data). Call it after signing the caller in, so a stranger's upload is never read.
 */
export async function receivePhoto(req: Request, res: Response): Promise<{ bytes: Buffer; contentType: 'image/jpeg' | 'image/png' | 'image/webp' }> {
  await new Promise<void>((resolve, reject) =>
    parse(req, res, (error: unknown) => {
      if (!error) return resolve()
      if (error instanceof multer.MulterError && error.code === 'LIMIT_FILE_SIZE') {
        return reject(fileError('media.tooBig'))
      }
      if (error instanceof multer.MulterError) return reject(fileError('media.notImage'))
      reject(error)
    }),
  )
  const file = req.file
  if (!file) throw fileError('field.required')
  const contentType = imageTypeOf(file.buffer)
  if (!contentType) throw fileError('media.notImage')
  return { bytes: withoutLocation(file.buffer), contentType }
}

export function mediaRoutes(api: Api, ctx: Context): void {
  const { pool } = ctx

  api.registry.registerPath({
    method: 'post',
    path: '/media/upload',
    tags: ['Media'],
    summary: 'Upload a photo (multipart: file, kind=IMAGE) (merchant, admin)',
    security: [{ bearer: [] }],
    request: {
      body: {
        content: {
          'multipart/form-data': {
            schema: z.object({ file: z.string().meta({ format: 'binary' }), kind: z.string().optional() }),
          },
        },
      },
    },
    responses: {
      200: { description: 'Success', content: { 'application/json': { schema: envelopeOf(Uploaded) } } },
      default: { description: 'An error, in the contract shape', content: { 'application/json': { schema: ErrorBody } } },
    },
  })

  // Signed in first, so a stranger's upload is never read into memory.
  // Saba uploads too: category pictures and Home banners (admin-catalog.ts).
  api.router.post('/media/upload', async (req: Request, res: Response) => {
    await api.authenticate(req, ['MERCHANT', 'ADMIN'])
    const { bytes, contentType } = await receivePhoto(req, res)

    const key = newKey(contentType)
    await ctx.media.save(key, bytes, contentType)
    const inserted = await exec(
      pool,
      'INSERT INTO media_files (owner_user_id, storage_key, content_type, byte_size) VALUES (?, ?, ?, ?)',
      [me(req).id, key, contentType, bytes.length],
    )
    const url = urlOf(req, ctx.config.mediaBaseUrl, key)
    // No thumbnails: the app already shrinks photos to 1600 px (BACKEND_PLAN.md §2.2).
    const data = {
      id: String(inserted.insertId),
      url,
      thumbnailUrl: url,
      kind: 'IMAGE' as const,
      mimeType: contentType,
      sizeBytes: bytes.length,
    }
    res.json(ok(api.checkResponses ? Uploaded.parse(data) : data))
  })

  route(api, {
    method: 'delete',
    path: '/media/:id',
    tag: 'Media',
    summary: 'Delete an own upload; refused while the store or a product still shows it',
    who: ['MERCHANT'],
    params: IdParams,
    response: z.object({}),
    async handle({ req, params }) {
      const id = /^\d{1,15}$/.test(params.id) ? Number(params.id) : 0
      const file = await one<{ storage_key: string }>(
        pool,
        'SELECT storage_key FROM media_files WHERE id = ? AND owner_user_id = ? AND deleted_at IS NULL',
        [id, me(req).id],
      )
      if (!file) throw new AppError(404, 'NOT_FOUND_ERROR', 'error.notFound')
      const used = await one(
        pool,
        `SELECT 1 FROM stores WHERE logo_url = ? OR banner_url = ?
          UNION ALL SELECT 1 FROM product_images WHERE url = ? LIMIT 1`,
        [file.storage_key, file.storage_key, file.storage_key],
      )
      if (used) throw new AppError(409, 'CONFLICT_ERROR', 'media.inUse')
      // Past orders show the photo they were placed with: it stays (the final review's item 7).
      // ponytail: order_items.image_url has no index, so this scans; index it if deleting photos gets slow.
      if (await one(pool, 'SELECT 1 FROM order_items WHERE image_url = ? LIMIT 1', [file.storage_key])) {
        throw new AppError(409, 'CONFLICT_ERROR', 'media.inOrders')
      }
      await exec(pool, 'UPDATE media_files SET deleted_at = NOW(3) WHERE id = ?', [id])
      await ctx.media.remove(file.storage_key)
      return {}
    },
  })
}

function fileError(key: 'media.tooBig' | 'media.notImage' | 'field.required'): AppError {
  return new AppError(422, 'VALIDATION_ERROR', key === 'field.required' ? 'error.validation' : key, undefined, {
    file: { key },
  })
}
