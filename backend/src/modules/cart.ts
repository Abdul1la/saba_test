import type { Request } from 'express'
import { z } from 'zod'
import type { Context } from '../app.js'
import type { Connection, Pool } from '../db/pool.js'
import { exec, one, rows } from '../db/sql.js'
import { withTransaction } from '../db/tx.js'
import { me } from '../http/auth.js'
import { AppError } from '../http/errors.js'
import { IdParams, optionalText } from '../http/inputs.js'
import { route, type Api } from '../http/route.js'
import { GOVERNORATES, governorateNames, type Governorate } from '../lib/governorates.js'
import { t, type Lang, type MessageKey, type MessageParams } from '../lib/i18n.js'
import { couponDiscount, grouped } from '../lib/money.js'
import { optionPrice, productPrice, stockStatus } from '../lib/pricing.js'
import { urlOf } from '../lib/storage.js'
import { FIRST_ORDER_LIMIT } from '../rules.js'
import { COUPON_COLUMNS, LIVE_COUPON, type CouponRow } from './coupons.js'
import { LISTED, loadProducts, type Loaded } from './products.js'
import { DELIVERY_TIMES } from './stores.js'

// The cart, and the one pricing function it shares with checkout's review and
// with placing an order, so the three can never disagree (BACKEND_PLAN.md
// §6.3; the numbers are DATABASE_DESIGN.md §6).

type DeliveryTime = (typeof DELIVERY_TIMES)[number]

/** One line to price: a cart row (its id), or a Buy now line (none). */
export interface LineIn {
  id: number | null
  skuId: number
  quantity: number
}

interface SkuRow {
  id: number
  product_id: number
  options: Record<string, string> | null
  option_label: string | null
  sku_code: string | null
  price: number | null
  stock: number
  deleted_at: Date | null
}

export interface StoreTerms {
  id: number
  owner: number
  name: string
  logo: string | null
  governorate: Governorate
  approved: boolean
  open: boolean
  feeInside: number | null
  timeInside: DeliveryTime | null
  feeOutside: number | null
  timeOutside: DeliveryTime | null
  areas: Set<string>
}

/** The cart's code, and whether it can be used now (LIVE_COUPON). */
export interface CartCoupon extends CouponRow {
  live: number
}

/** Everything a price depends on. */
export interface World {
  skus: Map<number, SkuRow>
  products: Map<number, Loaded>
  stores: Map<number, StoreTerms>
  coupon: CartCoupon | null
}

/**
 * What [lines] and the cart's coupon need to be priced. With [lock] (placing
 * an order) it is read under the checkout's locks, in the one lock order
 * (DATABASE_DESIGN.md §5.1): the coupon to update, the stores to share, then
 * each option to update, by id. A locking read sees the latest data, so
 * stock, a store's standing and a coupon's uses are never read stale.
 */
export async function loadWorld(db: Pool | Connection, lines: LineIn[], couponId: number | null, lock: boolean): Promise<World> {
  const skuIds = [...new Set(lines.map((line) => line.skuId))].sort((a, b) => a - b)
  const owners =
    skuIds.length === 0
      ? []
      : await rows<{ product_id: number; store_id: number }>(
          db,
          'SELECT DISTINCT k.product_id, p.store_id FROM product_skus k JOIN products p ON p.id = k.product_id WHERE k.id IN (?)',
          [skuIds],
        )
  const couponStore =
    couponId === null
      ? undefined
      : (await one<{ store_id: number }>(db, `SELECT store_id FROM coupons WHERE id = ?${lock ? ' FOR UPDATE' : ''}`, [couponId]))
          ?.store_id
  const storeIds = [...new Set([...owners.map((row) => row.store_id), ...(couponStore === undefined ? [] : [couponStore])])]
  const stores = await storeTerms(db, storeIds, lock)
  const coupon =
    couponStore === undefined
      ? undefined
      : await one<CartCoupon>(
          db,
          `SELECT ${COUPON_COLUMNS}, (${LIVE_COUPON}) AS live FROM coupons c JOIN stores s ON s.id = c.store_id
            WHERE c.id = ?${lock ? ' FOR SHARE' : ''}`,
          [couponId],
        )
  const skus =
    skuIds.length === 0
      ? []
      : await rows<SkuRow>(
          db,
          `SELECT id, product_id, options, option_label, sku_code, price, stock, deleted_at FROM product_skus
            WHERE id IN (?) ORDER BY id${lock ? ' FOR UPDATE' : ''}`,
          [skuIds],
        )
  const products = await loadProducts(db, [...new Set(owners.map((row) => row.product_id))])
  return {
    skus: new Map(skus.map((sku) => [sku.id, sku])),
    products: new Map(products.map((loaded) => [loaded.row.id, loaded])),
    stores,
    coupon: coupon ?? null,
  }
}

