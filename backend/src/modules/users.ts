import type { Request } from 'express'
import { z } from 'zod'
import type { Context } from '../app.js'
import type { Connection, Pool } from '../db/pool.js'
import { one } from '../db/sql.js'
import { fold } from '../lib/fold.js'
import { GOVERNORATES } from '../lib/governorates.js'
import { urlOf } from '../lib/storage.js'

// An account as both front-ends read it: the app's UserMapper
// (features/auth/data/auth_mappers.dart) and the web's Admin (id, fullName,
// email, phone, role). Every role gets the same shape from /customers/me.

export const User = z
  .object({
    id: z.string(),
    fullName: z.string(),
    fullNameAr: z.string().nullable(),
    email: z.string().nullable(),
    phone: z.string().nullable(),
    role: z.enum(['CUSTOMER', 'MERCHANT', 'ADMIN']),
    status: z.enum(['ACTIVE', 'SUSPENDED', 'DELETED']),
    governorate: z.enum(GOVERNORATES).nullable(),
    country: z.string(),
    // No email checks in v1 (BACKEND_PLAN.md §2.2), so shoppers and stores give
    // none at sign-up and only Saba's staff have one that counts as checked
    // (the reviewer's item 13: an unchecked email could take another person's).
    isEmailVerified: z.boolean(),
    // Every number was proved by an SMS code at sign-up.
    isPhoneVerified: z.boolean(),
    avatarUrl: z.string().nullable(),
    createdAt: z.string(),
    merchant: z
      .object({
        id: z.string(),
        storeName: z.string(),
        status: z.enum(['PENDING', 'APPROVED', 'REJECTED', 'SUSPENDED']),
        rejectionReason: z.string().nullable(),
        logoUrl: z.string().nullable(),
        bannerUrl: z.string().nullable(),
        rating: z.number().nullable(),
        // The owner asked to delete the account; the store stays closed until it is done or cancelled.
        deletionRequestedAt: z.string().nullable(),
      })
      .optional(),
  })
  .meta({ id: 'User' })

export type User = z.infer<typeof User>

interface UserRow {
  id: number
  role: User['role']
  status: User['status']
  full_name: string
  full_name_ar: string | null
  email: string | null
  phone: string | null
  governorate: User['governorate']
  country: string
  created_at: Date
  store_id: number | null
  store_name: string | null
  store_status: NonNullable<User['merchant']>['status'] | null
  rejection_reason: string | null
  logo_url: string | null
  banner_url: string | null
  rating_sum: number | null
  rating_count: number | null
  deletion_requested_at: Date | null
}

/** The account [id] as the front-ends read it, with its store for a store owner; photos as full addresses for [req]. */
export async function loadUser(db: Pool | Connection, id: number, req: Request, ctx: Context): Promise<User> {
  const url = (key: string | null) => (key === null ? null : urlOf(req, ctx.config.mediaBaseUrl, key))
  const row = await one<UserRow>(
    db,
    `SELECT u.id, u.role, u.status, u.full_name, u.full_name_ar, u.email, u.phone, u.governorate,
            u.country, u.created_at, s.id AS store_id, s.store_name, s.status AS store_status,
            s.rejection_reason, s.logo_url, s.banner_url, s.rating_sum, s.rating_count, s.deletion_requested_at
       FROM users u LEFT JOIN stores s ON s.owner_user_id = u.id
      WHERE u.id = ?`,
    [id],
  )
  if (!row) throw new Error(`user ${id} vanished`)
  return {
    id: String(row.id),
    fullName: row.full_name,
    fullNameAr: row.full_name_ar,
    email: row.email,
    phone: row.phone,
    role: row.role,
    status: row.status,
    governorate: row.governorate,
    country: row.country,
    // Only Saba's staff have a checked email (create-admin); v1 checks no other (the reviewer's item 13).
    isEmailVerified: row.role === 'ADMIN' && row.email !== null,
    isPhoneVerified: row.phone !== null,
    avatarUrl: null,
    createdAt: row.created_at.toISOString(),
    ...(row.store_id !== null && {
      merchant: {
        id: String(row.store_id),
        storeName: row.store_name!,
        status: row.store_status!,
        rejectionReason: row.rejection_reason,
        logoUrl: url(row.logo_url),
        bannerUrl: url(row.banner_url),
        rating: row.rating_count ? Math.round((row.rating_sum! / row.rating_count) * 10) / 10 : null,
        deletionRequestedAt: row.deletion_requested_at?.toISOString() ?? null,
      },
    }),
  }
}

/** users.search_text: both names folded (admin search, contract §1.7). */
export function userSearchText(fullName: string, fullNameAr: string | null = null): string {
  return fold(`${fullName} ${fullNameAr ?? ''}`).slice(0, 255)
}
