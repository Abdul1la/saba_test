import type { NextFunction, Request, Response } from 'express'
import type { Lang } from '../lib/i18n.js'

declare global {
  namespace Express {
    interface Request {
      /** The language the caller asked for (Accept-Language): Arabic or English. */
      lang: Lang
    }
  }
}

/** The first language in [header]: Arabic when it is Arabic, else English. */
export function languageOf(header: string | undefined): Lang {
  const first = header?.split(',')[0]?.trim().toLowerCase() ?? ''
  return first === 'ar' || first.startsWith('ar-') ? 'ar' : 'en'
}

export function language(req: Request, _res: Response, next: NextFunction): void {
  req.lang = languageOf(req.headers['accept-language'])
  next()
}
