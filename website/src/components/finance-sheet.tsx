import type { ReactNode } from 'react'
import { CircleCheck, Clock, Store, Wallet } from 'lucide-react'
import { MarkPaidButton, UndoPaidButton } from '@/components/actions'
import { Callout, EmptyState, StatusBadge, StoreBadge, Thumb, type Tone } from '@/components/blocks'
import { Body, Failed, Loading } from '@/components/detail-sheets'
import { Button } from '@/components/ui/button'
import { SheetDescription, SheetTitle } from '@/components/ui/sheet'
import { getStoreBills, type Bill, type BillStatus } from '@/data/finance'
import { date, money, monthName } from '@/lib/format'
import { useI18n } from '@/lib/i18n'
import { useSheet } from '@/lib/url-state'
import { useQuery } from '@/lib/use-query'

export const BILL_TONE = { OPEN: 'go', DUE: 'wait', PAID: 'ok', NONE: 'off' } as const satisfies Record<BillStatus, Tone>

export function BillBadge({ status }: { status: BillStatus }) {
  const { t } = useI18n()
  return <StatusBadge tone={BILL_TONE[status]}>{t.finance.status[status]}</StatusBadge>
}

/** One store's bills, month by month, opened from a Finance row (?bills=m-1). */
export function BillsDetail({ id }: { id: string }) {
  const { t, lang, city } = useI18n()
  const sheet = useSheet()
  const result = useQuery(() => getStoreBills(id), `bills:${id}`)

  if (result.error) return <Failed error={result.error} retry={result.retry} />
  if (!result.data) return <Loading />
  const { store, ratePercent, stillOwed } = result.data
  // As the app lists them: this month, and each earlier month that sold.
  const bills = result.data.bills.filter((b) => b.status === 'OPEN' || b.orderCount > 0 || b.returned > 0)

  return (
    <>
      <div className="px-7 pt-8">
        <div className="flex items-center gap-3.5">
          <Thumb src={store.logoUrl} name={store.storeName} round className="size-14" />
          <div className="min-w-0">
            <SheetTitle className="font-serif text-[28px] leading-tight font-normal text-navy">{store.storeName}</SheetTitle>
            <SheetDescription className="text-[15px] text-muted-foreground">
              {city(store.governorate)} · {t.finance.sheetText}
            </SheetDescription>
            {store.status !== 'APPROVED' && (
              <div className="mt-2">
                <StoreBadge status={store.status} />
              </div>
            )}
          </div>
        </div>
      </div>

      <Body>
        {stillOwed > 0 ? (
          <Callout tone="wait" icon={Wallet} title={t.finance.owesNow}>
            <span className="font-num text-2xl text-navy tabular-nums">{money(stillOwed, lang)}</span>
          </Callout>
        ) : (
          <Callout tone="ok" icon={CircleCheck}>
            {t.finance.owesNothing}
          </Callout>
        )}

        {bills.length === 0 ? (
          <EmptyState title={t.finance.noMonths} text={t.finance.noMonthsText} />
        ) : (
          bills.map((bill) => <MonthCard key={bill.month} bill={bill} rate={ratePercent} storeId={store.id} storeName={store.storeName} />)
        )}

        <Button variant="outline" className="h-11 w-full rounded-xl bg-white" onClick={() => sheet.open('store', store.id)}>
          <Store data-icon="inline-start" />
          {t.finance.storeDetails}
        </Button>
      </Body>
    </>
  )
}

function MonthCard({ bill, rate, storeId, storeName }: { bill: Bill; rate: number; storeId: string; storeName: string }) {
  const { t, lang } = useI18n()
  return (
    <section className="rounded-2xl border border-border bg-white p-5">
      <div className="mb-3 flex items-center justify-between gap-3">
        <h3 className="font-serif text-xl text-navy">{monthName(bill.month, lang)}</h3>
        <BillBadge status={bill.status} />
      </div>
      <dl className="space-y-2 text-[15px]">
        <Line label={`${t.finance.sales} · ${t.finance.orders(bill.orderCount)}`} value={money(bill.sales, lang)} />
        {bill.returned > 0 && <Line label={t.finance.returned} value={<span dir="ltr">−{money(bill.returned, lang)}</span>} />}
        <div className="flex items-baseline justify-between gap-4 border-t border-border pt-2.5">
          <dt className="font-medium text-navy">{t.finance.share(rate)}</dt>
          <dd className="font-num text-[22px] text-navy tabular-nums">{money(bill.owed, lang)}</dd>
        </div>
      </dl>
      {bill.status === 'DUE' && (
        <div className="mt-4">
          <MarkPaidButton storeId={storeId} storeName={storeName} bill={bill} />
        </div>
      )}
      {bill.status === 'PAID' && bill.paidAt && (
        <div className="mt-3 flex flex-wrap items-center justify-between gap-2">
          <p className="flex items-center gap-1.5 text-[13px] font-medium text-ok">
            <CircleCheck className="size-4" />
            {t.finance.paidOn(date(bill.paidAt, lang))}
          </p>
          <UndoPaidButton storeId={storeId} storeName={storeName} bill={bill} />
        </div>
      )}
      {bill.status === 'OPEN' && (
        <p className="mt-3 flex items-center gap-1.5 text-[13px] text-muted-foreground">
          <Clock className="size-4" />
          {t.finance.building}
        </p>
      )}
    </section>
  )
}

function Line({ label, value }: { label: string; value: ReactNode }) {
  return (
    <div className="flex justify-between gap-4">
      <dt className="text-muted-foreground">{label}</dt>
      <dd className="text-navy tabular-nums">{value}</dd>
    </div>
  )
}
