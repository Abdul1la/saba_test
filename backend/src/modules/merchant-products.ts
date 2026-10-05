import type { Request } from 'express'
import { z } from 'zod'
import type { Context } from '../app.js'
import type { Connection, Pool } from '../db/pool.js'
import { exec, one, rows } from '../db/sql.js'
import { withTransaction } from '../db/tx.js'
import { me } from '../http/auth.js'
import { AppError, type FieldMessage } from '../http/errors.js'
import { IdParams, optionalText } from '../http/inputs.js'
import { Page, PageQuery, route, type Api } from '../http/route.js'
import { fold, searchWords } from '../lib/fold.js'
import { publish } from '../lib/events.js'
import type { MessageKey } from '../lib/i18n.js'
import { LOW_STOCK_AT_MOST, productPrice, saleIsOn, saleOff, stockStatus } from '../lib/pricing.js'
import { settingOn } from '../lib/settings.js'
import { keyOf } from '../lib/storage.js'
import { loadProducts, Product, productSearchText, shaper, type Loaded } from './products.js'

// The store's own products (BACKEND_PLAN.md §6.5): the shelf, the product
// form, submit, show or hide, stock, flash sales and the inventory. Every
// change to a stock is locked and written to stock_movements in the same
// transaction (DATABASE_DESIGN.md §3.3, §5.2).

const TAG = 'Store: products'
const STORE = ['MERCHANT'] as const
const MAX_STOCK = 99_999

/** A price a store types: whole IQD, at least 250, in steps of 250 (the smallest note). */
const price = z
  .number()
  .int()
  .min(250)
  .max(1_000_000_000)
  .refine((value) => value % 250 === 0, { error: 'field.steps250' })

const stock = z.number().int().min(0).max(MAX_STOCK)

const VariantInput = z.object({
  id: z.string().nullish(),
  sku: optionalText(40),
  price: price.nullish(),
  stock: stock.default(0),
  // The stock the form showed: an edit changes a stock only when it differs (see editedStock).
  stockBefore: stock.nullish(),
  options: z
    .array(z.object({ name: z.string().trim().min(1, { error: 'field.required' }).max(40), value: z.string().trim().min(1, { error: 'field.required' }).max(40) }))
    .min(1),
})

const ProductInput = z.object({
  name: z.string().trim().max(120).nullish(),
  nameAr: z.string().trim().max(120).default(''),
  // Missing means unchanged: the form leaves a field it didn't show out.
  description: z.string().trim().max(5000).nullish(),
  warranty: z.string().trim().max(120).nullish(),
  categoryId: z.string(),
  brandId: z.string().nullish(),
  // A brand typed rather than picked (the user's call C, 2026-10-01): the one
  // of that name, or a new one waiting for Saba's check. It wins over brandId.
  brandName: z.string().trim().max(60).nullish(),
  price,
  originalPrice: price.nullish(),
  sku: optionalText(40),
  stock: stock.default(0),
  stockBefore: stock.nullish(),
  images: z.array(z.string()).max(10).optional(),
  variants: z.array(VariantInput).max(100).default([]),
})
type ProductInput = z.infer<typeof ProductInput>

const Row = z
  .object({
    id: z.string(),
    name: z.string(),
    nameAr: z.string(),
    price: z.number(),
    originalPrice: z.number().nullable(),
    saleEndsAt: z.string().nullable(),
    currencyCode: z.literal('IQD'),
    status: Product.shape.status,
    imageUrl: z.string().nullable(),
    sku: z.string().nullable(),
    stock: z.number(),
    lowStockThreshold: z.number(),
    // Sold in options: its stock is set per option, so the shelf offers no stepper.
    hasVariants: z.boolean(),
    isActive: z.boolean(),
    takenDown: z.boolean(),
    takenDownReason: z.string().nullable(),
    rejectionReason: z.string().nullable(),
  })
  .meta({ id: 'StoreProductRow' })

/** Every live product of [storeId], newest first, with its options and photos. */
export async function shelfOf(db: Pool | Connection, storeId: number): Promise<Loaded[]> {
  const ids = await rows<{ id: number }>(
    db,
    'SELECT id FROM products WHERE store_id = ? AND deleted_at IS NULL ORDER BY created_at DESC, id DESC',
    [storeId],
  )
  return loadProducts(
    db,
    ids.map((row) => row.id),
  )
}

const stockOf = (loaded: Loaded) => loaded.skus.reduce((sum, sku) => sum + sku.stock, 0)
const waiting = (loaded: Loaded) => loaded.row.status === 'PENDING' || loaded.row.status === 'DRAFT'
/** The shelf's tabs; the store's dashboard counts the same way. */
export const shelfFilters: Record<'waiting' | 'low' | 'out' | 'hidden', (loaded: Loaded) => boolean> = {
  waiting,
  low: (loaded) => stockOf(loaded) > 0 && stockOf(loaded) <= LOW_STOCK_AT_MOST,
  out: (loaded) => stockOf(loaded) <= 0,
  hidden: (loaded) => loaded.row.is_active === 0,
}

