import type { Request } from 'express'
import { z } from 'zod'
import type { Context } from '../app.js'
import type { Connection, Pool } from '../db/pool.js'
import { duplicateKey, exec, one, rows } from '../db/sql.js'
import { withTransaction } from '../db/tx.js'
import { me } from '../http/auth.js'
import { AppError } from '../http/errors.js'
import { governorate, IdParams, optionalText, requiredText } from '../http/inputs.js'
import { route, type Api } from '../http/route.js'
import { fold } from '../lib/fold.js'
import { GOVERNORATES, type Governorate } from '../lib/governorates.js'
import type { Lang } from '../lib/i18n.js'
import { keyOf, urlOf } from '../lib/storage.js'
import { NAME_MAX, RETURN_WINDOW_DAYS } from '../rules.js'
import { owedNow, storeBills } from './bills.js'

// A store: its owner's settings, the open switch, the page shoppers see, and
// the record Saba's admins read (BACKEND_PLAN.md §6.2, §6.5, §6.7).

export const DELIVERY_TIMES = ['SAME_DAY', '1_2_DAYS', '2_3_DAYS', '3_5_DAYS', '5_7_DAYS'] as const

export const StoreDelivery = z.object({
  governorates: z.array(z.enum(GOVERNORATES)),
  feeInside: z.number(),
  timeInside: z.enum(DELIVERY_TIMES),
  feeOutside: z.number().optional(),
  timeOutside: z.enum(DELIVERY_TIMES).optional(),
})
type StoreDelivery = z.infer<typeof StoreDelivery>

export const StoreStatus = z.enum(['PENDING', 'APPROVED', 'REJECTED', 'SUSPENDED', 'CLOSED'])

/** API_CONTRACT.md §2 AdminStore, plus isOpen and descriptionAr (BACKEND_PLAN.md §6.7). */
export const AdminStore = z
  .object({
    id: z.string(),
    storeName: z.string(),
    status: StoreStatus,
    fullName: z.string(),
    phone: z.string(),
    /** False: its owner signed up while SMS codes were off, the number never proven (PHONE_VERIFICATION). */
    phoneVerified: z.boolean(),
    email: z.string().optional(),
    businessAddress: z.string().optional(),
    description: z.string().optional(),
    descriptionAr: z.string().optional(),
    country: z.string(),
    governorate: z.enum(GOVERNORATES),
    logoUrl: z.string().optional(),
    bannerUrl: z.string().optional(),
    rating: z.number().optional(),
    reviewCount: z.number(),
    delivery: StoreDelivery.optional(),
    submittedAt: z.string(),
    answeredAt: z.string().optional(),
    rejectionReason: z.string().optional(),
    suspensionReason: z.string().optional(),
    productCount: z.number(),
    isOpen: z.boolean(),
    // Its owner asked to delete the account; CLOSED once it was done.
    deletionRequestedAt: z.string().optional(),
    closedAt: z.string().optional(),
  })
  .meta({ id: 'AdminStore' })
export type AdminStore = z.infer<typeof AdminStore>

export interface StoreRow {
  id: number
  owner_user_id: number
  store_name: string
  status: z.infer<typeof StoreStatus>
  rejection_reason: string | null
  suspension_reason: string | null
  submitted_at: Date
  answered_at: Date | null
  governorate: Governorate
  country: string
  business_type: string | null
  business_address: string | null
  business_address_ar: string | null
  description: string | null
  description_ar: string | null
  logo_url: string | null
  banner_url: string | null
  is_open: number
  fee_inside: number | null
  time_inside: StoreDelivery['timeInside'] | null
  fee_outside: number | null
  time_outside: StoreDelivery['timeInside'] | null
  rating_sum: number
  rating_count: number
  deletion_requested_at: Date | null
  closed_at: Date | null
  owner_name: string
  owner_phone: string | null
  owner_checked: number
  owner_email: string | null
  /** Its products, drafts not counted (the admin's count). */
  product_count: number
  /** Its products a shopper can see (the public page's count). */
  listed_count: number
}

