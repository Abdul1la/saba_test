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
import { publish } from '../lib/events.js'
import { notify } from '../lib/notify.js'
import { optionPrice, productPrice, saleIsOn, stockStatus } from '../lib/pricing.js'
import { urlOf } from '../lib/storage.js'
import { anyOf, likeFolded, ListQuery, pageSql, paged } from './admin-lists.js'
import { loadProducts, type Loaded } from './products.js'

// Saba's answers on products (API_CONTRACT.md §3.5, §6.8), plus the fields
// the audit asks for: descriptionAr, warrantyAr, sku, saleEndsAt, option
// fields, and inShop with its reason (D-P1). Nothing is translated: an admin
// reads both languages (contract §1.6).

const TAG = 'Admin: products'
const ADMIN = ['ADMIN'] as const

const StockStatus = z.enum(['IN_STOCK', 'LOW_STOCK', 'OUT_OF_STOCK'])

export const AdminProduct = z
  .object({
    id: z.string(),
    nameEn: z.string(),
    nameAr: z.string(),
    description: z.string().optional(),
    descriptionAr: z.string().optional(),
    price: z.number(),
    originalPrice: z.number().optional(),
    discountPercentage: z.number().optional(),
    saleEndsAt: z.string().optional(),
    currencyCode: z.literal('IQD'),
    stockStatus: StockStatus,
    availableQuantity: z.number(),
    sku: z.string().optional(),
    categoryId: z.string(),
    categoryName: z.string(),
    categoryNameAr: z.string(),
    /** isNew: a brand a store typed, still waiting for Saba's check; approving the product approves it. */
    brand: z.object({ id: z.string(), name: z.string(), nameAr: z.string().nullable(), isNew: z.boolean() }).optional(),
    merchant: z.object({ id: z.string(), storeName: z.string(), status: z.enum(['PENDING', 'APPROVED', 'REJECTED', 'SUSPENDED']) }),
    imageUrl: z.string().optional(),
    images: z.array(z.object({ id: z.string(), url: z.string(), isPrimary: z.boolean() })),
    warranty: z.string().optional(),
    warrantyAr: z.string().optional(),
    variants: z.array(
      z.object({
        id: z.string(),
        price: z.number(),
        originalPrice: z.number().optional(),
        availableQuantity: z.number(),
        stockStatus: StockStatus,
        options: z.record(z.string(), z.string()),
        optionLabel: z.string(),
        sku: z.string().optional(),
      }),
    ),
    createdAt: z.string(),
    status: z.enum(['DRAFT', 'PENDING', 'APPROVED', 'REJECTED']),
    rejectionReason: z.string().optional(),
    isActive: z.boolean(),
    takenDown: z.boolean(),
    takenDownReason: z.string().optional(),
    // D-P1: whether shoppers can see it now, and why not (a code the web translates).
    inShop: z.boolean(),
    notInShopReason: z.enum(['NOT_APPROVED', 'HIDDEN_BY_STORE', 'TAKEN_DOWN', 'STORE_NOT_APPROVED', 'STORE_CLOSED']).optional(),
  })
  .meta({ id: 'AdminProduct' })
export type AdminProduct = z.infer<typeof AdminProduct>