/** One product as a row of the store's shelf (the app's MerchantProductRow). */
export function shelfRow(shape: ReturnType<typeof shaper>, loaded: Loaded): z.infer<typeof Row> {
  const { row, skus } = loaded
  const shown = productPrice(row, shape.now)
  return {
    id: String(row.id),
    name: shape.inLang(row.name_en, row.name_ar)!,
    nameAr: row.name_ar,
    price: shown.price,
    originalPrice: shown.originalPrice,
    saleEndsAt: saleIsOn(row, shape.now) ? row.sale_ends_at!.toISOString() : null,
    currencyCode: 'IQD' as const,
    status: row.status,
    imageUrl: shape.url(loaded.images[0]?.url ?? null),
    sku: skus.find((sku) => sku.options === null)?.sku_code ?? null,
    stock: stockOf(loaded),
    lowStockThreshold: LOW_STOCK_AT_MOST,
    hasVariants: skus.some((sku) => sku.options !== null),
    isActive: row.is_active === 1,
    takenDown: row.taken_down === 1,
    takenDownReason: row.taken_down_reason,
    rejectionReason: row.rejection_reason,
  }
}
export { Row as ShelfRow }

const InventoryRow = z
  .object({
    id: z.string(),
    productId: z.string(),
    name: z.string(),
    variantLabel: z.string().nullable(),
    sku: z.string().nullable(),
    imageUrl: z.string().nullable(),
    available: z.number(),
    reserved: z.number(),
    sold: z.number(),
    lowStockThreshold: z.number(),
  })
  .meta({ id: 'InventoryRow' })