/** Every column the store shapes need. Drafts are the store's own business: not counted. */
export const STORE_SELECT = `
  SELECT s.id, s.owner_user_id, s.store_name, s.status, s.rejection_reason, s.suspension_reason,
         s.submitted_at, s.answered_at, s.governorate, s.country, s.business_type, s.business_address,
         s.business_address_ar, s.description, s.description_ar, s.logo_url, s.banner_url, s.is_open,
         s.fee_inside, s.time_inside, s.fee_outside, s.time_outside, s.rating_sum, s.rating_count,
         s.deletion_requested_at, s.closed_at,
         u.full_name AS owner_name, u.phone AS owner_phone, u.email AS owner_email, u.phone_verified_at IS NOT NULL AS owner_checked,
         (SELECT COUNT(*) FROM products p
           WHERE p.store_id = s.id AND p.status <> 'DRAFT' AND p.deleted_at IS NULL) AS product_count,
         (SELECT COUNT(*) FROM products p
           WHERE p.store_id = s.id AND p.status = 'APPROVED' AND p.is_active = 1 AND p.taken_down = 0
             AND p.deleted_at IS NULL) AS listed_count
    FROM stores s JOIN users u ON u.id = s.owner_user_id`

/** Where each of [storeIds] delivers, in the app's order of governorates. */
export async function deliveryAreas(db: Pool | Connection, storeIds: number[]): Promise<Map<number, Governorate[]>> {
  const areas = new Map<number, Governorate[]>(storeIds.map((id) => [id, []]))
  if (storeIds.length === 0) return areas
  const found = await rows<{ store_id: number; governorate: Governorate }>(
    db,
    `SELECT d.store_id, d.governorate FROM store_delivery_governorates d
       JOIN governorates g ON g.code = d.governorate
      WHERE d.store_id IN (?) ORDER BY g.sort_order`,
    [storeIds],
  )
  for (const { store_id, governorate } of found) areas.get(store_id)!.push(governorate)
  return areas
}

/** A store's delivery terms, or undefined before its owner has set any (BUGS 88). */
function deliveryOf(row: StoreRow, areas: Governorate[]): StoreDelivery | undefined {
  if (row.fee_inside === null || row.time_inside === null) return undefined
  return {
    governorates: areas,
    feeInside: row.fee_inside,
    timeInside: row.time_inside,
    ...(row.fee_outside !== null && row.time_outside !== null && {
      feeOutside: row.fee_outside,
      timeOutside: row.time_outside,
    }),
  }
}

export function ratingOf(row: Pick<StoreRow, 'rating_sum' | 'rating_count'>): number | undefined {
  return row.rating_count > 0 ? Math.round((row.rating_sum / row.rating_count) * 10) / 10 : undefined
}

/** In the asked language: the Arabic twin when there is one (BACKEND_PLAN.md §5.5). */
function inLang(lang: Lang, text: string | null, arabic: string | null): string | null {
  return lang === 'ar' && arabic ? arabic : text
}

export function adminStoreOf(req: Request, ctx: Context, row: StoreRow, areas: Governorate[]): AdminStore {
  const url = (key: string | null) => (key === null ? undefined : urlOf(req, ctx.config.mediaBaseUrl, key))
  const rating = ratingOf(row)
  const delivery = deliveryOf(row, areas)
  return {
    id: String(row.id),
    storeName: row.store_name,
    status: row.status,
    fullName: row.owner_name,
    phone: row.owner_phone ?? '',
    phoneVerified: Number(row.owner_checked) === 1,
    ...(row.owner_email !== null && { email: row.owner_email }),
    ...(row.business_address !== null && { businessAddress: row.business_address }),
    ...(row.description !== null && { description: row.description }),
    ...(row.description_ar !== null && { descriptionAr: row.description_ar }),
    country: row.country,
    governorate: row.governorate,
    ...(row.logo_url !== null && { logoUrl: url(row.logo_url) }),
    ...(row.banner_url !== null && { bannerUrl: url(row.banner_url) }),
    ...(rating !== undefined && { rating }),
    reviewCount: row.rating_count,
    ...(delivery && { delivery }),
    submittedAt: row.submitted_at.toISOString(),
    ...(row.answered_at && { answeredAt: row.answered_at.toISOString() }),
    ...(row.rejection_reason !== null && { rejectionReason: row.rejection_reason }),
    ...(row.suspension_reason !== null && { suspensionReason: row.suspension_reason }),
    productCount: Number(row.product_count),
    isOpen: row.is_open === 1,
    ...(row.deletion_requested_at && { deletionRequestedAt: row.deletion_requested_at.toISOString() }),
    ...(row.closed_at && { closedAt: row.closed_at.toISOString() }),
  }
}

