import type { Request } from 'express'
import { z } from 'zod'
import type { Context } from '../app.js'
import type { Connection, Pool } from '../db/pool.js'
import { exec, one, rows } from '../db/sql.js'
import { withTransaction } from '../db/tx.js'
import { me } from '../http/auth.js'
import { AppError } from '../http/errors.js'
import { IdParams, optionalText } from '../http/inputs.js'
import { Page, PageQuery, route, type Api } from '../http/route.js'
import { t, type MessageKey, type MessageParams } from '../lib/i18n.js'
import { billingMonth } from '../lib/money.js'
import { publish } from '../lib/events.js'
import { notify } from '../lib/notify.js'
import { RETURN_WINDOW_DAYS } from '../rules.js'
import { bothNames, loadOrders, orderWords, putBack, returnable } from './orders.js'

// Returns (BACKEND_PLAN.md §6.4, §6.5; DATABASE_DESIGN.md §3.6, §5.2): the
// shopper asks for one store's delivered lines back within 7 days, each line
// once, and is given back what was paid for them. The store approves or
// declines, then hands the cash back when it collects them, and the stock is
// back on its shelf. The order itself stays DELIVERED (Q8).

export const RETURN_REASONS = ['DAMAGED', 'WRONG_ITEM', 'NOT_AS_DESCRIBED', 'MISSING_PARTS', 'CHANGED_MIND', 'OTHER'] as const
export const RETURN_DECLINES = ['USED', 'INCOMPLETE', 'NOT_AS_SAID', 'OTHER'] as const
export const RETURN_STATUSES = ['REQUESTED', 'APPROVED', 'REJECTED', 'REFUNDED'] as const
export type ReturnStatus = (typeof RETURN_STATUSES)[number]

/** The store's answers, and nothing else: REJECTED and REFUNDED are ends. */
const NEXT: Partial<Record<ReturnStatus, readonly ReturnStatus[]>> = {
  REQUESTED: ['APPROVED', 'REJECTED'],
  APPROVED: ['REFUNDED'],
}

export interface ReturnRow {
  id: number
  order_id: number
  part_id: number
  store_id: number
  customer_id: number
  status: ReturnStatus
  reason: string
  description: string | null
  rejection_reason: string | null
  refund_amount: number
  requested_at: Date
  answered_at: Date | null
  refunded_at: Date | null
  order_number: string
  customer_name: string
  customer_name_ar: string | null
}

export interface ReturnLineRow {
  return_id: number
  order_item_id: number
  quantity: number
  refund_amount: number
  product_id: number
  product_name: string
  product_name_ar: string | null
  variant_label: string | null
  image_url: string | null
  store_name: string
  paid_unit_price: number
}

export interface ReturnData {
  ret: ReturnRow
  lines: ReturnLineRow[]
}

/** Returns [ids] with their lines, in the order given; missing ids are left out. */
export async function loadReturns(db: Pool | Connection, ids: number[]): Promise<ReturnData[]> {
  if (ids.length === 0) return []
  const found = await rows<ReturnRow>(
    db,
    `SELECT r.id, r.order_id, r.part_id, r.store_id, r.customer_id, r.status, r.reason, r.description, r.rejection_reason,
            r.refund_amount, r.requested_at, r.answered_at, r.refunded_at, o.order_number, o.customer_name, o.customer_name_ar
       FROM returns r JOIN orders o ON o.id = r.order_id WHERE r.id IN (?)`,
    [ids],
  )
  const lines = await rows<ReturnLineRow>(
    db,
    `SELECT ri.return_id, ri.order_item_id, ri.quantity, ri.refund_amount, oi.product_id, oi.product_name, oi.product_name_ar,
            oi.variant_label, oi.image_url, oi.store_name, oi.paid_unit_price
       FROM return_items ri JOIN order_items oi ON oi.id = ri.order_item_id WHERE ri.return_id IN (?) ORDER BY ri.id`,
    [ids],
  )
  const byId = new Map(found.map((ret) => [ret.id, ret]))
  return ids.flatMap((id) => {
    const ret = byId.get(id)
    return ret ? [{ ret, lines: lines.filter((line) => line.return_id === id) }] : []
  })
}

