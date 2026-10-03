import { useState } from 'react'
import { ArrowDown, ArrowUp, ImageIcon, Link2Off, Pencil, Plus, Trash2 } from 'lucide-react'
import { useRun } from '@/components/actions'
import { ContentCard, EmptyState, ErrorState, PageIntro } from '@/components/blocks'
import { ChoiceField, FormDialog, MoreMenu, PictureField, RowButton, SearchPick, Switch, TextField, type Picked } from '@/components/form'
import { Button } from '@/components/ui/button'
import { Label } from '@/components/ui/label'
import { addBanner, changeBanner, deleteBanner, listAdminCategories, listBanners, orderBanners, type AdminBanner, type BannerInput, type LinkType } from '@/data/catalog'
import { listProducts } from '@/data/products'
import { listStores } from '@/data/stores'
import { useI18n } from '@/lib/i18n'
import { useQuery } from '@/lib/use-query'
import { IconButton, RowsSkeleton } from './categories'

type Open = { kind: 'add' } | { kind: 'edit' | 'delete'; id: string }

/** A banner as a save sends it, with `change` on top: a PUT sends the whole banner. */
const inputOf = (b: AdminBanner, change: Partial<BannerInput> = {}): BannerInput => ({
  imageUrl: b.imageUrl ?? '',
  titleEn: b.titleEn,
  titleAr: b.titleAr,
  subtitleEn: b.subtitleEn,
  subtitleAr: b.subtitleAr,
  link: b.link && { type: b.link.type, id: b.link.id },
  isActive: b.isActive,
  ...change,
})

export function BannersPage() {
  const { t } = useI18n()
  const run = useRun()
  const list = useQuery(listBanners, 'banners')
  const [open, setOpen] = useState<Open | null>(null)
  const [busy, setBusy] = useState(false)
  const banners = list.data ?? []
  const current = open && open.kind !== 'add' ? banners.find((b) => b.id === open.id) : undefined
  const close = () => setOpen(null)

  const act = async (action: () => Promise<unknown>, done: string) => {
    setBusy(true)
    await run(action, done)
    setBusy(false)
  }
  /** Home's whole new order; the server refuses an out-of-date one (409). */
  const move = (from: number, to: number) => {
    const ids = banners.map((b) => b.id)
    ids.splice(to, 0, ...ids.splice(from, 1))
    act(() => orderBanners(ids), t.banners.moved)
  }

  return (
    <>
      <PageIntro>{t.banners.intro}</PageIntro>
      <ContentCard
        icon={ImageIcon}
        title={t.banners.cardTitle}
        description={t.banners.cardText}
        actions={
          <Button onClick={() => setOpen({ kind: 'add' })} className="h-10 rounded-full px-5">
            <Plus />
            {t.banners.add}
          </Button>
        }
      >
        {list.error ? (
          <ErrorState error={list.error} onRetry={list.retry} />
        ) : !list.data ? (
          <RowsSkeleton />
        ) : banners.length === 0 ? (
          <EmptyState icon={ImageIcon} title={t.banners.none} text={t.banners.noneText} />
        ) : (
          <ol className="divide-y divide-border/70">
            {banners.map((b, i) => (
              <li key={b.id} className="flex flex-wrap items-center gap-x-4 gap-y-3 py-4">
                <span className="flex min-w-0 flex-1 basis-72 items-center gap-3 sm:gap-4">
                  <span className="grid size-8 shrink-0 place-items-center rounded-full bg-surface-dark font-num text-[15px] text-white tabular-nums max-sm:hidden">{i + 1}</span>
                  <span className="grid aspect-[2/1] w-24 shrink-0 place-items-center overflow-hidden rounded-xl border border-border bg-soft sm:w-36">
                    {b.imageUrl ? <img src={b.imageUrl} alt="" className="size-full object-cover" /> : <ImageIcon className="size-5 text-faint" />}
                  </span>
                  <BannerWords banner={b} />
                </span>
                <span className="ms-auto flex flex-wrap items-center justify-end gap-1.5">
                  <span className="flex items-center gap-2 pe-2">
                    <Switch
                      on={b.isActive}
                      label={t.banners.switchLabel}
                      disabled={busy}
                      onChange={() => act(() => changeBanner(b.id, inputOf(b, { isActive: !b.isActive })), b.isActive ? t.banners.turnedOff : t.banners.turnedOn)}
                    />
                    <span className="w-16 text-[13px] font-medium text-navy">{b.isActive ? t.banners.onHome : t.banners.off}</span>
                  </span>
                  <IconButton label={t.featured.up} disabled={busy || i === 0} onClick={() => move(i, i - 1)}>
                    <ArrowUp />
                  </IconButton>
                  <IconButton label={t.featured.down} disabled={busy || i === banners.length - 1} onClick={() => move(i, i + 1)}>
                    <ArrowDown />
                  </IconButton>
                  <RowButton icon={<Pencil />} onClick={() => setOpen({ kind: 'edit', id: b.id })}>
                    {t.banners.edit}
                  </RowButton>
                  <MoreMenu
                    label={t.form.more(b.titleEn ?? t.banners.noWords)}
                    actions={[{ label: t.banners.deleteMenu, icon: <Trash2 />, danger: true, onSelect: () => setOpen({ kind: 'delete', id: b.id }) }]}
                  />
                </span>
              </li>
            ))}
          </ol>
        )}
      </ContentCard>

      {open?.kind === 'add' && <BannerForm onClose={close} />}
      {open?.kind === 'edit' && current && <BannerForm key={current.id} editing={current} onClose={close} />}
      {open?.kind === 'delete' && current && (
        <FormDialog
          open
          onOpenChange={(next) => !next && close()}
          title={t.banners.deleteTitle}
          text={t.banners.deleteText}
          saveLabel={t.banners.delete}
          done={t.banners.deleted}
          danger
          onSave={() => deleteBanner(current.id)}
        />
      )}
    </>
  )
}

