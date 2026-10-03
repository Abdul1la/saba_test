import type { Request } from 'express'
import { z } from 'zod'
import type { Context } from '../app.js'
import type { Connection, Pool } from '../db/pool.js'
import { duplicateKey, exec, one, rows } from '../db/sql.js'
import { withTransaction } from '../db/tx.js'
import { me } from '../http/auth.js'
import { AppError } from '../http/errors.js'
import { IdParams, moment } from '../http/inputs.js'
import { route, type Api } from '../http/route.js'
import type { MessageKey, MessageParams } from '../lib/i18n.js'

// A store's own discount codes (BACKEND_PLAN.md §6.5, DATABASE_DESIGN.md §3.4).
// v1 has no Saba-wide ones: in a cash-only v1 there is nothing to pay them from.

/** Running now: not paused, started, not ended, uses left, its store approved and open. Needs `c` and `s`. */
export const LIVE_COUPON = `c.is_active = 1 AND c.starts_at <= NOW(3) AND (c.ends_at IS NULL OR c.ends_at > NOW(3))
  AND (c.usage_limit IS NULL OR c.used_count < c.usage_limit) AND s.status = 'APPROVED' AND s.is_open = 1`

export const COUPON_COLUMNS =
  'c.id, c.store_id, c.code, c.discount_type, c.value, c.min_order_amount, c.starts_at, c.ends_at, c.usage_limit, c.used_count, c.is_active'

export interface CouponRow {
  id: number
  store_id: number
  code: string
  discount_type: 'PERCENTAGE' | 'FIXED'
  value: number
  min_order_amount: number | null
  starts_at: Date
  ends_at: Date | null
  usage_limit: number | null
  used_count: number
  is_active: number
}

const StoreCoupon = z
  .object({
    id: z.string(),
    code: z.string(),
    discountType: z.enum(['PERCENTAGE', 'FIXED']),
    value: z.number(),
    minOrderAmount: z.number().nullable(),
    startsAt: z.string(),
    endsAt: z.string().nullable(),
    usageLimit: z.number().nullable(),
    usedCount: z.number(),
    isActive: z.boolean(),
    currencyCode: z.literal('IQD'),
  })
  .meta({ id: 'StoreCoupon' })

function couponOf(row: CouponRow): z.infer<typeof StoreCoupon> {
  return {
    id: String(row.id),
    code: row.code,
    discountType: row.discount_type,
    value: row.value,
    minOrderAmount: row.min_order_amount,
    startsAt: row.starts_at.toISOString(),
    endsAt: row.ends_at?.toISOString() ?? null,
    usageLimit: row.usage_limit,
    usedCount: row.used_count,
    isActive: row.is_active === 1,
    currencyCode: 'IQD',
  }
}

/** A whole number; 0, empty or missing is none (the form's empty box). */
const noneOrPositive = (max: number) =>
  z
    .number()
    .int()
    .min(0)
    .max(max)
    .nullish()
    .transform((value) => (value ? value : null))

const CouponInput = z.object({
  code: z.string().trim().toUpperCase().regex(/^[A-Z0-9]{3,15}$/, { error: 'coupon.code' }),
  discountType: z.enum(['PERCENTAGE', 'FIXED'], { error: 'field.invalid' }).default('PERCENTAGE'),
  value: z.number().int().min(1, { error: 'coupon.value' }).max(1_000_000_000),
  minOrderAmount: noneOrPositive(1_000_000_000_000),
  startsAt: moment.nullish(),
  endsAt: moment.nullish(),
  // Empty is "no limit"; 0 is refused, not read as none: a store typing 0 to stop a code would get the opposite (M9).
  usageLimit: z
    .number()
    .int()
    .min(1)
    .max(1_000_000)
    .nullish()
    .transform((value) => value ?? null),
  isActive: z.boolean().default(true),
})
type CouponInput = z.infer<typeof CouponInput>

