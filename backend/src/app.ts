import { fileURLToPath } from 'node:url'
import { OpenAPIRegistry } from '@asteasolutions/zod-to-openapi'
import cors, { type CorsOptions } from 'cors'
import express, { type Express } from 'express'
import helmet from 'helmet'
import type { Logger } from 'pino'
import type { Config } from './config.js'
import type { Pool } from './db/pool.js'
import { serveDocs } from './http/docs.js'
import { errorHandler, notFound } from './http/error-handler.js'
import { language } from './http/language.js'
import { requestLogger } from './http/logging.js'
import { authenticator, identifier } from './http/auth.js'
import type { Api } from './http/route.js'
import { fcmPush, logPush, usePush, type SendPush } from './lib/push.js'
import { RateLimiter } from './lib/rate-limit.js'
import { logSms, otpiqSms, type SendSms } from './lib/sms.js'
import { IMAGE_KEY, imageTypeOf, mediaStoreOf, UPLOADS_PATH, type MediaStore } from './lib/storage.js'
import { createTokens, type Tokens } from './lib/tokens.js'
import { accountRoutes } from './modules/account.js'
import { adminCatalogRoutes } from './modules/admin-catalog.js'
import { adminCustomerRoutes } from './modules/admin-customers.js'
import { adminDashboardRoutes } from './modules/admin-dashboard.js'
import { adminOrderRoutes } from './modules/admin-orders.js'
import { adminProductRoutes } from './modules/admin-products.js'
import { adminReturnRoutes } from './modules/admin-returns.js'
import { adminReviewRoutes } from './modules/admin-reviews.js'
import { adminStoreRoutes } from './modules/admin-stores.js'
import { authRoutes } from './modules/auth.js'
import { billRoutes } from './modules/bills.js'
import { cartRoutes } from './modules/cart.js'
import { catalogRoutes } from './modules/catalog.js'
import { chatRoutes } from './modules/chats.js'
import { checkoutRoutes } from './modules/checkout.js'
import { couponRoutes } from './modules/coupons.js'
import { deviceRoutes } from './modules/devices.js'
import { eventRoutes } from './modules/events.js'
import { healthRoutes } from './modules/health.js'
import { mediaRoutes } from './modules/media.js'
import { merchantProductRoutes } from './modules/merchant-products.js'
import { notificationRoutes } from './modules/notifications.js'
import { orderRoutes } from './modules/orders.js'
import { reportRoutes } from './modules/reports.js'
import { returnRoutes } from './modules/returns.js'
import { storeDashboardRoutes } from './modules/store-dashboard.js'
import { storeDeletionRoutes } from './modules/store-deletion.js'
import { storeOrderRoutes } from './modules/store-orders.js'
import { storeRoutes } from './modules/stores.js'
import { ticketRoutes } from './modules/tickets.js'
import { SIGN_IN } from './rules.js'

export interface AppDeps {
  config: Config
  pool: Pool
  logger: Logger
  /** Where SMS codes go; the log until there is a gateway (Q11). */
  sms?: SendSms
  /** Where pushes go (S10); null for none. Left out: from config.push. */
  push?: SendPush | null
  /** Where uploads are kept. Left out: from config (the disk, or object storage). */
  media?: MediaStore
}

/** What the modules share. */
export interface Context {
  config: Config
  pool: Pool
  tokens: Tokens
  sms: SendSms
  media: MediaStore
  signInLimiter: RateLimiter
}