export function merchantProductRoutes(api: Api, ctx: Context): void {
  const { pool } = ctx

  async function storeOf(db: Pool | Connection, req: Request): Promise<{ id: number; owner: number }> {
    const store = await one<{ id: number }>(db, 'SELECT id FROM stores WHERE owner_user_id = ?', [me(req).id])
    if (!store) throw notFound()
    return { id: store.id, owner: me(req).id }
  }

  /** Every live product of the store, newest first, with its options and photos. */
  const shelf = async (req: Request): Promise<Loaded[]> => shelfOf(pool, (await storeOf(pool, req)).id)

  route(api, {
    method: 'get',
    path: '/merchants/me/products',
    tag: TAG,
    summary: "The store's shelf: status, filter (waiting, low, out, hidden), q; paged",
    who: STORE,
    query: PageQuery.extend({
      status: z.enum(['DRAFT', 'PENDING', 'APPROVED', 'REJECTED']).optional(),
      filter: z.enum(['waiting', 'low', 'out', 'hidden']).optional(),
      q: z.string().optional(),
    }),
    response: z.array(Row),
    async handle({ req, query }) {
      const shape = shaper(req, ctx)
      const words = searchWords(query.q ?? '')
      const found = (await shelf(req)).filter((loaded) => {
        if (query.status && loaded.row.status !== query.status) return false
        if (query.filter && !shelfFilters[query.filter](loaded)) return false
        const text = fold([loaded.row.name_en, loaded.row.name_ar, ...loaded.skus.map((s) => s.sku_code)].join(' '))
        return words.every((word) => text.includes(word))
      })
      const start = (query.page - 1) * query.perPage
      const items = found.slice(start, start + query.perPage).map((loaded) => shelfRow(shape, loaded))
      return new Page(items, query, found.length)
    },
  })

  route(api, {
    method: 'get',
    path: '/merchants/me/products/counts',
    tag: TAG,
    summary: 'How many on each tab of the shelf',
    who: STORE,
    response: z.object({ all: z.number(), waiting: z.number(), low: z.number(), out: z.number(), hidden: z.number() }),
    async handle({ req }) {
      const all = await shelf(req)
      const count = (test: (loaded: Loaded) => boolean) => all.filter(test).length
      return {
        all: all.length,
        waiting: count(shelfFilters.waiting),
        low: count(shelfFilters.low),
        out: count(shelfFilters.out),
        hidden: count(shelfFilters.hidden),
      }
    },
  })

  /** The store's own live product, locked when [lock] (one change at a time). */
  async function ownProduct(db: Pool | Connection, req: Request, id: string, lock = false) {
    const store = await storeOf(db, req)
    const found = await one<{ id: number; status: string; taken_down: number; base_price: number; compare_at_price: number | null; sale_price: number | null; sale_ends_at: Date | null }>(
      db,
      `SELECT id, status, taken_down, base_price, compare_at_price, sale_price, sale_ends_at FROM products
        WHERE id = ? AND store_id = ? AND deleted_at IS NULL${lock ? ' FOR UPDATE' : ''}`,
      [idOf(id), store.id],
    )
    if (!found) throw notFound()
    return { ...found, store }
  }

  async function detailOf(db: Pool | Connection, req: Request, id: number) {
    const [loaded] = await loadProducts(db, [id])
    return shaper(req, ctx).detail(db, loaded!)
  }

  route(api, {
    method: 'get',
    path: '/merchants/me/products/:id',
    tag: TAG,
    summary: 'One of its own products, in full, whatever its status',
    who: STORE,
    params: IdParams,
    response: Product,
    async handle({ req, params }) {
      const product = await ownProduct(pool, req, params.id)
      return detailOf(pool, req, product.id)
    },
  })

  route(api, {
    method: 'get',
    path: '/merchants/me/brands',
    tag: TAG,
    summary: "The brands a store picks from, by name: Saba's checked ones and those its own products use. Any other name can be typed (brandName)",
    who: STORE,
    response: z.array(z.object({ id: z.string(), name: z.string(), nameAr: z.string().nullable() })),
    async handle({ req }) {
      const store = await storeOf(pool, req)
      const found = await rows<{ id: number; name: string; name_ar: string | null }>(
        pool,
        `SELECT id, name, name_ar FROM brands
          WHERE status = 'APPROVED' OR id IN (SELECT brand_id FROM products WHERE store_id = ? AND deleted_at IS NULL)
          ORDER BY name, id`,
        [store.id],
      )
      return found.map((row) => ({ id: String(row.id), name: row.name, nameAr: row.name_ar }))
    },
  })

  route(api, {
    method: 'post',
    path: '/merchants/me/products',
    tag: TAG,
    summary: 'A new product; it waits for Saba (PENDING)',
    who: STORE,
    body: ProductInput,
    response: Product,
    async handle({ req, body }) {
      const store = await storeOf(pool, req)
      checkNameAr(body.nameAr)
      const id = await withTransaction(pool, async (conn) => {
        const refs = await references(conn, body, store.owner, null)
        const inserted = await exec(
          conn,
          `INSERT INTO products (store_id, category_id, brand_id, name_en, name_ar, description, warranty,
                                 base_price, compare_at_price, status, submitted_at, search_text)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'PENDING', NOW(3), ?)`,
          [
            store.id,
            refs.categoryId,
            refs.brandId,
            body.name || null,
            body.nameAr,
            body.description || null,
            body.warranty || null,
            body.price,
            normalOriginal(body),
            refs.searchText,
          ],
        )
        const productId = inserted.insertId
        await saveImages(conn, productId, refs.images ?? [])
        await saveSkus(conn, productId, body, body.price, 0, me(req).id)
        // It waits in Saba's queue, unless Saba's switch approves it at once.
        await approveIfAuto(conn, productId)
        publish(conn, 'ADMINS', 'products', productId)
        return productId
      })
      return detailOf(pool, req, id)
    },
  })

  route(api, {
    method: 'put',
    path: '/merchants/me/products/:id',
    tag: TAG,
    summary: 'Save a product; its status and any running sale stay (BACKEND_PLAN.md §9 item 4)',
    who: STORE,
    params: IdParams,
    body: ProductInput,
    response: Product,
    async handle({ req, params, body }) {
      checkNameAr(body.nameAr)
      const id = await withTransaction(pool, async (conn) => {
        const product = await ownProduct(conn, req, params.id, true)
        const refs = await references(conn, body, product.store.owner, product.id)
        const now = new Date()
        const shownBefore = await shownOf(conn, product.id)

        // During a sale the form shows the sale price as `price` and the
        // normal price as `originalPrice`, and each option at its sale price:
        // read them back that way, and add the sale's discount back on.
        let base: number
        let compareAt: number | null
        let salePrice: number | null = null
        let off = 0
        if (saleIsOn(product, now)) {
          base = body.originalPrice ?? product.base_price
          salePrice = body.price
          if (salePrice >= base) throw fieldError('price', 'product.saleBelowNormal')
          off = base - salePrice
          compareAt = product.compare_at_price !== null && product.compare_at_price > base ? product.compare_at_price : null
        } else {
          base = body.price
          compareAt = normalOriginal(body)
        }

        const kept = (await one<{ brand_id: number | null; description: string | null; description_ar: string | null; warranty: string | null; warranty_ar: string | null }>(
          conn,
          'SELECT brand_id, description, description_ar, warranty, warranty_ar FROM products WHERE id = ?',
          [product.id],
        ))!
        await exec(
          conn,
          `UPDATE products SET category_id = ?, brand_id = ?, name_en = ?, name_ar = ?, base_price = ?,
                               compare_at_price = ?, sale_price = ?, sale_ends_at = ?, search_text = ?
            WHERE id = ?`,
          [
            refs.categoryId,
            // The form sends no brand: it keeps its own (null clears it).
            body.brandId === undefined && !body.brandName ? kept.brand_id : refs.brandId,
            body.name || null,
            body.nameAr,
            base,
            compareAt,
            salePrice,
            salePrice === null ? null : product.sale_ends_at,
            refs.searchText,
            product.id,
          ],
        )
        // A field it sent replaces both languages, unless it is what the form
        // showed in the reader's language: then both stay (as the store's own
        // settings do). One it left out stays.
        const shown = (text: string | null, arabic: string | null) => (req.lang === 'ar' ? (arabic ?? text) : (text ?? arabic))
        if (body.description != null && (body.description || null) !== shown(kept.description, kept.description_ar)) {
          await exec(conn, 'UPDATE products SET description = ?, description_ar = NULL WHERE id = ?', [
            body.description || null,
            product.id,
          ])
        }
        if (body.warranty != null && (body.warranty || null) !== shown(kept.warranty, kept.warranty_ar)) {
          await exec(conn, 'UPDATE products SET warranty = ?, warranty_ar = NULL WHERE id = ?', [
            body.warranty || null,
            product.id,
          ])
        }
        if (refs.images !== undefined) await saveImages(conn, product.id, refs.images)
        await saveSkus(conn, product.id, body, base, off, me(req).id)
        // What shoppers read changed on an approved product: back to Saba before
        // it is shown again (the reviewer's item 8). Prices and stock need no review.
        if (product.status === 'APPROVED' && (await shownOf(conn, product.id)) !== shownBefore) {
          await exec(conn, "UPDATE products SET status = 'PENDING', submitted_at = NOW(3) WHERE id = ?", [product.id])
          publish(conn, 'ADMINS', 'products', product.id)
        }
        // Saba's switch on: nothing waits, not even what was waiting before it.
        if (await approveIfAuto(conn, product.id)) publish(conn, 'ADMINS', 'products', product.id)
        return product.id
      })
      return detailOf(pool, req, id)
    },
  })

  route(api, {
    method: 'delete',
    path: '/merchants/me/products/:id',
    tag: TAG,
    summary: 'Delete a product: marked deleted, and taken out of every cart and wishlist',
    who: STORE,
    params: IdParams,
    response: z.object({}),
    async handle({ req, params }) {
      await withTransaction(pool, async (conn) => {
        const product = await ownProduct(conn, req, params.id, true)
        await exec(conn, 'UPDATE products SET deleted_at = NOW(3) WHERE id = ?', [product.id])
        await exec(conn, 'DELETE FROM cart_items WHERE sku_id IN (SELECT id FROM product_skus WHERE product_id = ?)', [
          product.id,
        ])
        await exec(conn, 'DELETE FROM wishlist_items WHERE product_id = ?', [product.id])
      })
      return {}
    },
  })

  route(api, {
    method: 'post',
    path: '/merchants/me/products/:id/submit',
    tag: TAG,
    summary: 'Send a draft or a rejected product to Saba again',
    who: STORE,
    params: IdParams,
    response: z.object({}),
    async handle({ req, params }) {
      const product = await ownProduct(pool, req, params.id)
      const changed = await exec(
        pool,
        `UPDATE products SET status = 'PENDING', submitted_at = NOW(3), rejection_reason = NULL
          WHERE id = ? AND status IN ('DRAFT', 'REJECTED')`,
        [product.id],
      )
      if (changed.affectedRows === 0) throw new AppError(409, 'CONFLICT_ERROR', 'admin.wrongState')
      await approveIfAuto(pool, product.id)
      publish(pool, 'ADMINS', 'products', product.id)
      return {}
    },
  })

  route(api, {
    method: 'post',
    path: '/merchants/me/products/:id/visibility',
    tag: TAG,
    summary: "Show or hide a product (the store's switch); refused when Saba took it down",
    who: STORE,
    params: IdParams,
    body: z.object({ isActive: z.boolean() }),
    response: z.object({}),
    async handle({ req, params, body }) {
      const product = await ownProduct(pool, req, params.id)
      const changed = await exec(pool, 'UPDATE products SET is_active = ? WHERE id = ? AND taken_down = 0', [
        body.isActive,
        product.id,
      ])
      if (changed.affectedRows === 0) throw new AppError(409, 'CONFLICT_ERROR', 'product.takenDown')
      return {}
    },
  })

  route(api, {
    method: 'patch',
    path: '/merchants/me/products/:id/stock',
    tag: TAG,
    summary: 'Set the stock of a product without options',
    who: STORE,
    params: IdParams,
    body: z.object({ stock }),
    response: z.object({ stock: z.number() }),
    async handle({ req, params, body }) {
      return withTransaction(pool, async (conn) => {
        const product = await ownProduct(conn, req, params.id)
        const skus = await rows<{ id: number; options: unknown; stock: number }>(
          conn,
          'SELECT id, options, stock FROM product_skus WHERE product_id = ? AND deleted_at IS NULL FOR UPDATE',
          [product.id],
        )
        const single = skus.find((sku) => sku.options === null)
        if (!single || skus.length !== 1) throw new AppError(422, 'BUSINESS_RULE_ERROR', 'product.hasOptions')
        await setStock(conn, single.id, single.stock, body.stock, 'SET', me(req).id)
        return { stock: body.stock }
      })
    },
  })

  route(api, {
    method: 'post',
    path: '/merchants/me/products/:id/flash-sale',
    tag: TAG,
    summary: 'Start a flash sale, or change the one running: listed products only',
    who: STORE,
    params: IdParams,
    body: z.object({ salePrice: z.number(), saleEndsAt: z.string() }),
    response: z.object({}),
    async handle({ req, params, body }) {
      await withTransaction(pool, async (conn) => {
        const product = await ownProduct(conn, req, params.id, true)
        const listed = await one(
          conn,
          `SELECT 1 FROM products p JOIN stores s ON s.id = p.store_id
            WHERE p.id = ? AND p.status = 'APPROVED' AND p.is_active = 1 AND p.taken_down = 0 AND s.status = 'APPROVED'`,
          [product.id],
        )
        // Only what shoppers can see: a hidden product took a sale nobody saw (the demo).
        if (!listed) throw new AppError(409, 'CONFLICT_ERROR', 'product.notForSale')

        const errors: Record<string, FieldMessage> = {}
        const sale = body.salePrice
        const ends = new Date(body.saleEndsAt)
        // The price before any sale: the normal price.
        const normal = product.base_price
        if (!Number.isInteger(sale) || sale <= 0) errors.salePrice = { key: 'field.required' }
        else if (sale % 250 !== 0) errors.salePrice = { key: 'field.steps250' }
        else if (sale >= normal) errors.salePrice = { key: 'product.saleBelowNormal' }
        if (Number.isNaN(ends.getTime()) || ends <= new Date()) errors.saleEndsAt = { key: 'product.saleEnd' }
        if (!errors.salePrice) {
          // Each option comes down by the same amount; none may drop below 250.
          const cheapest = await one<{ price: number | null }>(
            conn,
            'SELECT MIN(price) AS price FROM product_skus WHERE product_id = ? AND deleted_at IS NULL AND options IS NOT NULL',
            [product.id],
          )
          if (cheapest?.price != null && cheapest.price - (normal - sale) < 250) {
            errors.salePrice = { key: 'product.saleTooDeep' }
          }
        }
        const first = Object.values(errors)[0]
        if (first) throw new AppError(422, 'VALIDATION_ERROR', first.key, undefined, errors)
        await exec(conn, 'UPDATE products SET sale_price = ?, sale_ends_at = ? WHERE id = ?', [sale, ends, product.id])
      })
      return {}
    },
  })

  route(api, {
    method: 'delete',
    path: '/merchants/me/products/:id/flash-sale',
    tag: TAG,
    summary: 'End the flash sale now',
    who: STORE,
    params: IdParams,
    response: z.object({}),
    async handle({ req, params }) {
      const product = await ownProduct(pool, req, params.id)
      await exec(pool, 'UPDATE products SET sale_price = NULL, sale_ends_at = NULL WHERE id = ?', [product.id])
      return {}
    },
  })

  route(api, {
    method: 'get',
    path: '/merchants/me/inventory',
    tag: TAG,
    summary: 'A row per thing sold: available, reserved in open orders, sold',
    who: STORE,
    query: PageQuery,
    response: z.array(InventoryRow),
    async handle({ req, query }) {
      const store = await storeOf(pool, req)
      const shape = shaper(req, ctx)
      const where = 'FROM product_skus k JOIN products p ON p.id = k.product_id WHERE p.store_id = ? AND p.deleted_at IS NULL AND k.deleted_at IS NULL'
      const total = await one<{ n: number }>(pool, `SELECT COUNT(*) AS n ${where}`, [store.id])
      const found = await rows<{
        id: number
        product_id: number
        name_en: string | null
        name_ar: string
        option_label: string | null
        sku_code: string | null
        stock: number
        image: string | null
        reserved: number | null
        sold: number | null
      }>(
        pool,
        `SELECT k.id, k.product_id, p.name_en, p.name_ar, k.option_label, k.sku_code, k.stock,
                (SELECT url FROM product_images i WHERE i.product_id = p.id ORDER BY position LIMIT 1) AS image,
                (SELECT SUM(oi.quantity) FROM order_items oi JOIN order_store_parts op ON op.id = oi.part_id
                  WHERE oi.sku_id = k.id AND op.status IN ('PENDING', 'CONFIRMED', 'PROCESSING', 'SHIPPED')) AS reserved,
                (SELECT SUM(oi.quantity) FROM order_items oi JOIN order_store_parts op ON op.id = oi.part_id
                  WHERE oi.sku_id = k.id AND op.status = 'DELIVERED') AS sold
           ${where} ORDER BY p.created_at DESC, p.id DESC, k.id LIMIT ? OFFSET ?`,
        [store.id, query.perPage, (query.page - 1) * query.perPage],
      )
      return new Page(
        found.map((row) => ({
          id: String(row.id),
          productId: String(row.product_id),
          name: shape.inLang(row.name_en, row.name_ar)!,
          variantLabel: row.option_label,
          sku: row.sku_code,
          imageUrl: shape.url(row.image),
          available: row.stock,
          reserved: Number(row.reserved ?? 0),
          sold: Number(row.sold ?? 0),
          lowStockThreshold: LOW_STOCK_AT_MOST,
        })),
        query,
        Number(total?.n ?? 0),
      )
    },
  })

  route(api, {
    method: 'post',
    path: '/merchants/me/inventory/:id/adjust',
    tag: TAG,
    summary: 'Change a stock by a quantity (+ or −); never below 0',
    who: STORE,
    params: IdParams,
    body: z.object({ quantity: z.number().int().min(-MAX_STOCK).max(MAX_STOCK), reason: z.string().max(200).nullish() }),
    response: z.object({ available: z.number() }),
    async handle({ req, params, body }) {
      const store = await storeOf(pool, req)
      return withTransaction(pool, async (conn) => {
        const sku = await one<{ id: number; stock: number }>(
          conn,
          `SELECT k.id, k.stock FROM product_skus k JOIN products p ON p.id = k.product_id
            WHERE k.id = ? AND p.store_id = ? AND p.deleted_at IS NULL AND k.deleted_at IS NULL FOR UPDATE`,
          [idOf(params.id), store.id],
        )
        if (!sku) throw notFound()
        const next = Math.min(MAX_STOCK, Math.max(0, sku.stock + body.quantity))
        await setStock(conn, sku.id, sku.stock, next, 'ADJUSTED', me(req).id)
        return { available: next }
      })
    },
  })

  // ------------------------------------------------------------- saving ---

  /**
   * The category, brand and photos a save names, checked; and the search text.
   * The category and brand are read FOR SHARE: one Saba is deleting at that
   * moment is waited for, so no product lands in a deleted one. (An edit locks
   * its product first and a removal its category or brand first; should the
   * two ever meet, InnoDB stops one and withTransaction runs it again.)
   */
  async function references(conn: Connection, body: ProductInput, ownerId: number, productId: number | null) {
    const categoryId = /^\d{1,9}$/.test(body.categoryId) ? Number(body.categoryId) : 0
    const category = await one<{ name: string; name_ar: string; parent_name: string | null; parent_name_ar: string | null; hidden: number }>(
      conn,
      `SELECT c.name, c.name_ar, pc.name AS parent_name, pc.name_ar AS parent_name_ar,
              c.is_hidden = 1 OR COALESCE(pc.is_hidden, 0) = 1 AS hidden
         FROM categories c LEFT JOIN categories pc ON pc.id = c.parent_id WHERE c.id = ? AND c.deleted_at IS NULL FOR SHARE`,
      [categoryId],
    )
    if (!category) throw fieldError('categoryId', 'field.invalid')
    // Hidden by Saba: not for new products; a product already in it may stay.
    if (category.hidden) {
      const current = productId === null ? undefined : await one<{ category_id: number }>(conn, 'SELECT category_id FROM products WHERE id = ?', [productId])
      if (current?.category_id !== categoryId) throw fieldError('categoryId', 'category.hidden')
    }
    let brandId: number | null = null
    const typed = body.brandName?.replace(/\s+/g, ' ')
    if (typed) {
      // The same name in either language, whatever its case, is that brand (the columns ignore case and accents).
      // Found, then locked by its key alone: a locking read on name_ar would lock every brand.
      const known = await one<{ id: number }>(conn, 'SELECT id FROM brands WHERE name = ? OR name_ar = ? LIMIT 1', [typed, typed])
      brandId =
        known && (await one(conn, 'SELECT id FROM brands WHERE id = ? FOR SHARE', [known.id]))
          ? known.id
          : (await exec(conn, "INSERT INTO brands (name, status) VALUES (?, 'PENDING') ON DUPLICATE KEY UPDATE id = LAST_INSERT_ID(id)", [typed]))
              .insertId
    } else if (body.brandId) {
      brandId = /^\d{1,9}$/.test(body.brandId) ? Number(body.brandId) : 0
      if (!(await one(conn, 'SELECT id FROM brands WHERE id = ? FOR SHARE', [brandId]))) throw fieldError('brandId', 'field.invalid')
    }
    let images: string[] | undefined
    if (body.images !== undefined) {
      images = []
      for (const url of body.images) {
        const key = keyOf(url, ctx.config.mediaBaseUrl)
        // Its own upload, or a photo the product already has (spec §51).
        const allowed =
          key !== null &&
          ((await one(conn, 'SELECT id FROM media_files WHERE storage_key = ? AND owner_user_id = ? AND deleted_at IS NULL', [
            key,
            ownerId,
          ])) ||
            (productId !== null &&
              (await one(conn, 'SELECT id FROM product_images WHERE product_id = ? AND url = ?', [productId, key]))))
        if (!allowed) throw fieldError('images', 'media.notUploaded')
        if (!images.includes(key)) images.push(key)
      }
    }
    const signatures = body.variants.map((variant) =>
      JSON.stringify([...variant.options].map((o) => [o.name, o.value]).sort()),
    )
    if (new Set(signatures).size !== signatures.length) throw fieldError('variants', 'product.duplicateOption')
    const searchText = productSearchText([body.name, body.nameAr, category.parent_name, category.parent_name_ar, category.name, category.name_ar])
    return { categoryId, brandId, images, searchText }
  }

  async function saveImages(conn: Connection, productId: number, keys: string[]): Promise<void> {
    await exec(conn, 'DELETE FROM product_images WHERE product_id = ?', [productId])
    if (keys.length > 0) {
      await exec(conn, 'INSERT INTO product_images (product_id, url, position) VALUES ?', [
        keys.map((key, position) => [productId, key, position]),
      ])
    }
  }

  /**
   * The things sold, as the form sent them: one row for a product without
   * options, one per option otherwise. Options are matched by id; a new one
   * gets a new id (BUGS 163); one left out is marked deleted (old orders
   * point at it). [off] is a running sale's discount, added back onto each
   * option's price. Every stock that moves is written to the ledger.
   */
  async function saveSkus(conn: Connection, productId: number, body: ProductInput, base: number, off: number, actor: number) {
    const live = await rows<{ id: number; options: unknown; stock: number }>(
      conn,
      'SELECT id, options, stock FROM product_skus WHERE product_id = ? AND deleted_at IS NULL FOR UPDATE',
      [productId],
    )
    const kept = new Set<number>()

    if (body.variants.length === 0) {
      const single = live.find((sku) => sku.options === null)
      if (single) {
        await exec(conn, 'UPDATE product_skus SET sku_code = ? WHERE id = ?', [body.sku, single.id])
        await setStock(conn, single.id, single.stock, editedStock(body.stock, body.stockBefore, single.stock), 'PRODUCT_SAVED', actor)
        kept.add(single.id)
      } else {
        const inserted = await exec(conn, 'INSERT INTO product_skus (product_id, sku_code, stock) VALUES (?, ?, 0)', [
          productId,
          body.sku,
        ])
        await setStock(conn, inserted.insertId, 0, body.stock, 'PRODUCT_SAVED', actor)
        kept.add(inserted.insertId)
      }
    } else {
      for (const variant of body.variants) {
        const options = Object.fromEntries(variant.options.map((o) => [o.name, o.value]))
        const label = variant.options.map((o) => o.value).join(' · ').slice(0, 120)
        const optionPrice = variant.price == null ? base : variant.price + off
        const match = live.find((sku) => sku.options !== null && String(sku.id) === variant.id && !kept.has(sku.id))
        if (match) {
          await exec(conn, 'UPDATE product_skus SET options = ?, option_label = ?, sku_code = ?, price = ? WHERE id = ?', [
            JSON.stringify(options),
            label,
            variant.sku,
            optionPrice,
            match.id,
          ])
          await setStock(conn, match.id, match.stock, editedStock(variant.stock, variant.stockBefore, match.stock, label), 'PRODUCT_SAVED', actor)
          kept.add(match.id)
        } else {
          const inserted = await exec(
            conn,
            'INSERT INTO product_skus (product_id, options, option_label, sku_code, price, stock) VALUES (?, ?, ?, ?, ?, 0)',
            [productId, JSON.stringify(options), label, variant.sku, optionPrice],
          )
          await setStock(conn, inserted.insertId, 0, variant.stock, 'PRODUCT_SAVED', actor)
          kept.add(inserted.insertId)
        }
      }
    }
    const gone = live.filter((sku) => !kept.has(sku.id)).map((sku) => sku.id)
    if (gone.length > 0) await exec(conn, 'UPDATE product_skus SET deleted_at = NOW(3) WHERE id IN (?)', [gone])
  }
}

