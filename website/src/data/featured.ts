import { http, USE_MOCK } from './http'
import { ApiError, reply } from './mock'
import { allStores } from './stores'
import type { AdminStore } from './types'

// The home screen's "Featured stores" rail. Today the app fills it with
// every store, in MockData.merchants order (MockApiInterceptor._home, the
// MERCHANT section); nobody chooses. Here Saba chooses which approved stores
// appear, and in what order (web-only, TODO.md).

/** Store ids in rail order. It starts as the app's rail today. */
let FEATURED: string[] = ['m-1', 'm-2', 'm-3', 'm-4', 'm-5', 'm-6', 'm-7', 'm-8']

export interface FeaturedList {
  /** Every approved store; a suspended one leaves the rail until it is reactivated. */
  stores: AdminStore[]
  /** The rail, in order: approved stores only. */
  featured: string[]
}

/** GET /admin/featured-stores (web-only route, TODO.md) */
export function getFeatured(): Promise<FeaturedList> {
  if (!USE_MOCK) return http('GET', '/admin/featured-stores')
  return reply(() => {
    const stores = allStores().filter((s) => s.status === 'APPROVED')
    const approved = new Set(stores.map((s) => s.id))
    return { stores, featured: FEATURED.filter((id) => approved.has(id)) }
  })
}

/** PUT /admin/featured-stores { storeIds } (web-only route): the whole rail, in order. */
export function saveFeatured(storeIds: string[]): Promise<FeaturedList> {
  if (!USE_MOCK) return http('PUT', '/admin/featured-stores', { storeIds })
  return reply(() => {
    const approved = new Set(allStores().filter((s) => s.status === 'APPROVED').map((s) => s.id))
    if (new Set(storeIds).size !== storeIds.length || storeIds.some((id) => !approved.has(id))) throw new ApiError('WRONG_STATE')
    // A featured store that is suspended stays chosen, at the end, for when it is reactivated.
    FEATURED = [...storeIds, ...FEATURED.filter((id) => !approved.has(id))]
    return { stores: allStores().filter((s) => s.status === 'APPROVED'), featured: storeIds }
  })
}