async function storeTerms(db: Pool | Connection, ids: number[], lock: boolean): Promise<Map<number, StoreTerms>> {
  const terms = new Map<number, StoreTerms>()
  if (ids.length === 0) return terms
  const found = await rows<{
    id: number
    owner_user_id: number
    store_name: string
    logo_url: string | null
    governorate: Governorate
    status: string
    is_open: number
    fee_inside: number | null
    time_inside: DeliveryTime | null
    fee_outside: number | null
    time_outside: DeliveryTime | null
  }>(
    db,
    `SELECT id, owner_user_id, store_name, logo_url, governorate, status, is_open, fee_inside, time_inside, fee_outside, time_outside
       FROM stores WHERE id IN (?) ORDER BY id${lock ? ' FOR SHARE' : ''}`,
    [ids],
  )
  const areas = await rows<{ store_id: number; governorate: string }>(
    db,
    `SELECT store_id, governorate FROM store_delivery_governorates WHERE store_id IN (?)${lock ? ' FOR SHARE' : ''}`,
    [ids],
  )
  for (const row of found) {
    terms.set(row.id, {
      id: row.id,
      owner: row.owner_user_id,
      name: row.store_name,
      logo: row.logo_url,
      governorate: row.governorate,
      approved: row.status === 'APPROVED',
      open: row.is_open === 1,
      feeInside: row.fee_inside,
      timeInside: row.time_inside,
      feeOutside: row.fee_outside,
      timeOutside: row.time_outside,
      areas: new Set(areas.filter((area) => area.store_id === row.id).map((area) => area.governorate)),
    })
  }
  return terms
}

export interface PricedLine {
  line: LineIn
  sku: SkuRow
  loaded: Loaded
  unitPrice: number
  originalUnitPrice: number | null
  lineTotal: number
  /** What can be had now: its stock while it is for sale, else none. */
  left: number
}

export interface Part {
  store: StoreTerms
  lines: PricedLine[]
  /** Its lines that can be bought: for sale and in stock. */
  subtotal: number
  /** What the store asks to bring this part to the city, or null when it can't now. */
  reach: { fee: number; time: DeliveryTime } | null
  discount: number
  /** What its driver collects at the door; null when it isn't coming. */
  amountDue: number | null
}

export interface Priced {
  parts: Part[]
  subtotal: number
  discount: number
  shipping: number
  total: number
  /** The cart's code as it stands: what it takes off, or nothing (under its minimum, or not live any more). */
  coupon: { row: CartCoupon; store: StoreTerms; discount: number } | null
}

/** What [store] asks to bring an order to [city], or null: not approved, closed, or not going there. */
export function reachOf(store: StoreTerms, city: Governorate): Part['reach'] {
  if (!store.approved || !store.open || !store.areas.has(city)) return null
  const [fee, time] = city === store.governorate ? [store.feeInside, store.timeInside] : [store.feeOutside, store.timeOutside]
  return fee === null || time === null ? null : { fee, time }
}

/**
 * [lines] priced for delivery to [city] (DATABASE_DESIGN.md §6). A part that
 * can't come is not in the total; the cart's coupon takes its store's share
 * off, unless [withCoupon] is false (Buy now).
 */
