import type { Pool } from '../db/pool.js'
import { exec } from '../db/sql.js'
import { HOUSEKEEPING } from '../rules.js'

// The one job on a clock (BACKEND_PLAN.md §5.6): deletes rows nothing reads
// any more. Missing a run breaks nothing; the tables only grow. A timer runs
// it in the server; a host's scheduler can run `npm run housekeeping` instead.

/** Deletes spent request keys, old SMS codes and expired refresh tokens; how many of each went. */
export async function housekeeping(pool: Pool): Promise<{ requestKeys: number; smsCodes: number; refreshTokens: number }> {
  const requestKeys = await exec(pool, 'DELETE FROM idempotency_keys WHERE created_at < NOW(3) - INTERVAL ? HOUR', [HOUSEKEEPING.requestKeyHours])
  const smsCodes = await exec(pool, 'DELETE FROM otp_challenges WHERE created_at < NOW(3) - INTERVAL ? HOUR', [HOUSEKEEPING.smsCodeHours])
  const refreshTokens = await exec(pool, 'DELETE FROM refresh_tokens WHERE expires_at < NOW(3)')
  return { requestKeys: requestKeys.affectedRows, smsCodes: smsCodes.affectedRows, refreshTokens: refreshTokens.affectedRows }
}
