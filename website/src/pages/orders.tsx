import { useState } from 'react'
import { CircleCheck, Hourglass, ReceiptText, Truck } from 'lucide-react'
import {
  ContentCard,
  DetailsButton,
  DetailsHead,
  EmptyState,
  ErrorState,
  FilterChips,
  Ltr,
  NameCell,
  OrderBadge,
  PageIntro,
  Pager,
  SearchBar,
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
  usePage,
} from '@/components/blocks'
import { Button } from '@/components/ui/button'
import { Select, SelectContent, SelectGroup, SelectItem, SelectLabel, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { listOrders } from '@/data/orders'
import type { AdminOrder, OrderStatus } from '@/data/types'
import { date, money } from '@/lib/format'
import { useI18n } from '@/lib/i18n'
import { useSheet, useUrlFilters } from '@/lib/url-state'
import { useDebounced, useQuery } from '@/lib/use-query'
import { cn } from '@/lib/utils'

export const ORDER_STATUSES: OrderStatus[] = [
  'PENDING',
  'CONFIRMED',
  'PROCESSING',
  'SHIPPED',
  'DELIVERED',
  'CANCELLED',
  'REFUSED',
  'RETURNED',
  'REFUNDED',
]

/**
 * How the filters show the app's statuses: every status in exactly one
 * group. The statuses themselves are unchanged.
 */
const ORDER_GROUPS = {
  waiting: ['PENDING'],
  moving: ['CONFIRMED', 'PROCESSING', 'SHIPPED'],
  delivered: ['DELIVERED'],
  problems: ['CANCELLED', 'REFUSED', 'RETURNED', 'REFUNDED'],
} as const satisfies Record<string, readonly OrderStatus[]>

type Group = keyof typeof ORDER_GROUPS
const GROUPS = Object.keys(ORDER_GROUPS) as Group[]
const groupOf = (status: OrderStatus) => GROUPS.find((g) => (ORDER_GROUPS[g] as readonly OrderStatus[]).includes(status))
const ALL = 'all'

const sum = (counts: Partial<Record<OrderStatus, number>>, statuses: readonly OrderStatus[]) =>
  statuses.reduce((n, s) => n + (counts[s] ?? 0), 0)

/** Order, first item, customer, total, status, Details. Shared with the dashboard. */
export function OrdersTable({ orders, dim = false }: { orders: AdminOrder[]; dim?: boolean }) {
  const { t, lang, city, pick } = useI18n()
  const sheet = useSheet()
  return (
    <Table className={cn('transition-opacity', card.table, dim && 'opacity-60')}>
      <TableHeader>
        <TableRow className="border-border hover:bg-transparent">
          <TableHead className={th}>{t.col.order}</TableHead>
          <TableHead className={th}>{t.col.items}</TableHead>
          <TableHead className={th}>{t.col.customer}</TableHead>
          <TableHead className={cn(th, 'text-end')}>{t.col.total}</TableHead>
          <TableHead className={th}>{t.col.status}</TableHead>
          <DetailsHead />
        </TableRow>
      </TableHeader>
      <TableBody>
        {orders.map((o) => {
          const first = o.items[0]
          const open = () => sheet.open('order', o.id)
          return (
            <TableRow key={o.id} className={row} onClick={open}>
              <TableCell className={td}>
                <Ltr className="block font-medium text-navy tabular-nums">{o.orderNumber}</Ltr>
                <span className="mt-0.5 block text-[13px] text-muted-foreground">
                  {date(o.placedAt, lang)}
                  {/* The total's own column is hidden on a narrow card. */}
                  <span className="hidden tabular-nums @max-3xl:inline"> · {money(o.total, lang)}</span>
                </span>
              </TableCell>
              <TableCell className={cn(td, card.hide)}>
                {/* A table cell ignores max-width; a box inside it does not, so a long name ends in "…". */}
                <div className="max-w-[220px] 2xl:max-w-[300px]">
                  <NameCell
                    thumb={<Thumb src={first?.imageUrl} name={first?.productName ?? '?'} />}
                    title={first && pick(first.productName, first.productNameAr)}
                    subtitle={
                      <>
                        <bdi>{o.merchantNames.join(', ')}</bdi>
                        {o.items.length > 1 && <span className="text-faint"> · {t.more(o.items.length - 1)}</span>}
                      </>
                    }
                  />
                </div>
              </TableCell>
              <TableCell className={cn(td, card.line)}>
                <div className="text-[15px] text-navy">{o.customerName}</div>
                <div className="text-[13px] text-muted-foreground">{city(o.shippingAddress.governorate)}</div>
              </TableCell>
              <TableCell className={cn(td, card.hide, 'text-end text-[15px] font-medium text-navy tabular-nums')}>
                {money(o.total, lang)}
              </TableCell>
              <TableCell className={td}>
                <OrderBadge status={o.status} />
              </TableCell>
              <TableCell className={cn(td, card.end, 'text-end')}>
                <DetailsButton onClick={open} />
              </TableCell>
            </TableRow>
          )
        })}
      </TableBody>
    </Table>
  )
}

export function OrdersPage() {
  const { t } = useI18n()
  const [q, setQ] = useState('')
  const [filters, setFilters] = useUrlFilters({ group: GROUPS, status: ORDER_STATUSES })
  const status = filters.status as OrderStatus | ''
  // An exact status always sits inside its group, so the group is worked out from it.
  const group: Group | '' = status ? (groupOf(status) ?? '') : (filters.group as Group | '')
  const statuses = status ? [status] : group ? [...ORDER_GROUPS[group]] : undefined
  const search = useDebounced(q)

  // The cards count the whole list; the counts are the same on every page, so one row is enough.
  const all = useQuery(() => listOrders({ page: 1, perPage: 1 }), 'orders:all')
  const [page, setPage] = usePage(`${search}:${group}:${status}`)
  const list = useQuery(() => listOrders({ q: search, statuses, page }), `orders:${search}:${group}:${status}:${page}`)
  const counts = all.data?.counts
  const stat = (g: Group | '') => (all.error ? '—' : counts ? (g ? sum(counts, ORDER_GROUPS[g]) : counts.all) : undefined)
  const filtered = !!(q || group || status)

  const chooseGroup = (g: Group | '') => setFilters({ group: g, status: '' })
  const chooseStatus = (value: string) =>
    value === ALL ? setFilters({ group, status: '' }) : setFilters({ group: '', status: value })
  /** A card shows exactly what it counted: its group, and no search. */
  const fromCard = (g: Group | '') => () => {
    setQ('')
    chooseGroup(g)
    showList()
  }

  return (
    <>
      <PageIntro>{t.orders.intro}</PageIntro>
      <StatRow>
        <StatCard label={t.orders.total} value={stat('')} icon={ReceiptText} onClick={fromCard('')} active={!group} />
        <StatCard label={t.orders.waiting} value={stat('waiting')} icon={Hourglass} onClick={fromCard('waiting')} active={group === 'waiting'} />
        <StatCard label={t.orders.moving} value={stat('moving')} icon={Truck} onClick={fromCard('moving')} active={group === 'moving'} />
        <StatCard label={t.orders.delivered} value={stat('delivered')} icon={CircleCheck} onClick={fromCard('delivered')} active={group === 'delivered'} />
      </StatRow>

      <ContentCard id="list" icon={ReceiptText} title={t.orders.cardTitle} description={t.orders.cardText}>
        <div className="space-y-4">
          <SearchBar value={q} onChange={setQ} placeholder={t.orders.search} />
          <div className="flex flex-wrap items-center justify-between gap-3">
            <FilterChips
              label={t.col.status}
              value={group}
              onChange={chooseGroup}
              chips={[
                { value: '', label: t.all, count: list.data?.counts.all },
                ...GROUPS.map((g) => ({ value: g, label: t.orders[g], count: list.data && sum(list.data.counts, ORDER_GROUPS[g]) })),
              ]}
            />
            <Select value={status || ALL} onValueChange={chooseStatus}>
              <SelectTrigger aria-label={t.orders.status} className={cn(pillSelect, status && 'border-primary text-primary')}>
                <span className="text-muted-foreground">{t.orders.status}:</span>
                <SelectValue />
              </SelectTrigger>
              <SelectContent position="popper" align="end" className="rounded-xl">
                <SelectItem value={ALL}>{t.orders.allStatuses}</SelectItem>
                {GROUPS.map((g) => (
                  <SelectGroup key={g}>
                    <SelectLabel>{t.orders[g]}</SelectLabel>
                    {ORDER_GROUPS[g].map((s) => (
                      <SelectItem key={s} value={s} className="ps-4">
                        {t.orderStatus[s]}
                        {list.data && <span className="text-faint tabular-nums">({list.data.counts[s] ?? 0})</span>}
                      </SelectItem>
                    ))}
                  </SelectGroup>
                ))}
              </SelectContent>
            </Select>
          </div>
        </div>
        <div className="mt-6">
          {list.error ? (
            <ErrorState error={list.error} onRetry={list.retry} />
          ) : !list.data ? (
            <TableSkeleton columns={5} />
          ) : list.data.items.length === 0 ? (
            <EmptyState
              title={t.empty.search}
              text={t.empty.searchText}
              action={
                filtered && (
                  <Button variant="outline" className="h-10 rounded-full px-5" onClick={() => (setQ(''), chooseGroup(''))}>
                    {t.clearFilters}
                  </Button>
                )
              }
            />
          ) : (
            <OrdersTable orders={list.data.items} dim={list.loading} />
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
