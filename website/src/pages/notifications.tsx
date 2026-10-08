import { useId, useState, type FormEvent } from 'react'
import { Bell, Megaphone, Send, Store, Users, UsersRound } from 'lucide-react'
import { toast } from 'sonner'
import { ConfirmDialog, solid } from '@/components/actions'
import { ContentCard, EmptyState, ErrorState, PageIntro, TableSkeleton, errorText } from '@/components/blocks'
import { fieldClass } from '@/components/form'
import { Button } from '@/components/ui/button'
import { Label } from '@/components/ui/label'
import { getAnnouncements, sendAnnouncement, type Audience } from '@/data/announcements'
import { dateTime, number } from '@/lib/format'
import { useI18n } from '@/lib/i18n'
import { refreshAll, useQuery } from '@/lib/use-query'
import { cn } from '@/lib/utils'

const TITLE_MAX = 120
const BODY_MAX = 1000

/**
 * Saba's announcements (the user's call, 2026-10-08): one notification to
 * everyone, every customer or every store owner, in their app's list and on
 * their phones. Only those three audiences, as the client asked; a send is
 * confirmed first, and the last ones sent are listed under the form.
 */
export function NotificationsPage() {
  const { t, lang } = useI18n()
  const overview = useQuery(getAnnouncements, 'announcements')
  const [audience, setAudience] = useState<Audience>('EVERYONE')
  const [title, setTitle] = useState('')
  const [body, setBody] = useState('')
  const [missing, setMissing] = useState(false)
  const [confirming, setConfirming] = useState(false)
  const titleId = useId()
  const bodyId = useId()

  const recipients = overview.data?.recipients[audience]
  const audiences: { value: Audience; label: string; icon: typeof Users }[] = [
    { value: 'EVERYONE', label: t.announce.everyone, icon: UsersRound },
    { value: 'CUSTOMERS', label: t.announce.customers, icon: Users },
    { value: 'MERCHANTS', label: t.announce.merchants, icon: Store },
  ]
  const audienceLabel = (value: Audience) => audiences.find((a) => a.value === value)!.label

  const ask = (event: FormEvent) => {
    event.preventDefault()
    if (!title.trim() || !body.trim()) {
      setMissing(true)
      return
    }
    setConfirming(true)
  }

  const send = async () => {
    try {
      const sent = await sendAnnouncement({ audience, title: title.trim(), body: body.trim() })
      toast.success(t.announce.sent(number(sent.recipients)))
      setTitle('')
      setBody('')
      setMissing(false)
      await refreshAll()
      return true
    } catch (error) {
      toast.error(errorText(error, t))
      await refreshAll()
      return false
    }
  }

  return (
    <>
      <PageIntro>{t.announce.intro}</PageIntro>

      <div className="grid items-start gap-6 xl:grid-cols-[minmax(0,1fr)_380px]">
        <ContentCard icon={Megaphone} title={t.announce.formTitle} description={t.announce.formText}>
          <form onSubmit={ask} noValidate className="space-y-6">
            <fieldset>
              <legend className="mb-2.5 text-[12px] font-semibold tracking-[0.08em] text-muted-foreground uppercase">
                {t.announce.audience}
              </legend>
              <div role="radiogroup" aria-label={t.announce.audience} className="flex flex-wrap gap-2">
                {audiences.map((option) => {
                  const selected = option.value === audience
                  return (
                    <button
                      key={option.value}
                      type="button"
                      role="radio"
                      aria-checked={selected}
                      onClick={() => setAudience(option.value)}
                      className={cn(
                        'inline-flex h-11 items-center gap-2 rounded-full border px-4 text-sm font-medium transition-colors outline-none focus-visible:ring-3 focus-visible:ring-primary/30',
                        selected
                          ? 'border-surface-dark bg-surface-dark text-white shadow-[0_6px_16px_-8px_rgba(14,26,43,0.6)]'
                          : 'border-border bg-white text-navy hover:border-border-strong hover:bg-soft',
                      )}
                    >
                      <option.icon className="size-4" strokeWidth={1.75} />
                      {option.label}
                      {overview.data && (
                        <span className={cn('tabular-nums', selected ? 'text-white/70' : 'text-faint')}>
                          {number(overview.data.recipients[option.value])}
                        </span>
                      )}
                    </button>
                  )
                })}
              </div>
              <p className="mt-3 inline-flex items-center gap-2 rounded-xl bg-soft px-3.5 py-2 text-sm text-navy">
                {t.announce.recipients}
                <span className="font-semibold tabular-nums">{recipients === undefined ? '…' : number(recipients)}</span>
              </p>
            </fieldset>

            <div>
              <div className="mb-2 flex items-baseline justify-between gap-3">
                <Label htmlFor={titleId} className="text-sm font-medium text-navy">
                  {t.announce.title}
                </Label>
                <span className="text-[12px] text-faint tabular-nums">
                  {title.length}/{TITLE_MAX}
                </span>
              </div>
              <input
                id={titleId}
                value={title}
                maxLength={TITLE_MAX}
                dir="auto"
                placeholder={t.announce.titleExample}
                aria-invalid={missing && !title.trim()}
                onChange={(e) => setTitle(e.target.value)}
                className={fieldClass}
              />
            </div>

            <div>
              <div className="mb-2 flex items-baseline justify-between gap-3">
                <Label htmlFor={bodyId} className="text-sm font-medium text-navy">
                  {t.announce.message}
                </Label>
                <span className="text-[12px] text-faint tabular-nums">
                  {body.length}/{BODY_MAX}
                </span>
              </div>
              <textarea
                id={bodyId}
                value={body}
                maxLength={BODY_MAX}
                rows={6}
                dir="auto"
                placeholder={t.announce.messageExample}
                aria-invalid={missing && !body.trim()}
                onChange={(e) => setBody(e.target.value)}
                className={cn(fieldClass, 'h-auto min-h-36 resize-y py-3 leading-relaxed')}
              />
              {missing && (!title.trim() || !body.trim()) && <p className="mt-2 text-sm text-bad">{t.announce.both}</p>}
            </div>

            <div className="flex flex-wrap items-center justify-between gap-3 border-t border-border pt-5">
              <p className="max-w-md text-[13px] leading-snug text-muted-foreground">{t.announce.howItGoes}</p>
              <Button
                type="submit"
                disabled={!recipients}
                className={cn('h-11 gap-2 rounded-full px-6 text-[15px]', solid.primary)}
              >
                <Send className="size-4" />
                {t.announce.sendTo(number(recipients ?? 0))}
              </Button>
            </div>
          </form>
        </ContentCard>

        {/* How it lands in the app: the notification list's card. */}
        <aside className="rounded-3xl border border-border bg-card p-6 shadow-[0_1px_2px_rgba(14,26,43,0.04),0_8px_24px_-12px_rgba(14,26,43,0.08)] sm:p-7 xl:sticky xl:top-28">
          <h2 className="text-[15px] font-semibold text-navy">{t.announce.preview}</h2>
          <div className="mt-4 flex gap-3.5 rounded-2xl border border-border bg-soft/60 p-4">
            <span className="grid size-11 shrink-0 place-items-center rounded-xl bg-surface-dark text-white">
              <Bell className="size-5" strokeWidth={1.75} />
            </span>
            <div className="min-w-0 flex-1">
              <p dir="auto" className="text-[15px] font-semibold break-words text-navy">
                {title.trim() || t.announce.previewTitle}
              </p>
              <p dir="auto" className="mt-1 text-sm leading-relaxed break-words whitespace-pre-line text-muted-foreground">
                {body.trim() || t.announce.previewBody}
              </p>
              <p className="mt-2 text-[12px] text-faint">{t.announce.now}</p>
            </div>
          </div>
          <p className="mt-4 text-[13px] leading-snug text-muted-foreground">{t.announce.previewNote}</p>
        </aside>
      </div>

      <ContentCard icon={Bell} title={t.announce.recentTitle} description={t.announce.recentText} className="mt-6">
        {overview.error ? (
          <ErrorState error={overview.error} onRetry={overview.retry} />
        ) : !overview.data ? (
          <TableSkeleton rows={3} columns={3} />
        ) : overview.data.sent.length === 0 ? (
          <EmptyState icon={Megaphone} title={t.announce.noneTitle} text={t.announce.noneText} />
        ) : (
          <ul className="divide-y divide-border">
            {overview.data.sent.map((one) => (
              <li key={one.id} className="flex flex-wrap items-start gap-x-6 gap-y-2 py-4 first:pt-0 last:pb-0">
                <div className="min-w-0 flex-1 basis-72">
                  <p dir="auto" className="truncate text-[15px] font-semibold text-navy">
                    {one.title}
                  </p>
                  <p dir="auto" className="mt-0.5 line-clamp-2 text-sm text-muted-foreground">
                    {one.body}
                  </p>
                </div>
                <div className="flex shrink-0 flex-col items-end gap-1 text-end">
                  <span className="rounded-full bg-soft px-3 py-1 text-[13px] font-medium text-navy">
                    {audienceLabel(one.audience)} · {t.announce.people(number(one.recipients))}
                  </span>
                  <span className="text-[12px] text-faint">
                    {dateTime(one.sentAt, lang)}
                    {one.sentBy && ` · ${one.sentBy}`}
                  </span>
                </div>
              </li>
            ))}
          </ul>
        )}
      </ContentCard>

      <ConfirmDialog
        open={confirming}
        onOpenChange={setConfirming}
        title={t.announce.confirmTitle(audienceLabel(audience), number(recipients ?? 0))}
        text={t.announce.confirmText}
        confirmLabel={t.announce.sendTo(number(recipients ?? 0))}
        onConfirm={send}
      />
    </>
  )
}
