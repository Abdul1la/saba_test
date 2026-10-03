import { z } from 'zod'
import { GOVERNORATES } from '../lib/governorates.js'
import { normalizePhone } from '../lib/phone.js'
import { BAGHDAD_OFFSET, PASSWORD } from '../rules.js'

// Input rules shared by several routes. Messages are i18n keys (validate.ts).

/** An Iraqi mobile however it was typed, as E.164. */
export const iraqiPhone = z.string().transform((value, ctx) => {
  const phone = normalizePhone(value)
  if (phone === null) {
    ctx.addIssue({ code: 'custom', message: 'field.phone' })
    return z.NEVER
  }
  return phone
})

/** Trimmed, not blank, at most [max] characters. */
export const requiredText = (max: number) =>
  z.string().trim().min(1, { error: 'field.required' }).max(max)

/** Trimmed; blank or missing is null. */
export const optionalText = (max: number) =>
  z
    .string()
    .trim()
    .max(max)
    .nullish()
    .transform((value) => (value ? value : null))

export const password = z.string().min(PASSWORD.min).max(PASSWORD.max)

/** Optional; blank is none; kept lower-case. */
export const optionalEmail = z
  .string()
  .trim()
  .toLowerCase()
  .max(254)
  .nullish()
  .transform((value, ctx) => {
    if (!value) return null
    if (!z.email().safeParse(value).success) {
      ctx.addIssue({ code: 'custom', message: 'field.email' })
      return z.NEVER
    }
    return value
  })

export const governorate = z.enum(GOVERNORATES, { error: 'field.invalid' })

/**
 * A moment: with its zone ("…Z", "…+03:00"), or without one, as the coupon
 * form sends a picked day ("2026-09-30T23:59:59.000"), read on Iraq's clock.
 */
export const moment = z.string().transform((text, ctx) => {
  const full = /^\d{4}-\d{2}-\d{2}$/.test(text) ? `${text}T00:00:00` : text
  const at = new Date(/(Z|[+-]\d{2}:?\d{2})$/i.test(full) ? full : `${full}${BAGHDAD_OFFSET}`)
  if (!/^\d{4}-\d{2}-\d{2}T/.test(full) || Number.isNaN(at.getTime())) {
    ctx.addIssue({ code: 'custom', message: 'field.invalid' })
    return z.NEVER
  }
  return at
})

/** A path id: digits only. Anything else is simply not found. */
export const IdParams = z.object({ id: z.string() })
