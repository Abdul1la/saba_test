import { GOVERNORATES } from '@/lib/i18n'
import { http, httpPage, USE_MOCK } from './http'
import { ApiError, countBy, matches, pageOf, reply } from './mock'
import { HISTORY_PEOPLE, NOOR as NOOR_P, SARA as SARA_P, YOUSEF as YOUSEF_P, type Person } from './people'
import { onSale, seedShelf } from './products'
import { deliveryFee, storeFace } from './stores'
import type { AdminOrder, Governorate, ListResult, OrderAddress, OrderItem, OrderStatus, OrderStep, OrderStorePart, PageAsk, Paged } from './types'

// A port of _seedMerchantOrders (mobile/lib/core/mock/mock_api_interceptor.dart):
// eight orders for each of the two demo stores, Nova (m-1) and Atlas (m-2).
// The app builds the same history for any store the first time it is used,
// but every store after Nova reuses Atlas's numbers (SB-200200...), so only
// the two demo stores are mirrored. Read-only: only a store moves an order on.

// The seed writes NEW, which is the same status as PENDING. No PACKED: the
// app dropped it (BUGS.md 34).
const SEED_STATUSES: OrderStatus[] = ['PENDING', 'CONFIRMED', 'PROCESSING', 'SHIPPED', 'DELIVERED']

type Customer = OrderAddress & { phone: string; governorate: Governorate }

/** A shopper as an order's address: the app's order keeps the English. */
const asCustomer = (p: Person): Customer => ({
  fullName: p.fullName,
  phone: p.phone,
  governorate: p.governorate,
  area: p.area,
  street: p.street,
  landmark: p.landmark,
})

const SARA = asCustomer(SARA_P)
const YOUSEF = asCustomer(YOUSEF_P)
// The seed sends Atlas's orders to Yousef in Erbil too, but Atlas does not
// deliver to Erbil, so its shop could never have taken them. Atlas's second
// customer lives in Basra instead (TODO.md).
const NOOR = asCustomer(NOOR_P)

const HOUR = 3_600_000
const iso = (ms: number) => new Date(ms).toISOString()

/** Units, not lines: two of one thing and one of another is 3 items (the app's `Order.itemCount`). */
const units = (items: OrderItem[]) => items.reduce((n, item) => n + item.quantity, 0)

/**
 * web-only demo: the steps up to `status`, one per time given. The app's
 * seed keeps no history on these orders; a live order gets one step each
 * time its store moves it (`_storeMoved`).
 */
const stepsTo = (status: OrderStatus, times: number[]): OrderStep[] =>
  SEED_STATUSES.slice(0, SEED_STATUSES.indexOf(status) + 1).map((s, i) => ({ status: s, occurredAt: iso(times[i]) }))

// web-only demo: each store's own driver, as the store types them when it
// marks an order shipped (courierName, courierPhone). The app's seed gives
// shipped orders a tracking number and no driver (TODO.md).
const DRIVERS: Record<string, [name: string, phone: string]> = {
  'm-1': ['Haider Salim', '+9647705550311'],
  'm-2': ['Mustafa Adnan', '+9647805550322'],
  'm-3': ['Rebwar Sabah', '+9647505550333'],
  'm-4': ['Shivan Ahmed', '+9647505550344'],
  'm-5': ['Hemin Rashid', '+9647505550355'],
  'm-6': ['Karwan Omer', '+9647505550366'],
  'm-7': ['Aram Jalal', '+9647705550377'],
  'm-8': ['Yasser Thamer', '+9647705550388'],
}

/**
 * The order's one store part (every demo order is one store's), as the
 * app's storeParts: what its driver collects, where it has got to, and once
 * it has gone out, who took it.
 */
function partOf(storeId: string, status: OrderStatus, amountDue: number): OrderStorePart[] {
  const out = status === 'SHIPPED' || status === 'DELIVERED'
  const [courierName, courierPhone] = out ? DRIVERS[storeId] : []
  return [{ merchantId: storeId, amountDue, status, courierName, courierPhone }]
}

