import { Ban, Coins, RotateCcw, Undo2 } from 'lucide-react'
import {
  ContentCard,
  DetailsButton,
  DetailsHead,
  EmptyState,
  ErrorState,
  FilterChips,
  NameCell,
  PageIntro,
  Pager,
  StatCard,
  StatRow,
  StatusBadge,
  TableSkeleton,
  Thumb,
  card,
  pillSelect,
  row,
  showList,
  td,
  th,
  usePage,
} from '@/components/blocks'
import { Button } from '@/components/ui/button'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { listAfterSales, type AfterSaleKind } from '@/data/returns'
import { ago, date, money } from '@/lib/format'
import { useI18n } from '@/lib/i18n'
import { useSheet, useUrlFilters } from '@/lib/url-state'
import { useQuery } from '@/lib/use-query'
import { cn } from '@/lib/utils'

const KINDS: AfterSaleKind[] = ['CANCELLED', 'RETURNED']
const PERIODS = ['7', '30', '90'] as const
const ALL = 'all'

export function ReturnsPage() {
  const { t, lang, pick } = useI18n()
  const sheet = useSheet()
  const [filters, setFilters] = useUrlFilters({ kind: KINDS, days: PERIODS })
  const kind = filters.kind as AfterSaleKind | ''
  const days = filters.days
  // The cards read the counts and value, which are the whole period's on every page.
  const [page, setPage] = usePage(`${kind}:${days}`)
  const list = useQuery(
    () => listAfterSales({ kind: kind || undefined, days: days ? Number(days) : undefined, page }),
    `after:${kind}:${days}:${page}`,
  )
  const data = list.data
  const stat = (n?: number) => (list.error ? '—' : n)
  /** A card shows what it counted: its kind, in the period chosen. */
  const fromCard = (next: AfterSaleKind | '') => () => {
    setFilters({ kind: next })
    showList()
  }
  const [digits, ...unit] = data ? money(data.value, lang).split(' ') : []

  return (
    <>
      <PageIntro>{t.after.intro}</PageIntro>
      <StatRow>
        <StatCard label={t.after.cancelled} value={stat(data?.counts.CANCELLED)} icon={Ban} onClick={fromCard('CANCELLED')} active={kind === 'CANCELLED'} />
        <StatCard label={t.after.returned} value={stat(data?.counts.RETURNED)} icon={RotateCcw} onClick={fromCard('RETURNED')} active={kind === 'RETURNED'} />
        <StatCard
          label={t.after.value}
          value={
            list.error
              ? '—'
              : data && (
                  <span className="text-[26px] sm:text-[32px]">
                    {digits}
                    <span className="ms-1.5 font-sans text-sm text-muted-foreground">{unit.join(' ')}</span>
                  </span>
                )
          }
          icon={Coins}
          onClick={fromCard('')}
          active={!kind}
        />
        <StatCard label={t.after.openReturns} value={stat(data?.counts.openReturns)} icon={Undo2} onClick={fromCard('RETURNED')} />
      </StatRow>

      <ContentCard id="list" icon={RotateCcw} title={t.after.cardTitle} description={t.after.cardText}>
        <div className="flex flex-wrap items-center justify-between gap-3">
          <FilterChips
            label={t.after.col.what}
            value={kind}
            onChange={(next) => setFilters({ kind: next })}
            chips={[
              { value: '', label: t.all, count: data?.counts.all },
              { value: 'CANCELLED', label: t.after.cancelled, count: data?.counts.CANCELLED },
              { value: 'RETURNED', label: t.after.returned, count: data?.counts.RETURNED },
            ]}
          />
          <Select value={days || ALL} onValueChange={(next) => setFilters({ days: next === ALL ? '' : next })}>
            <SelectTrigger aria-label={t.after.period} className={cn(pillSelect, days && 'border-primary text-primary')}>
              <span className="text-muted-foreground">{t.after.period}:</span>
              <SelectValue />
            </SelectTrigger>
            <SelectContent position="popper" align="end" className="rounded-xl">
              {[ALL, ...PERIODS].map((p) => (
                <SelectItem key={p} value={p}>
                  {t.after.periods[p]}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>

        <div className="mt-6">
          {list.error ? (
            <ErrorState error={list.error} onRetry={list.retry} />
          ) : !data ? (
            <TableSkeleton columns={5} />
          ) : data.items.length === 0 ? (
            <EmptyState
              icon={RotateCcw}
              title={t.empty.search}
              text={t.empty.searchText}
              action={
                (kind || days) && (
                  <Button variant="outline" className="h-10 rounded-full px-5" onClick={() => setFilters({ kind: '', days: '' })}>
                    {t.clearFilters}
                  </Button>
                )
              }
            />
          ) : (
            <Table className={cn('transition-opacity', card.table, list.loading && 'opacity-60')}>
              <TableHeader>
                <TableRow className="border-border hover:bg-transparent">
                  <TableHead className={th}>{t.after.col.item}</TableHead>
                  {/* Only where there is room: the buyer is one click away, on the order. */}
                  <TableHead className={cn(th, '@max-5xl:hidden')}>{t.after.col.buyer}</TableHead>
                  <TableHead className={th}>{t.after.col.reason}</TableHead>
                  <TableHead className={cn(th, 'text-end')}>{t.after.col.value}</TableHead>
                  <TableHead className={th}>{t.after.col.what}</TableHead>
                  <DetailsHead />
                </TableRow>
              </TableHeader>
              <TableBody>
                {data.items.map((a) => {
                  // A cancellation is its order; a return has its own sheet.
                  const open = () => (a.kind === 'CANCELLED' ? sheet.open('order', a.orderId) : sheet.open('return', a.id))
                  return (
                    <TableRow key={`${a.kind}:${a.id}`} className={row} onClick={open}>
                      <TableCell className={td}>
                        <div className="max-w-[240px] 2xl:max-w-[320px]">
                          <NameCell
                            thumb={<Thumb src={a.item.imageUrl} name={a.item.productName} />}
                            title={pick(a.item.productName, a.item.productNameAr)}
                            subtitle={
                              <>
                                <span dir="ltr">{a.orderNumber}</span> · <bdi>{a.storeName}</bdi>
                                {a.more > 0 && <span className="text-faint"> · {t.more(a.more)}</span>}
                              </>
                            }
                          />
                        </div>
                      </TableCell>
                      <TableCell className={cn(td, '@max-5xl:hidden', 'text-[15px] text-navy')}>
                        <bdi>{a.buyer}</bdi>
                      </TableCell>
                      <TableCell className={cn(td, card.line)}>
                        <div className="max-w-[210px] truncate text-[15px] text-navy @max-3xl:max-w-none">{t.after.reason[a.reason] ?? a.reason}</div>
                        <div className="text-[13px] text-muted-foreground">
                          {a.kind === 'CANCELLED' ? t.after.by[a.by] : t.after.returnStatus[a.returnStatus!]}
                          <span className="hidden tabular-nums @max-3xl:inline"> · {money(a.value, lang)}</span>
                        </div>
                      </TableCell>
                      <TableCell className={cn(td, card.hide, 'text-end text-[15px] font-medium text-navy tabular-nums')}>{money(a.value, lang)}</TableCell>
                      <TableCell className={td}>
                        <StatusBadge tone={a.kind === 'CANCELLED' ? 'bad' : 'off'}>{a.kind === 'CANCELLED' ? t.after.cancelled : t.after.returned}</StatusBadge>
                        <div className="mt-1 text-[13px] text-muted-foreground" title={ago(a.at, lang)}>
                          {date(a.at, lang)}
                        </div>
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
