import { GOVERNORATES } from '@/lib/i18n'
import { http, httpPage, USE_MOCK } from './http'
import { ApiError, countBy, daysAgo, matches, pageOf, reply, requireReason } from './mock'
import { allOrders } from './orders'
import { HISTORY_PEOPLE, SARA, customerIdOf, type Person } from './people'
import { allReturns } from './returns'
import type { AdminOrder, Governorate, ListResult, PageAsk, Paged } from './types'

// Shoppers, as the admin sees them: the app's `User` (name, phone, city,
// `status` ACTIVE or SUSPENDED, `createdAt`) with their `Address`es, and
// their orders found by phone, as an order keeps it.

export type CustomerStatus = 'ACTIVE' | 'SUSPENDED'

export interface CustomerAddress {
  id: string
  label: string
  fullName: string
  phone: string
  governorate: Governorate
  area: string
  areaAr?: string
  street?: string
  streetAr?: string
  landmark: string
  landmarkAr?: string
  isDefault: boolean
}

export interface Customer {
  id: string
  fullName: string
  fullNameAr: string
  phone: string
  governorate: Governorate
  status: CustomerStatus
  /** web-only: why Saba suspended the account. */
  suspensionReason?: string
  joinedAt: string
  orderCount: number
  /** What they paid for delivered orders, less cash handed back on returns. */
  spent: number
  /** false: signed up while SMS codes were off, so the number was never checked (API_CONTRACT.md §3.4, §3.11). */
  phoneVerified?: boolean
}

export interface CustomerDetail extends Customer {
  addresses: CustomerAddress[]
  orders: AdminOrder[]
}

type Account = Omit<Customer, 'orderCount' | 'spent' | 'joinedAt'> & { person: Person; joinedAt?: string; extra?: CustomerAddress[] }

const account = (person: Person, more: Partial<Account> = {}): Account => ({
  id: person.id,
  fullName: person.fullName,
  fullNameAr: person.fullNameAr,
  phone: person.phone,
  governorate: person.governorate,
  status: 'ACTIVE',
  person,
  ...more,
})

// web-only demo: a shopper who signed up but has not ordered yet.
const RANA: Person = {
  id: customerIdOf('+9647805550294'),
  fullName: 'Rana Salman',
  fullNameAr: 'رنا سلمان',
  phone: '+9647805550294',
  governorate: 'KARBALA',
  area: 'Al-Abbasiya',
  areaAr: 'العباسية',
  street: 'Street 5, House 14',
  streetAr: 'شارع 5، دار 14',
  landmark: 'Near the Al-Abbasiya market',
  landmarkAr: 'قرب سوق العباسية',
}

// The app's own demo shopper (MockData.userFor and _demoAddresses), who signs
// in as +964 770 123 4567. Her orders are the ones she places in the app, so
// the seed has none. The app keeps only her English name; the Arabic is the web's.
const AMINA: Person = {
  id: customerIdOf('+9647701234567'),
  fullName: 'Amina Saleh',
  fullNameAr: 'أمينة صالح',
  phone: '+9647701234567',
  governorate: 'BAGHDAD',
  area: 'Al-Mansour',
  areaAr: 'المنصور',
  street: 'Street 14, House 7',
  streetAr: 'شارع 14، دار 7',
  landmark: 'Behind Al-Mansour Mall',
  landmarkAr: 'خلف مول المنصور',
}

const ACCOUNTS: Account[] = [
  account(AMINA),
  ...HISTORY_PEOPLE.map((person) =>
    person === SARA
      ? // web-only demo: a second address, at work.
        account(person, {
          extra: [
            {
              id: `${person.id}-a2`,
              label: 'Work',
              fullName: person.fullName,
              phone: person.phone,
              governorate: 'BAGHDAD',
              area: 'Al-Jadriya',
              areaAr: 'الجادرية',
              street: 'University of Baghdad, College of Science',
              streetAr: 'جامعة بغداد، كلية العلوم',
              landmark: 'Main gate',
              landmarkAr: 'الباب الرئيسي',
              isDefault: false,
            },
          ],
        })
      : person.fullName === 'Hussein Karim'
        ? // web-only demo: one suspended account.
          account(person, { status: 'SUSPENDED', suspensionReason: 'Refused three cash orders at the door in one month.' })
        : account(person),
  ),
  // web-only demo: she signed up while SMS codes were off.
  account(RANA, { joinedAt: daysAgo(3), phoneVerified: false }),
]

const ordersOf = (phone: string) => allOrders().filter((o) => o.customerPhone === phone)

function withTotals(a: Account): Customer {
  const orders = ordersOf(a.phone)
  const ids = new Set(orders.map((o) => o.id))
  const refunded = allReturns()
    .filter((r) => r.status === 'REFUNDED' && ids.has(r.orderId))
    .reduce((sum, r) => sum + r.refundAmount, 0)
  const paid = orders.filter((o) => o.status === 'DELIVERED').reduce((sum, o) => sum + o.total, 0)
  // Joined three weeks before their first order, as a demo would have it.
  const first = orders.reduce((min, o) => (o.placedAt < min ? o.placedAt : min), new Date().toISOString())
  const { person: _person, extra: _extra, joinedAt, ...rest } = a
  return {
    ...rest,
    joinedAt: joinedAt ?? new Date(Date.parse(first) - 21 * 86_400_000).toISOString(),
    orderCount: orders.length,
    spent: paid - refunded,
  }
}

