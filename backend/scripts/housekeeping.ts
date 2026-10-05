// npm run housekeeping: one run of the server's hourly clean-up, for a host's
// scheduler (BACKEND_PLAN.md §12). The server runs it by itself too.
import { ConfigError, loadConfig, loadEnvFile } from '../src/config.js'
import { createPool } from '../src/db/pool.js'
import { createLogger } from '../src/http/logging.js'
import { housekeeping } from '../src/lib/housekeeping.js'
import { textSender } from '../src/lib/sms.js'
import { mediaStoreOf } from '../src/lib/storage.js'
import { deleteRemovedChatPhotos } from '../src/modules/account.js'
import { finishStoreDeletions } from '../src/modules/store-deletion.js'
import { autoDeliver } from '../src/modules/store-orders.js'

loadEnvFile()
try {
  const config = loadConfig()
  const pool = createPool(config.databaseUrl, 1, config.databaseCa)
  try {
    const deleted = await housekeeping(pool)
    console.log(`Deleted ${deleted.requestKeys} request keys, ${deleted.smsCodes} SMS codes, ${deleted.refreshTokens} refresh tokens.`)
    // A store whose owner asked, with nothing left to finish. From here the
    // server can't end the owner's open live streams; their reconnect is refused.
    const logger = createLogger(config.logLevel)
    const stores = await finishStoreDeletions({ pool, media: mediaStoreOf(config), sendText: textSender(config.sms, logger), logger })
    console.log(`Deleted ${stores} stores whose owners asked.`)
    const photos = await deleteRemovedChatPhotos(pool, mediaStoreOf(config))
    console.log(`Deleted ${photos} removed chat photos.`)
    const auto = await autoDeliver(pool)
    console.log(`Marked ${auto.delivered} parts delivered that stores left on their way (${auto.failed} failed, tried again next run).`)
  } finally {
    await pool.end()
  }
} catch (error) {
  console.error(error instanceof ConfigError ? error.message : error)
  process.exitCode = 1
}
