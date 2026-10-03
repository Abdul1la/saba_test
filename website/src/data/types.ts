// The shapes the admin screens read. Field names and status values are the
// mobile app's (mobile/lib/features/*/domain/entities.dart); anything the app
// does not have yet is marked "web-only" and listed in TODO.md.

/** `MerchantStatus`. No UNDER_REVIEW in v1 (API_CONTRACT.md §6.9). CLOSED: its owner deleted the account. */
export type StoreStatus = 'PENDING' | 'APPROVED' | 'REJECTED' | 'SUSPENDED' | 'CLOSED'

/** `MerchantProductRow.status`. */
export type ProductStatus = 'DRAFT' | 'PENDING' | 'APPROVED' | 'REJECTED'

/** `OrderStatus`. A store's NEW is the same status as PENDING. */
export type OrderStatus =
  | 'PENDING'
  | 'CONFIRMED'
  | 'PROCESSING'
  | 'SHIPPED'
  | 'DELIVERED'
  | 'CANCELLED'
  | 'REFUSED'
  | 'RETURNED'
  | 'REFUNDED'

/** CANCELLED: nothing is coming, so nothing is paid (the app's own value). */
export type PaymentStatus = 'PENDING' | 'PAID' | 'REFUNDED' | 'CANCELLED'

export type StockStatus = 'IN_STOCK' | 'LOW_STOCK' | 'OUT_OF_STOCK'

/** `Governorate.apiValue`: Iraq's 19. */
export type Governorate =
  | 'BAGHDAD'
  | 'BASRA'
  | 'NINEVEH'
  | 'ERBIL'
  | 'SULAYMANIYAH'
  | 'DUHOK'
  | 'KIRKUK'
  | 'NAJAF'
  | 'KARBALA'
  | 'BABYLON'
  | 'ANBAR'
  | 'DHI_QAR'
  | 'DIYALA'
  | 'SALAH_AL_DIN'
  | 'WASIT'
  | 'MAYSAN'
  | 'QADISIYAH'
  | 'MUTHANNA'
  | 'HALABJA'

export interface Category {
  id: string
  name: string
  nameAr: string
  /** The server sends null where there is none. */
  imageUrl?: string | null
  parentId?: string | null
  children: Category[]
}

/** A store's delivery settings, as `mock_data.dart` keeps them. */
export interface StoreDelivery {
  governorates: Governorate[]
  feeInside: number
  timeInside: string
  feeOutside: number
  timeOutside: string
}

/**
 * One store as the admin sees it: the store record (`MockData.merchants`),
 * its owner as `MerchantRegistration` names them, and where the review has
 * got to (`status`, `submittedAt`, `answeredAt` from the demo's queue record).
 */
export interface AdminStore {
  id: string
  storeName: string
  status: StoreStatus
  fullName: string
  phone: string
  email?: string
  businessAddress?: string
  description?: string
  country: string
  governorate: Governorate
  logoUrl?: string
  bannerUrl?: string
  rating?: number
  reviewCount: number
  delivery?: StoreDelivery
  submittedAt: string
  answeredAt?: string
  /** The name `MerchantProductRow` uses; kept for stores too. */
  rejectionReason?: string
  /** web-only: why it was suspended. */
  suspensionReason?: string
  /** Worked out from the catalogue, never typed in. */
  productCount: number
  /** Deleting the owner's account was requested (by the owner in the app, or by Saba; the server doesn't say which): the store is closed until it is done (every bill paid) or cancelled. */
  deletionRequestedAt?: string
  /** CLOSED: when the account was deleted. The owner's name, phone and email are gone; the store's name stays. */
  closedAt?: string
  /** false: signed up while SMS codes were off, so the owner's number was never checked (API_CONTRACT.md §3.4, §3.11). */
  phoneVerified?: boolean
}

export interface ProductVariant {
  id: string
  price: number
  /** The product's price before its discount, plus this option's extra. */
  originalPrice?: number
  availableQuantity: number
  stockStatus: StockStatus
  options: Record<string, string>
}

