import { http, USE_MOCK } from './http'
import { reply } from './mock'
import { allOrders } from './orders'
import { allProducts, waitingProducts } from './products'
import { allStores, waitingStores } from './stores'
import type { AdminOrder, OrderStatus } from './types'

export interface Waiting {
  kind: 'store' | 'product'
  id: string
  name: string
  nameAr?: string
  owner: string
  imageUrl?: string
  since: string
}

export interface Dashboard {
  storesWaiting: number
  productsWaiting: number
  stores: number
  products: number
  orders: number
  ordersByStatus: Partial<Record<OrderStatus, number>>
  recentOrders: AdminOrder[]
  /** The longest-waiting answers: nothing may wait for ever. */
  waitingLongest: Waiting[]
}

/** GET /admin/dashboard (web-only route, TODO.md) */
export function getDashboard(): Promise<Dashboard> {
  if (!USE_MOCK) return http('GET', '/admin/dashboard')
  return reply(() => {
    const stores = waitingStores()
    const products = waitingProducts()
    const orders = allOrders()
    const ordersByStatus: Partial<Record<OrderStatus, number>> = {}
    for (const order of orders) ordersByStatus[order.status] = (ordersByStatus[order.status] ?? 0) + 1

    const waiting: Waiting[] = [
      ...stores.map((s) => ({
        kind: 'store' as const,
        id: s.id,
        name: s.storeName,
        owner: s.fullName,
        imageUrl: s.logoUrl,
        since: s.submittedAt,
      })),
      ...products.map((p) => ({
        kind: 'product' as const,
        id: p.id,
        name: p.nameEn,
        nameAr: p.nameAr,
        owner: p.merchant.storeName,
        imageUrl: p.imageUrl,
        since: p.createdAt,
      })),
    ]

    return {
      storesWaiting: stores.length,
      productsWaiting: products.length,
      stores: allStores().length,
      products: allProducts().length,
      orders: orders.length,
      ordersByStatus,
      recentOrders: orders.slice(0, 5),
      waitingLongest: waiting.sort((a, b) => a.since.localeCompare(b.since)).slice(0, 4),
    }
  })
}
