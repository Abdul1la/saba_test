import { z } from 'zod'
import type { Context } from '../app.js'
import type { Connection, Pool } from '../db/pool.js'
import { exec, one, rows } from '../db/sql.js'
import { withTransaction } from '../db/tx.js'
import { me } from '../http/auth.js'
import { AppError } from '../http/errors.js'
import { governorate, IdParams, iraqiPhone, optionalText, requiredText } from '../http/inputs.js'
import { route, type Api } from '../http/route.js'
import { closeStreams, publish } from '../lib/events.js'
import { GOVERNORATES } from '../lib/governorates.js'
import { listOf, type Lang } from '../lib/i18n.js'
import type { MediaStore } from '../lib/storage.js'
import { NAME_MAX } from '../rules.js'
import { loadUser, User, userSearchText } from './users.js'

// The signed-in account and the shopper's addresses (BACKEND_PLAN.md §6.1).

const Empty = z.object({})

/**
 * Account [id] goes, a shopper's or a store owner's: its own data is deleted
 * and it is signed out everywhere. Its orders keep their own copies of name,
 * phone and address. The caller ends its live streams once this commits.
 */
export async function eraseAccount(conn: Connection, id: number): Promise<void> {
  await exec(conn, 'DELETE FROM cart_items WHERE user_id = ?', [id])
  await exec(conn, 'DELETE FROM carts WHERE user_id = ?', [id])
  await exec(conn, 'DELETE FROM wishlist_items WHERE user_id = ?', [id])
  await exec(conn, 'DELETE FROM addresses WHERE user_id = ?', [id])
  // No push reaches a deleted account's phones (S10).
  await exec(conn, 'DELETE FROM device_tokens WHERE user_id = ?', [id])
  await exec(
    conn,
    `UPDATE users SET status = 'DELETED', phone = NULL, email = NULL, full_name = '', full_name_ar = NULL,
                      password_hash = NULL, search_text = '', deleted_at = NOW(3)
      WHERE id = ?`,
    [id],
  )
  await exec(conn, 'UPDATE refresh_tokens SET revoked_at = NOW(3) WHERE user_id = ? AND revoked_at IS NULL', [id])
  // Their tickets keep what was said, not who said it; a store's keep its name (the reviewer's item 14).
  await exec(conn, "UPDATE support_tickets SET opener_phone = '', opener_name = IF(opened_by_kind = 'SHOPPER', '', opener_name) WHERE opened_by_user_id = ?", [id])
  // The photos they sent in chats go with them (the user's call, 2026-10-01): shown as removed at
  // once; the files go at the hourly run, once no open report still shows them (deleteRemovedChatPhotos).
  await exec(
    conn,
    `UPDATE messages m JOIN conversations c ON c.id = m.conversation_id JOIN stores s ON s.id = c.store_id
        SET m.photo_removed_at = NOW(3), m.photo_removed_by = 'ACCOUNT'
      WHERE m.photo_key IS NOT NULL AND m.photo_removed_at IS NULL
        AND ((m.sender = 'CUSTOMER' AND c.customer_id = ?) OR (m.sender = 'STORE' AND s.owner_user_id = ?))`,
    [id, id],
  )
}

/**
 * The hourly run's part for chat photos: the files of photos removed (their
 * sender's account deleted, or Saba removed them) are deleted from storage.
 * One its sender's deletion removed waits while an open report shows it, so
 * deleting an account never destroys evidence. How many went.
 */
export async function deleteRemovedChatPhotos(pool: Pool, media: MediaStore): Promise<number> {
  const due = await rows<{ id: number; photo_key: string }>(
    pool,
    `SELECT m.id, m.photo_key FROM messages m
      WHERE m.photo_removed_at IS NOT NULL AND m.photo_deleted_at IS NULL
        AND (m.photo_removed_by = 'SABA' OR NOT EXISTS (
              SELECT 1 FROM reports r WHERE r.status = 'OPEN' AND r.target_type = 'CONVERSATION'
                AND r.target_id = m.conversation_id AND JSON_CONTAINS(r.evidence, JSON_OBJECT('photo', m.photo_key))))
      LIMIT 500`,
  )
  for (const photo of due) {
    await media.remove(photo.photo_key)
    await exec(pool, 'UPDATE messages SET photo_deleted_at = NOW(3) WHERE id = ?', [photo.id])
  }
  return due.length
}

/**
 * Shopper [id]'s account goes now: their own delete, or Saba's at their
 * request. Refused (409, naming them) while an order is open (Q9).
 */