export function priceLines(world: World, lines: LineIn[], city: Governorate, now: Date, withCoupon: boolean): Priced {
  const parts: Part[] = []
  for (const line of lines) {
    const sku = world.skus.get(line.skuId)
    const loaded = sku && world.products.get(sku.product_id)
    const store = loaded && world.stores.get(loaded.row.store_id)
    if (!sku || !loaded || !store) continue
    const shown = sku.options === null ? productPrice(loaded.row, now) : optionPrice(loaded.row, sku.price!, now)
    const forSale = loaded.row.listed === 1 && store.approved && sku.deleted_at === null
    const priced: PricedLine = {
      line,
      sku,
      loaded,
      unitPrice: shown.price,
      originalUnitPrice: shown.originalPrice,
      lineTotal: shown.price * line.quantity,
      left: forSale ? sku.stock : 0,
    }
    let part = parts.find((candidate) => candidate.store.id === store.id)
    if (!part) {
      part = { store, lines: [], subtotal: 0, reach: reachOf(store, city), discount: 0, amountDue: null }
      parts.push(part)
    }
    part.lines.push(priced)
    if (priced.left > 0) part.subtotal += priced.lineTotal
  }

  const applied = withCoupon ? world.coupon : null
  let discount = 0
  if (applied?.live === 1) {
    const part = parts.find((candidate) => candidate.store.id === applied.store_id)
    const base = part?.reach ? part.subtotal : 0
    if (applied.min_order_amount === null || base >= applied.min_order_amount) {
      discount = couponDiscount(applied.discount_type, applied.value, base)
    }
    if (part) part.discount = discount
  }

  let subtotal = 0
  let shipping = 0
  for (const part of parts) {
    if (!part.reach) continue
    part.amountDue = part.subtotal - part.discount + part.reach.fee
    subtotal += part.subtotal
    shipping += part.reach.fee
  }
  const couponStore = applied ? world.stores.get(applied.store_id) : undefined
  return {
    parts,
    subtotal,
    discount,
    shipping,
    total: subtotal - discount + shipping,
    coupon: applied && couponStore ? { row: applied, store: couponStore, discount } : null,
  }
}

/** A line's name and option, in both languages: "Nova X5 - Black · 128GB". */
function lineName({ loaded, sku }: PricedLine): Record<Lang, string> {
  const label = sku.option_label ? ` - ${sku.option_label}` : ''
  return { en: `${loaded.row.name_en ?? loaded.row.name_ar}${label}`, ar: `${loaded.row.name_ar}${label}` }
}

/** The first line that can't be had in its quantity now, as the shopper is told it; null when every one can. */
export function shortOf(priced: Priced, buyNow = false): { key: MessageKey; params: MessageParams } | null {
  for (const part of priced.parts) {
    for (const line of part.lines) {
      if (line.left >= line.line.quantity) continue
      // Buy now has no cart to take it out of (M9).
      return line.left <= 0
        ? { key: buyNow ? 'buyNow.runOut' : 'cart.runOut', params: { name: lineName(line) } }
        : { key: 'cart.onlyLeft', params: { name: lineName(line), left: line.left } }
    }
  }
  return null
}

/** A shopper with no order delivered and paid may order at most FIRST_ORDER_LIMIT (`_overFirstOrderLimit`). */
export async function overFirstOrderLimit(db: Pool | Connection, userId: number, total: number): Promise<boolean> {
  if (total <= FIRST_ORDER_LIMIT) return false
  const trusted = await one(db, "SELECT id FROM orders WHERE customer_id = ? AND status = 'DELIVERED' AND payment_status = 'PAID' LIMIT 1", [
    userId,
  ])
  return !trusted
}

// ------------------------------------------------------------ what a cart holds ---

export async function cartLines(db: Pool | Connection, userId: number, lock = false): Promise<(LineIn & { saved: boolean })[]> {
  const found = await rows<{ id: number; sku_id: number; quantity: number; saved_for_later: number }>(
    db,
    `SELECT id, sku_id, quantity, saved_for_later FROM cart_items WHERE user_id = ? ORDER BY id${lock ? ' FOR UPDATE' : ''}`,
    [userId],
  )
  return found.map((row) => ({ id: row.id, skuId: row.sku_id, quantity: row.quantity, saved: row.saved_for_later === 1 }))
}

export async function cartCoupon(db: Pool | Connection, userId: number, lock = false): Promise<number | null> {
  const row = await one<{ coupon_id: number | null }>(db, `SELECT coupon_id FROM carts WHERE user_id = ?${lock ? ' FOR UPDATE' : ''}`, [
    userId,
  ])
  return row?.coupon_id ?? null
}

export interface AddressRow {
  id: number
  full_name: string
  full_name_ar: string | null
  phone: string
  governorate: Governorate
  area: string
  area_ar: string | null
  street: string | null
  street_ar: string | null
  landmark: string
  landmark_ar: string | null
  instructions: string | null
}

/** The shopper's own address [idText]; any other is refused on its field. */
export async function addressOf(db: Pool | Connection, userId: number, idText: string | null | undefined): Promise<AddressRow> {
  if (!idText) throw fieldError('addressId', 'field.required')
  const row = await one<AddressRow>(
    db,
    `SELECT id, full_name, full_name_ar, phone, governorate, area, area_ar, street, street_ar, landmark, landmark_ar, instructions
       FROM addresses WHERE id = ? AND user_id = ?`,
    [/^\d{1,15}$/.test(idText) ? Number(idText) : 0, userId],
  )
  if (!row) throw fieldError('addressId', 'field.invalid')
  return row
}

