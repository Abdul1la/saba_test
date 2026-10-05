import { useState } from 'react'
import { ClipboardCheck, Hourglass, Package, PackageCheck, Store, Timer, Zap } from 'lucide-react'
import { ProductActions, StoreActions, useRun } from '@/components/actions'
import {
  ContentCard,
  EmptyState,
  ErrorState,
  FilterChips,
  Ltr,
  NameCell,
  PageIntro,
  StatCard,
  StatRow,
  TableSkeleton,
  Thumb,
  card,
  row,
  showList,
  td,
  th,
} from '@/components/blocks'
import { Switch } from '@/components/form'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { getQueue, type Queue } from '@/data/queue'
import { changeSettings, getSettings } from '@/data/settings'
import { ago, isLate, money, phone } from '@/lib/format'
import { useI18n } from '@/lib/i18n'
import { useSheet, useUrlFilters } from '@/lib/url-state'
import { useQuery } from '@/lib/use-query'
import { cn } from '@/lib/utils'

const SECTIONS = ['stores', 'products'] as const
type Section = (typeof SECTIONS)[number]

/** Which section holds the item that has waited longest; both lists are oldest first. */
function oldestIn(data: Queue): { section: Section; since: string } | undefined {
  const store = data.stores[0]?.submittedAt
  const product = data.products[0]?.createdAt
  if (store && (!product || store <= product)) return { section: 'stores', since: store }
  if (product) return { section: 'products', since: product }
  return undefined
}

export function QueuePage() {
  const { t, lang } = useI18n()
  const queue = useQuery(getQueue, 'queue')
  const data = queue.data
  const oldest = data && oldestIn(data)
  const [filters, setFilters] = useUrlFilters({ show: SECTIONS })
  const show = filters.show as Section | ''
  const count = (n?: number) => (queue.error ? '—' : n)
  /** Show one section (or both) and scroll to it, as the other pages' cards do. */
  const reveal = (next: Section | '') => {
    setFilters({ show: next })
    showList()
  }

  return (
    <>
      <PageIntro>{t.queue.intro}</PageIntro>
      <StatRow>
        <StatCard
          label={t.queue.total}
          value={count(data && data.stores.length + data.products.length)}
          icon={ClipboardCheck}
          onClick={() => reveal('')}
          active={!show}
        />
        <StatCard
          label={t.queue.stores}
          value={count(data?.stores.length)}
          icon={Store}
          onClick={() => reveal('stores')}
          active={show === 'stores'}
        />
        <StatCard
          label={t.queue.products}
          value={count(data?.products.length)}
          icon={Package}
          onClick={() => reveal('products')}
          active={show === 'products'}
        />
        {/* A jump, not a filter: it opens the section where the oldest waits, first in its list. */}
        <StatCard
          label={t.queue.oldest}
          value={
            queue.error
              ? '—'
              : data && (
                  <span className={cn('text-[22px] sm:text-[30px]', oldest && isLate(oldest.since) && 'text-wait')}>
                    {oldest ? ago(oldest.since, lang) : t.queue.nothing}
                  </span>
                )
          }
          icon={Timer}
          onClick={oldest && (() => reveal(oldest.section))}
        />
      </StatRow>

      <div id="list" className="scroll-mt-28 space-y-6">
        <FilterChips
          label={t.queue.total}
          value={show}
          onChange={(next) => setFilters({ show: next })}
          chips={[
            { value: '', label: t.all, count: data && data.stores.length + data.products.length },
            { value: 'stores', label: t.nav.stores, count: data?.stores.length },
            { value: 'products', label: t.nav.products, count: data?.products.length },
          ]}
        />

        {show !== 'products' && (
          <ContentCard icon={Store} title={t.queue.storesTitle} description={t.queue.storesText}>
            {queue.error ? (
              <ErrorState error={queue.error} onRetry={queue.retry} />
            ) : !data ? (
              <TableSkeleton rows={2} columns={3} />
            ) : data.stores.length === 0 ? (
              <EmptyState icon={PackageCheck} title={t.queue.emptyStores} text={t.queue.emptyStoresText} />
            ) : (
              <StoresWaiting data={data} dim={queue.loading} />
            )}
          </ContentCard>
        )}

        {show !== 'stores' && (
          <ContentCard icon={Package} title={t.queue.productsTitle} description={t.queue.productsText} actions={<AutoApprove />}>
            {queue.error ? (
              <ErrorState error={queue.error} onRetry={queue.retry} />
            ) : !data ? (
              <TableSkeleton rows={4} columns={4} />
            ) : data.products.length === 0 ? (
              <EmptyState icon={PackageCheck} title={t.queue.emptyProducts} text={t.queue.emptyProductsText} />
            ) : (
              <ProductsWaiting data={data} dim={queue.loading} />
            )}
          </ContentCard>
        )}
      </div>
    </>
  )
}

