import { timingSafeEqual } from 'node:crypto'
import type { Request, Response } from 'express'
import { z } from 'zod'
import type { Context } from '../app.js'
import type { Connection, Pool } from '../db/pool.js'
import { exec, one, rows } from '../db/sql.js'
import { withTransaction } from '../db/tx.js'
import { me } from '../http/auth.js'
import { envelopeOf, ErrorBody, ok } from '../http/envelope.js'
import { AppError } from '../http/errors.js'
import { IdParams, requiredText } from '../http/inputs.js'
import { Page, PageQuery, route, type Api } from '../http/route.js'
import { t, type Lang } from '../lib/i18n.js'
import { notify } from '../lib/notify.js'
import { CHAT_PHOTO_KEY, imageTypeOf, newKey, photoLink, photoSignature, urlOf } from '../lib/storage.js'
import { receivePhoto } from './media.js'

// Chats between a shopper and a store (BACKEND_PLAN.md §6.6, DATABASE_DESIGN.md
// §3.8). Only its two sides can read a chat: the shopper, and the store's
// owner. Saba has no chat inbox; support is tickets (§9 item 11).

const TAG = 'Messages'
const SIDES = ['CUSTOMER', 'MERCHANT'] as const

type Sender = 'CUSTOMER' | 'STORE'

const Conversation = z
  .object({
    id: z.string(),
    // The other side: the store for a shopper, the shopper for a store.
    title: z.string(),
    avatarUrl: z.string().optional(),
    lastMessage: z.string().nullable(),
    /** The newest message is a photo (lastMessage is then null). */
    lastMessageIsPhoto: z.boolean(),
    updatedAt: z.string(),
    unreadCount: z.number(),
    // While either side has blocked the other, nobody writes in it (the reviewer's item 3).
    blocked: z.boolean(),
    // This reader blocked it, and can unblock it.
    blockedByMe: z.boolean(),
  })
  .meta({ id: 'Conversation' })

const Message = z
  .object({
    id: z.string(),
    /** The words; '' for a photo. */
    body: z.string(),
    /** A photo: a link signed for this chat's two sides, good for one to two hours. */
    photoUrl: z.string().optional(),
    /** A photo no longer there: its sender's account was deleted, or Saba removed it. */
    photoRemoved: z.enum(['ACCOUNT', 'SABA']).optional(),
    sentAt: z.string(),
    isMine: z.boolean(),
    senderName: z.string(),
  })
  .meta({ id: 'Message' })

interface MessageRow {
  id: number
  sender: Sender
  body: string | null
  photo_key: string | null
  photo_removed_by: 'ACCOUNT' | 'SABA' | null
  sent_at: Date
}

interface ChatRow {
  id: number
  customer_id: number
  store_id: number
  owner_user_id: number
  store_name: string
  logo_url: string | null
  full_name: string
  full_name_ar: string | null
  customer_status: string
  last_message_at: Date | null
  created_at: Date
  last_body: string | null
  last_photo: number | null
  unread: number
  customer_blocked_at: Date | null
  store_blocked_at: Date | null
}

/** Who is reading: the shopper, or the store whose owner is signed in. */
interface Reader {
  sender: Sender
  userId: number
  storeId: number | null
}

/**
 * Every chat column the shapes need; `unread` counts the other side's messages
 * after the reader's last-read one. Params: the reader's sender, twice.
 */
const CHAT_SELECT = `
  SELECT c.id, c.customer_id, c.store_id, s.owner_user_id, s.store_name, s.logo_url,
         u.full_name, u.full_name_ar, u.status AS customer_status, c.last_message_at, c.created_at,
         c.customer_blocked_at, c.store_blocked_at,
         (SELECT m.body FROM messages m WHERE m.conversation_id = c.id ORDER BY m.id DESC LIMIT 1) AS last_body,
         (SELECT m.photo_key IS NOT NULL FROM messages m WHERE m.conversation_id = c.id ORDER BY m.id DESC LIMIT 1) AS last_photo,
         (SELECT COUNT(*) FROM messages m
           WHERE m.conversation_id = c.id AND m.sender <> ?
             AND m.id > COALESCE(IF(? = 'STORE', c.store_last_read_id, c.customer_last_read_id), 0)) AS unread
    FROM conversations c JOIN stores s ON s.id = c.store_id JOIN users u ON u.id = c.customer_id`