/** Where things go before an address is chosen: the default address's city, else the account's (the app's deliveryCityProvider). */
async function homeCity(db: Pool | Connection, userId: number): Promise<Governorate> {
  const row = await one<{ governorate: Governorate | null }>(
    db,
    `SELECT COALESCE((SELECT a.governorate FROM addresses a WHERE a.user_id = u.id AND a.is_default = 1), u.governorate) AS governorate
       FROM users u WHERE u.id = ?`,
    [userId],
  )
  // ponytail: every shopper gives a city at sign-up; the fallback is for an account made by hand.
  return row?.governorate ?? 'BAGHDAD'
}

/** The option [variantText] of product [productText], or its single one; with [listedOnly], only while it is for sale. */
async function skuFor(db: Pool | Connection, productText: string, variantText: string | null | undefined, listedOnly: boolean): Promise<number> {
  const productId = /^\d{1,15}$/.test(productText) ? Number(productText) : 0
  const product = await one(
    db,
    listedOnly
      ? `SELECT p.id FROM products p JOIN stores s ON s.id = p.store_id WHERE p.id = ? AND ${LISTED}`
      : 'SELECT id FROM products WHERE id = ?',
    [productId],
  )
  if (!product) throw new AppError(404, 'NOT_FOUND_ERROR', 'product.notAvailable')
  const skus = await rows<{ id: number; options: unknown; deleted_at: Date | null }>(
    db,
    'SELECT id, options, deleted_at FROM product_skus WHERE product_id = ?',
    [productId],
  )
  if (variantText) {
    const sku = skus.find((s) => String(s.id) === variantText && s.options !== null && (!listedOnly || s.deleted_at === null))
    if (!sku) throw fieldError('variantId', 'field.invalid')
    return sku.id
  }
  const single = skus.find((s) => s.options === null && s.deleted_at === null)
  if (!single) throw fieldError('variantId', 'cart.chooseOptions')
  return single.id
}

const BuyNowItem = z.object({
  productId: z.string(),
  variantId: z.string().nullish(),
  quantity: z.number().int().min(1).max(999).default(1),
})

/** Buy now's lines, one per option (the same option twice is one line). */
export async function buyNowLines(db: Pool | Connection, items: z.infer<typeof BuyNowItem>[]): Promise<LineIn[]> {
  const merged = new Map<number, number>()
  for (const item of items) {
    const skuId = await skuFor(db, item.productId, item.variantId, false)
    merged.set(skuId, Math.min(999, (merged.get(skuId) ?? 0) + item.quantity))
  }
  return [...merged].map(([skuId, quantity]) => ({ id: null, skuId, quantity }))
}

/** What checkout sends to review and to place the order (checkout_providers.dart, CheckoutSelection.toJson). */
export const CheckoutBody = z.object({
  addressId: z.string().nullish(),
  deliveryInstructions: optionalText(300),
  // One way per store: its own driver at its own price. Sent, and needs no answer.
  shipping: z.array(z.object({ merchantId: z.string(), shippingOptionId: z.string() })).max(100).optional(),
  paymentMethodId: z.string().max(40).nullish(),
  items: z.array(BuyNowItem).max(50).nullish(),
})
export type CheckoutBody = z.infer<typeof CheckoutBody>

// -------------------------------------------------------------------- shapes ---

const StockStatus = z.enum(['IN_STOCK', 'LOW_STOCK', 'OUT_OF_STOCK'])

const CartItem = z.object({
  id: z.string(),
  productId: z.string(),
  variantId: z.string().nullable(),
  name: z.string(),
  nameAr: z.string(),
  unitPrice: z.number(),
  originalUnitPrice: z.number().nullable(),
  quantity: z.number(),
  lineTotal: z.number(),
  currencyCode: z.literal('IQD'),
  stockStatus: StockStatus,
  availableQuantity: z.number(),
  imageUrl: z.string().nullable(),
  variantLabel: z.string().nullable(),
  merchantId: z.string(),
  merchantName: z.string(),
})

const Totals = z.object({
  subtotal: z.number(),
  discount: z.number(),
  couponDiscount: z.number(),
  shipping: z.number(),
  total: z.number(),
  currencyCode: z.literal('IQD'),
})

