import { Flag, Star, Store } from 'lucide-react'
import { ReviewActions } from '@/components/actions'
import { ContentCard, EmptyState, ErrorState, FilterChips, PageIntro, Pager, StatusBadge, TableSkeleton, showList, usePage, type Tone } from '@/components/blocks'
import { Button } from '@/components/ui/button'
import { listReviewReports, type ReportedReview, type ReviewReportStatus } from '@/data/reviews'
import { ago, date } from '@/lib/format'
import { useI18n } from '@/lib/i18n'
import { useSheet, useUrlFilters } from '@/lib/url-state'
import { useQuery } from '@/lib/use-query'
import { cn } from '@/lib/utils'

const STATUSES: ReviewReportStatus[] = ['OPEN', 'DISMISSED', 'REMOVED']
const TONE: Record<ReviewReportStatus, Tone> = { OPEN: 'wait', DISMISSED: 'off', REMOVED: 'bad' }

export function ReviewsPage() {
  const { t } = useI18n()
  const [filters, setFilters] = useUrlFilters({ status: STATUSES })
  const status = filters.status as ReviewReportStatus | ''
  const [page, setPage] = usePage(status)
  const list = useQuery(() => listReviewReports({ status: status || undefined, page }), `reviews:${status}:${page}`)

  return (
    <>
      <PageIntro>{t.reported.intro}</PageIntro>
      <ContentCard id="list" icon={Flag} title={t.reported.cardTitle} description={t.reported.cardText}>
        <FilterChips
          label={t.col.status}
          value={status}
          onChange={(next) => setFilters({ status: next })}
          chips={[
            { value: '', label: t.all, count: list.data?.counts.all },
            ...STATUSES.map((s) => ({ value: s, label: t.reported.status[s], count: list.data && (list.data.counts[s] ?? 0) })),
          ]}
        />

        <div className="mt-6">
          {list.error ? (
            <ErrorState error={list.error} onRetry={list.retry} />
          ) : !list.data ? (
            <TableSkeleton columns={3} />
          ) : list.data.items.length === 0 ? (
            <EmptyState
              icon={Flag}
              title={status ? t.empty.search : t.reported.none}
              text={status ? t.empty.searchText : t.reported.noneText}
              action={
                status && (
                  <Button variant="outline" className="h-10 rounded-full px-5" onClick={() => setFilters({ status: '' })}>
                    {t.clearFilters}
                  </Button>
                )
              }
            />
          ) : (
            <ul className={cn('space-y-4 transition-opacity', list.loading && 'opacity-60')}>
              {list.data.items.map((review) => (
                <ReviewCard key={review.id} review={review} />
              ))}
            </ul>
          )}
        </div>
        <Pager
          meta={list.data?.meta}
          busy={list.loading}
          onPage={(next) => {
            setPage(next)
            showList()
          }}
        />
      </ContentCard>
    </>
  )
}

function ReviewCard({ review: r }: { review: ReportedReview }) {
  const { t, lang } = useI18n()
  const sheet = useSheet()
  return (
    <li className="rounded-2xl border border-border bg-white p-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <button
            type="button"
            onClick={() => sheet.open('store', r.store.id)}
            className="inline-flex items-center gap-1.5 text-[15px] font-medium text-navy hover:underline"
          >
            <Store className="size-4 text-faint" />
            <bdi>{r.store.storeName}</bdi>
          </button>
          <div className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1 text-[13px] text-muted-foreground">
            <Stars rating={r.rating} />
            <span>
              <bdi>{r.authorName ?? t.reported.deletedAccount}</bdi> · {date(r.createdAt, lang)}
            </span>
          </div>
        </div>
        <StatusBadge tone={TONE[r.status]}>{t.reported.status[r.status]}</StatusBadge>
      </div>

      {r.body ? (
        <p dir="auto" className="mt-3 text-[15px] leading-relaxed text-navy">
          {r.body}
        </p>
      ) : (
        <p className="mt-3 text-[14px] text-muted-foreground">{t.reported.noWords}</p>
      )}

      <div className="mt-4 rounded-xl bg-soft px-4 py-3">
        <p className="mb-2 text-[13px] font-semibold text-navy">{t.reported.reports(r.reports.length)}</p>
        <ul className="space-y-3">
          {r.reports.map((report) => (
            <li key={report.id} className="text-[14px]">
              <p className="font-medium text-navy">
                {t.reported.reason[report.reason]}
                {report.status !== 'OPEN' && <span className="font-normal text-muted-foreground"> · {t.reported.status[report.status]}</span>}
              </p>
              {report.description && (
                <p dir="auto" className="text-navy">
                  {report.description}
                </p>
              )}
              <p className="text-[13px] text-muted-foreground">
                <bdi>{report.reporterName ?? t.reported.deletedAccount}</bdi>
                {report.reporterRole && <> · {t.reports.role[report.reporterRole]}</>} · {ago(report.createdAt, lang)}
              </p>
            </li>
          ))}
        </ul>
      </div>

      {r.status === 'OPEN' && (
        <div className="mt-4">
          <ReviewActions review={r} />
        </div>
      )}
    </li>
  )
}

function Stars({ rating }: { rating: number }) {
  const { t } = useI18n()
  return (
    <span role="img" aria-label={t.reported.stars(rating)} className="inline-flex gap-0.5">
      {[1, 2, 3, 4, 5].map((n) => (
        <Star key={n} className={cn('size-3.5', n <= rating ? 'fill-heat text-heat' : 'text-border-strong')} strokeWidth={1.75} />
      ))}
    </span>
  )
}
