// Starts the API: reads backend/.env, checks it, listens, and shuts down cleanly.
import { createApp } from './app.js'
import { ConfigError, loadConfig, loadEnvFile, type Config } from './config.js'
import { createPool } from './db/pool.js'
import { createLogger } from './http/logging.js'
import { closeStreams } from './lib/events.js'
import { housekeeping } from './lib/housekeeping.js'
import { textSender } from './lib/sms.js'
import { mediaStoreOf } from './lib/storage.js'
import { deleteRemovedChatPhotos } from './modules/account.js'
import { finishStoreDeletions } from './modules/store-deletion.js'
import { HOUSEKEEPING } from './rules.js'

loadEnvFile()
let config: Config
try {
  config = loadConfig()
} catch (error) {
  console.error(error instanceof ConfigError ? error.message : error)
  process.exit(1)
}

const logger = createLogger(config.logLevel)
const pool = createPool(config.databaseUrl, config.dbPoolSize, config.databaseCa)
const app = createApp({ config, pool, logger })

const server = app.listen(config.port, () => {
  logger.info({ port: config.port, prefix: config.apiPrefix, env: config.env }, 'Saba API listening')
  // Push never stops a start (S10); it says so plainly instead.
  if (config.push.provider === 'off') {
    logger.warn(
      { why: config.push.why },
      'Push notifications are OFF: no phone gets a push. Set PUSH_PROVIDER=fcm and FCM_SERVICE_ACCOUNT_FILE to turn them on.',
    )
  }
  if (config.phoneVerification === 'off') {
    logger.warn('Phone checks at sign-up are OFF: new accounts need no SMS code. Password reset still sends one. PHONE_VERIFICATION=on turns them back on.')
  }
})

// Housekeeping: a minute after start, then every hour. A run that fails is
// logged and simply tried again next time. Store deletions wait for it too.
const sendText = textSender(config.sms, logger)
const tidy = () =>
  housekeeping(pool)
    .then(async (deleted) => ({
      ...deleted,
      stores: await finishStoreDeletions({ pool, media: mediaStoreOf(config), sendText, logger }),
      chatPhotos: await deleteRemovedChatPhotos(pool, mediaStoreOf(config)),
    }))
    .then(
      (deleted) => logger.info(deleted, 'housekeeping'),
      (error: unknown) => logger.warn({ err: error }, 'housekeeping failed; trying again at the next run'),
    )
const firstTidy = setTimeout(tidy, 60_000)
const tidying = setInterval(tidy, HOUSEKEEPING.everyMinutes * 60_000)

let stopping = false
function stop(signal: string): void {
  if (stopping) return
  stopping = true
  logger.info({ signal }, 'stopping: finishing the requests in flight')
  clearTimeout(firstTidy)
  clearInterval(tidying)
  // Stop taking requests, let those in flight finish, then close the pool.
  // Live streams never finish on their own: they are ended, and the apps reconnect.
  server.close(() => {
    pool.end().finally(() => process.exit(0))
  })
  closeStreams()
  setTimeout(() => process.exit(1), 10_000).unref()
}
process.on('SIGTERM', () => stop('SIGTERM'))
process.on('SIGINT', () => stop('SIGINT'))
