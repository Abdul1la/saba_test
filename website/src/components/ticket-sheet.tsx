import { useId, useState, type FormEvent } from 'react'
import { LifeBuoy, Lock, Phone, Send, Store, User, XCircle } from 'lucide-react'
import { ConfirmDialog, useRun } from '@/components/actions'
import { Callout, IconBox, Ltr, Section, StatusBadge, Thumb, type Tone } from '@/components/blocks'
import { Body, Failed, Loading } from '@/components/detail-sheets'
import { Button } from '@/components/ui/button'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { SheetDescription, SheetTitle } from '@/components/ui/sheet'
import { Textarea } from '@/components/ui/textarea'
import { getTicket, replyToTicket, setTicketStatus, type OpenedBy, type Ticket, type TicketStatus } from '@/data/tickets'
import { date, dateTime, phone } from '@/lib/format'
import { useI18n, type Strings } from '@/lib/i18n'
import { useSheet } from '@/lib/url-state'
import { useQuery } from '@/lib/use-query'
import { cn } from '@/lib/utils'

export const TICKET_STATUSES: TicketStatus[] = ['OPEN', 'IN_PROGRESS', 'WAITING_FOR_CUSTOMER', 'RESOLVED', 'CLOSED']

// orange: needs Saba · blue: Saba is on it · grey: with whoever opened it, or done · green: solved
export const TICKET_TONE = {
  OPEN: 'wait',
  IN_PROGRESS: 'go',
  WAITING_FOR_CUSTOMER: 'off',
  RESOLVED: 'ok',
  CLOSED: 'off',
} as const satisfies Record<TicketStatus, Tone>

/** The app's WAITING_FOR_CUSTOMER, said as who it waits for: a store's ticket waits for the store. */
export const ticketStatus = (t: Strings, status: TicketStatus, kind?: OpenedBy) =>
  status === 'WAITING_FOR_CUSTOMER' && kind ? t.support.waiting[kind] : t.support.status[status]

export function TicketBadge({ status, kind }: { status: TicketStatus; kind: OpenedBy }) {
  const { t } = useI18n()
  return <StatusBadge tone={TICKET_TONE[status]}>{ticketStatus(t, status, kind)}</StatusBadge>
}

/** One ticket and its conversation (?ticket=tk-5010): read, reply, change its status. */
export function TicketDetail({ id }: { id: string }) {
  const { t, lang } = useI18n()
  const sheet = useSheet()
  const result = useQuery(() => getTicket(id), `ticket:${id}`)

  if (result.error) return <Failed error={result.error} retry={result.retry} />
  if (!result.data) return <Loading />
  const ticket = result.data
  const by = ticket.openedBy

  return (
    <>
      <div className="px-7 pt-8">
        <div className="flex items-start gap-3.5">
          <IconBox icon={LifeBuoy} className="size-12 rounded-2xl" />
          <div className="min-w-0">
            <SheetTitle dir="auto" className="font-serif text-[26px] leading-tight font-normal text-navy">
              {ticket.subject}
            </SheetTitle>
            <SheetDescription className="mt-1 text-[15px] text-muted-foreground">
              <Ltr>{ticket.reference}</Ltr> · {t.support.category[ticket.category]} · {date(ticket.createdAt, lang)}
            </SheetDescription>
          </div>
        </div>
        <div className="mt-4 flex flex-wrap gap-2">
          <TicketBadge status={ticket.status} kind={by.kind} />
          <StatusBadge tone="off">{t.support.kind[by.kind]}</StatusBadge>
        </div>
      </div>

      <Body>
        <Section title={t.support.openedBy}>
          <div className="flex items-center gap-3">
            <Thumb name={by.name} round className="size-10" />
            <div className="min-w-0 flex-1">
              <p className="flex items-center gap-1.5 text-[15px] font-medium text-navy">
                {by.kind === 'STORE' ? <Store className="size-4 text-faint" /> : <User className="size-4 text-faint" />}
                <bdi>{by.name}</bdi>
              </p>
              <a href={`tel:${by.phone}`} className="inline-flex items-center gap-1.5 text-[13px] text-muted-foreground hover:text-primary">
                <Phone className="size-3.5" />
                <Ltr className="tabular-nums">{phone(by.phone)}</Ltr>
              </a>
            </div>
            {by.storeId && (
              <Button variant="outline" className="h-9 rounded-lg bg-white px-3 text-[13px]" onClick={() => sheet.open('store', by.storeId!)}>
                <Store data-icon="inline-start" />
                {t.support.storeDetails}
              </Button>
            )}
          </div>
        </Section>

        <Section title={t.support.conversation} aside={<span className="text-[13px] text-muted-foreground">{t.support.messages(ticket.messages.length)}</span>}>
          <ol className="space-y-4">
            {ticket.messages.map((m) => (
              <li key={m.id} className={cn('flex flex-col', m.isFromCustomer ? 'items-start' : 'items-end')}>
                <div
                  className={cn(
                    'max-w-[85%] rounded-2xl px-4 py-3 text-[15px] leading-relaxed text-navy',
                    m.isFromCustomer ? 'rounded-ss-md bg-soft' : 'rounded-se-md bg-accent-soft',
                  )}
                >
                  <p dir="auto" className="whitespace-pre-wrap">
                    {m.body}
                  </p>
                </div>
                <p className="mt-1 px-1 text-[12px] text-muted-foreground">
                  <bdi>{m.isFromCustomer ? (m.authorName ?? by.name) : (m.authorName ?? t.support.saba)}</bdi> · {dateTime(m.sentAt, lang)}
                </p>
              </li>
            ))}
          </ol>
        </Section>
      </Body>

      <div className="sticky bottom-0 mt-auto space-y-3 border-t border-border bg-white/95 px-7 py-4 backdrop-blur">
        <StatusControls ticket={ticket} />
        {ticket.status === 'CLOSED' ? (
          <Callout tone="off" icon={Lock}>
            {t.support.closedNote}
          </Callout>
        ) : (
          <ReplyBox ticket={ticket} />
        )}
      </div>
    </>
  )
}

