import { useState, type ReactNode } from 'react'
import { Link } from 'react-router'
import { Ban, ChevronLeft, ChevronRight, CircleX, Clock, EyeOff, Lock, Mail, Phone, ReceiptText, Star, Tag, Trash2, Truck, UserX, Zap } from 'lucide-react'
import { ProductActions, StoreActions } from '@/components/actions'
import { CustomerDetail } from '@/components/customer-sheet'
import { BillsDetail } from '@/components/finance-sheet'
import { ReturnDetail } from '@/components/return-sheet'
import { TicketDetail } from '@/components/ticket-sheet'
import {
  Callout,
  EmptyState,
  ErrorState,
  Field,
  Fields,
  IconBox,
  Ltr,
  ORDER_TONE,
  OrderBadge,
  Pager,
  ProductBadge,
  Section,
  SheetSkeleton,
  StatusBadge,
  StoreBadge,
  Thumb,
  toneClass,
  usePage,
} from '@/components/blocks'
import { Sheet, SheetContent, SheetDescription, SheetTitle } from '@/components/ui/sheet'
import { Skeleton } from '@/components/ui/skeleton'
import { getOrder } from '@/data/orders'
import { customerIdOf } from '@/data/people'
import { getProduct, listProducts } from '@/data/products'
import { getStore } from '@/data/stores'
import type { AdminOrder, AdminProduct, AdminStore } from '@/data/types'
import { ago, date, dateTime, money, number, phone } from '@/lib/format'
import { useI18n } from '@/lib/i18n'
import { useSheet, type SheetKind } from '@/lib/url-state'
import { useQuery } from '@/lib/use-query'
import { cn } from '@/lib/utils'

/** The one detail sheet, opened from any page by ?store= / ?product= / ?order=. */
export function DetailSheets() {
  const { t, dir } = useI18n()
  const sheet = useSheet()
  // Keep drawing the last one while the sheet slides away.
  const [shown, setShown] = useState<{ kind: SheetKind; id: string } | null>(null)
  if (sheet.kind && (shown?.kind !== sheet.kind || shown.id !== sheet.id)) {
    setShown({ kind: sheet.kind, id: sheet.id })
  }

  return (
    <Sheet open={!!sheet.kind} onOpenChange={(open) => !open && sheet.close()}>
      <SheetContent
        side={dir === 'rtl' ? 'left' : 'right'}
        // shadcn sizes the sheet under data-[side=...]; the width is overridden there.
        className="gap-0 overflow-y-auto border-border p-0 data-[side=left]:w-full data-[side=left]:sm:max-w-[620px] data-[side=right]:w-full data-[side=right]:sm:max-w-[620px] [&_[data-slot=sheet-close]]:z-10 [&_[data-slot=sheet-close]]:rounded-full [&_[data-slot=sheet-close]]:bg-white/90 [&_[data-slot=sheet-close]]:shadow-sm"
      >
        {/* Opened from another sheet (an order from its customer): the way back to it. */}
        {sheet.back && (
          // Above the header it tucks into, so the header never takes its click.
          <div className="relative z-10 -mb-4 w-fit px-5 pt-4">
            <button
              type="button"
              onClick={sheet.goBack}
              className="inline-flex h-8 items-center gap-1 rounded-full ps-1.5 pe-3 text-[13px] font-medium text-primary transition hover:bg-soft"
            >
              <ChevronLeft className="size-4 rtl:rotate-180" />
              {t.back}
            </button>
          </div>
        )}
        {shown?.kind === 'store' && <StoreDetail key={shown.id} id={shown.id} />}
        {shown?.kind === 'product' && <ProductDetail key={shown.id} id={shown.id} />}
        {shown?.kind === 'order' && <OrderDetail key={shown.id} id={shown.id} />}
        {shown?.kind === 'bills' && <BillsDetail key={shown.id} id={shown.id} />}
        {shown?.kind === 'ticket' && <TicketDetail key={shown.id} id={shown.id} />}
        {shown?.kind === 'return' && <ReturnDetail key={shown.id} id={shown.id} />}
        {shown?.kind === 'customer' && <CustomerDetail key={shown.id} id={shown.id} />}
      </SheetContent>
    </Sheet>
  )
}