// --------------------------------------------------------------------- routes ---

const Settings = z
  .object({
    id: z.string(),
    storeName: z.string(),
    status: StoreStatus,
    description: z.string().nullable(),
    businessType: z.string().nullable(),
    businessAddress: z.string().nullable(),
    country: z.string(),
    governorate: z.enum(GOVERNORATES),
    logoUrl: z.string().nullable(),
    isOpen: z.boolean(),
    delivery: StoreDelivery.optional(),
  })
  .meta({ id: 'StoreSettings' })

const PublicStore = z
  .object({
    id: z.string(),
    storeName: z.string(),
    description: z.string().nullable(),
    logoUrl: z.string().nullable(),
    bannerUrl: z.string().nullable(),
    rating: z.number(),
    reviewCount: z.number(),
    productCount: z.number(),
    governorate: z.enum(GOVERNORATES),
    country: z.string(),
    businessAddress: z.string().nullable(),
    /** The owner's number, for shoppers to call the store (the user's call, 2026-10-05). */
    phone: z.string().nullable(),
    delivery: StoreDelivery.optional(),
    isOpen: z.boolean(),
  })
  .meta({ id: 'PublicStore' })

/** A fee as the app sends it: whole IQD, in steps of 250 (the smallest note). */
const fee = z
  .number()
  .int()
  .min(0)
  .max(1_000_000)
  .refine((value) => value % 250 === 0, { error: 'field.steps250' })

