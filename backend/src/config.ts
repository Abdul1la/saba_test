import { existsSync, readFileSync } from 'node:fs'
import { z } from 'zod'
import { OTPIQ_CHANNELS } from './lib/sms.js'

// The only reader of process.env. Everything that differs between this laptop
// and a server is here, checked once at start: a bad value stops the server
// with the variable's name (never its value, which may be a secret).

const bool = z.enum(['true', 'false']).transform((value) => value === 'true')
const mysqlUrl = z.string().regex(/^mysql:\/\/.+/, 'must be a mysql:// address')

const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().min(1).max(65535).default(3000),
  API_PREFIX: z
    .string()
    .regex(/^(\/[a-z0-9-]+)+$/, 'must look like /api/v1')
    .default('/api/v1'),
  DATABASE_URL: mysqlUrl,
  DATABASE_URL_TEST: mysqlUrl.optional(),
  DB_POOL_SIZE: z.coerce.number().int().min(1).max(100).default(10),
  // The managed database's CA certificate (a file): the server and the
  // migrations then connect with TLS and check the certificate. Unset: no TLS
  // (a laptop's MySQL).
  DATABASE_CA_FILE: z
    .string()
    .optional()
    .transform((value) => value || undefined),
  // Signs access tokens and phone proofs; keys the SMS codes' hashes. Changing
  // either signs everyone out or voids the codes in flight.
  JWT_SECRET: z.string().min(32, 'must be at least 32 characters'),
  OTP_SECRET: z.string().min(32, 'must be at least 32 characters'),
  // Empty while developing: any http://localhost port may call (Flutter web
  // picks a new port each run). In production, only the listed origins.
  CORS_ORIGINS: z
    .string()
    .default('')
    .transform((value) =>
      value
        .split(',')
        .map((origin) => origin.trim())
        .filter(Boolean),
    ),
  // Where uploaded photos are kept (a folder), and the address they are loaded
  // from when it isn't this server (a file server or CDN in production).
  MEDIA_DIR: z.string().min(1).default('storage'),
  // disk: the folder above (development only). s3: object storage through its
  // S3 API (DigitalOcean Spaces, decided 2026-09-30), required in production:
  // a server's disk is lost with the server and isn't backed up (the reviewer's
  // item 5). MEDIA_BASE_URL is then the bucket's public (CDN) address.
  MEDIA_STORAGE: z.enum(['disk', 's3']).default('disk'),
  // Empty, as .env.example has them on a laptop: not set.
  S3_ENDPOINT: z
    .string()
    .regex(/^https:\/\/[^\s/]+$/, 'must be an https:// address with no path, like https://fra1.digitaloceanspaces.com')
    .or(z.literal(''))
    .optional()
    .transform((value) => value || undefined),
  S3_REGION: z.string().optional().transform((value) => value || undefined),
  S3_BUCKET: z.string().optional().transform((value) => value || undefined),
  S3_ACCESS_KEY_ID: z.string().optional().transform((value) => value || undefined),
  S3_SECRET_ACCESS_KEY: z.string().optional().transform((value) => value || undefined),
  // true (default): each photo is public in the bucket and loaded from
  // MEDIA_BASE_URL (its CDN). false: the bucket is private (Railway's buckets
  // can't be public), so the API itself serves images/ at /uploads/images,
  // reading them from the bucket; MEDIA_BASE_URL may then be left empty.
  S3_PUBLIC_READ: bool.default(true),
  MEDIA_BASE_URL: z
    .string()
    .regex(/^https?:\/\/[^\s]+[^/]$/, 'must be an http(s) address without a trailing /')
    .or(z.literal(''))
    .optional()
    .transform((value) => value || undefined),
  // SMS codes: "log" writes them to the server's log (development only);
  // "otpiq" sends them through OTPIQ (Q11). A dev key (sk_dev_) delivers only
  // to the test number set in OTPIQ's dashboard.
  SMS_PROVIDER: z.enum(['log', 'otpiq']).default('log'),
  // "off": sign-up needs no SMS code (the user's call, 2026-10-01: no SMS at
  // launch). Password reset keeps its code. "on" again: new sign-ups need the
  // code, and an account never checked is asked for one at its next sign-in.
  PHONE_VERIFICATION: z.enum(['on', 'off']).default('on'),
  OTPIQ_API_KEY: z
    .string()
    .regex(/^sk_(live|dev)_\S+$/, 'must be an OTPIQ key (sk_live_… or sk_dev_…)')
    .or(z.literal(''))
    .optional()
    .transform((value) => value || undefined),
  OTPIQ_CHANNEL: z.enum(OTPIQ_CHANNELS).default('auto'),
  OTPIQ_SENDER_ID: z
    .string()
    .max(11)
    .optional()
    .transform((value) => value || undefined),
  OTPIQ_BASE_URL: z.url().default('https://api.otpiq.com/api'),
  // Push (S10): "log" writes what would be sent to the server's log (development
  // only); "fcm" sends through Firebase with the service-account file Firebase
  // gives (never committed). Missing or unreadable, push is off and the server
  // says so at start: push never stops a launch (the user's call, 2026-09-29).
  PUSH_PROVIDER: z
    .enum(['log', 'fcm'])
    .or(z.literal(''))
    .optional()
    .transform((value) => value || undefined),
  FCM_SERVICE_ACCOUNT_FILE: z
    .string()
    .optional()
    .transform((value) => value || undefined),
  // The same file's contents, for a host with no files of its own (Railway):
  // the JSON itself, or it in base64. Used when FCM_SERVICE_ACCOUNT_FILE is not set.
  FCM_SERVICE_ACCOUNT_JSON: z
    .string()
    .optional()
    .transform((value) => value?.trim() || undefined),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent']).default('info'),
  DOCS_ENABLED: bool.optional(),
  // How many proxies stand in front of the server. Behind a host's HTTPS proxy
  // every request comes from the proxy: unset, one address's SMS and sign-in
  // limits become the whole site's (the reviewer's item 4). 1 behind one proxy
  // (Caddy on the same machine); false when the server faces the internet.
  // "true" trusts any address a client claims: development only.
  TRUST_PROXY: z
    .string()
    .regex(/^(true|false|[1-9])$/, 'must be false, or the number of proxies in front of the server (1-9)')
    .optional(),
})