export const Cart = z
  .object({
    id: z.string(),
    groups: z.array(
      z.object({
        merchant: z.object({ id: z.string(), storeName: z.string(), logoUrl: z.string().nullable(), governorate: z.enum(GOVERNORATES) }),
        items: z.array(CartItem),
        subtotal: z.number(),
        discount: z.number(),
        amountDue: z.number().optional(),
        currencyCode: z.literal('IQD'),
        deliversHere: z.boolean(),
        shippingFee: z.number().optional(),
        deliveryTime: z.enum(DELIVERY_TIMES).optional(),
        shippingMethodName: z.string().optional(),
        estimatedDelivery: z.string(),
      }),
    ),
    savedForLater: z.array(CartItem),
    totals: Totals,
    coupon: z
      .object({
        code: z.string(),
        discountAmount: z.number(),
        description: z.string(),
        applies: z.boolean(),
        minOrderAmount: z.number().nullable(),
      })
      .optional(),
  })
  .meta({ id: 'Cart' })

const CheckoutReview = z
  .object({
    canPlaceOrder: z.boolean(),
    warnings: z.array(z.string()),
    groups: z.array(
      z.object({
        merchantId: z.string(),
        merchantName: z.string(),
        itemCount: z.number(),
        items: z.array(z.object({ name: z.string(), quantity: z.number(), variantLabel: z.string().nullable() })),
        subtotal: z.number(),
        discount: z.number(),
        amountDue: z.number().nullable(),
        currencyCode: z.literal('IQD'),
        shippingFee: z.number().nullable(),
        estimatedDelivery: z.string(),
        deliversHere: z.boolean(),
        selectedShippingOptionId: z.string(),
        shippingOptions: z.array(
          z.object({ id: z.string(), name: z.string(), fee: z.number(), currencyCode: z.literal('IQD'), estimatedDelivery: z.string() }),
        ),
      }),
    ),
    totals: Totals,
    paymentMethods: z.array(z.object({ id: z.string(), type: z.literal('COD'), label: z.string(), description: z.string() })),
  })
  .meta({ id: 'CheckoutReview' })

/** One request's words: its language, its addresses for photos, the cities' names. */
async function wordsFor(req: Request, ctx: Context) {
  const lang: Lang = req.lang
  const cities = await governorateNames(ctx.pool)
  const url = (key: string | null) => (key === null ? null : urlOf(req, ctx.config.mediaBaseUrl, key))

  /** When a part comes, or why it doesn't. */
  function when(part: Part, city: Governorate): string {
    if (!part.store.approved || !part.store.open) return t(lang, 'cart.closed')
    if (!part.reach) return t(lang, 'cart.noDelivery', { city: cities.get(city)?.[lang] ?? city })
    return t(lang, `delivery.${part.reach.time}` as const)
  }

  function item(part: Part, line: PricedLine): z.infer<typeof CartItem> {
    const { row, images } = line.loaded
    return {
      id: String(line.line.id ?? line.sku.id),
      productId: String(row.id),
      variantId: line.sku.options === null ? null : String(line.sku.id),
      name: lang === 'ar' ? row.name_ar : (row.name_en ?? row.name_ar),
      nameAr: row.name_ar,
      unitPrice: line.unitPrice,
      originalUnitPrice: line.originalUnitPrice,
      quantity: line.line.quantity,
      lineTotal: line.lineTotal,
      currencyCode: 'IQD',
      stockStatus: stockStatus(line.left),
      availableQuantity: line.left,
      imageUrl: url(images[0]?.url ?? null),
      variantLabel: line.sku.option_label,
      merchantId: String(part.store.id),
      merchantName: part.store.name,
    }
  }

  function totals(priced: Priced): z.infer<typeof Totals> {
    return {
      subtotal: priced.subtotal,
      discount: 0,
      couponDiscount: priced.discount,
      shipping: priced.shipping,
      total: priced.total,
      currencyCode: 'IQD',
    }
  }

  function couponText(coupon: CouponRow, store: string): string {
    return coupon.discount_type === 'PERCENTAGE'
      ? t(lang, 'coupon.percentOff', { value: coupon.value, store })
      : t(lang, 'coupon.amountOff', { value: grouped(coupon.value), store })
  }

  return { lang, when, item, totals, couponText }
}