function seedOrders(storeId: string): AdminOrder[] {
  const shelf = seedShelf(storeId)
  const store = storeFace(storeId)
  const prefix = storeId === 'm-1' ? 'mo' : `${storeId}-mo`
  const firstNumber = storeId === 'm-1' ? 200100 : 200200

  return Array.from({ length: 8 }, (_, index) => {
    const lines = 1 + (index % 3)
    const items: OrderItem[] = Array.from({ length: lines }, (_, line) => {
      const product = shelf[(index + line) % shelf.length]
      const quantity = 1 + (line % 2)
      return {
        id: `${prefix}i-${index}-${line}`,
        productId: product.id,
        productName: product.nameEn,
        productNameAr: product.nameAr,
        imageUrl: product.imageUrl,
        quantity,
        unitPrice: product.price,
        lineTotal: product.price * quantity,
        merchantId: storeId,
        merchantName: store.storeName,
      }
    })
    const subtotal = items.reduce((sum, item) => sum + item.lineTotal, 0)
    const status = SEED_STATUSES[index % SEED_STATUSES.length]
    const customer = index % 2 === 0 ? SARA : storeId === 'm-2' ? NOOR : YOUSEF
    // What the store's own delivery terms charge there, as checkout would.
    // The seed charges a flat 5,000, which Nova's shop never asks.
    const shipping = deliveryFee(storeId, customer.governorate)
    if (shipping === undefined) throw new Error(`${storeId} does not deliver to ${customer.governorate}`)
    // Placed 6 hours apart, as the seed has them; an hour between steps, so delivered 4 hours after.
    const placed = Date.now() - 6 * index * HOUR
    const timeline = stepsTo(status, [0, 1, 2, 3, 4].map((h) => placed + h * HOUR))

    return {
      id: `${prefix}-${index + 1}`,
      orderNumber: `SB-${firstNumber + index}`,
      placedAt: iso(placed),
      deliveredAt: status === 'DELIVERED' ? timeline[4].occurredAt : undefined,
      status,
      // Cash is paid at the door, so paid only once delivered.
      paymentStatus: status === 'DELIVERED' ? 'PAID' : 'PENDING',
      isCashOnDelivery: true,
      paymentMethodLabel: 'Cash on delivery',
      subtotal,
      shipping,
      discount: 0,
      total: subtotal + shipping,
      currencyCode: 'IQD',
      itemCount: units(items),
      customerName: customer.fullName,
      customerPhone: customer.phone,
      shippingAddress: { ...customer },
      storeParts: partOf(storeId, status, subtotal + shipping),
      timeline,
      merchantNames: [store.storeName],
      items,
    }
  })
}

export const CUSTOMER_ADDRESSES: Customer[] = HISTORY_PEOPLE.map(asCustomer)

const HISTORY_STORES = ['m-1', 'm-2', 'm-3', 'm-4', 'm-5', 'm-6', 'm-7', 'm-8']

/**
 * web-only demo: delivered orders from the first of the month three months
 * back until yesterday, for every demo store, so Finance has history. The
 * app's seed has only today's orders (TODO.md). Built by fixed arithmetic,
 * so every reload gives the same history; each goes to a shopper its store
 * delivers to, at that store's fee.
 */
