import type { Connection, Pool } from '../db/pool.js'
import { rows } from '../db/sql.js'
import type { Lang } from './i18n.js'

// The 19 codes of migrations/0002_governorates.sql (API_CONTRACT.md §1.5), for
// validating input. The table's foreign keys hold them too.
export const GOVERNORATES = [
  'BAGHDAD',
  'BASRA',
  'NINEVEH',
  'ERBIL',
  'SULAYMANIYAH',
  'DUHOK',
  'KIRKUK',
  'NAJAF',
  'KARBALA',
  'BABYLON',
  'ANBAR',
  'DHI_QAR',
  'DIYALA',
  'SALAH_AL_DIN',
  'WASIT',
  'MAYSAN',
  'QADISIYAH',
  'MUTHANNA',
  'HALABJA',
] as const

export type Governorate = (typeof GOVERNORATES)[number]

let names: Map<string, Record<Lang, string>> | undefined

/** Each governorate's name in both languages. Read once: only a migration changes them. */
export async function governorateNames(db: Pool | Connection): Promise<Map<string, Record<Lang, string>>> {
  names ??= new Map(
    (await rows<{ code: string; name_en: string; name_ar: string }>(db, 'SELECT code, name_en, name_ar FROM governorates')).map(
      (row) => [row.code, { en: row.name_en, ar: row.name_ar }],
    ),
  )
  return names
}
