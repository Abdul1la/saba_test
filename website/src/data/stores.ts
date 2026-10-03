import { GOVERNORATES } from '@/lib/i18n'
import { http, httpPage, USE_MOCK } from './http'
import { ApiError, countBy, daysAgo, matches, pageOf, reply, requireReason } from './mock'
import { countProductsOf } from './products'
import type { AdminStore, Governorate, ListResult, PageAsk, Paged, StoreStatus } from './types'

type StoreRecord = Omit<AdminStore, 'productCount'>

const logo = (name: string) => `/demo/stores/${name}-logo.jpg`
const banner = (name: string) => `/demo/stores/${name}-banner.jpg`

// The eight stores are MockData.merchants, word for word. The mobile seed
// keeps no owner for m-3..m-8 and no application date, so those fields are
// web-only demo values; m-1 and m-2's owners are the app's two demo merchants
// (Omar and Layla). Nova's and Atlas's delivery is the app's own, which it
// keeps in MockApiInterceptor._deliveryOf rather than on the store record.
const STORES: StoreRecord[] = [
  {
    id: 'm-1',
    storeName: 'Nova Electronics',
    status: 'APPROVED',
    fullName: 'Omar Al-Sayed',
    phone: '+9647711234567',
    email: 'merchant@saba.app',
    businessAddress: 'Al-Mansour, Street 14',
    description: 'Authorised reseller for phones, laptops and audio.',
    country: 'Iraq',
    governorate: 'BAGHDAD',
    logoUrl: logo('nova'),
    bannerUrl: banner('nova'),
    rating: 4.6,
    reviewCount: 318,
    // Nova, in Baghdad, sends everywhere.
    delivery: {
      governorates: Object.keys(GOVERNORATES) as Governorate[],
      feeInside: 3000,
      timeInside: '1_2_DAYS',
      feeOutside: 6000,
      timeOutside: '3_5_DAYS',
    },
    submittedAt: daysAgo(120), // web-only demo
    answeredAt: daysAgo(119), // web-only demo
  },
  {
    id: 'm-2',
    storeName: 'Atlas Home',
    status: 'APPROVED',
    fullName: 'Layla Kareem',
    phone: '+9647801234567',
    email: 'merchant2@saba.app',
    businessAddress: 'Corniche Street, Al-Ashar',
    description: 'Home appliances and kitchen essentials.',
    country: 'Iraq',
    governorate: 'BASRA',
    logoUrl: logo('atlas'),
    bannerUrl: banner('atlas'),
    rating: 4.3,
    reviewCount: 142,
    // Atlas, in Basra, sends around the south and to Baghdad.
    delivery: {
      governorates: ['BASRA', 'MAYSAN', 'DHI_QAR', 'MUTHANNA', 'BAGHDAD'],
      feeInside: 2000,
      timeInside: 'SAME_DAY',
      feeOutside: 5000,
      timeOutside: '2_3_DAYS',
    },
    submittedAt: daysAgo(112), // web-only demo
    answeredAt: daysAgo(111), // web-only demo
  },
  {
    id: 'm-3',
    storeName: 'Zakho Mobile',
    status: 'APPROVED',
    fullName: 'Rebwar Salih', // web-only demo
    phone: '+9647505550131', // web-only demo
    businessAddress: 'Kawa Street, Duhok',
    description: 'Phones and accessories, delivered across Duhok the same day.',
    country: 'Iraq',
    governorate: 'DUHOK',
    logoUrl: logo('store-3'),
    bannerUrl: banner('store-3'),
    rating: 4.5,
    reviewCount: 96,
    delivery: {
      governorates: ['DUHOK', 'ERBIL', 'NINEVEH'],
      feeInside: 3000,
      timeInside: 'SAME_DAY',
      feeOutside: 5000,
      timeOutside: '1_2_DAYS',
    },
    submittedAt: daysAgo(64), // web-only demo
    answeredAt: daysAgo(63), // web-only demo
  },
  {
    id: 'm-4',
    storeName: 'Duhok Home Center',
    status: 'APPROVED',
    fullName: 'Shirin Ahmed', // web-only demo
    phone: '+9647505550144', // web-only demo
    businessAddress: 'Nohadra Street, Duhok',
    description: 'Coolers, fans and kitchen appliances for every home.',
    country: 'Iraq',
    governorate: 'DUHOK',
    logoUrl: logo('store-4'),
    bannerUrl: banner('store-4'),
    rating: 4.2,
    reviewCount: 57,
    delivery: {
      governorates: ['DUHOK', 'ERBIL', 'SULAYMANIYAH'],
      feeInside: 4000,
      timeInside: '1_2_DAYS',
      feeOutside: 7000,
      timeOutside: '2_3_DAYS',
    },
    submittedAt: daysAgo(58), // web-only demo
    answeredAt: daysAgo(57), // web-only demo
  },
  {
    id: 'm-5',
    storeName: 'Citadel Electronics',
    status: 'APPROVED',
    fullName: 'Karwan Aziz', // web-only demo
    phone: '+9647505550157', // web-only demo
    businessAddress: '100 Meter Road, Erbil',
    description: 'Laptops and computer accessories, sent anywhere in Iraq.',
    country: 'Iraq',
    governorate: 'ERBIL',
    logoUrl: logo('store-5'),
    bannerUrl: banner('store-5'),
    rating: 4.7,
    reviewCount: 211,
    delivery: {
      governorates: [
        'BAGHDAD', 'BASRA', 'NINEVEH', 'ERBIL', 'SULAYMANIYAH', 'DUHOK', 'KIRKUK',
        'NAJAF', 'KARBALA', 'BABYLON', 'ANBAR', 'DHI_QAR', 'DIYALA', 'SALAH_AL_DIN',
        'WASIT', 'MAYSAN', 'QADISIYAH', 'MUTHANNA', 'HALABJA',
      ],
      feeInside: 3000,
      timeInside: 'SAME_DAY',
      feeOutside: 6000,
      timeOutside: '2_3_DAYS',
    },
    submittedAt: daysAgo(51), // web-only demo
    answeredAt: daysAgo(50), // web-only demo
  },
  {
    id: 'm-6',
    storeName: 'Erbil Cool Air',
    status: 'APPROVED',
    fullName: 'Dilan Hussein', // web-only demo
    phone: '+9647505550162', // web-only demo
    businessAddress: 'Iskan, Erbil',
    description: 'Air conditioners and fans, installed in Erbil.',
    country: 'Iraq',
    governorate: 'ERBIL',
    logoUrl: logo('store-6'),
    bannerUrl: banner('store-6'),
    rating: 4.4,
    reviewCount: 88,
    delivery: {
      governorates: ['ERBIL', 'DUHOK', 'SULAYMANIYAH', 'KIRKUK'],
      feeInside: 5000,
      timeInside: '1_2_DAYS',
      feeOutside: 8000,
      timeOutside: '2_3_DAYS',
    },
    submittedAt: daysAgo(44), // web-only demo
    answeredAt: daysAgo(44), // web-only demo
  },
  {
    id: 'm-7',
    storeName: 'Slemani Gadgets',
    status: 'APPROVED',
    fullName: 'Aram Othman', // web-only demo
    phone: '+9647705550175', // web-only demo
    businessAddress: 'Salim Street, Sulaymaniyah',
    description: 'Phones, tablets and gadgets.',
    country: 'Iraq',
    governorate: 'SULAYMANIYAH',
    logoUrl: logo('store-7'),
    bannerUrl: banner('store-7'),
    rating: 4.6,
    reviewCount: 134,
    delivery: {
      governorates: ['SULAYMANIYAH', 'HALABJA', 'ERBIL', 'KIRKUK'],
      feeInside: 3000,
      timeInside: 'SAME_DAY',
      feeOutside: 6000,
      timeOutside: '1_2_DAYS',
    },
    submittedAt: daysAgo(37), // web-only demo
    answeredAt: daysAgo(36), // web-only demo
  },
  {
    id: 'm-8',
    storeName: 'Mosul Appliances',
    status: 'APPROVED',
    fullName: 'Yasir Younis', // web-only demo
    phone: '+9647705550188', // web-only demo
    phoneVerified: false, // web-only demo: he signed up while SMS codes were off
    businessAddress: 'Al-Faisaliya, Mosul',
    description: 'Washing machines, fridges and cookers.',
    country: 'Iraq',
    governorate: 'NINEVEH',
    logoUrl: logo('store-8'),
    bannerUrl: banner('store-8'),
    rating: 4.3,
    reviewCount: 75,
    delivery: {
      governorates: ['NINEVEH', 'DUHOK', 'ERBIL', 'KIRKUK', 'BAGHDAD'],
      feeInside: 4000,
      timeInside: '1_2_DAYS',
      feeOutside: 7000,
      timeOutside: '3_5_DAYS',
    },
    submittedAt: daysAgo(30), // web-only demo
    answeredAt: daysAgo(29), // web-only demo
  },

  // web-only demo: stores that signed up and wait for an answer, so the
  // queue and the status filters have something in them. Ids follow the
  // app's "m-new-..." pattern for a store opened in the app.
  {
    id: 'm-new-babylonphone', // web-only demo
    storeName: 'Babylon Phone House',
    status: 'PENDING',
    fullName: 'Ali Hassan',
    phone: '+9647805550121',
    businessAddress: 'Al-Iskan, Hillah',
    description: 'Phones, chargers and cases, with repairs in the shop.',
    country: 'Iraq',
    governorate: 'BABYLON',
    reviewCount: 0,
    submittedAt: daysAgo(3, 5),
  },
  {
    id: 'm-new-kufahome', // web-only demo
    storeName: 'Kufa Home Store',
    status: 'PENDING',
    fullName: 'Zainab Kadhim',
    phone: '+9647705550139',
    businessAddress: 'Al-Rasool Street, Najaf',
    description: 'Fans, coolers and small kitchen appliances.',
    country: 'Iraq',
    governorate: 'NAJAF',
    reviewCount: 0,
    submittedAt: daysAgo(0, 18),
  },
  {
    id: 'm-new-karbalatech', // web-only demo
    storeName: 'Karbala Tech Point',
    status: 'REJECTED',
    fullName: 'Mustafa Jabbar',
    phone: '+9647815550146',
    description: 'Laptops and printers.',
    country: 'Iraq',
    governorate: 'KARBALA',
    reviewCount: 0,
    submittedAt: daysAgo(9),
    answeredAt: daysAgo(8),
    rejectionReason: 'The shop address is missing. Add the street and a landmark, then apply again.',
  },
]