export function storeRoutes(api: Api, ctx: Context): void {
  const { pool } = ctx
  const mediaUrl = (req: Request, key: string | null) =>
    key === null ? null : urlOf(req, ctx.config.mediaBaseUrl, key)

  /** The session's own store; with [lock], its row is locked first (one save at a time). */
  async function ownStore(db: Pool | Connection, req: Request, lock = false): Promise<StoreRow> {
    if (lock) await one(db, 'SELECT id FROM stores WHERE owner_user_id = ? FOR UPDATE', [me(req).id])
    const row = await one<StoreRow>(db, `${STORE_SELECT} WHERE s.owner_user_id = ?`, [me(req).id])
    if (!row) throw new AppError(404, 'NOT_FOUND_ERROR', 'error.notFound')
    return row
  }

  async function settingsOf(db: Pool | Connection, req: Request): Promise<z.infer<typeof Settings>> {
    const row = await ownStore(db, req)
    const areas = (await deliveryAreas(db, [row.id])).get(row.id)!
    const delivery = deliveryOf(row, areas)
    return {
      id: String(row.id),
      storeName: row.store_name,
      status: row.status,
      description: inLang(req.lang, row.description, row.description_ar),
      businessType: row.business_type,
      businessAddress: inLang(req.lang, row.business_address, row.business_address_ar),
      country: row.country,
      governorate: row.governorate,
      logoUrl: mediaUrl(req, row.logo_url),
      isOpen: row.is_open === 1,
      ...(delivery && { delivery }),
    }
  }

  route(api, {
    method: 'get',
    path: '/merchants/me/store',
    tag: 'Store',
    summary: "The store's settings and delivery terms",
    who: ['MERCHANT'],
    response: Settings,
    handle: ({ req }) => settingsOf(pool, req),
  })

  route(api, {
    method: 'put',
    path: '/merchants/me/store',
    tag: 'Store',
    summary: "Save the store's settings: name, words, city, logo, delivery",
    who: ['MERCHANT'],
    body: z.object({
      storeName: requiredText(NAME_MAX.store),
      description: optionalText(1000),
      businessAddress: optionalText(200),
      // Always sent by the app; null or missing takes the logo away.
      logoUrl: z.string().nullish(),
      governorate,
      delivery: z.object({
        governorates: z.array(governorate).max(GOVERNORATES.length),
        feeInside: fee,
        timeInside: z.enum(DELIVERY_TIMES, { error: 'field.invalid' }),
        feeOutside: fee.nullish(),
        timeOutside: z.enum(DELIVERY_TIMES, { error: 'field.invalid' }).nullish(),
      }),
    }),
    // The form's fee and time boxes are feeInside, feeOutside…, not delivery.feeInside (M2).
    flatten: ['delivery'],
    response: Settings,
    async handle({ req, body }) {
      const home = body.governorate
      // It always delivers where it is (the demo's rule).
      const areas = [...new Set<Governorate>([home, ...body.delivery.governorates])]
      const goesOut = areas.some((area) => area !== home)
      if (goesOut && (body.delivery.feeOutside == null || body.delivery.timeOutside == null)) {
        throw new AppError(422, 'VALIDATION_ERROR', 'store.outsideTerms', undefined, {
          feeOutside: { key: 'store.outsideTerms' },
        })
      }

      await withTransaction(pool, async (conn) => {
        const row = await ownStore(conn, req, true)

        let logo: string | null = null
        if (body.logoUrl) {
          logo = keyOf(body.logoUrl, ctx.config.mediaBaseUrl)
          // Its own upload, or the logo it already has; nothing else (spec §51).
          const allowed =
            logo !== null &&
            (logo === row.logo_url ||
              (await one(conn, 'SELECT id FROM media_files WHERE storage_key = ? AND owner_user_id = ? AND deleted_at IS NULL', [
                logo,
                row.owner_user_id,
              ])))
          if (!allowed) {
            throw new AppError(422, 'VALIDATION_ERROR', 'error.validation', undefined, {
              logoUrl: { key: 'media.notUploaded' },
            })
          }
        }

        // An edited field replaces both languages; one sent back as it was
        // shown keeps both (BACKEND_PLAN.md §9 item 5).
        const twin = (sent: string | null, text: string | null, arabic: string | null): [string | null, string | null] =>
          sent === inLang(req.lang, text, arabic) ? [text, arabic] : [sent, null]
        const [description, descriptionAr] = twin(body.description, row.description, row.description_ar)
        const [address, addressAr] = twin(body.businessAddress, row.business_address, row.business_address_ar)

        try {
          await exec(
            conn,
            `UPDATE stores SET store_name = ?, name_key = ?, description = ?, description_ar = ?,
                               business_address = ?, business_address_ar = ?, governorate = ?, logo_url = ?,
                               fee_inside = ?, time_inside = ?, fee_outside = ?, time_outside = ?, search_text = ?
              WHERE id = ?`,
            [
              body.storeName,
              nameKey(body.storeName),
              description,
              descriptionAr,
              address,
              addressAr,
              home,
              logo,
              body.delivery.feeInside,
              body.delivery.timeInside,
              goesOut ? body.delivery.feeOutside : null,
              goesOut ? body.delivery.timeOutside : null,
              storeSearchText(body.storeName, address, addressAr),
              row.id,
            ],
          )
        } catch (error) {
          if (duplicateKey(error) === 'uq_stores_governorate_name_key') {
            throw new AppError(422, 'VALIDATION_ERROR', 'auth.storeNameTaken', undefined, {
              storeName: { key: 'auth.storeNameTaken' },
            })
          }
          throw error
        }
        await exec(conn, 'DELETE FROM store_delivery_governorates WHERE store_id = ?', [row.id])
        await exec(conn, 'INSERT INTO store_delivery_governorates (store_id, governorate) VALUES ?', [
          areas.map((area) => [row.id, area]),
        ])
      })
      return settingsOf(pool, req)
    },
  })

  route(api, {
    method: 'patch',
    path: '/merchants/me/store/open',
    tag: 'Store',
    summary: 'Open or close the store; says what closing leaves behind',
    who: ['MERCHANT'],
    body: z.object({ isOpen: z.boolean() }),
    response: z.object({
      isOpen: z.boolean(),
      currencyCode: z.literal('IQD'),
      openOrders: z.number(),
      owed: z.number(),
      returnsOpenUntil: z.string().nullable(),
    }),
    async handle({ req, body }) {
      const id = await withTransaction(pool, async (conn) => {
        // Locked: an owner's deletion request closes the store in between otherwise.
        const row = await ownStore(conn, req, true)
        if (body.isOpen && row.deletion_requested_at) throw new AppError(409, 'CONFLICT_ERROR', 'store.beingDeleted')
        await exec(conn, 'UPDATE stores SET is_open = ? WHERE id = ?', [body.isOpen, row.id])
        return row.id
      })
      const { openOrders, owed, returnsOpenUntil } = await leftBehind(pool, id)
      return { isOpen: body.isOpen, currencyCode: 'IQD' as const, openOrders, owed, returnsOpenUntil }
    },
  })

  route(api, {
    method: 'get',
    path: '/merchants/:id/store',
    tag: 'Stores',
    summary: "A store's public page; only an approved store has one",
    who: 'public',
    params: IdParams,
    response: PublicStore,
    async handle({ req, params }) {
      const id = /^\d{1,15}$/.test(params.id) ? Number(params.id) : 0
      const row = await one<StoreRow>(pool, `${STORE_SELECT} WHERE s.id = ? AND s.status = 'APPROVED'`, [id])
      if (!row) throw new AppError(404, 'NOT_FOUND_ERROR', 'error.notFound')
      const delivery = deliveryOf(row, (await deliveryAreas(pool, [row.id])).get(row.id)!)
      return {
        id: String(row.id),
        storeName: row.store_name,
        description: inLang(req.lang, row.description, row.description_ar),
        logoUrl: mediaUrl(req, row.logo_url),
        bannerUrl: mediaUrl(req, row.banner_url),
        rating: ratingOf(row) ?? 0,
        reviewCount: row.rating_count,
        productCount: Number(row.listed_count),
        governorate: row.governorate,
        country: row.country,
        businessAddress: inLang(req.lang, row.business_address, row.business_address_ar),
        phone: row.owner_phone,
        ...(delivery && { delivery }),
        isOpen: row.is_open === 1,
      }
    },
  })

  route(api, {
    method: 'get',
    path: '/stores/cities',
    tag: 'Stores',
    summary: "Governorates with an open, approved store, in the app's order (Home's city chips)",
    who: 'public',
    response: z.array(z.enum(GOVERNORATES)),
    async handle() {
      const found = await rows<{ code: Governorate }>(
        pool,
        `SELECT g.code FROM governorates g
          WHERE EXISTS (SELECT 1 FROM stores s WHERE s.governorate = g.code AND s.status = 'APPROVED' AND s.is_open = 1)
          ORDER BY g.sort_order`,
      )
      return found.map((row) => row.code)
    },
  })
}