export interface Config {
  env: 'development' | 'test' | 'production'
  port: number
  apiPrefix: string
  databaseUrl: string
  databaseUrlTest: string | undefined
  dbPoolSize: number
  /** The database's CA certificate (PEM) when it needs TLS. */
  databaseCa: string | undefined
  jwtSecret: string
  otpSecret: string
  mediaDir: string
  mediaBaseUrl: string | undefined
  /** Where uploads are kept: the disk folder above, or an S3 bucket (its keys never logged). */
  media:
    | { storage: 'disk' }
    | { storage: 's3'; endpoint: string; region: string; bucket: string; accessKeyId: string; secretAccessKey: string; publicRead: boolean }
  sms: { provider: 'log' } | { provider: 'otpiq'; apiKey: string; channel: (typeof OTPIQ_CHANNELS)[number]; senderId: string | undefined; baseUrl: string }
  /** Whether sign-up needs an SMS code (PHONE_VERIFICATION). */
  phoneVerification: 'on' | 'off'
  /** Where pushes go; off (with why, naming variables, never values) when Firebase isn't set up. */
  push:
    | { provider: 'off'; why: string }
    | { provider: 'log' }
    | { provider: 'fcm'; projectId: string; clientEmail: string; privateKey: string; tokenUrl: string }
  corsOrigins: string[]
  logLevel: string
  docsEnabled: boolean
  trustProxy: boolean | number
}

export class ConfigError extends Error {}

