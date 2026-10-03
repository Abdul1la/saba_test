import { decodeJwt } from 'jose'
import { me } from '../http/auth.js'
import type { Api } from '../http/route.js'
import { listen, type Topic } from '../lib/events.js'
import { LIVE_PING_SECONDS } from '../rules.js'

// GET /events (BACKEND_PLAN.md §10): the signed-in account's live stream, as
// Server-Sent Events. One `data:` line per change, `{"topic": "orders", "id":
// "12"}`, and a comment every 25 seconds. It ends when the access token does,
// so a suspended or deleted account hears nothing past its token; the app
// reconnects with a fresh one and announces every topic, catching up.

export function eventRoutes(api: Api): void {
  api.registry.registerPath({
    method: 'get',
    path: '/events',
    tags: ['Live updates'],
    summary: `The account's live stream: one message per change it is about, a comment every ${LIVE_PING_SECONDS} seconds (signed in)`,
    security: [{ bearer: [] }],
    responses: {
      200: {
        description: 'text/event-stream: `data: {"topic":"orders","id":"12"}` per change; ends when the access token does',
        content: { 'text/event-stream': { schema: { type: 'string' } } },
      },
    },
  })

  api.router.get('/events', async (req, res) => {
    await api.authenticate(req, 'signedIn')
    const user = me(req)
    const token = /^Bearer\s+(\S+)$/i.exec(req.headers.authorization ?? '')![1]!
    const endsAt = (decodeJwt(token).exp ?? 0) * 1000

    res.writeHead(200, {
      'Content-Type': 'text/event-stream; charset=utf-8',
      'Cache-Control': 'no-cache, no-transform',
      Connection: 'keep-alive',
      // A proxy in front must pass each message on at once, not buffer them.
      'X-Accel-Buffering': 'no',
    })
    res.write(': open\n\n')

    let open = true
    const end = () => {
      if (!open) return
      open = false
      clearInterval(ping)
      clearTimeout(expiry)
      stop()
      res.end()
    }
    const ping = setInterval(() => res.write(': ping\n\n'), LIVE_PING_SECONDS * 1000)
    const expiry = setTimeout(end, Math.max(0, endsAt - Date.now()))
    const stop = listen({
      userId: user.id,
      role: user.role,
      send: (topic: Topic, id: string | undefined) => void res.write(`data: ${JSON.stringify({ topic, ...(id !== undefined && { id }) })}\n\n`),
      close: end,
    })
    res.on('close', end)
  })
}
