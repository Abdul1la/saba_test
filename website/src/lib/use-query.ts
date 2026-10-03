import { useEffect, useState, useSyncExternalStore } from 'react'

// How screens stay fresh, the mobile app's way (BACKEND_READY.md): after any
// change, every screen asks again. Coarse on purpose: it cannot go stale.

let version = 0
const listeners = new Set<() => void>()
const loading = new Set<Promise<unknown>>()

/**
 * The server's live-update topics (BACKEND_PLAN.md §10), and the queries that
 * show each: a key equal to one of these, or starting with it.
 */
const TOPICS = {
  orders: ['orders:', 'order:', 'dashboard', 'customer:'],
  returns: ['after:', 'return:'],
  bills: ['finance:', 'bills:'],
  stores: ['stores:', 'store:', 'queue', 'dashboard', 'featured', 'reports:', 'banners'],
  // A product's count in its category and brand, and whether a banner's link still opens.
  products: ['products:', 'product:', 'store-products:', 'queue', 'dashboard', 'reports:', 'admin-categories', 'brands:', 'banners'],
  tickets: ['tickets:', 'ticket:'],
  customers: ['customers:', 'customer:'],
  reviews: ['reviews:'],
  reports: ['reports:'],
}
type Topic = keyof typeof TOPICS
const topicVersion = Object.fromEntries(Object.keys(TOPICS).map((topic) => [topic, 0])) as Record<Topic, number>

const topicsOf = (key: string) =>
  (Object.keys(TOPICS) as Topic[]).filter((topic) => TOPICS[topic].some((shown) => key === shown || (shown.endsWith(':') && key.startsWith(shown))))

/** Something about `topic` changed on the server: the queries that show it load again. Other topics are ignored. */
export function refreshTopic(topic: string): void {
  if (!(topic in TOPICS)) return
  topicVersion[topic as Topic]++
  listeners.forEach((listen) => listen())
}

/**
 * Something changed: everything on screen loads again. Settles once it has,
 * so whoever changed it can say "done" when the screen already shows it.
 */
export async function refreshAll(): Promise<void> {
  version++
  listeners.forEach((listen) => listen())
  // A turn for React to render and start the new loads, then wait for them.
  await new Promise((resolve) => setTimeout(resolve))
  await Promise.allSettled([...loading])
}

function subscribe(listen: () => void) {
  listeners.add(listen)
  return () => listeners.delete(listen)
}

interface QueryState<T> {
  data?: T
  error?: unknown
  loading: boolean
}

/**
 * Loads `load()` and again whenever `key` changes or anything is refreshed.
 * The last answer stays on screen while the next one loads, and an answer
 * that arrives after a newer request is dropped.
 */
export function useQuery<T>(load: () => Promise<T>, key: string) {
  const current = useSyncExternalStore(subscribe, () => `${version}:${topicsOf(key).map((topic) => topicVersion[topic]).join(',')}`)
  const [attempt, setAttempt] = useState(0)
  const [state, setState] = useState<QueryState<T>>({ loading: true })

  useEffect(() => {
    let live = true
    setState((previous) => ({ data: previous.data, loading: true }))
    const answer = load().then(
      (data) => live && setState({ data, loading: false }),
      (error: unknown) => live && setState({ error, loading: false }),
    )
    loading.add(answer)
    answer.finally(() => loading.delete(answer))
    return () => {
      live = false
    }
    // `load` is a new function every render; `key` says when it asks something new.
  }, [key, current, attempt])

  return { ...state, retry: () => setAttempt((n) => n + 1) }
}

export function useDebounced<T>(value: T, ms = 250): T {
  const [settled, setSettled] = useState(value)
  useEffect(() => {
    const timer = setTimeout(() => setSettled(value), ms)
    return () => clearTimeout(timer)
  }, [value, ms])
  return settled
}
