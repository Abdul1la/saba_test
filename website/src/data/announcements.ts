import { http, USE_MOCK } from './http'
import { reply } from './mock'

/** Who an announcement goes to: the client's three, and no one picked by hand. */
export type Audience = 'EVERYONE' | 'CUSTOMERS' | 'MERCHANTS'

export interface SentAnnouncement {
  id: string
  audience: Audience
  title: string
  body: string
  recipients: number
  sentAt: string
  sentBy: string
}

export interface Announcements {
  /** How many accounts each audience reaches now. */
  recipients: Record<Audience, number>
  /** The last 20 sent, newest first. */
  sent: SentAnnouncement[]
}

const RECIPIENTS: Record<Audience, number> = { EVERYONE: 128, CUSTOMERS: 112, MERCHANTS: 16 }
let SENT: SentAnnouncement[] = []

/** GET /admin/announcements */
export function getAnnouncements(): Promise<Announcements> {
  if (!USE_MOCK) return http('GET', '/admin/announcements')
  return reply(() => ({ recipients: { ...RECIPIENTS }, sent: [...SENT] }))
}

/** POST /admin/announcements: in the app and on the phones of [audience]. */
export function sendAnnouncement(input: { audience: Audience; title: string; body: string }): Promise<SentAnnouncement> {
  if (!USE_MOCK) return http('POST', '/admin/announcements', input, { serverWords: true })
  return reply(() => {
    const sent: SentAnnouncement = {
      id: `a-${Date.now()}`,
      ...input,
      recipients: RECIPIENTS[input.audience],
      sentAt: new Date().toISOString(),
      sentBy: 'Saba Admin',
    }
    SENT = [sent, ...SENT].slice(0, 20)
    return sent
  })
}
