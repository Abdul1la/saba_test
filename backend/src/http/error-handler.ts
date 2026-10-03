import type { ErrorRequestHandler, RequestHandler } from 'express'
import { errorBody } from './envelope.js'
import { AppError } from './errors.js'

/** The one place an error becomes a response. Nothing internal ever leaves. */
export const errorHandler: ErrorRequestHandler = (error, req, res, next) => {
  if (res.headersSent) {
    next(error)
    return
  }
  let known = asAppError(error)
  if (!known) {
    req.log.error({ err: error }, 'unhandled error')
    known = new AppError(500, undefined, 'error.internal')
  }
  if (known.retryAfter) res.setHeader('Retry-After', String(known.retryAfter))
  res.status(known.status).json(errorBody(known, req.lang ?? 'en'))
}

/** Anything no route answered. */
export const notFound: RequestHandler = (req, res) => {
  res.status(404).json(errorBody(new AppError(404, 'NOT_FOUND_ERROR', 'error.notFound'), req.lang))
}

function asAppError(error: unknown): AppError | undefined {
  if (error instanceof AppError) return error
  // Errors from express.json(): a body it couldn't read.
  const { type, status } = (error ?? {}) as { type?: unknown; status?: unknown }
  if (type === 'entity.too.large') return new AppError(413, 'VALIDATION_ERROR', 'error.tooLarge')
  if (typeof type === 'string' && typeof status === 'number' && status >= 400 && status < 500) {
    return new AppError(400, 'VALIDATION_ERROR', 'error.badJson')
  }
  return undefined
}
