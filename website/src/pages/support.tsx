import { CircleCheck, Hourglass, Inbox, LifeBuoy, Loader, Store, User } from 'lucide-react'
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
  TableSkeleton,
  card,
  pillSelect,
  row,
  showList,
  td,
  th,
  usePage,
} from '@/components/blocks'
import { TICKET_STATUSES, TicketBadge, ticketStatus } from '@/components/ticket-sheet'
import { Button } from '@/components/ui/button'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { listTickets, type OpenedBy, type TicketStatus } from '@/data/tickets'
import { ago, date } from '@/lib/format'
import { useI18n } from '@/lib/i18n'
import { useSheet, useUrlFilters } from '@/lib/url-state'
import { useQuery } from '@/lib/use-query'
import { cn } from '@/lib/utils'

const OPENERS: OpenedBy[] = ['SHOPPER', 'STORE']
const ANYONE = 'anyone'

export function SupportPage() {
  const { t, lang } = useI18n()
  const sheet = useSheet()
  const [filters, setFilters] = useUrlFilters({ status: TICKET_STATUSES, from: OPENERS })
  const status = filters.status as TicketStatus | ''
  const from = filters.from as OpenedBy | ''
  // The cards count the whole list; the counts are the same on every page, so one row is enough.
  const all = useQuery(() => listTickets({ page: 1, perPage: 1 }), 'tickets:all')
  const [page, setPage] = usePage(`${status}:${from}`)
  const list = useQuery(
    () => listTickets({ status: status || undefined, openedBy: from || undefined, page }),
    `tickets:${status}:${from}:${page}`,
  )
  const counts = all.data?.counts
  const stat = (s: TicketStatus) => (all.error ? '—' : counts ? (counts[s] ?? 0) : undefined)
  /** A card shows exactly what it counted: its status, from anyone. */
  const fromCard = (next: TicketStatus) => () => {
    setFilters({ status: next, from: '' })
    showList()
  }
  const cardFor = (s: TicketStatus, icon: typeof Inbox) => (
    <StatCard label={t.support.status[s]} value={stat(s)} icon={icon} onClick={fromCard(s)} active={status === s && !from} />
  )

  return (
    <>
      <PageIntro>{t.support.intro}</PageIntro>
      <StatRow>
        {cardFor('OPEN', Inbox)}
        {cardFor('IN_PROGRESS', Loader)}
        {cardFor('WAITING_FOR_CUSTOMER', Hourglass)}
        {cardFor('RESOLVED', CircleCheck)}
      </StatRow>

      <ContentCard id="list" icon={LifeBuoy} title={t.support.cardTitle} description={t.support.cardText}>
        <div className="flex flex-wrap items-center justify-between gap-3">
          <FilterChips
            label={t.col.status}
            value={status}
            onChange={(next) => setFilters({ status: next })}
            chips={[
              { value: '', label: t.all, count: list.data?.counts.all },
              // With "Opened by" set, the chip says whose reply it waits for.
              ...TICKET_STATUSES.map((s) => ({ value: s, label: ticketStatus(t, s, from || undefined), count: list.data && (list.data.counts[s] ?? 0) })),
            ]}
          />
          <Select value={from || ANYONE} onValueChange={(next) => setFilters({ from: next === ANYONE ? '' : next })}>
            <SelectTrigger aria-label={t.support.openedBy} className={cn(pillSelect, from && 'border-primary text-primary')}>
              <span className="text-muted-foreground">{t.support.openedBy}:</span>
              <SelectValue />
            </SelectTrigger>
            <SelectContent position="popper" align="end" className="rounded-xl">
              <SelectItem value={ANYONE}>{t.support.anyone}</SelectItem>
              {OPENERS.map((o) => (
                <SelectItem key={o} value={o}>
                  {t.support.kinds[o]}
                  {list.data && <span className="text-faint tabular-nums">({list.data.byOpener[o]})</span>}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>

        <div className="mt-6">
          {list.error ? (
            <ErrorState error={list.error} onRetry={list.retry} />
          ) : !list.data ? (
            <TableSkeleton columns={4} />
          ) : list.data.items.length === 0 ? (
            <EmptyState
              icon={LifeBuoy}
              title={t.empty.search}
              text={t.empty.searchText}
              action={
                (status || from) && (
                  <Button variant="outline" className="h-10 rounded-full px-5" onClick={() => setFilters({ status: '', from: '' })}>
                    {t.clearFilters}
                  </Button>
                )
              }
            />
          ) : (
            <Table className={cn('transition-opacity', card.table, list.loading && 'opacity-60')}>
              <TableHeader>
                <TableRow className="border-border hover:bg-transparent">
                  <TableHead className={th}>{t.support.col.subject}</TableHead>
                  <TableHead className={th}>{t.support.openedBy}</TableHead>
                  <TableHead className={th}>{t.col.status}</TableHead>
                  <TableHead className={th}>{t.support.col.activity}</TableHead>
                  <DetailsHead />
                </TableRow>
              </TableHeader>
              <TableBody>
                {list.data.items.map((ticket) => {
                  const open = () => sheet.open('ticket', ticket.id)
                  const by = ticket.openedBy
                  return (
                    <TableRow key={ticket.id} className={row} onClick={open}>
                      <TableCell className={td}>
                        <div className="max-w-[250px] 2xl:max-w-[360px]">
                          <NameCell
                            thumb={
                              <span className="grid size-11 shrink-0 place-items-center rounded-xl bg-accent-soft text-primary">
                                <LifeBuoy className="size-5" strokeWidth={1.75} />
                              </span>
                            }
                            title={ticket.subject}
                            subtitle={
                              <>
                                <span dir="ltr">{ticket.reference}</span> · {t.support.category[ticket.category]} · {t.support.messages(ticket.messageCount)}
                              </>
                            }
                          />
                        </div>
                      </TableCell>
                      <TableCell className={cn(td, card.line)}>
                        <div className="flex items-center gap-1.5 text-[15px] text-navy">
                          {by.kind === 'STORE' ? <Store className="size-4 text-faint" /> : <User className="size-4 text-faint" />}
                          <bdi>{by.name}</bdi>
                        </div>
                        <div className="text-[13px] text-muted-foreground">{t.support.kind[by.kind]}</div>
                      </TableCell>
                      <TableCell className={td}>
                        <TicketBadge status={ticket.status} kind={by.kind} />
                      </TableCell>
                      {/* The list is newest activity first, so it shows when that was: a reply or a close counts. */}
                      <TableCell className={cn(td, card.hide, 'text-[14px] text-muted-foreground')}>
                        <div className="text-navy">{ago(ticket.updatedAt, lang)}</div>
                        <div className="text-[13px]">{t.support.openedOn(date(ticket.createdAt, lang))}</div>
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