/**
 * The stock an edit leaves on a thing already sold ([now], read under its
 * lock): the store's number only when it changed the box. Sent without the
 * stock the form showed, or unchanged, the stock stays: units sold while the
 * form was open never come back. Changed while stock moved underneath:
 * refused, so neither number is lost.
 */
function editedStock(sent: number, before: number | null | undefined, now: number, option?: string): number {
  if (before == null || sent === before) return now
  if (now !== before) {
    throw option === undefined
      ? new AppError(409, 'CONFLICT_ERROR', 'product.stockMoved', { stock: now })
      : new AppError(409, 'CONFLICT_ERROR', 'product.optionStockMoved', { option, stock: now })
  }
  return sent
}

/** [skuId]'s stock from [from] (read under its lock) to [to], with its ledger row. */
async function setStock(
  conn: Connection,
  skuId: number,
  from: number,
  to: number,
  reason: 'SET' | 'ADJUSTED' | 'PRODUCT_SAVED',
  actor: number,
): Promise<void> {
  if (to === from) return
  await exec(conn, 'UPDATE product_skus SET stock = ? WHERE id = ?', [to, skuId])
  await exec(conn, 'INSERT INTO stock_movements (sku_id, delta, reason, actor_user_id) VALUES (?, ?, ?, ?)', [
    skuId,
    to - from,
    reason,
    actor,
  ])
}

