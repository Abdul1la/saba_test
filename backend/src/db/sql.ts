import type { ResultSetHeader, RowDataPacket } from 'mysql2/promise'
import type { Connection, Pool } from './pool.js'

// Thin helpers over mysql2: `?` placeholders only, never string-built SQL.

type Runner = Pool | Connection

export async function rows<T>(db: Runner, sql: string, params: unknown[] = []): Promise<T[]> {
  const [result] = await db.query<RowDataPacket[]>(sql, params)
  return result as T[]
}

export async function one<T>(db: Runner, sql: string, params: unknown[] = []): Promise<T | undefined> {
  return (await rows<T>(db, sql, params))[0]
}

export async function exec(db: Runner, sql: string, params: unknown[] = []): Promise<ResultSetHeader> {
  const [result] = await db.query<ResultSetHeader>(sql, params)
  return result
}

/** The unique key a write broke (`uq_users_phone`), or undefined for any other error. */
export function duplicateKey(error: unknown): string | undefined {
  const { errno, sqlMessage } = (error ?? {}) as { errno?: unknown; sqlMessage?: unknown }
  if (errno !== 1062 || typeof sqlMessage !== 'string') return undefined
  return /for key '(?:[^'.]+\.)?([^']+)'/.exec(sqlMessage)?.[1]
}
