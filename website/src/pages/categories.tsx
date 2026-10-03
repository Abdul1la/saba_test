import { useState, type ComponentProps } from 'react'
import { ArrowDown, ArrowUp, Eye, EyeOff, FolderPlus, Pencil, Plus, Shapes, Trash2 } from 'lucide-react'
import { useRun } from '@/components/actions'
import { ContentCard, EmptyState, ErrorState, PageIntro, StatusBadge, Thumb } from '@/components/blocks'
import { ChoiceField, FormDialog, MoreMenu, PictureField, RowButton, TextField } from '@/components/form'
import { Button } from '@/components/ui/button'
import { Label } from '@/components/ui/label'
import { Skeleton } from '@/components/ui/skeleton'
import { addCategory, changeCategory, deleteCategory, listAdminCategories, orderCategories, type AdminCategory, type CategoryInput } from '@/data/catalog'
import { useI18n } from '@/lib/i18n'
import { useQuery } from '@/lib/use-query'

/** Which dialog is open. Hide keeps the state it was opened in, so its words don't flip as it saves. */
type Open = { kind: 'add'; parentId: string | null } | { kind: 'edit' | 'delete'; id: string } | { kind: 'hide'; id: string; hidden: boolean }

/** A choice can't be '': the top level's own value. */
const TOP = 'top'

/** Every category: each top-level one, then its sub-categories. */
const flat = (tops: AdminCategory[]) => tops.flatMap((c) => [c, ...c.children])

export function CategoriesPage() {
  const { t } = useI18n()
  const run = useRun()
  const list = useQuery(listAdminCategories, 'admin-categories')
  const [open, setOpen] = useState<Open | null>(null)
  const [moving, setMoving] = useState(false)
  const tops = list.data ?? []
  // A dialog reads its category as it is now: its product count can change under it.
  const current = open && open.kind !== 'add' ? flat(tops).find((c) => c.id === open.id) : undefined
  const close = () => setOpen(null)

  /** One level's whole new order; the server refuses an out-of-date one (409). */
  const move = async (level: AdminCategory[], parentId: string | null, from: number, to: number) => {
    const ids = level.map((c) => c.id)
    ids.splice(to, 0, ...ids.splice(from, 1))
    setMoving(true)
    await run(() => orderCategories(parentId, ids), t.categories.moved)
    setMoving(false)
  }

  return (
    <>
      <PageIntro>{t.categories.intro}</PageIntro>
      <ContentCard
        icon={Shapes}
        title={t.categories.cardTitle}
        description={t.categories.cardText}
        actions={
          <Button onClick={() => setOpen({ kind: 'add', parentId: null })} className="h-10 rounded-full px-5">
            <Plus />
            {t.categories.add}
          </Button>
        }
      >
        {list.error ? (
          <ErrorState error={list.error} onRetry={list.retry} />
        ) : !list.data ? (
          <RowsSkeleton />
        ) : tops.length === 0 ? (
          <EmptyState icon={Shapes} title={t.categories.none} text={t.categories.noneText} />
        ) : (
          <ol className="divide-y divide-border/70">
            {tops.map((c, i) => (
              <li key={c.id}>
                <Row category={c} index={i} count={tops.length} busy={moving} onMove={(to) => move(tops, null, i, to)} onOpen={setOpen} />
                {c.children.length > 0 && (
                  <ol className="mb-3 ms-5 divide-y divide-border/50 border-s-2 border-border ps-4 sm:ms-14">
                    {c.children.map((s, j) => (
                      <li key={s.id}>
                        <Row category={s} index={j} count={c.children.length} busy={moving} onMove={(to) => move(c.children, c.id, j, to)} onOpen={setOpen} />
                      </li>
                    ))}
                  </ol>
                )}
              </li>
            ))}
          </ol>
        )}
      </ContentCard>

      {open?.kind === 'add' && <CategoryForm key={`add:${open.parentId}`} tops={tops} parentId={open.parentId} onClose={close} />}
      {open?.kind === 'edit' && current && <CategoryForm key={`edit:${current.id}`} tops={tops} editing={current} parentId={current.parentId} onClose={close} />}
      {open?.kind === 'hide' && current && <HideCategory category={current} hidden={open.hidden} onClose={close} />}
      {open?.kind === 'delete' && current && <DeleteCategory category={current} tops={tops} onClose={close} />}
    </>
  )
}

