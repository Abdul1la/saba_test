import type { Request } from 'express'
import { z } from 'zod'
import type { Context } from '../app.js'
import { exec, one, rows } from '../db/sql.js'
import { me, type SessionUser } from '../http/auth.js'
import { AppError } from '../http/errors.js'
import { governorate, IdParams } from '../http/inputs.js'
import { Page, PageQuery, route, type Api } from '../http/route.js'
import { fold, searchWords } from '../lib/fold.js'
import type { Governorate } from '../lib/governorates.js'
import { t } from '../lib/i18n.js'
import { urlOf } from '../lib/storage.js'
import { BANNER_LINK_LIVE } from './admin-catalog.js'
import { LIVE_COUPON } from './coupons.js'
import { BROWSABLE, LISTED, loadProducts, Product, ProductSummary, shaper, wishlistedAmong } from './products.js'

// What shoppers browse (BACKEND_PLAN.md §6.2, §6.3): categories, brands, the
// product list and search, a product's page, Home, coupon offers, the wishlist.

const TAG = 'Catalogue'

/** The price a shopper sees, in SQL: the sale price while a sale runs. */
const PRICE = 'IF(p.sale_price IS NOT NULL AND p.sale_ends_at > NOW(3), p.sale_price, p.base_price)'
const ON_SALE_NOW = '(p.sale_price IS NOT NULL AND p.sale_ends_at > NOW(3))'
const IN_STOCK = 'EXISTS (SELECT 1 FROM product_skus k WHERE k.product_id = p.id AND k.deleted_at IS NULL AND k.stock > 0)'

// Made once and named: it holds itself (children), and a schema rebuilt on every
// read sent the OpenAPI generator round for ever.
const Category = z
  .object({
    id: z.string(),
    name: z.string(),
    nameAr: z.string(),
    imageUrl: z.string().nullable(),
    parentId: z.string().nullable(),
    get children(): z.ZodArray<typeof Category> {
      return z.array(Category)
    },
  })
  .meta({ id: 'Category' })
type CategoryOut = z.infer<typeof Category>

const Offer = z
  .object({
    code: z.string(),
    discountType: z.enum(['PERCENTAGE', 'FIXED']),
    value: z.number(),
    currencyCode: z.literal('IQD'),
    minOrderAmount: z.number().nullable(),
    merchantId: z.string(),
    merchantName: z.string(),
  })
  .meta({ id: 'CouponOffer' })

const ListQuery = PageQuery.extend({
  q: z.string().max(100).optional(),
  categoryId: z.string().optional(),
  merchantId: z.string().optional(),
  governorate: governorate.optional(),
  deliverTo: governorate.optional(),
  brandIds: z.string().optional(),
  minPrice: z.coerce.number().optional(),
  maxPrice: z.coerce.number().optional(),
  inStock: z.enum(['true', 'false']).optional(),
  onSale: z.enum(['true', 'false']).optional(),
  sort: z.enum(['relevance', 'newest', 'price_asc', 'price_desc', 'best_selling']).optional(),
})
type ListQuery = z.infer<typeof ListQuery>

const numeric = (text: string | undefined) => (text && /^\d{1,15}$/.test(text) ? Number(text) : null)
const escapeLike = (text: string) => text.replace(/[\\%_]/g, '\\$&')