/**
 * What Saba approved of product [id], as one string: its names, words,
 * category, brand, photos and option names. Prices, stock and codes are left
 * out: they change without a review.
 */
async function shownOf(conn: Connection, id: number): Promise<string> {
  const product = await one(
    conn,
    'SELECT name_en, name_ar, description, description_ar, warranty, warranty_ar, category_id, brand_id FROM products WHERE id = ?',
    [id],
  )
  const photos = await rows<{ url: string }>(conn, 'SELECT url FROM product_images WHERE product_id = ? ORDER BY position', [id])
  const options = await rows<{ option_label: string | null }>(
    conn,
    'SELECT option_label FROM product_skus WHERE product_id = ? AND deleted_at IS NULL ORDER BY option_label',
    [id],
  )
  return JSON.stringify([product, photos.map((p) => p.url), options.map((o) => o.option_label)])
}

/** A lasting original price: above the price, or none. */
function normalOriginal(body: ProductInput): number | null {
  if (body.originalPrice == null) return null
  if (body.originalPrice <= body.price) throw fieldError('originalPrice', 'product.originalAbovePrice')
  return body.originalPrice
}

/** Every product has its Arabic name: 3 or more letters, with an Arabic one (`_noArabicName`). */
/**
 * Saba's switch (admin website, migration 0013): on, a waiting product is
 * approved at once, with what an admin's approval does besides (a brand its
 * store typed is approved with it). One whose Arabic name an admin would turn
 * down keeps waiting for them. The store is not told: it just saved it.
 * Whether it was approved.
 */
