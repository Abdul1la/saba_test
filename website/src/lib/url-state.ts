import { useSearchParams } from 'react-router'

// What is on screen is kept in the address, so a link can open it
// (the dashboard's cards) and the back button undoes it.

/**
 * Filters kept in the address (?status=PENDING). A value the page does not
 * know reads as no filter. `set` takes several at once; '' removes one.
 */
export function useUrlFilters<K extends string>(allowed: Record<K, readonly string[]>) {
  const [params, setParams] = useSearchParams()
  const value = {} as Record<K, string>
  for (const key of Object.keys(allowed) as K[]) {
    const raw = params.get(key) ?? ''
    value[key] = allowed[key].includes(raw) ? raw : ''
  }
  const set = (next: Partial<Record<K, string>>) =>
    setParams(
      (p) => {
        for (const [key, v] of Object.entries(next) as [K, string][]) {
          if (v) p.set(key, v)
          else p.delete(key)
        }
        return p
      },
      { replace: true },
    )
  return [value, set] as const
}

export type SheetKind = 'store' | 'product' | 'order' | 'bills' | 'ticket' | 'return' | 'customer'
const KINDS: SheetKind[] = ['store', 'product', 'order', 'bills', 'ticket', 'return', 'customer']

/**
 * The detail sheet that is open, kept in the address (?store=m-1), so the
 * back button closes it and a link can open one. One sheet at a time; one
 * opened from another remembers it (&back=customer:cu-5550142), for Back.
 */
export function useSheet() {
  const [params, setParams] = useSearchParams()
  const kind = KINDS.find((k) => params.has(k))
  const id = kind ? (params.get(kind) ?? '') : ''
  const from = params.get('back') ?? ''
  const cut = from.indexOf(':')
  const backKind = from.slice(0, cut) as SheetKind
  const back = cut > 0 && KINDS.includes(backKind) ? { kind: backKind, id: from.slice(cut + 1) } : undefined

  const show = (next?: { kind: SheetKind; id: string }, previous?: string) =>
    setParams((p) => {
      KINDS.forEach((k) => p.delete(k))
      p.delete('back')
      if (next) p.set(next.kind, next.id)
      if (previous) p.set('back', previous)
      return p
    })

  return {
    kind,
    id,
    back,
    open: (next: SheetKind, nextId: string) => show({ kind: next, id: nextId }, kind && `${kind}:${id}`),
    goBack: () => back && show(back),
    close: () => show(),
  }
}
