import { useState } from 'react'
import { Ban, BadgeCheck, DoorClosed, Hourglass, Store } from 'lucide-react'
import {
  ContentCard,
  DetailsButton,
  DetailsHead,
  EmptyState,
  ErrorState,
  FilterChips,
  Ltr,
  NameCell,
  PageIntro,
  Pager,
  SearchBar,
  StatCard,
  StatRow,
  StoreBadge,
  TableSkeleton,
  Thumb,
  card,
  row,
  showList,
  td,
  th,
  usePage,
} from '@/components/blocks'
import { Button } from '@/components/ui/button'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { listStores } from '@/data/stores'
import type { StoreStatus } from '@/data/types'
import { date, number, phone } from '@/lib/format'
import { useI18n } from '@/lib/i18n'
import { useSheet, useUrlFilters } from '@/lib/url-state'
import { useDebounced, useQuery } from '@/lib/use-query'
import { cn } from '@/lib/utils'

const FILTERS: StoreStatus[] = ['PENDING', 'APPROVED', 'REJECTED', 'SUSPENDED', 'CLOSED']

export function StoresPage() {
  const { t, lang, city } = useI18n()
  const sheet = useSheet()
  const [q, setQ] = useState('')
  const [filters, setFilters] = useUrlFilters({ status: FILTERS, number: ['unchecked'] })
  const status = filters.status as StoreStatus | ''
  // Only owners' numbers never checked (signed up while SMS codes were off).
  const unchecked = filters.number === 'unchecked'
  const setStatus = (next: StoreStatus | '') => setFilters({ status: next })
  const search = useDebounced(q)
  // The cards count the whole list; the counts are the same on every page, so one row is enough.
  const all = useQuery(() => listStores({ page: 1, perPage: 1 }), 'stores:all')
  const [page, setPage] = usePage(`${search}:${status}:${unchecked}`)
  const list = useQuery(
    () => listStores({ q: search, status: status || undefined, phoneVerified: unchecked ? false : undefined, page }),
    `stores:${search}:${status}:${unchecked}:${page}`,
  )
  const uncheckedCount = useQuery(() => listStores({ q: search, phoneVerified: false, page: 1, perPage: 1 }), `stores:unchecked:${search}`)
  const counts = all.data?.counts
  // A failed load says so; a skeleton that never ends says nothing.
  const stat = (n?: number) => (all.error ? '—' : n)
  const filtered = !!(q || status)
  /** A card shows exactly what it counted: its status, and no search. */
  const fromCard = (next: StoreStatus | '') => () => {
    setQ('')
    setStatus(next)
    showList()
  }

  return (
    <>
      <PageIntro>{t.stores.intro}</PageIntro>
      {/* Five cards: on a phone the total takes a whole row, so the four statuses pair up below it. */}
      <StatRow className="xl:grid-cols-5 [&>:first-child]:col-span-2 xl:[&>:first-child]:col-span-1">
        <StatCard label={t.stores.total} value={stat(counts?.all)} icon={Store} onClick={fromCard('')} active={!status} />
        <StatCard
          label={t.stores.approved}
          value={stat(counts && (counts.APPROVED ?? 0))}
          icon={BadgeCheck}
          onClick={fromCard('APPROVED')}
          active={status === 'APPROVED'}
        />
        <StatCard
          label={t.stores.waiting}
          value={stat(counts && (counts.PENDING ?? 0))}
          icon={Hourglass}
          onClick={fromCard('PENDING')}
          active={status === 'PENDING'}
        />
        <StatCard
          label={t.stores.suspended}
          value={stat(counts && (counts.SUSPENDED ?? 0))}
          icon={Ban}
          onClick={fromCard('SUSPENDED')}
          active={status === 'SUSPENDED'}
        />
        <StatCard
          label={t.stores.closed}
          value={stat(counts && (counts.CLOSED ?? 0))}
          icon={DoorClosed}
          onClick={fromCard('CLOSED')}
          active={status === 'CLOSED'}
        />
      </StatRow>

      <ContentCard id="list" icon={Store} title={t.stores.cardTitle} description={t.stores.cardText}>
        <div className="space-y-4">
          <SearchBar value={q} onChange={setQ} placeholder={t.stores.search} />
          <FilterChips
            label={t.col.status}
            value={status}
            onChange={setStatus}
            chips={[
              { value: '', label: t.all, count: list.data?.counts.all },
              ...FILTERS.map((s) => ({ value: s, label: t.storeStatus[s], count: list.data && (list.data.counts[s] ?? 0) })),
            ]}
          />
          <FilterChips
            label={t.number.filter}
            value={filters.number as 'unchecked' | ''}
            onChange={(next) => setFilters({ number: next })}
            chips={[
              { value: '', label: t.number.anyNumber },
              { value: 'unchecked', label: t.number.onlyUnchecked, count: uncheckedCount.data?.counts.all },
            ]}
          />
        </div>

        <div className="mt-6">
          {list.error ? (
            <ErrorState error={list.error} onRetry={list.retry} />
          ) : !list.data ? (
            <TableSkeleton columns={5} />
          ) : list.data.items.length === 0 ? (
            <EmptyState
              icon={Store}
              title={t.empty.search}
              text={t.empty.searchText}
              action={
                filtered && (
                  <Button variant="outline" className="h-10 rounded-full px-5" onClick={() => (setQ(''), setStatus(''))}>
                    {t.clearFilters}
                  </Button>
                )
              }
            />
          ) : (
            <Table className={cn('transition-opacity', card.table, list.loading && 'opacity-60')}>
              <TableHeader>
                <TableRow className="border-border hover:bg-transparent">
                  <TableHead className={th}>{t.col.store}</TableHead>
                  <TableHead className={th}>{t.col.owner}</TableHead>
                  <TableHead className={cn(th, 'text-end')}>{t.col.products}</TableHead>
                  <TableHead className={th}>{t.col.applied}</TableHead>
                  <TableHead className={th}>{t.col.status}</TableHead>
                  <DetailsHead />
                </TableRow>
              </TableHeader>
              <TableBody>
                {list.data.items.map((s) => (
                  <TableRow key={s.id} className={row} onClick={() => sheet.open('store', s.id)}>
                    <TableCell className={cn(td, 'max-w-[340px]')}>
                      <NameCell
                        thumb={<Thumb src={s.logoUrl} name={s.storeName} round />}
                        title={s.storeName}
                        subtitle={
                          <>
                            {city(s.governorate)}
                            {s.deletionRequestedAt && s.status !== 'CLOSED' && (
                              <span className="block text-wait">{t.store.deletionRequested(date(s.deletionRequestedAt, lang))}</span>
                            )}
                          </>
                        }
                      />
                    </TableCell>
                    <TableCell className={cn(td, card.line)}>
                      {s.status === 'CLOSED' ? (
                        <>
                          <div className="text-[15px] text-muted-foreground">{t.store.ownerGone}</div>
                          {s.closedAt && <div className="text-[13px] text-muted-foreground">{t.store.closedOn(date(s.closedAt, lang))}</div>}
                        </>
                      ) : (
                        <>
                          <div className="text-[15px] text-navy">{s.fullName}</div>
                          <Ltr className="text-[13px] text-muted-foreground tabular-nums">{phone(s.phone)}</Ltr>
                          {s.phoneVerified === false && <div className="text-[13px] font-medium text-wait">{t.number.unchecked}</div>}
                        </>
                      )}
                    </TableCell>
                    <TableCell className={cn(td, card.hide, 'text-end text-[15px] font-medium text-navy tabular-nums')}>
                      {number(s.productCount)}
                    </TableCell>
                    <TableCell className={cn(td, card.hide, 'text-[14px] text-muted-foreground')}>{date(s.submittedAt, lang)}</TableCell>
                    <TableCell className={td}>
                      <StoreBadge status={s.status} />
                    </TableCell>
                    <TableCell className={cn(td, card.end, 'text-end')}>
                      <DetailsButton onClick={() => sheet.open('store', s.id)} />
                    </TableCell>
                  </TableRow>
                ))}
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
