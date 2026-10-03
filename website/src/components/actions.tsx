import { useId, useState, type ComponentProps, type FormEvent, type ReactNode } from 'react'
import { Ban, Check, CircleX, Eye, EyeOff, PhoneOff, RotateCcw, Trash2, X } from 'lucide-react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { errorText } from '@/components/blocks'
import { deleteCustomer, freeCustomerNumber, suspendCustomer, unsuspendCustomer, type Customer } from '@/data/customers'
import { markBillPaid, unmarkBillPaid, type Bill } from '@/data/finance'
import { approveProduct, putBackProduct, rejectProduct, takeDownProduct } from '@/data/products'
import { dismissReports, resolveReports, type ReportedItem } from '@/data/reports'
import { dismissReviewReports, removeReview, type ReportedReview } from '@/data/reviews'
import { approveStore, freeStoreNumber, rejectStore, requestStoreDeletion, suspendStore, unsuspendStore } from '@/data/stores'
import type { AdminProduct, AdminStore } from '@/data/types'
import { dayValue, money, monthName } from '@/lib/format'
import { useI18n } from '@/lib/i18n'
import { useSheet } from '@/lib/url-state'
import { refreshAll } from '@/lib/use-query'
import { cn } from '@/lib/utils'

/** How a "no" is marked when it is done: never the green tick of good news. */
const NO_MARK = {
  rejected: <CircleX className="size-4 text-bad" />,
  suspended: <Ban className="size-4 text-off" />,
  takenDown: <EyeOff className="size-4 text-off" />,
  undone: <RotateCcw className="size-4 text-off" />,
}

/**
 * Runs one answer, then every screen asks again. "Done" is said once the
 * screen shows it: a toast saying "reactivated" over a badge still reading
 * SUSPENDED tells two stories.
 */
export function useRun() {
  const { t } = useI18n()
  return async (action: () => Promise<unknown>, done: string, mark?: keyof typeof NO_MARK): Promise<boolean> => {
    let ok = false
    try {
      await action()
      ok = true
    } catch (error) {
      toast.error(errorText(error, t))
    }
    // Even a refusal ("already answered") should show where it now stands.
    await refreshAll()
    if (ok && mark) toast(done, { icon: NO_MARK[mark] })
    else if (ok) toast.success(done)
    return ok
  }
}

export const solid = {
  primary: 'bg-primary text-white hover:bg-primary-pressed',
  danger: 'bg-bad text-white hover:bg-bad/90',
}

/**
 * A confirmation, with a required reason when `withReason` is set, or a
 * required day between `date.min` and `date.max` ("2026-09-01"). The
 * reason's hint and example speak to a store unless `reasonText` says who reads it.
 */
