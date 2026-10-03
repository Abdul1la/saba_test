import type { Request } from 'express'
import { z } from 'zod'
import type { Context } from '../app.js'
import type { Connection, Pool } from '../db/pool.js'
import { exec, one, rows } from '../db/sql.js'
import { withTransaction } from '../db/tx.js'
import { me } from '../http/auth.js'
import { AppError } from '../http/errors.js'
import { IdParams } from '../http/inputs.js'
import { route, type Api } from '../http/route.js'
import { publish } from '../lib/events.js'
import { ListQuery, pageSql, paged } from './admin-lists.js'
import { some } from './admin-orders.js'
import { REPORT_REASONS } from './orders.js'

// Reported reviews (decided 2026-09-29, before launch: app stores check that a
// report reaches someone). One row per reported review, with its reports.
// Saba removes the review (off the store's page and out of its rating) or
// dismisses its reports (the review stays). Both are kept in admin_actions.

const TAG = 'Admin: reviews'
const ADMIN = ['ADMIN'] as const
const STATUSES = ['OPEN', 'DISMISSED', 'REMOVED'] as const
type Status = (typeof STATUSES)[number]

const ReportedReview = z
  .object({
    id: z.string(),
    /** REMOVED once Saba removed it; OPEN while a report waits; else DISMISSED. */
    status: z.enum(STATUSES),
    store: z.object({ id: z.string(), storeName: z.string() }),
    rating: z.number(),
    body: z.string().optional(),
    /** Left out for a deleted account. */
    authorName: z.string().optional(),
    createdAt: z.string(),
    removedAt: z.string().optional(),
    lastReportedAt: z.string(),
    reports: z.array(
      z.object({
        id: z.string(),
        reason: z.enum(REPORT_REASONS),
        description: z.string().optional(),
        reporterName: z.string().optional(),
        /** Shoppers and, since the final review, stores (a review about themselves included). */
        reporterRole: z.enum(['CUSTOMER', 'MERCHANT']),
        createdAt: z.string(),
        status: z.enum(STATUSES),
      }),
    ),
  })
  .meta({ id: 'ReportedReview' })
type ReportedReview = z.infer<typeof ReportedReview>

/** One row per reported review: REMOVED once Saba removed it, OPEN while a report waits, else DISMISSED; its newest report places it. */
const REVIEWS_REPORTED = `
  SELECT r.id, IF(r.removed_at IS NOT NULL, 'REMOVED', IF(SUM(rr.status = 'OPEN') > 0, 'OPEN', 'DISMISSED')) AS status,
         MAX(rr.created_at) AS last_at
    FROM store_reviews r JOIN review_reports rr ON rr.review_id = r.id
   GROUP BY r.id, r.removed_at`

/** The reported reviews among [reviewIds] (all of them when null), the latest report first. */
async function reported(db: Pool | Connection, reviewIds: number[] | null): Promise<ReportedReview[]> {
  const reviews = await rows<{
    id: number
    store_id: number
    store_name: string
    rating: number
    body: string | null
    created_at: Date
    removed_at: Date | null
    author: string
  }>(
    db,
    `SELECT r.id, r.store_id, s.store_name, r.rating, r.body, r.created_at, r.removed_at, u.full_name AS author
       FROM store_reviews r JOIN stores s ON s.id = r.store_id JOIN users u ON u.id = r.customer_id
      WHERE EXISTS (SELECT 1 FROM review_reports rr WHERE rr.review_id = r.id)${reviewIds ? ' AND r.id IN (?)' : ''}`,
    reviewIds ? [reviewIds] : [],
  )
  if (reviews.length === 0) return []
  const reports = await rows<{
    id: number
    review_id: number
    reason: (typeof REPORT_REASONS)[number]
    description: string | null
    status: Status
    created_at: Date
    reporter: string
    reporter_role: 'CUSTOMER' | 'MERCHANT'
  }>(
    db,
    `SELECT rr.id, rr.review_id, rr.reason, rr.description, rr.status, rr.created_at, u.full_name AS reporter, u.role AS reporter_role
       FROM review_reports rr JOIN users u ON u.id = rr.reporter_user_id
      WHERE rr.review_id IN (?) ORDER BY rr.created_at DESC, rr.id DESC`,
    [reviews.map((review) => review.id)],
  )
  return reviews
    .map((review) => {
      const own = reports.filter((report) => report.review_id === review.id)
      const status: Status = review.removed_at ? 'REMOVED' : own.some((report) => report.status === 'OPEN') ? 'OPEN' : 'DISMISSED'
      return {
        id: String(review.id),
        status,
        store: { id: String(review.store_id), storeName: review.store_name },
        rating: review.rating,
        ...some('body', review.body),
        ...some('authorName', review.author || null),
        createdAt: review.created_at.toISOString(),
        ...some('removedAt', review.removed_at?.toISOString()),
        lastReportedAt: own[0]!.created_at.toISOString(),
        reports: own.map((report) => ({
          id: String(report.id),
          reason: report.reason,
          ...some('description', report.description),
          ...some('reporterName', report.reporter || null),
          reporterRole: report.reporter_role,
          createdAt: report.created_at.toISOString(),
          status: report.status,
        })),
      }
    })
    .sort((a, b) => b.lastReportedAt.localeCompare(a.lastReportedAt) || Number(b.id) - Number(a.id))
}

