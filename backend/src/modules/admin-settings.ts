import { z } from 'zod'
import type { Context } from '../app.js'
import type { Connection, Pool } from '../db/pool.js'
import { exec } from '../db/sql.js'
import { withTransaction } from '../db/tx.js'
import { me } from '../http/auth.js'
import { route, type Api } from '../http/route.js'
import { setSetting, settingOn } from '../lib/settings.js'

// Saba's switches on the admin website (the user's call, 2026-10-05). For now
// one: whether a store's new or changed product goes live without the queue.

const TAG = 'Admin: settings'
const ADMIN = ['ADMIN'] as const

const Settings = z
  .object({
    /** On: a product a store adds or changes is approved at once; off: it waits in the queue. */
    autoApproveProducts: z.boolean(),
  })
  .meta({ id: 'AdminSettings' })

export function adminSettingsRoutes(api: Api, ctx: Context): void {
  const { pool } = ctx

  const settingsOf = async (db: Pool | Connection): Promise<z.infer<typeof Settings>> => ({
    autoApproveProducts: await settingOn(db, 'auto_approve_products'),
  })

  route(api, {
    method: 'get',
    path: '/admin/settings',
    tag: TAG,
    summary: "Saba's switches",
    who: ADMIN,
    response: Settings,
    handle: () => settingsOf(pool),
  })

  route(api, {
    method: 'patch',
    path: '/admin/settings',
    tag: TAG,
    summary: "Change Saba's switches; each change is in the admin log",
    who: ADMIN,
    body: Settings.partial(),
    response: Settings,
    handle: ({ req, body }) =>
      withTransaction(pool, async (conn) => {
        if (body.autoApproveProducts !== undefined) {
          await setSetting(conn, 'auto_approve_products', body.autoApproveProducts)
          await exec(
            conn,
            `INSERT INTO admin_actions (admin_user_id, action, entity_type, entity_id, details, ip)
             VALUES (?, 'SETTING_CHANGE', 'SETTING', 'auto_approve_products', ?, ?)`,
            [me(req).id, JSON.stringify({ on: body.autoApproveProducts }), req.ip ?? null],
          )
        }
        return settingsOf(conn)
      }),
  })
}
