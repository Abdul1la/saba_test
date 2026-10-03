import { CircleCheck, Hourglass, TrendingUp, Wallet } from 'lucide-react'
import {
  ContentCard,
  DetailsButton,
  DetailsHead,
  EmptyState,
  ErrorState,
  FilterChips,
  NameCell,
  PageIntro,
  StatCard,
  StatRow,
  TableSkeleton,
  Thumb,
  card,
  pillSelect,
  row,
  showList,
  td,
  th,
} from '@/components/blocks'
import { BillBadge } from '@/components/finance-sheet'
import { Button } from '@/components/ui/button'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { getFinance, RATE_PERCENT, type PaidFilter } from '@/data/finance'
import { money, monthName, number } from '@/lib/format'
import { useI18n } from '@/lib/i18n'
import { useSheet, useUrlFilters } from '@/lib/url-state'
import { useQuery } from '@/lib/use-query'
import { cn } from '@/lib/utils'

const PAID_FILTERS: PaidFilter[] = ['PAID', 'DUE']

/** "2026-08" for `back` months before this one. */
function monthBack(back: number) {
  const at = new Date()
  const d = new Date(at.getFullYear(), at.getMonth() - back, 1)
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`
}

// Any of the last two years may sit in the address; the list offers the ones with sales.
const KNOWN_MONTHS = ['past', ...Array.from({ length: 24 }, (_, i) => monthBack(i))]

/** A sum of money on a stat card: smaller than a count, so a long one fits. */
function Amount({ value, lang }: { value: number; lang: 'en' | 'ar' }) {
  const [digits, ...unit] = money(value, lang).split(' ')
  return (
    <span className="text-[26px] sm:text-[32px]">
      {digits}
      <span className="ms-1.5 font-sans text-sm text-muted-foreground">{unit.join(' ')}</span>
    </span>
  )
}

export function FinancePage() {
  const { t, lang, city } = useI18n()
  const sheet = useSheet()
  const [filters, setFilters] = useUrlFilters({ month: KNOWN_MONTHS, paid: PAID_FILTERS })
  // Last month by default: the bill that is due now.
  const month = filters.month || monthBack(1)
  const paid = filters.paid as PaidFilter | ''
  const finance = useQuery(() => getFinance({ month, paid: paid || undefined }), `finance:${month}:${paid}`)
  const data = finance.data
  const current = monthBack(0)
  const last = monthBack(1)
  const amount = (n?: number) => (finance.error ? '—' : n === undefined ? undefined : <Amount value={n} lang={lang} />)
  const fromCard = (next: string, nextPaid: PaidFilter | '') => () => {
    setFilters({ month: next, paid: nextPaid })
    showList()
  }
  const rate = data?.ratePercent ?? RATE_PERCENT

  return (
    <>
      <PageIntro>{t.finance.intro(rate)}</PageIntro>
      <StatRow>
        <StatCard
          label={t.finance.soFarSales}
          value={amount(data?.thisMonth.sales)}
          icon={TrendingUp}
          onClick={fromCard(current, '')}
          active={month === current && !paid}
        />
        <StatCard
          label={t.finance.soFarOwed(rate)}
          value={amount(data?.thisMonth.owed)}
          icon={Hourglass}
          onClick={fromCard(current, '')}
          active={month === current && !paid}
        />
        <StatCard
          label={t.finance.lastCollected(monthName(last, lang))}
          value={amount(data?.lastMonth.collected)}
          icon={CircleCheck}
          onClick={fromCard(last, 'PAID')}
          active={month === last && paid === 'PAID'}
        />
        <StatCard
          label={t.finance.lastOwed(monthName(last, lang))}
          value={amount(data?.lastMonth.stillOwed)}
          icon={Wallet}
          onClick={fromCard(last, 'DUE')}
          active={month === last && paid === 'DUE'}
        />
      </StatRow>

      <ContentCard id="list" icon={Wallet} title={t.finance.cardTitle} description={t.finance.cardText}>
        <div className="flex flex-wrap items-center justify-between gap-3">
          <FilterChips
            label={t.finance.payment}
            value={paid}
            onChange={(next) => setFilters({ paid: next })}
            chips={[
              { value: '', label: t.all, count: data?.counts.all },
              { value: 'DUE', label: t.finance.status.DUE, count: data?.counts.DUE },
              { value: 'PAID', label: t.finance.status.PAID, count: data?.counts.PAID },
            ]}
          />
          <Select value={month} onValueChange={(next) => setFilters({ month: next })}>
            <SelectTrigger aria-label={t.finance.month} className={cn(pillSelect, 'border-primary text-primary')}>
              <span className="text-muted-foreground">{t.finance.month}:</span>
              <SelectValue />
            </SelectTrigger>
            <SelectContent position="popper" align="end" className="rounded-xl">
              {(data?.months ?? [current, last]).map((m) => (
                <SelectItem key={m} value={m}>
                  {monthName(m, lang)}
                  {m === current && <span className="text-faint">· {t.finance.soFar}</span>}
                </SelectItem>
              ))}
              {/* An address may name a month the list no longer offers. */}
              {data && month !== 'past' && !data.months.includes(month) && <SelectItem value={month}>{monthName(month, lang)}</SelectItem>}
              <SelectItem value="past">{t.finance.past}</SelectItem>
            </SelectContent>
          </Select>
        </div>

        {data && !finance.error && (
          <dl className="mt-5 grid gap-2 rounded-2xl bg-soft px-5 py-4 sm:grid-cols-3 sm:gap-3">
            {[
              [t.finance.total, data.totals.owed],
              [t.finance.paid, data.totals.paid],
              [t.finance.stillOwed, data.totals.stillOwed],
            ].map(([label, value]) => (
              // A line each on a phone, three columns from sm up.
              <div key={String(label)} className="flex min-w-0 items-baseline justify-between gap-3 sm:block">
                <dt className="truncate text-[13px] text-muted-foreground">{label}</dt>
                <dd className="truncate text-[15px] font-semibold text-navy tabular-nums sm:mt-0.5 sm:text-[17px]">{money(Number(value), lang)}</dd>
              </div>
            ))}
          </dl>
        )}

        <div className="mt-6">
          {finance.error ? (
            <ErrorState error={finance.error} onRetry={finance.retry} />
          ) : !data ? (
            <TableSkeleton columns={6} />
          ) : data.rows.length === 0 ? (
            <EmptyState
              icon={Wallet}
              title={t.empty.search}
              text={t.empty.searchText}
              action={
                paid && (
                  <Button variant="outline" className="h-10 rounded-full px-5" onClick={() => setFilters({ paid: '' })}>
                    {t.clearFilters}
                  </Button>
                )
              }
            />
          ) : (
            <Table className={cn('transition-opacity', card.table, finance.loading && 'opacity-60')}>
              <TableHeader>
                <TableRow className="border-border hover:bg-transparent">
                  <TableHead className={th}>{t.col.store}</TableHead>
                  <TableHead className={cn(th, 'text-end')}>{t.finance.sales}</TableHead>
                  <TableHead className={cn(th, 'text-end')}>{t.finance.commission(rate)}</TableHead>
                  <TableHead className={cn(th, 'text-end')}>{t.finance.paid}</TableHead>
                  <TableHead className={cn(th, 'text-end')}>{t.finance.stillOwed}</TableHead>
                  <TableHead className={th}>{t.col.status}</TableHead>
                  <DetailsHead />
                </TableRow>
              </TableHeader>
              <TableBody>
                {data.rows.map((r) => {
                  const open = () => sheet.open('bills', r.store.id)
                  // On a narrow card one figure stays: what is still owed, or this month's building share.
                  const key = r.status === 'OPEN' ? r.owed : r.stillOwed
                  return (
                    <TableRow key={r.store.id} className={row} onClick={open}>
                      <TableCell className={cn(td, 'max-w-[320px]')}>
                        <NameCell
                          thumb={<Thumb src={r.store.logoUrl} name={r.store.storeName} round />}
                          title={r.store.storeName}
                          subtitle={`${city(r.store.governorate)} · ${t.finance.orders(r.orderCount)}${r.store.status === 'APPROVED' ? '' : ` · ${t.storeStatus[r.store.status]}`}`}
                        />
                      </TableCell>
                      <TableCell className={cn(td, card.hide, 'text-end tabular-nums')}>
                        <div className="text-[15px] text-navy">{money(r.sales, lang)}</div>
                        {r.returned > 0 && <div className="text-[13px] text-muted-foreground">{t.finance.refunded(number(r.returned))}</div>}
                      </TableCell>
                      <TableCell className={cn(td, card.hide, 'text-end text-[15px] font-medium text-navy tabular-nums')}>{money(r.owed, lang)}</TableCell>
                      <TableCell className={cn(td, card.hide, 'text-end text-[15px] text-ok tabular-nums')}>{r.paid ? money(r.paid, lang) : '—'}</TableCell>
                      <TableCell
                        className={cn(td, card.line, 'text-end text-[15px] font-semibold tabular-nums', r.stillOwed > 0 ? 'text-wait' : 'text-navy')}
                      >
                        <span className="hidden font-normal text-muted-foreground @max-3xl:inline">
                          {r.status === 'OPEN' ? t.finance.commission(rate) : t.finance.stillOwed}:{' '}
                        </span>
                        <span className="@max-3xl:hidden">{r.stillOwed ? money(r.stillOwed, lang) : '—'}</span>
                        <span className="hidden @max-3xl:inline">{money(key, lang)}</span>
                      </TableCell>
                      <TableCell className={td}>
                        <BillBadge status={r.status} />
                      </TableCell>
                      <TableCell className={cn(td, card.end, 'text-end')}>
                        <DetailsButton onClick={open} />
                      </TableCell>
                    </TableRow>
                  )
                })}
              </TableBody>
            </Table>
          )}
        </div>
      </ContentCard>
    </>
  )
}
