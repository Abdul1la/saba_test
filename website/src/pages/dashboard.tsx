import { Link } from 'react-router'
import { ArrowRight, ChartPie, ChevronRight, ClipboardCheck, Hourglass, Package, PackageCheck, ReceiptText, Store } from 'lucide-react'
import { ContentCard, EmptyState, ErrorState, ORDER_TONE, PageIntro, StatCard, StatRow, TableSkeleton, Thumb, toneClass } from '@/components/blocks'
import { Skeleton } from '@/components/ui/skeleton'
import { getDashboard, type Dashboard } from '@/data/dashboard'
import type { OrderStatus } from '@/data/types'
import { ago, isLate, number } from '@/lib/format'
import { useI18n } from '@/lib/i18n'
import { useSheet } from '@/lib/url-state'
import { useQuery } from '@/lib/use-query'
import { cn } from '@/lib/utils'
import { ORDER_STATUSES, OrdersTable } from './orders'

/** The main road is always listed; the side roads only when an order took one. */
const ALWAYS: OrderStatus[] = ['PENDING', 'CONFIRMED', 'PROCESSING', 'SHIPPED', 'DELIVERED', 'CANCELLED']

const rowLink = 'rounded-xl transition outline-none hover:bg-soft focus-visible:ring-4 focus-visible:ring-primary/20'

export function DashboardPage() {
  const { t } = useI18n()
  const d = useQuery(getDashboard, 'dashboard')
  const data = d.data
  const stat = (n?: number) => (d.error ? '—' : n)

  return (
    <>
      <PageIntro>{t.dash.intro}</PageIntro>
      <StatRow>
        <StatCard label={t.dash.storesWaiting} value={stat(data?.storesWaiting)} icon={Hourglass} to="/stores?status=PENDING" />
        <StatCard label={t.dash.productsWaiting} value={stat(data?.productsWaiting)} icon={ClipboardCheck} to="/products?status=PENDING" />
        <StatCard label={t.dash.stores} value={stat(data?.stores)} icon={Store} to="/stores" />
        <StatCard label={t.dash.products} value={stat(data?.products)} icon={Package} to="/products" />
      </StatRow>

      {d.error ? (
        <ContentCard icon={ChartPie} title={t.dash.byStatus}>
          <ErrorState error={d.error} onRetry={d.retry} />
        </ContentCard>
      ) : (
        <div className="space-y-6">
          <div className="grid gap-6 xl:grid-cols-5">
            <ContentCard icon={ChartPie} title={t.dash.byStatus} description={t.dash.byStatusText} className="xl:col-span-3">
              {data ? <ByStatus data={data} /> : <ByStatusSkeleton />}
            </ContentCard>
            <ContentCard icon={Hourglass} title={t.dash.waiting} description={t.dash.waitingText} className="xl:col-span-2">
              {data ? <WaitingLongest data={data} /> : <ByStatusSkeleton rows={4} />}
            </ContentCard>
          </div>

          <ContentCard
            icon={ReceiptText}
            title={t.dash.recent}
            description={t.dash.recentText}
            actions={
              <Link to="/orders" className="inline-flex h-10 items-center gap-1.5 rounded-full border border-border px-4 text-sm font-medium text-navy transition hover:bg-soft">
                {t.seeAll}
                <ArrowRight className="size-4 rtl:rotate-180" />
              </Link>
            }
          >
            {data ? <OrdersTable orders={data.recentOrders} dim={d.loading} /> : <TableSkeleton rows={5} columns={4} />}
          </ContentCard>
        </div>
      )}
    </>
  )
}

