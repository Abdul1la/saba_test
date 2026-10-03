import { useId, useState, type FormEvent } from 'react'
import { Navigate, useLocation, useNavigate } from 'react-router'
import { ArrowRight, FlaskConical, Package, ReceiptText, Store, TriangleAlert } from 'lucide-react'
import { BrandLogo, LanguagePill } from '@/components/app-shell'
import { errorText } from '@/components/blocks'
import { Button } from '@/components/ui/button'
import { Label } from '@/components/ui/label'
import { currentAdmin, signIn } from '@/data/auth'
import { USE_MOCK } from '@/data/http'
import { ApiError } from '@/data/mock'
import { useI18n, type Lang } from '@/lib/i18n'

const field =
  'h-12 w-full rounded-xl border border-border bg-soft px-4 text-[15px] text-navy transition outline-none placeholder:text-faint focus:border-primary/40 focus:bg-white focus:ring-4 focus:ring-primary/10'

export function LoginPage() {
  const { t, lang } = useI18n()
  const navigate = useNavigate()
  const location = useLocation()
  const [login, setLogin] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const id = useId()
  const next = (location.state as { from?: string } | null)?.from ?? '/'

  if (currentAdmin()) return <Navigate to={next} replace />

  const submit = async (event: FormEvent) => {
    event.preventDefault()
    if (!login.trim() || !password) {
      setError(t.login.required)
      return
    }
    setBusy(true)
    setError('')
    try {
      await signIn(login, password)
      navigate(next, { replace: true })
    } catch (e) {
      setError(e instanceof ApiError && e.retryAfter ? t.login.wait(inMinutes(e.retryAfter, lang)) : errorText(e, t))
      setBusy(false)
    }
  }

  return (
    <div className="grid min-h-dvh bg-bg-page lg:grid-cols-[1.05fr_1fr]">
      <aside className="relative hidden overflow-hidden bg-surface-dark p-12 lg:flex lg:flex-col">
        <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(70%_55%_at_85%_10%,color-mix(in_srgb,var(--primary)_40%,transparent),transparent_65%),radial-gradient(60%_50%_at_0%_100%,rgba(27,95,168,0.25),transparent_60%)]" />
        <div className="pointer-events-none absolute inset-0 opacity-[0.07] [background-image:linear-gradient(white_1px,transparent_1px),linear-gradient(90deg,white_1px,transparent_1px)] [background-size:48px_48px] [mask-image:radial-gradient(70%_70%_at_50%_40%,black,transparent)]" />

        <div className="relative flex items-center">
          <BrandLogo tone="white" />
        </div>

        <div className="relative mt-auto max-w-lg">
          <p className="mb-5 inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/5 px-3.5 py-1.5 text-[13px] text-white/70">
            <span className="size-1.5 rounded-full bg-lavender" />
            {t.panel}
          </p>
          <h2 className="font-serif text-[46px] leading-[1.08] text-white">{t.login.heroTitle}</h2>
          <p className="mt-5 text-[17px] leading-relaxed text-white/65">{t.login.heroText}</p>
          <div className="mt-9 flex flex-wrap gap-2.5">
            {[
              [Store, t.nav.stores],
              [Package, t.nav.products],
              [ReceiptText, t.nav.orders],
            ].map(([Icon, label]) => {
              const I = Icon as typeof Store
              return (
                <span key={String(label)} className="inline-flex items-center gap-2 rounded-xl border border-white/10 bg-white/[0.06] px-4 py-2.5 text-sm text-white/80 backdrop-blur">
                  <I className="size-4 text-lavender" strokeWidth={1.75} />
                  {String(label)}
                </span>
              )
            })}
          </div>
        </div>
      </aside>

      <main className="flex flex-col px-6 py-6 sm:px-12">
        <div className="flex items-center justify-between lg:justify-end">
          <BrandLogo tone="color" className="lg:hidden" />
          <LanguagePill />
        </div>

        <div className="mx-auto flex w-full max-w-[400px] flex-1 flex-col justify-center py-12">
          <h1 className="font-serif text-[44px] leading-tight text-navy">{t.login.title}</h1>
          <p className="mt-2 text-[16px] text-muted-foreground">{t.login.subtitle}</p>

          <form onSubmit={submit} noValidate className="mt-9 space-y-5">
            <div>
              <Label htmlFor={`${id}-login`} className="mb-2 text-sm font-medium text-navy">
                {t.login.login}
              </Label>
              <input
                id={`${id}-login`}
                dir="ltr"
                autoComplete="username"
                autoFocus
                value={login}
                onChange={(e) => setLogin(e.target.value)}
                placeholder="admin@saba.app"
                className={`${field} rtl:text-end`}
              />
            </div>
            <div>
              <Label htmlFor={`${id}-password`} className="mb-2 text-sm font-medium text-navy">
                {t.login.password}
              </Label>
              <input
                id={`${id}-password`}
                type="password"
                autoComplete="current-password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className={field}
              />
            </div>

            {error && (
              <p role="alert" className="flex items-start gap-2.5 rounded-xl bg-bad-soft px-4 py-3 text-sm text-bad">
                <TriangleAlert className="mt-0.5 size-4 shrink-0" />
                {error}
              </p>
            )}

            <Button
              type="submit"
              disabled={busy}
              className="h-12 w-full rounded-xl bg-primary text-[15px] font-semibold text-white shadow-[0_10px_24px_-12px_color-mix(in_srgb,var(--primary)_90%,transparent)] hover:bg-primary-pressed"
            >
              {t.login.submit}
              <ArrowRight data-icon="inline-end" className="rtl:rotate-180" />
            </Button>
          </form>

          {USE_MOCK && (
            <p className="mt-8 flex items-start gap-2.5 rounded-xl border border-dashed border-border bg-soft/60 px-4 py-3 text-[13px] text-muted-foreground">
              <FlaskConical className="mt-0.5 size-4 shrink-0 text-primary" strokeWidth={1.75} />
              <span>{t.login.demo}</span>
            </p>
          )}
        </div>
      </main>
    </div>
  )
}

/** "in 3 minutes" / "خلال 3 دقائق". */
function inMinutes(seconds: number, lang: Lang): string {
  return new Intl.RelativeTimeFormat(lang === 'ar' ? 'ar-u-nu-latn' : 'en').format(Math.ceil(seconds / 60), 'minute')
}