export async function deleteShopper(conn: Connection, id: number): Promise<void> {
  // The shopper's row first, as checkout takes it (DATABASE_DESIGN.md §5.1):
  // no order can be placed while this runs, so none slips past the check.
  await one(conn, 'SELECT id FROM users WHERE id = ? FOR UPDATE', [id])
  const open = await rows<{ number: string }>(
    conn,
    `SELECT COALESCE(order_number, CONCAT('SB-', 100000 + id)) AS number FROM orders
      WHERE customer_id = ? AND status NOT IN ('DELIVERED', 'CANCELLED', 'REFUSED') ORDER BY id`,
    [id],
  )
  if (open.length > 0) {
    const orders = listOf(open.map((order) => order.number))
    throw new AppError(409, 'CONFLICT_ERROR', open.length === 1 ? 'account.openOrder' : 'account.openOrders', { orders })
  }
  await eraseAccount(conn, id)
}

export function accountRoutes(api: Api, ctx: Context): void {
  const { pool } = ctx

  route(api, {
    method: 'get',
    path: '/customers/me',
    tag: 'Account',
    summary: 'The signed-in account, with its store for a store owner (every role)',
    who: 'signedIn',
    response: User,
    handle: ({ req }) => loadUser(pool, me(req).id, req, ctx),
  })

  route(api, {
    method: 'patch',
    path: '/customers/me',
    tag: 'Account',
    summary: 'Change the name or governorate (a new phone number needs an SMS check, so it is ignored)',
    who: 'signedIn',
    body: z.object({ fullName: requiredText(NAME_MAX.person).optional(), governorate: governorate.optional() }),
    response: User,
    async handle({ req, body }) {
      const { id } = me(req)
      if (body.fullName !== undefined) {
        await exec(pool, 'UPDATE users SET full_name = ?, search_text = ? WHERE id = ?', [
          body.fullName,
          userSearchText(body.fullName),
          id,
        ])
      }
      if (body.governorate !== undefined) {
        await exec(pool, 'UPDATE users SET governorate = ? WHERE id = ?', [body.governorate, id])
      }
      return loadUser(pool, id, req, ctx)
    },
  })

  route(api, {
    method: 'delete',
    path: '/customers/me',
    tag: 'Account',
    summary: "Delete the shopper's account; refused while an order is open (Q9)",
    who: ['CUSTOMER'],
    response: Empty,
    async handle({ req }) {
      const { id } = me(req)
      await withTransaction(pool, async (conn) => {
        await deleteShopper(conn, id)
        publish(conn, 'ADMINS', 'customers', id)
      })
      // Gone at once: its live streams end with its sign-ins.
      closeStreams(id)
      return {}
    },
  })

  // ---------------------------------------------------------------- addresses ---

  const AddressInput = z.object({
    fullName: requiredText(NAME_MAX.person),
    phone: iraqiPhone,
    governorate,
    area: requiredText(100),
    landmark: requiredText(150),
    street: optionalText(150),
    label: optionalText(30),
    instructions: optionalText(300),
    isDefault: z.boolean().optional(),
  })
  type AddressInput = z.infer<typeof AddressInput>

  route(api, {
    method: 'get',
    path: '/customers/me/addresses',
    tag: 'Account',
    summary: "The shopper's addresses, the default first",
    who: ['CUSTOMER'],
    response: z.array(Address),
    async handle({ req }) {
      const found = await rows<AddressRow>(
        pool,
        `${ADDRESS_SELECT} WHERE user_id = ? ORDER BY is_default DESC, id DESC`,
        [me(req).id],
      )
      return found.map((row) => addressOut(row, req.lang))
    },
  })

  route(api, {
    method: 'post',
    path: '/customers/me/addresses',
    tag: 'Account',
    summary: 'Add an address; the first one is the default',
    who: ['CUSTOMER'],
    body: AddressInput,
    response: Address,
    async handle({ req, body }) {
      const userId = me(req).id
      const id = await withTransaction(pool, async (conn) => {
        const first = !(await one(conn, 'SELECT id FROM addresses WHERE user_id = ? LIMIT 1', [userId]))
        const isDefault = first || body.isDefault === true
        if (isDefault) await clearDefault(conn, userId)
        const inserted = await exec(
          conn,
          `INSERT INTO addresses (user_id, label, full_name, phone, governorate, area, street, landmark,
                                  instructions, is_default)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          [userId, ...addressValues(body), isDefault],
        )
        return inserted.insertId
      })
      return addressOut((await readAddress(pool, id, userId))!, req.lang)
    },
  })

  route(api, {
    method: 'put',
    path: '/customers/me/addresses/:id',
    tag: 'Account',
    summary: 'Replace an address',
    who: ['CUSTOMER'],
    params: IdParams,
    body: AddressInput,
    response: Address,
    async handle({ req, params, body }) {
      const userId = me(req).id
      const id = idOf(params.id)
      await withTransaction(pool, async (conn) => {
        const current = await readAddress(conn, id, userId)
        if (!current) throw notFound()
        const isDefault = body.isDefault ?? current.is_default === 1
        if (isDefault) await clearDefault(conn, userId)
        // A field edited in one language replaces both (BACKEND_PLAN.md §9 item 5).
        await exec(
          conn,
          `UPDATE addresses SET label = ?, full_name = ?, phone = ?, governorate = ?, area = ?, street = ?,
                                landmark = ?, instructions = ?, is_default = ?,
                                full_name_ar = NULL, area_ar = NULL, street_ar = NULL, landmark_ar = NULL
            WHERE id = ? AND user_id = ?`,
          [...addressValues(body), isDefault, id, userId],
        )
      })
      return addressOut((await readAddress(pool, id, userId))!, req.lang)
    },
  })

  route(api, {
    method: 'delete',
    path: '/customers/me/addresses/:id',
    tag: 'Account',
    summary: 'Delete an address',
    who: ['CUSTOMER'],
    params: IdParams,
    response: Empty,
    async handle({ req, params }) {
      const deleted = await exec(pool, 'DELETE FROM addresses WHERE id = ? AND user_id = ?', [
        idOf(params.id),
        me(req).id,
      ])
      if (deleted.affectedRows === 0) throw notFound()
      return {}
    },
  })

  route(api, {
    method: 'put',
    path: '/customers/me/addresses/:id/default',
    tag: 'Account',
    summary: 'Make an address the default',
    who: ['CUSTOMER'],
    params: IdParams,
    response: Address,
    async handle({ req, params }) {
      const userId = me(req).id
      const id = idOf(params.id)
      await withTransaction(pool, async (conn) => {
        if (!(await readAddress(conn, id, userId))) throw notFound()
        await clearDefault(conn, userId)
        await exec(conn, 'UPDATE addresses SET is_default = 1 WHERE id = ? AND user_id = ?', [id, userId])
      })
      return addressOut((await readAddress(pool, id, userId))!, req.lang)
    },
  })

  function addressValues(body: AddressInput) {
    return [
      body.label,
      body.fullName,
      body.phone,
      body.governorate,
      body.area,
      body.street,
      body.landmark,
      body.instructions,
    ]
  }
}

// An address as the app's AddressMappers reads it.
const Address = z
  .object({
    id: z.string(),
    label: z.string().nullable(),
    fullName: z.string(),
    phone: z.string(),
    governorate: z.enum(GOVERNORATES),
    area: z.string(),
    street: z.string().nullable(),
    landmark: z.string(),
    instructions: z.string().nullable(),
    isDefault: z.boolean(),
  })
  .meta({ id: 'Address' })

interface AddressRow {
  id: number
  label: string | null
  full_name: string
  full_name_ar: string | null
  phone: string
  governorate: (typeof GOVERNORATES)[number]
  area: string
  area_ar: string | null
  street: string | null
  street_ar: string | null
  landmark: string
  landmark_ar: string | null
  instructions: string | null
  is_default: number
}

const ADDRESS_SELECT = `SELECT id, label, full_name, full_name_ar, phone, governorate, area, area_ar, street, street_ar,
                               landmark, landmark_ar, instructions, is_default FROM addresses`

function readAddress(db: Parameters<typeof one>[0], id: number, userId: number) {
  return one<AddressRow>(db, `${ADDRESS_SELECT} WHERE id = ? AND user_id = ?`, [id, userId])
}

/** In the asked language: the Arabic twin, when a seeded address has one (BACKEND_PLAN.md §5.5). */
function addressOut(row: AddressRow, lang: Lang): z.infer<typeof Address> {
  const pick = (text: string, arabic: string | null) => (lang === 'ar' && arabic ? arabic : text)
  const street = row.street === null ? null : pick(row.street, row.street_ar)
  return {
    id: String(row.id),
    label: row.label,
    fullName: pick(row.full_name, row.full_name_ar),
    phone: row.phone,
    governorate: row.governorate,
    area: pick(row.area, row.area_ar),
    street,
    landmark: pick(row.landmark, row.landmark_ar),
    instructions: row.instructions,
    isDefault: row.is_default === 1,
  }
}

/**
 * Clears the shopper's default. Its row locks (every address of theirs, through
 * the user_id index) make two changes of default take turns; the unique
 * default_for holds the one-default rule even so.
 */
async function clearDefault(conn: Connection, userId: number): Promise<void> {
  await exec(conn, 'UPDATE addresses SET is_default = 0 WHERE user_id = ? AND is_default = 1', [userId])
}

/** A path id, or 404: an id that isn't a number names nothing. */
function idOf(text: string): number {
  if (!/^\d{1,15}$/.test(text)) throw notFound()
  return Number(text)
}

function notFound(): AppError {
  return new AppError(404, 'NOT_FOUND_ERROR', 'error.notFound')
}
