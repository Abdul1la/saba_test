import { http, httpPage, USE_MOCK } from './http'
import { ApiError, countBy, pageOf, reply } from './mock'
import type { ListResult, PageAsk, Paged } from './types'

// Support tickets, as the app keeps them (features/support and
// MockApiInterceptor._support): a reference, subject, category and status,
// and a thread of messages marked from the customer or from Saba. In the app
// each account sees only its own; the admin sees everyone's, so each ticket
// here also says who opened it (web-only, TODO.md).

/** `TicketStatus`. */
export type TicketStatus = 'OPEN' | 'IN_PROGRESS' | 'WAITING_FOR_CUSTOMER' | 'RESOLVED' | 'CLOSED'

/** `TicketCategory`. */
export type TicketCategory = 'ORDER' | 'PAYMENT' | 'DELIVERY' | 'RETURN' | 'PRODUCT' | 'ACCOUNT' | 'OTHER'

export type OpenedBy = 'SHOPPER' | 'STORE'

export interface TicketMessage {
  id: string
  body: string
  sentAt: string
  isFromCustomer: boolean
  authorName?: string
}

export interface Ticket {
  id: string
  reference: string
  subject: string
  category: TicketCategory
  status: TicketStatus
  createdAt: string
  updatedAt: string
  lastMessage: string
  /** web-only: who opened it. `storeId` is set for a store's ticket. */
  openedBy: { kind: OpenedBy; name: string; phone: string; storeId?: string }
  messages: TicketMessage[]
}

const hoursAgo = (hours: number) => new Date(Date.now() - hours * 3_600_000).toISOString()

type Seed = [
  reference: number,
  openedBy: Ticket['openedBy'],
  category: TicketCategory,
  status: TicketStatus,
  subject: string,
  thread: [hoursAgo: number, fromCustomer: boolean, body: string][],
]

const SARA = { kind: 'SHOPPER', name: 'Sara Ahmed', phone: '+9647705550142' } as const

// web-only demo: the app's seed has no tickets. Eleven, from shoppers and
// stores, across every status; some already answered.
const SEEDS: Seed[] = [
  [5011, { kind: 'STORE', name: 'Nova Electronics', phone: '+9647711234567', storeId: 'm-1' }, 'ORDER', 'OPEN', 'A customer refused an order at the door', [
    [2, true, 'Order SB-200103 was refused when our driver arrived. The customer said she ordered by mistake. Do we mark it refused, and who pays our driver?'],
  ]],
  [5010, SARA, 'ORDER', 'OPEN', 'My order still says waiting', [
    [3, true, 'I ordered the Nova X5 this morning (SB-200100) and it still says waiting for the store. Is it coming today?'],
  ]],
  [5009, { kind: 'STORE', name: 'Atlas Home', phone: '+9647801234567', storeId: 'm-2' }, 'PAYMENT', 'OPEN', 'How do we pay last month’s bill?', [
    [6, true, 'Our bill for last month is due. Can we pay in two parts, and where do we send the money?'],
  ]],
  [5008, { kind: 'SHOPPER', name: 'Zahraa Ali', phone: '+9647805550237' }, 'DELIVERY', 'IN_PROGRESS', 'الطلب تأخر أكثر من أسبوع', [
    [30, true, 'طلبت مكيفاً قبل أسبوع ولم يصل بعد، والمتجر لا يرد على الهاتف.'],
    [26, false, 'نعتذر عن التأخير. تواصلنا مع المتجر وسنعود إليك اليوم بموعد التوصيل.'],
  ]],
  [5007, { kind: 'STORE', name: 'Mosul Appliances', phone: '+9647705550188', storeId: 'm-8' }, 'PRODUCT', 'IN_PROGRESS', 'When will our air fryer be reviewed?', [
    [52, true, 'We sent the Hadba Air Fryer 6L for review four days ago. Is anything missing?'],
    [49, false, 'Thanks for waiting. It is in the queue now; the photos and Arabic name look complete.'],
  ]],
  [5006, { kind: 'SHOPPER', name: 'Hawre Kamal', phone: '+9647505550224' }, 'RETURN', 'WAITING_FOR_CUSTOMER', 'The store has not picked up my return', [
    [80, true, 'The store approved my return three days ago but nobody came to collect it.'],
    [75, false, 'Sorry about this. Could you send a photo of the item and the box, so we can pass it to the store?'],
  ]],
  [5005, { kind: 'STORE', name: 'Karbala Tech Point', phone: '+9647815550146', storeId: 'm-new-karbalatech' }, 'ACCOUNT', 'WAITING_FOR_CUSTOMER', 'Why was our store rejected?', [
    [200, true, 'We applied and were rejected. What do we need to change?'],
    [196, false, 'The shop address is missing. Add the street and a landmark in your store details, then apply again, and tell us here when you have.'],
  ]],
  [5004, { kind: 'SHOPPER', name: 'Omar Farouk', phone: '+9647705550243' }, 'PAYMENT', 'RESOLVED', 'The driver had no change', [
    [150, true, 'I paid with a 50,000 note for a 35,000 order and the driver had no change. He said the store would send it.'],
    [147, false, 'We have asked the store. They will send the 15,000 with your next order or bring it tomorrow; which do you prefer?'],
    [140, true, 'Tomorrow is fine, thank you.'],
    [120, false, 'The store confirms it was delivered today. We are closing this as resolved.'],
  ]],
  [5003, { kind: 'STORE', name: 'Zakho Mobile', phone: '+9647505550131', storeId: 'm-3' }, 'OTHER', 'RESOLVED', 'Can we add a second phone number?', [
    [220, true, 'Our shop has two lines. Can customers see both?'],
    [215, false, 'Not yet: a store shows one phone number. We have noted the request.'],
  ]],
  [5002, { kind: 'SHOPPER', name: 'Noor Hadi', phone: '+9647805550167' }, 'ACCOUNT', 'CLOSED', 'لا يصلني رمز التحقق', [
    [340, true, 'أحاول تسجيل الدخول ولا تصلني رسالة الرمز.'],
    [336, false, 'جرّب مرة أخرى الآن، كان هناك تأخير في الرسائل صباح اليوم.'],
    [330, true, 'وصل الرمز، شكراً.'],
  ]],
  [5001, { kind: 'SHOPPER', name: 'Lana Aziz', phone: '+9647505550256' }, 'PRODUCT', 'CLOSED', 'Does the Gara air cooler work on 220V?', [
    [480, true, 'Does the Gara Air Cooler 60L work on 220V, and does it need a stabiliser?'],
    [470, false, 'It runs on 220V. The store suggests a stabiliser where the power cuts in and out.'],
  ]],
]

