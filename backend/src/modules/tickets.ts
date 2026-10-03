import { z } from 'zod'
import type { Context } from '../app.js'
import type { Connection, Pool } from '../db/pool.js'
import { exec, one, rows } from '../db/sql.js'
import { withTransaction } from '../db/tx.js'
import { me } from '../http/auth.js'
import { AppError } from '../http/errors.js'
import { IdParams, requiredText } from '../http/inputs.js'
import { route, type Api } from '../http/route.js'
import { publish } from '../lib/events.js'
import { t, type Lang, type MessageKey } from '../lib/i18n.js'
import { notify } from '../lib/notify.js'
import { ListQuery, pageSql, paged } from './admin-lists.js'

// Support tickets (API_CONTRACT.md §3.8, BACKEND_PLAN.md §6.6): a shopper or a
// store opens one and writes in it; Saba answers and moves it along. A reply
// from whoever opened it reopens a waiting or resolved ticket; a closed one
// takes no replies from either side until Saba opens it again (D-T2).

export const TICKET_STATUSES = ['OPEN', 'IN_PROGRESS', 'WAITING_FOR_CUSTOMER', 'RESOLVED', 'CLOSED'] as const
type TicketStatus = (typeof TICKET_STATUSES)[number]
export const TICKET_CATEGORIES = ['ORDER', 'PAYMENT', 'DELIVERY', 'RETURN', 'PRODUCT', 'ACCOUNT', 'OTHER'] as const
const OPENERS = ['SHOPPER', 'STORE'] as const

const TicketMessage = z
  .object({
    id: z.string(),
    body: z.string(),
    sentAt: z.string(),
    isFromCustomer: z.boolean(),
    // The opener's name on their own messages; Saba's answers are unsigned.
    authorName: z.string().optional(),
  })
  .meta({ id: 'TicketMessage' })

const TicketBase = z.object({
  id: z.string(),
  reference: z.string(),
  subject: z.string(),
  category: z.enum(TICKET_CATEGORIES),
  status: z.enum(TICKET_STATUSES),
  createdAt: z.string(),
  updatedAt: z.string(),
  lastMessage: z.string(),
  openedBy: z.object({ kind: z.enum(OPENERS), name: z.string(), phone: z.string(), storeId: z.string().optional() }),
})
const TicketRow = TicketBase.extend({ messageCount: z.number() }).meta({ id: 'TicketRow' })
const Ticket = TicketBase.extend({ messages: z.array(TicketMessage) }).meta({ id: 'Ticket' })

interface Row {
  id: number
  reference: string
  subject: string
  category: (typeof TICKET_CATEGORIES)[number]
  status: TicketStatus
  created_at: Date
  updated_at: Date
  last_message: string
  opened_by_user_id: number
  opened_by_kind: (typeof OPENERS)[number]
  store_id: number | null
  opener_name: string
  opener_phone: string
  message_count: number
}

const TICKET_SELECT = `
  SELECT t.id, t.reference, t.subject, t.category, t.status, t.created_at, t.updated_at, t.last_message,
         t.opened_by_user_id, t.opened_by_kind, t.store_id, t.opener_name, t.opener_phone,
         (SELECT COUNT(*) FROM support_messages m WHERE m.ticket_id = t.id) AS message_count
    FROM support_tickets t`

/** A deleted shopper's name and number went with the account (the reviewer's item 14). */
const openerName = (row: Row, lang: Lang) => row.opener_name || t(lang, 'chat.deletedAccount')

function base(row: Row, lang: Lang): z.infer<typeof TicketBase> {
  return {
    id: String(row.id),
    reference: row.reference,
    subject: row.subject,
    category: row.category,
    status: row.status,
    createdAt: row.created_at.toISOString(),
    updatedAt: row.updated_at.toISOString(),
    lastMessage: row.last_message,
    openedBy: {
      kind: row.opened_by_kind,
      name: openerName(row, lang),
      phone: row.opener_phone,
      ...(row.store_id !== null && { storeId: String(row.store_id) }),
    },
  }
}

const rowOf = (row: Row, lang: Lang): z.infer<typeof TicketRow> => ({ ...base(row, lang), messageCount: Number(row.message_count) })

