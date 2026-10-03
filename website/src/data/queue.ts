import { http, USE_MOCK } from './http'
import { reply } from './mock'
import { waitingProducts } from './products'
import { waitingStores } from './stores'
import type { AdminProduct, AdminStore } from './types'

export interface Queue {
  stores: AdminStore[]
  products: AdminProduct[]
}

/** GET /admin/queue — everything waiting for an answer, oldest first. */
export function getQueue(): Promise<Queue> {
  if (!USE_MOCK) return http('GET', '/admin/queue')
  return reply(() => ({ stores: waitingStores(), products: waitingProducts() }))
}