/** The whole API, without listening, so tests can start it on any port. */
export function createApp({ config, pool, logger, sms, push, media }: AppDeps): Express {
  // Pushes go out after their transaction commits, from anywhere notify() runs (S10).
  usePush(
    push !== undefined
      ? push
      : config.push.provider === 'fcm'
        ? fcmPush(config.push)
        : config.push.provider === 'log'
          ? logPush(logger)
          : null,
    pool,
    logger,
  )
  const app = express()
  app.set('trust proxy', config.trustProxy)

  app.use(requestLogger(logger))
  // Photos will be loaded by the web and Flutter web from other origins, which
  // helmet's default same-origin resource policy would block.
  app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }))
  app.use(cors(corsOptions(config)))
  // Uploaded photos. Their names are random and never reused, so they can be cached for good.
  // On the disk only: object storage serves its own files (MEDIA_BASE_URL).
  // Only images/: a chat's photos (chats/) are private, opened through signed links (chats.ts).
  if (config.media.storage === 'disk') {
    app.use(`${UPLOADS_PATH}/images`, express.static(`${config.mediaDir}/images`, { index: false, dotfiles: 'deny', immutable: true, maxAge: '365d' }))
  }
  // A private bucket (Railway's can't be public): the API reads images/ from it and serves them here.
  const store = media ?? mediaStoreOf(config)
  if (config.media.storage === 's3' && !config.media.publicRead) {
    app.get(`${UPLOADS_PATH}/images/:year/:month/:file`, (req, res, next) => {
      const key = `images/${req.params.year}/${req.params.month}/${req.params.file}`
      if (!IMAGE_KEY.test(key)) return next()
      store.read(key).then(
        (bytes) => {
          if (!bytes) return next()
          res.set({ 'content-type': imageTypeOf(bytes) ?? 'application/octet-stream', 'cache-control': 'public, max-age=31536000, immutable' }).send(bytes)
        },
        next,
      )
    })
  }
  // The pages the app stores link to: public, both languages (BACKEND_PLAN.md §2.0, §12).
  app.get('/delete-account', (_req, res) => res.sendFile(DELETE_ACCOUNT_PAGE))
  app.get('/privacy', (_req, res) => res.sendFile(PRIVACY_PAGE))
  app.use(express.json({ limit: '1mb' }))
  app.use(language)

  const tokens = createTokens(config.jwtSecret)
  const ctx: Context = {
    config,
    pool,
    tokens,
    sms: sms ?? (config.sms.provider === 'otpiq' ? otpiqSms({ ...config.sms, logger }) : logSms(logger)),
    media: store,
    signInLimiter: new RateLimiter(SIGN_IN.tries, SIGN_IN.windowSeconds),
  }
  const api: Api = {
    router: express.Router(),
    registry: new OpenAPIRegistry(),
    checkResponses: config.env !== 'production',
    authenticate: authenticator(pool, tokens),
    identify: identifier(pool, tokens),
  }
  api.registry.registerComponent('securitySchemes', 'bearer', { type: 'http', scheme: 'bearer', bearerFormat: 'JWT' })
  healthRoutes(api, pool)
  authRoutes(api, ctx)
  accountRoutes(api, ctx)
  storeRoutes(api, ctx)
  storeDeletionRoutes(api, ctx)
  notificationRoutes(api, ctx)
  deviceRoutes(api, ctx)
  mediaRoutes(api, ctx)
  // The store's own routes before the public /merchants/:id/… ones, so "me" is never read as an id.
  merchantProductRoutes(api, ctx)
  couponRoutes(api, ctx)
  storeOrderRoutes(api, ctx)
  returnRoutes(api, ctx)
  storeDashboardRoutes(api, ctx)
  chatRoutes(api, ctx)
  reportRoutes(api, ctx)
  ticketRoutes(api, ctx)
  catalogRoutes(api, ctx)
  cartRoutes(api, ctx)
  checkoutRoutes(api, ctx)
  orderRoutes(api, ctx)
  adminStoreRoutes(api, ctx)
  adminProductRoutes(api, ctx)
  adminCatalogRoutes(api, ctx)
  adminOrderRoutes(api, ctx)
  adminReturnRoutes(api, ctx)
  adminReviewRoutes(api, ctx)
  adminCustomerRoutes(api, ctx)
  adminDashboardRoutes(api, ctx)
  billRoutes(api, ctx)
  eventRoutes(api)
  app.use(config.apiPrefix, api.router)
  if (config.docsEnabled) serveDocs(app, api.registry, config.apiPrefix)

  app.use(notFound)
  app.use(errorHandler)
  return app
}

const LOCALHOST = /^http:\/\/(localhost|127\.0\.0\.1)(:\d{1,5})?$/

const DELETE_ACCOUNT_PAGE = fileURLToPath(new URL('../public/delete-account.html', import.meta.url))
const PRIVACY_PAGE = fileURLToPath(new URL('../public/privacy.html', import.meta.url))

/**
 * Listed origins always. Outside production, any http://localhost port too:
 * Flutter web picks a new port every run. Requests with no Origin (the phone
 * app, curl) are not a browser's, so CORS doesn't apply to them.
 */
export function corsOptions(config: Config): CorsOptions {
  return {
    origin(origin, callback) {
      const allowed =
        origin === undefined ||
        config.corsOrigins.includes(origin) ||
        (config.env !== 'production' && LOCALHOST.test(origin))
      callback(null, allowed)
    },
    // Retry-After: how long a 429 waits, for the web to say (W1).
    exposedHeaders: ['X-Request-Id', 'Retry-After'],
    maxAge: 600,
  }
}
