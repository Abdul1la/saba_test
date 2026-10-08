import type { Connection, Pool } from '../db/pool.js'
import { exec } from '../db/sql.js'
import { publish } from './events.js'
import { pushLater } from './push.js'

// A notification row, written in both languages when it is made and sent in
// the one each reader asks for (DATABASE_DESIGN.md §3.8). Written inside the
// transaction of the change it is about; the reader's live stream hears of it
// once that commits.

export type NotificationType =
  | 'ORDER'
  | 'SHIPPING'
  | 'DELIVERY'
  | 'PRODUCT_APPROVAL'
  | 'STORE'
  | 'MESSAGE'
  | 'TICKET'
  | 'PAYMENT'
  /** Saba's own, from the admin website (migration 0014): opens nothing. */
  | 'ANNOUNCEMENT'

/** What a tap opens (notifications_screen.dart). */
export type NotificationTarget =
  | 'ORDER'
  | 'STORE_ORDER'
  | 'RETURN'
  | 'STORE_PRODUCT'
  | 'STORE'
  | 'CONVERSATION'
  | 'TICKET'

export interface Words {
  title: string
  body: string
}

export async function notify(
  db: Pool | Connection,
  userId: number,
  type: NotificationType,
  words: { en: Words; ar: Words },
  target?: { type: NotificationTarget; id: string | number },
  /** push: also to the reader's phones (S10: only what needs action or touches money, BACKEND_PLAN.md §2.0). */
  options: { push?: boolean } = {},
): Promise<void> {
  const inserted = await exec(
    db,
    `INSERT INTO notifications (user_id, type, title_en, title_ar, body_en, body_ar, entity_type, entity_id)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      userId,
      type,
      words.en.title,
      words.ar.title,
      words.en.body.slice(0, 1000),
      words.ar.body.slice(0, 1000),
      target?.type ?? null,
      target === undefined ? null : String(target.id),
    ],
  )
  // The bell and the list reload on the reader's open screens.
  publish(db, userId, 'notifications')
  if (options.push) pushLater(db, inserted.insertId)
}