function historyOrders(): AdminOrder[] {
  const now = new Date()
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  const made: Omit<AdminOrder, 'id' | 'orderNumber'>[] = []
  let n = 0
  // Each store's own count of orders, to walk its whole shelf (as the app's _history).
  const sold = HISTORY_STORES.map(() => 0)
  for (let back = 3; back >= 0; back--) {
    HISTORY_STORES.forEach((storeId, s) => {
      const store = storeFace(storeId)
      // Only what was on sale: a product waiting, a draft or one switched off was never bought.
      const shelf = seedShelf(storeId).filter(onSale)
      const reachable = CUSTOMER_ADDRESSES.filter((c) => deliveryFee(storeId, c.governorate) !== undefined)
      for (let k = 0; k < 2 + ((s + back) % 3); k++, n++) {
        const deliveredAt = new Date(now.getFullYear(), now.getMonth() - back, 3 + k * 8 + (s % 4), 11 + (n % 7))
        if (deliveredAt >= today) continue
        const nth = sold[s]++
        const customer = reachable[n % reachable.length]
        const items: OrderItem[] = Array.from({ length: 1 + (n % 2) }, (_, line) => {
          const product = shelf[(nth + line) % shelf.length]
          const quantity = line === 0 ? 1 + (n % 3 === 0 ? 1 : 0) : 1
          return {
            id: `hi-${n}-${line}`,
            productId: product.id,
            productName: product.nameEn,
            productNameAr: product.nameAr,
            imageUrl: product.imageUrl,
            quantity,
            unitPrice: product.price,
            lineTotal: product.price * quantity,
            merchantId: storeId,
            merchantName: store.storeName,
          }
        })
        const subtotal = items.reduce((sum, item) => sum + item.lineTotal, 0)
        const shipping = deliveryFee(storeId, customer.governorate)!
        const delivered = deliveredAt.getTime()
        const placed = delivered - (1 + (n % 3)) * 24 * HOUR
        made.push({
          placedAt: iso(placed),
          deliveredAt: iso(delivered),
          status: 'DELIVERED',
          paymentStatus: 'PAID',
          isCashOnDelivery: true,
          paymentMethodLabel: 'Cash on delivery',
          subtotal,
          shipping,
          discount: 0,
          total: subtotal + shipping,
          currencyCode: 'IQD',
          itemCount: units(items),
          customerName: customer.fullName,
          customerPhone: customer.phone,
          shippingAddress: { ...customer },
          storeParts: partOf(storeId, 'DELIVERED', subtotal + shipping),
          // Confirmed within the hour, prepared that day, out two hours before it arrived.
          timeline: stepsTo('DELIVERED', [placed, placed + HOUR, placed + 3 * HOUR, delivered - 2 * HOUR, delivered]),
          merchantNames: [store.storeName],
          items,
        })
      }
    })
  }
  // Numbered in the order they were placed, below the seed's SB-2001xx.
  return made
    .sort((a, b) => a.placedAt.localeCompare(b.placedAt))
    .map((order, i) => ({ ...order, id: `ho-${i + 1}`, orderNumber: `SB-${190001 + i}` }))
}

type CancelSeed = [storeId: string, customer: number, daysAgo: number, by: 'SHOPPER' | 'STORE', reason: string, note?: string]

// web-only demo: orders cancelled before they went out, by the shopper (the
// app's CancelReason codes) or by the store (its decline codes). Numbered
// apart from the history, whose numbers the app's seed matches.
const CANCELS: CancelSeed[] = [
  ['m-1', 3, 1, 'SHOPPER', 'CHANGED_MIND'],
  ['m-5', 5, 4, 'SHOPPER', 'FOUND_CHEAPER'],
  ['m-2', 2, 9, 'STORE', 'OUT_OF_STOCK'],
  ['m-6', 8, 15, 'SHOPPER', 'DELIVERY_TOO_SLOW'],
  ['m-7', 4, 23, 'STORE', 'ADDRESS_PROBLEM'],
  ['m-8', 6, 38, 'SHOPPER', 'ORDERED_BY_MISTAKE'],
  ['m-3', 7, 52, 'STORE', 'CANNOT_FULFIL'],
  ['m-4', 10, 70, 'SHOPPER', 'OTHER', 'We are moving house next week. I will order again after.'],
]