const isWaiting = (status: StoreStatus) => status === 'PENDING'

const withCount = (store: StoreRecord): AdminStore => ({ ...store, productCount: countProductsOf(store.id) })

/** GET /admin/stores?status=&q=&page= : one page, newest first. */
export function listStores(query: { q?: string; status?: StoreStatus; phoneVerified?: false } & PageAsk): Promise<Paged<ListResult<AdminStore, StoreStatus>>> {
  if (!USE_MOCK) return httpPage('/admin/stores', { q: query.q, status: query.status, phoneVerified: query.phoneVerified === false ? 'false' : undefined }, query)
  return reply(() => {
    // The counts follow the number filter, as they follow the search.
    const found = STORES.filter(
      (s) =>
        (query.phoneVerified !== false || s.phoneVerified === false) &&
        // The city in both languages: the list shows it in the admin's.
        matches(query.q ?? '', s.storeName, s.fullName, s.phone, s.email, s.businessAddress, ...GOVERNORATES[s.governorate]),
    )
    const items = found
      .filter((s) => !query.status || s.status === query.status)
      .sort((a, b) => b.submittedAt.localeCompare(a.submittedAt))
      .map(withCount)
    return { ...pageOf(items, query), counts: countBy(found, (s) => [s.status]) }
  })
}

