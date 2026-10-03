import { z } from 'zod'
import { t, type Lang } from '../lib/i18n.js'
import type { AppError } from './errors.js'

// The one response shape (API_CONTRACT.md §1.2, the app's §54 envelope).

export function ok<T>(data: T, meta: Record<string, unknown> = {}) {
  return { success: true as const, message: '', data, meta }
}

export function envelopeOf<S extends z.ZodType>(data: S) {
  return z.object({
    success: z.literal(true),
    message: z.string(),
    data,
    meta: z.record(z.string(), z.unknown()),
  })
}

export const ErrorBody = z
  .object({
    success: z.literal(false),
    code: z.string().optional(),
    message: z.string(),
    errors: z.record(z.string(), z.string()).optional(),
  })
  .meta({ id: 'Error' })

/** [error] in the contract's error shape, its words in [lang]. */
export function errorBody(error: AppError, lang: Lang): z.infer<typeof ErrorBody> {
  return {
    success: false,
    ...(error.code && { code: error.code }),
    message: t(lang, error.messageKey, error.params),
    ...(error.fields && {
      errors: Object.fromEntries(
        Object.entries(error.fields).map(([field, { key, params }]) => [field, t(lang, key, params)]),
      ),
    }),
  }
}
