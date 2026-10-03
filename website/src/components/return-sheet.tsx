import { Clock, Lock, ReceiptText, RotateCcw, Store } from 'lucide-react'
import { Callout, Field, Fields, IconBox, Ltr, Section, StatusBadge, Thumb, toneClass, type Tone } from '@/components/blocks'
import { Body, Failed, Loading } from '@/components/detail-sheets'
import { Button } from '@/components/ui/button'
import { SheetDescription, SheetTitle } from '@/components/ui/sheet'
import { getReturn, type ReturnStatus } from '@/data/returns'
import { dateTime, money } from '@/lib/format'
import { useI18n } from '@/lib/i18n'
import { useSheet } from '@/lib/url-state'
import { useQuery } from '@/lib/use-query'
import { cn } from '@/lib/utils'

export const RETURN_TONE = { REQUESTED: 'wait', APPROVED: 'go', REJECTED: 'bad', REFUNDED: 'ok' } as const satisfies Record<ReturnStatus, Tone>

/** One return, read-only (?return=ret-3). */
export function ReturnDetail({ id }: { id: string }) {
  const { t, lang, pick } = useI18n()
  const sheet = useSheet()
  const result = useQuery(() => getReturn(id), `return:${id}`)

  if (result.error) return <Failed error={result.error} retry={result.retry} />
  if (!result.data) return <Loading />
  const r = result.data
  const steps: { label: string; at?: string; tone: Tone }[] = [
    { label: t.after.stepRequested, at: r.requestedAt, tone: 'wait' },
    ...(r.status === 'REJECTED' ? [{ label: t.after.stepRejected, at: r.answeredAt, tone: 'bad' as const }] : []),
    ...(r.status === 'APPROVED' || r.status === 'REFUNDED' ? [{ label: t.after.stepApproved, at: r.answeredAt, tone: 'go' as const }] : []),
    ...(r.status === 'REFUNDED' ? [{ label: t.after.stepRefunded, at: r.refundedAt, tone: 'ok' as const }] : []),
  ]

  return (
    <>
      <div className="px-7 pt-8">
        <div className="flex items-center gap-3.5">
          <IconBox icon={RotateCcw} className="size-12 rounded-2xl" />
          <div className="min-w-0">
            <SheetTitle className="font-serif text-[26px] leading-tight font-normal text-navy">
              {t.after.returnOn} <Ltr>{r.orderNumber}</Ltr>
            </SheetTitle>
            <SheetDescription className="text-[15px] text-muted-foreground">
              <bdi>{r.merchantName}</bdi> · <bdi>{r.customerName}</bdi>
            </SheetDescription>
          </div>
        </div>
        <div className="mt-4">
          <StatusBadge tone={RETURN_TONE[r.status]}>{t.after.returnStatus[r.status]}</StatusBadge>
        </div>
      </div>

      <Body>
        <Callout tone="go" icon={Lock}>
          {t.after.readOnly}
        </Callout>

        <Section title={t.after.col.item}>
          <ul className="divide-y divide-border/70">
            {r.items.map((item, i) => (
              <li key={i} className="flex items-center gap-3 py-3 first:pt-0 last:pb-0">
                <Thumb src={item.imageUrl} name={item.productName} className="size-11" />
                <div className="min-w-0 flex-1">
                  <p className="truncate text-[15px] text-navy">{pick(item.productName, item.productNameAr)}</p>
                  <p className="text-[13px] text-muted-foreground tabular-nums">
                    <Ltr>
                      {item.quantity} × {money(item.unitPrice, lang)}
                    </Ltr>
                  </p>
                </div>
              </li>
            ))}
          </ul>
        </Section>

        <Section title={t.after.col.reason}>
          <Fields>
            <Field label={t.after.col.reason}>{t.after.reason[r.reason] ?? r.reason}</Field>
            {r.description && (
              <Field label={t.after.theirWords}>
                <bdi>{r.description}</bdi>
              </Field>
            )}
            {r.rejectionReason && <Field label={t.after.storeReason}>{t.after.decline[r.rejectionReason] ?? r.rejectionReason}</Field>}
            <Field label={t.after.refund}>
              <span className="font-medium tabular-nums">{money(r.refundAmount, lang)}</span>
            </Field>
          </Fields>
          {!!r.photos?.length && (
            <div className="mt-4 flex flex-wrap gap-2">
              {r.photos.map((url) => (
                <a key={url} href={url} target="_blank" rel="noreferrer" className="block size-20 overflow-hidden rounded-xl border border-border">
                  <img src={url} alt={t.after.photo} className="size-full object-cover" />
                </a>
              ))}
            </div>
          )}
        </Section>

        <Section title={t.after.returnSteps}>
          <ol className="relative space-y-5 ps-6">
            <span className="absolute start-[7px] top-2 bottom-2 w-px bg-border" aria-hidden />
            {steps.map((step) => (
              <li key={step.label} className="relative">
                <span className={cn('absolute -start-6 top-1 size-[15px] rounded-full border-[3px] border-white', toneClass(step.tone).dot)} />
                <p className="text-[15px] font-medium text-navy">{step.label}</p>
                {step.at && (
                  <p className="flex items-center gap-1.5 text-[13px] text-muted-foreground">
                    <Clock className="size-3.5" />
                    {dateTime(step.at, lang)}
                  </p>
                )}
              </li>
            ))}
          </ol>
        </Section>

        <div className="grid gap-2 sm:grid-cols-2">
          <Button variant="outline" className="h-11 rounded-xl bg-white" onClick={() => sheet.open('order', r.orderId)}>
            <ReceiptText data-icon="inline-start" />
            {t.after.openOrder}
          </Button>
          <Button variant="outline" className="h-11 rounded-xl bg-white" onClick={() => sheet.open('store', r.merchantId)}>
            <Store data-icon="inline-start" />
            {t.support.storeDetails}
          </Button>
        </div>
      </Body>
    </>
  )
}
