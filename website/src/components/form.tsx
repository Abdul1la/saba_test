import { useId, useRef, useState, type ComponentProps, type FormEvent, type ReactNode } from 'react'
import { Ellipsis, ImagePlus, Loader2 } from 'lucide-react'
import { toast } from 'sonner'
import { solid } from '@/components/actions'
import { errorText } from '@/components/blocks'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from '@/components/ui/dropdown-menu'
import { Label } from '@/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { uploadImage } from '@/data/catalog'
import { useI18n } from '@/lib/i18n'
import { refreshAll, useDebounced, useQuery } from '@/lib/use-query'
import { cn } from '@/lib/utils'

// The pieces of Saba's own forms (categories, banners, brands): fields, a
// picture, a search-and-pick, and the dialog that saves them.

export const fieldClass =
  'h-11 w-full rounded-xl border border-input bg-soft px-3.5 text-[15px] text-navy outline-none placeholder:text-faint focus-visible:border-primary/40 focus-visible:bg-white focus-visible:ring-4 focus-visible:ring-primary/10 aria-invalid:border-bad'

/** The server takes pictures up to 5 MB (POST /media/upload). */
const MAX_PICTURE = 5 * 1024 * 1024

function Hint({ id, error, hint }: { id?: string; error?: string; hint?: string }) {
  if (!error && !hint) return null
  return (
    <p id={id} className={cn('mt-1.5 text-[13px]', error ? 'font-medium text-bad' : 'text-muted-foreground')}>
      {error || hint}
    </p>
  )
}

export function TextField({
  label,
  value,
  onChange,
  dir,
  error,
  hint,
  autoFocus,
}: {
  label: string
  value: string
  onChange: (value: string) => void
  /** Arabic names are typed right to left whatever the page's language. */
  dir?: 'ltr' | 'rtl'
  error?: string
  hint?: string
  autoFocus?: boolean
}) {
  const id = useId()
  return (
    <div>
      <Label htmlFor={id} className="mb-2 text-sm font-medium text-navy">
        {label}
      </Label>
      <input
        id={id}
        dir={dir}
        value={value}
        autoFocus={autoFocus}
        maxLength={120}
        onChange={(e) => onChange(e.target.value)}
        aria-invalid={!!error}
        aria-describedby={`${id}-hint`}
        className={fieldClass}
      />
      <Hint id={`${id}-hint`} error={error} hint={hint} />
    </div>
  )
}