/** Saba's switch: on, a store's new or changed product skips this queue and goes live at once. */
function AutoApprove() {
  const { t } = useI18n()
  const settings = useQuery(getSettings, 'settings')
  const run = useRun()
  const [busy, setBusy] = useState(false)
  const on = settings.data?.autoApproveProducts
  // Not known yet, or not answered: no switch rather than a wrong one.
  if (on === undefined) return null
  const turn = async (next: boolean) => {
    setBusy(true)
    await run(() => changeSettings({ autoApproveProducts: next }), next ? t.queue.autoApproveTurnedOn : t.queue.autoApproveTurnedOff)
    setBusy(false)
  }
  return (
    <div
      className={cn(
        'flex w-full max-w-[420px] items-center gap-3 rounded-2xl border px-4 py-3 transition-colors sm:w-auto',
        on ? 'border-primary/30 bg-primary/5' : 'border-border bg-soft',
      )}
    >
      <span className={cn('grid size-9 shrink-0 place-items-center rounded-xl', on ? 'bg-primary text-white' : 'bg-card text-muted-foreground')}>
        <Zap className="size-4" strokeWidth={2} />
      </span>
      <span className="min-w-0 flex-1">
        <span className="block text-[14px] font-semibold text-navy">{t.queue.autoApprove}</span>
        <span className="block text-[13px] leading-snug text-muted-foreground">{on ? t.queue.autoApproveOn : t.queue.autoApproveOff}</span>
      </span>
      <Switch on={on} label={t.queue.autoApprove} disabled={busy || settings.loading} onChange={turn} />
    </div>
  )
}

function Waited({ since }: { since: string }) {
  const { lang } = useI18n()
  return (
    <span className={cn('inline-flex items-center gap-1.5 text-[14px]', isLate(since) ? 'font-medium text-wait' : 'text-muted-foreground')}>
      <Hourglass className="size-3.5" strokeWidth={1.75} />
      {ago(since, lang)}
    </span>
  )
}

function StoresWaiting({ data, dim }: { data: Queue; dim: boolean }) {
  const { t, city } = useI18n()
  const sheet = useSheet()
  return (
    <Table className={cn('transition-opacity', card.table, dim && 'opacity-60')}>
      <TableHeader>
        <TableRow className="border-border hover:bg-transparent">
          <TableHead className={th}>{t.col.store}</TableHead>
          <TableHead className={th}>{t.col.owner}</TableHead>
          <TableHead className={th}>{t.col.waiting}</TableHead>
          <TableHead className={th} />
        </TableRow>
      </TableHeader>
      <TableBody>
        {data.stores.map((s) => (
          <TableRow key={s.id} className={row} onClick={() => sheet.open('store', s.id)}>
            <TableCell className={td}>
              <NameCell
                thumb={<Thumb src={s.logoUrl} name={s.storeName} round />}
                title={
                  <button type="button" className="max-w-full truncate text-start outline-none focus-visible:underline">
                    {s.storeName}
                  </button>
                }
                subtitle={city(s.governorate)}
              />
            </TableCell>
            <TableCell className={cn(td, card.hide)}>
              <div className="text-[15px] text-navy">{s.fullName}</div>
              <Ltr className="text-[13px] text-muted-foreground tabular-nums">{phone(s.phone)}</Ltr>
            </TableCell>
            <TableCell className={td}>
              <Waited since={s.submittedAt} />
            </TableCell>
            <TableCell className={cn(td, card.end)}>
              <StoreActions store={s} />
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  )
}

function ProductsWaiting({ data, dim }: { data: Queue; dim: boolean }) {
  const { t, lang, pick } = useI18n()
  const sheet = useSheet()
  return (
    <Table className={cn('transition-opacity', card.table, dim && 'opacity-60')}>
      <TableHeader>
        <TableRow className="border-border hover:bg-transparent">
          <TableHead className={th}>{t.col.product}</TableHead>
          <TableHead className={th}>{t.col.store}</TableHead>
          <TableHead className={cn(th, 'text-end')}>{t.col.price}</TableHead>
          <TableHead className={th}>{t.col.waiting}</TableHead>
          <TableHead className={th} />
        </TableRow>
      </TableHeader>
      <TableBody>
        {data.products.map((p) => (
          <TableRow key={p.id} className={row} onClick={() => sheet.open('product', p.id)}>
            <TableCell className={cn(td, 'max-w-[340px]')}>
              <NameCell
                thumb={<Thumb src={p.imageUrl} name={p.nameEn} />}
                title={
                  <button type="button" className="max-w-full truncate text-start outline-none focus-visible:underline">
                    {pick(p.nameEn, p.nameAr)}
                  </button>
                }
                subtitle={pick(p.categoryName, p.categoryNameAr)}
              />
            </TableCell>
            <TableCell className={cn(td, card.hide, 'text-[15px] text-navy')}>{p.merchant.storeName}</TableCell>
            <TableCell className={cn(td, card.line, 'text-end text-[15px] font-medium text-navy tabular-nums')}>{money(p.price, lang)}</TableCell>
            <TableCell className={td}>
              <Waited since={p.createdAt} />
            </TableCell>
            <TableCell className={cn(td, card.end)}>
              <ProductActions product={p} />
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  )
}