async function messagesOf(db: Pool | Connection, ticket: Row, lang: Lang): Promise<z.infer<typeof TicketMessage>[]> {
  const found = await rows<{ id: number; body: string; sent_at: Date; is_from_customer: number }>(
    db,
    'SELECT id, body, sent_at, is_from_customer FROM support_messages WHERE ticket_id = ? ORDER BY id',
    [ticket.id],
  )
  return found.map((m) => ({
    id: String(m.id),
    body: m.body,
    sentAt: m.sent_at.toISOString(),
    isFromCustomer: m.is_from_customer === 1,
    ...(m.is_from_customer === 1 && { authorName: openerName(ticket, lang) }),
  }))
}

/** The first 500 characters of the newest message, for the lists. */
const preview = (text: string) => text.slice(0, 500)

/** The opener is told, in both languages; a tap opens the ticket. */
async function tellOpener(conn: Connection, ticket: Row, title: MessageKey, body: MessageKey, params: Record<string, string>): Promise<void> {
  const words = { reference: ticket.reference, ...params }
  await notify(
    conn,
    ticket.opened_by_user_id,
    'TICKET',
    { en: { title: t('en', title, words), body: t('en', body, words) }, ar: { title: t('ar', title, words), body: t('ar', body, words) } },
    { type: 'TICKET', id: ticket.id },
  )
}

