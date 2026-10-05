import { http, USE_MOCK } from './http'
import { reply } from './mock'

/** Saba's switches (GET/PATCH /admin/settings). */
export interface Settings {
  /** On: a product a store adds or changes goes live at once, without the queue. */
  autoApproveProducts: boolean
}

let SETTINGS: Settings = { autoApproveProducts: true }

/** GET /admin/settings */
export function getSettings(): Promise<Settings> {
  if (!USE_MOCK) return http('GET', '/admin/settings')
  return reply(() => ({ ...SETTINGS }))
}

/** PATCH /admin/settings: what it leaves out stays. */
export function changeSettings(change: Partial<Settings>): Promise<Settings> {
  if (!USE_MOCK) return http('PATCH', '/admin/settings', change)
  return reply(() => {
    SETTINGS = { ...SETTINGS, ...change }
    return { ...SETTINGS }
  })
}
