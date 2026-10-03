import { z } from 'zod'
import type { Context } from '../app.js'
import { one, rows } from '../db/sql.js'
import { route, type Api } from '../http/route.js'
import { urlOf } from '../lib/storage.js'
import { AdminOrder, adminOrderOf, some } from './admin-orders.js'
import { adminProductOf, adminProductsWhere } from './admin-products.js'
import { loadOrders } from './orders.js'

// Saba's first page (API_CONTRACT.md §3.2): what is waiting for an answer,
// the longest-waiting first, and the orders at a glance.

const Waiting = z
  .object({
    kind: z.enum(['store', 'product']),
    id: z.string(),
    name: z.string(),
    nameAr: z.string().optional(),
    owner: z.string(),
    imageUrl: z.string().optional(),
    since: z.string(),
  })
  .meta({ id: 'Waiting' })
type Waiting = z.infer<typeof Waiting>

export function adminDashboardRoutes(api: Api, ctx: Context): void {
  const { pool } = ctx

  route(api, {
    method: 'get',
    path: '/admin/dashboard',
    tag: 'Admin: dashboard',
    summary: 'What waits for an answer, the counts, the 5 newest orders and the 4 longest waiting',
    who: ['ADMIN'],
    response: z.object({
      storesWaiting: z.number(),
      productsWaiting: z.number(),
      stores: z.number(),
      products: z.number(),
      orders: z.number(),
      ordersByStatus: z.record(z.string(), z.number()),
      recentOrders: z.array(AdminOrder),
      waitingLongest: z.array(Waiting),
    }),
    async handle({ req }) {
      const count = async (sql: string) => Number((await one<{ n: number }>(pool, sql))?.n ?? 0)
      // The queue's own two lists (GET /admin/queue), so the numbers agree.
      const stores = await rows<{ id: number; store_name: string; logo_url: string | null; submitted_at: Date; full_name: string }>(
        pool,
        `SELECT s.id, s.store_name, s.logo_url, s.submitted_at, u.full_name
           FROM stores s JOIN users u ON u.id = s.owner_user_id WHERE s.status = 'PENDING'`,
      )
      const products = (await adminProductsWhere(pool, "AND p.status = 'PENDING'", [])).map((item) => adminProductOf(req, ctx, item))
      const byStatus = await rows<{ status: string; n: number }>(pool, 'SELECT status, COUNT(*) AS n FROM orders GROUP BY status')
      const recent = await rows<{ id: number }>(pool, 'SELECT id FROM orders ORDER BY placed_at DESC, id DESC LIMIT 5')

      const waiting: Waiting[] = [
        ...stores.map((store) => ({
          kind: 'store' as const,
          id: String(store.id),
          name: store.store_name,
          owner: store.full_name,
          ...some('imageUrl', store.logo_url === null ? null : urlOf(req, ctx.config.mediaBaseUrl, store.logo_url)),
          since: store.submitted_at.toISOString(),
        })),
        ...products.map((product) => ({
          kind: 'product' as const,
          id: product.id,
          name: product.nameEn,
          ...some('nameAr', product.nameAr || null),
          owner: product.merchant.storeName,
          ...some('imageUrl', product.imageUrl),
          since: product.createdAt,
        })),
      ]
      return {
        storesWaiting: stores.length,
        productsWaiting: products.length,
        stores: await count('SELECT COUNT(*) AS n FROM stores'),
        products: await count("SELECT COUNT(*) AS n FROM products WHERE status <> 'DRAFT' AND deleted_at IS NULL"),
        orders: await count('SELECT COUNT(*) AS n FROM orders'),
        ordersByStatus: Object.fromEntries(byStatus.map((row) => [row.status, Number(row.n)])),
        recentOrders: (
          await loadOrders(
            pool,
            recent.map((row) => row.id),
          )
        ).map((data) => adminOrderOf(req, ctx, data)),
        waitingLongest: waiting.sort((a, b) => a.since.localeCompare(b.since)).slice(0, 4),
      }
    },
  })
}
