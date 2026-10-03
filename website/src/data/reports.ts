import { http, httpPage, USE_MOCK } from './http'
import { ApiError, countBy, daysAgo, pageOf, reply } from './mock'
import { SARA } from './people'
import { allProducts } from './products'
import type { ReportReason } from './reviews'
import { storeFace } from './stores'
import type { ListResult, PageAsk, Paged } from './types'

// Products, stores and chats reported from the app (API_CONTRACT.md §3.13).
// Saba acts with the tools it has (takes the product down, suspends the store
// or the chat's shopper), then marks the reports handled, or dismisses them.

export type ReportTarget = 'PRODUCT' | 'STORE' | 'CONVERSATION'
/** ACTIONED: "handled". */
export type ReportStatus = 'OPEN' | 'DISMISSED' | 'ACTIONED'

export interface ChatLine {
  from: 'CUSTOMER' | 'STORE'
  /** '' for a photo. */
  body: string
  sentAt: string
  /** For "Remove photo"; old reports have none (API_CONTRACT.md §3.13). */
  messageId?: string
  /** A photo sent in the chat, signed for Saba: it opens for one to two hours. */
  photoUrl?: string
  /** ACCOUNT: its sender deleted their account (the photo still opens while the report is open). SABA: Saba removed it. */
  photoRemoved?: 'ACCOUNT' | 'SABA'
}

export interface Report {
  id: string
  reason: ReportReason
  /** The reporter's own words. */
  description?: string
  /** Left out for a deleted account. */
  reporterName?: string
  reporterRole: 'CUSTOMER' | 'MERCHANT'
  createdAt: string
  status: ReportStatus
  /** A chat report: the chat's last 20 messages when it was reported, oldest first. */
  evidence?: ChatLine[]
}

export interface ReportedItem {
  /** "PRODUCT-12", "STORE-3", "CONVERSATION-40". */
  id: string
  type: ReportTarget
  targetId: string
  /** OPEN while a report waits; else how the last one was closed. */
  status: ReportStatus
  /** The product's name, the store's name, or "Shopper · Store" for a chat. */
  title: string
  product?: { id: string; name: string; status: string; takenDown: boolean }
  /** A product's store, the store, or a chat's store. */
  store?: { id: string; storeName: string; status: string }
  /** A chat's shopper; left out for a deleted account. */
  customer?: { id: string; fullName: string }
  lastReportedAt: string
  /** Newest first. */
  reports: Report[]
}

/** GET /admin/reports?status=&type=&page= : one page, the latest report first; the counts are within `type`, whatever `status`. */
export function listReports(query: { status?: ReportStatus; type?: ReportTarget } & PageAsk): Promise<Paged<ListResult<ReportedItem, ReportStatus>>> {
  if (!USE_MOCK) return httpPage('/admin/reports', { status: query.status, type: query.type }, query)
  return reply(() => {
    const ofType = seeds().filter((s) => !query.type || s.type === query.type)
    return {
      ...pageOf(
        ofType
          .filter((s) => !query.status || s.status === query.status)
          .sort((a, b) => b.lastReportedAt.localeCompare(a.lastReportedAt))
          .map(face),
        query,
      ),
      counts: countBy(ofType, (s) => [s.status]),
    }
  })
}

/** POST /admin/reports/{type}/{targetId}/dismiss: nothing needed doing; its open reports close as DISMISSED. */
export function dismissReports(item: ReportedItem): Promise<ReportedItem> {
  if (!USE_MOCK) return http('POST', reportPath(item, 'dismiss'))
  return close(item, 'DISMISSED')
}

/** POST /admin/reports/{type}/{targetId}/resolve: Saba acted; its open reports close as ACTIONED. */
export function resolveReports(item: ReportedItem): Promise<ReportedItem> {
  if (!USE_MOCK) return http('POST', reportPath(item, 'resolve'))
  return close(item, 'ACTIONED')
}

/** POST /admin/messages/{messageId}/remove-photo: from the chat, for both sides, and its file. 409 when already removed. */
export function removeChatPhoto(messageId: string): Promise<unknown> {
  if (!USE_MOCK) return http('POST', `/admin/messages/${encodeURIComponent(messageId)}/remove-photo`, undefined, { serverWords: true })
  return reply(() => {
    const line = seeds()
      .flatMap((s) => s.reports.flatMap((r) => r.evidence ?? []))
      .find((m) => m.messageId === messageId && (m.photoUrl || m.photoRemoved))
    if (!line) throw new ApiError('NOT_FOUND')
    if (line.photoRemoved === 'SABA') throw new ApiError('WRONG_STATE')
    line.photoRemoved = 'SABA'
    delete line.photoUrl
    return {}
  })
}

