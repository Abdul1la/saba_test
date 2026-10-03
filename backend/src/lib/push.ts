import { importPKCS8, SignJWT } from 'jose'
import type { Logger } from 'pino'
import type { Connection, Pool } from '../db/pool.js'
import { exec, one, rows } from '../db/sql.js'
import { afterCommit } from './events.js'

// Push notifications (S10, BACKEND_PLAN.md §7): a notification the server has
// written, sent to the phones of the account it is for, once its transaction
// has committed. Only the kinds in BACKEND_PLAN.md §2.0 "S10" push (their
// notify() calls say so); the rest wait in the list until the app is opened.
// Each phone gets it in its own language. A push that fails is logged and
// never undoes the change: that has already been committed.

export interface PushMessage {
  token: string
  platform: 'ANDROID' | 'IOS'
  title: string
  body: string
  /** What a tap opens: the same as the notification in the list. FCM data values are strings. */
  data: Record<string, string>
}

/** 'sent', or 'gone' when the phone no longer holds that token: its row is then deleted. Throws on anything else. */
export type SendPush = (message: PushMessage) => Promise<'sent' | 'gone'>

/** While developing: what would be sent goes to the server's log. */
export function logPush(logger: Logger): SendPush {
  return async (message) => {
    logger.info(
      { platform: message.platform, token: `${message.token.slice(0, 8)}…`, title: message.title, body: message.body, data: message.data },
      'Push (log): what Firebase would be sent',
    )
    return 'sent'
  }
}

export interface FcmOptions {
  projectId: string
  clientEmail: string
  privateKey: string
  /** Google's token endpoint (the service account's token_uri); a stand-in in tests. */
  tokenUrl?: string
  /** FCM's send endpoint; a stand-in in tests. */
  sendUrl?: string
}

const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging'

/**
 * Firebase Cloud Messaging, HTTP v1: an OAuth2 token from the service account
 * (a JWT signed with its private key), kept until a minute before it runs out,
 * then one POST per phone. The private key and the tokens are never logged.
 * iPhones are reached through Firebase too: the APNs key is uploaded there.
 */
export function fcmPush(options: FcmOptions): SendPush {
  const tokenUrl = options.tokenUrl ?? 'https://oauth2.googleapis.com/token'
  const sendUrl = options.sendUrl ?? `https://fcm.googleapis.com/v1/projects/${options.projectId}/messages:send`
  let key: ReturnType<typeof importPKCS8> | null = null
  let access: { token: string; until: number } | null = null

  async function accessToken(): Promise<string> {
    if (access && access.until > Date.now() + 60_000) return access.token
    key ??= importPKCS8(options.privateKey, 'RS256')
    const assertion = await new SignJWT({ scope: FCM_SCOPE })
      .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
      .setIssuer(options.clientEmail)
      .setAudience(tokenUrl)
      .setIssuedAt()
      .setExpirationTime('1h')
      .sign(await key)
    const response = await fetch(tokenUrl, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }),
      signal: AbortSignal.timeout(10_000),
    })
    const body = (await response.json().catch(() => ({}))) as { access_token?: string; expires_in?: number; error?: string }
    if (!response.ok || !body.access_token) throw new Error(`Firebase refused the service account (${response.status} ${body.error ?? ''})`)
    access = { token: body.access_token, until: Date.now() + (body.expires_in ?? 3600) * 1000 }
    return access.token
  }

  return async (message) => {
    const response = await fetch(sendUrl, {
      method: 'POST',
      headers: { authorization: `Bearer ${await accessToken()}`, 'content-type': 'application/json' },
      body: JSON.stringify({
        message: {
          token: message.token,
          notification: { title: message.title, body: message.body },
          data: message.data,
          android: { notification: { channel_id: 'saba_default' } },
        },
      }),
      signal: AbortSignal.timeout(10_000),
    })
    if (response.ok) return 'sent'
    const body = (await response.json().catch(() => ({}))) as { error?: { status?: string; details?: { errorCode?: string }[] } }
    // The app was removed or its token replaced: FCM says so, and the token is forgotten.
    if (response.status === 404 || body.error?.details?.some((detail) => detail.errorCode === 'UNREGISTERED')) return 'gone'
    if (response.status === 401) access = null
    throw new Error(`Firebase refused the push (${response.status} ${body.error?.status ?? ''})`)
  }
}

// ------------------------------------------------------------ sending ---

/** Where pushes go, set by createApp; null when push is off. */
let active: { send: SendPush; pool: Pool; logger: Logger } | null = null

export function usePush(send: SendPush | null, pool: Pool, logger: Logger): void {
  active = send ? { send, pool, logger } : null
}

const inflight = new Set<Promise<void>>()

/** Sends notification [notificationId] to its reader's phones once [db]'s transaction commits; nothing after a rollback. */
export function pushLater(db: Pool | Connection, notificationId: number): void {
  afterCommit(db, () => {
    const job: Promise<void> = pushOut(notificationId).finally(() => inflight.delete(job))
    inflight.add(job)
  })
}

/** For tests: resolves once every push started so far has finished. */
export async function pushesDone(): Promise<void> {
  while (inflight.size > 0) await Promise.all([...inflight])
}

async function pushOut(id: number): Promise<void> {
  const sender = active
  if (!sender) return
  try {
    const note = await one<{
      user_id: number
      status: string
      title_en: string
      title_ar: string
      body_en: string
      body_ar: string
      entity_type: string | null
      entity_id: string | null
    }>(
      sender.pool,
      `SELECT n.user_id, u.status, n.title_en, n.title_ar, n.body_en, n.body_ar, n.entity_type, n.entity_id
         FROM notifications n JOIN users u ON u.id = n.user_id WHERE n.id = ?`,
      [id],
    )
    // A deleted account or a suspended shopper gets none. A suspended store's
    // owner is still an active account: it still works its open orders (Q4).
    if (!note || note.status !== 'ACTIVE') return
    const devices = await rows<{ id: number; token: string; platform: 'ANDROID' | 'IOS'; language: string }>(
      sender.pool,
      'SELECT id, token, platform, language FROM device_tokens WHERE user_id = ?',
      [note.user_id],
    )
    const data: Record<string, string> = {
      notificationId: String(id),
      ...(note.entity_type !== null && { targetType: note.entity_type }),
      ...(note.entity_id !== null && { targetId: note.entity_id }),
    }
    for (const device of devices) {
      const arabic = device.language === 'ar'
      try {
        const result = await sender.send({
          token: device.token,
          platform: device.platform,
          title: arabic ? note.title_ar : note.title_en,
          body: arabic ? note.body_ar : note.body_en,
          data,
        })
        if (result === 'gone') await exec(sender.pool, 'DELETE FROM device_tokens WHERE id = ? AND token = ?', [device.id, device.token])
      } catch (error) {
        sender.logger.warn({ err: error, notificationId: id, deviceId: device.id }, 'push not sent')
      }
    }
  } catch (error) {
    sender.logger.warn({ err: error, notificationId: id }, 'push not sent')
  }
}
