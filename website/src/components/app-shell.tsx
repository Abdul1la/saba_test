import { useEffect, useId, useState, type ComponentType } from 'react'
import { NavLink, Outlet, useLocation, useNavigate } from 'react-router'
import { ClipboardCheck, Flag, FlaskConical, Globe, ImageIcon, LayoutGrid, LifeBuoy, LogOut, Menu, Package, ReceiptText, RotateCcw, Shapes, ShieldAlert, Star, Store, Tag, Users, Wallet } from 'lucide-react'
import { DetailSheets } from '@/components/detail-sheets'
import { Button } from '@/components/ui/button'
import { DirectionProvider } from '@/components/ui/direction'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { Sheet, SheetContent, SheetDescription, SheetTitle } from '@/components/ui/sheet'
import { Toaster } from '@/components/ui/sonner'
import { currentAdmin, signOut } from '@/data/auth'
import { startEvents } from '@/data/events'
import { USE_MOCK } from '@/data/http'
import { getQueue } from '@/data/queue'
import { listBrands } from '@/data/catalog'
import { listReports } from '@/data/reports'
import { listReviewReports } from '@/data/reviews'
import { listTickets } from '@/data/tickets'
import { initials } from '@/lib/format'
import { useI18n } from '@/lib/i18n'
import { useQuery } from '@/lib/use-query'
import { cn } from '@/lib/utils'

interface NavItem {
  to: string
  label: string
  icon: ComponentType<{ className?: string; strokeWidth?: number }>
  badge?: number
}

/**
 * Saba's mark (saba_test/logo/app-icon.png, redrawn: the files there are
 * small and on a cream ground): a bag whose body is cut into an S, with an
 * amber diamond under the handle. `color` is white on purple, for light
 * ground and the favicon (public/favicon.svg); `white` is purple on white,
 * for navy.
 */
export function BrandMark({ tone, className }: { tone: 'color' | 'white'; className?: string }) {
  const mask = useId()
  return (
    <svg viewBox="0 0 100 100" aria-hidden className={cn('size-10 shrink-0', className)}>
      <mask id={mask}>
        <rect width="100" height="100" fill="#000" />
        <path d="M21 38A6 6 0 0 1 27 32H72.5A6 6 0 0 1 78.5 38V73.5A10 10 0 0 1 68.5 83.5H27A6 6 0 0 1 21 77.5Z" fill="#fff" />
        <path d="M31 34V30A19 14 0 0 1 69 30V34Z" fill="#fff" />
        <path d="M36.5 57V37A13 13 0 0 1 62.5 37V44Z" fill="#000" />
        <line x1="8" y1="88.6" x2="55.7" y2="63.3" stroke="#000" strokeWidth="12" strokeLinecap="round" />
      </mask>
      <rect width="100" height="100" rx="22" fill={tone === 'color' ? 'var(--logo)' : '#fff'} />
      <rect width="100" height="100" fill={tone === 'color' ? '#fff' : 'var(--logo)'} mask={`url(#${mask})`} />
      <path d="M49.5 29L56.8 36.3L49.5 43.6L42.2 36.3Z" fill="var(--heat)" />
    </svg>
  )
}

/**
 * The mark and the name in the page's language, as the logo files set them
 * (logo-latin, logo-arabic; logo-white-* on navy): the mark on the left in
 * both.
 */
export function BrandLogo({ tone, className }: { tone: 'color' | 'white'; className?: string }) {
  const { lang } = useI18n()
  return (
    <span dir="ltr" className={cn('flex items-center gap-3', tone === 'color' ? 'text-logo' : 'text-white', className)}>
      <BrandMark tone={tone} />
      {lang === 'ar' ? (
        <span lang="ar" className="font-sans text-[28px] leading-none font-bold">
          سبأ
        </span>
      ) : (
        <span className="font-num text-[28px] leading-none">Saba</span>
      )}
    </span>
  )
}

