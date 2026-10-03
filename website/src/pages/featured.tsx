import { useEffect, useState, type DragEvent } from 'react'
import { useBlocker } from 'react-router'
import { ArrowDown, ArrowUp, GripVertical, Star, Store, TriangleAlert } from 'lucide-react'
import { ConfirmDialog, useRun } from '@/components/actions'
import { Callout, ContentCard, EmptyState, ErrorState, PageIntro, Thumb } from '@/components/blocks'
import { Switch } from '@/components/form'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import { currentAdmin } from '@/data/auth'
import { getFeatured, saveFeatured } from '@/data/featured'
import type { AdminStore } from '@/data/types'
import { useI18n } from '@/lib/i18n'
import { useSheet } from '@/lib/url-state'
import { useQuery } from '@/lib/use-query'
import { cn } from '@/lib/utils'

function StoreLine({ store }: { store: AdminStore }) {
  const { t, city, dir } = useI18n()
  return (
    <>
      <Thumb src={store.logoUrl} name={store.storeName} round />
      <span className="min-w-0 flex-1">
        {/* Its own direction, lined up with the page, as in NameCell. */}
        <span dir="auto" className={cn('block truncate text-[15px] font-medium text-navy', dir === 'rtl' ? 'text-right' : 'text-left')}>
          {store.storeName}
        </span>
        <span className="block truncate text-[13px] text-muted-foreground">
          {city(store.governorate)} · {t.store.productsText(store.productCount)}
        </span>
      </span>
    </>
  )
}

