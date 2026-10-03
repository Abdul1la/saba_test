import { once } from 'node:events'
import type { AddressInfo } from 'node:net'
import { Writable } from 'node:stream'
import mysql from 'mysql2/promise'
import { createApp, type AppDeps } from '../src/app.js'
import { loadConfig, loadEnvFile, type Config } from '../src/config.js'
import { migrate } from '../src/db/migrations.js'
import { createLogger } from '../src/http/logging.js'

/** Nothing listens on port 1: a pool pointed here fails at once, like a database that is down. */
export const DEAD_DATABASE_URL = 'mysql://nobody@127.0.0.1:1/none'

export function testConfig(overrides: NodeJS.ProcessEnv = {}): Config {
  return loadConfig({
    NODE_ENV: 'test',
    DATABASE_URL: DEAD_DATABASE_URL,
    LOG_LEVEL: 'info',
    JWT_SECRET: 'test-jwt-secret-at-least-32-characters-long',
    OTP_SECRET: 'test-otp-secret-at-least-32-characters-long',
    ...overrides,
  })
}

/** A logger writing into [lines], so a test can read what was logged. */
export function memoryLogger() {
  const lines: string[] = []
  const stream = new Writable({
    write(chunk, _encoding, done) {
      lines.push(String(chunk))
      done()
    },
  })
  return { logger: createLogger('info', stream), lines }
}

/** The app on a free port. */
export async function startApp(deps: AppDeps) {
  const server = createApp(deps).listen(0, '127.0.0.1')
  await once(server, 'listening')
  const { port } = server.address() as AddressInfo
  return {
    url: `http://127.0.0.1:${port}`,
    close: () => new Promise<void>((resolve) => server.close(() => resolve())),
  }
}

/**
 * The database the tests may empty: DATABASE_URL_TEST from backend/.env. Its
 * name must end in _test, so a slip can never point the tests at real data.
 */
export function testDatabaseUrl(env: NodeJS.ProcessEnv = process.env): string {
  if (env === process.env) loadEnvFile()
  const url = env.DATABASE_URL_TEST
  if (!url) {
    throw new Error(
      'DATABASE_URL_TEST is not set in backend/.env. The database tests need their own database (saba_test).',
    )
  }
  const name = decodeURIComponent(new URL(url).pathname.slice(1))
  if (!name.endsWith('_test')) {
    throw new Error(
      `DATABASE_URL_TEST points at "${name}". Tests empty their database, so its name must end in _test.`,
    )
  }
  return url
}

/** Drops every table in the test database. Only ever called with testDatabaseUrl(). */
export async function emptyDatabase(url: string): Promise<void> {
  const connection = await mysql.createConnection({ uri: url })
  try {
    await connection.query('SET FOREIGN_KEY_CHECKS = 0')
    const [rows] = await connection.query<mysql.RowDataPacket[]>(
      'SELECT TABLE_NAME AS name FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE()',
    )
    for (const { name } of rows) await connection.query(`DROP TABLE \`${String(name)}\``)
  } finally {
    await connection.end()
  }
}

/** An empty test database with every migration run. */
export async function freshDatabase(url: string, dir?: string): Promise<void> {
  await emptyDatabase(url)
  await migrate(url, dir)
}

/** [n] promises that each resolve once all [n] have been reached. */
export function barrier(n: number): () => Promise<void> {
  let arrived = 0
  let release!: () => void
  const all = new Promise<void>((resolve) => (release = resolve))
  return () => {
    arrived += 1
    if (arrived >= n) release()
    return all
  }
}