function SidebarNav({ onNavigate }: { onNavigate?: () => void }) {
  const { t } = useI18n()
  const queue = useQuery(getQueue, 'queue')
  const waiting = queue.data ? queue.data.stores.length + queue.data.products.length : undefined
  // Open tickets: the counts are the whole list's on any page, so one row is enough.
  const tickets = useQuery(() => listTickets({ page: 1, perPage: 1 }), 'tickets:open')
  const reviews = useQuery(() => listReviewReports({ page: 1, perPage: 1 }), 'reviews:open')
  // The counts are the whole list's on any page, so one row is enough.
  const reports = useQuery(() => listReports({ page: 1, perPage: 1 }), 'reports:open')
  const brands = useQuery(() => listBrands({ page: 1, perPage: 1 }), 'brands:new')

  const groups: { label: string; items: NavItem[] }[] = [
    { label: t.nav.overview, items: [{ to: '/', label: t.nav.dashboard, icon: LayoutGrid }] },
    // By how often Saba opens them: every day, every week, and the shop's setup.
    {
      label: t.nav.daily,
      items: [
        { to: '/queue', label: t.nav.queue, icon: ClipboardCheck, badge: waiting },
        { to: '/orders', label: t.nav.orders, icon: ReceiptText },
        { to: '/reports', label: t.nav.reports, icon: ShieldAlert, badge: reports.data?.counts.OPEN },
        { to: '/reviews', label: t.nav.reviews, icon: Flag, badge: reviews.data?.counts.OPEN },
        { to: '/support', label: t.nav.support, icon: LifeBuoy, badge: tickets.data?.counts.OPEN },
        { to: '/returns', label: t.nav.returns, icon: RotateCcw },
      ],
    },
    {
      label: t.nav.weekly,
      items: [
        { to: '/stores', label: t.nav.stores, icon: Store },
        { to: '/products', label: t.nav.products, icon: Package },
        { to: '/customers', label: t.nav.customers, icon: Users },
        { to: '/finance', label: t.nav.finance, icon: Wallet },
      ],
    },
    {
      label: t.nav.setup,
      items: [
        { to: '/categories', label: t.nav.categories, icon: Shapes },
        // New: names stores typed, waiting for Saba's check.
        { to: '/brands', label: t.nav.brands, icon: Tag, badge: brands.data?.counts.PENDING },
        { to: '/banners', label: t.nav.banners, icon: ImageIcon },
        { to: '/featured', label: t.nav.featured, icon: Star },
      ],
    },
  ]

  return (
    <div className="flex h-full flex-col bg-surface-dark bg-[radial-gradient(120%_60%_at_0%_0%,color-mix(in_srgb,var(--primary)_18%,transparent),transparent_60%)]">
      <div className="flex h-[84px] shrink-0 items-center px-6">
        <BrandLogo tone="white" />
      </div>

      <nav className="flex-1 space-y-7 overflow-y-auto px-4 pt-4 pb-6">
        {groups.map((group) => (
          <div key={group.label}>
            <p className="mb-2 px-3 text-[11px] font-semibold text-white/40 uppercase ltr:tracking-[0.16em] rtl:text-xs">{group.label}</p>
            <ul className="space-y-1">
              {group.items.map((item) => (
                <li key={item.to}>
                  <NavLink
                    to={item.to}
                    end={item.to === '/'}
                    onClick={onNavigate}
                    className={({ isActive }) =>
                      cn(
                        'group flex h-11 items-center gap-3 rounded-xl px-3 text-[15px] font-medium transition-colors outline-none focus-visible:ring-2 focus-visible:ring-lavender',
                        isActive ? 'bg-primary text-white' : 'text-white/70 hover:bg-white/[0.06] hover:text-white',
                      )
                    }
                  >
                    {({ isActive }) => (
                      <>
                        <item.icon
                          className={cn('size-[19px] shrink-0', isActive ? 'text-white' : 'text-white/50 group-hover:text-white/80')}
                          strokeWidth={1.75}
                        />
                        <span className="truncate">{item.label}</span>
                        {!!item.badge && (
                          <span
                            className={cn(
                              'ms-auto grid h-5 min-w-5 place-items-center rounded-full px-1.5 text-[11px] font-semibold tabular-nums',
                              isActive ? 'bg-white text-primary' : 'bg-lavender text-navy',
                            )}
                          >
                            {item.badge}
                          </span>
                        )}
                      </>
                    )}
                  </NavLink>
                </li>
              ))}
            </ul>
          </div>
        ))}
      </nav>

      {/* The demo build only (npm run dev:demo): the real server's panel says nothing. */}
      {USE_MOCK && (
        <div className="shrink-0 p-4">
          <div className="flex items-center gap-2.5 rounded-xl border border-white/[0.07] bg-white/[0.04] px-3.5 py-3 text-[13px] text-white/55">
            <FlaskConical className="size-4 shrink-0 text-heat" strokeWidth={1.75} />
            {t.demoData}
          </div>
        </div>
      )}
    </div>
  )
}

