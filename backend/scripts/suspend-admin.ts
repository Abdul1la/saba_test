// npm run suspend-admin -- --email name@example.com --reason "Left Saba"
// npm run suspend-admin -- --email name@example.com --restore
// A staff account's way out (the final review's item 6): suspended, it is refused
// at sign-in and at its next request, and every sign-in it holds is ended, so it
// can't come back even when restored. --restore lets it sign in again.
import { parseArgs } from 'node:util'
import { loadConfig, loadEnvFile } from '../src/config.js'
import { createPool } from '../src/db/pool.js'
import { exec, one } from '../src/db/sql.js'
import { withTransaction } from '../src/db/tx.js'
import { normalizePhone } from '../src/lib/phone.js'

const { values } = parseArgs({
  options: { email: { type: 'string' }, phone: { type: 'string' }, reason: { type: 'string' }, restore: { type: 'boolean' } },
})
const email = values.email?.trim().toLowerCase() || null
const phone = values.phone ? normalizePhone(values.phone) : null
const reason = values.reason?.trim() ?? ''
const problems = [
  !email && !phone && '--email or --phone: the admin to suspend or restore',
  !values.restore && (reason.length === 0 || reason.length > 500) && '--reason: why, 1 to 500 characters (or --restore)',
].filter(Boolean)
if (problems.length > 0) {
  console.error(`Nothing changed:\n  ${problems.join('\n  ')}`)
  process.exit(1)
}

loadEnvFile()
const config = loadConfig()
const pool = createPool(config.databaseUrl, 1, config.databaseCa)
try {
  const said = await withTransaction(pool, async (conn) => {
    const admin = await one<{ id: number; full_name: string }>(
      conn,
      `SELECT id, full_name FROM users WHERE role = 'ADMIN' AND ${email ? 'email' : 'phone'} = ? FOR UPDATE`,
      [email ?? phone],
    )
    if (!admin) return null
    if (values.restore) {
      await exec(conn, "UPDATE users SET status = 'ACTIVE', suspension_reason = NULL WHERE id = ?", [admin.id])
      return `Admin ${admin.id} (${admin.full_name}) can sign in again.`
    }
    await exec(conn, "UPDATE users SET status = 'SUSPENDED', suspension_reason = ? WHERE id = ?", [reason, admin.id])
    const ended = await exec(conn, 'UPDATE refresh_tokens SET revoked_at = NOW(3) WHERE user_id = ? AND revoked_at IS NULL', [admin.id])
    return `Admin ${admin.id} (${admin.full_name}) is suspended; ${ended.affectedRows} sign-in(s) ended.`
  })
  if (said === null) {
    console.error('No admin has that email or number. Nothing changed.')
    process.exitCode = 1
  } else {
    console.log(said)
  }
} finally {
  await pool.end()
}
