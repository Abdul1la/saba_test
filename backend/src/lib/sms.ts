import type { Logger } from 'pino'
import type { Config } from '../config.js'

// Sending an SMS code. The server makes and checks the codes itself (slice 1's
// rules); the gateway only delivers them. OTPIQ is the gateway (decided
// 2026-09-26, Q11): https://docs.otpiq.com/api-reference/messaging/post.md

/** Sends [code] to [phone] (E.164). Throws SmsError when it could not. */
export type SendSms = (phone: string, code: string) => Promise<void>

/** Sends [text], a notice in Saba's own words, to [phone]. Throws SmsError when it could not. */
export type SendText = (phone: string, text: string) => Promise<void>

export class SmsError extends Error {
  constructor(
    readonly kind: 'rate-limited' | 'failed',
    /** For rate-limited: how long the gateway asks us to wait. */
    readonly waitSeconds = 0,
  ) {
    super(`SMS ${kind}`)
  }
}

/** While developing: the code goes to the server's log, where whoever is testing reads it. */
export function logSms(logger: Logger): SendSms {
  return async (phone, code) => {
    logger.info({ phone }, `SMS code for ${phone}: ${code}`)
  }
}

export function logText(logger: Logger): SendText {
  return async (phone, text) => {
    logger.info({ phone }, `SMS for ${phone}: ${text}`)
  }
}

/** Where notices go: OTPIQ once it is set up, else the log, as the codes do. */
export function textSender(sms: Config['sms'], logger: Logger): SendText {
  return sms.provider === 'otpiq' ? otpiqText({ ...sms, logger }) : logText(logger)
}

export const OTPIQ_CHANNELS = [
  'auto',
  'whatsapp-sms',
  'telegram-sms',
  'whatsapp-telegram-sms',
  'sms',
  'whatsapp',
  'telegram',
] as const

export interface OtpiqOptions {
  apiKey: string
  baseUrl: string
  channel: (typeof OTPIQ_CHANNELS)[number]
  senderId?: string | undefined
  logger: Logger
}

/**
 * OTPIQ's verification message. The API key and the code are never logged;
 * what OTPIQ says when it refuses is, for whoever runs the server (credit
 * running out is theirs to fix, not the shopper's).
 */
export function otpiqSms(options: OtpiqOptions): SendSms {
  return (phone, code) =>
    otpiqSend(options, phone, { smsType: 'verification', verificationCode: code }, 'SMS code sent through OTPIQ')
}

/** OTPIQ's own-words message (smsType "custom", up to 1,000 characters): a notice, never a code. */
export function otpiqText(options: OtpiqOptions): SendText {
  return (phone, text) => otpiqSend(options, phone, { smsType: 'custom', customMessage: text }, 'SMS notice sent through OTPIQ')
}

async function otpiqSend(options: OtpiqOptions, phone: string, message: Record<string, string>, sent: string): Promise<void> {
  let response: Response
  try {
    response = await fetch(`${options.baseUrl}/sms`, {
      method: 'POST',
      headers: { authorization: `Bearer ${options.apiKey}`, 'content-type': 'application/json' },
      body: JSON.stringify({
        // International form without the +: 9647701234567.
        phoneNumber: phone.replace(/^\+/, ''),
        ...message,
        provider: options.channel,
        ...(options.senderId && { senderId: options.senderId }),
      }),
      signal: AbortSignal.timeout(10_000),
    })
  } catch (error) {
    options.logger.error({ err: error, phone }, 'OTPIQ did not answer')
    throw new SmsError('failed')
  }
  const body = (await response.json().catch(() => ({}))) as Record<string, unknown>
  if (response.ok) {
    options.logger.info({ phone, smsId: body.smsId, remainingCredit: body.remainingCredit }, sent)
    return
  }
  if (response.status === 429) {
    const minutes = Number(body.waitMinutes)
    throw new SmsError('rate-limited', Number.isFinite(minutes) && minutes > 0 ? minutes * 60 : 600)
  }
  options.logger.error(
    { phone, status: response.status, error: body.error ?? body.message },
    'OTPIQ refused the SMS',
  )
  throw new SmsError('failed')
}