/** One of a few choices; a choice can't be '', so "none" has its own value. */
export function ChoiceField<T extends string>({
  label,
  value,
  onChange,
  options,
  placeholder,
  error,
}: {
  label: string
  value: T | ''
  onChange: (value: T) => void
  options: { value: T; label: string }[]
  placeholder?: string
  error?: string
}) {
  const id = useId()
  return (
    <div>
      <Label htmlFor={id} className="mb-2 text-sm font-medium text-navy">
        {label}
      </Label>
      <Select value={value || undefined} onValueChange={(next) => onChange(next as T)}>
        <SelectTrigger id={id} aria-invalid={!!error} className={cn(fieldClass, 'h-11 justify-between')}>
          <SelectValue placeholder={placeholder} />
        </SelectTrigger>
        <SelectContent position="popper" className="max-h-72 rounded-xl">
          {options.map((o) => (
            <SelectItem key={o.value} value={o.value}>
              {o.label}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
      <Hint id={`${id}-hint`} error={error} />
    </div>
  )
}

/** A picture, uploaded as soon as it is chosen; `value` is its url. */
export function PictureField({
  label,
  value,
  onChange,
  required = false,
  wide = false,
  error,
}: {
  label: string
  value: string | null
  onChange: (url: string | null) => void
  /** A banner needs one; a category may have none. */
  required?: boolean
  /** A banner's shape. */
  wide?: boolean
  error?: string
}) {
  const { t } = useI18n()
  const input = useRef<HTMLInputElement>(null)
  const [busy, setBusy] = useState(false)
  const [failed, setFailed] = useState<string>()

  const choose = async (file?: File) => {
    if (!file) return
    if (!file.type.startsWith('image/')) return setFailed(t.form.notPicture)
    if (file.size > MAX_PICTURE) return setFailed(t.form.tooBig)
    setBusy(true)
    setFailed(undefined)
    try {
      onChange(await uploadImage(file))
    } catch (e) {
      setFailed(errorText(e, t))
    }
    setBusy(false)
  }

  return (
    <div>
      <p className="mb-2 text-sm font-medium text-navy">{label}</p>
      <div className="flex flex-wrap items-center gap-4">
        <div className={cn('grid shrink-0 place-items-center overflow-hidden rounded-xl border border-border bg-soft', wide ? 'aspect-[2/1] w-44' : 'size-20')}>
          {value ? <img src={value} alt="" className="size-full object-cover" /> : <ImagePlus className="size-6 text-faint" />}
        </div>
        <div className="flex flex-wrap gap-2">
          <Button type="button" variant="outline" disabled={busy} onClick={() => input.current?.click()} className="h-10 rounded-xl px-4">
            {busy ? <Loader2 className="animate-spin" /> : <ImagePlus />}
            {busy ? t.form.uploading : value ? t.form.changePicture : t.form.addPicture}
          </Button>
          {value && !required && (
            <Button type="button" variant="ghost" disabled={busy} onClick={() => onChange(null)} className="h-10 rounded-xl px-4 text-muted-foreground">
              {t.form.removePicture}
            </Button>
          )}
        </div>
        <input
          ref={input}
          type="file"
          accept="image/*"
          hidden
          onChange={(e) => {
            choose(e.target.files?.[0])
            e.target.value = ''
          }}
        />
      </div>
      <Hint error={failed || error} hint={t.form.pictureHint} />
    </div>
  )
}

export interface Picked {
  id: string
  name: string
  /** A second line: its store, its Arabic name. */
  sub?: string
}

/** One thing chosen by searching for it: a product, a store, a brand. */
export function SearchPick({
  label,
  value,
  onChange,
  search,
  placeholder,
  extra = [],
  error,
}: {
  label: string
  value: Picked | null
  onChange: (value: Picked | null) => void
  search: (q: string) => Promise<Picked[]>
  placeholder: string
  /** Offered whatever is typed ("No brand"). */
  extra?: Picked[]
  error?: string
}) {
  const { t } = useI18n()
  const id = useId()
  const [q, setQ] = useState('')
  const settled = useDebounced(q.trim())
  const found = useQuery(() => search(settled), `pick:${id}:${settled}`)
  const choices = [...extra, ...(found.data ?? [])]

  return (
    <div>
      <Label htmlFor={id} className="mb-2 text-sm font-medium text-navy">
        {label}
      </Label>
      {value ? (
        <div className="flex items-center justify-between gap-3 rounded-xl border border-primary/30 bg-accent-soft px-4 py-2">
          <span className="min-w-0">
            <bdi className="block truncate text-[15px] font-medium text-navy">{value.name}</bdi>
            {value.sub && <bdi className="block truncate text-[13px] text-muted-foreground">{value.sub}</bdi>}
          </span>
          <Button type="button" variant="ghost" onClick={() => onChange(null)} className="h-9 shrink-0 rounded-lg px-3">
            {t.form.change}
          </Button>
        </div>
      ) : (
        <>
          <input id={id} type="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder={placeholder} aria-invalid={!!error} className={fieldClass} />
          <ul className="mt-2 max-h-52 divide-y divide-border/70 overflow-y-auto rounded-xl border border-border">
            {choices.map((pick) => (
              <li key={pick.id}>
                <button type="button" onClick={() => onChange(pick)} className="w-full px-4 py-2.5 text-start transition hover:bg-soft">
                  <bdi className="block truncate text-[15px] text-navy">{pick.name}</bdi>
                  {pick.sub && <bdi className="block truncate text-[13px] text-muted-foreground">{pick.sub}</bdi>}
                </button>
              </li>
            ))}
            {found.error ? (
              <li className="px-4 py-3 text-[13px] text-bad">{errorText(found.error, t)}</li>
            ) : !found.data ? (
              <li className="px-4 py-3 text-[13px] text-muted-foreground">{t.form.searching}</li>
            ) : (
              found.data.length === 0 && <li className="px-4 py-3 text-[13px] text-muted-foreground">{t.form.nothingFound}</li>
            )}
          </ul>
        </>
      )}
      <Hint error={error} />
    </div>
  )
}

/** A row's action, in words: the common ones stay on the row. */
export function RowButton({ icon, children, ...props }: { icon: ReactNode } & ComponentProps<typeof Button>) {
  return (
    <Button type="button" variant="outline" className="h-9 rounded-xl px-3 text-[13px]" {...props}>
      {icon}
      {children}
    </Button>
  )
}

export interface MenuAction {
  label: string
  icon: ReactNode
  onSelect: () => void
  /** Deleting: last, apart, in red, and it always asks first. */
  danger?: boolean
}

/** A row's other actions, in words, behind "…". */
export function MoreMenu({ label, actions }: { label: string; actions: MenuAction[] }) {
  const safe = actions.filter((a) => !a.danger)
  const danger = actions.filter((a) => a.danger)
  const item = 'h-10 gap-2.5 rounded-lg px-3 text-[14px]'
  return (
    // Not modal: an item opens a dialog, which takes the focus from here.
    <DropdownMenu modal={false}>
      <DropdownMenuTrigger asChild>
        <Button type="button" variant="ghost" size="icon" aria-label={label} title={label}>
          <Ellipsis />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="min-w-52 rounded-xl p-1.5">
        {safe.map((a) => (
          <DropdownMenuItem key={a.label} onSelect={a.onSelect} className={item}>
            {a.icon}
            {a.label}
          </DropdownMenuItem>
        ))}
        {safe.length > 0 && danger.length > 0 && <DropdownMenuSeparator />}
        {danger.map((a) => (
          <DropdownMenuItem key={a.label} variant="destructive" onSelect={a.onSelect} className={cn(item, 'font-medium')}>
            {a.icon}
            {a.label}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

/** On or off, like the app's own switches. */
export function Switch({ on, label, onChange, disabled }: { on: boolean; label: string; onChange: (on: boolean) => void; disabled?: boolean }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={on}
      aria-label={label}
      title={label}
      disabled={disabled}
      onClick={(e) => {
        e.stopPropagation()
        onChange(!on)
      }}
      className={cn(
        'relative h-7 w-12 shrink-0 rounded-full transition-colors outline-none focus-visible:ring-4 focus-visible:ring-primary/25 disabled:opacity-50',
        on ? 'bg-primary' : 'bg-border-strong',
      )}
    >
      <span className={cn('absolute top-1 size-5 rounded-full bg-white shadow transition-[inset-inline-start]', on ? 'start-6' : 'start-1')} />
    </button>
  )
}

/**
 * A form in a dialog. `check` runs the form's own checks first (false: the
 * fields say why). A refusal from the server shows in the form, in its own
 * words, and the form stays open; a save says `done`, closes, and every
 * screen asks again.
 */
export function FormDialog({
  open,
  onOpenChange,
  title,
  text,
  saveLabel,
  done,
  check,
  onSave,
  danger = false,
  children,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  title: string
  text?: string
  /** None: it only tells (something can't be done yet), and closes. */
  saveLabel?: string
  done?: string
  check?: () => boolean
  onSave?: () => Promise<unknown>
  danger?: boolean
  children?: ReactNode
}) {
  const { t } = useI18n()
  const [busy, setBusy] = useState(false)
  const [failed, setFailed] = useState<string>()
  // Opened again: no old refusal.
  const [wasOpen, setWasOpen] = useState(open)
  if (open !== wasOpen) {
    setWasOpen(open)
    if (open) setFailed(undefined)
  }

  const submit = async (event: FormEvent) => {
    event.preventDefault()
    if (busy || !onSave || (check && !check())) return
    setBusy(true)
    setFailed(undefined)
    try {
      await onSave()
      await refreshAll()
      if (done) toast.success(done)
      onOpenChange(false)
    } catch (error) {
      setFailed(errorText(error, t))
      // A refusal can come from a change made elsewhere (more products now): show where it stands.
      await refreshAll()
    }
    setBusy(false)
  }

  return (
    <Dialog open={open} onOpenChange={(next) => !busy && onOpenChange(next)}>
      <DialogContent className="gap-0 overflow-hidden rounded-3xl p-0 sm:max-w-[560px]">
        <form onSubmit={submit} noValidate className="flex max-h-[90dvh] flex-col">
          <DialogHeader className="gap-1.5 px-7 pt-7">
            <DialogTitle className="font-serif text-2xl leading-snug font-normal text-navy">{title}</DialogTitle>
            <DialogDescription className={cn('text-[15px] text-muted-foreground', !text && 'sr-only')}>{text ?? title}</DialogDescription>
          </DialogHeader>
          {children && <div className="min-h-0 space-y-5 overflow-y-auto px-7 pt-5 pb-1">{children}</div>}
          {failed && (
            <p role="alert" className="mx-7 mt-5 rounded-xl bg-bad-soft px-4 py-3 text-[14px] font-medium text-bad">
              {failed}
            </p>
          )}
          <DialogFooter className="mx-0 mt-7 mb-0 flex-row justify-end gap-2 rounded-b-3xl border-t bg-soft/60 px-7 py-4">
            <Button type="button" variant="outline" disabled={busy} onClick={() => onOpenChange(false)} className="h-10 rounded-xl px-4">
              {saveLabel ? t.cancel : t.form.close}
            </Button>
            {saveLabel && (
              <Button type="submit" disabled={busy} className={cn('h-10 rounded-xl px-5', danger ? solid.danger : solid.primary)}>
                {saveLabel}
              </Button>
            )}
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