export function LanguagePill({ className }: { className?: string }) {
  const { lang, setLang, t } = useI18n()
  return (
    <button
      type="button"
      onClick={() => setLang(lang === 'ar' ? 'en' : 'ar')}
      aria-label={t.switchTo}
      title={t.switchTo}
      className={cn(
        'inline-flex h-10 items-center gap-2 rounded-full border border-border bg-soft px-4 text-sm font-semibold text-navy transition hover:bg-white hover:shadow-sm focus-visible:ring-3 focus-visible:ring-primary/30 focus-visible:outline-none',
        className,
      )}
    >
      <Globe className="size-4 text-muted-foreground" strokeWidth={1.75} />
      {t.langShort}
    </button>
  )
}

export function AppShell() {
  const { t, dir } = useI18n()
  const location = useLocation()
  const navigate = useNavigate()
  const [menuOpen, setMenuOpen] = useState(false)
  const admin = currentAdmin()
  // Live updates while signed in (the live build only); signing out leaves the shell and closes it.
  useEffect(() => (USE_MOCK ? undefined : startEvents()), [])

  const titles: Record<string, string> = {
    '/': t.nav.dashboard,
    '/queue': t.nav.queue,
    '/stores': t.nav.stores,
    '/products': t.nav.products,
    '/orders': t.nav.orders,
    '/finance': t.nav.finance,
    '/support': t.nav.support,
    '/reviews': t.nav.reviews,
    '/reports': t.nav.reports,
    '/categories': t.nav.categories,
    '/brands': t.nav.brands,
    '/banners': t.nav.banners,
    '/featured': t.nav.featured,
    '/returns': t.nav.returns,
    '/customers': t.nav.customers,
  }

  return (
    <DirectionProvider dir={dir}>
      <div className="min-h-dvh bg-bg-page">
        <aside className="fixed inset-y-0 start-0 z-30 hidden w-[272px] lg:block">
          <SidebarNav />
        </aside>

        <Sheet open={menuOpen} onOpenChange={setMenuOpen}>
          <SheetContent side={dir === 'rtl' ? 'right' : 'left'} showCloseButton={false} className="border-0 p-0 data-[side=left]:w-[272px] data-[side=left]:sm:max-w-[272px] data-[side=right]:w-[272px] data-[side=right]:sm:max-w-[272px]">
            <SheetTitle className="sr-only">{t.menu}</SheetTitle>
            <SheetDescription className="sr-only">{t.brand}</SheetDescription>
            <SidebarNav onNavigate={() => setMenuOpen(false)} />
          </SheetContent>
        </Sheet>

        <div className="lg:ps-[272px]">
          <header className="sticky top-0 z-20 flex h-[84px] items-center gap-3 border-b border-border bg-bg-page/90 px-5 backdrop-blur-md sm:px-8 lg:px-10">
            <Button variant="ghost" size="icon-lg" className="-ms-2 lg:hidden" onClick={() => setMenuOpen(true)} aria-label={t.menu}>
              <Menu className="size-5" />
            </Button>
            <h1 className="truncate font-serif text-[22px] leading-none text-navy sm:text-[34px]">{titles[location.pathname] ?? ''}</h1>

            <div className="ms-auto flex items-center gap-3">
              <LanguagePill />
              <DropdownMenu dir={dir}>
                <DropdownMenuTrigger className="flex items-center gap-3 rounded-full py-1 ps-1 pe-1 outline-none focus-visible:ring-3 focus-visible:ring-primary/30 sm:ps-3">
                  <span className="hidden text-sm font-medium text-navy sm:block">{admin?.fullName}</span>
                  <span className="grid size-10 place-items-center rounded-full bg-lavender font-num text-lg text-navy">
                    {initials(admin?.fullName ?? '?').slice(0, 1)}
                  </span>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end" className="min-w-56 rounded-xl p-1.5">
                  <DropdownMenuLabel className="px-2.5 py-2">
                    <div className="text-sm font-medium text-navy">{admin?.fullName}</div>
                    <div className="text-xs font-normal text-muted-foreground">{admin?.email}</div>
                  </DropdownMenuLabel>
                  <DropdownMenuSeparator />
                  <DropdownMenuItem
                    className="gap-2.5 rounded-lg px-2.5 py-2"
                    onSelect={() => void signOut().then(() => navigate('/login', { replace: true }))}
                  >
                    <LogOut className="size-4 rtl:rotate-180" />
                    {t.signOut}
                  </DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenu>
            </div>
          </header>

          <main className="mx-auto max-w-[1480px] px-5 py-8 sm:px-8 lg:px-10 lg:py-9">
            <Outlet />
          </main>
        </div>

        <DetailSheets />
        <Toaster dir={dir} position={dir === 'rtl' ? 'bottom-left' : 'bottom-right'} />
      </div>
    </DirectionProvider>
  )
}