function cancelledOrders(): AdminOrder[] {
  return CANCELS.map(([storeId, c, days, by, reason, note], i) => {
    const store = storeFace(storeId)
    const shelf = seedShelf(storeId).filter(onSale)
    const customer = CUSTOMER_ADDRESSES[c]
    const shipping = deliveryFee(storeId, customer.governorate)
    if (shipping === undefined) throw new Error(`${storeId} does not deliver to ${customer.governorate}`)
    const items: OrderItem[] = Array.from({ length: 1 + (i % 2) }, (_, line) => {
      const product = shelf[(i * 5 + line) % shelf.length]
      return {
        id: `ci-${i}-${line}`,
        productId: product.id,
        productName: product.nameEn,
        productNameAr: product.nameAr,
        imageUrl: product.imageUrl,
        quantity: 1,
        unitPrice: product.price,
        lineTotal: product.price,
        merchantId: storeId,
        merchantName: store.storeName,
      }
    })
    const subtotal = items.reduce((sum, item) => sum + item.lineTotal, 0)
    const placed = Date.now() - days * 24 * HOUR - 5 * HOUR
    const cancelled = placed + (by === 'STORE' ? 5 : 2) * HOUR
    return {
      id: `co-${i + 1}`,
      orderNumber: `SB-${180001 + i}`,
      placedAt: iso(placed),
      cancelledAt: iso(cancelled),
      cancelledBy: by,
      cancelReason: reason,
      cancelNote: note,
      status: 'CANCELLED',
      paymentStatus: 'CANCELLED',
      isCashOnDelivery: true,
      paymentMethodLabel: 'Cash on delivery',
      subtotal,
      shipping,
      discount: 0,
      total: subtotal + shipping,
      currencyCode: 'IQD',
      itemCount: units(items),
      customerName: customer.fullName,
      customerPhone: customer.phone,
      shippingAddress: { ...customer },
      storeParts: partOf(storeId, 'CANCELLED', subtotal + shipping),
      // Turned down or called off before anyone confirmed it.
      timeline: [
        { status: 'PENDING', occurredAt: iso(placed) },
        { status: 'CANCELLED', occurredAt: iso(cancelled) },
      ],
      merchantNames: [store.storeName],
      items,
    }
  })
}

const ORDERS: AdminOrder[] = [...seedOrders('m-1'), ...seedOrders('m-2'), ...historyOrders(), ...cancelledOrders()].sort((a, b) =>
  b.placedAt.localeCompare(a.placedAt),
)

/**
 * GET /admin/orders?q=&status= — for support: find by number, customer,
 * phone, item or city, the item and city in either language.
 * `status` may name several (the group chips; web-only, TODO.md).
 */
export function listOrders(query: { q?: string; statuses?: OrderStatus[] } & PageAsk): Promise<Paged<ListResult<AdminOrder, OrderStatus>>> {
  if (!USE_MOCK) return httpPage('/admin/orders', { q: query.q, status: query.statuses?.join(',') }, query)
  return reply(() => {
    const found = ORDERS.filter((o) =>
      matches(
        query.q ?? '',
        o.orderNumber,
        o.customerName,
        o.customerPhone,
        ...o.merchantNames,
        ...o.items.flatMap((item) => [item.productName, item.productNameAr]),
        ...(o.shippingAddress.governorate ? GOVERNORATES[o.shippingAddress.governorate] : []),
      ),
    )
    return {
      ...pageOf(
        found.filter((o) => !query.statuses?.length || query.statuses.includes(o.status)),
        query,
      ),
      counts: countBy(found, (o) => [o.status]),
    }
  })
}

/** GET /admin/orders/{id} (web-only route, TODO.md) */
export function getOrder(id: string): Promise<AdminOrder> {
  if (!USE_MOCK) return http('GET', `/admin/orders/${encodeURIComponent(id)}`)
  return reply(() => {
    const order = ORDERS.find((o) => o.id === id)
    if (!order) throw new ApiError('NOT_FOUND')
    return order
  })
}

// Read by the other mock files, never by a screen.
export function allOrders(): AdminOrder[] {
  return ORDERS
}
