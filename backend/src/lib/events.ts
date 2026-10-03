import type { Connection, Pool } from '../db/pool.js'
import type { Role } from './tokens.js'

// Live updates (BACKEND_PLAN.md §10): who has a stream open, and one small
// message to each account a change is about, `{"topic": "orders", "id": "12"}`,
// sent only once the change's transaction has committed. Never to anyone else:
// a message is addressed to accounts by id, or to Saba's admins.
//
// ponytail: held in this process's memory. With two server processes, this
// file publishes through Redis instead (§12); nothing that calls it changes.

/** What changed. The app reads `orders` and `notifications`; the web the rest (contract §5). */
export type Topic = 'orders' | 'notifications' | 'returns' | 'bills' | 'stores' | 'products' | 'tickets' | 'customers' | 'reviews' | 'reports'

/** Who is told: one account, or every admin with a stream open. */
export type Audience = number | 'ADMINS'

export interface Listener {
  userId: number
  role: Role
  send(topic: Topic, id: string | undefined): void
  close(): void
}

const listeners = new Set<Listener>()

/** Starts delivering to [listener]; the returned function stops it. */
export function listen(listener: Listener): () => void {
  listeners.add(listener)
  return () => void listeners.delete(listener)
}

function deliver(to: Audience, topic: Topic, id: string | undefined): void {
  for (const listener of listeners) {
    if (to === 'ADMINS' ? listener.role !== 'ADMIN' : listener.userId !== to) continue
    // A stream that fails to take a message never fails the change behind it,
    // which has already been committed; the app catches up when it reconnects.
    try {
      listener.send(topic, id)
    } catch {
      listener.close()
    }
  }
}

type Change = [Audience, Topic, string | undefined]

/** What waits for a transaction to commit, by its connection: live changes, and other work (pushes). */
const outboxes = new WeakMap<Connection, { changes: Change[]; tasks: (() => void)[] }>()

/**
 * Tells [to] that [topic] changed: once [db]'s transaction commits, or at
 * once when [db] is not in one (its write has already been committed).
 */
export function publish(db: Pool | Connection, to: Audience | readonly Audience[], topic: Topic, id?: string | number): void {
  const outbox = outboxes.get(db as Connection)
  for (const one of Array.isArray(to) ? to : [to]) {
    const change: Change = [one, topic, id === undefined ? undefined : String(id)]
    if (outbox) outbox.changes.push(change)
    else deliver(...change)
  }
}

/** Runs [task] once [db]'s transaction commits, or at once when [db] is not in one; never after a rollback. */
export function afterCommit(db: Pool | Connection, task: () => void): void {
  const outbox = outboxes.get(db as Connection)
  if (outbox) outbox.tasks.push(task)
  else task()
}

/** withTransaction's side: an outbox for [conn] while its transaction runs. */
export const outbox = {
  open: (conn: Connection) => void outboxes.set(conn, { changes: [], tasks: [] }),
  /** After COMMIT: each change once, to each account once; then the work that waited. */
  send(conn: Connection): void {
    const { changes, tasks } = outboxes.get(conn) ?? { changes: [], tasks: [] }
    outboxes.delete(conn)
    const sent = new Set<string>()
    for (const [to, topic, id] of changes) {
      const key = `${to}|${topic}|${id ?? ''}`
      if (!sent.has(key)) deliver(to, topic, id)
      sent.add(key)
    }
    for (const task of tasks) task()
  },
  /** After ROLLBACK: nothing happened, so nobody is told. */
  drop: (conn: Connection) => void outboxes.delete(conn),
}

/** Ends [userId]'s streams (suspended, deleted), or every stream when the server stops. */
export function closeStreams(userId?: number): void {
  for (const listener of [...listeners]) {
    if (userId === undefined || listener.userId === userId) listener.close()
  }
}
