import { randomUUID } from 'node:crypto'
import type { IncomingMessage, ServerResponse } from 'node:http'
import { pino, type DestinationStream, type Logger } from 'pino'
import { pinoHttp } from 'pino-http'

/**
 * What a log line must never show. Passwords, tokens and SMS codes travel in
 * bodies, which are never logged; these are the headers that carry them.
 */
export const REDACTED = [
  'req.headers.authorization',
  'req.headers.cookie',
  'res.headers["set-cookie"]',
]

/** Structured JSON logs on standard output (or [destination], for tests). */
export function createLogger(level: string, destination?: DestinationStream): Logger {
  const options = { level, redact: { paths: REDACTED, censor: '[Redacted]' } }
  return destination ? pino(options, destination) : pino(options)
}

const REQUEST_ID = /^[A-Za-z0-9-]{8,64}$/

/** One line per request, carrying a request id the client can quote. */
export function requestLogger(logger: Logger) {
  return pinoHttp({
    logger,
    // The app sends X-Request-Id; anything that doesn't look like one is replaced.
    genReqId(req: IncomingMessage, res: ServerResponse) {
      const incoming = req.headers['x-request-id']
      const id = typeof incoming === 'string' && REQUEST_ID.test(incoming) ? incoming : randomUUID()
      res.setHeader('X-Request-Id', id)
      return id
    },
    customLogLevel(_req, res, error) {
      if (error || res.statusCode >= 500) return 'error'
      if (res.statusCode >= 400) return 'warn'
      return 'info'
    },
  })
}
