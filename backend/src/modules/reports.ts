import type { Request } from 'express'
import { z } from 'zod'
import type { Context } from '../app.js'
import type { Connection, Pool } from '../db/pool.js'
import { exec, one, rows } from '../db/sql.js'
import { withTransaction } from '../db/tx.js'
import { me } from '../http/auth.js'
import { AppError } from '../http/errors.js'
import { optionalText } from '../http/inputs.js'
import { route, type Api } from '../http/route.js'
import { publish } from '../lib/events.js'
import { photoLink } from '../lib/storage.js'
import { ListQuery, pageSql, paged } from './admin-lists.js'
import { some } from './admin-orders.js'
import { REPORT_REASONS } from './orders.js'

// Reporting a product, a store or a chat (the reviewer's item 3, 2026-09-30:
// Apple 1.2 and Google require a way to report what other people post).
// Reviews have their own reports (admin-reviews.ts). Saba sees the reports
// grouped by what they are about, dismisses them or marks them handled after
// acting with the tools it already has: taking a product down, suspending a
// store or a shopper. Both are kept in admin_actions.

const TARGETS = ['PRODUCT', 'STORE', 'CONVERSATION'] as const
type Target = (typeof TARGETS)[number]
const STATUSES = ['OPEN', 'DISMISSED', 'ACTIONED'] as const
type Status = (typeof STATUSES)[number]
/** A chat report keeps this many of its last messages: Saba has no chat inbox. */
const EVIDENCE_MESSAGES = 20

const Evidence = z.array(
  z.object({
    from: z.enum(['CUSTOMER', 'STORE']),
    /** '' for a photo. */
    body: z.string(),
    sentAt: z.string(),
    /** The message, for "Remove photo" (POST /admin/messages/{id}/remove-photo); kept since 2026-10-01. */
    messageId: z.string().optional(),
    /** A photo Saba can open: signed for evidence, until the report is closed even once its sender's account went. */
    photoUrl: z.string().optional(),
    /** ACCOUNT: its sender's account was deleted (the photo still shows while this report waits); SABA: removed by Saba. */
    photoRemoved: z.enum(['ACCOUNT', 'SABA']).optional(),
  }),
)

/** A chat report's evidence as kept: each message's words or photo key. */
interface KeptMessage {
  from: 'CUSTOMER' | 'STORE'
  body: string | null
  sentAt: string
  messageId?: string
  photo?: string
}

const ReportedItem = z
  .object({
    /** The target: "PRODUCT-12", "STORE-3", "CONVERSATION-40". */
    id: z.string(),
    type: z.enum(TARGETS),
    targetId: z.string(),
    /** OPEN while a report waits; else how the last one was closed. */
    status: z.enum(STATUSES),
    title: z.string(),
    product: z.object({ id: z.string(), name: z.string(), status: z.string(), takenDown: z.boolean() }).optional(),
    store: z.object({ id: z.string(), storeName: z.string(), status: z.string() }).optional(),
    /** A chat's shopper; left out for a deleted account. */
    customer: z.object({ id: z.string(), fullName: z.string() }).optional(),
    lastReportedAt: z.string(),
    reports: z.array(
      z.object({
        id: z.string(),
        reason: z.enum(REPORT_REASONS),
        description: z.string().optional(),
        /** Left out for a deleted account. */
        reporterName: z.string().optional(),
        reporterRole: z.enum(['CUSTOMER', 'MERCHANT']),
        createdAt: z.string(),
        status: z.enum(STATUSES),
        /** A chat report's last messages, oldest first, as they were when it was sent. */
        evidence: Evidence.optional(),
      }),
    ),
  })
  .meta({ id: 'ReportedItem' })
type ReportedItem = z.infer<typeof ReportedItem>

interface ReportRow {
  id: number
  target_type: Target
  target_id: number
  reason: (typeof REPORT_REASONS)[number]
  description: string | null
  evidence: KeptMessage[] | string | null
  status: Status
  created_at: Date
  handled_at: Date | null
  reporter: string
  reporter_role: 'CUSTOMER' | 'MERCHANT'
}

/**
 * One row per reported target that still exists (of [type] when given), for Saba's list, counted
 * and paged in the database like the other lists (the app's #4): OPEN while a report waits, else
 * how its last one was closed; its newest report places it.
 */