export function ticketRoutes(api: Api, ctx: Context): void {
  const { pool } = ctx
  const OPENER_ROLES = ['CUSTOMER', 'MERCHANT'] as const
  const ADMIN = ['ADMIN'] as const

  async function ticketById(db: Pool | Connection, id: string, openerId?: number): Promise<Row> {
    const row = /^\d{1,15}$/.test(id)
      ? await one<Row>(db, `${TICKET_SELECT} WHERE t.id = ?${openerId === undefined ? '' : ' AND t.opened_by_user_id = ?'}`, [
          Number(id),
          ...(openerId === undefined ? [] : [openerId]),
        ])
      : undefined
    if (!row) throw notFound()
    return row
  }

  const fullTicket = async (db: Pool | Connection, row: Row, lang: Lang): Promise<z.infer<typeof Ticket>> => ({
    ...base(row, lang),
    messages: await messagesOf(db, row, lang),
  })

  // ------------------------------------------------------------ the app ---

  route(api, {
    method: 'get',
    path: '/support/tickets',
    tag: 'Support',
    summary: 'The tickets this account opened, the newest activity first',
    who: OPENER_ROLES,
    response: z.array(TicketRow),
    async handle({ req }) {
      const found = await rows<Row>(pool, `${TICKET_SELECT} WHERE t.opened_by_user_id = ? ORDER BY t.updated_at DESC, t.id DESC`, [me(req).id])
      return found.map((row) => rowOf(row, req.lang))
    },
  })

  route(api, {
    method: 'post',
    path: '/support/tickets',
    tag: 'Support',
    summary: 'Open a ticket: a shopper in their own name, a store in its name (from the session)',
    who: OPENER_ROLES,
    body: z.object({
      subject: z.string().trim().min(4).max(120),
      category: z.enum(TICKET_CATEGORIES, { error: 'field.invalid' }),
      description: z.string().trim().min(10).max(2000),
    }),
    response: TicketRow,
    async handle({ req, body }) {
      const user = me(req)
      const id = await withTransaction(pool, async (conn) => {
        const account = (await one<{ full_name: string; phone: string }>(conn, 'SELECT full_name, phone FROM users WHERE id = ?', [user.id]))!
        const store =
          user.role === 'MERCHANT' ? await one<{ id: number; store_name: string }>(conn, 'SELECT id, store_name FROM stores WHERE owner_user_id = ?', [user.id]) : undefined
        if (user.role === 'MERCHANT' && !store) throw notFound()
        const at = new Date()
        const inserted = await exec(
          conn,
          `INSERT INTO support_tickets (opened_by_user_id, opened_by_kind, store_id, opener_name, opener_phone, subject, category,
                                        last_message, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          [
            user.id,
            store ? 'STORE' : 'SHOPPER',
            store?.id ?? null,
            store?.store_name ?? account.full_name,
            account.phone,
            body.subject,
            body.category,
            preview(body.description),
            at,
            at,
          ],
        )
        // Set with the column that would otherwise take the moment of this update.
        await exec(conn, 'UPDATE support_tickets SET reference = ?, updated_at = ? WHERE id = ?', [`T-${5000 + inserted.insertId}`, at, inserted.insertId])
        await exec(conn, 'INSERT INTO support_messages (ticket_id, body, is_from_customer, author_user_id, sent_at) VALUES (?, ?, 1, ?, ?)', [
          inserted.insertId,
          body.description,
          user.id,
          at,
        ])
        publish(conn, 'ADMINS', 'tickets', inserted.insertId)
        return inserted.insertId
      })
      return rowOf(await ticketById(pool, String(id)), req.lang)
    },
  })

  route(api, {
    method: 'get',
    path: '/support/tickets/:id',
    tag: 'Support',
    summary: 'One of its own tickets; anyone else gets 404',
    who: OPENER_ROLES,
    params: IdParams,
    response: TicketRow,
    handle: async ({ req, params }) => rowOf(await ticketById(pool, params.id, me(req).id), req.lang),
  })

  route(api, {
    method: 'get',
    path: '/support/tickets/:id/messages',
    tag: 'Support',
    summary: "One of its own tickets' messages, oldest first",
    who: OPENER_ROLES,
    params: IdParams,
    response: z.array(TicketMessage),
    handle: async ({ req, params }) => messagesOf(pool, await ticketById(pool, params.id, me(req).id), req.lang),
  })

  route(api, {
    method: 'post',
    path: '/support/tickets/:id/messages',
    tag: 'Support',
    summary: 'Write in its own ticket: a waiting or resolved one opens again; a closed one takes nothing (409)',
    who: OPENER_ROLES,
    params: IdParams,
    body: z.object({ body: requiredText(2000) }),
    response: TicketMessage,
    async handle({ req, params, body }) {
      const user = me(req)
      const ticket = await ticketById(pool, params.id, user.id)
      const at = new Date()
      const id = await withTransaction(pool, async (conn) => {
        // One conditional update: a ticket closed a moment ago takes nothing.
        const changed = await exec(
          conn,
          `UPDATE support_tickets SET status = IF(status IN ('WAITING_FOR_CUSTOMER', 'RESOLVED'), 'OPEN', status), last_message = ?, updated_at = ?
            WHERE id = ? AND status <> 'CLOSED'`,
          [preview(body.body), at, ticket.id],
        )
        if (changed.affectedRows === 0) throw new AppError(409, 'CONFLICT_ERROR', 'ticket.closed')
        const inserted = await exec(conn, 'INSERT INTO support_messages (ticket_id, body, is_from_customer, author_user_id, sent_at) VALUES (?, ?, 1, ?, ?)', [
          ticket.id,
          body.body,
          user.id,
          at,
        ])
        publish(conn, 'ADMINS', 'tickets', ticket.id)
        return inserted.insertId
      })
      return { id: String(id), body: body.body, sentAt: at.toISOString(), isFromCustomer: true, authorName: ticket.opener_name }
    },
  })

  // ------------------------------------------------------------- Saba ---

  route(api, {
    method: 'get',
    path: '/admin/tickets',
    tag: 'Admin: support',
    summary: 'Every ticket, the newest activity first; counts by status and by who opened them',
    who: ADMIN,
    query: z.object({ status: z.enum(TICKET_STATUSES).optional(), openedBy: z.enum(OPENERS).optional(), ...ListQuery }),
    response: z.object({
      items: z.array(TicketRow),
      counts: z.record(z.string(), z.number()),
      byOpener: z.object({ SHOPPER: z.number(), STORE: z.number() }),
    }),
    async handle({ req, query }) {
      // Counts by status within who opened them, and by opener within the status, in the database.
      const [kind, kindParams] = query.openedBy ? [' AND t.opened_by_kind = ?', [query.openedBy]] : ['', []]
      const [status, statusParams] = query.status ? [' AND t.status = ?', [query.status]] : ['', []]
      const counts: Record<string, number> = { all: 0 }
      for (const row of await rows<{ status: string; n: number }>(
        pool,
        `SELECT t.status, COUNT(*) AS n FROM support_tickets t WHERE 1 = 1${kind} GROUP BY t.status`,
        kindParams,
      )) {
        counts[row.status] = Number(row.n)
        counts.all! += Number(row.n)
      }
      const byOpener = { SHOPPER: 0, STORE: 0 }
      for (const row of await rows<{ kind: 'SHOPPER' | 'STORE'; n: number }>(
        pool,
        `SELECT t.opened_by_kind AS kind, COUNT(*) AS n FROM support_tickets t WHERE 1 = 1${status} GROUP BY t.opened_by_kind`,
        statusParams,
      )) {
        byOpener[row.kind] = Number(row.n)
      }
      const found = await rows<Row>(
        pool,
        `${TICKET_SELECT} WHERE 1 = 1${kind}${status} ORDER BY t.updated_at DESC, t.id DESC${pageSql(query)}`,
        [...kindParams, ...statusParams],
      )
      const total = query.status ? (counts[query.status] ?? 0) : counts.all!
      return paged({ items: found.map((row) => rowOf(row, req.lang)), counts, byOpener }, query, total)
    },
  })

  route(api, {
    method: 'get',
    path: '/admin/tickets/:id',
    tag: 'Admin: support',
    summary: 'One ticket with its messages, oldest first',
    who: ADMIN,
    params: IdParams,
    response: Ticket,
    handle: async ({ req, params }) => fullTicket(pool, await ticketById(pool, params.id), req.lang),
  })

  route(api, {
    method: 'post',
    path: '/admin/tickets/:id/messages',
    tag: 'Admin: support',
    summary: "Saba's answer, unsigned; refused on a closed ticket (409). Whoever opened it is told",
    who: ADMIN,
    params: IdParams,
    body: z.object({ body: requiredText(4000) }),
    response: Ticket,
    async handle({ req, params, body }) {
      const ticket = await ticketById(pool, params.id)
      const at = new Date()
      await withTransaction(pool, async (conn) => {
        const changed = await exec(conn, "UPDATE support_tickets SET last_message = ?, updated_at = ? WHERE id = ? AND status <> 'CLOSED'", [
          preview(body.body),
          at,
          ticket.id,
        ])
        if (changed.affectedRows === 0) throw new AppError(409, 'CONFLICT_ERROR', 'ticket.closed')
        // The admin who wrote it is kept, though Saba's answers are sent unsigned.
        await exec(conn, 'INSERT INTO support_messages (ticket_id, body, is_from_customer, author_user_id, sent_at) VALUES (?, ?, 0, ?, ?)', [
          ticket.id,
          body.body,
          me(req).id,
          at,
        ])
        await tellOpener(conn, ticket, 'notify.ticketAnswered.title', 'notify.ticketAnswered.body', {
          text: body.body.length <= 80 ? body.body : `${body.body.slice(0, 79)}…`,
        })
        publish(conn, 'ADMINS', 'tickets', ticket.id)
      })
      return fullTicket(pool, await ticketById(pool, params.id), req.lang)
    },
  })

  route(api, {
    method: 'post',
    path: '/admin/tickets/:id/status',
    tag: 'Admin: support',
    summary: 'Move a ticket to any other status; a closed one can be opened again. Whoever opened it is told',
    who: ADMIN,
    params: IdParams,
    body: z.object({ status: z.enum(TICKET_STATUSES, { error: 'field.invalid' }) }),
    response: Ticket,
    async handle({ req, params, body }) {
      const ticket = await ticketById(pool, params.id)
      await withTransaction(pool, async (conn) => {
        const changed = await exec(conn, 'UPDATE support_tickets SET status = ?, updated_at = ? WHERE id = ? AND status <> ?', [
          body.status,
          new Date(),
          ticket.id,
          body.status,
        ])
        if (changed.affectedRows === 0) throw new AppError(409, 'CONFLICT_ERROR', 'admin.wrongState')
        await exec(
          conn,
          `INSERT INTO admin_actions (admin_user_id, action, entity_type, entity_id, details, ip)
           VALUES (?, 'TICKET_STATUS', 'TICKET', ?, ?, ?)`,
          [me(req).id, String(ticket.id), JSON.stringify({ status: body.status }), req.ip ?? null],
        )
        await tellOpener(conn, ticket, 'notify.ticketStatus.title', `ticketStatus.${body.status}`, {})
        publish(conn, 'ADMINS', 'tickets', ticket.id)
      })
      return fullTicket(pool, await ticketById(pool, params.id), req.lang)
    },
  })
}

function notFound(): AppError {
  return new AppError(404, 'NOT_FOUND_ERROR', 'error.notFound')
}