export function Loading() {
  const { t } = useI18n()
  return (
    <>
      <SheetTitle className="sr-only">…</SheetTitle>
      <SheetDescription className="sr-only">{t.brand}</SheetDescription>
      <SheetSkeleton />
    </>
  )
}

export function Failed({ error, retry }: { error: unknown; retry: () => void }) {
  const { t } = useI18n()
  return (
    <div className="pt-16">
      <SheetTitle className="sr-only">{t.errors.title}</SheetTitle>
      <SheetDescription className="sr-only">{t.errors.title}</SheetDescription>
      <ErrorState error={error} onRetry={retry} />
    </div>
  )
}

function Footer({ children }: { children: ReactNode }) {
  return <div className="sticky bottom-0 mt-auto border-t border-border bg-white/95 px-7 py-4 backdrop-blur">{children}</div>
}

export function Body({ children }: { children: ReactNode }) {
  return <div className="space-y-4 px-7 pt-6 pb-8">{children}</div>
}

// ----------------------------------------------------------------- store ---

function StoreDetail({ id }: { id: string }) {
  const { t, lang, city } = useI18n()
  const store = useQuery(() => getStore(id), `store:${id}`)

  if (store.error) return <Failed error={store.error} retry={store.retry} />
  if (!store.data) return <Loading />
  const s: AdminStore = store.data
  // A closed store (its owner's account deleted) has no actions; a rejected one only the deletion, until it is asked.
  const acts = s.status !== 'CLOSED' && !(s.status === 'REJECTED' && s.deletionRequestedAt)
  const closed = s.status === 'CLOSED'

  return (
    <>
      <div className="relative h-40 shrink-0 overflow-hidden bg-surface-dark">
        {s.bannerUrl ? (
          <img src={s.bannerUrl} alt="" className="size-full object-cover" />
        ) : (
          <div className="size-full bg-[radial-gradient(90%_120%_at_100%_0%,color-mix(in_srgb,var(--primary)_55%,transparent),transparent_60%),radial-gradient(80%_100%_at_0%_100%,rgba(27,95,168,0.35),transparent_60%)]" />
        )}
        <div className="absolute inset-0 bg-gradient-to-t from-surface-dark/50 to-transparent" />
      </div>

      <div className="px-7">
        <Thumb src={s.logoUrl} name={s.storeName} className="relative -mt-10 size-20 rounded-2xl border-4 border-white bg-white text-2xl shadow-md" />
        <div className="mt-4 flex flex-wrap items-center gap-3">
          <SheetTitle className="font-serif text-[30px] leading-tight font-normal text-navy">{s.storeName}</SheetTitle>
          <StoreBadge status={s.status} />
        </div>
        <SheetDescription className="mt-1 text-[15px] text-muted-foreground">{city(s.governorate)}</SheetDescription>
      </div>

      <Body>
        {s.status === 'REJECTED' && s.rejectionReason && (
          <Callout tone="bad" icon={CircleX} title={t.store.rejectionReason}>
            <bdi>{s.rejectionReason}</bdi>
          </Callout>
        )}
        {s.status === 'SUSPENDED' && s.suspensionReason && (
          <Callout tone="off" icon={Ban} title={t.store.suspensionReason}>
            <bdi>{s.suspensionReason}</bdi>
          </Callout>
        )}
        {closed ? (
          <Callout tone="off" icon={UserX} title={s.closedAt ? t.store.closedOn(date(s.closedAt, lang)) : t.storeStatus.CLOSED}>
            {t.store.closedText}
          </Callout>
        ) : (
          s.deletionRequestedAt && (
            <Callout tone="wait" icon={Trash2} title={t.store.deletionRequested(date(s.deletionRequestedAt, lang))}>
              {t.store.deletionRequestedText}
            </Callout>
          )
        )}

        <Section title={t.store.about}>
          {s.description && <p className="text-[15px] leading-relaxed text-navy"><bdi>{s.description}</bdi></p>}
          {s.rating !== undefined && (
            <p className="mt-3 flex items-center gap-1.5 text-sm text-muted-foreground">
              <Star className="size-4 fill-heat text-heat" />
              <span className="font-semibold text-navy tabular-nums">{s.rating.toFixed(1)}</span>· {t.reviews(s.reviewCount)}
            </p>
          )}
        </Section>

        {!closed && (
          <Section title={t.store.owner}>
            <Fields>
              <Field label={t.store.owner}>{s.fullName}</Field>
              <Field label={t.store.phone}>
                <a href={`tel:${s.phone}`} className="inline-flex items-center gap-1.5 hover:text-primary">
                  <Phone className="size-3.5 text-faint" />
                  <Ltr className="tabular-nums">{phone(s.phone)}</Ltr>
                </a>
                {s.phoneVerified === false && (
                  <span className="mt-1.5 block">
                    <StatusBadge tone="wait">{t.number.unchecked}</StatusBadge>
                    <span className="mt-1 block text-[13px] text-wait">{t.number.uncheckedHint}</span>
                  </span>
                )}
              </Field>
              {s.email && (
                <Field label={t.store.email} wide>
                  <span className="inline-flex items-center gap-1.5">
                    <Mail className="size-3.5 text-faint" />
                    <Ltr>{s.email}</Ltr>
                  </span>
                </Field>
              )}
              <Field label={t.store.city}>{city(s.governorate)}</Field>
              <Field label={t.store.address}>
                <bdi>{s.businessAddress ?? '—'}</bdi>
              </Field>
            </Fields>
          </Section>
        )}

        <Section title={t.store.delivery}>
          {s.delivery ? (
            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-3">
                {[
                  [t.store.inside, s.delivery.feeInside, s.delivery.timeInside],
                  [t.store.outside, s.delivery.feeOutside, s.delivery.timeOutside],
                ].map(([label, fee, time]) => (
                  <div key={String(label)} className="rounded-xl bg-soft px-4 py-3">
                    <p className="text-[13px] text-muted-foreground">{label}</p>
                    <p className="mt-1 text-[15px] font-medium text-navy tabular-nums">{money(Number(fee), lang)}</p>
                    <p className="text-[13px] text-muted-foreground">{t.deliveryTime[String(time)] ?? time}</p>
                  </div>
                ))}
              </div>
              <div>
                <p className="mb-2 flex items-center gap-1.5 text-[13px] text-muted-foreground">
                  <Truck className="size-3.5" /> {t.store.deliversTo}
                </p>
                <div className="flex flex-wrap gap-1.5">
                  {s.delivery.governorates.map((g) => (
                    <span key={g} className="rounded-full border border-border px-2.5 py-1 text-[13px] text-navy">
                      {city(g)}
                    </span>
                  ))}
                </div>
              </div>
            </div>
          ) : (
            <p className="text-sm text-muted-foreground">{t.store.noDelivery}</p>
          )}
        </Section>

        <Section title={t.store.review}>
          <Fields>
            <Field label={t.store.applied}>
              {date(s.submittedAt, lang)} <span className="text-muted-foreground">· {ago(s.submittedAt, lang)}</span>
            </Field>
            <Field label={t.store.answered}>{s.answeredAt ? date(s.answeredAt, lang) : '—'}</Field>
          </Fields>
        </Section>

        <Section title={t.col.products} aside={<span className="text-[13px] text-muted-foreground">{t.store.productsText(s.productCount)}</span>}>
          <StoreProducts storeId={s.id} />
        </Section>
      </Body>

      {acts && (
        <Footer>
          <StoreActions store={s} size="sheet" />
        </Footer>
      )}
    </>
  )
}

