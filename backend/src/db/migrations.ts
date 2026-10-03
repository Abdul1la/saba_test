import { createHash } from 'node:crypto'
import { readdir, readFile } from 'node:fs/promises'
import path from 'node:path'
import mysql from 'mysql2/promise'

/** backend/migrations; npm scripts and tests run from backend/. */
export const MIGRATIONS_DIR = path.resolve('migrations')

const FILE_NAME = /^\d{4}_[a-z0-9_]+\.sql$/

export class MigrationError extends Error {}

interface Applied {
  version: string
  checksum: Buffer
}

/**
 * Runs every migration in [dir] not yet recorded in schema_migrations, in
 * name order, and returns the ones it ran.
 *
 * Refuses, before running anything, when:
 * - a migration that already ran has been edited (write a new one instead);
 * - a migration that already ran is no longer on disk;
 * - a new migration sorts before one that already ran.
 *
 * Checksums are taken with Windows line endings turned into \n, so a checkout
 * with CRLF doesn't look like an edit.
 *
 * MySQL can't roll back CREATE TABLE, so a migration that fails part-way
 * leaves what it created behind and is not recorded. On a development
 * database: drop it, create it empty, migrate again.
 */
export async function migrate(databaseUrl: string, dir = MIGRATIONS_DIR, ca?: string): Promise<string[]> {
  const connection = await mysql.createConnection({
    uri: databaseUrl,
    ...(ca && { ssl: { ca, rejectUnauthorized: true } }),
    multipleStatements: true,
    charset: 'utf8mb4_0900_ai_ci',
  })
  try {
    await connection.query("SET time_zone = '+00:00'")
    await connection.query(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version     VARCHAR(100) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
        checksum    BINARY(32) NOT NULL,
        applied_at  DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
        PRIMARY KEY (version)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci`)

    const files = (await readdir(dir)).filter((name) => FILE_NAME.test(name)).sort()
    const [rows] = await connection.query<mysql.RowDataPacket[]>(
      'SELECT version, checksum FROM schema_migrations ORDER BY version',
    )
    const applied = rows as unknown as Applied[]

    const sources = new Map<string, { sql: string; checksum: Buffer }>()
    for (const file of files) {
      const sql = (await readFile(path.join(dir, file), 'utf8'))
        .replace(/^﻿/, '')
        .replace(/\r\n/g, '\n')
      sources.set(file, { sql, checksum: createHash('sha256').update(sql).digest() })
    }

    for (const { version, checksum } of applied) {
      const source = sources.get(version)
      if (!source) {
        throw new MigrationError(`Migration ${version} has run, but its file is gone.`)
      }
      if (!source.checksum.equals(checksum)) {
        throw new MigrationError(
          `Migration ${version} was edited after it ran. Put the change in a new migration.`,
        )
      }
    }

    const last = applied.at(-1)?.version
    const pending = files.filter((file) => !applied.some((row) => row.version === file))
    const early = last === undefined ? undefined : pending.find((file) => file < last)
    if (early) {
      throw new MigrationError(
        `Migration ${early} is new but sorts before ${last}, which already ran. Give it a later number.`,
      )
    }

    for (const file of pending) {
      const source = sources.get(file)!
      await connection.query(source.sql)
      await connection.query('INSERT INTO schema_migrations (version, checksum) VALUES (?, ?)', [
        file,
        source.checksum,
      ])
    }
    return pending
  } finally {
    await connection.end()
  }
}
