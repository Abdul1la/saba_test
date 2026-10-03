import type { Request } from 'express'
import { z } from 'zod'
import type { Context } from '../app.js'
import type { Connection, Pool } from '../db/pool.js'
import { exec, one, rows } from '../db/sql.js'
import { withTransaction } from '../db/tx.js'
import { me } from '../http/auth.js'
import { AppError } from '../http/errors.js'
import { IdParams, requiredText } from '../http/inputs.js'
import { route, type Api } from '../http/route.js'
import { t, type MessageKey } from '../lib/i18n.js'
import { closeStreams, publish } from '../lib/events.js'
import { notify } from '../lib/notify.js'
import { anyOf, cityWhere, likeFolded, ListQuery, pageSql, paged, phoneWhere } from './admin-lists.js'
import { AdminProduct, adminProductOf, adminProductsWhere } from './admin-products.js'
import { askDeletion } from './store-deletion.js'
import { adminStoreOf, AdminStore, deliveryAreas, STORE_SELECT, StoreStatus, type StoreRow } from './stores.js'

// Saba's answers on stores, the queue, and Home's featured rail
// (API_CONTRACT.md §3.3, §3.4, §3.9). Every write also writes admin_actions.

const TAG = 'Admin: stores'
const ADMIN = ['ADMIN'] as const

const Reason = z.object({ reason: requiredText(500) })