function StoreProducts({ storeId }: { storeId: string }) {
  const { t, lang, pick } = useI18n()
  const sheet = useSheet()
  const [page, setPage] = usePage(storeId)
  const result = useQuery(() => listProducts({ storeId, page }), `store-products:${storeId}:${page}`)
  if (result.error) return <ErrorState error={result.error} onRetry={result.retry} />
  if (!result.data)
    return (
      <div className="space-y-3">
        {[0, 1, 2].map((i) => (
          <Skeleton key={i} className="h-14 rounded-xl" />
        ))}
      </div>
    )
  if (result.data.items.length === 0) return <EmptyState title={t.store.noProducts} text={t.store.noProductsText} />
  return (
    <>
      <ul className="-mx-2 divide-y divide-border/70">
        {result.data.items.map((p) => (
          <li key={p.id}>
            <button
              type="button"
              onClick={() => sheet.open('product', p.id)}
              className="flex w-full items-center gap-3 rounded-xl px-2 py-3 text-start transition hover:bg-soft"
            >
              <Thumb src={p.imageUrl} name={p.nameEn} className="size-10" />
              <span className="min-w-0 flex-1">
                <span className="block truncate text-sm font-medium text-navy">{pick(p.nameEn, p.nameAr)}</span>
                <span className="block text-[13px] text-muted-foreground tabular-nums">{money(p.price, lang)}</span>
              </span>
              <ProductBadge product={p} />
              <ChevronRight className="size-4 shrink-0 text-faint rtl:rotate-180" />
            </button>
          </li>
        ))}
      </ul>
      <Pager meta={result.data.meta} busy={result.loading} onPage={setPage} />
    </>
  )
}

