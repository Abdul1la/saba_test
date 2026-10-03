import { z } from 'zod'
import type { Context } from '../app.js'
import { exec, one, rows } from '../db/sql.js'
import { me } from '../http/auth.js'
import { AppError } from '../http/errors.js'
import { IdParams } from '../http/inputs.js'
import { Page, PageQuery, route, type Api } from '../http/route.js'

// The bell: each account's own notifications, in the language it asks for
// (BACKEND_PLAN.md §6.6). The app reads target* or entity*; both are sent as entity*.

const Notification = z
  .object({
    id: z.string(),
    type: z.string(),
    title: z.string(),
    body: z.string(),
    entityType: z.string().nullable(),
    entityId: z.string().nullable(),
    isRead: z.boolean(),
    createdAt: z.string(),
  })
  .meta({ id: 'Notification' })

interface Row {
  id: number
  type: string
  title_en: string
  title_ar: string
  body_en: string
  body_ar: string
  entity_type: string | null
  entity_id: string | null
  is_read: number
  created_at: Date
}

export function notificationRoutes(api: Api, ctx: Context): void {
  const { pool } = ctx

  route(api, {
    method: 'get',
    path: '/notifications',
    tag: 'Notifications',
    summary: 'My notifications, newest first, in the asked language',
    who: 'signedIn',
    query: PageQuery,
    response: z.array(Notification),
    async handle({ req, query }) {
      const userId = me(req).id
      const total = await one<{ n: number }>(pool, 'SELECT COUNT(*) AS n FROM notifications WHERE user_id = ?', [userId])
      const found = await rows<Row>(
        pool,
        `SELECT id, type, title_en, title_ar, body_en, body_ar, entity_type, entity_id, is_read, created_at
           FROM notifications WHERE user_id = ? ORDER BY id DESC LIMIT ? OFFSET ?`,
        [userId, query.perPage, (query.page - 1) * query.perPage],
      )
      const arabic = req.lang === 'ar'
      return new Page(
        found.map((row) => ({
          id: String(row.id),
          type: row.type,
          title: arabic ? row.title_ar : row.title_en,
          body: arabic ? row.body_ar : row.body_en,
          entityType: row.entity_type,
          entityId: row.entity_id,
          isRead: row.is_read === 1,
          createdAt: row.created_at.toISOString(),
        })),
        query,
        Number(total?.n ?? 0),
      )
    },
  })

  route(api, {
    method: 'get',
    path: '/notifications/unread-count',
    tag: 'Notifications',
    summary: 'How many are unread (the bell)',
    who: 'signedIn',
    response: z.object({ count: z.number() }),
    async handle({ req }) {
      const found = await one<{ n: number }>(
        pool,
        'SELECT COUNT(*) AS n FROM notifications WHERE user_id = ? AND is_read = 0',
        [me(req).id],
      )
      return { count: Number(found?.n ?? 0) }
    },
  })

  route(api, {
    method: 'patch',
    path: '/notifications/:id',
    tag: 'Notifications',
    summary: 'Mark one read (or unread)',
    who: 'signedIn',
    params: IdParams,
    body: z.object({ isRead: z.boolean().optional() }),
    response: z.object({}),
    async handle({ req, params, body }) {
      const id = /^\d{1,15}$/.test(params.id) ? Number(params.id) : 0
      const changed = await exec(pool, 'UPDATE notifications SET is_read = ? WHERE id = ? AND user_id = ?', [
        body.isRead ?? true,
        id,
        me(req).id,
      ])
      if (changed.affectedRows === 0) throw new AppError(404, 'NOT_FOUND_ERROR', 'error.notFound')
      return {}
    },
  })

  route(api, {
    method: 'post',
    path: '/notifications/read-all',
    tag: 'Notifications',
    summary: 'Mark every one read',
    who: 'signedIn',
    response: z.object({}),
    async handle({ req }) {
      await exec(pool, 'UPDATE notifications SET is_read = 1 WHERE user_id = ? AND is_read = 0', [me(req).id])
      return {}
    },
  })
}