async function approveIfAuto(db: Pool | Connection, productId: number): Promise<boolean> {
  if (!(await settingOn(db, 'auto_approve_products'))) return false
  const row = await one<{ name_ar: string }>(db, "SELECT name_ar FROM products WHERE id = ? AND status = 'PENDING'", [productId])
  if (!row || row.name_ar.trim().length < 3 || !/[؀-ۿ]/.test(row.name_ar)) return false
  const changed = await exec(db, "UPDATE products SET status = 'APPROVED', rejection_reason = NULL WHERE id = ? AND status = 'PENDING'", [productId])
  if (changed.affectedRows === 0) return false
  await exec(db, "UPDATE brands b JOIN products p ON p.brand_id = b.id SET b.status = 'APPROVED' WHERE p.id = ? AND b.status = 'PENDING'", [productId])
  return true
}

export function checkNameAr(nameAr: string): void {
  if (!/[؀-ۿ]/.test(nameAr)) throw fieldError('nameAr', 'product.nameAr')
  // Arabic, but too short: say that, not "write it in Arabic" (M3).
  if (nameAr.trim().length < 3) {
    const tooShort: FieldMessage = { key: 'field.tooShort', params: { min: 3 } }
    throw new AppError(422, 'VALIDATION_ERROR', tooShort.key, tooShort.params, { nameAr: tooShort })
  }
}

function fieldError(field: string, key: MessageKey): AppError {
  return new AppError(422, 'VALIDATION_ERROR', key, undefined, { [field]: { key } })
}

function idOf(text: string): number {
  if (!/^\d{1,15}$/.test(text)) throw notFound()
  return Number(text)
}

function notFound(): AppError {
  return new AppError(404, 'NOT_FOUND_ERROR', 'error.notFound')
}

export { saleOff, stockStatus }
