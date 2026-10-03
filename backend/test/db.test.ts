import assert from 'node:assert/strict'
import { cp, mkdtemp, readdir, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { after, before, describe, test } from 'node:test'
import mysql from 'mysql2/promise'
import { createPool, type Pool } from '../src/db/pool.js'
import { MIGRATIONS_DIR, MigrationError, migrate } from '../src/db/migrations.js'
import { withTransaction } from '../src/db/tx.js'
import { barrier, freshDatabase, memoryLogger, startApp, testConfig, testDatabaseUrl } from './helpers.js'

const url = testDatabaseUrl()

// Every table in DATABASE_DESIGN.md §2.
const TABLES = [
  'addresses', 'admin_actions', 'bill_payments', 'brands', 'cart_items', 'carts', 'categories',
  'conversations', 'coupons', 'device_tokens', 'featured_stores', 'governorates', 'home_banners', 'idempotency_keys',
  'media_files', 'messages', 'notifications', 'order_events', 'order_items', 'order_store_parts',
  'orders', 'otp_challenges', 'product_images', 'product_skus', 'products', 'refresh_tokens', 'reports',
  'return_items', 'returns', 'review_reports', 'schema_migrations', 'search_terms',
  'stock_movements', 'store_delivery_governorates', 'store_reviews', 'stores', 'support_messages',
  'support_tickets', 'users', 'wishlist_items',
]

async function scalar<T>(sql: string): Promise<T> {
  const connection = await mysql.createConnection({ uri: url })
  try {
    const [rows] = await connection.query<mysql.RowDataPacket[]>(sql)
    return Object.values(rows[0] ?? {})[0] as T
  } finally {
    await connection.end()
  }
}

describe('migrations', () => {
  let scratch: string

  before(async () => {
    scratch = await mkdtemp(path.join(tmpdir(), 'saba-migrations-'))
  })
  after(async () => {
    await rm(scratch, { recursive: true, force: true })
    await freshDatabase(url)
  })

  /** A copy of the real migrations to edit, in its own folder. */
  async function copyOfMigrations(name: string): Promise<string> {
    const dir = path.join(scratch, name)
    await cp(MIGRATIONS_DIR, dir, { recursive: true })
    return dir
  }

  test('a clean database migrates to every table of the design, with its reference data', async () => {
    await freshDatabase(url)
    const connection = await mysql.createConnection({ uri: url })
    try {
      const [tables] = await connection.query<mysql.RowDataPacket[]>(
        'SELECT TABLE_NAME AS name FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() ORDER BY name',
      )
      assert.deepEqual(tables.map((row) => row.name), TABLES)
      const [governorates] = await connection.query<mysql.RowDataPacket[]>(
        'SELECT code FROM governorates ORDER BY sort_order',
      )
      assert.equal(governorates.length, 19)
      assert.equal(governorates[0]?.code, 'BAGHDAD')
      assert.equal(governorates[18]?.code, 'HALABJA')
      const [categories] = await connection.query<mysql.RowDataPacket[]>(
        'SELECT COUNT(*) AS top, (SELECT COUNT(*) FROM categories WHERE parent_id IS NOT NULL) AS sub FROM categories WHERE parent_id IS NULL',
      )
      assert.deepEqual({ ...categories[0] }, { top: 7, sub: 6 })
    } finally {
      await connection.end()
    }
  })

  test('running them again runs nothing', async () => {
    await freshDatabase(url)
    assert.deepEqual(await migrate(url), [])
  })

  test('a migration edited after it ran is refused, and nothing else runs', async () => {
    const dir = await copyOfMigrations('edited')
    await freshDatabase(url, dir)
    const file = path.join(dir, '0003_categories.sql')
    await writeFile(file, (await readFile(file, 'utf8')) + '\n-- a quiet change\n')
    await writeFile(path.join(dir, '9999_after.sql'), 'CREATE TABLE should_not_exist (id INT);')
    await assert.rejects(migrate(url, dir), (error: unknown) => {
      assert.ok(error instanceof MigrationError)
      assert.match(error.message, /0003_categories\.sql was edited after it ran/)
      return true
    })
    assert.equal(await scalar<number>("SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'should_not_exist'"), 0)
  })

  test('Windows line endings are not an edit', async () => {
    const dir = await copyOfMigrations('crlf')
    await freshDatabase(url, dir)
    for (const name of await readdir(dir)) {
      const file = path.join(dir, name)
      await writeFile(file, (await readFile(file, 'utf8')).replace(/\r?\n/g, '\r\n'))
    }
    assert.deepEqual(await migrate(url, dir), [])
  })

  test('a migration that ran but whose file is gone is refused', async () => {
    const dir = await copyOfMigrations('gone')
    await freshDatabase(url, dir)
    await rm(path.join(dir, '0003_categories.sql'))
    await assert.rejects(migrate(url, dir), /0003_categories\.sql has run, but its file is gone/)
  })

  test('a new migration numbered before one that ran is refused', async () => {
    const dir = await copyOfMigrations('early')
    await freshDatabase(url, dir)
    await writeFile(path.join(dir, '0002_sneaked_in.sql'), 'CREATE TABLE should_not_exist (id INT);')
    await assert.rejects(migrate(url, dir), /0002_sneaked_in\.sql is new but sorts before \d{4}_\w+\.sql, which already ran/)
  })
})

describe('the pool and transactions', () => {
  let pool: Pool

  before(async () => {
    await freshDatabase(url)
    pool = createPool(url, 4)
  })
  after(async () => {
    await pool.end()
  })

  test('every pooled connection works in UTC, whatever the server\'s own zone (this laptop is UTC+3)', async () => {
    for (let i = 0; i < 3; i++) {
      const connection = await pool.getConnection()
      try {
        const [rows] = await connection.query<mysql.RowDataPacket[]>(
          'SELECT @@session.time_zone AS zone, NOW(3) AS now',
        )
        assert.equal(rows[0]?.zone, '+00:00')
        const drift = Math.abs((rows[0]?.now as Date).getTime() - Date.now())
        assert.ok(drift < 60_000, `NOW() is ${Math.round(drift / 60_000)} minutes off UTC`)
      } finally {
        connection.release()
      }
    }
  })

  test('a transaction keeps what its work wrote', async () => {
    await withTransaction(pool, (connection) =>
      connection.query("INSERT INTO brands (name) VALUES ('tx-kept')"),
    )
    assert.equal(await scalar<number>("SELECT COUNT(*) FROM brands WHERE name = 'tx-kept'"), 1)
  })

  test('a transaction whose work throws keeps nothing, and the error comes back', async () => {
    await assert.rejects(
      withTransaction(pool, async (connection) => {
        await connection.query("INSERT INTO brands (name) VALUES ('tx-dropped')")
        throw new Error('the work failed')
      }),
      /the work failed/,
    )
    assert.equal(await scalar<number>("SELECT COUNT(*) FROM brands WHERE name = 'tx-dropped'"), 0)
  })

  test('a deadlock is retried once, so both transactions finish', async () => {
    // Two transactions take the same two rows in opposite orders: MySQL kills
    // one of them with a deadlock. The retry must run it again, after the other.
    const bothHoldOne = barrier(2)
    let runs = 0
    const lockBoth = (first: string, second: string) =>
      withTransaction(pool, async (connection) => {
        runs += 1
        await connection.query('UPDATE governorates SET name_en = name_en WHERE code = ?', [first])
        await bothHoldOne()
        await connection.query('UPDATE governorates SET name_en = name_en WHERE code = ?', [second])
      })
    await Promise.all([lockBoth('BAGHDAD', 'BASRA'), lockBoth('BASRA', 'BAGHDAD')])
    assert.equal(runs, 3, 'one of the two ran twice')
  })
})

describe('health, with the database up', () => {
  const pool = createPool(url, 2)
  let app: Awaited<ReturnType<typeof startApp>>

  before(async () => {
    await freshDatabase(url)
    app = await startApp({ config: testConfig(), pool, logger: memoryLogger().logger })
  })
  after(async () => {
    await app.close()
    await pool.end()
  })

  test('says ok in the envelope', async () => {
    const response = await fetch(`${app.url}/api/v1/health`)
    assert.equal(response.status, 200)
    assert.deepEqual(await response.json(), {
      success: true,
      message: '',
      data: { status: 'ok' },
      meta: {},
    })
  })
})
