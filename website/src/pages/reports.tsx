import { Flag, ImageOff, MessageSquare, Package, Store, Trash2, User, type LucideIcon } from 'lucide-react'
import { useState, type ReactNode } from 'react'
import { ConfirmDialog, ReportActions, useRun } from '@/components/actions'
import { ContentCard, EmptyState, ErrorState, FilterChips, PageIntro, Pager, StatusBadge, TableSkeleton, pillSelect, showList, usePage, type Tone } from '@/components/blocks'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogDescription, DialogTitle } from '@/components/ui/dialog'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import type { ProductFilter } from '@/data/products'
import { listReports, removeChatPhoto, type ChatLine, type ReportedItem, type ReportStatus, type ReportTarget } from '@/data/reports'
import type { StoreStatus } from '@/data/types'
import { ago, dateTime } from '@/lib/format'
import { useI18n } from '@/lib/i18n'
import { useSheet, useUrlFilters } from '@/lib/url-state'
import { useQuery } from '@/lib/use-query'
import { cn } from '@/lib/utils'

const STATUSES: ReportStatus[] = ['OPEN', 'DISMISSED', 'ACTIONED']
const TYPES: ReportTarget[] = ['PRODUCT', 'STORE', 'CONVERSATION']
const ALL = 'all'
const TONE: Record<ReportStatus, Tone> = { OPEN: 'wait', DISMISSED: 'off', ACTIONED: 'ok' }

