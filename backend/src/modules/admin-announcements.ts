import { z } from 'zod'
import type { Context } from '../app.js'
import { exec, one, rows } from '../db/sql.js'
import { withTransaction } from '../db/tx.js'
import { me } from '../http/auth.js'
import { AppError } from '../http/errors.js'
import { requiredText } from '../http/inputs.js'
import { route, type Api } from '../http/route.js'
import { notify } from '../lib/notify.js'

// Saba's announcements (the user's call, 2026-10-08): one notification, written
// on the admin website, to every customer, every store owner, or both. Each
// gets it in their notification list (the bell, live) and on their phones. It
// is shown as typed, whichever language the app is in, and opens nothing.
// Suspended and deleted accounts get nothing. Each send is in the admin log,
// which is also the list of what was sent.

const TAG = 'Admin: announcements'
const ADMIN = ['ADMIN'] as const

const AUDIENCES = ['EVERYONE', 'CUSTOMERS', 'MERCHANTS'] as const
type Audience = (typeof AUDIENCES)[number]
const ROLES: Record<Audience, readonly string[]> = {
  EVERYONE: ['CUSTOMER', 'MERCHANT'],
  CUSTOMERS: ['CUSTOMER'],
  MERCHANTS: ['MERCHANT'],
}

/** Who can receive one: an account in use. */
const RECEIVES = "status = 'ACTIVE' AND deleted_at IS NULL"

/** The same words to the same people this soon again is a second click: refused. */
const AGAIN_AFTER_MINUTES = 2

const Sent = z
  .object({
    id: z.string(),
    audience: z.enum(AUDIENCES),
    title: z.string(),
    body: z.string(),
    recipients: z.number(),
    sentAt: z.string(),
    sentBy: z.string(),
  })
  .meta({ id: 'SentAnnouncement' })

const Overview = z
  .object({
    /** How many accounts each audience reaches now. */
    recipients: z.object({ EVERYONE: z.number(), CUSTOMERS: z.number(), MERCHANTS: z.number() }),
    /** The last 20 sent, newest first. */
    sent: z.array(Sent),
  })
  .meta({ id: 'AnnouncementsOverview' })

interface SentDetails {
  audience: Audience
  title: string
  body: string
  recipients: number
}

export function adminAnnouncementRoutes(api: Api, ctx: Context): void {
  const { pool } = ctx

  route(api, {
    method: 'get',
    path: '/admin/announcements',
    tag: TAG,
    summary: 'How many each audience reaches, and the last 20 announcements sent',
    who: ADMIN,
    response: Overview,
    async handle() {
      const counts = await rows<{ role: string; n: number }>(
        pool,
        `SELECT role, COUNT(*) AS n FROM users WHERE role IN ('CUSTOMER', 'MERCHANT') AND ${RECEIVES} GROUP BY role`,
      )
      const of = (role: string) => Number(counts.find((row) => row.role === role)?.n ?? 0)
      const sent = await rows<{ id: number; details: unknown; created_at: Date; full_name: string | null }>(
        pool,
        `SELECT a.id, a.details, a.created_at, u.full_name FROM admin_actions a JOIN users u ON u.id = a.admin_user_id
          WHERE a.action = 'ANNOUNCEMENT_SEND' ORDER BY a.id DESC LIMIT 20`,
      )
      return {
        recipients: { EVERYONE: of('CUSTOMER') + of('MERCHANT'), CUSTOMERS: of('CUSTOMER'), MERCHANTS: of('MERCHANT') },
        sent: sent.map((row) => {
          const details = (typeof row.details === 'string' ? JSON.parse(row.details) : row.details) as SentDetails
          return {
            id: String(row.id),
            audience: details.audience,
            title: details.title,
            body: details.body,
            recipients: details.recipients,
            sentAt: row.created_at.toISOString(),
            sentBy: row.full_name ?? '',
          }
        }),
      }
    },
  })

  route(api, {
    method: 'post',
    path: '/admin/announcements',
    tag: TAG,
    summary: 'Send an announcement to everyone, every customer or every store owner: in the app and on their phones',
    who: ADMIN,
    body: z.object({ audience: z.enum(AUDIENCES), title: requiredText(120), body: requiredText(1000) }),
    response: Sent,
    handle: ({ req, body }) =>
      withTransaction(pool, async (conn) => {
        const adminId = me(req).id
        // One send at a time for each admin: a double click waits for the
        // first, then finds it below.
        const admin = await one<{ full_name: string | null }>(conn, 'SELECT full_name FROM users WHERE id = ? FOR UPDATE', [adminId])
        const again = await one<{ id: number }>(
          conn,
          `SELECT id FROM admin_actions
            WHERE action = 'ANNOUNCEMENT_SEND' AND entity_id = ? AND created_at > NOW(3) - INTERVAL ? MINUTE
              AND JSON_UNQUOTE(JSON_EXTRACT(details, '$.title')) = ? AND JSON_UNQUOTE(JSON_EXTRACT(details, '$.body')) = ?
            LIMIT 1`,
          [body.audience, AGAIN_AFTER_MINUTES, body.title, body.body],
        )
        if (again) throw new AppError(409, 'CONFLICT_ERROR', 'announcement.justSent')

        const people = await rows<{ id: number }>(conn, `SELECT id FROM users WHERE role IN (?) AND ${RECEIVES} ORDER BY id`, [
          ROLES[body.audience],
        ])
        if (people.length === 0) throw new AppError(422, 'BUSINESS_RULE_ERROR', 'announcement.nobody')

        // Shown as typed, in either app language.
        const words = { title: body.title, body: body.body }
        for (const person of people) {
          await notify(conn, person.id, 'ANNOUNCEMENT', { en: words, ar: words }, undefined, { push: true })
        }

        const details: SentDetails = { audience: body.audience, title: body.title, body: body.body, recipients: people.length }
        const logged = await exec(
          conn,
          `INSERT INTO admin_actions (admin_user_id, action, entity_type, entity_id, details, ip)
           VALUES (?, 'ANNOUNCEMENT_SEND', 'ANNOUNCEMENT', ?, ?, ?)`,
          [adminId, body.audience, JSON.stringify(details), req.ip ?? null],
        )
        return { id: String(logged.insertId), ...details, sentAt: new Date().toISOString(), sentBy: admin?.full_name ?? '' }
      }),
  })
}
