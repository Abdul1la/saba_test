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
import { closeStreams, publish } from '../lib/events.js'
import { GOVERNORATES, type Governorate } from '../lib/governorates.js'
import { deleteShopper } from './account.js'
import { AdminOrder, adminOrderOf, some } from './admin-orders.js'
import { anyOf, cityWhere, likeFolded, likeTyped, ListQuery, pageSql, paged, phoneWhere } from './admin-lists.js'
import { loadOrders } from './orders.js'

// Saba's shoppers (API_CONTRACT.md §3.11): who they are, what they bought, and
// suspending them. A deleted account is left out: it has no name or number
// left to show (the user's call, 2026-09-27); its orders stay under Orders.

const Customer = z
  .object({
    id: z.string(),
    fullName: z.string(),
    fullNameAr: z.string(),
    phone: z.string(),
    /** False: signed up while SMS codes were off, the number never proven (PHONE_VERIFICATION). */
    phoneVerified: z.boolean(),
    governorate: z.enum(GOVERNORATES),
    status: z.enum(['ACTIVE', 'SUSPENDED']),
    suspensionReason: z.string().optional(),
    joinedAt: z.string(),
    orderCount: z.number(),
    spent: z.number(),
  })
  .meta({ id: 'Customer' })
type Customer = z.infer<typeof Customer>

const CustomerDetail = Customer.extend({
  addresses: z.array(
    z.object({
      id: z.string(),
      label: z.string(),
      fullName: z.string(),
      phone: z.string(),
      governorate: z.enum(GOVERNORATES),
      area: z.string(),
      areaAr: z.string().optional(),
      street: z.string().optional(),
      streetAr: z.string().optional(),
      landmark: z.string(),
      landmarkAr: z.string().optional(),
      isDefault: z.boolean(),
    }),
  ),
  orders: z.array(AdminOrder),
}).meta({ id: 'CustomerDetail' })

interface CustomerRow {
  id: number
  full_name: string
  full_name_ar: string | null
  phone: string
  checked: number
  governorate: Governorate
  status: 'ACTIVE' | 'SUSPENDED'
  suspension_reason: string | null
  created_at: Date
  area: string | null
  area_ar: string | null
  order_count: number
  delivered: string | number
  refunded: string | number
}

// Sums come back from MySQL as DECIMAL strings: read through Number().
const CUSTOMER_SELECT = `SELECT u.id, u.full_name, u.full_name_ar, u.phone, u.phone_verified_at IS NOT NULL AS checked, u.governorate, u.status, u.suspension_reason, u.created_at,
       a.area, a.area_ar,
       (SELECT COUNT(*) FROM orders o WHERE o.customer_id = u.id) AS order_count,
       (SELECT COALESCE(SUM(op.amount_due), 0) FROM orders o JOIN order_store_parts op ON op.order_id = o.id
         WHERE o.customer_id = u.id AND op.status = 'DELIVERED') AS delivered,
       (SELECT COALESCE(SUM(r.refund_amount), 0) FROM returns r WHERE r.customer_id = u.id AND r.status = 'REFUNDED') AS refunded
  FROM users u LEFT JOIN addresses a ON a.user_id = u.id AND a.is_default = 1
 WHERE u.role = 'CUSTOMER' AND u.status IN ('ACTIVE', 'SUSPENDED')`

function customerOf(row: CustomerRow): Customer {
  return {
    id: String(row.id),
    fullName: row.full_name,
    fullNameAr: row.full_name_ar ?? '',
    phone: row.phone,
    phoneVerified: Number(row.checked) === 1,
    governorate: row.governorate,
    status: row.status,
    ...some('suspensionReason', row.suspension_reason),
    joinedAt: row.created_at.toISOString(),
    orderCount: Number(row.order_count),
    // What their delivered parts came to, less the cash handed back on returns (Q7).
    spent: Number(row.delivered) - Number(row.refunded),
  }
}