/** The shopper's name as the store reads it, in its language; a deleted account has none left. */
function customerName(lang: Lang, row: ChatRow): string {
  if (row.customer_status === 'DELETED') return t(lang, 'chat.deletedAccount')
  return lang === 'ar' && row.full_name_ar ? row.full_name_ar : row.full_name
}

export function chatRoutes(api: Api, ctx: Context): void {
  const { pool } = ctx

  async function readerOf(db: Pool | Connection, req: Request): Promise<Reader> {
    const user = me(req)
    if (user.role === 'CUSTOMER') return { sender: 'CUSTOMER', userId: user.id, storeId: null }
    const store = await one<{ id: number }>(db, 'SELECT id FROM stores WHERE owner_user_id = ?', [user.id])
    if (!store) throw notFound()
    return { sender: 'STORE', userId: user.id, storeId: store.id }
  }

  /** The reader's own chat [id], else 404: nobody else's chat is found. */
  async function chatOf(db: Pool | Connection, reader: Reader, id: string): Promise<ChatRow> {
    const row = /^\d{1,15}$/.test(id)
      ? await one<ChatRow>(db, `${CHAT_SELECT} WHERE c.id = ? AND ${reader.sender === 'STORE' ? 'c.store_id' : 'c.customer_id'} = ?`, [
          reader.sender,
          reader.sender,
          Number(id),
          reader.storeId ?? reader.userId,
        ])
      : undefined
    if (!row) throw notFound()
    return row
  }

  function card(req: Request, reader: Reader, row: ChatRow): z.infer<typeof Conversation> {
    const asStore = reader.sender === 'STORE'
    return {
      id: String(row.id),
      title: asStore ? customerName(req.lang, row) : row.store_name,
      ...(!asStore && row.logo_url !== null && { avatarUrl: urlOf(req, ctx.config.mediaBaseUrl, row.logo_url) }),
      lastMessage: row.last_body,
      lastMessageIsPhoto: Number(row.last_photo) === 1,
      updatedAt: (row.last_message_at ?? row.created_at).toISOString(),
      unreadCount: Number(row.unread),
      blocked: row.customer_blocked_at !== null || row.store_blocked_at !== null,
      blockedByMe: (asStore ? row.store_blocked_at : row.customer_blocked_at) !== null,
    }
  }

  const apiBase = (req: Request) => `${req.protocol}://${req.get('host')}${ctx.config.apiPrefix}`

  function messageOf(req: Request, reader: Reader, chat: ChatRow, m: MessageRow) {
    return {
      id: String(m.id),
      body: m.body ?? '',
      ...(m.photo_key !== null &&
        (m.photo_removed_by !== null
          ? { photoRemoved: m.photo_removed_by }
          : { photoUrl: photoLink(apiBase(req), ctx.config.jwtSecret, 'chat', m.photo_key) })),
      sentAt: m.sent_at.toISOString(),
      isMine: m.sender === reader.sender,
      senderName: m.sender === 'STORE' ? chat.store_name : customerName(req.lang, chat),
    }
  }

  route(api, {
    method: 'get',
    path: '/messages/conversations',
    tag: TAG,
    summary: "A shopper's chats, or the store's inbox: the newest message first; a chat nobody has written in is not listed",
    who: SIDES,
    response: z.array(Conversation),
    async handle({ req }) {
      const reader = await readerOf(pool, req)
      const found = await rows<ChatRow>(
        pool,
        `${CHAT_SELECT} WHERE ${reader.sender === 'STORE' ? 'c.store_id' : 'c.customer_id'} = ? AND c.last_message_at IS NOT NULL
          ORDER BY c.last_message_at DESC, c.id DESC`,
        [reader.sender, reader.sender, reader.storeId ?? reader.userId],
      )
      return found.map((row) => card(req, reader, row))
    },
  })

  route(api, {
    method: 'post',
    path: '/messages/conversations',
    tag: TAG,
    summary: 'The shopper\'s chat with a store ("Message the store"): the one already there, or a new one',
    who: ['CUSTOMER'],
    body: z.object({ merchantId: z.string().trim().min(1, { error: 'chat.chooseStore' }) }),
    response: Conversation,
    async handle({ req, body }) {
      const reader = await readerOf(pool, req)
      const storeId = /^\d{1,15}$/.test(body.merchantId) ? Number(body.merchantId) : 0
      const find = () => one<{ id: number }>(pool, 'SELECT id FROM conversations WHERE customer_id = ? AND store_id = ?', [reader.userId, storeId])
      if (!(await find())) {
        // A chat is started only with a store shoppers can see.
        const store = await one<{ id: number }>(pool, "SELECT id FROM stores WHERE id = ? AND status = 'APPROVED'", [storeId])
        if (!store) throw notFound()
        // Two taps at once make one chat: the pair is unique.
        await exec(pool, 'INSERT INTO conversations (customer_id, store_id) VALUES (?, ?) ON DUPLICATE KEY UPDATE id = id', [reader.userId, store.id])
      }
      return card(req, reader, await chatOf(pool, reader, String((await find())!.id)))
    },
  })

  route(api, {
    method: 'get',
    path: '/messages/conversations/:id',
    tag: TAG,
    summary: 'One chat, as its reader sees it; 404 for anyone but its two sides',
    who: SIDES,
    params: IdParams,
    response: Conversation,
    async handle({ req, params }) {
      const reader = await readerOf(pool, req)
      return card(req, reader, await chatOf(pool, reader, params.id))
    },
  })

  route(api, {
    method: 'get',
    path: '/messages/conversations/:id/messages',
    tag: TAG,
    summary: "A chat's messages, newest first, paged",
    who: SIDES,
    params: IdParams,
    query: PageQuery,
    response: z.array(Message),
    async handle({ req, params, query }) {
      const reader = await readerOf(pool, req)
      const chat = await chatOf(pool, reader, params.id)
      const found = await rows<MessageRow>(
        pool,
        'SELECT id, sender, body, photo_key, photo_removed_by, sent_at FROM messages WHERE conversation_id = ? ORDER BY id DESC LIMIT ? OFFSET ?',
        [chat.id, query.perPage, (query.page - 1) * query.perPage],
      )
      const total = await one<{ n: number }>(pool, 'SELECT COUNT(*) AS n FROM messages WHERE conversation_id = ?', [chat.id])
      return new Page(
        found.map((m) => messageOf(req, reader, chat, m)),
        query,
        Number(total?.n ?? 0),
      )
    },
  })

  route(api, {
    method: 'post',
    path: '/messages/conversations/:id/messages',
    tag: TAG,
    summary: 'Write in a chat; the other side is told',
    who: SIDES,
    params: IdParams,
    body: z.object({ body: requiredText(2000) }),
    response: Message,
    async handle({ req, params, body }) {
      const reader = await readerOf(pool, req)
      const chat = await chatOf(pool, reader, params.id)
      return send(req, reader, chat, { body: body.body })
    },
  })

  /** A chat's other side refused while either blocked it (409). */
  function open(chat: ChatRow): void {
    if (chat.customer_blocked_at || chat.store_blocked_at) throw new AppError(409, 'CONFLICT_ERROR', 'chat.blocked')
  }

  /** [what] written in [chat]: words, or a photo already saved; the other side is told. */
  async function send(req: Request, reader: Reader, chat: ChatRow, what: { body: string } | { photoKey: string }) {
    open(chat)
    const body = 'body' in what ? what.body : null
    const photoKey = 'photoKey' in what ? what.photoKey : null
    const sentAt = new Date()
    const id = await withTransaction(pool, async (conn) => {
      const inserted = await exec(conn, 'INSERT INTO messages (conversation_id, sender, body, photo_key, sent_at) VALUES (?, ?, ?, ?, ?)', [
        chat.id,
        reader.sender,
        body,
        photoKey,
        sentAt,
      ])
      // What you wrote, you have read.
      await exec(
        conn,
        `UPDATE conversations SET last_message_at = ?,
                customer_last_read_id = IF(? = 'CUSTOMER', ?, customer_last_read_id),
                store_last_read_id = IF(? = 'STORE', ?, store_last_read_id)
          WHERE id = ?`,
        [sentAt, reader.sender, inserted.insertId, reader.sender, inserted.insertId, chat.id],
      )
      // A photo is told as "Sent a photo", in each reader's language.
      const text = (lang: Lang) => (body === null ? t(lang, 'notify.message.photo') : body.length <= 80 ? body : `${body.slice(0, 79)}…`)
      const [to, name] =
        reader.sender === 'STORE'
          ? [chat.customer_id, { en: chat.store_name, ar: chat.store_name }]
          : [chat.owner_user_id, { en: customerName('en', chat), ar: customerName('ar', chat) }]
      await notify(
        conn,
        to,
        'MESSAGE',
        {
          en: { title: t('en', 'notify.message.title', { name }), body: text('en') },
          ar: { title: t('ar', 'notify.message.title', { name }), body: text('ar') },
        },
        { type: 'CONVERSATION', id: chat.id },
        { push: true },
      )
      return inserted.insertId
    })
    return messageOf(req, reader, chat, { id, sender: reader.sender, body, photo_key: photoKey, photo_removed_by: null, sent_at: sentAt })
  }

  // A photo in a chat (the user's call, 2026-10-01): multipart, so it is read here, not by route().
  api.registry.registerPath({
    method: 'post',
    path: '/messages/conversations/{id}/photos',
    tags: [TAG],
    summary: "Send a photo in a chat (multipart: file): checked as uploads are, its location removed, kept privately; the other side is told \"Sent a photo\"",
    security: [{ bearer: [] }],
    request: {
      params: IdParams,
      body: { content: { 'multipart/form-data': { schema: z.object({ file: z.string().meta({ format: 'binary' }) }) } } },
    },
    responses: {
      200: { description: 'Success', content: { 'application/json': { schema: envelopeOf(Message) } } },
      default: { description: 'An error, in the contract shape', content: { 'application/json': { schema: ErrorBody } } },
    },
  })
  api.router.post('/messages/conversations/:id/photos', async (req: Request, res: Response) => {
    await api.authenticate(req, [...SIDES])
    const reader = await readerOf(pool, req)
    // Its own chat and open, before the photo is read.
    const chat = await chatOf(pool, reader, String(req.params.id))
    open(chat)
    const { bytes, contentType } = await receivePhoto(req, res)
    const key = newKey(contentType, new Date(), 'chats')
    await ctx.media.save(key, bytes, contentType, 'private')
    const data = await send(req, reader, chat, { photoKey: key })
    res.json(ok(api.checkResponses ? Message.parse(data) : data))
  })

  // A chat photo through its signed link: no sign-in, so an image tag can show it; nothing without a good signature.
  api.registry.registerPath({
    method: 'get',
    path: '/chat-photos/{year}/{month}/{file}',
    tags: [TAG],
    summary: "A chat photo, through the link the API signed: for a side of its chat (for=chat) or Saba's report evidence (for=evidence), until it expires",
    request: {
      params: z.object({ year: z.string(), month: z.string(), file: z.string() }),
      query: z.object({ for: z.enum(['chat', 'evidence']), e: z.string(), s: z.string() }),
    },
    responses: {
      200: { description: 'The photo', content: { 'image/jpeg': { schema: z.string().meta({ format: 'binary' }) } } },
      default: { description: 'An error, in the contract shape', content: { 'application/json': { schema: ErrorBody } } },
    },
  })
  api.router.get('/chat-photos/:year/:month/:file', async (req: Request, res: Response) => {
    const key = `chats/${req.params.year}/${req.params.month}/${req.params.file}`
    const kind = req.query.for === 'evidence' ? 'evidence' : 'chat'
    const expires = Number(req.query.e)
    const given = Buffer.from(String(req.query.s ?? ''))
    const wanted = Buffer.from(photoSignature(ctx.config.jwtSecret, kind, key, expires))
    const signed = CHAT_PHOTO_KEY.test(key) && given.length === wanted.length && timingSafeEqual(given, wanted)
    if (!signed || !(expires * 1000 > Date.now())) throw new AppError(404, 'NOT_FOUND_ERROR', 'error.notFound')
    // A chat's sides see it while it is there; Saba's evidence also once its sender's account went, until the report closes.
    const message = await one<{ removed_by: string | null }>(pool, 'SELECT photo_removed_by AS removed_by FROM messages WHERE photo_key = ?', [key])
    const allowed = message && (message.removed_by === null || (kind === 'evidence' && message.removed_by === 'ACCOUNT'))
    const bytes = allowed ? await ctx.media.read(key) : null
    if (!bytes) throw new AppError(404, 'NOT_FOUND_ERROR', 'error.notFound')
    res.set({ 'content-type': imageTypeOf(bytes) ?? 'application/octet-stream', 'cache-control': 'private, max-age=3600' }).send(bytes)
  })

  /** This reader's side of chat [id] blocked ([on]) or not; the chat as it now reads. */
  async function block(req: Request, id: string, on: boolean) {
    const reader = await readerOf(pool, req)
    const chat = await chatOf(pool, reader, id)
    const column = reader.sender === 'STORE' ? 'store_blocked_at' : 'customer_blocked_at'
    // Blocked twice: the first moment stands.
    await exec(pool, `UPDATE conversations SET ${column} = ${on ? `COALESCE(${column}, NOW(3))` : 'NULL'} WHERE id = ?`, [chat.id])
    return card(req, reader, await chatOf(pool, reader, id))
  }

  route(api, {
    method: 'post',
    path: '/messages/conversations/:id/block',
    tag: TAG,
    summary: 'Block the other side of a chat: nobody writes in it until this side unblocks (Apple 1.2)',
    who: SIDES,
    params: IdParams,
    response: Conversation,
    handle: ({ req, params }) => block(req, params.id, true),
  })

  route(api, {
    method: 'delete',
    path: '/messages/conversations/:id/block',
    tag: TAG,
    summary: "Unblock: this side's block ends; the chat opens again unless the other side blocked too",
    who: SIDES,
    params: IdParams,
    response: Conversation,
    handle: ({ req, params }) => block(req, params.id, false),
  })

  route(api, {
    method: 'post',
    path: '/messages/conversations/:id/read',
    tag: TAG,
    summary: "Mark the chat read up to its newest message, for this side only",
    who: SIDES,
    params: IdParams,
    response: z.object({}),
    async handle({ req, params }) {
      const reader = await readerOf(pool, req)
      const chat = await chatOf(pool, reader, params.id)
      const newest = await one<{ id: number | null }>(pool, 'SELECT MAX(id) AS id FROM messages WHERE conversation_id = ?', [chat.id])
      if (newest?.id) {
        await exec(
          pool,
          `UPDATE conversations SET customer_last_read_id = IF(? = 'CUSTOMER', ?, customer_last_read_id),
                                    store_last_read_id = IF(? = 'STORE', ?, store_last_read_id)
            WHERE id = ?`,
          [reader.sender, newest.id, reader.sender, newest.id, chat.id],
        )
      }
      return {}
    },
  })
}

function notFound(): AppError {
  return new AppError(404, 'NOT_FOUND_ERROR', 'error.notFound')
}
