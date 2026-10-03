import type { ReactNode } from 'react'
import { Navigate, Route, RouterProvider, createBrowserRouter, createRoutesFromElements, useLocation } from 'react-router'
import { AppShell } from '@/components/app-shell'
import { currentAdmin } from '@/data/auth'
import { I18nProvider } from '@/lib/i18n'
import { CustomersPage } from '@/pages/customers'
import { DashboardPage } from '@/pages/dashboard'
import { FeaturedPage } from '@/pages/featured'
import { FinancePage } from '@/pages/finance'
import { LoginPage } from '@/pages/login'
import { OrdersPage } from '@/pages/orders'
import { ProductsPage } from '@/pages/products'
import { QueuePage } from '@/pages/queue'
import { ReturnsPage } from '@/pages/returns'
import { BannersPage } from '@/pages/banners'
import { BrandsPage } from '@/pages/brands'
import { CategoriesPage } from '@/pages/categories'
import { ReportsPage } from '@/pages/reports'
import { ReviewsPage } from '@/pages/reviews'
import { StoresPage } from '@/pages/stores'
import { SupportPage } from '@/pages/support'

/** Only a signed-in admin gets past; anyone else goes to sign-in and back. */
function RequireAdmin({ children }: { children: ReactNode }) {
  const location = useLocation()
  if (!currentAdmin()) return <Navigate to="/login" replace state={{ from: location.pathname + location.search }} />
  return children
}

// A data router, so a page with unsaved changes (Featured stores) can hold
// a leave until the admin says so (useBlocker).
const router = createBrowserRouter(
  createRoutesFromElements(
    <>
      <Route path="/login" element={<LoginPage />} />
      <Route
        element={
          <RequireAdmin>
            <AppShell />
          </RequireAdmin>
        }
      >
        <Route index element={<DashboardPage />} />
        <Route path="queue" element={<QueuePage />} />
        <Route path="stores" element={<StoresPage />} />
        <Route path="products" element={<ProductsPage />} />
        <Route path="orders" element={<OrdersPage />} />
        <Route path="finance" element={<FinancePage />} />
        <Route path="support" element={<SupportPage />} />
        <Route path="reviews" element={<ReviewsPage />} />
        <Route path="reports" element={<ReportsPage />} />
        <Route path="categories" element={<CategoriesPage />} />
        <Route path="brands" element={<BrandsPage />} />
        <Route path="banners" element={<BannersPage />} />
        <Route path="featured" element={<FeaturedPage />} />
        <Route path="returns" element={<ReturnsPage />} />
        <Route path="customers" element={<CustomersPage />} />
      </Route>
      <Route path="*" element={<Navigate to="/" replace />} />
    </>,
  ),
)

export function App() {
  return (
    <I18nProvider>
      <RouterProvider router={router} />
    </I18nProvider>
  )
}