function Row({
  category: c,
  index,
  count,
  busy,
  onMove,
  onOpen,
}: {
  category: AdminCategory
  index: number
  count: number
  busy: boolean
  onMove: (to: number) => void
  onOpen: (open: Open) => void
}) {
  const { t, pick } = useI18n()
  const sub = c.parentId !== null
  return (
    <div className="flex flex-wrap items-center gap-x-3 gap-y-2 py-3">
      <span className="flex min-w-0 flex-1 basis-60 items-center gap-3">
        <Thumb src={c.imageUrl ?? undefined} name={c.name} className={sub ? 'size-9' : undefined} />
        <span className="min-w-0">
          <span className="flex flex-wrap items-center gap-2">
            <bdi className="truncate text-[15px] font-medium text-navy">{pick(c.name, c.nameAr)}</bdi>
            {c.hidden && <StatusBadge tone="off">{t.categories.hiddenBadge}</StatusBadge>}
          </span>
          <span className="block truncate text-[13px] text-muted-foreground">
            <bdi>{pick(c.nameAr, c.name)}</bdi> · {t.categories.count(c.productCount)}
          </span>
        </span>
      </span>
      <span className="ms-auto flex flex-wrap items-center justify-end gap-1.5">
        <IconButton label={t.featured.up} disabled={busy || index === 0} onClick={() => onMove(index - 1)}>
          <ArrowUp />
        </IconButton>
        <IconButton label={t.featured.down} disabled={busy || index === count - 1} onClick={() => onMove(index + 1)}>
          <ArrowDown />
        </IconButton>
        <RowButton icon={<Pencil />} onClick={() => onOpen({ kind: 'edit', id: c.id })}>
          {t.categories.edit}
        </RowButton>
        {!sub && (
          <RowButton icon={<FolderPlus />} onClick={() => onOpen({ kind: 'add', parentId: c.id })}>
            {t.categories.addSub}
          </RowButton>
        )}
        <MoreMenu
          label={t.form.more(pick(c.name, c.nameAr))}
          actions={[
            {
              label: c.hidden ? t.categories.showMenu : t.categories.hideMenu,
              icon: c.hidden ? <Eye /> : <EyeOff />,
              onSelect: () => onOpen({ kind: 'hide', id: c.id, hidden: c.hidden }),
            },
            { label: t.categories.deleteMenu, icon: <Trash2 />, danger: true, onSelect: () => onOpen({ kind: 'delete', id: c.id }) },
          ]}
        />
      </span>
    </div>
  )
}

export function IconButton({ label, ...props }: { label: string } & ComponentProps<typeof Button>) {
  return <Button type="button" variant="ghost" size="icon" aria-label={label} title={label} {...props} />
}

function CategoryForm({ tops, editing, parentId: startParent, onClose }: { tops: AdminCategory[]; editing?: AdminCategory; parentId: string | null; onClose: () => void }) {
  const { t, pick } = useI18n()
  const [name, setName] = useState(editing?.name ?? '')
  const [nameAr, setNameAr] = useState(editing?.nameAr ?? '')
  const [parentId, setParentId] = useState(startParent)
  const [imageUrl, setImageUrl] = useState(editing?.imageUrl ?? null)
  const [checked, setChecked] = useState(false)
  const missing = (value: string) => (checked && !value.trim() ? t.form.required : undefined)
  const parent = tops.find((c) => c.id === startParent)
  // Two levels: one with sub-categories stays at the top.
  const locked = !!editing && editing.children.length > 0

  const save = () => {
    const input: CategoryInput = { name: name.trim(), nameAr: nameAr.trim(), parentId, imageUrl }
    if (!editing) return addCategory(input)
    // Only what changed: what a PATCH leaves out stays.
    const change = Object.fromEntries(Object.entries(input).filter(([key, value]) => value !== editing[key as keyof CategoryInput]))
    return changeCategory(editing.id, change)
  }

  return (
    <FormDialog
      open
      onOpenChange={(next) => !next && onClose()}
      title={
        editing
          ? t.categories.editTitle(pick(editing.name, editing.nameAr))
          : parent
            ? t.categories.addSubTitle(pick(parent.name, parent.nameAr))
            : t.categories.addTitle
      }
      text={editing ? t.categories.editText : t.categories.addText}
      saveLabel={t.categories.save}
      done={editing ? t.categories.saved : t.categories.added}
      check={() => {
        setChecked(true)
        return !!name.trim() && !!nameAr.trim()
      }}
      onSave={save}
    >
      <TextField label={t.categories.name} value={name} onChange={setName} dir="ltr" error={missing(name)} autoFocus />
      <TextField label={t.categories.nameAr} value={nameAr} onChange={setNameAr} dir="rtl" error={missing(nameAr)} />
      {locked ? (
        <div>
          <Label className="mb-2 text-sm font-medium text-navy">{t.categories.parent}</Label>
          <p className="text-[14px] text-muted-foreground">{t.categories.parentLocked}</p>
        </div>
      ) : (
        <ChoiceField
          label={t.categories.parent}
          value={parentId ?? TOP}
          onChange={(next) => setParentId(next === TOP ? null : next)}
          options={[
            { value: TOP, label: t.categories.topLevel },
            ...tops.filter((c) => c.id !== editing?.id).map((c) => ({ value: c.id, label: pick(c.name, c.nameAr) })),
          ]}
        />
      )}
      <PictureField label={t.categories.picture} value={imageUrl} onChange={setImageUrl} />
    </FormDialog>
  )
}