export function cartRoutes(api: Api, ctx: Context): void {
  const { pool } = ctx
  const SHOPPER = ['CUSTOMER'] as const
  const TAG = 'Cart'

  async function cartOf(req: Request): Promise<z.infer<typeof Cart>> {
    const userId = me(req).id
    const lines = await cartLines(pool, userId)
    const world = await loadWorld(pool, lines, await cartCoupon(pool, userId), false)
    const city = await homeCity(pool, userId)
    const now = new Date()
    const active = priceLines(
      world,
      lines.filter((line) => !line.saved),
      city,
      now,
      true,
    )
    const saved = priceLines(
      world,
      lines.filter((line) => line.saved),
      city,
      now,
      false,
    )
    const words = await wordsFor(req, ctx)
    return {
      id: String(userId),
      groups: active.parts.map((part) => ({
        merchant: {
          id: String(part.store.id),
          storeName: part.store.name,
          logoUrl: part.store.logo === null ? null : urlOf(req, ctx.config.mediaBaseUrl, part.store.logo),
          governorate: part.store.governorate,
        },
        items: part.lines.map((line) => words.item(part, line)),
        subtotal: part.subtotal,
        discount: part.discount,
        currencyCode: 'IQD' as const,
        deliversHere: part.reach !== null,
        ...(part.reach && {
          amountDue: part.amountDue!,
          shippingFee: part.reach.fee,
          deliveryTime: part.reach.time,
          shippingMethodName: t(words.lang, 'cart.storeDelivery'),
        }),
        estimatedDelivery: words.when(part, city),
      })),
      savedForLater: saved.parts.flatMap((part) => part.lines.map((line) => words.item(part, line))),
      totals: words.totals(active),
      ...(active.coupon && {
        coupon: {
          code: active.coupon.row.code,
          discountAmount: active.coupon.discount,
          description: words.couponText(active.coupon.row, active.coupon.store.name),
          // On, but taking nothing off: under its minimum, or no longer live (BUGS 166).
          applies: active.coupon.discount > 0,
          minOrderAmount: active.coupon.row.min_order_amount,
        },
      }),
    }
  }

  route(api, {
    method: 'get',
    path: '/cart',
    tag: TAG,
    summary: "The shopper's cart, priced: a group per store, delivery to the default address's city",
    who: SHOPPER,
    response: Cart,
    handle: ({ req }) => cartOf(req),
  })

  route(api, {
    method: 'post',
    path: '/cart/items',
    tag: TAG,
    summary: 'Add a product (or one of its options); the same option again adds to its line',
    who: SHOPPER,
    body: BuyNowItem,
    response: Cart,
    async handle({ req, body }) {
      const skuId = await skuFor(pool, body.productId, body.variantId, true)
      // None left: refused here (M4). More than is left still goes in; the review says how many.
      const left = await one<{ stock: number }>(pool, 'SELECT stock FROM product_skus WHERE id = ?', [skuId])
      if (!left || left.stock <= 0) throw new AppError(422, 'INVENTORY_ERROR', 'cart.soldOut')
      await exec(
        pool,
        `INSERT INTO cart_items (user_id, sku_id, quantity, saved_for_later) VALUES (?, ?, ?, 0)
         ON DUPLICATE KEY UPDATE quantity = LEAST(quantity + ?, 999)`,
        [me(req).id, skuId, body.quantity, body.quantity],
      )
      return cartOf(req)
    },
  })

  route(api, {
    method: 'patch',
    path: '/cart/items/:id',
    tag: TAG,
    summary: "Change a line's quantity",
    who: SHOPPER,
    params: IdParams,
    body: z.object({ quantity: z.number().int().min(1).max(999) }),
    response: Cart,
    async handle({ req, params, body }) {
      const changed = await exec(pool, 'UPDATE cart_items SET quantity = ? WHERE id = ? AND user_id = ?', [
        body.quantity,
        idOf(params.id),
        me(req).id,
      ])
      if (changed.affectedRows === 0) throw notFound()
      return cartOf(req)
    },
  })

  route(api, {
    method: 'delete',
    path: '/cart/items/:id',
    tag: TAG,
    summary: 'Take a line out',
    who: SHOPPER,
    params: IdParams,
    response: Cart,
    async handle({ req, params }) {
      await exec(pool, 'DELETE FROM cart_items WHERE id = ? AND user_id = ?', [idOf(params.id), me(req).id])
      return cartOf(req)
    },
  })

  /** A line to the other list; onto a line already there, the quantities add. */
  async function move(req: Request, idText: string, toSaved: boolean): Promise<void> {
    const userId = me(req).id
    await withTransaction(pool, async (conn) => {
      const line = await one<{ id: number; sku_id: number; quantity: number; saved_for_later: number }>(
        conn,
        'SELECT id, sku_id, quantity, saved_for_later FROM cart_items WHERE id = ? AND user_id = ? FOR UPDATE',
        [idOf(idText), userId],
      )
      if (!line) throw notFound()
      if (line.saved_for_later === Number(toSaved)) return
      const there = await one<{ id: number; quantity: number }>(
        conn,
        'SELECT id, quantity FROM cart_items WHERE user_id = ? AND sku_id = ? AND saved_for_later = ? FOR UPDATE',
        [userId, line.sku_id, toSaved],
      )
      if (there) {
        await exec(conn, 'UPDATE cart_items SET quantity = LEAST(?, 999) WHERE id = ?', [there.quantity + line.quantity, there.id])
        await exec(conn, 'DELETE FROM cart_items WHERE id = ?', [line.id])
      } else {
        await exec(conn, 'UPDATE cart_items SET saved_for_later = ? WHERE id = ?', [toSaved, line.id])
      }
    })
  }

  route(api, {
    method: 'post',
    path: '/cart/items/:id/save-for-later',
    tag: TAG,
    summary: 'Keep a line for later: out of the total',
    who: SHOPPER,
    params: IdParams,
    response: Cart,
    async handle({ req, params }) {
      await move(req, params.id, true)
      return cartOf(req)
    },
  })

  route(api, {
    method: 'post',
    path: '/cart/items/:id/move-to-cart',
    tag: TAG,
    summary: 'Bring a saved line back into the cart',
    who: SHOPPER,
    params: IdParams,
    response: Cart,
    async handle({ req, params }) {
      await move(req, params.id, false)
      return cartOf(req)
    },
  })

  route(api, {
    method: 'post',
    path: '/cart/coupon',
    tag: TAG,
    summary: "Apply a store's code: it must be live, and the cart must hold enough of that store's things",
    who: SHOPPER,
    body: z.object({ code: z.string().trim().max(40) }),
    response: Cart,
    async handle({ req, body }) {
      const userId = me(req).id
      const code = body.code.toUpperCase()
      const coupon = await one<CouponRow & { store_name: string }>(
        pool,
        `SELECT ${COUPON_COLUMNS}, s.store_name FROM coupons c JOIN stores s ON s.id = c.store_id WHERE c.code = ? AND ${LIVE_COUPON}`,
        [code],
      )
      if (!coupon) {
        // One not started yet says when it does: "not valid or has expired" was wrong (the tester).
        const later = await one<{ starts_at: Date }>(pool, 'SELECT starts_at FROM coupons WHERE code = ? AND is_active = 1 AND starts_at > NOW(3)', [
          code,
        ])
        if (later) throw fieldError('code', 'coupon.notStarted', { day: dayOf(later.starts_at) })
        // One its store paused says so (the user, after M9).
        if (await one(pool, 'SELECT id FROM coupons WHERE code = ? AND is_active = 0', [code])) throw fieldError('code', 'coupon.paused')
        throw fieldError('code', 'coupon.invalid')
      }
      // A store's code takes money off that store's things only: the cart has to hold some, and enough.
      const lines = (await cartLines(pool, userId)).filter((line) => !line.saved)
      const world = await loadWorld(pool, lines, null, false)
      const priced = priceLines(world, lines, await homeCity(pool, userId), new Date(), false)
      const atStore = priced.parts.find((part) => part.store.id === coupon.store_id)?.subtotal ?? 0
      if (atStore <= 0) throw fieldError('code', 'coupon.forStore', { store: coupon.store_name })
      if (coupon.min_order_amount !== null && atStore < coupon.min_order_amount) {
        throw fieldError('code', 'coupon.minimum', { amount: grouped(coupon.min_order_amount), store: coupon.store_name })
      }
      await exec(pool, 'INSERT INTO carts (user_id, coupon_id) VALUES (?, ?) ON DUPLICATE KEY UPDATE coupon_id = ?', [
        userId,
        coupon.id,
        coupon.id,
      ])
      return cartOf(req)
    },
  })

  route(api, {
    method: 'delete',
    path: '/cart/coupon',
    tag: TAG,
    summary: 'Take the code off',
    who: SHOPPER,
    response: Cart,
    async handle({ req }) {
      await exec(pool, 'UPDATE carts SET coupon_id = NULL WHERE user_id = ?', [me(req).id])
      return cartOf(req)
    },
  })

  route(api, {
    method: 'post',
    path: '/checkout/review',
    tag: 'Checkout',
    summary: 'Price the cart (or Buy now) for an address: a group per store, warnings, whether it can be placed',
    who: SHOPPER,
    body: CheckoutBody,
    response: CheckoutReview,
    async handle({ req, body }) {
      const userId = me(req).id
      const buyNow = (body.items?.length ?? 0) > 0
      const lines = buyNow ? await buyNowLines(pool, body.items!) : (await cartLines(pool, userId)).filter((line) => !line.saved)
      const world = await loadWorld(pool, lines, buyNow ? null : await cartCoupon(pool, userId), false)
      const city = body.addressId ? (await addressOf(pool, userId, body.addressId)).governorate : await homeCity(pool, userId)
      const priced = priceLines(world, lines, city, new Date(), !buyNow)
      const words = await wordsFor(req, ctx)
      const problems = await problemsOf(pool, userId, priced, buyNow)
      return {
        canPlaceOrder: lines.length > 0 && problems.length === 0 && priced.parts.every((part) => part.reach !== null),
        // A store that can't deliver is said on its own row, not here (BUGS 17).
        warnings: problems.map((problem) => t(words.lang, problem.key, problem.params)),
        groups: priced.parts.map((part) => {
          const estimatedDelivery = words.when(part, city)
          return {
            merchantId: String(part.store.id),
            merchantName: part.store.name,
            // Units, not lines (BUGS 66).
            itemCount: part.lines.reduce((sum, line) => sum + line.line.quantity, 0),
            items: part.lines.map((line) => ({
              name: words.item(part, line).name,
              quantity: line.line.quantity,
              variantLabel: line.sku.option_label,
            })),
            subtotal: part.subtotal,
            discount: part.discount,
            amountDue: part.amountDue,
            currencyCode: 'IQD' as const,
            shippingFee: part.reach?.fee ?? null,
            estimatedDelivery,
            deliversHere: part.reach !== null,
            selectedShippingOptionId: 'ship-store',
            shippingOptions: part.reach
              ? [
                  {
                    id: 'ship-store',
                    name: t(words.lang, 'cart.storeDelivery'),
                    fee: part.reach.fee,
                    currencyCode: 'IQD' as const,
                    estimatedDelivery,
                  },
                ]
              : [],
          }
        }),
        totals: words.totals(priced),
        // Cash only in v1, and only cash is offered (BUGS 80).
        paymentMethods: [
          { id: 'pm-cod', type: 'COD' as const, label: t(words.lang, 'payment.cod'), description: t(words.lang, 'payment.codDescription') },
        ],
      }
    },
  })
}

