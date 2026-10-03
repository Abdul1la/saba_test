import { useState } from 'react'
import { Ban, ShoppingBag, UserCheck, Users } from 'lucide-react'
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
  TableSkeleton,
  Thumb,
  card,
  row,
  showList,
  td,
  th,
  usePage,
} from '@/components/blocks'
import { CustomerBadge } from '@/components/customer-sheet'
import { Button } from '@/components/ui/button'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { listCustomers, type CustomerStatus } from '@/data/customers'
import { listOrders } from '@/data/orders'
import { date, money, number, phone } from '@/lib/format'
import { useI18n } from '@/lib/i18n'
import { useSheet, useUrlFilters } from '@/lib/url-state'
import { useDebounced, useQuery } from '@/lib/use-query'
import { cn } from '@/lib/utils'

const STATUSES: CustomerStatus[] = ['ACTIVE', 'SUSPENDED']

export function CustomersPage() {
  const { t, lang, city, pick } = useI18n()
  const sheet = useSheet()
  const [q, setQ] = useState('')
  const [filters, setFilters] = useUrlFilters({ status: STATUSES, number: ['unchecked'] })
  const status = filters.status as CustomerStatus | ''
  // Only numbers never checked (signed up while SMS codes were off).
  const unchecked = filters.number === 'unchecked'
  const search = useDebounced(q)
  // The cards count the whole list; the counts are the same on every page, so one row is enough.
  const all = useQuery(() => listCustomers({ page: 1, perPage: 1 }), 'customers:all')
  // The Orders card leads to Orders, so it says what that page counts.
  const orders = useQuery(() => listOrders({ page: 1, perPage: 1 }), 'orders:all')
  const [page, setPage] = usePage(`${search}:${status}:${unchecked}`)
  const list = useQuery(
    () => listCustomers({ q: search, status: status || undefined, phoneVerified: unchecked ? false : undefined, page }),
    `customers:${search}:${status}:${unchecked}:${page}`,
  )
  const uncheckedCount = useQuery(() => listCustomers({ q: search, phoneVerified: false, page: 1, perPage: 1 }), `customers:unchecked:${search}`)
  const counts = all.data?.counts
  const stat = (n?: number) => (all.error ? '—' : n)
  const fromCard = (next: CustomerStatus | '') => () => {
    setQ('')
    setFilters({ status: next })
    showList()
  }
  const filtered = !!(q || status)

  return (
    <>
      <PageIntro>{t.customers.intro}</PageIntro>
      <StatRow>
        <StatCard label={t.customers.total} value={stat(counts?.all)} icon={Users} onClick={fromCard('')} active={!status} />
        <StatCard label={t.customers.active} value={stat(counts && (counts.ACTIVE ?? 0))} icon={UserCheck} onClick={fromCard('ACTIVE')} active={status === 'ACTIVE'} />
        <StatCard
          label={t.customers.suspended}
          value={stat(counts && (counts.SUSPENDED ?? 0))}
          icon={Ban}
          onClick={fromCard('SUSPENDED')}
          active={status === 'SUSPENDED'}
        />
        <StatCard label={t.customers.col.orders} value={orders.error ? '—' : orders.data?.counts.all} icon={ShoppingBag} to="/orders" />
      </StatRow>

      <ContentCard id="list" icon={Users} title={t.customers.cardTitle} description={t.customers.cardText}>
        <div className="space-y-4">
          <SearchBar value={q} onChange={setQ} placeholder={t.customers.search} />
          <FilterChips
            label={t.col.status}
            value={status}
            onChange={(next) => setFilters({ status: next })}
            chips={[
              { value: '', label: t.all, count: list.data?.counts.all },
              ...STATUSES.map((s) => ({ value: s, label: t.customers.status[s], count: list.data && (list.data.counts[s] ?? 0) })),
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
              icon={Users}
              title={t.empty.search}
              text={t.empty.searchText}
              action={
                filtered && (
                  <Button variant="outline" className="h-10 rounded-full px-5" onClick={() => (setQ(''), setFilters({ status: '' }))}>
                    {t.clearFilters}
                  </Button>
                )
              }
            />
          ) : (
            <Table className={cn('transition-opacity', card.table, list.loading && 'opacity-60')}>
              <TableHeader>
                <TableRow className="border-border hover:bg-transparent">
                  <TableHead className={th}>{t.customers.col.customer}</TableHead>
                  <TableHead className={th}>{t.customers.col.city}</TableHead>
                  <TableHead className={cn(th, 'text-end')}>{t.customers.col.orders}</TableHead>
                  <TableHead className={cn(th, 'text-end')}>{t.customers.col.spent}</TableHead>
                  <TableHead className={th}>{t.col.status}</TableHead>
                  <TableHead className={cn(th, '@max-5xl:hidden')}>{t.customers.col.joined}</TableHead>
                  <DetailsHead />
                </TableRow>
              </TableHeader>
              <TableBody>
                {list.data.items.map((c) => {
                  const open = () => sheet.open('customer', c.id)
                  return (
                    <TableRow key={c.id} className={row} onClick={open}>
                      <TableCell className={td}>
                        <NameCell
                          thumb={<Thumb name={c.fullName} round />}
                          title={pick(c.fullName, c.fullNameAr)}
                          subtitle={
                            <>
                              <Ltr className="tabular-nums">{phone(c.phone)}</Ltr>
                              {c.phoneVerified === false && <span className="ms-2 text-[13px] font-medium text-wait">{t.number.unchecked}</span>}
                            </>
                          }
                        />
                      </TableCell>
                      <TableCell className={cn(td, card.line, 'text-[15px] text-navy')}>
                        {city(c.governorate)}
                        {/* The figures' own columns are hidden on a narrow card. */}
                        <span className="hidden text-[13px] text-muted-foreground tabular-nums @max-3xl:inline">
                          {' · '}
                          {t.finance.orders(c.orderCount)} · {money(c.spent, lang)}
                        </span>
                      </TableCell>
                      <TableCell className={cn(td, card.hide, 'text-end text-[15px] text-navy tabular-nums')}>{number(c.orderCount)}</TableCell>
                      <TableCell className={cn(td, card.hide, 'text-end text-[15px] font-medium text-navy tabular-nums')}>{money(c.spent, lang)}</TableCell>
                      <TableCell className={td}>
                        <CustomerBadge status={c.status} />
                      </TableCell>
                      <TableCell className={cn(td, '@max-5xl:hidden', 'text-[14px] text-muted-foreground')}>{date(c.joinedAt, lang)}</TableCell>
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