/** GET /admin/stores/{id} (web-only route, TODO.md) */
export function getStore(id: string): Promise<AdminStore> {
  if (!USE_MOCK) return http('GET', storePath(id))
  return reply(() => withCount(find(id)))
}

/** POST /admin/stores/{id}/approve */
export function approveStore(id: string): Promise<AdminStore> {
  if (!USE_MOCK) return http('POST', storePath(id, 'approve'))
  return change(id, isWaiting, () => ({ status: 'APPROVED', answeredAt: now() }))
}

/** POST /admin/stores/{id}/reject { reason } */
export function rejectStore(id: string, reason: string): Promise<AdminStore> {
  if (!USE_MOCK) return http('POST', storePath(id, 'reject'), { reason })
  return change(id, isWaiting, () => ({
    status: 'REJECTED',
    rejectionReason: requireReason(reason),
    answeredAt: now(),
  }))
}

/** POST /admin/stores/{id}/suspend { reason } — its products leave the shop. */
export function suspendStore(id: string, reason: string): Promise<AdminStore> {
  if (!USE_MOCK) return http('POST', storePath(id, 'suspend'), { reason })
  return change(id, (s) => s === 'APPROVED', () => ({
    status: 'SUSPENDED',
    suspensionReason: requireReason(reason),
  }))
}