function targetRows(type: Target | undefined): [string, unknown[]] {
  return [
    `SELECT r.target_type, r.target_id, MAX(r.created_at) AS last_at, MAX(r.id) AS last_id,
            IF(SUM(r.status = 'OPEN') > 0, 'OPEN',
               SUBSTRING_INDEX(GROUP_CONCAT(IF(r.status = 'OPEN', NULL, r.status) ORDER BY r.handled_at DESC, r.created_at DESC, r.id DESC), ',', 1)) AS status
       FROM reports r
      WHERE CASE r.target_type
              WHEN 'PRODUCT' THEN EXISTS (SELECT 1 FROM products p WHERE p.id = r.target_id)
              WHEN 'STORE' THEN EXISTS (SELECT 1 FROM stores s WHERE s.id = r.target_id)
              ELSE EXISTS (SELECT 1 FROM conversations c WHERE c.id = r.target_id) END${type ? ' AND r.target_type = ?' : ''}
      GROUP BY r.target_type, r.target_id`,
    type ? [type] : [],
  ]
}

/** [targets] with their reports, the latest report first; a chat photo in the evidence through [link]. */
async function reportedItems(db: Pool | Connection, targets: { type: Target; id: number }[], link: (key: string) => string): Promise<ReportedItem[]> {
  if (targets.length === 0) return []
  const reports = await rows<ReportRow>(
    db,
    `SELECT r.id, r.target_type, r.target_id, r.reason, r.description, r.evidence, r.status, r.created_at, r.handled_at,
            u.full_name AS reporter, u.role AS reporter_role
       FROM reports r JOIN users u ON u.id = r.reporter_user_id
      WHERE (r.target_type, r.target_id) IN (?)
      ORDER BY r.created_at DESC, r.id DESC`,
    [targets.map((target) => [target.type, target.id])],
  )
  if (reports.length === 0) return []
  // The evidence's photos as they are now: still there, gone with their sender's account, or removed by Saba.
  const kept = (evidence: KeptMessage[] | string) => (typeof evidence === 'string' ? (JSON.parse(evidence) as KeptMessage[]) : evidence)
  const keys = [...new Set(reports.flatMap((r) => (r.evidence === null ? [] : kept(r.evidence).flatMap((m) => (m.photo ? [m.photo] : [])))))]
  const photos = new Map(
    (keys.length
      ? await rows<{ photo_key: string; removed_by: 'ACCOUNT' | 'SABA' | null; gone: number }>(
          db,
          'SELECT photo_key, photo_removed_by AS removed_by, photo_deleted_at IS NOT NULL AS gone FROM messages WHERE photo_key IN (?)',
          [keys],
        )
      : []
    ).map((row) => [row.photo_key, row]),
  )
  const shown = (m: KeptMessage): z.infer<typeof Evidence>[number] => {
    const photo = m.photo ? photos.get(m.photo) : undefined
    const openable = photo && photo.removed_by !== 'SABA' && Number(photo.gone) === 0
    return {
      from: m.from,
      body: m.body ?? '',
      sentAt: m.sentAt,
      ...(m.messageId && { messageId: m.messageId }),
      ...(openable && { photoUrl: link(m.photo!) }),
      ...(photo?.removed_by && { photoRemoved: photo.removed_by }),
    }
  }
  const idsOf = (type: Target) => [...new Set(reports.filter((r) => r.target_type === type).map((r) => r.target_id))]
  const [productIds, storeIds, chatIds] = [idsOf('PRODUCT'), idsOf('STORE'), idsOf('CONVERSATION')]
  const products = productIds.length
    ? await rows<{ id: number; name: string; status: string; taken_down: number; store_id: number; store_name: string; store_status: string }>(
        db,
        `SELECT p.id, COALESCE(p.name_en, p.name_ar) AS name, p.status, p.taken_down, s.id AS store_id, s.store_name, s.status AS store_status
           FROM products p JOIN stores s ON s.id = p.store_id WHERE p.id IN (?)`,
        [productIds],
      )
    : []
  const stores = storeIds.length
    ? await rows<{ id: number; store_name: string; status: string }>(db, 'SELECT id, store_name, status FROM stores WHERE id IN (?)', [storeIds])
    : []
  const chats = chatIds.length
    ? await rows<{ id: number; customer_id: number; full_name: string; store_id: number; store_name: string; store_status: string }>(
        db,
        `SELECT c.id, c.customer_id, u.full_name, c.store_id, s.store_name, s.status AS store_status
           FROM conversations c JOIN users u ON u.id = c.customer_id JOIN stores s ON s.id = c.store_id WHERE c.id IN (?)`,
        [chatIds],
      )
    : []

  const groups = new Map<string, ReportRow[]>()
  for (const report of reports) {
    const key = `${report.target_type}-${report.target_id}`
    groups.set(key, [...(groups.get(key) ?? []), report])
  }
  const items: ReportedItem[] = []
  for (const [key, own] of groups) {
    const { target_type: type, target_id: targetId } = own[0]!
    let title: string
    let extra: Pick<ReportedItem, 'product' | 'store' | 'customer'> = {}
    if (type === 'PRODUCT') {
      const p = products.find((row) => row.id === targetId)
      if (!p) continue
      title = p.name
      extra = {
        product: { id: String(p.id), name: p.name, status: p.status, takenDown: p.taken_down === 1 },
        store: { id: String(p.store_id), storeName: p.store_name, status: p.store_status },
      }
    } else if (type === 'STORE') {
      const s = stores.find((row) => row.id === targetId)
      if (!s) continue
      title = s.store_name
      extra = { store: { id: String(s.id), storeName: s.store_name, status: s.status } }
    } else {
      const c = chats.find((row) => row.id === targetId)
      if (!c) continue
      title = c.full_name ? `${c.full_name} · ${c.store_name}` : c.store_name
      extra = {
        store: { id: String(c.store_id), storeName: c.store_name, status: c.store_status },
        ...(c.full_name && { customer: { id: String(c.customer_id), fullName: c.full_name } }),
      }
    }
    // The last one closed decides a closed target's status (reports are newest first).
    const lastClosed = own.filter((r) => r.status !== 'OPEN').sort((a, b) => b.handled_at!.getTime() - a.handled_at!.getTime())[0]
    const status: Status = own.some((r) => r.status === 'OPEN') ? 'OPEN' : lastClosed!.status
    items.push({
      id: key,
      type,
      targetId: String(targetId),
      status,
      title,
      ...extra,
      lastReportedAt: own[0]!.created_at.toISOString(),
      reports: own.map((r) => ({
        id: String(r.id),
        reason: r.reason,
        ...some('description', r.description),
        ...some('reporterName', r.reporter || null),
        reporterRole: r.reporter_role,
        createdAt: r.created_at.toISOString(),
        status: r.status,
        ...(r.evidence !== null && { evidence: kept(r.evidence).map(shown) }),
      })),
    })
  }
  return items
}

