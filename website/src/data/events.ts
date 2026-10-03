import { refreshAll, refreshTopic } from '@/lib/use-query'
import { openStream } from './http'

// Live updates (BACKEND_PLAN.md §10): GET /events is a text/event-stream of
// `data: {"topic":"orders","id":"12"}` lines, sent after each saved change.
// fetch, not EventSource: EventSource can't send the Authorization header.

/** No bytes for this long (the server pings every 25 s): the connection is dead, open another. */
const SILENT_MS = 60_000
const MAX_WAIT_S = 30

/** Opens the stream and keeps it open until the returned function is called. */
export function startEvents(): () => void {
  const stop = new AbortController()
  void keepOpen(stop.signal)
  return () => stop.abort()
}

async function keepOpen(stop: AbortSignal) {
  let wait = 0
  let opened = false
  while (!stop.aborted) {
    const connection = new AbortController()
    const end = () => connection.abort()
    stop.addEventListener('abort', end)
    try {
      const body = await openStream('/events', AbortSignal.any([stop, connection.signal]))
      // After every reconnect everything loads once: nothing missed in between is lost.
      if (opened) void refreshAll()
      opened = true
      wait = 0
      await read(body, connection)
      // A normal end (its access token ran out): open again at once, with a fresh one.
    } catch {
      if (stop.aborted) return
      wait = Math.min(wait ? wait * 2 : 1, MAX_WAIT_S)
      await pause(wait * 1000, stop)
    } finally {
      stop.removeEventListener('abort', end)
    }
  }
}

/** Reads blocks separated by a blank line; each `data:` line names a topic; `:` lines are pings. */
async function read(body: ReadableStream<Uint8Array>, connection: AbortController) {
  const reader = body.getReader()
  const decoder = new TextDecoder()
  let silent = setTimeout(() => connection.abort(), SILENT_MS)
  let text = ''
  try {
    for (;;) {
      const { value, done } = await reader.read()
      if (done) return
      clearTimeout(silent)
      silent = setTimeout(() => connection.abort(), SILENT_MS)
      text = (text + decoder.decode(value, { stream: true })).replace(/\r\n/g, '\n')
      let end: number
      while ((end = text.indexOf('\n\n')) >= 0) {
        const block = text.slice(0, end)
        text = text.slice(end + 2)
        for (const line of block.split('\n')) {
          if (!line.startsWith('data:')) continue
          try {
            refreshTopic((JSON.parse(line.slice(5)) as { topic: string }).topic)
          } catch {
            // Not a line we know: skip it.
          }
        }
      }
    }
  } finally {
    clearTimeout(silent)
    reader.releaseLock()
  }
}

function pause(ms: number, stop: AbortSignal) {
  return new Promise<void>((done) => {
    const timer = setTimeout(done, ms)
    stop.addEventListener('abort', () => (clearTimeout(timer), done()), { once: true })
  })
}