function BannerWords({ banner: b }: { banner: AdminBanner }) {
  const { t, lang } = useI18n()
  // Both languages or neither: the admin's own first.
  const title = lang === 'ar' ? b.titleAr : b.titleEn
  const subtitle = lang === 'ar' ? b.subtitleAr : b.subtitleEn
  return (
    <span className="min-w-0">
      {title ? <bdi className="line-clamp-2 block text-[15px] font-medium text-navy">{title}</bdi> : <span className="block text-[15px] text-muted-foreground">{t.banners.noWords}</span>}
      {subtitle && <bdi className="line-clamp-2 block text-[13px] text-muted-foreground">{subtitle}</bdi>}
      <span className="block text-[13px] text-muted-foreground">
        {b.link ? t.banners.opens(t.banners.linkType[b.link.type], b.link.name ?? t.banners.gone) : t.banners.opensNothing}
      </span>
      {b.linkBroken && (
        <span className="mt-1 flex items-center gap-1.5 text-[13px] font-medium text-bad">
          <Link2Off className="size-3.5 shrink-0" />
          {t.banners.linkBroken}
        </span>
      )}
    </span>
  )
}

const NONE = 'NONE'

function BannerForm({ editing, onClose }: { editing?: AdminBanner; onClose: () => void }) {
  const { t } = useI18n()
  const [imageUrl, setImageUrl] = useState(editing?.imageUrl ?? null)
  const [titleEn, setTitleEn] = useState(editing?.titleEn ?? '')
  const [titleAr, setTitleAr] = useState(editing?.titleAr ?? '')
  const [subtitleEn, setSubtitleEn] = useState(editing?.subtitleEn ?? '')
  const [subtitleAr, setSubtitleAr] = useState(editing?.subtitleAr ?? '')
  const [linkType, setLinkType] = useState<LinkType | typeof NONE>(editing?.link?.type ?? NONE)
  const [target, setTarget] = useState<Picked | null>(editing?.link ? { id: editing.link.id, name: editing.link.name ?? t.banners.gone } : null)
  const [isActive, setIsActive] = useState(editing?.isActive ?? true)
  const [checked, setChecked] = useState(false)

  /** Each pair in both languages or neither: the empty one says so. */
  const pairError = (mine: string, other: string) => (checked && !mine.trim() && !!other.trim() ? t.form.bothOrNeither : undefined)
  const text = (value: string) => value.trim() || null

  const save = () => {
    const input: BannerInput = {
      imageUrl: imageUrl!,
      titleEn: text(titleEn),
      titleAr: text(titleAr),
      subtitleEn: text(subtitleEn),
      subtitleAr: text(subtitleAr),
      link: linkType === NONE || !target ? null : { type: linkType, id: target.id },
      isActive,
    }
    return editing ? changeBanner(editing.id, input) : addBanner(input)
  }

  return (
    <FormDialog
      open
      onOpenChange={(next) => !next && onClose()}
      title={editing ? t.banners.editTitle : t.banners.addTitle}
      text={editing ? t.banners.editText : t.banners.addText}
      saveLabel={t.banners.save}
      done={editing ? t.banners.saved : t.banners.added}
      check={() => {
        setChecked(true)
        const pairs = [
          [titleEn, titleAr],
          [subtitleEn, subtitleAr],
        ].every(([en, ar]) => !!en.trim() === !!ar.trim())
        return !!imageUrl && pairs && (linkType === NONE || !!target)
      }}
      onSave={save}
    >
      <PictureField label={t.banners.picture} value={imageUrl} onChange={setImageUrl} required wide error={checked && !imageUrl ? t.banners.pictureRequired : undefined} />
      <p className="text-[13px] text-muted-foreground">{t.banners.wordsHint}</p>
      <div className="grid gap-4 sm:grid-cols-2">
        <TextField label={t.banners.titleEn} value={titleEn} onChange={setTitleEn} dir="ltr" error={pairError(titleEn, titleAr)} />
        <TextField label={t.banners.titleAr} value={titleAr} onChange={setTitleAr} dir="rtl" error={pairError(titleAr, titleEn)} />
        <TextField label={t.banners.subtitleEn} value={subtitleEn} onChange={setSubtitleEn} dir="ltr" error={pairError(subtitleEn, subtitleAr)} />
        <TextField label={t.banners.subtitleAr} value={subtitleAr} onChange={setSubtitleAr} dir="rtl" error={pairError(subtitleAr, subtitleEn)} />
      </div>
      <ChoiceField
        label={t.banners.link}
        value={linkType}
        onChange={(next) => {
          setLinkType(next)
          setTarget(null)
        }}
        options={[
          { value: NONE, label: t.banners.linkNone },
          ...(['PRODUCT', 'STORE', 'CATEGORY'] as const).map((type) => ({ value: type, label: t.banners.linkChoice[type] })),
        ]}
      />
      {linkType !== NONE && <LinkTarget type={linkType} value={target} onChange={setTarget} error={checked && !target ? t.banners.chooseLink : undefined} />}
      <div className="flex items-center justify-between gap-4 rounded-xl border border-border px-4 py-3">
        <Label className="text-[15px] font-medium text-navy">{t.banners.isActive}</Label>
        <Switch on={isActive} label={t.banners.isActive} onChange={setIsActive} />
      </div>
    </FormDialog>
  )
}

