import { useEffect, useState, type ComponentType, type ReactNode } from 'react'
import { Link } from 'react-router'
import { cn } from '@/lib/utils'
import { ChevronLeft, ChevronRight, Eye, Inbox, RefreshCw, Search, TriangleAlert, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import { TableHead } from '@/components/ui/table'
import { ApiError } from '@/data/mock'
import type { AdminProduct, OrderStatus, PageMeta, StoreStatus } from '@/data/types'
import type { ProductFilter } from '@/data/products'
import { useI18n, type Strings } from '@/lib/i18n'
import { initials, number } from '@/lib/format'

type Icon = ComponentType<{ className?: string; strokeWidth?: number }>

// ---------------------------------------------------------------- layout ---

export function PageIntro({ children }: { children: ReactNode }) {
  return <p className="mb-7 text-[15px] text-muted-foreground">{children}</p>
}

export function StatRow({ children, className }: { children: ReactNode; className?: string }) {
  return <div className={cn('mb-8 grid grid-cols-2 gap-4 xl:grid-cols-4', className)}>{children}</div>
}

/**
 * Small label, big serif number, outlined icon in the corner. With `onClick`
 * it filters the list below; with `to` it opens another page's list.
 * `active` marks the card whose filter is on.
 */
export function StatCard({
  label,
  value,
  icon: IconCmp,
  onClick,
  to,
  active = false,
}: {
  label: string
  value?: ReactNode
  icon: Icon
  onClick?: () => void
  to?: string
  active?: boolean
}) {
  const className = cn(
    'group relative block rounded-2xl border border-border bg-accent-soft px-5 pt-5 pb-6 text-start',
    (onClick || to) &&
      'cursor-pointer transition duration-200 outline-none hover:-translate-y-0.5 hover:border-primary/35 hover:bg-white hover:shadow-[0_12px_28px_-16px_rgba(14,26,43,0.35)] focus-visible:ring-4 focus-visible:ring-primary/20',
    // Stronger than the hover, so "this filter is on" never reads as "the mouse is here".
    active && 'border-primary bg-white shadow-[0_12px_28px_-18px_color-mix(in_srgb,var(--primary)_55%,transparent)] ring-1 ring-primary hover:border-primary',
  )
  // Spans only: this may sit inside a button or a link.
  const body = (
    <>
      <span className="flex items-start justify-between gap-3">
        <span className="pt-1 text-[13px] font-medium text-muted-foreground">{label}</span>
        <span
          className={cn(
            'grid size-9 shrink-0 place-items-center rounded-xl border border-border bg-white text-primary transition-colors',
            (onClick || to) && 'group-hover:border-primary group-hover:bg-primary group-hover:text-white',
            active && 'border-primary bg-primary text-white',
          )}
        >
          <IconCmp className="size-[18px]" strokeWidth={1.75} />
        </span>
      </span>
      <span className="mt-3 block font-num text-[40px] leading-none text-navy tabular-nums">
        {value === undefined ? <span className="block h-10 w-20 animate-pulse rounded-lg bg-soft" /> : value}
      </span>
    </>
  )
  if (to) {
    return (
      <Link to={to} className={className}>
        {body}
      </Link>
    )
  }
  if (onClick) {
    return (
      <button type="button" onClick={onClick} aria-pressed={active} className={className}>
        {body}
      </button>
    )
  }
  return <div className={className}>{body}</div>
}

/** Scrolls to the page's list, below the sticky top bar. */
export function showList() {
  document.getElementById('list')?.scrollIntoView({ behavior: 'smooth', block: 'start' })
}

export function IconBox({ icon: IconCmp, className }: { icon: Icon; className?: string }) {
  return (
    <span className={cn('grid size-10 shrink-0 place-items-center rounded-xl bg-accent-soft text-primary', className)}>
      <IconCmp className="size-5" strokeWidth={1.75} />
    </span>
  )
}

/** A large white card: tinted icon box, serif title, one grey line under it. */
export function ContentCard({
  icon,
  title,
  description,
  actions,
  children,
  className,
  id,
}: {
  icon: Icon
  title: ReactNode
  description?: ReactNode
  actions?: ReactNode
  children: ReactNode
  className?: string
  id?: string
}) {
  return (
    <section
      id={id}
      // A container, so a table inside turns into cards when the card is narrow.
      className={cn(
        '@container scroll-mt-28 rounded-3xl border border-border bg-card p-6 shadow-[0_1px_2px_rgba(14,26,43,0.04),0_8px_24px_-12px_rgba(14,26,43,0.08)] sm:p-7',
        className,
      )}
    >
      <div className="mb-5 flex flex-wrap items-start gap-x-4 gap-y-3">
        {/* basis: on a narrow card the actions go under the title, not squeeze it. */}
        <div className="flex min-w-0 flex-1 basis-64 items-center gap-3.5">
          <IconBox icon={icon} />
          <div className="min-w-0">
            <h2 className="font-serif text-[22px] leading-tight text-navy">{title}</h2>
            {description && <p className="mt-0.5 text-sm text-muted-foreground">{description}</p>}
          </div>
        </div>
        {actions}
      </div>
      {children}
    </section>
  )
}

// --------------------------------------------------------------- filters ---

export interface Chip<T extends string> {
  value: T | ''
  label: string
  count?: number
}

/** Rounded pills; the selected one is filled with the accent. */
export function FilterChips<T extends string>({
  chips,
  value,
  onChange,
  label,
}: {
  chips: Chip<T>[]
  value: T | ''
  onChange: (value: T | '') => void
  label: string
}) {
  return (
    <div role="group" aria-label={label} className="flex flex-wrap gap-2">
      {chips.map((chip) => {
        const selected = chip.value === value
        return (
          <button
            key={chip.value || 'all'}
            type="button"
            aria-pressed={selected}
            onClick={() => onChange(chip.value)}
            className={cn(
              'inline-flex h-10 items-center gap-1.5 rounded-full border px-4 text-sm font-medium transition-colors outline-none focus-visible:ring-3 focus-visible:ring-primary/30',
              selected
                ? 'border-primary bg-primary text-white shadow-[0_6px_16px_-8px_color-mix(in_srgb,var(--primary)_70%,transparent)]'
                : 'border-border bg-white text-navy hover:border-border-strong hover:bg-soft',
            )}
          >
            {chip.label}
            {chip.count !== undefined && (
              <span className={cn('tabular-nums', selected ? 'text-white/80' : 'text-faint')}>({chip.count})</span>
            )}
          </button>
        )
      })}
    </div>
  )
}

/**
 * Which page of a list shows (API_CONTRACT.md §1.3): the first again
 * whenever what the list shows changes (`of`: its search and filters).
 */
export function usePage(of: string) {
  const [state, setState] = useState({ of, page: 1 })
  if (state.of !== of) setState({ of, page: 1 })
  return [state.of === of ? state.page : 1, (page: number) => setState({ of, page })] as const
}

/**
 * Previous and next under a paged list, and where it is ("51–100 of 312").
 * Nothing when it fits one page. A page emptied by the answer to its last row
 * (the last waiting store approved) moves to the last page that has rows.
 */
export function Pager({ meta, busy, onPage }: { meta?: PageMeta; busy?: boolean; onPage: (page: number) => void }) {
  const { t } = useI18n()
  const emptied = !!meta && meta.page > 1 && meta.page > meta.totalPages
  const last = Math.max(1, meta?.totalPages ?? 1)
  useEffect(() => {
    if (emptied) onPage(last)
    // `onPage` is a new function every render; `emptied` and `last` say when to move.
  }, [emptied, last])
  // An unpaged answer can carry an empty meta: nothing to show then.
  if (!meta?.totalPages || meta.totalPages <= 1 || emptied) return null
  const from = (meta.page - 1) * meta.perPage + 1
  const to = Math.min(meta.total, meta.page * meta.perPage)
  return (
    <nav aria-label={t.pager.label} className="mt-5 flex flex-wrap items-center justify-between gap-3">
      <p className="text-[13px] text-muted-foreground tabular-nums">
        {/* The range stays left to right in Arabic too: isolated, "1–50" can't flip to "50–1". */}
        {t.pager.showing(`\u2066${number(from)}–${number(to)}\u2069`, number(meta.total))}
      </p>
      <div className="flex gap-2">
        <Button variant="outline" className="h-10 rounded-full px-4" disabled={busy || meta.page <= 1} onClick={() => onPage(meta.page - 1)}>
          <ChevronLeft className="size-4 rtl:rotate-180" />
          {t.pager.previous}
        </Button>
        <Button variant="outline" className="h-10 rounded-full px-4" disabled={busy || meta.page >= meta.totalPages} onClick={() => onPage(meta.page + 1)}>
          {t.pager.next}
          <ChevronRight className="size-4 rtl:rotate-180" />
        </Button>
      </div>
    </nav>
  )
}

/** A dropdown shaped like the filter pills, for the shadcn SelectTrigger. */
export const pillSelect =
  'h-10 min-w-48 gap-1.5 rounded-full border-border bg-white px-4 text-sm font-medium text-navy data-[size=default]:h-10'

export function SearchBar({ value, onChange, placeholder }: { value: string; onChange: (v: string) => void; placeholder: string }) {
  return (
    <div className="relative">
      <Search className="pointer-events-none absolute start-4 top-1/2 size-[18px] -translate-y-1/2 text-faint" strokeWidth={1.75} />
      <input
        type="search"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        aria-label={placeholder}
        className="h-12 w-full rounded-xl border border-border bg-soft ps-11 pe-11 text-[15px] text-navy transition outline-none placeholder:text-faint focus:border-primary/40 focus:bg-white focus:ring-4 focus:ring-primary/10 [&::-webkit-search-cancel-button]:hidden"
      />
      {value && (
        <button
          type="button"
          onClick={() => onChange('')}
          aria-label="Clear"
          className="absolute end-3 top-1/2 grid size-7 -translate-y-1/2 place-items-center rounded-full text-faint hover:bg-muted hover:text-navy"
        >
          <X className="size-4" />
        </button>
      )}
    </div>
  )
}

// ---------------------------------------------------------------- status ---

export type Tone = 'ok' | 'wait' | 'bad' | 'go' | 'off'

const TONE: Record<Tone, { badge: string; dot: string; bar: string }> = {
  ok: { badge: 'bg-ok-soft text-ok', dot: 'bg-ok', bar: 'bg-ok' },
  wait: { badge: 'bg-wait-soft text-wait', dot: 'bg-wait', bar: 'bg-wait' },
  bad: { badge: 'bg-bad-soft text-bad', dot: 'bg-bad', bar: 'bg-bad' },
  go: { badge: 'bg-go-soft text-go', dot: 'bg-go', bar: 'bg-go' },
  off: { badge: 'bg-off-soft text-off', dot: 'bg-[#8a99ab]', bar: 'bg-[#8a99ab]' },
}

export const toneClass = (tone: Tone) => TONE[tone]

// green approved/delivered · orange waiting · red rejected · grey taken down/suspended · blue in progress
export const STORE_TONE = {
  PENDING: 'wait',
  APPROVED: 'ok',
  REJECTED: 'bad',
  SUSPENDED: 'off',
  CLOSED: 'off',
} as const satisfies Record<StoreStatus, Tone>

export const PRODUCT_TONE = {
  DRAFT: 'off',
  PENDING: 'wait',
  APPROVED: 'ok',
  REJECTED: 'bad',
  TAKEN_DOWN: 'off',
} as const satisfies Record<ProductFilter | 'DRAFT', Tone>

export const ORDER_TONE = {
  PENDING: 'wait',
  CONFIRMED: 'go',
  PROCESSING: 'go',
  SHIPPED: 'go',
  DELIVERED: 'ok',
  CANCELLED: 'bad',
  REFUSED: 'bad',
  RETURNED: 'off',
  REFUNDED: 'off',
} as const satisfies Record<OrderStatus, Tone>

/** Small uppercase pill with a soft tint and matching text. */
export function StatusBadge({ tone, children }: { tone: Tone; children: ReactNode }) {
  return (
    <span
      className={cn(
        'inline-flex h-6 items-center rounded-md px-2.5 text-[11px] font-semibold whitespace-nowrap uppercase ltr:tracking-[0.06em] rtl:text-xs',
        TONE[tone].badge,
      )}
    >
      {children}
    </span>
  )
}

export function StoreBadge({ status }: { status: StoreStatus }) {
  const { t } = useI18n()
  return <StatusBadge tone={STORE_TONE[status]}>{t.storeStatus[status]}</StatusBadge>
}

/**
 * Taken down, approved in a suspended store, or switched off by its store: out
 * of the shop either way, so the badge says why instead of "Approved".
 */
export function ProductBadge({ product }: { product: Pick<AdminProduct, 'status' | 'takenDown' | 'isActive' | 'merchant'> }) {
  const { t } = useI18n()
  if (product.status === 'APPROVED' && !product.takenDown && product.merchant.status === 'SUSPENDED') {
    return <StatusBadge tone="off">{t.product.storeSuspended}</StatusBadge>
  }
  // The store's own switch, not Saba's takedown.
  if (product.status === 'APPROVED' && !product.takenDown && !product.isActive) {
    return <StatusBadge tone="off">{t.product.storeOff}</StatusBadge>
  }
  const key = product.takenDown ? 'TAKEN_DOWN' : product.status
  return <StatusBadge tone={PRODUCT_TONE[key]}>{t.productStatus[key]}</StatusBadge>
}

export function OrderBadge({ status }: { status: OrderStatus }) {
  const { t } = useI18n()
  return <StatusBadge tone={ORDER_TONE[status]}>{t.orderStatus[status]}</StatusBadge>
}

// ---------------------------------------------------------------- people ---

const AVATAR_TINTS = ['bg-accent-soft text-primary', 'bg-go-soft text-go', 'bg-ok-soft text-ok', 'bg-wait-soft text-wait']

/** A photo, or the first letters of the name on a soft tint when there is none. */
export function Thumb({ src, name, round = false, className }: { src?: string; name: string; round?: boolean; className?: string }) {
  const [broken, setBroken] = useState(false)
  const shape = round ? 'rounded-full' : 'rounded-xl'
  if (src && !broken) {
    return (
      <img
        src={src}
        alt=""
        onError={() => setBroken(true)}
        className={cn('size-11 shrink-0 border border-border bg-soft object-cover', shape, className)}
      />
    )
  }
  const tint = AVATAR_TINTS[[...name].reduce((sum, ch) => sum + ch.charCodeAt(0), 0) % AVATAR_TINTS.length]
  return (
    <span className={cn('grid size-11 shrink-0 place-items-center font-serif text-[17px]', shape, tint, className)} aria-hidden>
      {initials(name).slice(0, round ? 1 : 2)}
    </span>
  )
}

/**
 * Thumbnail, name, and a small grey second line. The name is laid out in its
 * own direction, so an English name cut short in Arabic loses its end, not
 * its start, and still lines up with the page.
 */
export function NameCell({ thumb, title, subtitle }: { thumb: ReactNode; title: ReactNode; subtitle?: ReactNode }) {
  const { dir } = useI18n()
  return (
    <div className="flex min-w-0 items-center gap-3.5">
      {thumb}
      <div className="min-w-0">
        <div dir="auto" className={cn('truncate text-[15px] font-medium text-navy', dir === 'rtl' ? 'text-right' : 'text-left')}>
          {title}
        </div>
        {subtitle && <div className="mt-0.5 truncate text-[13px] text-muted-foreground">{subtitle}</div>}
      </div>
    </div>
  )
}

/** Left-to-right text inside Arabic: phone numbers, order numbers, SKUs. */
export function Ltr({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <span dir="ltr" className={className}>
      {children}
    </span>
  )
}

// ---------------------------------------------------------------- states ---

export function errorText(error: unknown, t: Strings): string {
  return error instanceof ApiError ? (error.detail ?? t.errors[error.code]) : t.errors.NETWORK
}

function StateFrame({ icon: IconCmp, tone, title, text, action }: { icon: Icon; tone: 'primary' | 'bad'; title: string; text: string; action?: ReactNode }) {
  return (
    <div className="flex flex-col items-center px-6 py-14 text-center">
      <div className={cn('grid size-20 place-items-center rounded-full', tone === 'bad' ? 'bg-bad-soft/70' : 'bg-soft')}>
        <div
          className={cn(
            'grid size-12 place-items-center rounded-full border bg-white shadow-sm',
            tone === 'bad' ? 'border-bad/15 text-bad' : 'border-border text-primary',
          )}
        >
          <IconCmp className="size-[22px]" strokeWidth={1.75} />
        </div>
      </div>
      <h3 className="mt-5 font-serif text-xl text-navy">{title}</h3>
      <p className="mt-1.5 max-w-sm text-sm text-muted-foreground">{text}</p>
      {action && <div className="mt-5">{action}</div>}
    </div>
  )
}

export function EmptyState({ icon = Inbox, title, text, action }: { icon?: Icon; title: string; text: string; action?: ReactNode }) {
  return <StateFrame icon={icon} tone="primary" title={title} text={text} action={action} />
}

export function ErrorState({ error, onRetry }: { error: unknown; onRetry: () => void }) {
  const { t } = useI18n()
  // Only a lost connection can go better a second time; "no longer there" stays so.
  const canRetry = !(error instanceof ApiError) || error.code === 'NETWORK'
  return (
    <StateFrame
      icon={TriangleAlert}
      tone="bad"
      title={t.errors.title}
      text={errorText(error, t)}
      action={
        canRetry && (
          <Button variant="outline" size="lg" onClick={onRetry} className="h-10 rounded-full px-5">
            <RefreshCw data-icon="inline-start" />
            {t.retry}
          </Button>
        )
      }
    />
  )
}

/** Rows shaped like the table that is loading. */
export function TableSkeleton({ rows = 6, columns = 4 }: { rows?: number; columns?: number }) {
  return (
    <div aria-busy="true" className="divide-y divide-border/70">
      <div className="flex gap-6 pb-3">
        {Array.from({ length: columns + 1 }, (_, i) => (
          <Skeleton key={i} className={cn('h-3 rounded', i === 0 ? 'w-24' : 'ms-auto w-14')} />
        ))}
      </div>
      {Array.from({ length: rows }, (_, row) => (
        <div key={row} className="flex items-center gap-6 py-4">
          <div className="flex flex-1 items-center gap-3.5">
            <Skeleton className="size-11 rounded-xl" />
            <div className="space-y-2">
              <Skeleton className="h-3.5 rounded" style={{ width: `${140 + ((row * 37) % 80)}px` }} />
              <Skeleton className="h-3 w-24 rounded" />
            </div>
          </div>
          {Array.from({ length: columns - 1 }, (_, i) => (
            <Skeleton key={i} className="hidden h-3.5 w-20 rounded md:block" />
          ))}
          <Skeleton className="h-6 w-20 rounded-md" />
        </div>
      ))}
    </div>
  )
}

// ---------------------------------------------------------------- sheets ---

/** A soft card inside a detail sheet. */
export function Section({ title, aside, children }: { title: string; aside?: ReactNode; children: ReactNode }) {
  return (
    <section className="rounded-2xl border border-border bg-white p-5">
      <div className="mb-4 flex items-center justify-between gap-3">
        <h3 className="text-[12px] font-semibold text-faint uppercase ltr:tracking-[0.1em] rtl:text-[13px]">{title}</h3>
        {aside}
      </div>
      {children}
    </section>
  )
}

export function Fields({ children }: { children: ReactNode }) {
  return <dl className="grid grid-cols-1 gap-x-6 gap-y-4 sm:grid-cols-2">{children}</dl>
}

export function Field({ label, children, wide = false }: { label: string; children: ReactNode; wide?: boolean }) {
  return (
    <div className={cn('min-w-0', wide && 'sm:col-span-2')}>
      <dt className="text-[13px] text-muted-foreground">{label}</dt>
      <dd className="mt-1 text-[15px] break-words text-navy">{children}</dd>
    </div>
  )
}

/** A reason from Saba, shown where the store's answer lives. */
export function Callout({ tone, icon: IconCmp, title, children }: { tone: Tone; icon: Icon; title?: string; children: ReactNode }) {
  return (
    <div className={cn('flex gap-3 rounded-2xl px-4 py-3.5 text-[14px]', TONE[tone].badge)}>
      <IconCmp className="mt-0.5 size-[18px] shrink-0" strokeWidth={1.75} />
      <div>
        {title && <p className="font-semibold">{title}</p>}
        <div className={cn(title && 'mt-0.5', 'text-navy/85')}>{children}</div>
      </div>
    </div>
  )
}

export function SheetSkeleton() {
  return (
    <div aria-busy="true" className="space-y-4 p-7">
      <Skeleton className="h-40 w-full rounded-2xl" />
      <Skeleton className="h-8 w-2/3 rounded-lg" />
      <Skeleton className="h-4 w-1/3 rounded" />
      {[0, 1, 2].map((i) => (
        <div key={i} className="space-y-3 rounded-2xl border border-border p-5">
          <Skeleton className="h-3 w-24 rounded" />
          <div className="grid grid-cols-2 gap-4">
            <Skeleton className="h-10 rounded-lg" />
            <Skeleton className="h-10 rounded-lg" />
          </div>
        </div>
      ))}
    </div>
  )
}

// ---------------------------------------------------------------- tables ---

/** Light uppercase headers, generous rows. */
export const th = 'h-11 px-3 text-[11px] font-semibold uppercase text-faint ltr:tracking-[0.08em] rtl:text-xs first:ps-0 last:pe-0'
export const td = 'px-3 py-4 first:ps-0 last:pe-0 @max-3xl:min-w-0 @max-3xl:p-0 @max-3xl:first:basis-full'
/** The whole row opens the details; `group/row` lets its Details button answer the hover. */
export const row =
  'group/row cursor-pointer border-border/70 transition-colors hover:bg-soft @max-3xl:flex @max-3xl:flex-wrap @max-3xl:items-center @max-3xl:gap-x-3 @max-3xl:gap-y-2.5 @max-3xl:py-4'

// In a card narrower than 48rem (a phone, or a tablet beside the menu) a
// table would run off the edge, so each row becomes a small card instead,
// read in column order: the first cell on its own line, then each
// `card.line` cell on its own line, then the rest (the status) on the last
// line with `card.end` pushed to its end. `card.hide` cells are left to the
// details sheet. The table gets `card.table`.
export const card = {
  table: '@max-3xl:block @max-3xl:[&_thead]:hidden @max-3xl:[&_tbody]:block',
  line: '@max-3xl:basis-full @max-3xl:text-start',
  end: '@max-3xl:ms-auto',
  hide: '@max-3xl:hidden',
}

/** The "Details" button at the end of a row. Opens what the row opens. */
export function DetailsButton({ onClick }: { onClick: () => void }) {
  const { t } = useI18n()
  return (
    <Button
      type="button"
      variant="outline"
      onClick={(event) => {
        // The row opens the same thing; once is enough.
        event.stopPropagation()
        onClick()
      }}
      className="h-9 rounded-lg bg-white px-3 text-[13px] text-navy group-hover/row:border-primary/50 group-hover/row:text-primary"
    >
      <Eye data-icon="inline-start" />
      {t.details}
    </Button>
  )
}

/** The empty header above the Details buttons, named for screen readers. */
export function DetailsHead() {
  const { t } = useI18n()
  return (
    <TableHead className={th}>
      <span className="sr-only">{t.details}</span>
    </TableHead>
  )
}
