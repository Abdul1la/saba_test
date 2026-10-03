// npm run create-admin -- --name "Saba admin" --email admin@saba.app --phone "0770 999 9999"
// The only way a Saba staff account is made: public sign-up makes shoppers and
// store owners only (spec §5). Asks for the password, so it is never in the
// shell's history.
import { createInterface } from 'node:readline/promises'
import { parseArgs } from 'node:util'
import { z } from 'zod'
import { loadConfig, loadEnvFile } from '../src/config.js'
import { createPool } from '../src/db/pool.js'
import { duplicateKey, exec } from '../src/db/sql.js'
import { hashPassword } from '../src/lib/password.js'
import { normalizePhone } from '../src/lib/phone.js'
import { userSearchText } from '../src/modules/users.js'
import { NAME_MAX, PASSWORD } from '../src/rules.js'

/**
 * A line typed without being shown (the final review's item 13): at a terminal nothing
 * is echoed, Backspace works and Ctrl+C stops; piped input is read as it comes.
 */
async function hiddenLine(question: string): Promise<string> {
  const input = process.stdin
  if (!input.isTTY) {
    for await (const line of createInterface({ input })) return line
    return ''
  }
  process.stdout.write(question)
  input.setRawMode(true)
  input.setEncoding('utf8')
  input.resume()
  return new Promise((resolve) => {
    let typed = ''
    const onData = (chunk: string) => {
      for (const char of chunk) {
        if (char === '\u0003') {
          input.setRawMode(false)
          process.stdout.write('\n')
          process.exit(130)
        }
        if (char === '\r' || char === '\n') {
          input.setRawMode(false)
          input.pause()
          input.off('data', onData)
          process.stdout.write('\n')
          return resolve(typed)
        }
        if (char === '\u007f' || char === '\b') typed = typed.slice(0, -1)
        else if (char >= ' ') typed += char
      }
    }
    input.on('data', onData)
  })
}

const { values } = parseArgs({
  options: { name: { type: 'string' }, email: { type: 'string' }, phone: { type: 'string' } },
})
const name = values.name?.trim() ?? ''
const email = values.email?.trim().toLowerCase() ?? ''
const phone = normalizePhone(values.phone ?? '')
const problems = [
  (name.length === 0 || name.length > NAME_MAX.person) && `--name: 1 to ${NAME_MAX.person} characters`,
  !z.email().safeParse(email).success && '--email: an email address (the web signs in with it)',
  !phone && '--phone: an Iraqi mobile number',
].filter(Boolean)
if (problems.length > 0) {
  console.error(`Can't create the admin:\n  ${problems.join('\n  ')}`)
  process.exit(1)
}

const password = await hiddenLine(`Password (at least ${PASSWORD.min} characters): `)
if (password.length < PASSWORD.min || password.length > PASSWORD.max) {
  console.error(`The password must be ${PASSWORD.min} to ${PASSWORD.max} characters.`)
  process.exit(1)
}

loadEnvFile()
const config = loadConfig()
const pool = createPool(config.databaseUrl, 1, config.databaseCa)
try {
  const inserted = await exec(
    pool,
    // Given by whoever runs this on the server: counted as checked.
    `INSERT INTO users (role, full_name, phone, email, password_hash, search_text, phone_verified_at)
     VALUES ('ADMIN', ?, ?, ?, ?, ?, NOW(3))`,
    [name, phone, email, await hashPassword(password), userSearchText(name)],
  )
  console.log(`Admin ${inserted.insertId} created: ${name}, ${email}, ${phone}`)
} catch (error) {
  const key = duplicateKey(error)
  if (!key) throw error
  console.error(key === 'uq_users_email' ? 'That email already has an account.' : 'That number already has an account.')
  process.exitCode = 1
} finally {
  await pool.end()
}