export function adminCustomerRoutes(api: Api, ctx: Context): void {
  const { pool } = ctx
  const ADMIN = ['ADMIN'] as const
  const TAG = 'Admin: customers'

  async function customerById(db: Pool | Connection, id: number): Promise<Customer> {
    const row = await one<CustomerRow>(db, `${CUSTOMER_SELECT} AND u.id = ?`, [id])
    if (!row) throw notFound()
    return customerOf(row)
  }

  route(api, {
    method: 'get',
    path: '/admin/customers',
    tag: TAG,
    summary: 'Shoppers, newest first, with counts per status',
    who: ADMIN,
    query: z.object({
      q: z.string().max(100).optional(),
      status: z.enum(['ACTIVE', 'SUSPENDED']).optional(),
      // "false": only numbers never checked; the counts follow it like the search.
      phoneVerified: z.enum(['true', 'false']).optional(),
      ...ListQuery,
    }),
    response: z.object({ items: z.array(Customer), counts: z.record(z.string(), z.number()) }),
    async handle({ query }) {
      // The web's `matches`, in the database: the name in either language
      // (users.search_text, folded), the home area in either language, the
      // city in either language, the phone however it is typed (contract §3.11).
      const q = query.q ?? ''
      const [matching, searchParams] = anyOf(q, [
        ['u.search_text LIKE ?', [likeFolded(q)]],
        ['a.area LIKE ? OR a.area_ar LIKE ?', [likeTyped(q), likeTyped(q)]],
        await cityWhere(pool, 'u.governorate', q),
        phoneWhere('SUBSTRING(u.phone, 5)', q),
      ])
      const search =
        matching + (query.phoneVerified ? ` AND u.phone_verified_at IS ${query.phoneVerified === 'true' ? 'NOT ' : ''}NULL` : '')
      const counts: Record<string, number> = { all: 0 }
      const byStatus = await rows<{ status: string; n: number }>(
        pool,
        `SELECT u.status, COUNT(*) AS n FROM users u LEFT JOIN addresses a ON a.user_id = u.id AND a.is_default = 1
          WHERE u.role = 'CUSTOMER' AND u.status IN ('ACTIVE', 'SUSPENDED')${search} GROUP BY u.status`,
        searchParams,
      )
      for (const row of byStatus) {
        counts[row.status] = Number(row.n)
        counts.all! += Number(row.n)
      }
      const found = await rows<CustomerRow>(
        pool,
        `${CUSTOMER_SELECT}${search}${query.status ? ' AND u.status = ?' : ''} ORDER BY u.created_at DESC, u.id DESC${pageSql(query)}`,
        [...searchParams, ...(query.status ? [query.status] : [])],
      )
      return paged({ items: found.map(customerOf), counts }, query, query.status ? (counts[query.status] ?? 0) : counts.all!)
    },
  })

  route(api, {
    method: 'get',
    path: '/admin/customers/:id',
    tag: TAG,
    summary: 'One shopper: their addresses, the default first, and their orders, newest first',
    who: ADMIN,
    params: IdParams,
    response: CustomerDetail,
    async handle({ req, params }) {
      const id = idOf(params.id)
      const customer = await customerById(pool, id)
      const addresses = await rows<{
        id: number
        label: string | null
        full_name: string
        phone: string
        governorate: Governorate
        area: string
        area_ar: string | null
        street: string | null
        street_ar: string | null
        landmark: string
        landmark_ar: string | null
        is_default: number
      }>(
        pool,
        `SELECT id, label, full_name, phone, governorate, area, area_ar, street, street_ar, landmark, landmark_ar, is_default
           FROM addresses WHERE user_id = ? ORDER BY is_default DESC, id`,
        [id],
      )
      const orderIds = await rows<{ id: number }>(pool, 'SELECT id FROM orders WHERE customer_id = ? ORDER BY placed_at DESC, id DESC', [id])
      return {
        ...customer,
        addresses: addresses.map((address) => ({
          id: String(address.id),
          label: address.label ?? '',
          fullName: address.full_name,
          phone: address.phone,
          governorate: address.governorate,
          area: address.area,
          ...some('areaAr', address.area_ar),
          ...some('street', address.street),
          ...some('streetAr', address.street_ar),
          landmark: address.landmark,
          ...some('landmarkAr', address.landmark_ar),
          isDefault: address.is_default === 1,
        })),
        orders: (
          await loadOrders(
            pool,
            orderIds.map((row) => row.id),
          )
        ).map((data) => adminOrderOf(req, ctx, data)),
      }
    },
  })

  /** Moves shopper [id] from [from], conditionally (0 rows is 404 or 409), with the audit row, in one transaction. */
  async function change(req: Request, id: number, from: 'ACTIVE' | 'SUSPENDED', action: string, reason: string | null): Promise<Customer> {
    return withTransaction(pool, async (conn) => {
      const changed = await exec(
        conn,
        `UPDATE users SET status = ?, suspension_reason = ? WHERE id = ? AND role = 'CUSTOMER' AND status = ?`,
        [from === 'ACTIVE' ? 'SUSPENDED' : 'ACTIVE', reason, id, from],
      )
      if (changed.affectedRows === 0) {
        await customerById(conn, id)
        throw new AppError(409, 'CONFLICT_ERROR', 'admin.wrongState')
      }
      // Out at once, and every sign-in ended: lifting the suspension later
      // brings none of them back (BACKEND_PLAN.md §5.1).
      if (from === 'ACTIVE') {
        await exec(conn, 'UPDATE refresh_tokens SET revoked_at = NOW(3) WHERE user_id = ? AND revoked_at IS NULL', [id])
      }
      await exec(
        conn,
        `INSERT INTO admin_actions (admin_user_id, action, entity_type, entity_id, reason, ip)
         VALUES (?, ?, 'CUSTOMER', ?, ?, ?)`,
        [me(req).id, action, String(id), reason, req.ip ?? null],
      )
      publish(conn, 'ADMINS', 'customers', id)
      return customerById(conn, id)
    })
  }

  route(api, {
    method: 'post',
    path: '/admin/customers/:id/suspend',
    tag: TAG,
    summary: "Suspend a shopper: they can't sign in or order; their orders stay as they are. The reason is Saba's own note",
    who: ADMIN,
    params: IdParams,
    body: z.object({ reason: requiredText(500) }),
    response: Customer,
    async handle({ req, params, body }) {
      const id = idOf(params.id)
      const customer = await change(req, id, 'ACTIVE', 'CUSTOMER_SUSPEND', body.reason)
      // Out at once: their live streams end with their sign-ins.
      closeStreams(id)
      return customer
    },
  })

  route(api, {
    method: 'post',
    path: '/admin/customers/:id/unsuspend',
    tag: TAG,
    summary: 'Lift a suspension; the shopper signs in again',
    who: ADMIN,
    params: IdParams,
    response: Customer,
    handle: ({ req, params }) => change(req, idOf(params.id), 'SUSPENDED', 'CUSTOMER_UNSUSPEND', null),
  })

  route(api, {
    method: 'delete',
    path: '/admin/customers/:id',
    tag: TAG,
    summary:
      "Delete a shopper's account at their request (support; Google's deletion page), as their own delete does: now, refused while an order is open",
    who: ADMIN,
    params: IdParams,
    response: z.object({}),
    async handle({ req, params }) {
      const id = idOf(params.id)
      await withTransaction(pool, async (conn) => {
        // A shopper, active or suspended; a store owner's account goes with its store.
        await customerById(conn, id)
        await deleteShopper(conn, id)
        await exec(
          conn,
          `INSERT INTO admin_actions (admin_user_id, action, entity_type, entity_id, ip)
           VALUES (?, 'CUSTOMER_DELETE', 'CUSTOMER', ?, ?)`,
          [me(req).id, String(id), req.ip ?? null],
        )
        publish(conn, 'ADMINS', 'customers', id)
      })
      closeStreams(id)
      return {}
    },
  })

  route(api, {
    method: 'post',
    path: '/admin/customers/:id/free-number',
    tag: TAG,
    summary:
      "Free a number held by the wrong person (signed up while SMS codes were off): the shopper's account is deleted, as DELETE does, so the number's owner can sign up. Only for a number never checked; refused while an order is open",
    who: ADMIN,
    params: IdParams,
    body: z.object({ reason: requiredText(500) }),
    response: z.object({}),
    async handle({ req, params, body }) {
      const id = idOf(params.id)
      await withTransaction(pool, async (conn) => {
        await customerById(conn, id)
        const held = await one<{ checked: number }>(conn, 'SELECT phone_verified_at IS NOT NULL AS checked FROM users WHERE id = ? FOR UPDATE', [id])
        // A number its code proved is its holder's: never taken from them this way.
        if (Number(held!.checked) === 1) throw new AppError(409, 'CONFLICT_ERROR', 'admin.numberChecked')
        await deleteShopper(conn, id)
        await exec(
          conn,
          `INSERT INTO admin_actions (admin_user_id, action, entity_type, entity_id, reason, ip)
           VALUES (?, 'NUMBER_FREE', 'CUSTOMER', ?, ?, ?)`,
          [me(req).id, String(id), body.reason, req.ip ?? null],
        )
        publish(conn, 'ADMINS', 'customers', id)
      })
      closeStreams(id)
      return {}
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