/**
 * What a closing store leaves behind (BR): orders to finish, returns still
 * open, the day the last return window ends (a return may be asked while
 * `now - delivered <= RETURN_WINDOW_DAYS`), and what it owes Saba: this month
 * so far and every month still due. All four at nothing: a deletion can go.
 */
export async function leftBehind(db: Pool | Connection, storeId: number) {
  const open = await one<{ orders: number; returns: number; until: Date | null }>(
    db,
    `SELECT (SELECT COUNT(*) FROM order_store_parts
              WHERE store_id = ? AND status NOT IN ('DELIVERED', 'CANCELLED', 'REFUSED')) AS orders,
            (SELECT COUNT(*) FROM returns WHERE store_id = ? AND status NOT IN ('REJECTED', 'REFUNDED')) AS returns,
            (SELECT MAX(delivered_at) + INTERVAL ? DAY FROM order_store_parts
              WHERE store_id = ? AND status = 'DELIVERED' AND delivered_at >= NOW(3) - INTERVAL ? DAY) AS until`,
    [storeId, storeId, RETURN_WINDOW_DAYS, storeId, RETURN_WINDOW_DAYS],
  )
  return {
    openOrders: Number(open!.orders),
    openReturns: Number(open!.returns),
    returnsOpenUntil: open!.until ? open!.until.toISOString() : null,
    owed: owedNow(await storeBills(db, storeId)),
  }
}

/** stores.name_key: lower-cased, trimmed, inner spaces made one (unique per city, BUGS 120). */
export function nameKey(storeName: string): string {
  return storeName.trim().toLowerCase().replace(/\s+/g, ' ')
}

/** stores.search_text: the name and address, both languages, folded (admin search). */
export function storeSearchText(name: string, address: string | null, addressAr: string | null = null): string {
  return fold(`${name} ${address ?? ''} ${addressAr ?? ''}`).slice(0, 500)
}
