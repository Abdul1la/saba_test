import { z } from 'zod'
import type { Context } from '../app.js'
import { exec } from '../db/sql.js'
import { me } from '../http/auth.js'
import { route, type Api } from '../http/route.js'

// A phone's push address (S10, BACKEND_PLAN.md §7): the app sends its
// Firebase token at sign-in, when Firebase gives it a new one, and when the
// app's language changes; and takes it away at sign-out.

const TAG = 'Push'
const APP = ['CUSTOMER', 'MERCHANT'] as const

/** An FCM registration token: printable ASCII, no spaces. */
const token = z.string().regex(/^[\x21-\x7e]{1,1024}$/, { error: 'field.invalid' })

export function deviceRoutes(api: Api, ctx: Context): void {
  const { pool } = ctx

  route(api, {
    method: 'put',
    path: '/devices',
    tag: TAG,
    summary: "This phone's push address and language; a token already known moves to this account",
    who: APP,
    body: z.object({
      token,
      platform: z.enum(['ANDROID', 'IOS'], { error: 'field.invalid' }),
      language: z.enum(['en', 'ar'], { error: 'field.invalid' }),
    }),
    response: z.object({}),
    async handle({ req, body }) {
      // One row per token: the next person to sign in on this phone takes it
      // over, so one account's pushes never reach the next.
      await exec(
        pool,
        `INSERT INTO device_tokens (token, user_id, platform, language) VALUES (?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE user_id = VALUES(user_id), platform = VALUES(platform), language = VALUES(language)`,
        [body.token, me(req).id, body.platform, body.language],
      )
      return {}
    },
  })

  route(api, {
    method: 'delete',
    path: '/devices',
    tag: TAG,
    summary: "Forget this phone's push address (at sign-out); only the account's own",
    who: APP,
    body: z.object({ token }),
    response: z.object({}),
    async handle({ req, body }) {
      await exec(pool, 'DELETE FROM device_tokens WHERE token = ? AND user_id = ?', [body.token, me(req).id])
      return {}
    },
  })
}
