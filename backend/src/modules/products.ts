import type { Request } from 'express'
import { z } from 'zod'
import type { Context } from '../app.js'
import type { Connection, Pool } from '../db/pool.js'
import { exec, rows } from '../db/sql.js'
import { fold } from '../lib/fold.js'
import { GOVERNORATES, type Governorate } from '../lib/governorates.js'
import type { Lang } from '../lib/i18n.js'
import { optionPrice, productPrice, saleIsOn, stockStatus } from '../lib/pricing.js'
import { urlOf } from '../lib/storage.js'
import { deliveryAreas, StoreDelivery } from './stores.js'

// Products as they are read: the one "for sale" rule, and the shapes the app
// reads (catalog_mappers.dart) (DATABASE_DESIGN.md §3.3).

/**
 * For sale ("listed"), one rule everywhere: approved, the store's switch on,
 * not taken down by Saba, not deleted, and its store approved. Needs `p` and `s`.
 */
export const LISTED = `p.status = 'APPROVED' AND p.is_active = 1 AND p.taken_down = 0 AND p.deleted_at IS NULL AND s.status = 'APPROVED'`

/** What a product is found by: its names and its category's and parent's names, folded (the app's search_text.dart). */
export function productSearchText(names: (string | null | undefined)[]): string {
  return fold(names.join(' ')).slice(0, 500)
}

/**
 * Rebuilds the search text of the live products [where] picks (`p` the
 * product, `c` its category) once Saba renamed or moved their category.
 * Their updated_at stays: the store changed nothing.
 */
export async function refreshSearchText(conn: Connection, where: string, params: unknown[]): Promise<void> {
  const found = await rows<{ id: number; name_en: string | null; name_ar: string; c: string; c_ar: string; pc: string | null; pc_ar: string | null }>(
    conn,
    `SELECT p.id, p.name_en, p.name_ar, c.name AS c, c.name_ar AS c_ar, pc.name AS pc, pc.name_ar AS pc_ar
       FROM products p JOIN categories c ON c.id = p.category_id LEFT JOIN categories pc ON pc.id = c.parent_id
      WHERE p.deleted_at IS NULL AND (${where})`,
    params,
  )
  for (const p of found) {
    await exec(conn, 'UPDATE products SET search_text = ?, updated_at = updated_at WHERE id = ?', [
      productSearchText([p.name_en, p.name_ar, p.pc, p.pc_ar, p.c, p.c_ar]),
      p.id,
    ])
  }
}

/** Browsing (search, categories, Home, related, a store's page) also needs the store open. */
export const BROWSABLE = `${LISTED} AND s.is_open = 1`

const StockStatus = z.enum(['IN_STOCK', 'LOW_STOCK', 'OUT_OF_STOCK'])

const MerchantFace = z.object({
  id: z.string(),
  storeName: z.string(),
  governorate: z.enum(GOVERNORATES),
  logoUrl: z.string().nullable(),
})

export const ProductSummary = z
  .object({
    id: z.string(),
    name: z.string(),
    nameEn: z.string().nullable(),
    nameAr: z.string(),
    price: z.number(),
    originalPrice: z.number().nullable(),
    discountPercentage: z.number().nullable(),
    currencyCode: z.literal('IQD'),
    stockStatus: StockStatus,
    availableQuantity: z.number(),
    imageUrl: z.string().nullable(),
    merchant: MerchantFace,
    brand: z.object({ id: z.string(), name: z.string() }).nullable(),
    hasVariants: z.boolean(),
    isFlashSale: z.boolean(),
    saleEndsAt: z.string().nullable(),
    createdAt: z.string(),
    isWishlisted: z.boolean(),
    deliveryAvailable: z.boolean().optional(),
  })
  .meta({ id: 'ProductSummary' })
export type ProductSummary = z.infer<typeof ProductSummary>

export const Variant = z.object({
  id: z.string(),
  sku: z.string().nullable(),
  price: z.number(),
  originalPrice: z.number().nullable(),
  discountPercentage: z.number().nullable(),
  availableQuantity: z.number(),
  stockStatus: StockStatus,
  options: z.record(z.string(), z.string()),
})

