// Business constants, in one place (BACKEND_PLAN.md §2.0 Q3, §4).

export const ACCESS_TOKEN_SECONDS = 15 * 60
/** The app keeps a sign-in 30 days; Saba's staff, on the web, 12 hours (Q3). */
export const REFRESH_TOKEN_SECONDS = { app: 30 * 24 * 60 * 60, admin: 12 * 60 * 60 }
/** How long the proof of an SMS check lasts, between the code and the sign-up form. */
export const VERIFICATION_TOKEN_SECONDS = 15 * 60

export const OTP = {
  validSeconds: 5 * 60,
  resendSeconds: 60,
  /** Wrong tries on one code; the next needs a new code. */
  maxTries: 5,
  perPhonePerHour: 5,
  perIpPerHour: 20,
}

export const SIGN_IN = { tries: 10, windowSeconds: 15 * 60 }

export const PASSWORD = { min: 8, max: 128 }
export const NAME_MAX = { person: 50, store: 40 }

/** A shopper may ask for a return this many days after delivery (BR). */
export const RETURN_WINDOW_DAYS = 7

/** A shopper with no order delivered and paid can order at most this, in IQD (`_overFirstOrderLimit`). */
export const FIRST_ORDER_LIMIT = 1_000_000

/** Saba's one rate, in percent, on every store's delivered sales less its refunds (v1 scope; a changeable rate is Future). */
export const COMMISSION_PERCENT = 8

/** Iraq's clock all year (no summer time): a bill's month and a coupon's day follow it. */
export const BAGHDAD_OFFSET = '+03:00'

/**
 * Housekeeping (BACKEND_PLAN.md §5.6): how often it runs, and how long what it
 * deletes is kept. A request key 24 hours (DATABASE_DESIGN.md §3.5); an SMS
 * code a day, well past its hourly count and the 15-minute proof it backs.
 * Refresh tokens go once expired.
 */
export const HOUSEKEEPING = { everyMinutes: 60, requestKeyHours: 24, smsCodeHours: 24 }

/** A live stream says something at least this often, so a proxy never closes it as idle (§10). */
export const LIVE_PING_SECONDS = 25

/** The rating sheet is put off at most this many times per order (`_ratingAsks`). */
export const RATING_ASKS = 3