/** POST /admin/stores/{id}/unsuspend (web-only route, TODO.md) */
export function unsuspendStore(id: string): Promise<AdminStore> {
  if (!USE_MOCK) return http('POST', storePath(id, 'unsuspend'))
  return change(id, (s) => s === 'SUSPENDED', () => ({ status: 'APPROVED', suspensionReason: undefined }))
}

/**
 * POST /admin/stores/{id}/deletion: what the owner's own button starts. The
 * store closes now and is deleted once its orders, returns and bills are
 * finished; the owner is told and can cancel. Once only; never on a CLOSED store.
 */
/**
 * POST /admin/stores/{id}/free-number { reason }: the owner's number never
 * checked, held by the wrong person. The owner is suspended at once and the
 * store's deletion starts; the number is free once the store closes.
 */
export function freeStoreNumber(id: string, reason: string): Promise<AdminStore> {
  if (!USE_MOCK) return http('POST', storePath(id, 'free-number'), { reason }, { serverWords: true })
  return reply(() => {
    const store = find(id)
    if (store.phoneVerified !== false) throw new ApiError('WRONG_STATE')
    if (store.status === 'CLOSED') throw new ApiError('NOT_FOUND')
    store.deletionRequestedAt ??= now()
    return withCount(store)
  })
}

export function requestStoreDeletion(id: string): Promise<AdminStore> {
  if (!USE_MOCK) return http('POST', storePath(id, 'deletion'))
  return reply(() => {
    const store = find(id)
    if (store.deletionRequestedAt || store.status === 'CLOSED') throw new ApiError('WRONG_STATE')
    store.deletionRequestedAt = now()
    return withCount(store)
  })
}

const now = () => new Date().toISOString()

const storePath = (id: string, action?: string) => `/admin/stores/${encodeURIComponent(id)}${action ? `/${action}` : ''}`

function change(
  id: string,
  allowedFrom: (status: StoreStatus) => boolean,
  update: () => Partial<StoreRecord>,
): Promise<AdminStore> {
  return reply(() => {
    const store = find(id)
    if (!allowedFrom(store.status)) throw new ApiError('WRONG_STATE')
    Object.assign(store, update())
    return withCount(store)
  })
}

function find(id: string): StoreRecord {
  const store = STORES.find((s) => s.id === id)
  if (!store) throw new ApiError('NOT_FOUND')
  return store
}

// Read by the other mock files, never by a screen.

export function waitingStores(): AdminStore[] {
  return STORES.filter((s) => isWaiting(s.status))
    .sort((a, b) => a.submittedAt.localeCompare(b.submittedAt))
    .map(withCount)
}

export function allStores(): AdminStore[] {
  return STORES.map(withCount)
}

export function storeFace(id: string): { id: string; storeName: string; status: StoreStatus } {
  const store = find(id)
  return { id: store.id, storeName: store.storeName, status: store.status }
}

/**
 * What a store charges to bring an order to [city], as the app's
 * _deliveryTerms works it out; undefined where it does not deliver.
 */
export function deliveryFee(id: string, city: Governorate): number | undefined {
  const { delivery, governorate } = find(id)
  if (!delivery?.governorates.includes(city)) return undefined
  return city === governorate ? delivery.feeInside : delivery.feeOutside
}