export function ConfirmDialog({
  open,
  onOpenChange,
  title,
  text,
  confirmLabel,
  danger = false,
  withReason = false,
  reasonText,
  date,
  onConfirm,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  title: string
  text: string
  confirmLabel: string
  danger?: boolean
  withReason?: boolean
  reasonText?: { hint: string; placeholder: string }
  date?: { label: string; hint: string; min: string; max: string }
  onConfirm: (value: string) => Promise<boolean>
}) {
  const { t } = useI18n()
  const [reason, setReason] = useState('')
  const [missing, setMissing] = useState(false)
  const [busy, setBusy] = useState(false)
  const fieldId = useId()

  // Opened again: start from an empty reason (or today), not the last one typed.
  const [wasOpen, setWasOpen] = useState(open)
  if (open !== wasOpen) {
    setWasOpen(open)
    if (open) {
      setReason(date ? date.max : '')
      setMissing(false)
    }
  }

  const submit = async (event: FormEvent) => {
    event.preventDefault()
    // Days as "YYYY-MM-DD" compare as text.
    const bad = date ? !reason || reason < date.min || reason > date.max : withReason && !reason.trim()
    if (bad) {
      setMissing(true)
      return
    }
    setBusy(true)
    const ok = await onConfirm(reason.trim())
    setBusy(false)
    if (ok) onOpenChange(false)
  }

  return (
    <Dialog open={open} onOpenChange={(next) => !busy && onOpenChange(next)}>
      <DialogContent className="gap-0 overflow-hidden rounded-3xl p-0 sm:max-w-[480px]">
        {/* noValidate: our own message, in the admin's language, not the browser's. */}
        <form onSubmit={submit} noValidate>
          <DialogHeader className="gap-1.5 px-7 pt-7">
            <DialogTitle className="font-serif text-2xl leading-snug font-normal text-navy">{title}</DialogTitle>
            <DialogDescription className="text-[15px] text-muted-foreground">{text}</DialogDescription>
          </DialogHeader>
          {withReason && (
            <div className="px-7 pt-5">
              <Label htmlFor={fieldId} className="mb-2 text-sm font-medium text-navy">
                {t.reason}
              </Label>
              <Textarea
                id={fieldId}
                autoFocus
                rows={4}
                value={reason}
                onChange={(e) => {
                  setReason(e.target.value)
                  if (e.target.value.trim()) setMissing(false)
                }}
                placeholder={reasonText?.placeholder ?? t.reasonPlaceholder}
                aria-invalid={missing}
                aria-describedby={`${fieldId}-hint`}
                className="min-h-28 rounded-xl bg-soft px-3.5 py-3 text-[15px] focus-visible:bg-white"
              />
              <p id={`${fieldId}-hint`} className={cn('mt-2 text-[13px]', missing ? 'font-medium text-bad' : 'text-muted-foreground')}>
                {missing ? t.errors.REASON_REQUIRED : (reasonText?.hint ?? t.reasonHint)}
              </p>
            </div>
          )}
          {date && (
            <div className="px-7 pt-5">
              <Label htmlFor={fieldId} className="mb-2 text-sm font-medium text-navy">
                {date.label}
              </Label>
              <input
                id={fieldId}
                type="date"
                autoFocus
                min={date.min}
                max={date.max}
                value={reason}
                onChange={(e) => {
                  setReason(e.target.value)
                  setMissing(false)
                }}
                aria-invalid={missing}
                aria-describedby={`${fieldId}-hint`}
                className="h-11 w-full rounded-xl border border-input bg-soft px-3.5 text-[15px] text-navy outline-none focus-visible:border-primary/40 focus-visible:bg-white focus-visible:ring-4 focus-visible:ring-primary/10 aria-invalid:border-bad"
              />
              <p id={`${fieldId}-hint`} className={cn('mt-2 text-[13px]', missing ? 'font-medium text-bad' : 'text-muted-foreground')}>
                {missing ? t.errors.BAD_DATE : date.hint}
              </p>
            </div>
          )}
          <DialogFooter className="mx-0 mt-7 mb-0 flex-row justify-end gap-2 rounded-b-3xl border-t bg-soft/60 px-7 py-4">
            <Button type="button" variant="outline" disabled={busy} onClick={() => onOpenChange(false)} className="h-10 rounded-xl px-4">
              {t.cancel}
            </Button>
            <Button type="submit" disabled={busy} className={cn('h-10 rounded-xl px-5', danger ? solid.danger : solid.primary)}>
              {confirmLabel}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}

type Size = 'row' | 'sheet'

function ActionButton({
  size,
  tone,
  icon,
  children,
  ...props
}: { size: Size; tone: 'primary' | 'outline'; icon: ReactNode; children: ReactNode } & ComponentProps<'button'>) {
  return (
    <Button
      variant={tone === 'outline' ? 'outline' : 'default'}
      className={cn(
        size === 'row' ? 'h-9 rounded-lg px-3' : 'h-11 rounded-xl px-5 text-[15px]',
        tone === 'primary' && solid.primary,
        tone === 'outline' && 'bg-white',
      )}
      {...props}
    >
      {icon}
      {children}
    </Button>
  )
}

/**
 * Stops clicks here from also opening the row they sit in: React sends a
 * click inside a dialog up through the tree that rendered it.
 */
function Actions({ children, size }: { children: ReactNode; size: Size }) {
  return (
    <div onClick={(e) => e.stopPropagation()} className={cn('flex flex-wrap items-center gap-2', size === 'row' && 'justify-end')}>
      {children}
    </div>
  )
}

/** Waiting: approve or reject. Approved: suspend. Suspended: reactivate. */
export function StoreActions({ store, size = 'row' }: { store: AdminStore; size?: Size }) {
  const { t } = useI18n()
  const run = useRun()
  const [dialog, setDialog] = useState<'approve' | 'reject' | 'suspend' | 'unsuspend' | 'delete' | 'free' | null>(null)
  const name = store.storeName
  const close = (open: boolean) => !open && setDialog(null)
  const { status } = store
  // Deleting an owner's account: from the sheet only, once, never on a closed store.
  const canDelete = size === 'sheet' && !store.deletionRequestedAt && status !== 'CLOSED'
  // Freeing a number never checked, held by the wrong person: from the sheet only.
  const canFree = size === 'sheet' && store.phoneVerified === false && status !== 'CLOSED'

  if ((status === 'REJECTED' || status === 'CLOSED') && !canDelete && !canFree && !dialog) return null
  return (
    <Actions size={size}>
      {status === 'PENDING' && (
        <>
          <ActionButton size={size} tone="outline" icon={<X />} onClick={() => setDialog('reject')}>
            {t.reject}
          </ActionButton>
          <ActionButton size={size} tone="primary" icon={<Check />} onClick={() => setDialog('approve')}>
            {t.approve}
          </ActionButton>
        </>
      )}
      {status === 'APPROVED' && (
        <ActionButton size={size} tone="outline" icon={<Ban />} onClick={() => setDialog('suspend')}>
          {t.suspend}
        </ActionButton>
      )}
      {status === 'SUSPENDED' && (
        <ActionButton size={size} tone="primary" icon={<RotateCcw />} onClick={() => setDialog('unsuspend')}>
          {t.unsuspend}
        </ActionButton>
      )}
      {/* One dialog per action, whatever the status. An answer re-draws the page
          before its dialog closes (useRun waits for refreshAll): a dialog chosen
          by the status would switch to the next action's words, or hand its busy
          state to that action's dialog. */}
      <ConfirmDialog
        open={dialog === 'approve'}
        onOpenChange={close}
        title={t.confirm.approveStore(name)}
        text={t.confirm.approveStoreText}
        confirmLabel={t.approve}
        onConfirm={() => run(() => approveStore(store.id), t.done.approved(name))}
      />
      <ConfirmDialog
        open={dialog === 'reject'}
        onOpenChange={close}
        title={t.confirm.rejectStore(name)}
        text={t.confirm.rejectStoreText}
        confirmLabel={t.reject}
        danger
        withReason
        onConfirm={(reason) => run(() => rejectStore(store.id, reason), t.done.rejected(name), 'rejected')}
      />
      <ConfirmDialog
        open={dialog === 'suspend'}
        onOpenChange={close}
        title={t.confirm.suspend(name)}
        text={t.confirm.suspendText}
        confirmLabel={t.suspend}
        danger
        withReason
        onConfirm={(reason) => run(() => suspendStore(store.id, reason), t.done.suspended(name), 'suspended')}
      />
      <ConfirmDialog
        open={dialog === 'unsuspend'}
        onOpenChange={close}
        title={t.confirm.unsuspend(name)}
        text={t.confirm.unsuspendText}
        confirmLabel={t.unsuspend}
        onConfirm={() => run(() => unsuspendStore(store.id), t.done.unsuspended(name))}
      />
      {(canDelete || canFree) && (
        // Apart from the answers above: rare steps, at the far end.
        <div className="ms-auto flex flex-wrap gap-2">
          {canFree && (
            <ActionButton size={size} tone="outline" icon={<PhoneOff />} onClick={() => setDialog('free')}>
              {t.number.free}
            </ActionButton>
          )}
          {canDelete && (
            <ActionButton size={size} tone="outline" icon={<Trash2 />} onClick={() => setDialog('delete')}>
              {t.store.deleteAccount}
            </ActionButton>
          )}
        </div>
      )}
      <ConfirmDialog
        open={dialog === 'free'}
        onOpenChange={close}
        title={t.number.freeStoreTitle(name)}
        text={t.number.freeStoreText}
        confirmLabel={t.number.free}
        danger
        withReason
        reasonText={{ hint: t.number.reasonHint, placeholder: t.number.reasonPlaceholder }}
        onConfirm={(reason) => run(() => freeStoreNumber(store.id, reason), t.number.freedStore(name))}
      />
      <ConfirmDialog
        open={dialog === 'delete'}
        onOpenChange={close}
        title={t.store.deleteTitle}
        text={t.store.deleteText}
        confirmLabel={t.store.deleteAccount}
        danger
        onConfirm={() => run(() => requestStoreDeletion(store.id), t.store.deletionStarted(name))}
      />
    </Actions>
  )
}

/** Waiting: approve (Arabic name required) or reject. Approved: hide or show again. */
export function ProductActions({ product, size = 'row' }: { product: AdminProduct; size?: Size }) {
  const { t, pick } = useI18n()
  const run = useRun()
  const [dialog, setDialog] = useState<'approve' | 'reject' | 'takeDown' | 'putBack' | null>(null)
  const name = pick(product.nameEn, product.nameAr)
  const close = (open: boolean) => !open && setDialog(null)
  const { status, takenDown: down } = product
  const noArabic = !product.nameAr.trim()

  if (status !== 'PENDING' && status !== 'APPROVED' && !dialog) return null
  return (
    <Actions size={size}>
      {status === 'PENDING' && (
        <>
          <ActionButton size={size} tone="outline" icon={<X />} onClick={() => setDialog('reject')}>
            {t.reject}
          </ActionButton>
          <ActionButton
            size={size}
            tone="primary"
            icon={<Check />}
            disabled={noArabic}
            title={noArabic ? t.product.noArabic : undefined}
            onClick={() => setDialog('approve')}
          >
            {t.approve}
          </ActionButton>
        </>
      )}
      {status === 'APPROVED' && (
        <ActionButton
          size={size}
          tone={down ? 'primary' : 'outline'}
          icon={down ? <Eye /> : <EyeOff />}
          onClick={() => setDialog(down ? 'putBack' : 'takeDown')}
        >
          {down ? t.putBack : t.takeDown}
        </ActionButton>
      )}
      {/* One dialog per action, whatever the status: see StoreActions. */}
      <ConfirmDialog
        open={dialog === 'approve'}
        onOpenChange={close}
        title={t.confirm.approveProduct(name)}
        text={t.confirm.approveProductText}
        confirmLabel={t.approve}
        onConfirm={() => run(() => approveProduct(product.id), t.done.approved(name))}
      />
      <ConfirmDialog
        open={dialog === 'reject'}
        onOpenChange={close}
        title={t.confirm.rejectProduct(name)}
        text={t.confirm.rejectProductText}
        confirmLabel={t.reject}
        danger
        withReason
        onConfirm={(reason) => run(() => rejectProduct(product.id, reason), t.done.rejected(name), 'rejected')}
      />
      <ConfirmDialog
        open={dialog === 'takeDown'}
        onOpenChange={close}
        title={t.confirm.takeDown(name)}
        text={t.confirm.takeDownText}
        confirmLabel={t.takeDown}
        danger
        // Taking it down tells the store why, as rejecting and suspending do.
        withReason
        onConfirm={(reason) => run(() => takeDownProduct(product.id, reason), t.done.takenDown(name), 'takenDown')}
      />
      <ConfirmDialog
        open={dialog === 'putBack'}
        onOpenChange={close}
        title={t.confirm.putBack(name)}
        text={t.confirm.putBackText}
        confirmLabel={t.putBack}
        onConfirm={() => run(() => putBackProduct(product.id), t.done.putBack(name))}
      />
    </Actions>
  )
}

/** A closed month still due: record that the store paid all of it, and on which day. */
export function MarkPaidButton({ storeId, storeName, bill }: { storeId: string; storeName: string; bill: Bill }) {
  const { t, lang } = useI18n()
  const run = useRun()
  const [open, setOpen] = useState(false)
  const month = monthName(bill.month, lang)
  const [year, m] = bill.month.split('-').map(Number)
  return (
    <Actions size="row">
      <ActionButton size="row" tone="primary" icon={<Check />} onClick={() => setOpen(true)}>
        {t.finance.markPaid}
      </ActionButton>
      <ConfirmDialog
        open={open}
        onOpenChange={setOpen}
        title={t.finance.markPaidTitle(month)}
        text={t.finance.markPaidText(storeName, money(bill.owed, lang))}
        confirmLabel={t.finance.markPaid}
        // From the first of the next month (JS months count from 0) to today.
        date={{ label: t.finance.paidDate, hint: t.finance.paidDateHint, min: dayValue(new Date(year, m, 1)), max: dayValue(new Date()) }}
        onConfirm={(paidAt) => run(() => markBillPaid(storeId, bill.month, paidAt), t.finance.done(storeName, month))}
      />
    </Actions>
  )
}

/** A month marked paid by mistake: due again, after asking. */
export function UndoPaidButton({ storeId, storeName, bill }: { storeId: string; storeName: string; bill: Bill }) {
  const { t, lang } = useI18n()
  const run = useRun()
  const [open, setOpen] = useState(false)
  const month = monthName(bill.month, lang)
  return (
    <Actions size="row">
      <ActionButton size="row" tone="outline" icon={<RotateCcw />} onClick={() => setOpen(true)}>
        {t.finance.undoPaid}
      </ActionButton>
      <ConfirmDialog
        open={open}
        onOpenChange={setOpen}
        title={t.finance.undoTitle(month)}
        text={t.finance.undoText(storeName, money(bill.owed, lang))}
        confirmLabel={t.finance.undoPaid}
        danger
        onConfirm={() => run(() => unmarkBillPaid(storeId, bill.month), t.finance.undone(storeName, month), 'undone')}
      />
    </Actions>
  )
}

/** Active: suspend, with a reason. Suspended: reactivate. */
export function CustomerActions({ customer, size = 'row' }: { customer: Customer; size?: Size }) {
  const { t, pick } = useI18n()
  const run = useRun()
  const sheet = useSheet()
  const [dialog, setDialog] = useState<'suspend' | 'unsuspend' | 'delete' | 'free' | null>(null)
  const name = pick(customer.fullName, customer.fullNameAr)
  const active = customer.status === 'ACTIVE'
  const close = (open: boolean) => !open && setDialog(null)
  return (
    <Actions size={size}>
      <ActionButton size={size} tone={active ? 'outline' : 'primary'} icon={active ? <Ban /> : <RotateCcw />} onClick={() => setDialog(active ? 'suspend' : 'unsuspend')}>
        {active ? t.suspend : t.unsuspend}
      </ActionButton>
      {/* One dialog per action, whatever the status: see StoreActions. */}
      <ConfirmDialog
        open={dialog === 'suspend'}
        onOpenChange={close}
        title={t.customers.suspend(name)}
        text={t.customers.suspendText}
        confirmLabel={t.suspend}
        danger
        withReason
        // Saba's own note, not a store's to act on.
        reasonText={{ hint: t.customers.reasonHint, placeholder: t.customers.reasonPlaceholder }}
        onConfirm={(reason) => run(() => suspendCustomer(customer.id, reason), t.done.suspended(name), 'suspended')}
      />
      <ConfirmDialog
        open={dialog === 'unsuspend'}
        onOpenChange={close}
        title={t.customers.unsuspend(name)}
        text={t.customers.unsuspendText}
        confirmLabel={t.unsuspend}
        onConfirm={() => run(() => unsuspendCustomer(customer.id), t.done.unsuspended(name))}
      />
      <div className="ms-auto flex flex-wrap gap-2">
        {/* A number never checked, held by the wrong person: from the sheet only. */}
        {size === 'sheet' && customer.phoneVerified === false && (
          <ActionButton size={size} tone="outline" icon={<PhoneOff />} onClick={() => setDialog('free')}>
            {t.number.free}
          </ActionButton>
        )}
        <ActionButton size={size} tone="outline" icon={<Trash2 />} onClick={() => setDialog('delete')}>
          {t.customers.deleteAccount}
        </ActionButton>
      </div>
      <ConfirmDialog
        open={dialog === 'free'}
        onOpenChange={close}
        title={t.number.freeShopperTitle(name)}
        text={t.number.freeShopperText}
        confirmLabel={t.number.free}
        danger
        withReason
        reasonText={{ hint: t.number.reasonHint, placeholder: t.number.reasonPlaceholder }}
        // The account is gone, and its sheet with it.
        onConfirm={(reason) => run(() => freeCustomerNumber(customer.id, reason).then(() => sheet.close()), t.number.freedShopper(name))}
      />
      <ConfirmDialog
        open={dialog === 'delete'}
        onOpenChange={close}
        title={t.customers.deleteTitle}
        text={t.customers.deleteText}
        confirmLabel={t.customers.deleteAccount}
        danger
        // They leave the list, and their sheet with them: closed as soon as the account is gone.
        onConfirm={() => run(() => deleteCustomer(customer.id).then(() => sheet.close()), t.customers.deleted(name))}
      />
    </Actions>
  )
}

/** An open reported review: remove it, or dismiss its reports and keep it. */
export function ReviewActions({ review }: { review: ReportedReview }) {
  const { t } = useI18n()
  const run = useRun()
  const [dialog, setDialog] = useState<'remove' | 'dismiss' | null>(null)
  const close = (open: boolean) => !open && setDialog(null)
  return (
    <Actions size="row">
      <ActionButton size="row" tone="outline" icon={<Check />} onClick={() => setDialog('dismiss')}>
        {t.reported.dismiss}
      </ActionButton>
      <ActionButton size="row" tone="primary" icon={<X />} onClick={() => setDialog('remove')}>
        {t.reported.remove}
      </ActionButton>
      <ConfirmDialog
        open={dialog === 'remove'}
        onOpenChange={close}
        title={t.reported.confirmRemove(review.store.storeName)}
        text={t.reported.confirmRemoveText}
        confirmLabel={t.reported.remove}
        danger
        onConfirm={() => run(() => removeReview(review.id), t.reported.removed)}
      />
      <ConfirmDialog
        open={dialog === 'dismiss'}
        onOpenChange={close}
        title={t.reported.confirmDismiss}
        text={t.reported.confirmDismissText}
        confirmLabel={t.reported.dismiss}
        onConfirm={() => run(() => dismissReviewReports(review.id), t.reported.dismissed)}
      />
    </Actions>
  )
}

/** An open report: mark it handled once Saba has acted with its own tools, or dismiss it. */
export function ReportActions({ item }: { item: ReportedItem }) {
  const { t } = useI18n()
  const run = useRun()
  const [dialog, setDialog] = useState<'resolve' | 'dismiss' | null>(null)
  const close = (open: boolean) => !open && setDialog(null)
  return (
    <Actions size="row">
      <ActionButton size="row" tone="outline" icon={<X />} onClick={() => setDialog('dismiss')}>
        {t.reports.dismiss}
      </ActionButton>
      <ActionButton size="row" tone="primary" icon={<Check />} onClick={() => setDialog('resolve')}>
        {t.reports.resolve}
      </ActionButton>
      <ConfirmDialog
        open={dialog === 'resolve'}
        onOpenChange={close}
        title={t.reports.confirmResolve}
        text={t.reports.confirmResolveText[item.type]}
        confirmLabel={t.reports.resolve}
        onConfirm={() => run(() => resolveReports(item), t.reports.resolved)}
      />
      <ConfirmDialog
        open={dialog === 'dismiss'}
        onOpenChange={close}
        title={t.reports.confirmDismiss}
        text={t.reports.confirmDismissText}
        confirmLabel={t.reports.dismiss}
        onConfirm={() => run(() => dismissReports(item), t.reports.dismissed)}
      />
    </Actions>
  )
}
