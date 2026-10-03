// npm run migrate: brings the database in DATABASE_URL up to date.
import { ConfigError, loadConfig, loadEnvFile } from '../src/config.js'
import { MigrationError, migrate } from '../src/db/migrations.js'

loadEnvFile()
try {
  const config = loadConfig()
  const ran = await migrate(config.databaseUrl, undefined, config.databaseCa)
  console.log(ran.length === 0 ? 'Nothing to migrate.' : `Ran:\n  ${ran.join('\n  ')}`)
} catch (error) {
  if (error instanceof ConfigError || error instanceof MigrationError) {
    console.error(error.message)
  } else {
    console.error(error)
  }
  process.exitCode = 1
}