/** What the banner opens: a product or a store found by searching, or a category from the tree. */
function LinkTarget({ type, value, onChange, error }: { type: LinkType; value: Picked | null; onChange: (value: Picked | null) => void; error?: string }) {
  const { t, pick, city } = useI18n()
  if (type === 'CATEGORY') return <CategoryTarget value={value} onChange={onChange} error={error} />
  const search =
    type === 'PRODUCT'
      ? async (q: string) =>
          (await listProducts({ q: q || undefined, status: 'APPROVED', page: 1, perPage: 8 })).items.map((p) => ({
            id: p.id,
            name: pick(p.nameEn, p.nameAr),
            sub: p.merchant.storeName,
          }))
      : async (q: string) =>
          (await listStores({ q: q || undefined, status: 'APPROVED', page: 1, perPage: 8 })).items.map((s) => ({ id: s.id, name: s.storeName, sub: city(s.governorate) }))
  return (
    <SearchPick
      key={type}
      label={t.banners.linkChoice[type]}
      value={value}
      onChange={onChange}
      search={search}
      placeholder={type === 'PRODUCT' ? t.banners.searchProduct : t.banners.searchStore}
      error={error}
    />
  )
}

function CategoryTarget({ value, onChange, error }: { value: Picked | null; onChange: (value: Picked | null) => void; error?: string }) {
  const { t, pick } = useI18n()
  const tree = useQuery(listAdminCategories, 'admin-categories')
  // A hidden category opens nothing on Home, so it isn't offered.
  const options = (tree.data ?? [])
    .filter((c) => !c.hidden)
    .flatMap((c) => [
      { value: c.id, label: pick(c.name, c.nameAr) },
      ...c.children.filter((s) => !s.hidden).map((s) => ({ value: s.id, label: `${pick(c.name, c.nameAr)} › ${pick(s.name, s.nameAr)}` })),
    ])
  return (
    <ChoiceField
      label={t.banners.linkChoice.CATEGORY}
      value={value?.id ?? ''}
      onChange={(id) => onChange({ id, name: options.find((o) => o.value === id)?.label ?? '' })}
      options={options}
      placeholder={t.banners.chooseCategory}
      error={error}
    />
  )
}