/** [loaded] as the admin reads it. */
export function adminProductOf(req: Request, ctx: Context, { row, skus, images }: Loaded): AdminProduct {
  const now = new Date()
  const url = (key: string) => urlOf(req, ctx.config.mediaBaseUrl, key)
  const stock = skus.reduce((sum, sku) => sum + sku.stock, 0)
  const shown = productPrice(row, now)
  const single = skus.find((sku) => sku.options === null)
  const notInShop: AdminProduct['notInShopReason'] =
    row.status !== 'APPROVED'
      ? 'NOT_APPROVED'
      : row.taken_down === 1
        ? 'TAKEN_DOWN'
        : row.is_active === 0
          ? 'HIDDEN_BY_STORE'
          : row.store_status !== 'APPROVED'
            ? 'STORE_NOT_APPROVED'
            : row.store_open === 0
              ? 'STORE_CLOSED'
              : undefined
  const optional = <K extends string, V>(key: K, value: V | null | undefined) =>
    (value === null || value === undefined ? {} : { [key]: value }) as Partial<Record<K, V>>
  return {
    id: String(row.id),
    nameEn: row.name_en ?? '',
    nameAr: row.name_ar,
    ...optional('description', row.description),
    ...optional('descriptionAr', row.description_ar),
    price: shown.price,
    ...optional('originalPrice', shown.originalPrice),
    ...optional('discountPercentage', shown.discountPercentage),
    ...optional('saleEndsAt', saleIsOn(row, now) ? row.sale_ends_at!.toISOString() : null),
    currencyCode: 'IQD',
    stockStatus: stockStatus(stock),
    availableQuantity: stock,
    ...optional('sku', single?.sku_code),
    categoryId: String(row.category_id),
    categoryName: row.category_name,
    categoryNameAr: row.category_name_ar,
    ...optional(
      'brand',
      row.brand_id === null
        ? null
        : { id: String(row.brand_id), name: row.brand_name!, nameAr: row.brand_name_ar, isNew: row.brand_status === 'PENDING' },
    ),
    merchant: { id: String(row.store_id), storeName: row.store_name, status: row.store_status as AdminProduct['merchant']['status'] },
    ...optional('imageUrl', images[0] ? url(images[0].url) : null),
    images: images.map((image, index) => ({ id: String(image.id), url: url(image.url), isPrimary: index === 0 })),
    ...optional('warranty', row.warranty),
    ...optional('warrantyAr', row.warranty_ar),
    variants: skus
      .filter((sku) => sku.options !== null)
      .map((sku) => {
        const price = optionPrice(row, sku.price!, now)
        return {
          id: String(sku.id),
          price: price.price,
          ...optional('originalPrice', price.originalPrice),
          availableQuantity: sku.stock,
          stockStatus: stockStatus(sku.stock),
          options: sku.options!,
          optionLabel: sku.option_label!,
          ...optional('sku', sku.sku_code),
        }
      }),
    // "The web shows it as when it was sent for review."
    createdAt: (row.submitted_at ?? row.created_at).toISOString(),
    status: row.status,
    ...optional('rejectionReason', row.rejection_reason),
    isActive: row.is_active === 1,
    takenDown: row.taken_down === 1,
    ...optional('takenDownReason', row.taken_down_reason),
    inShop: notInShop === undefined,
    ...optional('notInShopReason', notInShop),
  }
}

/** Products the admin sees (never drafts, never deleted), [where] more, newest first. */
export async function adminProductsWhere(db: Pool | Connection, where: string, params: unknown[], order = 'COALESCE(p.submitted_at, p.created_at) DESC, p.id DESC') {
  const found = await rows<{ id: number }>(
    db,
    `SELECT p.id FROM products p WHERE p.status <> 'DRAFT' AND p.deleted_at IS NULL ${where} ORDER BY ${order}`,
    params,
  )
  return loadProducts(
    db,
    found.map((row) => row.id),
  )
}

const Reason = z.object({ reason: requiredText(500) })

