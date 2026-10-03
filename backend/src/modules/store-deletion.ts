import type { Logger } from 'pino'
import { z } from 'zod'
import type { Context } from '../app.js'
import type { Connection, Pool } from '../db/pool.js'
import { exec, one, rows } from '../db/sql.js'
import { withTransaction } from '../db/tx.js'
import { me } from '../http/auth.js'
import { AppError } from '../http/errors.js'
import { route, type Api } from '../http/route.js'
import { closeStreams, publish } from '../lib/events.js'
import { t } from '../lib/i18n.js'
import type { SendText } from '../lib/sms.js'
import type { MediaStore } from '../lib/storage.js'
import { eraseAccount } from './account.js'
import { leftBehind, storeSearchText } from './stores.js'

// A store owner deletes their account (BACKEND_PLAN.md §6.2; Apple and Google
// refuse deactivation only). Asking closes the store at once. The hourly run
// deletes it once its orders and returns are finished, the last return window
// has passed and Saba is paid: this month's bill is due once the month ends.
// Orders, returns and bills stay, with the store's name on them.

const StoreDeletion = z
  .object({
    requestedAt: z.string().nullable(),
    openOrders: z.number(),
    openReturns: z.number(),
    returnsOpenUntil: z.string().nullable(),
    owed: z.number(),
    currencyCode: z.literal('IQD'),
  })
  .meta({ id: 'StoreDeletion' })

/**
 * Store [id]'s owner asks, or Saba asks for them: the store closes now. False
 * when it was asked already: the first day stands.
 */
export async function askDeletion(db: Pool | Connection, id: number): Promise<boolean> {
  const asked = await exec(db, 'UPDATE stores SET deletion_requested_at = NOW(3), is_open = 0 WHERE id = ? AND deletion_requested_at IS NULL', [id])
  return asked.affectedRows === 1
}

export function storeDeletionRoutes(api: Api, ctx: Context): void {
  const { pool } = ctx

  async function ownStoreId(ownerId: number): Promise<number> {
    const store = await one<{ id: number }>(pool, 'SELECT id FROM stores WHERE owner_user_id = ?', [ownerId])
    if (!store) throw new AppError(404, 'NOT_FOUND_ERROR', 'error.notFound')
    return store.id
  }

  async function stateOf(storeId: number): Promise<z.infer<typeof StoreDeletion>> {
    const row = await one<{ deletion_requested_at: Date | null }>(pool, 'SELECT deletion_requested_at FROM stores WHERE id = ?', [storeId])
    return { requestedAt: row!.deletion_requested_at?.toISOString() ?? null, ...(await leftBehind(pool, storeId)), currencyCode: 'IQD' }
  }

  route(api, {
    method: 'get',
    path: '/merchants/me/deletion',
    tag: 'Store',
    summary: "The owner's account deletion: when it was asked (null: not asked) and what is left to finish",
    who: ['MERCHANT'],
    response: StoreDeletion,
    handle: async ({ req }) => stateOf(await ownStoreId(me(req).id)),
  })

  route(api, {
    method: 'post',
    path: '/merchants/me/deletion',
    tag: 'Store',
    summary: 'Ask to delete the account: the store closes now; the account goes once nothing is left to finish',
    who: ['MERCHANT'],
    response: StoreDeletion,
    async handle({ req }) {
      const id = await ownStoreId(me(req).id)
      await askDeletion(pool, id)
      publish(pool, 'ADMINS', 'stores', id)
      return stateOf(id)
    },
  })

  route(api, {
    method: 'delete',
    path: '/merchants/me/deletion',
    tag: 'Store',
    summary: 'Cancel the deletion; the store stays closed until its owner opens it',
    who: ['MERCHANT'],
    response: z.object({}),
    async handle({ req }) {
      const id = await ownStoreId(me(req).id)
      await exec(pool, "UPDATE stores SET deletion_requested_at = NULL WHERE id = ? AND status <> 'CLOSED'", [id])
      publish(pool, 'ADMINS', 'stores', id)
      return {}
    },
  })
}

interface Closed {
  ownerId: number
  storeName: string
  phone: string | null
  /** The logo and banner, once nothing else shows them. */
  files: string[]
}

/**
 * Store [id], if its owner still asks and nothing is left to finish: closed
 * for good and its owner's account deleted. Null: not yet.
 */