export function reportRoutes(api: Api, ctx: Context): void {
  const { pool } = ctx
  /** A chat photo in the evidence, signed for Saba (chats.ts serves it). */
  const evidenceLink = (req: Request) => (key: string) =>
    photoLink(`${req.protocol}://${req.get('host')}${ctx.config.apiPrefix}`, ctx.config.jwtSecret, 'evidence', key)

  route(api, {
    method: 'post',
    path: '/reports',
    tag: 'Reports',
    summary:
      'Report a product, a store or a chat to Saba; once per person and target while open, reopened when sent again after Saba closed it; Saba sees it among its reports',
    who: ['CUSTOMER', 'MERCHANT'],
    body: z.object({
      targetType: z.enum(TARGETS, { error: 'field.invalid' }),
      targetId: z.string(),
      reason: z.enum(REPORT_REASONS, { error: 'field.invalid' }),
      description: optionalText(500),
    }),
    response: z.object({}),
    async handle({ req, body }) {
      const user = me(req).id
      const id = /^\d{1,15}$/.test(body.targetId) ? Number(body.targetId) : 0
      let evidence: string | null = null
      // What the person can see, and never their own.
      if (body.targetType === 'PRODUCT') {
        const found = await one(
          pool,
          `SELECT p.id FROM products p JOIN stores s ON s.id = p.store_id
            WHERE p.id = ? AND p.status = 'APPROVED' AND p.deleted_at IS NULL AND s.status = 'APPROVED' AND s.owner_user_id <> ?`,
          [id, user],
        )
        if (!found) throw notFound()
      } else if (body.targetType === 'STORE') {
        if (!(await one(pool, "SELECT id FROM stores WHERE id = ? AND status = 'APPROVED' AND owner_user_id <> ?", [id, user]))) throw notFound()
      } else {
        const chat = await one(
          pool,
          'SELECT c.id FROM conversations c JOIN stores s ON s.id = c.store_id WHERE c.id = ? AND (c.customer_id = ? OR s.owner_user_id = ?)',
          [id, user, user],
        )
        if (!chat) throw notFound()
        const last = await rows<{ id: number; sender: 'CUSTOMER' | 'STORE'; body: string | null; photo_key: string | null; removed: number; sent_at: Date }>(
          pool,
          'SELECT id, sender, body, photo_key, photo_removed_at IS NOT NULL AS removed, sent_at FROM messages WHERE conversation_id = ? ORDER BY id DESC LIMIT ?',
          [id, EVIDENCE_MESSAGES],
        )
        // A photo by its key: it stays for Saba while this report is open, even if its sender deletes their account.
        evidence = JSON.stringify(
          last.reverse().map(
            (m): KeptMessage => ({
              from: m.sender,
              body: m.body,
              sentAt: m.sent_at.toISOString(),
              messageId: String(m.id),
              ...(m.photo_key !== null && !Number(m.removed) && { photo: m.photo_key }),
            }),
          ),
        )
      }
      // Sent again while open: kept as it was. After Saba closed it: open again, with the new words
      // and evidence (the final review's item 3). MySQL sets these left to right, so status is set last.
      const added = await exec(
        pool,
        `INSERT INTO reports (target_type, target_id, reporter_user_id, reason, description, evidence) VALUES (?, ?, ?, ?, ?, ?) AS sent
         ON DUPLICATE KEY UPDATE
           reason = IF(reports.status = 'OPEN', reports.reason, sent.reason),
           description = IF(reports.status = 'OPEN', reports.description, sent.description),
           evidence = IF(reports.status = 'OPEN', reports.evidence, sent.evidence),
           created_at = IF(reports.status = 'OPEN', reports.created_at, NOW(3)),
           handled_at = NULL, handled_by = NULL, status = 'OPEN'`,
        [body.targetType, id, user, body.reason, body.description, evidence],
      )
      if (added.affectedRows > 0) publish(pool, 'ADMINS', 'reports', `${body.targetType}-${id}`)
      return {}
    },
  })

  route(api, {
    method: 'get',
    path: '/admin/reports',
    tag: 'Admin: reports',
    summary: 'Reported products, stores and chats, the latest report first, each with its reports; counts per status within the type; a page',
    who: ['ADMIN'],
    query: z.object({ status: z.enum(STATUSES).optional(), type: z.enum(TARGETS).optional(), ...ListQuery }),
    response: z.object({ items: z.array(ReportedItem), counts: z.record(z.string(), z.number()) }),
    async handle({ req, query }) {
      const [targets, params] = targetRows(query.type)
      const counts: Record<string, number> = { all: 0 }
      for (const row of await rows<{ status: Status; n: number }>(pool, `SELECT status, COUNT(*) AS n FROM (${targets}) t GROUP BY status`, params)) {
        counts[row.status] = Number(row.n)
        counts.all! += Number(row.n)
      }
      const page = await rows<{ target_type: Target; target_id: number }>(
        pool,
        `SELECT target_type, target_id FROM (${targets}) t${query.status ? ' WHERE status = ?' : ''}
          ORDER BY last_at DESC, last_id DESC${pageSql(query)}`,
        query.status ? [...params, query.status] : params,
      )
      const found = new Map(
        (await reportedItems(pool, page.map((row) => ({ type: row.target_type, id: row.target_id })), evidenceLink(req))).map((item) => [item.id, item]),
      )
      const items = page.flatMap((row) => found.get(`${row.target_type}-${row.target_id}`) ?? [])
      return paged({ items, counts }, query, query.status ? (counts[query.status] ?? 0) : counts.all!)
    },
  })

  /** Closes the target's open reports as [status], with its audit row, in one transaction. */
  async function close(req: Request, typeText: string, idText: string, status: 'DISMISSED' | 'ACTIONED'): Promise<ReportedItem> {
    const type = (TARGETS as readonly string[]).includes(typeText) ? (typeText as Target) : null
    const id = /^\d{1,15}$/.test(idText) ? Number(idText) : 0
    if (!type) throw notFound()
    return withTransaction(pool, async (conn) => {
      const closed = await exec(
        conn,
        "UPDATE reports SET status = ?, handled_at = NOW(3), handled_by = ? WHERE target_type = ? AND target_id = ? AND status = 'OPEN'",
        [status, me(req).id, type, id],
      )
      if (closed.affectedRows === 0) {
        if (!(await one(conn, 'SELECT id FROM reports WHERE target_type = ? AND target_id = ? LIMIT 1', [type, id]))) throw notFound()
        throw new AppError(409, 'CONFLICT_ERROR', 'admin.wrongState')
      }
      await exec(conn, "INSERT INTO admin_actions (admin_user_id, action, entity_type, entity_id, ip) VALUES (?, ?, 'REPORT', ?, ?)", [
        me(req).id,
        status === 'DISMISSED' ? 'REPORTS_DISMISS' : 'REPORTS_RESOLVE',
        `${type}-${id}`,
        req.ip ?? null,
      ])
      publish(conn, 'ADMINS', 'reports', `${type}-${id}`)
      return (await reportedItems(conn, [{ type, id }], evidenceLink(req)))[0]!
    })
  }

  route(api, {
    method: 'post',
    path: '/admin/reports/:type/:id/dismiss',
    tag: 'Admin: reports',
    summary: "Dismiss a target's open reports: nothing needed doing",
    who: ['ADMIN'],
    params: z.object({ type: z.string(), id: z.string() }),
    response: ReportedItem,
    handle: ({ req, params }) => close(req, params.type, params.id, 'DISMISSED'),
  })

  route(api, {
    method: 'post',
    path: '/admin/reports/:type/:id/resolve',
    tag: 'Admin: reports',
    summary: "Mark a target's open reports handled, once Saba has acted (taken the product down, suspended the store or the shopper)",
    who: ['ADMIN'],
    params: z.object({ type: z.string(), id: z.string() }),
    response: ReportedItem,
    handle: ({ req, params }) => close(req, params.type, params.id, 'ACTIONED'),
  })

  route(api, {
    method: 'post',
    path: '/admin/messages/:id/remove-photo',
    tag: 'Admin: reports',
    summary:
      "Remove a chat photo (Apple asks that objectionable content can be removed): both sides then see it removed by Saba, and its file is deleted. Kept in admin_actions",
    who: ['ADMIN'],
    params: z.object({ id: z.string() }),
    response: z.object({}),
    async handle({ req, params }) {
      const id = /^\d{1,15}$/.test(params.id) ? Number(params.id) : 0
      const key = await withTransaction(pool, async (conn) => {
        const message = await one<{ photo_key: string | null; removed: number }>(
          conn,
          'SELECT photo_key, photo_removed_at IS NOT NULL AS removed FROM messages WHERE id = ? FOR UPDATE',
          [id],
        )
        if (!message?.photo_key) throw notFound()
        if (Number(message.removed)) throw new AppError(409, 'CONFLICT_ERROR', 'admin.wrongState')
        await exec(conn, "UPDATE messages SET photo_removed_at = NOW(3), photo_removed_by = 'SABA' WHERE id = ?", [id])
        await exec(conn, "INSERT INTO admin_actions (admin_user_id, action, entity_type, entity_id, ip) VALUES (?, 'CHAT_PHOTO_REMOVE', 'MESSAGE', ?, ?)", [
          me(req).id,
          String(id),
          req.ip ?? null,
        ])
        return message.photo_key
      })
      // The file now; if storage fails, the hourly run deletes it (deleteRemovedChatPhotos).
      try {
        await ctx.media.remove(key)
        await exec(pool, 'UPDATE messages SET photo_deleted_at = NOW(3) WHERE id = ?', [id])
      } catch (error) {
        req.log.warn({ err: error, messageId: id }, 'chat photo not deleted yet; the hourly run tries again')
      }
      return {}
    },
  })
}

function notFound(): AppError {
  return new AppError(404, 'NOT_FOUND_ERROR', 'error.notFound')
}
