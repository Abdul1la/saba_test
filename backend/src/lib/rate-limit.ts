// ponytail: one process's memory. Two server processes each count on their
// own; move this behind Redis then (BACKEND_PLAN.md §12).

/** At most [limit] tries per key in each [windowSeconds]. */
export class RateLimiter {
  readonly #hits = new Map<string, { count: number; resetAt: number }>()

  constructor(
    readonly limit: number,
    readonly windowSeconds: number,
    readonly now: () => number = Date.now,
  ) {}

  /** Counts one try for [key]: 0 when allowed, else the seconds until it is. */
  take(key: string): number {
    const now = this.now()
    if (this.#hits.size > 10_000) {
      for (const [k, hit] of this.#hits) if (hit.resetAt <= now) this.#hits.delete(k)
    }
    let hit = this.#hits.get(key)
    if (!hit || hit.resetAt <= now) {
      hit = { count: 0, resetAt: now + this.windowSeconds * 1000 }
      this.#hits.set(key, hit)
    }
    hit.count += 1
    return hit.count > this.limit ? Math.ceil((hit.resetAt - now) / 1000) : 0
  }
}
