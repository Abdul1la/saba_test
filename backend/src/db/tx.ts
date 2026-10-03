import { outbox } from '../lib/events.js'
import type { Connection, Pool } from './pool.js'

const ER_LOCK_DEADLOCK = 1213

function isDeadlock(error: unknown): boolean {
  return (error as { errno?: unknown } | null)?.errno === ER_LOCK_DEADLOCK
}

/**
 * Runs [work] in one transaction: commit when it returns, roll back when it
 * throws. A deadlock is retried once from the start, so [work] must be safe to
 * run twice (it is: the first run was rolled back). Anything else is thrown.
 * Live updates published inside it go out only after the commit.
 */
export async function withTransaction<T>(
  pool: Pool,
  work: (connection: Connection) => Promise<T>,
): Promise<T> {
  for (let attempt = 1; ; attempt++) {
    const connection = await pool.getConnection()
    let reusable = true
    try {
      await connection.beginTransaction()
      outbox.open(connection)
      const result = await work(connection)
      await connection.commit()
      outbox.send(connection)
      return result
    } catch (error) {
      outbox.drop(connection)
      try {
        await connection.rollback()
      } catch {
        // A connection that can't roll back can't be trusted with the next caller.
        reusable = false
      }
      if (attempt === 1 && isDeadlock(error)) continue
      throw error
    } finally {
      if (reusable) connection.release()
      else connection.destroy()
    }
  }
}
