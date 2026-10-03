import mysql from 'mysql2/promise'
import type { PoolConnection as CallbackPoolConnection } from 'mysql2'

export type Pool = mysql.Pool
export type Connection = mysql.PoolConnection

/**
 * The application's connection pool.
 *
 * Every connection is set to UTC before its first query, so NOW() and the
 * CURRENT_TIMESTAMP defaults write UTC whatever the server's own zone is
 * (this laptop's is UTC+3). `timezone: 'Z'` alone is not enough: it only tells
 * mysql2 how to turn JS dates into text and back.
 *
 * Multiple statements stay off here; only the migration runner turns them on.
 * With [ca] (a managed database's certificate), it connects with TLS and checks it.
 */
export function createPool(url: string, connectionLimit: number, ca?: string): Pool {
  const pool = mysql.createPool({
    uri: url,
    connectionLimit,
    ...(ca && { ssl: { ca, rejectUnauthorized: true } }),
    timezone: 'Z',
    charset: 'utf8mb4_0900_ai_ci',
    supportBigNumbers: true,
    bigNumberStrings: false,
    decimalNumbers: true,
  })
  // The promise pool hands this event the callback-style connection, whatever
  // its typings say (mysql2/lib/promise/inherit_events.js forwards the raw
  // arguments). So: the callback form. The SET is queued before any query the
  // pool gives this connection out for; if it fails, the connection is dropped
  // rather than used in the wrong time zone.
  pool.on('connection', (connection) => {
    const raw = connection as unknown as CallbackPoolConnection
    raw.query("SET time_zone = '+00:00'", (error) => {
      if (error) raw.destroy()
    })
  })
  return pool
}