export function ReportsPage() {
  const { t } = useI18n()
  const [filters, setFilters] = useUrlFilters({ status: STATUSES, type: TYPES })
  const status = filters.status as ReportStatus | ''
  const type = filters.type as ReportTarget | ''
  const [page, setPage] = usePage(`${status}:${type}`)
  const list = useQuery(() => listReports({ status: status || undefined, type: type || undefined, page }), `reports:${status}:${type}:${page}`)
  const filtered = Boolean(status || type)

  return (
    <>
      <PageIntro>{t.reports.intro}</PageIntro>
      <ContentCard id="list" icon={Flag} title={t.reports.cardTitle} description={t.reports.cardText}>
        <div className="flex flex-wrap items-center justify-between gap-3">
          <FilterChips
            label={t.col.status}
            value={status}
            onChange={(next) => setFilters({ status: next })}
            chips={[
              { value: '', label: t.all, count: list.data?.counts.all },
              ...STATUSES.map((s) => ({ value: s, label: t.reports.status[s], count: list.data && (list.data.counts[s] ?? 0) })),
            ]}
          />
          <Select value={type || ALL} onValueChange={(next) => setFilters({ type: next === ALL ? '' : next })}>
            <SelectTrigger aria-label={t.reports.typeLabel} className={cn(pillSelect, type && 'border-primary text-primary')}>
              <span className="text-muted-foreground">{t.reports.typeLabel}:</span>
              <SelectValue />
            </SelectTrigger>
            <SelectContent position="popper" align="end" className="rounded-xl">
              <SelectItem value={ALL}>{t.all}</SelectItem>
              {TYPES.map((k) => (
                <SelectItem key={k} value={k}>
                  {t.reports.types[k]}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>

        <div className="mt-6">
          {list.error ? (
            <ErrorState error={list.error} onRetry={list.retry} />
          ) : !list.data ? (
            <TableSkeleton columns={3} />
          ) : list.data.items.length === 0 ? (
            <EmptyState
              icon={Flag}
              title={filtered ? t.empty.search : t.reports.none}
              text={filtered ? t.empty.searchText : t.reports.noneText}
              action={
                filtered && (
                  <Button variant="outline" className="h-10 rounded-full px-5" onClick={() => setFilters({ status: '', type: '' })}>
                    {t.clearFilters}
                  </Button>
                )
              }
            />
          ) : (
            <ul className={cn('space-y-4 transition-opacity', list.loading && 'opacity-60')}>
              {list.data.items.map((item) => (
                <ReportCard key={item.id} item={item} />
              ))}
            </ul>
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

function ReportCard({ item }: { item: ReportedItem }) {
  const { t, lang } = useI18n()
  const sheet = useSheet()
  const run = useRun()
  // The photo "Remove photo" asks about: its message's id.
  const [removing, setRemoving] = useState<string | null>(null)
  const { product, store, customer } = item
  const storeLink = store && (
    <SheetLink icon={Store} onClick={() => sheet.open('store', store.id)}>
      {store.storeName}
    </SheetLink>
  )
  // What Saba already did shows here: a product out of the shop, a store not approved.
  const states = [
    product && (product.takenDown ? t.productStatus.TAKEN_DOWN : product.status !== 'APPROVED' ? (t.productStatus[product.status as ProductFilter] ?? product.status) : undefined),
    store && store.status !== 'APPROVED' ? (t.storeStatus[store.status as StoreStatus] ?? store.status) : undefined,
  ].filter(Boolean)

  return (
    <li className="rounded-2xl border border-border bg-white p-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
            {item.type === 'PRODUCT' ? (
              product ? (
                <SheetLink icon={Package} onClick={() => sheet.open('product', product.id)}>
                  {product.name}
                </SheetLink>
              ) : (
                <bdi className="text-[15px] font-medium text-navy">{item.title}</bdi>
              )
            ) : item.type === 'STORE' ? (
              (storeLink ?? <bdi className="text-[15px] font-medium text-navy">{item.title}</bdi>)
            ) : (
              <>
                {customer ? (
                  <SheetLink icon={User} onClick={() => sheet.open('customer', customer.id)}>
                    {customer.fullName}
                  </SheetLink>
                ) : (
                  <span className="text-[15px] font-medium text-navy">{t.reported.deletedAccount}</span>
                )}
                <span className="text-faint">·</span>
                {storeLink}
              </>
            )}
          </div>
          <p className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1 text-[13px] text-muted-foreground">
            <span className="inline-flex items-center gap-1.5">
              {item.type === 'CONVERSATION' && <MessageSquare className="size-3.5" />}
              {t.reports.type[item.type]}
            </span>
            {item.type === 'PRODUCT' && store && (
              <>
                <span>·</span>
                <button type="button" onClick={() => sheet.open('store', store.id)} className="hover:text-navy hover:underline">
                  <bdi>{store.storeName}</bdi>
                </button>
              </>
            )}
            {states.map((state) => (
              <span key={state}>· {state}</span>
            ))}
          </p>
        </div>
        <StatusBadge tone={TONE[item.status]}>{t.reports.status[item.status]}</StatusBadge>
      </div>

      <div className="mt-4 rounded-xl bg-soft px-4 py-3">
        <p className="mb-2 text-[13px] font-semibold text-navy">{t.reported.reports(item.reports.length)}</p>
        <ul className="space-y-4">
          {item.reports.map((report) => (
            <li key={report.id} className="text-[14px]">
              <p className="font-medium text-navy">
                {t.reported.reason[report.reason]}
                {report.status !== 'OPEN' && <span className="font-normal text-muted-foreground"> · {t.reports.status[report.status]}</span>}
              </p>
              {report.description && (
                <p dir="auto" className="text-navy">
                  {report.description}
                </p>
              )}
              <p className="text-[13px] text-muted-foreground">
                <bdi>{report.reporterName ?? t.reported.deletedAccount}</bdi> · {t.reports.role[report.reporterRole]} · {ago(report.createdAt, lang)}
              </p>
              {report.evidence && (
                <div className="mt-3">
                  <p className="text-[13px] font-medium text-muted-foreground">{t.reports.chat}</p>
                  {report.evidence.length === 0 ? (
                    <p className="text-[13px] text-muted-foreground">{t.reports.noChat}</p>
                  ) : (
                    <ol className="mt-2 max-h-96 space-y-3 overflow-y-auto rounded-xl bg-white p-3">
                      {report.evidence.map((m, i) => (
                        <li key={m.messageId ?? i} className={cn('flex flex-col', m.from === 'CUSTOMER' ? 'items-start' : 'items-end')}>
                          <div
                            className={cn(
                              'max-w-[85%] rounded-2xl px-3.5 py-2 leading-relaxed text-navy',
                              m.from === 'CUSTOMER' ? 'rounded-ss-md bg-soft' : 'rounded-se-md bg-accent-soft',
                            )}
                          >
                            <ChatPhoto line={m} />
                            {m.body && (
                              <p dir="auto" className="whitespace-pre-wrap">
                                {m.body}
                              </p>
                            )}
                          </div>
                          <p className="mt-1 flex flex-wrap items-center gap-x-2 px-1 text-[12px] text-muted-foreground">
                            <span>
                              <bdi>{m.from === 'CUSTOMER' ? (customer?.fullName ?? t.reports.role.CUSTOMER) : (store?.storeName ?? t.reports.role.MERCHANT)}</bdi> ·{' '}
                              {dateTime(m.sentAt, lang)}
                            </span>
                            {/* Only a photo still in the chat: one its sender's deleted account took goes by itself. */}
                            {m.messageId && m.photoUrl && !m.photoRemoved && (
                              <button
                                type="button"
                                onClick={() => setRemoving(m.messageId!)}
                                className="inline-flex items-center gap-1 font-medium text-bad hover:underline"
                              >
                                <Trash2 className="size-3.5" />
                                {t.reports.removePhoto}
                              </button>
                            )}
                          </p>
                        </li>
                      ))}
                    </ol>
                  )}
                </div>
              )}
            </li>
          ))}
        </ul>
      </div>

      <ConfirmDialog
        open={removing !== null}
        onOpenChange={(open) => !open && setRemoving(null)}
        title={t.reports.removePhotoTitle}
        text={t.reports.removePhotoText}
        confirmLabel={t.reports.removePhoto}
        danger
        onConfirm={() => run(() => removeChatPhoto(removing!), t.reports.photoRemoved)}
      />

      {item.status === 'OPEN' && (
        <div className="mt-4">
          <ReportActions item={item} />
        </div>
      )}
    </li>
  )
}

/** A photo in a chat's evidence, as it stands now: shown (a click enlarges it), or why it isn't. */
function ChatPhoto({ line: m }: { line: ChatLine }) {
  const { t } = useI18n()
  const [open, setOpen] = useState(false)
  const [broken, setBroken] = useState(false)
  if (m.photoRemoved === 'SABA') return <PhotoNote>{t.reports.removedBySaba}</PhotoNote>
  if (!m.photoUrl) return m.photoRemoved === 'ACCOUNT' ? <PhotoNote>{t.reports.goneWithAccount}</PhotoNote> : null
  // Signed for an hour or two: an old page's link runs out.
  if (broken) return <PhotoNote>{t.reports.photoExpired}</PhotoNote>
  return (
    <>
      <button type="button" onClick={() => setOpen(true)} title={t.reports.enlarge} aria-label={t.reports.enlarge} className="block overflow-hidden rounded-xl">
        <img src={m.photoUrl} alt={t.reports.photoAlt} onError={() => setBroken(true)} className="max-h-56 max-w-full object-cover" />
      </button>
      {m.photoRemoved === 'ACCOUNT' && <p className="mt-1.5 text-[12px] text-wait">{t.reports.accountGone}</p>}
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-[min(92vw,960px)] rounded-3xl p-3 sm:max-w-[min(92vw,960px)]">
          <DialogTitle className="sr-only">{t.reports.photoAlt}</DialogTitle>
          <DialogDescription className="sr-only">{t.reports.photoAlt}</DialogDescription>
          <img src={m.photoUrl} alt={t.reports.photoAlt} className="max-h-[85vh] w-full rounded-2xl object-contain" />
        </DialogContent>
      </Dialog>
    </>
  )
}

function PhotoNote({ children }: { children: ReactNode }) {
  return (
    <p className="flex items-center gap-1.5 text-[13px] text-muted-foreground">
      <ImageOff className="size-4 shrink-0" />
      {children}
    </p>
  )
}

function SheetLink({ icon: Icon, onClick, children }: { icon: LucideIcon; onClick: () => void; children: ReactNode }) {
  return (
    <button type="button" onClick={onClick} className="inline-flex items-center gap-1.5 text-[15px] font-medium text-navy hover:underline">
      <Icon className="size-4 text-faint" />
      <bdi>{children}</bdi>
    </button>
  )
}