const reportPath = (item: ReportedItem, action: string) => `/admin/reports/${item.type}/${encodeURIComponent(item.targetId)}/${action}`

// web-only demo: a product and a chat waiting for an answer, a store whose report was dismissed.
// The product and the stores are read from their own mock each time, so a takedown or a suspension shows here.
type Seed = Omit<ReportedItem, 'title' | 'product' | 'store' | 'customer'> & { chatStoreId?: string }
let seeded: Seed[] | undefined

function seeds(): Seed[] {
  if (seeded) return seeded
  const product = allProducts().find((p) => p.merchant.id === 'm-1' && p.status === 'APPROVED')!
  const chat = (from: ChatLine['from'], body: string, days: number, hours: number): ChatLine => ({ from, body, sentAt: daysAgo(days, hours) })
  seeded = [
    {
      id: `PRODUCT-${product.id}`,
      type: 'PRODUCT',
      targetId: product.id,
      status: 'OPEN',
      lastReportedAt: daysAgo(0, 3),
      reports: [
        { id: 'rp-2', reason: 'COUNTERFEIT', description: 'The box has no serial number. It is not the real brand.', reporterName: 'Yousef Karim', reporterRole: 'CUSTOMER', createdAt: daysAgo(0, 3), status: 'OPEN' },
        { id: 'rp-1', reason: 'MISLEADING', reporterName: 'Noor Hadi', reporterRole: 'CUSTOMER', createdAt: daysAgo(2), status: 'OPEN' },
      ],
    },
    {
      id: 'CONVERSATION-cv-1',
      type: 'CONVERSATION',
      targetId: 'cv-1',
      chatStoreId: 'm-2',
      status: 'OPEN',
      lastReportedAt: daysAgo(1, 2),
      reports: [
        {
          id: 'rp-3',
          reason: 'OFFENSIVE',
          description: 'The shopper insulted our staff.',
          reporterName: 'Atlas Home',
          reporterRole: 'MERCHANT',
          createdAt: daysAgo(1, 2),
          status: 'OPEN',
          evidence: [
            chat('CUSTOMER', 'Where is my order? It is three days late.', 1, 6),
            chat('STORE', 'Sorry for the wait. The driver will call you today.', 1, 5),
            chat('CUSTOMER', 'You are all liars. I will make sure nobody buys from you.', 1, 3),
            // web-only demo: a photo sent in the chat.
            { from: 'CUSTOMER', body: '', sentAt: daysAgo(1, 3), messageId: 'msg-4', photoUrl: '/demo/products/home-appliances-1.jpg' },
          ],
        },
      ],
    },
    {
      id: 'STORE-m-3',
      type: 'STORE',
      targetId: 'm-3',
      status: 'DISMISSED',
      lastReportedAt: daysAgo(6),
      reports: [{ id: 'rp-4', reason: 'SPAM', reporterName: 'Omar Farouk', reporterRole: 'CUSTOMER', createdAt: daysAgo(6), status: 'DISMISSED' }],
    },
  ]
  return seeded
}

function face({ chatStoreId, ...seed }: Seed): ReportedItem {
  if (seed.type === 'PRODUCT') {
    const p = allProducts().find((x) => x.id === seed.targetId)!
    return { ...seed, title: p.nameEn, product: { id: p.id, name: p.nameEn, status: p.status, takenDown: p.takenDown }, store: storeFace(p.merchant.id) }
  }
  if (seed.type === 'STORE') {
    const store = storeFace(seed.targetId)
    return { ...seed, title: store.storeName, store }
  }
  const store = storeFace(chatStoreId!)
  return { ...seed, title: `${SARA.fullName} · ${store.storeName}`, store, customer: { id: SARA.id, fullName: SARA.fullName } }
}

function close(item: ReportedItem, to: 'DISMISSED' | 'ACTIONED'): Promise<ReportedItem> {
  return reply(() => {
    const seed = seeds().find((s) => s.type === item.type && s.targetId === item.targetId)
    if (!seed) throw new ApiError('NOT_FOUND')
    if (seed.status !== 'OPEN') throw new ApiError('WRONG_STATE')
    seed.status = to
    for (const report of seed.reports) if (report.status === 'OPEN') report.status = to
    return face(seed)
  })
}