/** Its steps, from its three moments (DATABASE_DESIGN.md §3.6): no second table. */
export function returnSteps(ret: ReturnRow): { status: ReturnStatus; at: Date }[] {
  const steps: { status: ReturnStatus; at: Date }[] = [{ status: 'REQUESTED', at: ret.requested_at }]
  if (ret.answered_at) steps.push({ status: ret.status === 'REJECTED' ? 'REJECTED' : 'APPROVED', at: ret.answered_at })
  if (ret.refunded_at) steps.push({ status: 'REFUNDED', at: ret.refunded_at })
  return steps
}

export const Return = z
  .object({
    id: z.string(),
    orderId: z.string(),
    orderNumber: z.string(),
    status: z.enum(RETURN_STATUSES),
    requestedAt: z.string(),
    reason: z.string(),
    description: z.string().nullable(),
    merchantId: z.string(),
    merchantName: z.string(),
    customerName: z.string(),
    items: z.array(
      z.object({
        orderItemId: z.string(),
        productId: z.string(),
        name: z.string(),
        nameAr: z.string().nullable(),
        quantity: z.number(),
        imageUrl: z.string().nullable(),
        variantLabel: z.string().nullable(),
        refundAmount: z.number(),
      }),
    ),
    itemCount: z.number(),
    currencyCode: z.literal('IQD'),
    refundAmount: z.number(),
    previewImageUrl: z.string().nullable(),
    rejectionReason: z.string().nullable(),
    // D6: the refund is its own block. A declined return hands nothing back.
    refund: z
      .object({
        amount: z.number(),
        currencyCode: z.literal('IQD'),
        status: z.enum(['PENDING', 'COMPLETED']),
        method: z.string(),
        processedAt: z.string().nullable(),
      })
      .nullable(),
    timeline: z.array(z.object({ status: z.enum(RETURN_STATUSES), occurredAt: z.string(), noteCode: z.string().nullable() })),
    photos: z.array(z.string()),
  })
  .meta({ id: 'Return' })
export type Return = z.infer<typeof Return>

/** A return as the app reads it (returns_repository_impl.dart, ReturnMappers.detail), for the shopper and the store. */
export function returnJson(req: Request, ctx: Context, { ret, lines }: ReturnData): Return {
  const { lang, url, inLang } = orderWords(req, ctx)
  const items = lines.map((line) => ({
    orderItemId: String(line.order_item_id),
    productId: String(line.product_id),
    name: inLang(line.product_name, line.product_name_ar),
    nameAr: line.product_name_ar,
    quantity: line.quantity,
    imageUrl: url(line.image_url),
    variantLabel: line.variant_label,
    refundAmount: line.refund_amount,
  }))
  return {
    id: String(ret.id),
    orderId: String(ret.order_id),
    orderNumber: ret.order_number,
    status: ret.status,
    requestedAt: ret.requested_at.toISOString(),
    reason: ret.reason,
    description: ret.description,
    merchantId: String(ret.store_id),
    merchantName: lines[0]?.store_name ?? '',
    customerName: inLang(ret.customer_name, ret.customer_name_ar),
    items,
    itemCount: lines.reduce((count, line) => count + line.quantity, 0),
    currencyCode: 'IQD',
    refundAmount: ret.refund_amount,
    previewImageUrl: items[0]?.imageUrl ?? null,
    rejectionReason: ret.rejection_reason,
    refund:
      ret.status === 'REJECTED'
        ? null
        : {
            amount: ret.refund_amount,
            currencyCode: 'IQD',
            status: ret.status === 'REFUNDED' ? 'COMPLETED' : 'PENDING',
            // Paid in cash at the door, so given back in cash, by the store, when it collects the things.
            method: t(lang, 'refund.cash'),
            processedAt: ret.refunded_at?.toISOString() ?? null,
          },
    timeline: returnSteps(ret).map((step) => ({
      status: step.status,
      occurredAt: step.at.toISOString(),
      noteCode: step.status === 'REQUESTED' ? 'RETURN_REQUESTED' : null,
    })),
    photos: [],
  }
}