export function couponRoutes(api: Api, ctx: Context): void {
  const { pool } = ctx
  const STORE = ['MERCHANT'] as const
  const TAG = 'Store: coupons'

  async function storeOf(db: Pool | Connection, req: Request): Promise<number> {
    const store = await one<{ id: number }>(db, 'SELECT id FROM stores WHERE owner_user_id = ?', [me(req).id])
    if (!store) throw notFound()
    return store.id
  }

  /** The store's coupon [idText], locked when [lock]; another store's is not found. */
  async function own(db: Pool | Connection, req: Request, idText: string, lock = false): Promise<CouponRow> {
    const id = /^\d{1,15}$/.test(idText) ? Number(idText) : 0
    const row = await one<CouponRow>(
      db,
      `SELECT ${COUPON_COLUMNS} FROM coupons c WHERE c.id = ? AND c.store_id = ?${lock ? ' FOR UPDATE' : ''}`,
      [id, await storeOf(db, req)],
    )
    if (!row) throw notFound()
    return row
  }

  /** The rules a code's numbers keep; the database holds them again (§4). */
  function check(input: CouponInput, startsAt: Date): void {
    if (input.discountType === 'FIXED' && input.value % 250 !== 0) throw fieldError('value', 'field.steps250')
    if (input.discountType === 'PERCENTAGE' && input.value > 90) throw fieldError('value', 'coupon.percentMax')
    if (input.endsAt && input.endsAt <= startsAt) throw fieldError('endsAt', 'coupon.endBeforeStart')
  }

  /** A code is typed into any cart, so it is one of its kind across Saba. */
  async function saving<T>(work: () => Promise<T>): Promise<T> {
    try {
      return await work()
    } catch (error) {
      if (duplicateKey(error) === 'uq_coupons_code') throw fieldError('code', 'coupon.codeTaken')
      throw error
    }
  }

  route(api, {
    method: 'get',
    path: '/merchants/me/coupons',
    tag: TAG,
    summary: "The store's own codes, newest first",
    who: STORE,
    response: z.array(StoreCoupon),
    async handle({ req }) {
      const found = await rows<CouponRow>(pool, `SELECT ${COUPON_COLUMNS} FROM coupons c WHERE c.store_id = ? ORDER BY c.id DESC`, [
        await storeOf(pool, req),
      ])
      return found.map(couponOf)
    },
  })

  route(api, {
    method: 'post',
    path: '/merchants/me/coupons',
    tag: TAG,
    summary: 'A new code: unique across Saba; a fixed amount in steps of 250, a percentage at most 90',
    who: STORE,
    body: CouponInput,
    response: StoreCoupon,
    async handle({ req, body }) {
      const startsAt = body.startsAt ?? new Date()
      check(body, startsAt)
      const store = await storeOf(pool, req)
      const inserted = await saving(() =>
        exec(
          pool,
          `INSERT INTO coupons (store_id, code, discount_type, value, min_order_amount, starts_at, ends_at, usage_limit, is_active)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          [store, body.code, body.discountType, body.value, body.minOrderAmount, startsAt, body.endsAt ?? null, body.usageLimit, body.isActive],
        ),
      )
      return couponOf(await own(pool, req, String(inserted.insertId)))
    },
  })

  route(api, {
    method: 'put',
    path: '/merchants/me/coupons/:id',
    tag: TAG,
    summary: 'Change a code; its uses so far stay, and the limit cannot go below them',
    who: STORE,
    params: IdParams,
    body: CouponInput,
    response: StoreCoupon,
    async handle({ req, params, body }) {
      await withTransaction(pool, async (conn) => {
        const row = await own(conn, req, params.id, true)
        const startsAt = body.startsAt ?? row.starts_at
        check(body, startsAt)
        if (body.usageLimit !== null && body.usageLimit < row.used_count) {
          throw fieldError('usageLimit', 'coupon.limitBelowUsed', { used: row.used_count })
        }
        await saving(() =>
          exec(
            conn,
            `UPDATE coupons SET code = ?, discount_type = ?, value = ?, min_order_amount = ?, starts_at = ?, ends_at = ?,
                                usage_limit = ?, is_active = ?
              WHERE id = ?`,
            [body.code, body.discountType, body.value, body.minOrderAmount, startsAt, body.endsAt ?? null, body.usageLimit, body.isActive, row.id],
          ),
        )
      })
      return couponOf(await own(pool, req, params.id))
    },
  })

  route(api, {
    method: 'patch',
    path: '/merchants/me/coupons/:id',
    tag: TAG,
    summary: 'Pause or resume a code',
    who: STORE,
    params: IdParams,
    body: z.object({ isActive: z.boolean() }),
    response: StoreCoupon,
    async handle({ req, params, body }) {
      const row = await own(pool, req, params.id)
      await exec(pool, 'UPDATE coupons SET is_active = ? WHERE id = ?', [body.isActive, row.id])
      return couponOf(await own(pool, req, params.id))
    },
  })

  route(api, {
    method: 'delete',
    path: '/merchants/me/coupons/:id',
    tag: TAG,
    summary: 'Delete a code; orders keep the code they used',
    who: STORE,
    params: IdParams,
    response: z.object({}),
    async handle({ req, params }) {
      const row = await own(pool, req, params.id)
      await exec(pool, 'DELETE FROM coupons WHERE id = ?', [row.id])
      return {}
    },
  })
}

function fieldError(field: string, key: MessageKey, params?: MessageParams): AppError {
  return new AppError(422, 'VALIDATION_ERROR', key, params, { [field]: { key, params } })
}

function notFound(): AppError {
  return new AppError(404, 'NOT_FOUND_ERROR', 'error.notFound')
}
