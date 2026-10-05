import type { Connection, Pool } from '../db/pool.js'
import { exec, one } from '../db/sql.js'

// Saba's own switches (migration 0013), set from the admin website. A switch
// with no row reads as off: everything works as it did before it existed.

export type SettingName = 'auto_approve_products'

/** Whether switch [name] is on. */
export async function settingOn(db: Pool | Connection, name: SettingName): Promise<boolean> {
  const row = await one<{ value: string }>(db, 'SELECT value FROM app_settings WHERE name = ?', [name])
  return row?.value === 'true'
}

/** Turns switch [name] on or off. */
export async function setSetting(db: Pool | Connection, name: SettingName, on: boolean): Promise<void> {
  await exec(db, 'INSERT INTO app_settings (name, value) VALUES (?, ?) ON DUPLICATE KEY UPDATE value = VALUES(value)', [name, String(on)])
}
