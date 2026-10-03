import { z } from 'zod'
import type { Pool } from '../db/pool.js'
import { AppError } from '../http/errors.js'
import { route, type Api } from '../http/route.js'

/** GET /health: the API is up and its database answers. For the host's checks. */
export function healthRoutes(api: Api, pool: Pool): void {
  route(api, {
    method: 'get',
    path: '/health',
    tag: 'System',
    summary: 'The API is up and its database answers',
    who: 'public',
    response: z.object({ status: z.literal('ok') }),
    async handle({ req }) {
      try {
        await pool.query('SELECT 1')
      } catch (error) {
        req.log.warn({ err: error }, 'health check: the database did not answer')
        throw new AppError(503, 'EXTERNAL_SERVICE_ERROR', 'error.unavailable')
      }
      return { status: 'ok' as const }
    },
  })
}
