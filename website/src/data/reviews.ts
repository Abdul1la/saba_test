import { http, httpPage, USE_MOCK } from './http'
import { ApiError, countBy, daysAgo, pageOf, reply } from './mock'
import type { ListResult, PageAsk, Paged } from './types'

// Reviews shoppers reported from the app (API_CONTRACT.md §3.12). A report
// always reaches someone: Saba removes the review or dismisses its reports.

export type ReviewReportStatus = 'OPEN' | 'DISMISSED' | 'REMOVED'
export type ReportReason = 'COUNTERFEIT' | 'PROHIBITED' | 'MISLEADING' | 'OFFENSIVE' | 'SPAM' | 'OTHER'

export interface ReviewReport {
  id: string
  reason: ReportReason
  /** The reporter's own words. */
  description?: string
  /** Left out for a deleted account. */
  reporterName?: string
  /** A store may report a review too; left out where the server doesn't say. */
  reporterRole?: 'CUSTOMER' | 'MERCHANT'
  createdAt: string
  status: ReviewReportStatus
}

export interface ReportedReview {
  /** The review's id. */
  id: string
  /** REMOVED once removed; OPEN while a report waits; else DISMISSED. */
  status: ReviewReportStatus
  store: { id: string; storeName: string }
  rating: number
  body?: string
  /** Left out for a deleted account. */
  authorName?: string
  createdAt: string
  removedAt?: string
  lastReportedAt: string
  /** Newest first. */
  reports: ReviewReport[]
}

// web-only demo: one review waiting for an answer, one whose reports were dismissed.
const REVIEWS: ReportedReview[] = [
  {
    id: 'rv-1',
    status: 'OPEN',
    store: { id: 'm-1', storeName: 'Nova Electronics' },
    rating: 1,
    body: 'Fake charger, do not buy from them. Call me on 0770 000 0000 for a better price.',
    authorName: 'Ahmed Karim',
    createdAt: daysAgo(3),
    lastReportedAt: daysAgo(0, 5),
    reports: [
      { id: 'rr-2', reason: 'SPAM', description: 'It advertises a phone number.', reporterName: 'Sara Ahmed', createdAt: daysAgo(0, 5), status: 'OPEN' },
      { id: 'rr-1', reason: 'MISLEADING', reporterName: 'Omar Farouk', createdAt: daysAgo(1), status: 'OPEN' },
    ],
  },
  {
    id: 'rv-2',
    status: 'DISMISSED',
    store: { id: 'm-2', storeName: 'Atlas Home' },
    rating: 2,
    body: 'The blender is louder than I expected.',
    createdAt: daysAgo(12),
    lastReportedAt: daysAgo(9),
    reports: [{ id: 'rr-3', reason: 'OFFENSIVE', reporterName: 'Noor Hadi', createdAt: daysAgo(9), status: 'DISMISSED' }],
  },
]

/** GET /admin/review-reports?status=&page= : one page, the latest report first; the counts ignore `status`. */
export function listReviewReports(query: { status?: ReviewReportStatus } & PageAsk): Promise<Paged<ListResult<ReportedReview, ReviewReportStatus>>> {
  if (!USE_MOCK) return httpPage('/admin/review-reports', { status: query.status }, query)
  return reply(() => ({
    ...pageOf(
      REVIEWS.filter((r) => !query.status || r.status === query.status).sort((a, b) => b.lastReportedAt.localeCompare(a.lastReportedAt)),
      query,
    ),
    counts: countBy(REVIEWS, (r) => [r.status]),
  }))
}

/** POST /admin/review-reports/{id}/remove: it leaves the store's page and rating; its open reports close as REMOVED. */
export function removeReview(id: string): Promise<ReportedReview> {
  if (!USE_MOCK) return http('POST', reviewPath(id, 'remove'))
  return change(id, (r) => r.status !== 'REMOVED', 'REMOVED')
}

/** POST /admin/review-reports/{id}/dismiss: the review stays; its open reports close as DISMISSED. */
export function dismissReviewReports(id: string): Promise<ReportedReview> {
  if (!USE_MOCK) return http('POST', reviewPath(id, 'dismiss'))
  return change(id, (r) => r.status === 'OPEN', 'DISMISSED')
}

const reviewPath = (id: string, action: string) => `/admin/review-reports/${encodeURIComponent(id)}/${action}`

function change(id: string, allowed: (r: ReportedReview) => boolean, to: 'REMOVED' | 'DISMISSED'): Promise<ReportedReview> {
  return reply(() => {
    const review = REVIEWS.find((r) => r.id === id)
    if (!review) throw new ApiError('NOT_FOUND')
    if (!allowed(review)) throw new ApiError('WRONG_STATE')
    review.status = to
    if (to === 'REMOVED') review.removedAt = new Date().toISOString()
    for (const report of review.reports) if (report.status === 'OPEN') report.status = to
    return review
  })
}