// --------------------------------------------------------------- product ---

function inShop(p: AdminProduct, t: ReturnType<typeof useI18n>['t']): { yes: boolean; why?: string } {
  if (p.takenDown) return { yes: false, why: t.product.whyTakenDown }
  if (p.status === 'PENDING') return { yes: false, why: t.product.whyPending }
  if (p.status !== 'APPROVED') return { yes: false, why: t.product.whyRejected }
  if (p.merchant.status !== 'APPROVED') return { yes: false, why: t.product.whyStore }
  if (!p.isActive) return { yes: false, why: t.product.whyStoreOff }
  // Only the server knows its store has closed.
  if (p.notInShopReason === 'STORE_CLOSED') return { yes: false, why: t.product.whyStoreClosed }
  return { yes: true }
}

function ProductDetail({ id }: { id: string }) {
  const { t, lang, pick } = useI18n()
  const sheet = useSheet()
  const product = useQuery(() => getProduct(id), `product:${id}`)
  const [photo, setPhoto] = useState(0)

  if (product.error) return <Failed error={product.error} retry={product.retry} />
  if (!product.data) return <Loading />
  const p = product.data
  const shop = inShop(p, t)
  const main = pick(p.nameEn, p.nameAr)
  const other = lang === 'ar' ? p.nameEn : p.nameAr
  const acts = p.status === 'PENDING' || p.status === 'APPROVED'

  return (
    <>
      <div className="px-7 pt-7">
        <div className="overflow-hidden rounded-2xl border border-border bg-soft">
          {p.images[photo] ? (
            <img src={p.images[photo].url} alt={main} className="aspect-[16/10] w-full object-cover" />
          ) : (
            <Thumb name={main} className="aspect-[16/10] h-auto w-full rounded-none text-5xl" />
          )}
        </div>
        {p.images.length > 1 && (
          <div className="mt-3 flex gap-2">
            {p.images.map((image, i) => (
              <button
                key={image.id}
                type="button"
                onClick={() => setPhoto(i)}
                aria-pressed={i === photo}
                className={cn('overflow-hidden rounded-xl border-2 transition', i === photo ? 'border-primary' : 'border-transparent opacity-70 hover:opacity-100')}
              >
                <img src={image.url} alt="" className="size-14 object-cover" />
              </button>
            ))}
          </div>
        )}

        <div className="mt-5 flex flex-wrap items-center gap-3">
          <SheetTitle className="font-serif text-[28px] leading-tight font-normal text-navy">{main}</SheetTitle>
          <ProductBadge product={p} />
        </div>
        <SheetDescription className="mt-1 text-[15px] text-muted-foreground" dir={lang === 'ar' ? 'ltr' : 'rtl'}>
          {other || '—'}
        </SheetDescription>

        <div className="mt-4 flex flex-wrap items-end justify-between gap-3">
          <div className="flex items-baseline gap-3">
            <span className="font-num text-[32px] leading-none text-navy tabular-nums">{money(p.price, lang)}</span>
            {p.originalPrice !== undefined && (
              <span className="text-sm text-muted-foreground line-through tabular-nums">{money(p.originalPrice, lang)}</span>
            )}
            {p.discountPercentage !== undefined && (
              <span className="rounded-md bg-heat px-2 py-0.5 text-[12px] font-semibold text-navy tabular-nums">
                <Ltr>−{p.discountPercentage}%</Ltr>
              </span>
            )}
          </div>
          <span
            className={cn(
              'inline-flex items-center gap-2 rounded-full px-3 py-1.5 text-[13px] font-medium',
              shop.yes ? 'bg-ok-soft text-ok' : 'bg-off-soft text-off',
            )}
            title={shop.why}
          >
            <span className={cn('size-2 rounded-full', shop.yes ? 'bg-ok' : 'bg-[#8a99ab]')} />
            {shop.yes ? t.product.inShop : `${t.product.notInShop} · ${shop.why}`}
          </span>
        </div>
      </div>

      <Body>
        {p.status === 'REJECTED' && p.rejectionReason && (
          <Callout tone="bad" icon={CircleX} title={t.product.rejectionReason}>
            <bdi>{p.rejectionReason}</bdi>
          </Callout>
        )}
        {p.takenDown && p.takenDownReason && (
          <Callout tone="off" icon={EyeOff} title={t.product.takenDownReason}>
            <bdi>{p.takenDownReason}</bdi>
          </Callout>
        )}

        <Section title={t.product.names}>
          <Fields>
            <Field label={t.product.nameEn}>
              <span dir="ltr">{p.nameEn || '—'}</span>
            </Field>
            <Field label={t.product.nameAr}>
              {p.nameAr ? (
                <span dir="rtl" lang="ar">
                  {p.nameAr}
                </span>
              ) : (
                <span className="text-bad">{t.product.noArabic}</span>
              )}
            </Field>
          </Fields>
        </Section>

        <Section title={t.product.details}>
          <Fields>
            <Field label={t.product.category}>{pick(p.categoryName, p.categoryNameAr)}</Field>
            <Field label={t.product.brand}>
              {p.brand ? (
                <>
                  <bdi>{p.brand.name}</bdi>
                  {p.brand.nameAr && (
                    <>
                      {' · '}
                      <bdi dir="rtl">{p.brand.nameAr}</bdi>
                    </>
                  )}
                </>
              ) : (
                '—'
              )}
            </Field>
            <Field label={t.product.stock}>
              <span className="tabular-nums">{t.product.left(p.availableQuantity)}</span>
              <span className={cn('ms-2 text-[13px]', p.stockStatus === 'IN_STOCK' ? 'text-ok' : p.stockStatus === 'LOW_STOCK' ? 'text-wait' : 'text-bad')}>
                · {t.stock[p.stockStatus]}
              </span>
            </Field>
            <Field label={t.product.sent}>{date(p.createdAt, lang)}</Field>
          </Fields>
          {p.brand?.isNew && (
            <div className="mt-4">
              <Callout tone="wait" icon={Tag} title={t.product.brandNew}>
                <p>{t.product.brandNewText}</p>
                <Link to={`/brands?status=PENDING&q=${encodeURIComponent(p.brand.name)}`} className="mt-2 inline-block font-semibold underline underline-offset-2">
                  {t.product.openBrands}
                </Link>
              </Callout>
            </div>
          )}
        </Section>

        <Section title={t.product.store}>
          <button
            type="button"
            onClick={() => sheet.open('store', p.merchant.id)}
            className="-m-2 flex w-[calc(100%+1rem)] items-center gap-3 rounded-xl p-2 text-start transition hover:bg-soft"
          >
            <Thumb name={p.merchant.storeName} className="size-10" />
            <span className="flex-1 truncate text-[15px] font-medium text-navy">{p.merchant.storeName}</span>
            <StoreBadge status={p.merchant.status} />
            <ChevronRight className="size-4 text-faint rtl:rotate-180" />
          </button>
        </Section>

        {p.variants.length > 0 && (
          <Section title={t.product.options}>
            <div className="-mx-1 overflow-x-auto">
              <table className="w-full text-sm">
                <tbody className="divide-y divide-border/70">
                  {p.variants.map((v) => (
                    <tr key={v.id}>
                      <td className="px-1 py-2.5 text-navy">{Object.values(v.options).join(' / ')}</td>
                      <td className="px-1 py-2.5 text-end tabular-nums">
                        {money(v.price, lang)}
                        {v.originalPrice !== undefined && (
                          <div className="text-[13px] text-faint line-through">{money(v.originalPrice, lang)}</div>
                        )}
                      </td>
                      <td className={cn('px-1 py-2.5 text-end tabular-nums', v.availableQuantity === 0 && 'text-bad')}>
                        {number(v.availableQuantity)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </Section>
        )}

        <Section title={t.product.description}>
          <p className="text-[15px] leading-relaxed text-navy">
            <bdi>{p.description ?? '—'}</bdi>
          </p>
          {p.warranty && (
            <p className="mt-3 text-sm text-muted-foreground">
              {t.product.warranty}: <bdi>{p.warranty}</bdi>
            </p>
          )}
        </Section>
      </Body>

      {acts && (
        <Footer>
          <ProductActions product={p} size="sheet" />
        </Footer>
      )}
    </>
  )
}

// ----------------------------------------------------------------- order ---

function OrderDetail({ id }: { id: string }) {
  const { t, lang, city, pick } = useI18n()
  const sheet = useSheet()
  const order = useQuery(() => getOrder(id), `order:${id}`)

  if (order.error) return <Failed error={order.error} retry={order.retry} />
  if (!order.data) return <Loading />
  const o: AdminOrder = order.data
  const address = o.shippingAddress
  const byStore = new Map<string, AdminOrder['items']>()
  for (const item of o.items) byStore.set(item.merchantName, [...(byStore.get(item.merchantName) ?? []), item])

  // Each store sends its own driver, named when it ships its part. A part not
  // shipped yet says so; a cancelled or refused one never will name anyone.
  const drivers = o.storeParts.filter((p) => p.courierName || ['PENDING', 'CONFIRMED', 'PROCESSING'].includes(p.status))
  const storeName = (id: string) => o.items.find((item) => item.merchantId === id)?.merchantName ?? id

  return (
    <>
      <div className="px-7 pt-8">
        <div className="flex items-center gap-3.5">
          <IconBox icon={ReceiptText} className="size-12 rounded-2xl" />
          <div className="min-w-0">
            <SheetTitle className="font-num text-[30px] leading-tight font-normal text-navy">
              <Ltr>{o.orderNumber}</Ltr>
            </SheetTitle>
            <SheetDescription className="text-[15px] text-muted-foreground">
              {dateTime(o.placedAt, lang)} · {ago(o.placedAt, lang)}
            </SheetDescription>
          </div>
        </div>
        <div className="mt-4 flex flex-wrap gap-2">
          <OrderBadge status={o.status} />
          <StatusBadge tone={o.paymentStatus === 'PAID' ? 'ok' : 'off'}>{t.payment[o.paymentStatus]}</StatusBadge>
        </div>
      </div>

      <Body>
        <Callout tone="go" icon={Lock}>
          {t.order.readOnly}
        </Callout>
        {o.status === 'CANCELLED' && o.cancelReason && (
          <Callout tone="bad" icon={CircleX} title={o.cancelledBy ? t.after.by[o.cancelledBy] : t.orderStatus.CANCELLED}>
            {t.after.reason[o.cancelReason] ?? o.cancelReason}
            {o.cancelNote && (
              <>
                {' · '}
                <bdi>{o.cancelNote}</bdi>
              </>
            )}
          </Callout>
        )}

        <Section
          title={t.order.customer}
          aside={
            <button type="button" onClick={() => sheet.open('customer', o.customerId ?? customerIdOf(o.customerPhone))} className="inline-flex items-center gap-1 text-[13px] font-medium text-primary hover:underline">
              {t.customers.customerDetails}
              <ChevronRight className="size-3.5 rtl:rotate-180" />
            </button>
          }
        >
          <Fields>
            <Field label={t.order.customer}>{o.customerName}</Field>
            <Field label={t.store.phone}>
              <a href={`tel:${o.customerPhone}`} className="inline-flex items-center gap-1.5 hover:text-primary">
                <Phone className="size-3.5 text-faint" />
                <Ltr className="tabular-nums">{phone(o.customerPhone)}</Ltr>
              </a>
            </Field>
            <Field label={t.order.address} wide>
              <bdi>{[address.street, address.area].filter(Boolean).join(', ')}</bdi>
              {lang === 'ar' ? '، ' : ', '}
              {city(address.governorate)}
            </Field>
            {address.landmark && (
              <Field label={t.order.landmark} wide>
                <bdi>{address.landmark}</bdi>
              </Field>
            )}
          </Fields>
        </Section>

        <Section title={t.order.items} aside={<span className="text-[13px] text-muted-foreground">{t.items(o.itemCount)}</span>}>
          <div className="space-y-5">
            {[...byStore.entries()].map(([storeName, items]) => (
              <div key={storeName}>
                <p className="mb-1 text-[13px] font-semibold text-navy">{storeName}</p>
                <ul className="divide-y divide-border/70">
                  {items.map((item) => (
                    <li key={item.id} className="flex items-center gap-3 py-3">
                      <Thumb src={item.imageUrl} name={item.productName} className="size-11" />
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-[15px] text-navy">{pick(item.productName, item.productNameAr)}</p>
                        {item.variantLabel && (
                          <p className="truncate text-[13px] text-muted-foreground">
                            <bdi>{item.variantLabel}</bdi>
                          </p>
                        )}
                        <p className="text-[13px] text-muted-foreground tabular-nums">
                          <Ltr>
                            {item.quantity} × {money(item.unitPrice, lang)}
                          </Ltr>
                        </p>
                      </div>
                      <span className="text-[15px] font-medium text-navy tabular-nums">{money(item.lineTotal, lang)}</span>
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </div>

          <dl className="mt-4 space-y-2 rounded-xl bg-soft px-4 py-4 text-[15px]">
            <Line label={t.order.subtotal} value={money(o.subtotal, lang)} />
            <Line label={t.order.shipping} value={money(o.shipping, lang)} />
            {o.discount > 0 && <Line label={t.order.discount} value={<Ltr>−{money(o.discount, lang)}</Ltr>} />}
            <div className="mt-2 flex items-baseline justify-between border-t border-border pt-3">
              <dt className="font-medium text-navy">{t.order.total}</dt>
              <dd className="font-num text-2xl text-navy tabular-nums">{money(o.total, lang)}</dd>
            </div>
          </dl>
        </Section>

        <Section title={t.order.payment}>
          <Fields>
            <Field label={t.order.payment}>{o.isCashOnDelivery ? t.order.cash : o.paymentMethodLabel}</Field>
          </Fields>
        </Section>

        {drivers.length > 0 && (
          <Section title={t.order.courier}>
            <div className="space-y-5">
              {drivers.map((part) => (
                <div key={part.merchantId}>
                  {/* Named by store only when there is more than one. */}
                  {o.storeParts.length > 1 && <p className="mb-1 text-[13px] font-semibold text-navy">{storeName(part.merchantId)}</p>}
                  {part.courierName ? (
                    <Fields>
                      <Field label={t.order.driver}>
                        <bdi>{part.courierName}</bdi>
                      </Field>
                      {part.courierPhone && (
                        <Field label={t.store.phone}>
                          <a href={`tel:${part.courierPhone}`} className="inline-flex items-center gap-1.5 hover:text-primary">
                            <Phone className="size-3.5 text-faint" />
                            <Ltr className="tabular-nums">{phone(part.courierPhone)}</Ltr>
                          </a>
                        </Field>
                      )}
                    </Fields>
                  ) : (
                    <p className="flex items-center gap-2 text-[15px] text-muted-foreground">
                      <Truck className="size-4 shrink-0 text-faint" />
                      {t.order.noCourier}
                    </p>
                  )}
                </div>
              ))}
            </div>
          </Section>
        )}

        <Section title={t.order.history}>
          <ol className="relative space-y-5 ps-6">
            <span className="absolute start-[7px] top-2 bottom-2 w-px bg-border" aria-hidden />
            {o.timeline.map((step, i) => (
              <li key={i} className="relative">
                <span className={cn('absolute -start-6 top-1 size-[15px] rounded-full border-[3px] border-white', toneClass(ORDER_TONE[step.status]).dot)} />
                <p className="text-[15px] font-medium text-navy">
                  {i === 0 ? t.order.placed : t.orderStatus[step.status]}
                  {/* Which store took this step: two stores each confirm, ship and deliver their own part. */}
                  {step.storeName && (
                    <span className="font-normal text-muted-foreground">
                      {' · '}
                      <bdi>{step.storeName}</bdi>
                    </span>
                  )}
                </p>
                <p className="flex items-center gap-1.5 text-[13px] text-muted-foreground">
                  <Clock className="size-3.5" />
                  {dateTime(step.occurredAt, lang)}
                </p>
                {step.noteCode === 'AUTO_DELIVERED' && (
                  <p className="mt-1.5 inline-flex items-start gap-1.5 rounded-lg bg-soft px-2.5 py-1.5 text-[13px] leading-snug text-navy">
                    <Zap className="mt-0.5 size-3.5 shrink-0 text-primary" />
                    {t.order.autoDelivered}
                  </p>
                )}
              </li>
            ))}
          </ol>
        </Section>
      </Body>
    </>
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