function StatusControls({ ticket }: { ticket: Ticket }) {
  const { t } = useI18n()
  const run = useRun()
  const [closing, setClosing] = useState(false)
  const [busy, setBusy] = useState(false)
  const change = async (next: TicketStatus) => {
    setBusy(true)
    await run(() => setTicketStatus(ticket.id, next), t.support.statusChanged(ticketStatus(t, next, ticket.openedBy.kind)))
    setBusy(false)
  }
  return (
    <div className="flex flex-wrap items-center gap-2">
      <Select value={ticket.status} onValueChange={(next) => change(next as TicketStatus)} disabled={busy}>
        <SelectTrigger aria-label={t.support.changeStatus} className="h-10 min-w-52 rounded-xl bg-white text-sm">
          <span className="text-muted-foreground">{t.support.changeStatus}:</span>
          <SelectValue />
        </SelectTrigger>
        <SelectContent position="popper" className="rounded-xl">
          {TICKET_STATUSES.map((s) => (
            <SelectItem key={s} value={s}>
              {ticketStatus(t, s, ticket.openedBy.kind)}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
      {ticket.status !== 'CLOSED' && (
        <Button variant="outline" className="h-10 rounded-xl bg-white px-4" onClick={() => setClosing(true)}>
          <XCircle data-icon="inline-start" />
          {t.support.close}
        </Button>
      )}
      <ConfirmDialog
        open={closing}
        onOpenChange={setClosing}
        title={t.support.closeTitle(ticket.reference)}
        text={t.support.closeText}
        confirmLabel={t.support.close}
        onConfirm={() => run(() => setTicketStatus(ticket.id, 'CLOSED'), t.support.closed(ticket.reference))}
      />
    </div>
  )
}

function ReplyBox({ ticket }: { ticket: Ticket }) {
  const { t } = useI18n()
  const run = useRun()
  const [text, setText] = useState('')
  const [missing, setMissing] = useState(false)
  const [busy, setBusy] = useState(false)
  const fieldId = useId()
  const send = async (event: FormEvent) => {
    event.preventDefault()
    if (!text.trim()) {
      setMissing(true)
      return
    }
    setBusy(true)
    if (await run(() => replyToTicket(ticket.id, text), t.support.sent)) setText('')
    setBusy(false)
  }
  return (
    <form onSubmit={send} noValidate className="space-y-2">
      <label htmlFor={fieldId} className="sr-only">
        {t.support.replyLabel}
      </label>
      <Textarea
        id={fieldId}
        // Empty, it follows the page, so the hint reads right; typed, it follows the text.
        dir={text ? 'auto' : undefined}
        rows={3}
        // The server takes at most 4,000 characters (API_CONTRACT.md §3.8).
        maxLength={4000}
        value={text}
        onChange={(e) => {
          setText(e.target.value)
          if (e.target.value.trim()) setMissing(false)
        }}
        placeholder={t.support.replyPlaceholder}
        aria-invalid={missing}
        className="min-h-20 rounded-xl bg-soft px-3.5 py-3 text-[15px] focus-visible:bg-white"
      />
      <div className="flex items-center justify-between gap-3">
        <p className={cn('text-[13px]', missing ? 'font-medium text-bad' : 'text-transparent')} aria-live="polite">
          {missing ? t.errors.MESSAGE_REQUIRED : '.'}
        </p>
        <Button type="submit" disabled={busy} className="h-10 rounded-xl bg-primary px-5 text-white hover:bg-primary-pressed">
          <Send data-icon="inline-start" className="rtl:-scale-x-100" />
          {t.support.send}
        </Button>
      </div>
    </form>
  )
}
