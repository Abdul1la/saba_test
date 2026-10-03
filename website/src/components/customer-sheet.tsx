import { Ban, ChevronRight, MapPin, Phone, UserX } from 'lucide-react'
import { CustomerActions } from '@/components/actions'
import { Callout, EmptyState, Field, Fields, Ltr, OrderBadge, Section, StatusBadge, Thumb } from '@/components/blocks'
import { Body, Failed, Loading } from '@/components/detail-sheets'
import { SheetDescription, SheetTitle } from '@/components/ui/sheet'
import { getCustomer, type CustomerStatus } from '@/data/customers'
import { ApiError } from '@/data/mock'
import { date, money, number, phone } from '@/lib/format'
import { useI18n } from '@/lib/i18n'
import { useSheet } from '@/lib/url-state'
import { useQuery } from '@/lib/use-query'

export function CustomerBadge({ status }: { status: CustomerStatus }) {
  const { t } = useI18n()
  return <StatusBadge tone={status === 'ACTIVE' ? 'ok' : 'off'}>{t.customers.status[status]}</StatusBadge>
}

/** One shopper (?customer=cu-5550142): details, addresses, orders. */
export function CustomerDetail({ id }: { id: string }) {
  const { t, lang, city, pick } = useI18n()
  const sheet = useSheet()
  const result = useQuery(() => getCustomer(id), `customer:${id}`)

  // A shopper who deleted their account is wiped and left out: their orders still open, their details don't.
  if (result.error instanceof ApiError && result.error.code === 'NOT_FOUND')
    return (
      <div className="pt-16">
        <SheetTitle className="sr-only">{t.customers.gone}</SheetTitle>
        <SheetDescription className="sr-only">{t.customers.goneText}</SheetDescription>
        <EmptyState icon={UserX} title={t.customers.gone} text={t.customers.goneText} />
      </div>
    )
  if (result.error) return <Failed error={result.error} retry={result.retry} />
  if (!result.data) return <Loading />
  const c = result.data
  const name = pick(c.fullName, c.fullNameAr)

  return (
    <>
      <div className="px-7 pt-8">
        <div className="flex items-center gap-3.5">
          <Thumb name={c.fullName} round className="size-14 text-xl" />
          <div className="min-w-0">
            <div className="flex flex-wrap items-center gap-3">
              <SheetTitle className="font-serif text-[28px] leading-tight font-normal text-navy">{name}</SheetTitle>
              <CustomerBadge status={c.status} />
              {c.phoneVerified === false && <StatusBadge tone="wait">{t.number.unchecked}</StatusBadge>}
            </div>
            <SheetDescription className="text-[15px] text-muted-foreground">
              {city(c.governorate)} · <Ltr className="tabular-nums">{phone(c.phone)}</Ltr>
            </SheetDescription>
          </div>
        </div>
      </div>

      <Body>
        {c.status === 'SUSPENDED' && c.suspensionReason && (
          <Callout tone="off" icon={Ban} title={t.customers.suspensionReason}>
            <bdi>{c.suspensionReason}</bdi>
          </Callout>
        )}

        <Section title={t.customers.details}>
          <Fields>
            <Field label={t.store.phone}>
              <a href={`tel:${c.phone}`} className="inline-flex items-center gap-1.5 hover:text-primary">
                <Phone className="size-3.5 text-faint" />
                <Ltr className="tabular-nums">{phone(c.phone)}</Ltr>
              </a>
              {c.phoneVerified === false && <p className="mt-1 text-[13px] text-wait">{t.number.uncheckedHint}</p>}
            </Field>
            <Field label={t.customers.col.joined}>{date(c.joinedAt, lang)}</Field>
            <Field label={t.customers.col.orders}>
              <span className="tabular-nums">{number(c.orderCount)}</span>
            </Field>
            <Field label={t.customers.col.spent}>
              <span className="font-medium tabular-nums">{money(c.spent, lang)}</span>
              <span className="block text-[13px] text-muted-foreground">{t.customers.spentText}</span>
            </Field>
          </Fields>
        </Section>

        <Section title={t.customers.addresses}>
          <ul className="space-y-3">
            {c.addresses.map((a) => (
              <li key={a.id} className="flex gap-3 rounded-xl bg-soft px-4 py-3">
                <MapPin className="mt-0.5 size-4 shrink-0 text-faint" />
                <div className="min-w-0 text-[15px] text-navy">
                  <p className="flex items-center gap-2 font-medium">
                    {t.customers.home[a.label] ?? a.label}
                    {a.isDefault && <StatusBadge tone="go">{t.customers.isDefault}</StatusBadge>}
                  </p>
                  <p>
                    <bdi>{[pick(a.street, a.streetAr), pick(a.area, a.areaAr)].filter(Boolean).join(lang === 'ar' ? '، ' : ', ')}</bdi>
                    {lang === 'ar' ? '، ' : ', '}
                    {city(a.governorate)}
                  </p>
                  <p className="text-[13px] text-muted-foreground">
                    <bdi>{pick(a.landmark, a.landmarkAr)}</bdi>
                  </p>
                </div>
              </li>
            ))}
          </ul>
        </Section>

        <Section title={t.customers.ordersTitle} aside={<span className="text-[13px] text-muted-foreground">{number(c.orders.length)}</span>}>
          {c.orders.length === 0 ? (
            <EmptyState title={t.customers.noOrders} text={t.customers.noOrdersText} />
          ) : (
            <ul className="-mx-2 divide-y divide-border/70">
              {c.orders.map((o) => (
                <li key={o.id}>
                  <button
                    type="button"
                    onClick={() => sheet.open('order', o.id)}
                    className="flex w-full items-center gap-3 rounded-xl px-2 py-3 text-start transition hover:bg-soft"
                  >
                    <Thumb src={o.items[0]?.imageUrl} name={o.items[0]?.productName ?? '?'} className="size-10" />
                    <span className="min-w-0 flex-1">
                      <span className="block truncate text-sm font-medium text-navy">
                        <Ltr>{o.orderNumber}</Ltr> · <bdi>{o.merchantNames.join(', ')}</bdi>
                      </span>
                      <span className="block text-[13px] text-muted-foreground tabular-nums">
                        {date(o.placedAt, lang)} · {money(o.total, lang)}
                      </span>
                    </span>
                    <OrderBadge status={o.status} />
                    <ChevronRight className="size-4 shrink-0 text-faint rtl:rotate-180" />
                  </button>
                </li>
              ))}
            </ul>
          )}
        </Section>
      </Body>

      <div className="sticky bottom-0 mt-auto border-t border-border bg-white/95 px-7 py-4 backdrop-blur">
        <CustomerActions customer={c} size="sheet" />
      </div>
    </>
  )
}