export function catalogRoutes(api: Api, ctx: Context): void {
  const { pool } = ctx

  /** A shopper's wishlist hearts, when the caller is one. */
  async function shopperOf(req: Request): Promise<number | null> {
    const user = await api.identify(req)
    return user?.role === 'CUSTOMER' ? user.id : null
  }

  // ------------------------------------------------------------- categories ---

  async function categoryTree(req: Request, user: SessionUser | null): Promise<CategoryOut[]> {
    // What Saba hid or deleted is left out, and a hidden parent's sub-categories with it (a child is only put under its parent).
    const found = await rows<{ id: number; parent_id: number | null; name: string; name_ar: string; image_url: string | null }>(
      pool,
      'SELECT id, parent_id, name, name_ar, image_url FROM categories WHERE deleted_at IS NULL AND is_hidden = 0 ORDER BY position, id',
    )
    // Admins read both names, always (contract §1.6); shoppers and stores their language.
    const arabic = req.lang === 'ar' && user?.role !== 'ADMIN'
    const out = (row: (typeof found)[number]): CategoryOut => ({
      id: String(row.id),
      name: arabic ? row.name_ar : row.name,
      nameAr: row.name_ar,
      imageUrl: row.image_url === null ? null : urlOf(req, ctx.config.mediaBaseUrl, row.image_url),
      parentId: row.parent_id === null ? null : String(row.parent_id),
      children: found.filter((child) => child.parent_id === row.id).map(out),
    })
    return found.filter((row) => row.parent_id === null).map(out)
  }

  route(api, {
    method: 'get',
    path: '/categories',
    tag: TAG,
    summary: 'The category tree',
    who: 'public',
    response: z.array(Category),
    handle: async ({ req }) => categoryTree(req, await api.identify(req)),
  })

  route(api, {
    method: 'get',
    path: '/categories/:id',
    tag: TAG,
    summary: 'One category, with its children',
    who: 'public',
    params: IdParams,
    response: Category,
    async handle({ req, params }) {
      const tree = await categoryTree(req, await api.identify(req))
      const found = [...tree, ...tree.flatMap((c) => c.children)].find((c) => c.id === params.id)
      if (!found) throw new AppError(404, 'NOT_FOUND_ERROR', 'error.notFound')
      return found
    },
  })

  route(api, {
    method: 'get',
    path: '/categories/:id/attributes',
    tag: TAG,
    summary: 'Filter chips: none in v1 (Q5)',
    who: 'public',
    params: IdParams,
    response: z.array(z.unknown()),
    handle: async () => [],
  })

  route(api, {
    method: 'get',
    path: '/brands',
    tag: TAG,
    summary: 'Brands with a listed product (in categoryId when sent), counted',
    who: 'public',
    query: z.object({ categoryId: z.string().optional() }),
    response: z.array(z.object({ id: z.string(), name: z.string(), productCount: z.number() })),
    // Only brands Saba has checked have a listed product: approving the product approves a typed brand.
    async handle({ req, query }) {
      const category = numeric(query.categoryId)
      const found = await rows<{ id: number; name: string; name_ar: string | null; n: number }>(
        pool,
        `SELECT b.id, b.name, b.name_ar, COUNT(*) AS n FROM products p JOIN stores s ON s.id = p.store_id JOIN brands b ON b.id = p.brand_id
          WHERE ${LISTED}${category === null ? '' : ' AND p.category_id IN (SELECT id FROM categories WHERE id = ? OR parent_id = ?)'}
          GROUP BY b.id, b.name, b.name_ar ORDER BY b.name`,
        category === null ? [] : [category, category],
      )
      const arabic = req.lang === 'ar'
      return found.map((row) => ({ id: String(row.id), name: arabic ? (row.name_ar ?? row.name) : row.name, productCount: Number(row.n) }))
    },
  })

  // ------------------------------------------------------------ the product list ---

  /** The browsable products [query] finds, as a page of ids, and how many in all. */
  async function browse(query: ListQuery): Promise<{ ids: number[]; total: number }> {
    const where = [BROWSABLE]
    const params: unknown[] = []
    const words = searchWords(query.q ?? '')
    for (const word of words) {
      where.push('p.search_text LIKE ?')
      params.push(`%${escapeLike(word)}%`)
    }
    const category = numeric(query.categoryId)
    if (query.categoryId !== undefined) {
      where.push('p.category_id IN (SELECT id FROM categories WHERE id = ? OR parent_id = ?)')
      params.push(category ?? 0, category ?? 0)
    }
    if (query.merchantId !== undefined) {
      where.push('p.store_id = ?')
      params.push(numeric(query.merchantId) ?? 0)
    }
    if (query.governorate) {
      where.push('s.governorate = ?')
      params.push(query.governorate)
    }
    const brands = (query.brandIds ?? '').split(',').filter(Boolean)
    if (brands.length > 0) {
      where.push('p.brand_id IN (?)')
      params.push(brands.map((b) => numeric(b) ?? 0))
    }
    if (query.minPrice !== undefined) {
      where.push(`${PRICE} >= ?`)
      params.push(query.minPrice)
    }
    if (query.maxPrice !== undefined) {
      where.push(`${PRICE} <= ?`)
      params.push(query.maxPrice)
    }
    if (query.inStock === 'true') where.push(IN_STOCK)
    if (query.onSale === 'true') where.push(`(${ON_SALE_NOW} OR p.compare_at_price IS NOT NULL)`)

    const from = `FROM products p JOIN stores s ON s.id = p.store_id WHERE ${where.join(' AND ')}`
    const sort = query.sort ?? 'relevance'
    const offset = (query.page - 1) * query.perPage

    if (sort === 'relevance' && words.length > 0) {
      // A product whose name matches before one found only by its category,
      // then newest (BACKEND_PLAN.md §2.2).
      // ponytail: every match read to rank it (a few thousand rows at most);
      // a name-only search column when the catalogue outgrows that.
      const found = await rows<{ id: number; name_en: string | null; name_ar: string }>(
        pool,
        `SELECT p.id, p.name_en, p.name_ar ${from} ORDER BY p.created_at DESC, p.id DESC`,
        params,
      )
      const named = (row: (typeof found)[number]) => {
        const text = fold(`${row.name_en ?? ''} ${row.name_ar}`)
        return words.every((word) => text.includes(word))
      }
      const ranked = [...found.filter(named), ...found.filter((row) => !named(row))]
      return { ids: ranked.slice(offset, offset + query.perPage).map((row) => row.id), total: ranked.length }
    }

    const order = {
      relevance: 'p.created_at DESC, p.id DESC',
      newest: 'p.created_at DESC, p.id DESC',
      price_asc: `${PRICE} ASC, p.id DESC`,
      price_desc: `${PRICE} DESC, p.id DESC`,
      best_selling: `(SELECT COALESCE(SUM(oi.quantity), 0) FROM order_items oi JOIN order_store_parts op ON op.id = oi.part_id
                       WHERE oi.product_id = p.id AND op.status = 'DELIVERED') DESC, p.created_at DESC, p.id DESC`,
    }[sort]
    const total = await one<{ n: number }>(pool, `SELECT COUNT(*) AS n ${from}`, params)
    const found = await rows<{ id: number }>(pool, `SELECT p.id ${from} ORDER BY ${order} LIMIT ? OFFSET ?`, [
      ...params,
      query.perPage,
      offset,
    ])
    return { ids: found.map((row) => row.id), total: Number(total?.n ?? 0) }
  }

  /**
   * The stores among [storeIds] that bring an order to [city] today: open, and
   * delivering there. A store's delivery rows are only ever saved with the
   * fee and time that cover them (PUT /merchants/me/store).
   */
  async function deliveringTo(storeIds: number[], city: Governorate): Promise<Set<number>> {
    if (storeIds.length === 0) return new Set()
    const found = await rows<{ id: number }>(
      pool,
      `SELECT s.id FROM stores s JOIN store_delivery_governorates d ON d.store_id = s.id AND d.governorate = ?
        WHERE s.id IN (?) AND s.is_open = 1`,
      [city, storeIds],
    )
    return new Set(found.map((row) => row.id))
  }

  async function summaries(req: Request, ids: number[], deliverTo?: Governorate): Promise<ProductSummary[]> {
    const loaded = await loadProducts(pool, ids)
    const shape = shaper(req, ctx, await wishlistedAmong(pool, await shopperOf(req), ids))
    const delivers = deliverTo ? await deliveringTo([...new Set(loaded.map((l) => l.row.store_id))], deliverTo) : null
    return loaded.map((item) => ({
      ...shape.summary(item),
      ...(delivers && { deliveryAvailable: delivers.has(item.row.store_id) }),
    }))
  }

  const listProducts = async (req: Request, query: ListQuery) => {
    const { ids, total } = await browse(query)
    // A search that found something counts once toward popular searches, on its first page.
    const term = query.q?.trim()
    if (term && total > 0 && query.page === 1) {
      await exec(
        pool,
        `INSERT INTO search_terms (term_key, display_text, hits) VALUES (?, ?, 1)
         ON DUPLICATE KEY UPDATE hits = hits + 1`,
        [fold(term).slice(0, 100), term.slice(0, 100)],
      )
    }
    return new Page(await summaries(req, ids, query.deliverTo), query, total)
  }

  for (const path of ['/products', '/search']) {
    route(api, {
      method: 'get',
      path,
      tag: TAG,
      summary: 'Listed products in open stores: q (every word), category, store, city, brands, price, stock, sale; sorted, paged',
      who: 'public',
      query: ListQuery,
      response: z.array(ProductSummary),
      handle: ({ req, query }) => listProducts(req, query),
    })
  }

  route(api, {
    method: 'get',
    path: '/search/suggestions',
    tag: TAG,
    summary: 'Up to 8 product names matching q, in the asked language',
    who: 'public',
    query: z.object({ q: z.string().max(100).optional() }),
    response: z.array(z.object({ text: z.string(), type: z.literal('PRODUCT'), productId: z.string() })),
    async handle({ req, query }) {
      const words = searchWords(query.q ?? '')
      if (words.length === 0) return []
      const found = await rows<{ id: number; name_en: string | null; name_ar: string }>(
        pool,
        `SELECT p.id, p.name_en, p.name_ar FROM products p JOIN stores s ON s.id = p.store_id
          WHERE ${BROWSABLE}${' AND p.search_text LIKE ?'.repeat(words.length)}
          ORDER BY p.created_at DESC, p.id DESC LIMIT 8`,
        words.map((word) => `%${escapeLike(word)}%`),
      )
      return found.map((row) => ({
        text: req.lang === 'ar' ? row.name_ar : (row.name_en ?? row.name_ar),
        type: 'PRODUCT' as const,
        productId: String(row.id),
      }))
    },
  })

  route(api, {
    method: 'get',
    path: '/search/popular',
    tag: TAG,
    summary: 'The 6 most-searched terms that found something',
    who: 'public',
    response: z.array(z.object({ text: z.string() })),
    async handle() {
      const found = await rows<{ display_text: string }>(
        pool,
        'SELECT display_text FROM search_terms ORDER BY hits DESC, updated_at DESC LIMIT 6',
      )
      return found.map((row) => ({ text: row.display_text }))
    },
  })

  // Recent searches stay on the phone (BACKEND_PLAN.md §2.2): as the demo answers.
  route(api, {
    method: 'get',
    path: '/search/history',
    tag: TAG,
    summary: 'Always empty: recent searches stay on the phone',
    who: ['CUSTOMER'],
    response: z.array(z.unknown()),
    handle: async () => [],
  })
  route(api, {
    method: 'delete',
    path: '/search/history',
    tag: TAG,
    summary: 'Nothing to clear on the server',
    who: ['CUSTOMER'],
    response: z.object({}),
    handle: async () => ({}),
  })

  // --------------------------------------------------------- a product's page ---

  route(api, {
    method: 'get',
    path: '/products/:id',
    tag: TAG,
    summary: 'A listed product in full (its own store also opens it when it is not)',
    who: 'public',
    params: IdParams,
    response: Product,
    async handle({ req, params }) {
      const user = await api.identify(req)
      const [loaded] = await loadProducts(pool, [numeric(params.id) ?? 0])
      const own =
        loaded !== undefined &&
        user?.role === 'MERCHANT' &&
        (await one(pool, 'SELECT id FROM stores WHERE id = ? AND owner_user_id = ?', [loaded.row.store_id, user.id])) !==
          undefined
      if (!loaded || loaded.row.deleted_at !== null || (loaded.row.listed !== 1 && !own)) {
        throw new AppError(404, 'NOT_FOUND_ERROR', 'product.notAvailable')
      }
      const shape = shaper(req, ctx, await wishlistedAmong(pool, user?.role === 'CUSTOMER' ? user.id : null, [loaded.row.id]))
      return shape.detail(pool, loaded)
    },
  })

  route(api, {
    method: 'get',
    path: '/products/:id/related',
    tag: TAG,
    summary: 'Up to 6 listed products of the same category',
    who: 'public',
    params: IdParams,
    response: z.array(ProductSummary),
    async handle({ req, params }) {
      const id = numeric(params.id) ?? 0
      const found = await rows<{ id: number }>(
        pool,
        `SELECT p.id FROM products p JOIN stores s ON s.id = p.store_id
          WHERE ${BROWSABLE} AND p.id <> ? AND p.category_id = (SELECT category_id FROM products WHERE id = ?)
          ORDER BY p.created_at DESC, p.id DESC LIMIT 6`,
        [id, id],
      )
      return summaries(
        req,
        found.map((row) => row.id),
      )
    },
  })

  // ------------------------------------------------------------------- Home ---

  const Section = z.object({
    id: z.string(),
    type: z.enum(['BANNER', 'CATEGORY', 'FLASH_SALE', 'COUPONS', 'MERCHANT']),
    title: z.string().optional(),
    endsAt: z.string().optional(),
    items: z.array(z.unknown()).optional(),
  })

  route(api, {
    method: 'get',
    path: '/home/sections',
    tag: TAG,
    summary: "Home: banners, categories, the running flash sales, coupons, Saba's featured stores",
    who: 'public',
    response: z.array(Section),
    async handle({ req }) {
      const url = (key: string | null) => (key === null ? null : urlOf(req, ctx.config.mediaBaseUrl, key))
      const arabic = req.lang === 'ar'
      const sections: z.infer<typeof Section>[] = []

      // Saba's banners in its order; one whose link no longer opens anything is left off. None: no section.
      const banners = await rows<{
        id: number
        title_en: string | null
        title_ar: string | null
        subtitle_en: string | null
        subtitle_ar: string | null
        image_url: string | null
        link_type: string | null
        link_id: number | null
      }>(
        pool,
        `SELECT b.id, b.title_en, b.title_ar, b.subtitle_en, b.subtitle_ar, b.image_url, b.link_type, b.link_id
           FROM home_banners b WHERE b.is_active = 1 AND ${BANNER_LINK_LIVE} ORDER BY b.position, b.id`,
      )
      if (banners.length > 0) {
        const pick = (en: string | null, ar: string | null) => (arabic ? (ar ?? en) : (en ?? ar))
        sections.push({
          id: 's-banners',
          type: 'BANNER',
          items: banners.map((b) => ({
            id: String(b.id),
            ...(pick(b.title_en, b.title_ar) !== null && { title: pick(b.title_en, b.title_ar) }),
            ...(pick(b.subtitle_en, b.subtitle_ar) !== null && { subtitle: pick(b.subtitle_en, b.subtitle_ar) }),
            imageUrl: url(b.image_url),
            link: b.link_type === null ? null : { type: b.link_type, id: String(b.link_id) },
          })),
        })
      }

      sections.push({
        id: 's-categories',
        type: 'CATEGORY',
        title: t(req.lang, 'home.categories'),
        items: await categoryTree(req, null),
      })

      // Running sales, open stores, in stock, the soonest to end first.
      const onSale = await rows<{ id: number; sale_ends_at: Date }>(
        pool,
        `SELECT p.id, p.sale_ends_at FROM products p JOIN stores s ON s.id = p.store_id
          WHERE ${BROWSABLE} AND ${ON_SALE_NOW} AND ${IN_STOCK}
          ORDER BY p.sale_ends_at, p.id LIMIT 20`,
      )
      if (onSale.length > 0) {
        sections.push({
          id: 's-flash',
          type: 'FLASH_SALE',
          endsAt: onSale[0]!.sale_ends_at.toISOString(),
          items: await summaries(
            req,
            onSale.map((row) => row.id),
          ),
        })
      }

      // No items: the offers come from /coupons.
      sections.push({ id: 's-coupons', type: 'COUPONS' })

      // Saba's featured stores, approved ones only, in Saba's order; left out when none (D28).
      const featured = await rows<{
        id: number
        store_name: string
        logo_url: string | null
        banner_url: string | null
        rating_sum: number
        rating_count: number
        governorate: Governorate
        is_open: number
        listed: number
      }>(
        pool,
        `SELECT s.id, s.store_name, s.logo_url, s.banner_url, s.rating_sum, s.rating_count, s.governorate, s.is_open,
                (SELECT COUNT(*) FROM products p WHERE p.store_id = s.id AND ${LISTED}) AS listed
           FROM featured_stores f JOIN stores s ON s.id = f.store_id
          WHERE s.status = 'APPROVED' ORDER BY f.position`,
      )
      if (featured.length > 0) {
        sections.push({
          id: 's-merchants',
          type: 'MERCHANT',
          items: featured.map((s) => ({
            id: String(s.id),
            storeName: s.store_name,
            logoUrl: url(s.logo_url),
            bannerUrl: url(s.banner_url),
            rating: s.rating_count ? Math.round((s.rating_sum / s.rating_count) * 10) / 10 : null,
            reviewCount: s.rating_count,
            governorate: s.governorate,
            isOpen: s.is_open === 1,
            productCount: Number(s.listed),
          })),
        })
      }
      return sections
    },
  })

  // ------------------------------------------------------------ coupon offers ---

  async function liveOffers(storeId: number | null) {
    const found = await rows<{
      code: string
      discount_type: 'PERCENTAGE' | 'FIXED'
      value: number
      min_order_amount: number | null
      store_id: number
      store_name: string
    }>(
      pool,
      `SELECT c.code, c.discount_type, c.value, c.min_order_amount, c.store_id, s.store_name
         FROM coupons c JOIN stores s ON s.id = c.store_id
        WHERE ${LIVE_COUPON}${storeId === null ? '' : ' AND c.store_id = ?'}
        ORDER BY c.id DESC`,
      storeId === null ? [] : [storeId],
    )
    return found.map((c) => ({
      code: c.code,
      discountType: c.discount_type,
      value: c.value,
      currencyCode: 'IQD' as const,
      minOrderAmount: c.min_order_amount,
      merchantId: String(c.store_id),
      merchantName: c.store_name,
    }))
  }

  route(api, {
    method: 'get',
    path: '/coupons',
    tag: TAG,
    summary: "Every live store coupon, as an offer (Home's strip, the cart)",
    who: 'public',
    response: z.array(Offer),
    handle: () => liveOffers(null),
  })

  route(api, {
    method: 'get',
    path: '/merchants/:id/coupons',
    tag: TAG,
    summary: "A store's live coupons, as offers",
    who: 'public',
    params: IdParams,
    response: z.array(Offer),
    handle: ({ params }) => liveOffers(numeric(params.id) ?? 0),
  })

  // --------------------------------------------------------------- wishlist ---

  route(api, {
    method: 'get',
    path: '/wishlist/items',
    tag: 'Wishlist',
    summary: "The shopper's wishlist: listed products, the latest added first",
    who: ['CUSTOMER'],
    response: z.array(ProductSummary),
    async handle({ req }) {
      const found = await rows<{ product_id: number }>(
        pool,
        `SELECT w.product_id FROM wishlist_items w JOIN products p ON p.id = w.product_id JOIN stores s ON s.id = p.store_id
          WHERE w.user_id = ? AND ${LISTED} ORDER BY w.created_at DESC, w.product_id DESC`,
        [me(req).id],
      )
      return summaries(
        req,
        found.map((row) => row.product_id),
      )
    },
  })

  route(api, {
    method: 'post',
    path: '/wishlist/items',
    tag: 'Wishlist',
    summary: 'Add a listed product',
    who: ['CUSTOMER'],
    body: z.object({ productId: z.string() }),
    response: z.object({}),
    async handle({ req, body }) {
      const id = numeric(body.productId) ?? 0
      const listed = await one(pool, `SELECT p.id FROM products p JOIN stores s ON s.id = p.store_id WHERE p.id = ? AND ${LISTED}`, [
        id,
      ])
      if (!listed) throw new AppError(404, 'NOT_FOUND_ERROR', 'product.notAvailable')
      await exec(pool, 'INSERT IGNORE INTO wishlist_items (user_id, product_id) VALUES (?, ?)', [me(req).id, id])
      return {}
    },
  })

  route(api, {
    method: 'delete',
    path: '/wishlist/items/:id',
    tag: 'Wishlist',
    summary: 'Take a product off the wishlist',
    who: ['CUSTOMER'],
    params: IdParams,
    response: z.object({}),
    async handle({ req, params }) {
      await exec(pool, 'DELETE FROM wishlist_items WHERE user_id = ? AND product_id = ?', [me(req).id, numeric(params.id) ?? 0])
      return {}
    },
  })
}