/** Reads and checks [env]. Throws a ConfigError naming every bad variable. */
export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const parsed = schema.safeParse(env)
  if (!parsed.success) {
    const problems = parsed.error.issues.map(
      (issue) => `${issue.path.join('.')}: ${issue.message}`,
    )
    throw new ConfigError(`Invalid configuration:\n  ${problems.join('\n  ')}`)
  }
  const values = parsed.data
  const production = values.NODE_ENV === 'production'
  if (production && values.CORS_ORIGINS.length === 0) {
    throw new ConfigError(
      'Invalid configuration:\n  CORS_ORIGINS: required in production (a comma-separated list of origins)',
    )
  }
  // One leaked secret must not give away the other.
  if (production && values.JWT_SECRET === values.OTP_SECRET) {
    throw new ConfigError('Invalid configuration:\n  OTP_SECRET: must differ from JWT_SECRET in production')
  }
  // Codes in a log reach no phone, and put every code where a log goes.
  if (production && values.SMS_PROVIDER !== 'otpiq') {
    throw new ConfigError('Invalid configuration:\n  SMS_PROVIDER: must be otpiq in production')
  }
  if (values.SMS_PROVIDER === 'otpiq' && !values.OTPIQ_API_KEY) {
    throw new ConfigError('Invalid configuration:\n  OTPIQ_API_KEY: required when SMS_PROVIDER is otpiq')
  }
  if (production && values.TRUST_PROXY === undefined) {
    throw new ConfigError(
      'Invalid configuration:\n  TRUST_PROXY: required in production: the number of proxies in front of the server (1 behind one HTTPS proxy), or false when it faces the internet itself',
    )
  }
  if (production && values.TRUST_PROXY === 'true') {
    throw new ConfigError(
      'Invalid configuration:\n  TRUST_PROXY: true trusts any address a client claims; in production give the number of proxies in front, like 1',
    )
  }
  if (production && values.MEDIA_STORAGE !== 's3') {
    throw new ConfigError(
      "Invalid configuration:\n  MEDIA_STORAGE: must be s3 in production: photos on the server's disk are lost with the server and aren't backed up",
    )
  }
  if (values.MEDIA_STORAGE === 's3') {
    const needed: ('S3_ENDPOINT' | 'S3_REGION' | 'S3_BUCKET' | 'S3_ACCESS_KEY_ID' | 'S3_SECRET_ACCESS_KEY' | 'MEDIA_BASE_URL')[] = [
      'S3_ENDPOINT',
      'S3_REGION',
      'S3_BUCKET',
      'S3_ACCESS_KEY_ID',
      'S3_SECRET_ACCESS_KEY',
    ]
    // A private bucket's photos are served by this API: their address is its own.
    if (values.S3_PUBLIC_READ) needed.push('MEDIA_BASE_URL')
    const missing = needed.filter((name) => !values[name])
    if (missing.length > 0) {
      throw new ConfigError(`Invalid configuration:\n  ${missing.map((name) => `${name}: required when MEDIA_STORAGE is s3`).join('\n  ')}`)
    }
  }
  let databaseCa: string | undefined
  if (values.DATABASE_CA_FILE) {
    databaseCa = existsSync(values.DATABASE_CA_FILE) ? readFileSync(values.DATABASE_CA_FILE, 'utf8') : ''
    if (!databaseCa.includes('BEGIN CERTIFICATE')) {
      throw new ConfigError('Invalid configuration:\n  DATABASE_CA_FILE: not a readable certificate file (PEM)')
    }
  }
  return {
    env: values.NODE_ENV,
    port: values.PORT,
    apiPrefix: values.API_PREFIX,
    databaseUrl: values.DATABASE_URL,
    databaseUrlTest: values.DATABASE_URL_TEST,
    dbPoolSize: values.DB_POOL_SIZE,
    databaseCa,
    jwtSecret: values.JWT_SECRET,
    otpSecret: values.OTP_SECRET,
    phoneVerification: values.PHONE_VERIFICATION,
    mediaDir: values.MEDIA_DIR,
    mediaBaseUrl: values.MEDIA_BASE_URL,
    media:
      values.MEDIA_STORAGE === 's3'
        ? {
            storage: 's3',
            endpoint: values.S3_ENDPOINT!,
            region: values.S3_REGION!,
            bucket: values.S3_BUCKET!,
            accessKeyId: values.S3_ACCESS_KEY_ID!,
            secretAccessKey: values.S3_SECRET_ACCESS_KEY!,
            publicRead: values.S3_PUBLIC_READ,
          }
        : { storage: 'disk' },
    sms:
      values.SMS_PROVIDER === 'otpiq'
        ? {
            provider: 'otpiq',
            apiKey: values.OTPIQ_API_KEY!,
            channel: values.OTPIQ_CHANNEL,
            senderId: values.OTPIQ_SENDER_ID,
            baseUrl: values.OTPIQ_BASE_URL,
          }
        : { provider: 'log' },
    push: pushOf(values.PUSH_PROVIDER, values.FCM_SERVICE_ACCOUNT_FILE, values.FCM_SERVICE_ACCOUNT_JSON, production),
    corsOrigins: values.CORS_ORIGINS,
    logLevel: values.LOG_LEVEL,
    docsEnabled: values.DOCS_ENABLED ?? !production,
    trustProxy:
      values.TRUST_PROXY === undefined || values.TRUST_PROXY === 'false' ? false : values.TRUST_PROXY === 'true' ? true : Number(values.TRUST_PROXY),
  }
}

/**
 * Where pushes go. Never a reason to refuse to start: a push not sent is not
 * a failure the way a code sent nowhere is. Firebase's service-account file
 * gives the project, the account and its private key; nothing of it is logged.
 */
function pushOf(
  provider: 'log' | 'fcm' | undefined,
  file: string | undefined,
  inline: string | undefined,
  production: boolean,
): Config['push'] {
  if (provider === undefined) {
    return production ? { provider: 'off', why: 'PUSH_PROVIDER is not set' } : { provider: 'log' }
  }
  // What would be sent, in a production log, reaches no phone: off instead.
  if (provider === 'log') return production ? { provider: 'off', why: 'PUSH_PROVIDER=log is for development' } : { provider: 'log' }
  if (!file && !inline) return { provider: 'off', why: 'FCM_SERVICE_ACCOUNT_FILE is not set' }
  try {
    const contents = file
      ? readFileSync(file, 'utf8')
      : inline!.startsWith('{')
        ? inline!
        : Buffer.from(inline!, 'base64').toString('utf8')
    const account = JSON.parse(contents) as Record<string, unknown>
    const text = (key: string) => (typeof account[key] === 'string' && account[key] ? (account[key] as string) : null)
    const projectId = text('project_id')
    const clientEmail = text('client_email')
    const privateKey = text('private_key')
    if (!projectId || !clientEmail || !privateKey?.includes('PRIVATE KEY')) throw new Error('not a service account')
    return { provider: 'fcm', projectId, clientEmail, privateKey, tokenUrl: text('token_uri') ?? 'https://oauth2.googleapis.com/token' }
  } catch {
    return {
      provider: 'off',
      why: file
        ? 'FCM_SERVICE_ACCOUNT_FILE is not a readable Firebase service-account file'
        : 'FCM_SERVICE_ACCOUNT_JSON is not a Firebase service-account file (its JSON, or that in base64)',
    }
  }
}

/** Loads backend/.env into process.env when there is one (npm scripts run from backend/). */
export function loadEnvFile(path = '.env'): void {
  if (existsSync(path)) process.loadEnvFile(path)
}