/** The returns on one store's part, newest first: the store's order screen shows them. */
export async function returnsOfPart(db: Pool | Connection, req: Request, ctx: Context, partId: number): Promise<Return[]> {
  const ids = await rows<{ id: number }>(db, 'SELECT id FROM returns WHERE part_id = ? ORDER BY requested_at DESC, id DESC', [partId])
  return (
    await loadReturns(
      db,
      ids.map((row) => row.id),
    )
  ).map((data) => returnJson(req, ctx, data))
}

// ------------------------------------------------------------------ routes ---

const Answer = z.object({ status: z.enum(RETURN_STATUSES), reason: z.string().trim().max(40).nullish() })

/** The shopper's words for a store's answer: [title, body]. */
const TOLD: Partial<Record<ReturnStatus, [MessageKey, MessageKey]>> = {
  APPROVED: ['notify.returnApproved.title', 'notify.returnApproved.body'],
  REJECTED: ['notify.returnRejected.title', 'notify.returnRejected.body'],
  REFUNDED: ['notify.returnRefunded.title', 'notify.returnRefunded.body'],
}

export function returnRoutes(api: Api, ctx: Context): void {
  const { pool } = ctx
  const SHOPPER = ['CUSTOMER'] as const
  const TAG = 'Returns'

  const reread = async (db: Pool | Connection, req: Request, id: number) => returnJson(req, ctx, (await loadReturns(db, [id]))[0]!)

  route(api, {
    method: 'post',
    path: '/returns',
    tag: TAG,
    summary: "Ask for one store's delivered lines back, within 7 days, each line once; the refund is what was paid for them",
    who: SHOPPER,
    body: z.object({
      orderId: z.string(),
      reason: z.enum(RETURN_REASONS, { error: 'return.chooseReason' }),
      description: optionalText(1000),
      items: z
        .array(z.object({ orderItemId: z.string(), quantity: z.number().int().min(1).max(999) }))
        .min(1, { error: 'return.chooseItems' })
        .max(100),
    }),
    response: Return,
    async handle({ req, body }) {
      const userId = me(req).id
      return withTransaction(pool, async (conn) => {
        // The order first (DATABASE_DESIGN.md §5.2): a second request for the
        // same line waits here, then finds the first one's return.
        const order = await one<{ id: number; order_number: string; customer_name: string; customer_name_ar: string | null }>(
          conn,
          'SELECT id, order_number, customer_name, customer_name_ar FROM orders WHERE id = ? AND customer_id = ? FOR UPDATE',
          [/^\d{1,15}$/.test(body.orderId) ? Number(body.orderId) : 0, userId],
        )
        if (!order) throw new AppError(404, 'NOT_FOUND_ERROR', 'order.notFound')
        const [data] = await loadOrders(conn, [order.id])
        const now = new Date()
        const picked: { itemId: number; partId: number; storeId: number; quantity: number; refund: number }[] = []
        for (const line of body.items) {
          const item = data!.items.find((candidate) => String(candidate.id) === line.orderItemId)
          if (!item || picked.some((done) => done.itemId === item.id)) throw itemsError('field.invalid')
          const part = data!.parts.find((candidate) => candidate.id === item.part_id)!
          // Once: one pair of headphones went back three times (BUGS 160).
          if (item.returned === 1) throw ruleError('return.once')
          // Never delivered (cancelled, refused, on its way): not a window that passed (M5).
          if (part.status !== 'DELIVERED') throw ruleError('return.notDelivered')
          if (!returnable(part, item, now)) throw ruleError('return.window', { days: RETURN_WINDOW_DAYS })
          if (line.quantity > item.quantity) throw itemsError('return.tooMany')
          // What it cost after the store's code, not its shelf price (BUGS 161, 175).
          picked.push({ itemId: item.id, partId: part.id, storeId: part.store_id, quantity: line.quantity, refund: item.paid_unit_price * line.quantity })
        }
        // Each store collects its own things, so one store at a time (the demo).
        if (new Set(picked.map((line) => line.partId)).size > 1) throw ruleError('return.oneStore')

        const { partId, storeId } = picked[0]!
        const inserted = await exec(
          conn,
          `INSERT INTO returns (order_id, part_id, store_id, customer_id, reason, description, refund_amount, requested_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, NOW(3))`,
          [order.id, partId, storeId, userId, body.reason, body.description, picked.reduce((sum, line) => sum + line.refund, 0)],
        )
        await exec(conn, 'INSERT INTO return_items (return_id, order_item_id, quantity, refund_amount) VALUES ?', [
          picked.map((line) => [inserted.insertId, line.itemId, line.quantity, line.refund]),
        ])

        const owner = await one<{ owner_user_id: number }>(conn, 'SELECT owner_user_id FROM stores WHERE id = ?', [storeId])
        const count = picked.reduce((sum, line) => sum + line.quantity, 0)
        const words = {
          number: order.order_number,
          customer: bothNames(order.customer_name, order.customer_name_ar),
          items: `${count} ${count === 1 ? 'item' : 'items'}`,
          count,
        }
        await notify(
          conn,
          owner!.owner_user_id,
          'ORDER',
          {
            en: { title: t('en', 'notify.returnAsked.title', words), body: t('en', 'notify.returnAsked.body', words) },
            ar: { title: t('ar', 'notify.returnAsked.title', words), body: t('ar', 'notify.returnAsked.body', words) },
          },
          { type: 'STORE_ORDER', id: partId },
          { push: true },
        )
        publish(conn, [userId, owner!.owner_user_id], 'orders', order.id)
        publish(conn, 'ADMINS', 'returns', inserted.insertId)
        return reread(conn, req, inserted.insertId)
      })
    },
  })

  route(api, {
    method: 'get',
    path: '/returns',
    tag: TAG,
    summary: "The shopper's returns, newest first",
    who: SHOPPER,
    query: PageQuery.extend({ status: z.string().max(20).optional() }),
    response: z.array(Return),
    async handle({ req, query }) {
      const where = ['customer_id = ?']
      const params: unknown[] = [me(req).id]
      if (query.status) {
        where.push('status = ?')
        params.push(query.status.toUpperCase())
      }
      const total = await one<{ n: number }>(pool, `SELECT COUNT(*) AS n FROM returns WHERE ${where.join(' AND ')}`, params)
      const ids = await rows<{ id: number }>(
        pool,
        `SELECT id FROM returns WHERE ${where.join(' AND ')} ORDER BY requested_at DESC, id DESC LIMIT ? OFFSET ?`,
        [...params, query.perPage, (query.page - 1) * query.perPage],
      )
      const found = await loadReturns(
        pool,
        ids.map((row) => row.id),
      )
      return new Page(
        found.map((data) => returnJson(req, ctx, data)),
        query,
        Number(total?.n ?? 0),
      )
    },
  })

  route(api, {
    method: 'get',
    path: '/returns/:id',
    tag: TAG,
    summary: "One of the shopper's returns, with its steps and its refund",
    who: SHOPPER,
    params: IdParams,
    response: Return,
    async handle({ req, params }) {
      const found = await one<{ id: number }>(pool, 'SELECT id FROM returns WHERE id = ? AND customer_id = ?', [idOf(params.id), me(req).id])
      if (!found) throw notFound()
      return reread(pool, req, found.id)
    },
  })

  route(api, {
    method: 'patch',
    path: '/merchants/me/returns/:id',
    tag: 'Store: orders',
    summary: 'Answer a return: approve, decline (a reason), then say the cash was handed back (the stock returns)',
    who: ['MERCHANT'],
    params: IdParams,
    body: Answer,
    response: Return,
    async handle({ req, params, body }) {
      const actor = me(req).id
      const store = await one<{ id: number; store_name: string }>(pool, 'SELECT id, store_name FROM stores WHERE owner_user_id = ?', [actor])
      if (!store) throw notFound()
      return withTransaction(pool, async (conn) => {
        const ret = await one<{ id: number; customer_id: number; status: ReturnStatus }>(
          conn,
          'SELECT id, customer_id, status FROM returns WHERE id = ? AND store_id = ? FOR UPDATE',
          [idOf(params.id), store.id],
        )
        if (!ret) throw notFound()
        const next = body.status
        if (!NEXT[ret.status]?.includes(next)) throw new AppError(409, 'CONFLICT_ERROR', 'return.wrongStep')

        let reason: (typeof RETURN_DECLINES)[number] | null = null
        switch (next) {
          case 'APPROVED':
            await exec(conn, "UPDATE returns SET status = 'APPROVED', answered_at = NOW(3) WHERE id = ?", [ret.id])
            break
          case 'REJECTED':
            reason = RETURN_DECLINES.find((code) => code === body.reason) ?? null
            if (!reason) throw new AppError(422, 'VALIDATION_ERROR', 'order.declineReason', undefined, { reason: { key: 'order.declineReason' } })
            await exec(conn, "UPDATE returns SET status = 'REJECTED', rejection_reason = ?, answered_at = NOW(3) WHERE id = ?", [reason, ret.id])
            break
          case 'REFUNDED': {
            // Off the bill of the month the cash went back, on Iraq's calendar.
            const at = new Date()
            await exec(conn, "UPDATE returns SET status = 'REFUNDED', refunded_at = ?, refund_month = ? WHERE id = ?", [at, billingMonth(at), ret.id])
            // What came back is on the shelf again: the returned quantities, not the whole lines.
            const back = await rows<{ part_id: number; sku_id: number; quantity: number }>(
              conn,
              `SELECT oi.part_id, oi.sku_id, ri.quantity FROM return_items ri JOIN order_items oi ON oi.id = ri.order_item_id
                WHERE ri.return_id = ? ORDER BY oi.sku_id, ri.id`,
              [ret.id],
            )
            await putBack(conn, back, 'RETURN_REFUNDED', actor, ret.id)
            break
          }
        }

        const [data] = await loadReturns(conn, [ret.id])
        const [title, text] = TOLD[next]!
        const words = {
          store: store.store_name,
          number: data!.ret.order_number,
          ...(reason && { reason: { en: t('en', `returnDecline.${reason}` as const), ar: t('ar', `returnDecline.${reason}` as const) } }),
        }
        await notify(
          conn,
          ret.customer_id,
          'ORDER',
          {
            en: { title: t('en', title, words), body: t('en', text, words) },
            ar: { title: t('ar', title, words), body: t('ar', text, words) },
          },
          { type: 'RETURN', id: ret.id },
          { push: true },
        )
        publish(conn, [ret.customer_id, actor], 'orders', data!.ret.order_id)
        publish(conn, 'ADMINS', 'returns', ret.id)
        // Cash handed back comes off this month's bill.
        if (next === 'REFUNDED') publish(conn, 'ADMINS', 'bills')
        return returnJson(req, ctx, data!)
      })
    },
  })
}

function ruleError(key: MessageKey, params?: MessageParams): AppError {
  return new AppError(422, 'BUSINESS_RULE_ERROR', key, params)
}

function itemsError(key: MessageKey): AppError {
  return new AppError(422, 'VALIDATION_ERROR', key, undefined, { items: { key } })
}

function idOf(text: string): number {
  if (!/^\d{1,15}$/.test(text)) throw notFound()
  return Number(text)
}

function notFound(): AppError {
  return new AppError(404, 'NOT_FOUND_ERROR', 'return.notFound')
}