function ByStatus({ data }: { data: Dashboard }) {
  const { t } = useI18n()
  const statuses = ORDER_STATUSES.filter((s) => ALWAYS.includes(s) || (data.ordersByStatus[s] ?? 0) > 0)
  return (
    <div>
      <ul className="-mx-2 space-y-1">
        {statuses.map((s) => {
          const count = data.ordersByStatus[s] ?? 0
          const tone = toneClass(ORDER_TONE[s])
          return (
            <li key={s}>
              {/* Opens the orders in that status, as the cards above open theirs. */}
              <Link to={`/orders?status=${s}`} className={cn(rowLink, 'block px-2 py-2')}>
                <span className="flex items-center gap-2.5 text-[15px]">
                  <span className={cn('size-2.5 rounded-full', tone.dot)} />
                  <span className="font-medium text-navy">{t.orderStatus[s]}</span>
                  <span className="ms-auto font-semibold text-navy tabular-nums">{number(count)}</span>
                  <ChevronRight className="size-4 text-faint rtl:rotate-180" />
                </span>
                <span className="mt-2 block h-1.5 overflow-hidden rounded-full bg-soft">
                  <span
                    className={cn('block h-full rounded-full transition-[width] duration-700', tone.bar)}
                    style={{ width: data.orders ? `${(count / data.orders) * 100}%` : 0 }}
                  />
                </span>
              </Link>
            </li>
          )
        })}
      </ul>
      <Link to="/orders" className={cn(rowLink, 'mt-5 flex items-center gap-3 rounded-2xl border border-border bg-soft px-5 py-4 hover:bg-white')}>
        <ReceiptText className="size-5 text-muted-foreground" strokeWidth={1.75} />
        <span className="text-[15px] text-navy">{t.dash.totalOrders}</span>
        <span className="ms-auto font-num text-[28px] leading-none text-navy tabular-nums">{number(data.orders)}</span>
        <ChevronRight className="size-4 text-faint rtl:rotate-180" />
      </Link>
    </div>
  )
}

function ByStatusSkeleton({ rows = 6 }: { rows?: number }) {
  return (
    <div className="space-y-5">
      {Array.from({ length: rows }, (_, i) => (
        <div key={i} className="space-y-2">
          <div className="flex justify-between">
            <Skeleton className="h-3.5 w-28 rounded" />
            <Skeleton className="h-3.5 w-6 rounded" />
          </div>
          <Skeleton className="h-1.5 w-full rounded-full" />
        </div>
      ))}
    </div>
  )
}

function WaitingLongest({ data }: { data: Dashboard }) {
  const { t, lang, pick } = useI18n()
  const sheet = useSheet()
  if (data.waitingLongest.length === 0) {
    return <EmptyState icon={PackageCheck} title={t.dash.allAnswered} text={t.dash.allAnsweredText} />
  }
  return (
    <div>
      <ul className="-mx-2 space-y-1">
        {data.waitingLongest.map((w) => {
          const name = pick(w.name, w.nameAr)
          return (
            <li key={`${w.kind}:${w.id}`}>
              <button
                type="button"
                onClick={() => sheet.open(w.kind, w.id)}
                className="flex w-full items-center gap-3.5 rounded-xl px-2 py-2.5 text-start transition hover:bg-soft"
              >
                <Thumb src={w.imageUrl} name={name} round={w.kind === 'store'} />
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-[15px] font-medium text-navy">{name}</span>
                  <span className="block truncate text-[13px] text-muted-foreground">
                    {w.kind === 'store' ? t.dash.kindStore : t.dash.kindProduct} · {w.owner}
                  </span>
                </span>
                <span className={cn('shrink-0 text-[13px] font-medium', isLate(w.since) ? 'text-wait' : 'text-muted-foreground')}>
                  {ago(w.since, lang)}
                </span>
              </button>
            </li>
          )
        })}
      </ul>
      <Link
        to="/queue"
        className="mt-5 flex h-11 items-center justify-center gap-2 rounded-xl bg-primary text-[15px] font-medium text-white shadow-[0_8px_20px_-10px_color-mix(in_srgb,var(--primary)_80%,transparent)] transition hover:bg-primary-pressed"
      >
        {t.dash.openQueue}
        <ArrowRight className="size-4 rtl:rotate-180" />
      </Link>
    </div>
  )
}
