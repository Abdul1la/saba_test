import { useState } from 'react'
import { useSearchParams } from 'react-router'
import { Check, Pencil, Plus, Tag, Trash2 } from 'lucide-react'
import { ContentCard, EmptyState, ErrorState, FilterChips, PageIntro, Pager, SearchBar, StatusBadge, showList, usePage } from '@/components/blocks'
import { FormDialog, MoreMenu, RowButton, SearchPick, TextField } from '@/components/form'
import { Button } from '@/components/ui/button'
import { addBrand, changeBrand, deleteBrand, listBrands, type AdminBrand, type BrandStatus } from '@/data/catalog'
import { useI18n } from '@/lib/i18n'
import { useUrlFilters } from '@/lib/url-state'
import { useDebounced, useQuery } from '@/lib/use-query'
import { cn } from '@/lib/utils'
import { RowsSkeleton } from './categories'

const STATUSES: BrandStatus[] = ['PENDING', 'APPROVED']

type Open = { kind: 'add' } | { kind: 'edit' | 'delete'; id: string }

export function BrandsPage() {
  const { t } = useI18n()
  // ?q= : the product sheet's "Open Brands" comes with the brand's name.
  const [params] = useSearchParams()
  const [q, setQ] = useState(() => params.get('q') ?? '')
  const search = useDebounced(q.trim())
  const [filters, setFilters] = useUrlFilters({ status: STATUSES })
  const status = filters.status as BrandStatus | ''
  const [page, setPage] = usePage(`${search}:${status}`)
  const list = useQuery(() => listBrands({ q: search || undefined, status: status || undefined, page }), `brands:${search}:${status}:${page}`)
  const [open, setOpen] = useState<Open | null>(null)
  // A dialog reads its brand as it is now: its product count can change under it.
  const current = open && open.kind !== 'add' ? list.data?.items.find((b) => b.id === open.id) : undefined
  const close = () => setOpen(null)
  const filtered = Boolean(search || status)

  return (
    <>
      <PageIntro>{t.brands.intro}</PageIntro>
      <ContentCard
        id="list"
        icon={Tag}
        title={t.brands.cardTitle}
        description={t.brands.cardText}
        actions={
          <Button onClick={() => setOpen({ kind: 'add' })} className="h-10 rounded-full px-5">
            <Plus />
            {t.brands.add}
          </Button>
        }
      >
        <div className="space-y-4">
          <SearchBar value={q} onChange={setQ} placeholder={t.brands.search} />
          <FilterChips
            label={t.col.status}
            value={status}
            onChange={(next) => setFilters({ status: next })}
            chips={[
              { value: '', label: t.all, count: list.data?.counts.all },
              ...STATUSES.map((s) => ({ value: s, label: t.brands.status[s], count: list.data && (list.data.counts[s] ?? 0) })),
            ]}
          />
        </div>

        <div className="mt-6">
          {list.error ? (
            <ErrorState error={list.error} onRetry={list.retry} />
          ) : !list.data ? (
            <RowsSkeleton />
          ) : list.data.items.length === 0 ? (
            <EmptyState
              icon={Tag}
              title={filtered ? t.empty.search : t.brands.none}
              text={filtered ? t.empty.searchText : t.brands.noneText}
              action={
                filtered && (
                  <Button variant="outline" className="h-10 rounded-full px-5" onClick={() => (setQ(''), setFilters({ status: '' }))}>
                    {t.clearFilters}
                  </Button>
                )
              }
            />
          ) : (
            <ul className={cn('divide-y divide-border/70 transition-opacity', list.loading && 'opacity-60')}>
              {list.data.items.map((b) => (
                <li key={b.id} className="flex flex-wrap items-center gap-x-3 gap-y-2 py-3">
                  <span className="min-w-0 flex-1 basis-56">
                    <span className="flex flex-wrap items-center gap-2">
                      <bdi className="truncate text-[15px] font-medium text-navy">{b.name}</bdi>
                      {b.status === 'PENDING' && <StatusBadge tone="wait">{t.brands.status.PENDING}</StatusBadge>}
                    </span>
                    <span className="block truncate text-[13px] text-muted-foreground">
                      {b.nameAr ? <bdi dir="rtl">{b.nameAr}</bdi> : t.brands.noArabic} · {t.categories.count(b.productCount)}
                    </span>
                  </span>
                  <span className="ms-auto flex shrink-0 items-center gap-1.5">
                    <RowButton icon={b.status === 'PENDING' ? <Check /> : <Pencil />} onClick={() => setOpen({ kind: 'edit', id: b.id })}>
                      {b.status === 'PENDING' ? t.brands.check : t.brands.edit}
                    </RowButton>
                    <MoreMenu
                      label={t.form.more(b.name)}
                      actions={[{ label: t.brands.deleteMenu, icon: <Trash2 />, danger: true, onSelect: () => setOpen({ kind: 'delete', id: b.id }) }]}
                    />
                  </span>
                </li>
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

      {open?.kind === 'add' && <BrandForm onClose={close} />}
      {open?.kind === 'edit' && current && <BrandForm key={current.id} editing={current} onClose={close} />}
      {open?.kind === 'delete' && current && <DeleteBrand brand={current} onClose={close} />}
    </>
  )
}

function BrandForm({ editing, onClose }: { editing?: AdminBrand; onClose: () => void }) {
  const { t } = useI18n()
  const [name, setName] = useState(editing?.name ?? '')
  const [nameAr, setNameAr] = useState(editing?.nameAr ?? '')
  const [checked, setChecked] = useState(false)
  const missing = (value: string) => (checked && !value.trim() ? t.form.required : undefined)
  // A name a store typed: saving it is Saba's check.
  const typed = editing?.status === 'PENDING'
  const input = () => ({ name: name.trim(), nameAr: nameAr.trim() })
  return (
    <FormDialog
      open
      onOpenChange={(next) => !next && onClose()}
      title={!editing ? t.brands.addTitle : typed ? t.brands.checkTitle(editing.name) : t.brands.editTitle(editing.name)}
      text={!editing ? t.brands.addText : typed ? t.brands.checkText : t.brands.editText}
      saveLabel={typed ? t.brands.checkSave : t.brands.save}
      done={editing ? t.brands.saved : t.brands.added}
      check={() => {
        setChecked(true)
        return !!name.trim() && !!nameAr.trim()
      }}
      onSave={() => (editing ? changeBrand(editing.id, input()) : addBrand(input()))}
    >
      <TextField label={t.brands.name} value={name} onChange={setName} dir="ltr" error={missing(name)} autoFocus />
      <TextField label={t.brands.nameAr} value={nameAr} onChange={setNameAr} dir="rtl" error={missing(nameAr)} />
    </FormDialog>
  )
}

function DeleteBrand({ brand: b, onClose }: { brand: AdminBrand; onClose: () => void }) {
  const { t } = useI18n()
  const [moveTo, setMoveTo] = useState<{ id: string; name: string } | null>(null)
  const [checked, setChecked] = useState(false)
  const count = b.productCount
  // Only a checked brand takes its products; "none" leaves them with no brand.
  const search = async (q: string) =>
    (await listBrands({ q: q || undefined, status: 'APPROVED', page: 1, perPage: 8 })).items
      .filter((x) => x.id !== b.id)
      .map((x) => ({ id: x.id, name: x.name, sub: x.nameAr ?? undefined }))
  return (
    <FormDialog
      open
      onOpenChange={(next) => !next && onClose()}
      title={t.brands.deleteTitle(b.name)}
      text={count > 0 ? t.brands.deleteMove(b.name, count) : t.brands.deleteNone(b.name)}
      saveLabel={t.brands.delete}
      done={t.brands.deleted}
      danger
      check={() => {
        setChecked(true)
        return count === 0 || !!moveTo
      }}
      onSave={() => deleteBrand(b.id, count > 0 ? moveTo?.id : undefined)}
    >
      {count > 0 && (
        <SearchPick
          label={t.brands.moveTo}
          value={moveTo}
          onChange={setMoveTo}
          search={search}
          placeholder={t.brands.searchBrand}
          extra={[{ id: 'none', name: t.brands.noBrand }]}
          error={checked && !moveTo ? t.brands.chooseOne : undefined}
        />
      )}
    </FormDialog>
  )
}