export function FeaturedPage() {
  const { t } = useI18n()
  const sheet = useSheet()
  const run = useRun()
  const result = useQuery(getFeatured, 'featured')
  // Changes stay here until saved: the rail is live on every shopper's home.
  const [draft, setDraft] = useState<string[] | null>(null)
  const [dragging, setDragging] = useState<number | null>(null)
  const [busy, setBusy] = useState(false)

  const data = result.data
  const rail = draft ?? data?.featured ?? []
  const dirty = !!data && draft !== null && draft.join() !== data.featured.join()
  const byId = new Map(data?.stores.map((s) => [s.id, s]))

  // Unsaved changes are not dropped without asking: not by leaving the page
  // (a store's sheet opens on it, so that is fine), nor by reload or closing
  // the tab. Signed out, nothing could be saved, so that one is let go.
  const blocker = useBlocker(({ currentLocation, nextLocation }) => dirty && currentLocation.pathname !== nextLocation.pathname && !!currentAdmin())
  useEffect(() => {
    if (!dirty) return
    const warn = (event: BeforeUnloadEvent) => event.preventDefault()
    window.addEventListener('beforeunload', warn)
    return () => window.removeEventListener('beforeunload', warn)
  }, [dirty])
  const others = data?.stores.filter((s) => !rail.includes(s.id)) ?? []

  const move = (from: number, to: number) => {
    if (to < 0 || to >= rail.length || from === to) return
    const next = [...rail]
    next.splice(to, 0, ...next.splice(from, 1))
    setDraft(next)
  }
  const onDrop = (to: number) => (e: DragEvent) => {
    e.preventDefault()
    if (dragging !== null) move(dragging, to)
    setDragging(null)
  }
  const save = async () => {
    setBusy(true)
    if (await run(() => saveFeatured(rail), t.featured.saved)) setDraft(null)
    setBusy(false)
  }

  if (result.error) {
    return (
      <>
        <PageIntro>{t.featured.intro}</PageIntro>
        <ContentCard icon={Star} title={t.featured.railTitle}>
          <ErrorState error={result.error} onRetry={result.retry} />
        </ContentCard>
      </>
    )
  }

  return (
    <>
      <PageIntro>{t.featured.intro}</PageIntro>

      {data && rail.length === 0 && (
        <div className="mb-6">
          <Callout tone="wait" icon={TriangleAlert} title={t.featured.noneTitle}>
            {t.featured.noneText}
          </Callout>
        </div>
      )}

      <div className="space-y-6">
        <ContentCard
          icon={Star}
          title={t.featured.railTitle}
          description={t.featured.railText}
          actions={
            data && (
              <span className="inline-flex h-9 items-center rounded-full bg-accent-soft px-4 text-sm font-semibold text-primary tabular-nums">
                {t.featured.count(rail.length, data.stores.length)}
              </span>
            )
          }
        >
          {!data ? (
            <ListSkeleton />
          ) : rail.length === 0 ? (
            <EmptyState icon={Star} title={t.featured.noneTitle} text={t.featured.noneText} />
          ) : (
            <ol className="divide-y divide-border/70">
              {rail.map((id, index) => {
                const store = byId.get(id)
                if (!store) return null
                return (
                  <li
                    key={id}
                    draggable
                    onDragStart={(e) => {
                      setDragging(index)
                      e.dataTransfer.effectAllowed = 'move'
                    }}
                    onDragOver={(e) => e.preventDefault()}
                    onDrop={onDrop(index)}
                    onDragEnd={() => setDragging(null)}
                    onClick={() => sheet.open('store', id)}
                    // On a phone the controls wrap under the name, so the name is not cut to a few letters.
                    className={cn(
                      'flex cursor-pointer flex-wrap items-center gap-x-3 gap-y-2 py-3.5 transition hover:bg-soft sm:gap-x-4',
                      dragging === index && 'opacity-40',
                    )}
                  >
                    <span className="flex min-w-0 flex-1 basis-56 items-center gap-3 sm:gap-4">
                      <GripVertical className="size-4 shrink-0 cursor-grab text-faint max-sm:hidden" aria-label={t.featured.drag} />
                      <span className="grid size-8 shrink-0 place-items-center rounded-full bg-surface-dark font-num text-[15px] text-white tabular-nums">
                        {index + 1}
                      </span>
                      <StoreLine store={store} />
                    </span>
                    <span className="ms-auto flex shrink-0 items-center gap-1" onClick={(e) => e.stopPropagation()}>
                      <Button variant="ghost" size="icon" aria-label={t.featured.up} title={t.featured.up} disabled={index === 0} onClick={() => move(index, index - 1)}>
                        <ArrowUp />
                      </Button>
                      <Button
                        variant="ghost"
                        size="icon"
                        aria-label={t.featured.down}
                        title={t.featured.down}
                        disabled={index === rail.length - 1}
                        onClick={() => move(index, index + 1)}
                      >
                        <ArrowDown />
                      </Button>
                      <Switch on label={t.featured.feature(store.storeName)} onChange={() => setDraft(rail.filter((x) => x !== id))} />
                    </span>
                  </li>
                )
              })}
            </ol>
          )}
        </ContentCard>

        <ContentCard icon={Store} title={t.featured.othersTitle} description={t.featured.othersText}>
          {!data ? (
            <ListSkeleton />
          ) : others.length === 0 ? (
            <EmptyState icon={Star} title={t.featured.allFeatured} text={t.featured.allFeaturedText} />
          ) : (
            <ul className="divide-y divide-border/70">
              {others.map((store) => (
                <li
                  key={store.id}
                  onClick={() => sheet.open('store', store.id)}
                  className="flex cursor-pointer items-center gap-3 py-3.5 transition hover:bg-soft sm:gap-4"
                >
                  <StoreLine store={store} />
                  <Switch on={false} label={t.featured.feature(store.storeName)} onChange={() => setDraft([...rail, store.id])} />
                </li>
              ))}
            </ul>
          )}
        </ContentCard>
      </div>

      <ConfirmDialog
        open={blocker.state === 'blocked'}
        onOpenChange={(open) => !open && blocker.reset?.()}
        title={t.featured.leaveTitle}
        text={t.featured.leaveText}
        confirmLabel={t.featured.leave}
        danger
        onConfirm={async () => {
          blocker.proceed?.()
          return true
        }}
      />

      {dirty && (
        <div className="sticky bottom-4 z-10 mt-6 flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-border bg-surface-dark px-5 py-4 text-white shadow-[0_16px_40px_-16px_rgba(14,26,43,0.6)]">
          <p className="text-[15px]">{t.featured.unsaved}</p>
          <div className="flex gap-2">
            <Button variant="outline" disabled={busy} onClick={() => setDraft(null)} className="h-10 rounded-xl border-white/20 bg-transparent px-4 text-white hover:bg-white/10 hover:text-white">
              {t.featured.discard}
            </Button>
            <Button disabled={busy} onClick={save} className="h-10 rounded-xl bg-primary px-5 text-white hover:bg-primary-pressed">
              {t.featured.save}
            </Button>
          </div>
        </div>
      )}
    </>
  )
}

function ListSkeleton() {
  return (
    <div aria-busy="true" className="space-y-3">
      {[0, 1, 2, 3].map((i) => (
        <Skeleton key={i} className="h-14 rounded-xl" />
      ))}
    </div>
  )
}