export interface AdminProduct {
  id: string
  nameEn: string
  nameAr: string
  description?: string
  price: number
  originalPrice?: number
  discountPercentage?: number
  currencyCode: string
  stockStatus: StockStatus
  availableQuantity: number
  categoryId: string
  categoryName: string
  /** web-only: the admin reads both languages, so both names come back. */
  categoryNameAr: string
  /** isNew: a name a store typed, waiting for Saba's check; approving the product approves it (API_CONTRACT.md §3.14). */
  brand?: { id: string; name: string; nameAr?: string | null; isNew?: boolean }
  merchant: { id: string; storeName: string; status: StoreStatus }
  imageUrl?: string
  images: { id: string; url: string; isPrimary: boolean }[]
  warranty?: string
  variants: ProductVariant[]
  createdAt: string
  status: ProductStatus
  rejectionReason?: string
  /** The store's own switch (the app's `isActive`): off, it is not sold. */
  isActive: boolean
  /** web-only: taken out of the shop by Saba; the store keeps its copy and can't put it back (API_CONTRACT.md §6.8). */
  takenDown: boolean
  /** web-only: why Saba took it down; the store is told. */
  takenDownReason?: string
  /** The server's word on the shop; the mock leaves it out and the sheet works it out. */
  inShop?: boolean
  notInShopReason?: 'NOT_APPROVED' | 'TAKEN_DOWN' | 'HIDDEN_BY_STORE' | 'STORE_NOT_APPROVED' | 'STORE_CLOSED'
}

/** `OrderAddress`. */
export interface OrderAddress {
  fullName: string
  phone?: string
  governorate?: Governorate
  area?: string
  street?: string
  landmark?: string
}

/** `OrderItem`: the snapshot taken when the order was placed. */
export interface OrderItem {
  id: string
  productId?: string
  productName: string
  /** web-only: the admin reads both languages, so both names are kept. */
  productNameAr?: string
  imageUrl?: string
  /** The option bought ("Black · 128GB"); the server's, the mock has none. */
  variantLabel?: string
  quantity: number
  unitPrice: number
  lineTotal: number
  merchantId: string
  merchantName: string
}

/**
 * One store's part of an order: the app's `storeParts` entry. Each store
 * ships its own part with its own driver, named when it marks it shipped.
 * Delivery companies and tracking numbers come later (TODO.md).
 */
export interface OrderStorePart {
  merchantId: string
  /** What its driver collects at the door. */
  amountDue: number
  status: OrderStatus
  courierName?: string
  courierPhone?: string
  /** The shopper's "did you receive it?"; not read here. */
  received?: boolean
}

export interface OrderStep {
  status: OrderStatus
  occurredAt: string
  /** The store that took this step; the server's, the mock has none. */
  storeName?: string
}

/** A shopper's `Order` with the customer a store sees (`MerchantOrderRow`). */
export interface AdminOrder {
  id: string
  orderNumber: string
  placedAt: string
  deliveredAt?: string
  status: OrderStatus
  paymentStatus: PaymentStatus
  isCashOnDelivery: boolean
  paymentMethodLabel: string
  subtotal: number
  shipping: number
  discount: number
  total: number
  currencyCode: string
  itemCount: number
  customerName: string
  customerPhone: string
  /** The shopper's account; the server's, the mock finds it by phone (customerIdOf). */
  customerId?: string
  shippingAddress: OrderAddress
  /** One per store: each part's status and, once shipped, its driver (API_CONTRACT.md §6.4). */
  storeParts: OrderStorePart[]
  /** Every step it took, oldest first: the app's `timeline` (`OrderTimelineEntry`). */
  timeline: OrderStep[]
  /** Set on a CANCELLED order: when, who, and the reason's code (the app's `cancelReason` / `cancellationReason`). */
  cancelledAt?: string
  /** web-only: the app keeps who by the reason's code; the admin reads it plainly. */
  cancelledBy?: 'SHOPPER' | 'STORE'
  cancelReason?: string
  cancelNote?: string
  merchantNames: string[]
  items: OrderItem[]
}

export interface Admin {
  id: string
  fullName: string
  email: string
  phone: string
}

/** A list and how many of each status match the search (for the chips). */
export interface ListResult<T, S extends string> {
  items: T[]
  counts: Partial<Record<S, number>> & { all: number }
}

/** Which page of a list to ask for (API_CONTRACT.md §1.3): pages count from 1; PER_PAGE rows unless said. */
export interface PageAsk {
  page: number
  perPage?: number
}

/** The page a list answered with: `total` rows match its search and filters. */
export interface PageMeta {
  page: number
  perPage: number
  total: number
  totalPages: number
}

/** One page of a list: its usual object (the counts stay the whole list's), with `meta`. */
export type Paged<R> = R & { meta: PageMeta }