/** Phone digits as typed at home ("0770 555 0142") or in full ("+964 770..."). */
function phoneMatches(query: string, phone: string): boolean {
  const digits = query.replace(/\D/g, '').replace(/^(964|0)/, '')
  return digits.length >= 4 && phone.replace(/\D/g, '').includes(digits)
}

/** GET /admin/customers?q=&status=&page= : name, phone or city, in either language; one page, newest first. */
export function listCustomers(query: { q?: string; status?: CustomerStatus; phoneVerified?: false } & PageAsk): Promise<Paged<ListResult<Customer, CustomerStatus>>> {
  if (!USE_MOCK) return httpPage('/admin/customers', { q: query.q, status: query.status, phoneVerified: query.phoneVerified === false ? 'false' : undefined }, query)
  return reply(() => {
    const q = query.q ?? ''
    // The counts follow the number filter, as they follow the search.
    const found = ACCOUNTS.filter(
      (a) =>
        (query.phoneVerified !== false || a.phoneVerified === false) &&
        (matches(q, a.fullName, a.fullNameAr, a.person.area, a.person.areaAr, ...GOVERNORATES[a.governorate]) || phoneMatches(q, a.phone)),
    )
    return {
      ...pageOf(
        found
          .filter((a) => !query.status || a.status === query.status)
          .map(withTotals)
          .sort((a, b) => b.joinedAt.localeCompare(a.joinedAt)),
        query,
      ),
      counts: countBy(found, (a) => [a.status]),
    }
  })
}

/** GET /admin/customers/{id} (web-only route): details, addresses and orders. */
export function getCustomer(id: string): Promise<CustomerDetail> {
  if (!USE_MOCK) return http('GET', customerPath(id))
  return reply(() => {
    const a = find(id)
    const home: CustomerAddress = {
      id: `${a.id}-a1`,
      label: 'Home',
      fullName: a.fullName,
      phone: a.phone,
      governorate: a.person.governorate,
      area: a.person.area,
      areaAr: a.person.areaAr,
      street: a.person.street,
      streetAr: a.person.streetAr,
      landmark: a.person.landmark,
      landmarkAr: a.person.landmarkAr,
      isDefault: true,
    }
    return {
      ...withTotals(a),
      addresses: [home, ...(a.extra ?? [])],
      orders: ordersOf(a.phone).sort((x, y) => y.placedAt.localeCompare(x.placedAt)),
    }
  })
}

/** POST /admin/customers/{id}/suspend { reason } (web-only route): they can no longer use the app. */
export function suspendCustomer(id: string, reason: string): Promise<Customer> {
  if (!USE_MOCK) return http('POST', customerPath(id, 'suspend'), { reason })
  return change(id, 'ACTIVE', () => ({ status: 'SUSPENDED', suspensionReason: requireReason(reason) }))
}

/** POST /admin/customers/{id}/unsuspend (web-only route) */
export function unsuspendCustomer(id: string): Promise<Customer> {
  if (!USE_MOCK) return http('POST', customerPath(id, 'unsuspend'))
  return change(id, 'SUSPENDED', () => ({ status: 'ACTIVE', suspensionReason: undefined }))
}

const customerPath = (id: string, action?: string) => `/admin/customers/${encodeURIComponent(id)}${action ? `/${action}` : ''}`

function change(id: string, from: CustomerStatus, update: () => Partial<Account>): Promise<Customer> {
  return reply(() => {
    const a = find(id)
    if (a.status !== from) throw new ApiError('WRONG_STATE')
    Object.assign(a, update())
    return withTotals(a)
  })
}

/**
 * DELETE /admin/customers/{id}: the shopper's account goes now, as the app's own
 * delete does; their orders keep their copy. Refused (409) while an order is
 * open: the server names the orders, and those words are shown as they come.
 */
export function deleteCustomer(id: string): Promise<void> {
  if (!USE_MOCK) return http('DELETE', customerPath(id), undefined, { serverWords: true })
  return reply(() => {
    ACCOUNTS.splice(ACCOUNTS.indexOf(find(id)), 1)
  })
}

/**
 * POST /admin/customers/{id}/free-number { reason }: a number never checked,
 * held by the wrong person. The account goes as DELETE does, so the number's
 * owner can sign up with it. 409 while an order is open, or for a checked number.
 */
export function freeCustomerNumber(id: string, reason: string): Promise<unknown> {
  if (!USE_MOCK) return http('POST', `${customerPath(id)}/free-number`, { reason }, { serverWords: true })
  return reply(() => {
    const a = find(id)
    if (a.phoneVerified !== false) throw new ApiError('WRONG_STATE')
    ACCOUNTS.splice(ACCOUNTS.indexOf(a), 1)
    return {}
  })
}

function find(id: string): Account {
  const a = ACCOUNTS.find((x) => x.id === id)
  if (!a) throw new ApiError('NOT_FOUND')
  return a
}