function HideCategory({ category: c, hidden, onClose }: { category: AdminCategory; hidden: boolean; onClose: () => void }) {
  const { t, pick } = useI18n()
  const name = pick(c.name, c.nameAr)
  return (
    <FormDialog
      open
      onOpenChange={(next) => !next && onClose()}
      title={hidden ? t.categories.showTitle(name) : t.categories.hideTitle(name)}
      text={hidden ? t.categories.showText : t.categories.hideText}
      saveLabel={hidden ? t.categories.show : t.categories.hide}
      done={hidden ? t.categories.shown : t.categories.hidden}
      onSave={() => changeCategory(c.id, { hidden: !hidden })}
    />
  )
}

function DeleteCategory({ category: c, tops, onClose }: { category: AdminCategory; tops: AdminCategory[]; onClose: () => void }) {
  const { t, pick, lang } = useI18n()
  const [moveTo, setMoveTo] = useState('')
  const [checked, setChecked] = useState(false)
  const count = c.productCount
  const name = pick(c.name, c.nameAr)
  // Not yet: it says why, and only closes.
  if (c.children.length > 0) {
    const list = c.children.map((s) => pick(s.name, s.nameAr)).join(lang === 'ar' ? '، ' : ', ')
    return <FormDialog open onOpenChange={(next) => !next && onClose()} title={t.categories.cantDelete(name)} text={t.categories.hasChildren(name, list)} />
  }
  const options = flat(tops)
    .filter((x) => x.id !== c.id)
    .map((x) => {
      const parent = tops.find((p) => p.id === x.parentId)
      const label = (parent ? `${pick(parent.name, parent.nameAr)} › ` : '') + pick(x.name, x.nameAr)
      return { value: x.id, label: x.hidden ? `${label} ${t.categories.hiddenMark}` : label }
    })
  return (
    <FormDialog
      open
      onOpenChange={(next) => !next && onClose()}
      title={t.categories.deleteTitle(name)}
      text={count > 0 ? t.categories.deleteMove(name, count) : t.categories.deleteNone(name)}
      saveLabel={t.categories.delete}
      done={t.categories.deleted}
      danger
      check={() => {
        setChecked(true)
        return count === 0 || !!moveTo
      }}
      onSave={() => deleteCategory(c.id, count > 0 ? moveTo : undefined)}
    >
      {count > 0 && (
        <ChoiceField
          label={t.categories.moveTo}
          value={moveTo}
          onChange={setMoveTo}
          options={options}
          placeholder={t.categories.chooseCategory}
          error={checked && !moveTo ? t.form.required : undefined}
        />
      )}
    </FormDialog>
  )
}

export function RowsSkeleton() {
  return (
    <div aria-busy="true" className="space-y-3">
      {[0, 1, 2, 3].map((i) => (
        <Skeleton key={i} className="h-14 rounded-xl" />
      ))}
    </div>
  )
}