export const Product = ProductSummary.extend({
  description: z.string().nullable(),
  descriptionAr: z.string().nullable(),
  warranty: z.string().nullable(),
  warrantyAr: z.string().nullable(),
  sku: z.string().nullable(),
  categoryId: z.string(),
  categoryName: z.string(),
  categoryNameAr: z.string(),
  images: z.array(z.object({ id: z.string(), url: z.string(), isPrimary: z.boolean() })),
  variants: z.array(Variant),
  optionColours: z.record(z.string(), z.string()),
  sizeGuide: z.string().nullable(),
  merchant: MerchantFace.extend({
    rating: z.number().nullable(),
    reviewCount: z.number(),
    isOpen: z.boolean(),
    delivery: StoreDelivery.optional(),
  }),
  isListed: z.boolean(),
  // The store's own view needs where its product stands.
  status: z.enum(['DRAFT', 'PENDING', 'APPROVED', 'REJECTED']),
  rejectionReason: z.string().nullable(),
  isActive: z.boolean(),
  takenDown: z.boolean(),
  takenDownReason: z.string().nullable(),
}).meta({ id: 'Product' })
export type Product = z.infer<typeof Product>

export interface ProductRow {
  id: number
  store_id: number
  category_id: number
  brand_id: number | null
  brand_name: string | null
  brand_name_ar: string | null
  brand_status: 'APPROVED' | 'PENDING' | null
  name_en: string | null
  name_ar: string
  description: string | null
  description_ar: string | null
  warranty: string | null
  warranty_ar: string | null
  base_price: number
  compare_at_price: number | null
  sale_price: number | null
  sale_ends_at: Date | null
  status: Product['status']
  rejection_reason: string | null
  is_active: number
  taken_down: number
  taken_down_reason: string | null
  option_colours: Record<string, string> | null
  size_guide: string | null
  submitted_at: Date | null
  created_at: Date
  deleted_at: Date | null
  category_name: string
  category_name_ar: string
  store_name: string
  store_governorate: Governorate
  store_logo: string | null
  store_status: string
  store_open: number
  rating_sum: number
  rating_count: number
  fee_inside: number | null
  time_inside: string | null
  fee_outside: number | null
  time_outside: string | null
  listed: number
}

export interface SkuRow {
  id: number
  product_id: number
  options: Record<string, string> | null
  option_label: string | null
  sku_code: string | null
  price: number | null
  stock: number
}

const PRODUCT_SELECT = `
  SELECT p.id, p.store_id, p.category_id, p.brand_id, b.name AS brand_name, b.name_ar AS brand_name_ar, b.status AS brand_status, p.name_en, p.name_ar,
         p.description, p.description_ar, p.warranty, p.warranty_ar, p.base_price, p.compare_at_price,
         p.sale_price, p.sale_ends_at, p.status, p.rejection_reason, p.is_active, p.taken_down,
         p.taken_down_reason, p.option_colours, p.size_guide, p.submitted_at, p.created_at, p.deleted_at,
         c.name AS category_name, c.name_ar AS category_name_ar,
         s.store_name, s.governorate AS store_governorate, s.logo_url AS store_logo, s.status AS store_status,
         s.is_open AS store_open, s.rating_sum, s.rating_count, s.fee_inside, s.time_inside, s.fee_outside,
         s.time_outside, (${LISTED}) AS listed
    FROM products p
    JOIN stores s ON s.id = p.store_id
    JOIN categories c ON c.id = p.category_id
    LEFT JOIN brands b ON b.id = p.brand_id`

export interface Loaded {
  row: ProductRow
  skus: SkuRow[]
  images: { id: number; url: string }[]
}

/** [ids], with their options and photos, in the order given; missing ids are left out. */
export async function loadProducts(db: Pool | Connection, ids: number[]): Promise<Loaded[]> {
  if (ids.length === 0) return []
  const found = await rows<ProductRow>(db, `${PRODUCT_SELECT} WHERE p.id IN (?)`, [ids])
  const skus = await rows<SkuRow>(
    db,
    `SELECT id, product_id, options, option_label, sku_code, price, stock FROM product_skus
      WHERE product_id IN (?) AND deleted_at IS NULL ORDER BY id`,
    [ids],
  )
  const images = await rows<{ id: number; product_id: number; url: string }>(
    db,
    'SELECT id, product_id, url FROM product_images WHERE product_id IN (?) ORDER BY position',
    [ids],
  )
  const byId = new Map(found.map((row) => [row.id, row]))
  return ids.flatMap((id) => {
    const row = byId.get(id)
    if (!row) return []
    return [{ row, skus: skus.filter((s) => s.product_id === id), images: images.filter((i) => i.product_id === id) }]
  })
}