export function adminReviewRoutes(api: Api, ctx: Context): void {
  const { pool } = ctx

  route(api, {
    method: 'get',
    path: '/admin/review-reports',
    tag: TAG,
    summary: 'Reported reviews, the latest report first, each with its reports; counts per status; a page',
    who: ADMIN,
    query: z.object({ status: z.enum(STATUSES).optional(), ...ListQuery }),
    response: z.object({ items: z.array(ReportedReview), counts: z.record(z.string(), z.number()) }),
    // Counted and paged in the database like the other lists (the final review's item 12).
    async handle({ query }) {
      const counts: Record<string, number> = { all: 0 }
      for (const row of await rows<{ status: Status; n: number }>(pool, `SELECT status, COUNT(*) AS n FROM (${REVIEWS_REPORTED}) t GROUP BY status`)) {
        counts[row.status] = Number(row.n)
        counts.all! += Number(row.n)
      }
      const page = await rows<{ id: number }>(
        pool,
        `SELECT id FROM (${REVIEWS_REPORTED}) t${query.status ? ' WHERE status = ?' : ''} ORDER BY last_at DESC, id DESC${pageSql(query)}`,
        query.status ? [query.status] : [],
      )
      const found = new Map((await reported(pool, page.length ? page.map((row) => row.id) : [0])).map((item) => [item.id, item]))
      const items = page.flatMap((row) => found.get(String(row.id)) ?? [])
      return paged({ items, counts }, query, query.status ? (counts[query.status] ?? 0) : counts.all!)
    },
  })

  /** One moderation step on review [idText], with its audit row, in one transaction. */
  async function moderate(req: Request, idText: string, remove: boolean): Promise<ReportedReview> {
    const id = /^\d{1,15}$/.test(idText) ? Number(idText) : 0
    return withTransaction(pool, async (conn) => {
      const review = await one<{ store_id: number; rating: number; removed: number }>(
        conn,
        'SELECT store_id, rating, removed_at IS NOT NULL AS removed FROM store_reviews WHERE id = ? FOR UPDATE',
        [id],
      )
      if (!review) throw new AppError(404, 'NOT_FOUND_ERROR', 'error.notFound')
      if (review.removed) throw new AppError(409, 'CONFLICT_ERROR', 'admin.wrongState')
      if (remove) {
        await exec(conn, 'UPDATE store_reviews SET removed_at = NOW(3), removed_by = ? WHERE id = ?', [me(req).id, id])
        // Out of the store's rating too: its stars were added when it was written.
        await exec(conn, 'UPDATE stores SET rating_sum = rating_sum - ?, rating_count = rating_count - 1 WHERE id = ?', [
          review.rating,
          review.store_id,
        ])
      }
      const closed = await exec(
        conn,
        "UPDATE review_reports SET status = ?, handled_at = NOW(3), handled_by = ? WHERE review_id = ? AND status = 'OPEN'",
        [remove ? 'REMOVED' : 'DISMISSED', me(req).id, id],
      )
      // Dismissing needs something to dismiss.
      if (!remove && closed.affectedRows === 0) throw new AppError(409, 'CONFLICT_ERROR', 'admin.wrongState')
      await exec(
        conn,
        `INSERT INTO admin_actions (admin_user_id, action, entity_type, entity_id, ip) VALUES (?, ?, 'REVIEW', ?, ?)`,
        [me(req).id, remove ? 'REVIEW_REMOVE' : 'REVIEW_REPORTS_DISMISS', String(id), req.ip ?? null],
      )
      publish(conn, 'ADMINS', 'reviews', id)
      const [item] = await reported(conn, [id])
      if (!item) throw new AppError(404, 'NOT_FOUND_ERROR', 'error.notFound')
      return item
    })
  }

  route(api, {
    method: 'post',
    path: '/admin/review-reports/:id/remove',
    tag: TAG,
    summary: "Remove a review: off the store's page and out of its rating; its open reports close as REMOVED",
    who: ADMIN,
    params: IdParams,
    response: ReportedReview,
    handle: ({ req, params }) => moderate(req, params.id, true),
  })

  route(api, {
    method: 'post',
    path: '/admin/review-reports/:id/dismiss',
    tag: TAG,
    summary: "Dismiss a review's open reports: the review stays",
    who: ADMIN,
    params: IdParams,
    response: ReportedReview,
    handle: ({ req, params }) => moderate(req, params.id, false),
  })
}