export function adminStoreRoutes(api: Api, ctx: Context): void {
  const { pool } = ctx

  /** [where] stores as AdminStore records, in [order]. */
  async function storesWhere(db: Pool | Connection, req: Request, where: string, params: unknown[], order: string) {
    const found = await rows<StoreRow>(db, `${STORE_SELECT} ${where} ORDER BY ${order}`, params)
    const areas = await deliveryAreas(
      db,
      found.map((row) => row.id),
    )
    return found.map((row) => adminStoreOf(req, ctx, row, areas.get(row.id)!))
  }

  async function storeById(db: Pool | Connection, req: Request, id: number): Promise<AdminStore> {
    const [store] = await storesWhere(db, req, 'WHERE s.id = ?', [id], 's.id')
    if (!store) throw notFound()
    return store
  }

  route(api, {
    method: 'get',
    path: '/admin/stores',
    tag: TAG,
    summary: 'Stores, newest first, with counts per status',
    who: ADMIN,
    query: z.object({
      status: StoreStatus.optional(),
      q: z.string().optional(),
      // "false": only owners whose number was never checked; the counts follow it like the search.
      phoneVerified: z.enum(['true', 'false']).optional(),
      ...ListQuery,
    }),
    response: z.object({ items: z.array(AdminStore), counts: z.record(z.string(), z.number()) }),
    async handle({ req, query }) {
      // The web's `matches`, in the database: the store's name and address
      // (stores.search_text), the owner's name (users.search_text) and email,
      // the city in either language, the phone however it is typed (contract §1.7).
      const q = query.q ?? ''
      const [matching, searchParams] = anyOf(q, [
        ['s.search_text LIKE ? OR u.search_text LIKE ? OR u.email LIKE ?', [likeFolded(q), likeFolded(q), likeFolded(q)]],
        await cityWhere(pool, 's.governorate', q),
        phoneWhere('SUBSTRING(u.phone, 5)', q),
      ])
      const search =
        matching + (query.phoneVerified ? ` AND u.phone_verified_at IS ${query.phoneVerified === 'true' ? 'NOT ' : ''}NULL` : '')
      const counts: Record<string, number> = { all: 0 }
      const byStatus = await rows<{ status: string; n: number }>(
        pool,
        `SELECT s.status, COUNT(*) AS n FROM stores s JOIN users u ON u.id = s.owner_user_id WHERE 1 = 1${search} GROUP BY s.status`,
        searchParams,
      )
      for (const row of byStatus) {
        counts[row.status] = Number(row.n)
        counts.all! += Number(row.n)
      }
      const items = await storesWhere(
        pool,
        req,
        `WHERE 1 = 1${search}${query.status ? ' AND s.status = ?' : ''}`,
        [...searchParams, ...(query.status ? [query.status] : [])],
        `s.submitted_at DESC, s.id DESC${pageSql(query)}`,
      )
      return paged({ items, counts }, query, query.status ? (counts[query.status] ?? 0) : counts.all!)
    },
  })

  route(api, {
    method: 'get',
    path: '/admin/stores/:id',
    tag: TAG,
    summary: 'One store',
    who: ADMIN,
    params: IdParams,
    response: AdminStore,
    handle: ({ req, params }) => storeById(pool, req, idOf(params.id)),
  })

  /**
   * Moves store [id] from [from] to its answer, conditionally (0 rows is 404
   * or 409), writes the audit row and tells the owner, in one transaction.
   */
  async function answer(
    req: Request,
    id: number,
    step: {
      from: 'PENDING' | 'APPROVED' | 'SUSPENDED'
      set: string
      params: unknown[]
      action: string
      reason?: string
      tell?: { title: MessageKey; body: MessageKey }
    },
  ): Promise<AdminStore> {
    return withTransaction(pool, async (conn) => {
      const changed = await exec(conn, `UPDATE stores SET ${step.set} WHERE id = ? AND status = ?`, [
        ...step.params,
        id,
        step.from,
      ])
      if (changed.affectedRows === 0) {
        if (!(await one(conn, 'SELECT id FROM stores WHERE id = ?', [id]))) throw notFound()
        throw new AppError(409, 'CONFLICT_ERROR', 'admin.wrongState')
      }
      await exec(
        conn,
        `INSERT INTO admin_actions (admin_user_id, action, entity_type, entity_id, reason, ip)
         VALUES (?, ?, 'STORE', ?, ?, ?)`,
        [me(req).id, step.action, String(id), step.reason ?? null, req.ip ?? null],
      )
      if (step.tell) {
        const owner = await one<{ owner_user_id: number }>(conn, 'SELECT owner_user_id FROM stores WHERE id = ?', [id])
        const words = (lang: 'en' | 'ar') => ({
          title: t(lang, step.tell!.title),
          body: t(lang, step.tell!.body, { reason: step.reason ?? '' }),
        })
        await notify(conn, owner!.owner_user_id, 'STORE', { en: words('en'), ar: words('ar') }, { type: 'STORE', id })
      }
      publish(conn, 'ADMINS', 'stores', id)
      return storeById(conn, req, id)
    })
  }

  route(api, {
    method: 'post',
    path: '/admin/stores/:id/approve',
    tag: TAG,
    summary: 'Approve a waiting store; the store is told',
    who: ADMIN,
    params: IdParams,
    response: AdminStore,
    handle: ({ req, params }) =>
      answer(req, idOf(params.id), {
        from: 'PENDING',
        set: "status = 'APPROVED', answered_at = NOW(3), rejection_reason = NULL",
        params: [],
        action: 'STORE_APPROVE',
        tell: { title: 'notify.storeApproved.title', body: 'notify.storeApproved.body' },
      }),
  })

  route(api, {
    method: 'post',
    path: '/admin/stores/:id/reject',
    tag: TAG,
    summary: 'Turn a waiting store down, with a reason; the store is told',
    who: ADMIN,
    params: IdParams,
    body: Reason,
    response: AdminStore,
    handle: ({ req, params, body }) =>
      answer(req, idOf(params.id), {
        from: 'PENDING',
        set: "status = 'REJECTED', answered_at = NOW(3), rejection_reason = ?",
        params: [body.reason],
        action: 'STORE_REJECT',
        reason: body.reason,
        tell: { title: 'notify.storeRejected.title', body: 'notify.storeRejected.body' },
      }),
  })

  route(api, {
    method: 'post',
    path: '/admin/stores/:id/suspend',
    tag: TAG,
    summary: 'Suspend an approved store: its products leave the shop, it takes no new orders (Q4)',
    who: ADMIN,
    params: IdParams,
    body: Reason,
    response: AdminStore,
    handle: ({ req, params, body }) =>
      answer(req, idOf(params.id), {
        from: 'APPROVED',
        set: "status = 'SUSPENDED', suspension_reason = ?",
        params: [body.reason],
        action: 'STORE_SUSPEND',
        reason: body.reason,
        tell: { title: 'notify.storeSuspended.title', body: 'notify.storeSuspended.body' },
      }),
  })

  route(api, {
    method: 'post',
    path: '/admin/stores/:id/unsuspend',
    tag: TAG,
    summary: 'Reactivate a suspended store; the store is told it can sell again',
    who: ADMIN,
    params: IdParams,
    response: AdminStore,
    handle: ({ req, params }) =>
      answer(req, idOf(params.id), {
        from: 'SUSPENDED',
        set: "status = 'APPROVED', suspension_reason = NULL",
        params: [],
        action: 'STORE_UNSUSPEND',
        // Its own words, not "approved" again (contract §3.4): the owner can sell again.
        tell: { title: 'notify.storeReactivated.title', body: 'notify.storeReactivated.body' },
      }),
  })

  route(api, {
    method: 'post',
    path: '/admin/stores/:id/deletion',
    tag: TAG,
    summary:
      "Start deleting the owner's account at their request (support; Google's deletion page), as their own button does: the store closes now and goes once nothing is left to finish. The owner is told, and can cancel in the app",
    who: ADMIN,
    params: IdParams,
    response: AdminStore,
    handle: ({ req, params }) =>
      withTransaction(pool, async (conn) => {
        const id = idOf(params.id)
        if (!(await askDeletion(conn, id))) {
          if (!(await one(conn, 'SELECT id FROM stores WHERE id = ?', [id]))) throw notFound()
          // Asked already, by its owner or by Saba (a CLOSED store was asked too).
          throw new AppError(409, 'CONFLICT_ERROR', 'admin.wrongState')
        }
        await exec(
          conn,
          `INSERT INTO admin_actions (admin_user_id, action, entity_type, entity_id, ip)
           VALUES (?, 'STORE_DELETION', 'STORE', ?, ?)`,
          [me(req).id, String(id), req.ip ?? null],
        )
        // Told, so an owner who never asked can cancel it.
        const owner = await one<{ owner_user_id: number }>(conn, 'SELECT owner_user_id FROM stores WHERE id = ?', [id])
        const words = (lang: 'en' | 'ar') => ({ title: t(lang, 'notify.storeDeletion.title'), body: t(lang, 'notify.storeDeletion.body') })
        await notify(conn, owner!.owner_user_id, 'STORE', { en: words('en'), ar: words('ar') }, { type: 'STORE', id })
        publish(conn, 'ADMINS', 'stores', id)
        return storeById(conn, req, id)
      }),
  })

  route(api, {
    method: 'post',
    path: '/admin/stores/:id/free-number',
    tag: TAG,
    summary:
      "Free a number held by the wrong person (signed up while SMS codes were off): the owner is suspended at once, so they can't cancel, and the store's deletion starts; the number is free once it closes (the hourly run, when nothing is left to finish). Only for a number never checked",
    who: ADMIN,
    params: IdParams,
    body: z.object({ reason: requiredText(500) }),
    response: AdminStore,
    async handle({ req, params, body }) {
      const id = idOf(params.id)
      const freed = await withTransaction(pool, async (conn) => {
        const owner = await one<{ id: number; checked: number }>(
          conn,
          `SELECT u.id, u.phone_verified_at IS NOT NULL AS checked FROM stores s JOIN users u ON u.id = s.owner_user_id
            WHERE s.id = ? AND s.status <> 'CLOSED' FOR UPDATE`,
          [id],
        )
        if (!owner) throw notFound()
        // A number its code proved is its holder's: never taken from them this way.
        if (Number(owner.checked) === 1) throw new AppError(409, 'CONFLICT_ERROR', 'admin.numberChecked')
        await askDeletion(conn, id)
        await exec(conn, "UPDATE users SET status = 'SUSPENDED', suspension_reason = ? WHERE id = ? AND status = 'ACTIVE'", [body.reason, owner.id])
        await exec(conn, 'UPDATE refresh_tokens SET revoked_at = NOW(3) WHERE user_id = ? AND revoked_at IS NULL', [owner.id])
        await exec(
          conn,
          `INSERT INTO admin_actions (admin_user_id, action, entity_type, entity_id, reason, ip)
           VALUES (?, 'NUMBER_FREE', 'STORE', ?, ?, ?)`,
          [me(req).id, String(id), body.reason, req.ip ?? null],
        )
        publish(conn, 'ADMINS', 'stores', id)
        return { store: await storeById(conn, req, id), ownerId: owner.id }
      })
      // Out at once: the owner's live streams end with their sign-ins.
      closeStreams(freed.ownerId)
      return freed.store
    },
  })

  route(api, {
    method: 'get',
    path: '/admin/queue',
    tag: TAG,
    summary: 'Everything waiting for an answer, oldest first',
    who: ADMIN,
    response: z.object({ stores: z.array(AdminStore), products: z.array(AdminProduct) }),
    async handle({ req }) {
      const stores = await storesWhere(pool, req, "WHERE s.status = 'PENDING'", [], 's.submitted_at, s.id')
      const products = await adminProductsWhere(pool, "AND p.status = 'PENDING'", [], 'COALESCE(p.submitted_at, p.created_at), p.id')
      return { stores, products: products.map((item) => adminProductOf(req, ctx, item)) }
    },
  })

  const Featured = z.object({ stores: z.array(AdminStore), featured: z.array(z.string()) })

  async function featuredList(db: Pool | Connection, req: Request): Promise<z.infer<typeof Featured>> {
    const stores = await storesWhere(db, req, "WHERE s.status = 'APPROVED'", [], 's.submitted_at DESC, s.id DESC')
    const featured = await rows<{ store_id: number }>(
      db,
      `SELECT f.store_id FROM featured_stores f JOIN stores s ON s.id = f.store_id
        WHERE s.status = 'APPROVED' ORDER BY f.position`,
    )
    return { stores, featured: featured.map((row) => String(row.store_id)) }
  }

  route(api, {
    method: 'get',
    path: '/admin/featured-stores',
    tag: TAG,
    summary: "Home's featured rail: every approved store, and the rail in order",
    who: ADMIN,
    response: Featured,
    handle: ({ req }) => featuredList(pool, req),
  })

  route(api, {
    method: 'put',
    path: '/admin/featured-stores',
    tag: TAG,
    summary: 'Save the rail in order; a suspended featured store keeps its place at the end',
    who: ADMIN,
    body: z.object({ storeIds: z.array(z.string()).max(500) }),
    response: Featured,
    async handle({ req, body }) {
      const ids = body.storeIds.map((text) => (/^\d{1,15}$/.test(text) ? Number(text) : 0))
      return withTransaction(pool, async (conn) => {
        const approved = ids.length
          ? await rows<{ id: number }>(conn, "SELECT id FROM stores WHERE id IN (?) AND status = 'APPROVED'", [ids])
          : []
        // A store no longer approved (it may have changed while the admin edited),
        // or a repeat: IN (…) finds each store once, so a repeat falls short too.
        if (approved.length !== ids.length) {
          throw new AppError(409, 'CONFLICT_ERROR', 'admin.wrongState')
        }
        const kept = await rows<{ store_id: number }>(
          conn,
          `SELECT f.store_id FROM featured_stores f JOIN stores s ON s.id = f.store_id
            WHERE s.status <> 'APPROVED' ORDER BY f.position`,
        )
        const rail = [...ids, ...kept.map((row) => row.store_id).filter((id) => !ids.includes(id))]
        await exec(conn, 'DELETE FROM featured_stores')
        if (rail.length > 0) {
          await exec(conn, 'INSERT INTO featured_stores (store_id, position) VALUES ?', [
            rail.map((id, index) => [id, index + 1]),
          ])
        }
        await exec(
          conn,
          `INSERT INTO admin_actions (admin_user_id, action, entity_type, entity_id, details, ip)
           VALUES (?, 'FEATURED_SAVE', 'FEATURED', 'rail', ?, ?)`,
          [me(req).id, JSON.stringify({ storeIds: rail.map(String) }), req.ip ?? null],
        )
        return featuredList(conn, req)
      })
    },
  })
}

function idOf(text: string): number {
  if (!/^\d{1,15}$/.test(text)) throw notFound()
  return Number(text)
}

function notFound(): AppError {
  return new AppError(404, 'NOT_FOUND_ERROR', 'error.notFound')
}