async function closeStore(conn: Connection, id: number): Promise<Closed | null> {
  // Locked, so a cancel waits, and so does a checkout (it reads the store FOR SHARE).
  const store = await one<{ owner_user_id: number; store_name: string; logo_url: string | null; banner_url: string | null; phone: string | null }>(
    conn,
    `SELECT s.owner_user_id, s.store_name, s.logo_url, s.banner_url, u.phone FROM stores s JOIN users u ON u.id = s.owner_user_id
      WHERE s.id = ? AND s.deletion_requested_at IS NOT NULL AND s.status <> 'CLOSED' FOR UPDATE`,
    [id],
  )
  if (!store) return null
  const left = await leftBehind(conn, id)
  if (left.openOrders > 0 || left.openReturns > 0 || left.returnsOpenUntil !== null || left.owed > 0) return null

  // Its products leave the shop for good, and every cart and wishlist. Their
  // photos stay: past orders show the same files.
  await exec(
    conn,
    'DELETE FROM cart_items WHERE sku_id IN (SELECT k.id FROM product_skus k JOIN products p ON p.id = k.product_id WHERE p.store_id = ?)',
    [id],
  )
  await exec(conn, 'DELETE FROM wishlist_items WHERE product_id IN (SELECT id FROM products WHERE store_id = ?)', [id])
  await exec(conn, 'UPDATE products SET deleted_at = NOW(3) WHERE store_id = ? AND deleted_at IS NULL', [id])
  // Orders keep the code they used.
  await exec(conn, 'DELETE FROM coupons WHERE store_id = ?', [id])
  await exec(conn, 'DELETE FROM featured_stores WHERE store_id = ?', [id])
  await exec(
    conn,
    `UPDATE stores SET status = 'CLOSED', closed_at = NOW(3), is_open = 0, logo_url = NULL, banner_url = NULL,
                       business_address = NULL, business_address_ar = NULL, description = NULL, description_ar = NULL,
                       search_text = ?
      WHERE id = ?`,
    [storeSearchText(store.store_name, null), id],
  )
  await eraseAccount(conn, store.owner_user_id)

  const files: string[] = []
  for (const key of new Set([store.logo_url, store.banner_url])) {
    if (key === null) continue
    const used = await one(conn, 'SELECT 1 FROM product_images WHERE url = ? UNION ALL SELECT 1 FROM order_items WHERE image_url = ? LIMIT 1', [
      key,
      key,
    ])
    if (used) continue
    await exec(conn, 'UPDATE media_files SET deleted_at = NOW(3) WHERE storage_key = ?', [key])
    files.push(key)
  }
  publish(conn, 'ADMINS', 'stores', id)
  return { ownerId: store.owner_user_id, storeName: store.store_name, phone: store.phone, files }
}

/**
 * The hourly run's part (BACKEND_PLAN.md §5.6): every store whose owner asked
 * and has nothing left to finish is deleted, and its owner told by SMS. A store
 * that fails waits for the next run; an SMS that fails is only logged.
 * How many stores went.
 */
export async function finishStoreDeletions(deps: { pool: Pool; media: MediaStore; sendText: SendText; logger: Logger }): Promise<number> {
  const asked = await rows<{ id: number }>(
    deps.pool,
    "SELECT id FROM stores WHERE deletion_requested_at IS NOT NULL AND status <> 'CLOSED' ORDER BY id",
  )
  let deleted = 0
  for (const { id } of asked) {
    let closed: Closed | null
    try {
      closed = await withTransaction(deps.pool, (conn) => closeStore(conn, id))
    } catch (error) {
      deps.logger.warn({ err: error, storeId: id }, 'store deletion failed; trying again at the next run')
      continue
    }
    if (!closed) continue
    deleted += 1
    closeStreams(closed.ownerId)
    // Both languages in one message: the owner's language went with the account.
    const text = `${t('ar', 'sms.storeDeleted', { store: closed.storeName })}\n${t('en', 'sms.storeDeleted', { store: closed.storeName })}`
    if (closed.phone) {
      await deps.sendText(closed.phone, text).catch((error: unknown) => deps.logger.warn({ err: error, storeId: id }, 'the store-deleted SMS was not sent'))
    }
    for (const key of closed.files) {
      await deps.media.remove(key).catch((error: unknown) => deps.logger.warn({ err: error, key }, 'a deleted store photo stayed in storage'))
    }
  }
  return deleted
}