/** The shape builders for one request: its language, its addresses, one clock. */
export function shaper(req: Request, ctx: Context, wishlisted: Set<number> = new Set()) {
  const now = new Date()
  const lang: Lang = req.lang
  const url = (key: string | null) => (key === null ? null : urlOf(req, ctx.config.mediaBaseUrl, key))
  const inLang = (text: string | null, arabic: string | null) =>
    lang === 'ar' ? (arabic ?? text) : (text ?? arabic)

  function summary({ row, skus, images }: Loaded): ProductSummary {
    const stock = skus.reduce((sum, sku) => sum + sku.stock, 0)
    const price = productPrice(row, now)
    const onSale = saleIsOn(row, now)
    return {
      id: String(row.id),
      name: inLang(row.name_en, row.name_ar)!,
      nameEn: row.name_en,
      nameAr: row.name_ar,
      ...price,
      currencyCode: 'IQD',
      stockStatus: stockStatus(stock),
      availableQuantity: stock,
      imageUrl: url(images[0]?.url ?? null),
      merchant: {
        id: String(row.store_id),
        storeName: row.store_name,
        governorate: row.store_governorate,
        logoUrl: url(row.store_logo),
      },
      brand: row.brand_id === null ? null : { id: String(row.brand_id), name: inLang(row.brand_name, row.brand_name_ar)! },
      hasVariants: skus.some((sku) => sku.options !== null),
      isFlashSale: onSale,
      saleEndsAt: onSale ? row.sale_ends_at!.toISOString() : null,
      createdAt: row.created_at.toISOString(),
      isWishlisted: wishlisted.has(row.id),
    }
  }

  async function detail(db: Pool | Connection, loaded: Loaded): Promise<Product> {
    const { row, skus, images } = loaded
    const areas = (await deliveryAreas(db, [row.store_id])).get(row.store_id)!
    const single = skus.find((sku) => sku.options === null)
    const delivery =
      row.fee_inside === null
        ? undefined
        : StoreDelivery.parse({
            governorates: areas,
            feeInside: row.fee_inside,
            timeInside: row.time_inside,
            ...(row.fee_outside !== null && { feeOutside: row.fee_outside, timeOutside: row.time_outside }),
          })
    return {
      ...summary(loaded),
      description: inLang(row.description, row.description_ar),
      descriptionAr: row.description_ar,
      warranty: inLang(row.warranty, row.warranty_ar),
      warrantyAr: row.warranty_ar,
      sku: single?.sku_code ?? null,
      categoryId: String(row.category_id),
      categoryName: lang === 'ar' ? row.category_name_ar : row.category_name,
      categoryNameAr: row.category_name_ar,
      images: images.map((image, index) => ({ id: String(image.id), url: url(image.url)!, isPrimary: index === 0 })),
      variants: skus
        .filter((sku) => sku.options !== null)
        .map((sku) => ({
          id: String(sku.id),
          sku: sku.sku_code,
          ...optionPrice(row, sku.price!, now),
          availableQuantity: sku.stock,
          stockStatus: stockStatus(sku.stock),
          options: sku.options!,
        })),
      optionColours: row.option_colours ?? {},
      sizeGuide: row.size_guide,
      merchant: {
        ...summary(loaded).merchant,
        rating: row.rating_count ? Math.round((row.rating_sum / row.rating_count) * 10) / 10 : null,
        reviewCount: row.rating_count,
        isOpen: row.store_open === 1,
        ...(delivery && { delivery }),
      },
      isListed: row.listed === 1,
      status: row.status,
      rejectionReason: row.rejection_reason,
      isActive: row.is_active === 1,
      takenDown: row.taken_down === 1,
      takenDownReason: row.taken_down_reason,
    }
  }

  return { now, lang, url, inLang, summary, detail }
}

/** The shopper's wishlisted products among [ids] (none for anyone else). */
export async function wishlistedAmong(db: Pool | Connection, userId: number | null, ids: number[]): Promise<Set<number>> {
  if (userId === null || ids.length === 0) return new Set()
  const found = await rows<{ product_id: number }>(
    db,
    'SELECT product_id FROM wishlist_items WHERE user_id = ? AND product_id IN (?)',
    [userId, ids],
  )
  return new Set(found.map((row) => row.product_id))
}