/**
 * What stops [priced] being ordered, in the order a shopper meets them:
 * something run out, the cart's code no longer live, the first-order limit.
 * A store that can't deliver is its own row. Shared with placing an order.
 */
export async function problemsOf(
  db: Pool | Connection,
  userId: number,
  priced: Priced,
  /** Buy now: said without the cart, which it doesn't use (M9). */
  buyNow = false,
): Promise<{ key: MessageKey; params?: MessageParams; code: 'INVENTORY_ERROR' | 'BUSINESS_RULE_ERROR' }[]> {
  const problems: { key: MessageKey; params?: MessageParams; code: 'INVENTORY_ERROR' | 'BUSINESS_RULE_ERROR' }[] = []
  const short = shortOf(priced, buyNow)
  if (short) problems.push({ ...short, code: 'INVENTORY_ERROR' })
  if (priced.coupon && priced.coupon.row.live !== 1) {
    problems.push({ key: 'coupon.gone', params: { code: priced.coupon.row.code }, code: 'BUSINESS_RULE_ERROR' })
  }
  if (await overFirstOrderLimit(db, userId, priced.total)) {
    problems.push({
      key: buyNow ? 'buyNow.firstOrderLimit' : 'cart.firstOrderLimit',
      params: { limit: grouped(FIRST_ORDER_LIMIT) },
      code: 'BUSINESS_RULE_ERROR',
    })
  }
  return problems
}

/** "Sep 28" / "28 سبتمبر", on Iraq's calendar, Western digits (BUGS 28). */
function dayOf(at: Date): Record<Lang, string> {
  const format = (locale: string) => new Intl.DateTimeFormat(locale, { month: 'short', day: 'numeric', timeZone: 'Asia/Baghdad' }).format(at)
  return { en: format('en-US'), ar: format('ar-u-nu-latn') }
}

function fieldError(field: string, key: MessageKey, params?: MessageParams): AppError {
  return new AppError(422, 'VALIDATION_ERROR', key, params, { [field]: { key, params } })
}

function idOf(text: string): number {
  if (!/^\d{1,15}$/.test(text)) throw notFound()
  return Number(text)
}

function notFound(): AppError {
  return new AppError(404, 'NOT_FOUND_ERROR', 'error.notFound')
}