export function adminProductRoutes(api: Api, ctx: Context): void {
  const { pool } = ctx

  route(api, {
    method: 'get',
    path: '/admin/products',
    tag: TAG,
    summary: 'Products (no drafts), newest first, with counts: status, q, categoryId, storeId',
    who: ADMIN,
    query: z.object({
      status: z.enum(['PENDING', 'APPROVED', 'REJECTED', 'TAKEN_DOWN']).optional(),
      q: z.string().optional(),
      categoryId: z.string().optional(),
      storeId: z.string().optional(),
      ...ListQuery,
    }),
    response: z.object({ items: z.array(AdminProduct), counts: z.record(z.string(), z.number()) }),
    async handle({ req, query }) {
      const where: string[] = []
      const params: unknown[] = []
      const numeric = (text: string) => (/^\d{1,15}$/.test(text) ? Number(text) : 0)
      if (query.categoryId !== undefined) {
        where.push(' AND p.category_id IN (SELECT id FROM categories WHERE id = ? OR parent_id = ?)')
        params.push(numeric(query.categoryId), numeric(query.categoryId))
      }
      if (query.storeId !== undefined) {
        where.push(' AND p.store_id = ?')
        params.push(numeric(query.storeId))
      }
      // In the database: the name in either language and its category
      // (products.search_text), or its store's name and address (stores.search_text).
      const q = query.q ?? ''
      const [search, searchParams] = anyOf(q, [['p.search_text LIKE ? OR s.search_text LIKE ?', [likeFolded(q), likeFolded(q)]]])
      const base = `FROM products p JOIN stores s ON s.id = p.store_id
                    WHERE p.status <> 'DRAFT' AND p.deleted_at IS NULL${where.join('')}${search}`
      // Each product counts once: a taken-down one only under TAKEN_DOWN.
      const counts: Record<string, number> = { all: 0 }
      const buckets = await rows<{ bucket: string; n: number }>(
        pool,
        `SELECT IF(p.taken_down = 1, 'TAKEN_DOWN', p.status) AS bucket, COUNT(*) AS n ${base} GROUP BY bucket`,
        [...params, ...searchParams],
      )
      for (const row of buckets) {
        counts[row.bucket] = Number(row.n)
        counts.all! += Number(row.n)
      }
      const [only, onlyParams] =
        query.status === undefined ? ['', []] : query.status === 'TAKEN_DOWN' ? [' AND p.taken_down = 1', []] : [' AND p.taken_down = 0 AND p.status = ?', [query.status]]
      const ids = await rows<{ id: number }>(
        pool,
        `SELECT p.id ${base}${only} ORDER BY COALESCE(p.submitted_at, p.created_at) DESC, p.id DESC${pageSql(query)}`,
        [...params, ...searchParams, ...onlyParams],
      )
      const items = (await loadProducts(pool, ids.map((row) => row.id))).map((item) => adminProductOf(req, ctx, item))
      return paged({ items, counts }, query, query.status ? (counts[query.status] ?? 0) : counts.all!)
    },
  })

  async function productById(db: Pool | Connection, req: Request, id: number): Promise<AdminProduct> {
    const [found] = await adminProductsWhere(db, 'AND p.id = ?', [id])
    if (!found) throw notFound()
    return adminProductOf(req, ctx, found)
  }

  route(api, {
    method: 'get',
    path: '/admin/products/:id',
    tag: TAG,
    summary: 'One product',
    who: ADMIN,
    params: IdParams,
    response: AdminProduct,
    handle: ({ req, params }) => productById(pool, req, idOf(params.id)),
  })

  /**
   * One answer on product [id]: a conditional update from where it must be
   * (0 rows is 404 or 409), the audit row, and the store told, together.
   */
  async function answer(
    req: Request,
    id: number,
    step: {
      when: string
      set: string
      params: unknown[]
      action: string
      reason?: string
      tell?: { title: MessageKey; body: MessageKey }
      check?: (conn: Connection) => Promise<void>
    },
  ): Promise<AdminProduct> {
    return withTransaction(pool, async (conn) => {
      const product = await one<{ store_id: number; name_en: string | null; name_ar: string }>(
        conn,
        "SELECT store_id, name_en, name_ar FROM products WHERE id = ? AND status <> 'DRAFT' AND deleted_at IS NULL FOR UPDATE",
        [id],
      )
      if (!product) throw notFound()
      await step.check?.(conn)
      const changed = await exec(conn, `UPDATE products SET ${step.set} WHERE id = ? AND ${step.when}`, [...step.params, id])
      if (changed.affectedRows === 0) throw new AppError(409, 'CONFLICT_ERROR', 'admin.wrongState')
      await exec(
        conn,
        `INSERT INTO admin_actions (admin_user_id, action, entity_type, entity_id, reason, ip)
         VALUES (?, ?, 'PRODUCT', ?, ?, ?)`,
        [me(req).id, step.action, String(id), step.reason ?? null, req.ip ?? null],
      )
      if (step.tell) {
        const store = await one<{ owner_user_id: number }>(conn, 'SELECT owner_user_id FROM stores WHERE id = ?', [product.store_id])
        const name = { en: product.name_en ?? product.name_ar, ar: product.name_ar }
        const words = (lang: 'en' | 'ar') => ({
          title: t(lang, step.tell!.title, { name }),
          body: t(lang, step.tell!.body, { reason: step.reason ?? '' }),
        })
        await notify(conn, store!.owner_user_id, 'PRODUCT_APPROVAL', { en: words('en'), ar: words('ar') }, { type: 'STORE_PRODUCT', id })
      }
      publish(conn, 'ADMINS', 'products', id)
      return productById(conn, req, id)
    })
  }

  route(api, {
    method: 'post',
    path: '/admin/products/:id/approve',
    tag: TAG,
    summary: 'Approve a waiting product; it needs its Arabic name. The store is told.',
    who: ADMIN,
    params: IdParams,
    response: AdminProduct,
    handle: ({ req, params }) => {
      const id = idOf(params.id)
      return answer(req, id, {
        when: "status = 'PENDING'",
        set: "status = 'APPROVED', rejection_reason = NULL",
        params: [],
        action: 'PRODUCT_APPROVE',
        tell: { title: 'notify.productApproved.title', body: 'notify.productApproved.body' },
        async check(conn) {
          const row = await one<{ name_ar: string }>(conn, 'SELECT name_ar FROM products WHERE id = ?', [id])
          if (!row || row.name_ar.trim().length < 3 || !/[؀-ۿ]/.test(row.name_ar)) {
            throw new AppError(422, 'BUSINESS_RULE_ERROR', 'product.nameAr', undefined, { nameAr: { key: 'product.nameAr' } })
          }
          // A brand its store typed was checked with it (the user's call C): approved too.
          await exec(conn, "UPDATE brands b JOIN products p ON p.brand_id = b.id SET b.status = 'APPROVED' WHERE p.id = ? AND b.status = 'PENDING'", [id])
        },
      })
    },
  })

  route(api, {
    method: 'post',
    path: '/admin/products/:id/reject',
    tag: TAG,
    summary: 'Turn a waiting product down, with a reason; the store is told',
    who: ADMIN,
    params: IdParams,
    body: Reason,
    response: AdminProduct,
    handle: ({ req, params, body }) =>
      answer(req, idOf(params.id), {
        when: "status = 'PENDING'",
        set: "status = 'REJECTED', rejection_reason = ?",
        params: [body.reason],
        action: 'PRODUCT_REJECT',
        reason: body.reason,
        tell: { title: 'notify.productRejected.title', body: 'notify.productRejected.body' },
      }),
  })

  route(api, {
    method: 'post',
    path: '/admin/products/:id/hide',
    tag: TAG,
    summary: "Take an approved product out of the shop (Saba's takedown); the store is told why",
    who: ADMIN,
    params: IdParams,
    body: Reason,
    response: AdminProduct,
    handle: ({ req, params, body }) =>
      answer(req, idOf(params.id), {
        when: "status = 'APPROVED' AND taken_down = 0",
        set: 'taken_down = 1, taken_down_reason = ?',
        params: [body.reason],
        action: 'PRODUCT_TAKE_DOWN',
        reason: body.reason,
        tell: { title: 'notify.productTakenDown.title', body: 'notify.productTakenDown.body' },
      }),
  })

  route(api, {
    method: 'post',
    path: '/admin/products/:id/unhide',
    tag: TAG,
    summary: 'Put a taken-down product back in the shop; the store is told',
    who: ADMIN,
    params: IdParams,
    response: AdminProduct,
    handle: ({ req, params }) =>
      answer(req, idOf(params.id), {
        when: 'taken_down = 1',
        set: 'taken_down = 0, taken_down_reason = NULL',
        params: [],
        action: 'PRODUCT_RESTORE',
        tell: { title: 'notify.productRestored.title', body: 'notify.productRestored.body' },
      }),
  })
}

function idOf(text: string): number {
  if (!/^\d{1,15}$/.test(text)) throw notFound()
  return Number(text)
}

function notFound(): AppError {
  return new AppError(404, 'NOT_FOUND_ERROR', 'error.notFound')
}