const TICKETS: Ticket[] = SEEDS.map(([reference, openedBy, category, status, subject, thread]) => {
  const messages = thread.map(([hours, isFromCustomer, body], i) => ({
    id: `tm-${reference}-${i + 1}`,
    body,
    sentAt: hoursAgo(hours),
    isFromCustomer,
    // Saba's answers are unsigned: the screen says "Saba support" in its own language.
    authorName: isFromCustomer ? openedBy.name : undefined,
  }))
  const last = messages[messages.length - 1]
  return {
    id: `tk-${reference}`,
    reference: `T-${reference}`,
    subject,
    category,
    status,
    createdAt: messages[0].sentAt,
    updatedAt: last.sentAt,
    lastMessage: last.body,
    openedBy,
    messages,
  }
})

/** The list leaves the thread out, as the app's list does. */
export type TicketRow = Omit<Ticket, 'messages'> & { messageCount: number }
const row = ({ messages, ...ticket }: Ticket): TicketRow => ({ ...ticket, messageCount: messages.length })

/** GET /admin/tickets?status=&openedBy=&page= : one page, newest activity first. */
export function listTickets(
  query: { status?: TicketStatus; openedBy?: OpenedBy } & PageAsk,
): Promise<Paged<ListResult<TicketRow, TicketStatus> & { byOpener: Record<OpenedBy, number> }>> {
  if (!USE_MOCK) return httpPage('/admin/tickets', { status: query.status, openedBy: query.openedBy }, query)
  return reply(() => {
    const found = TICKETS.filter((t) => !query.openedBy || t.openedBy.kind === query.openedBy)
    return {
      ...pageOf(
        found
          .filter((t) => !query.status || t.status === query.status)
          .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt))
          .map(row),
        query,
      ),
      counts: countBy(found, (t) => [t.status]),
      byOpener: {
        SHOPPER: TICKETS.filter((t) => t.openedBy.kind === 'SHOPPER' && (!query.status || t.status === query.status)).length,
        STORE: TICKETS.filter((t) => t.openedBy.kind === 'STORE' && (!query.status || t.status === query.status)).length,
      },
    }
  })
}

/** GET /admin/tickets/{id}, with its thread (web-only route, TODO.md). */
export function getTicket(id: string): Promise<Ticket> {
  if (!USE_MOCK) return http('GET', ticketPath(id))
  return reply(() => find(id))
}

/** POST /admin/tickets/{id}/messages { body } (web-only route): Saba's answer. */
export function replyToTicket(id: string, body: string): Promise<Ticket> {
  if (!USE_MOCK) return http('POST', ticketPath(id, 'messages'), { body })
  return reply(() => {
    const ticket = find(id)
    if (ticket.status === 'CLOSED') throw new ApiError('WRONG_STATE')
    const text = body.trim()
    if (!text) throw new ApiError('MESSAGE_REQUIRED')
    const now = new Date().toISOString()
    // Unsigned, like the seeded answers: every reply reads "Saba support".
    ticket.messages.push({ id: `tm-${ticket.id}-${ticket.messages.length + 1}`, body: text, sentAt: now, isFromCustomer: false })
    Object.assign(ticket, { updatedAt: now, lastMessage: text })
    return ticket
  })
}

/** POST /admin/tickets/{id}/status { status } (web-only route). Closing is the last step, but a closed one can be opened again. */
export function setTicketStatus(id: string, status: TicketStatus): Promise<Ticket> {
  if (!USE_MOCK) return http('POST', ticketPath(id, 'status'), { status })
  return reply(() => {
    const ticket = find(id)
    if (ticket.status === status) throw new ApiError('WRONG_STATE')
    Object.assign(ticket, { status, updatedAt: new Date().toISOString() })
    return ticket
  })
}

const ticketPath = (id: string, action?: string) => `/admin/tickets/${encodeURIComponent(id)}${action ? `/${action}` : ''}`

function find(id: string): Ticket {
  const ticket = TICKETS.find((t) => t.id === id)
  if (!ticket) throw new ApiError('NOT_FOUND')
  return ticket
}
