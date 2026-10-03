import type { MessageKey, MessageParams } from '../lib/i18n.js'

// The contract's error codes (API_CONTRACT.md §1.4) and the app's
// (mobile/lib/core/errors/error_mapper.dart). A 429 and a 500 carry none: both
// front-ends fall back to the HTTP status for them.
export type ErrorCode =
  | 'VALIDATION_ERROR'
  | 'AUTHENTICATION_ERROR'
  | 'AUTHORIZATION_ERROR'
  | 'NOT_FOUND_ERROR'
  | 'CONFLICT_ERROR'
  | 'BUSINESS_RULE_ERROR'
  | 'INVENTORY_ERROR'
  | 'EXTERNAL_SERVICE_ERROR'
  // Sign-in of an account never checked, once phone checks are on: ask for a VERIFY_PHONE code.
  | 'PHONE_NOT_VERIFIED'

export interface FieldMessage {
  key: MessageKey
  params?: MessageParams
}

/**
 * An error the client is meant to see. Its words are keys, put in the
 * request's language by the error handler, never text chosen here.
 */
export class AppError extends Error {
  constructor(
    readonly status: number,
    readonly code: ErrorCode | undefined,
    readonly messageKey: MessageKey,
    readonly params?: MessageParams,
    readonly fields?: Readonly<Record<string, FieldMessage>>,
  ) {
    super(messageKey)
  }

  /** Seconds before trying again: sent as Retry-After with a 429. */
  retryAfter?: number
}

/** 429: too many tries. Carries no code: both front-ends go by the status. */
export function tooManyTries(seconds: number, messageKey: MessageKey = 'error.tooManyTries', params?: MessageParams): AppError {
  const error = new AppError(429, undefined, messageKey, params)
  error.retryAfter = seconds
  return error
}
