import { categoryById, topCategoryOf } from './categories'
import { http, httpPage, USE_MOCK } from './http'
import { ApiError, countBy, daysAgo, matches, pageOf, reply, requireReason } from './mock'
import { storeFace } from './stores'
import type { AdminProduct, ListResult, PageAsk, Paged, ProductStatus, ProductVariant, StockStatus } from './types'

/** The chips on the products page: the statuses, and Taken down. */
export type ProductFilter = Exclude<ProductStatus, 'DRAFT'> | 'TAKEN_DOWN'

// A product without its store and category names, which are looked up when
// it is read, as a server would join them.
type ProductRecord = Omit<AdminProduct, 'merchant' | 'categoryName' | 'categoryNameAr'> & { merchantId: string }

// ---------------------------------------------------------------------------
// A port of MockData.products (mobile/lib/core/mock/mock_data.dart): the same
// names, ids, prices, stock and categories, built by the same arithmetic.

/** What a product is sold in: one kind, a phone's options or a laptop's. */
type Sold = 'plain' | 'phone' | 'laptop'

/** name, Arabic name, category, brand, price, price before a discount, what it is sold in. */
type First = [string, string, string, string, number, number | null, Sold]

// Nova Electronics' and Atlas Home's own, alternating (p-1 Nova, p-2 Atlas, ...).
const FIRST_PRODUCTS: First[] = [
  ['Nova X5 Smartphone', 'هاتف نوفا X5 الذكي', 'c-smartphones', 'b-nova', 329000, 389000, 'phone'],
  ['Atlas Air Fryer 5L', 'قلاية هوائية أطلس 5 لتر', 'c-home', 'b-atlas', 95000, null, 'plain'],
  ['Lumen Book 14 Ultrabook', 'حاسوب لومن بوك 14 النحيف', 'c-ultrabooks', 'b-lumen', 675000, null, 'laptop'],
  ['Atlas Steam Iron', 'مكواة بخار أطلس', 'c-home', 'b-atlas', 32000, 38000, 'plain'],
  ['Kite Audio Studio Headphones', 'سماعات كايت أوديو ستوديو', 'c-headphones', 'b-kite', 145000, null, 'plain'],
  ['Atlas Robot Vacuum', 'مكنسة روبوت أطلس', 'c-home', 'b-atlas', 265000, null, 'plain'],
  ['Nova Watch Series 4', 'ساعة نوفا الذكية الإصدار 4', 'c-watches', 'b-nova', 189000, 229000, 'plain'],
  ['Atlas Stand Mixer', 'عجّانة أطلس الكهربائية', 'c-home', 'b-atlas', 145000, null, 'plain'],
  ['Orbit Mirrorless Camera', 'كاميرا أوربت بدون مرآة', 'c-cameras', 'b-orbit', 950000, null, 'plain'],
  ['Atlas Espresso Machine', 'ماكينة إسبريسو أطلس', 'c-home', 'b-atlas', 185000, 219000, 'plain'],
  ['Nova Fast Charger 65W', 'شاحن نوفا السريع 65 واط', 'c-chargers', 'b-nova', 25000, null, 'plain'],
  ['Atlas Rice Cooker', 'طباخة رز أطلس', 'c-home', 'b-atlas', 45000, null, 'plain'],
]

/** The demo's brands, shared with their products, so a rename shows on each. PENDING: typed by a store, not checked yet. */
export const BRANDS: { id: string; name: string; nameAr: string | null; status: 'APPROVED' | 'PENDING' }[] = [
  // web-only demo: the Arabic names (the app keeps one name).
  { id: 'b-nova', name: 'Nova', nameAr: 'نوفا', status: 'APPROVED' },
  { id: 'b-lumen', name: 'Lumen', nameAr: 'لومن', status: 'APPROVED' },
  { id: 'b-atlas', name: 'Atlas', nameAr: 'أطلس', status: 'APPROVED' },
  { id: 'b-kite', name: 'Kite Audio', nameAr: 'كايت أوديو', status: 'APPROVED' },
  { id: 'b-orbit', name: 'Orbit', nameAr: 'أوربت', status: 'APPROVED' },
  { id: 'b-zagros', name: 'Zagros', nameAr: null, status: 'PENDING' }, // web-only demo: typed by Zagros's store with p-new-2
]

/** name, Arabic name, category, store, price, price before a discount. */
type More = [string, string, string, string, number, number | null]

const MORE_PRODUCTS: More[] = [
  ['Zagros Z10 Smartphone', 'هاتف زاغروس Z10 الذكي', 'c-smartphones', 'm-3', 289000, 339000],
  ['Zagros Z10 Clear Case', 'غطاء شفاف لهاتف زاغروس Z10', 'c-phone-cases', 'm-3', 9000, null],
  ['Tigris Power Bank 20000mAh', 'باور بانك دجلة 20000 ملي أمبير', 'c-chargers', 'm-3', 32000, null],
  ['Zagros Z7 Smartphone', 'هاتف زاغروس Z7', 'c-smartphones', 'm-3', 199000, null],
  ['Leather Flip Cover', 'غطاء جلد قلاب', 'c-phone-cases', 'm-3', 12500, 15000],
  ['Gara Air Cooler 60L', 'مبردة هواء كارا 60 لتر', 'c-home', 'm-4', 245000, 280000],
  ['Gara Standing Fan', 'مروحة كارا عمودية', 'c-home', 'm-4', 55000, null],
  ['Khabur Water Heater 50L', 'سخان ماء خابور 50 لتر', 'c-home', 'm-4', 175000, null],
  ['Khabur Electric Kettle', 'غلاية كهربائية خابور', 'c-home', 'm-4', 22500, 27500],
  ['Citadel Book 15 Laptop', 'حاسوب سيتادل بوك 15', 'c-ultrabooks', 'm-5', 690000, 790000],
  ['Citadel Gamer 17', 'حاسوب ألعاب سيتادل 17', 'c-gaming-laptops', 'm-5', 1250000, null],
  ['Citadel Book Air 13', 'حاسوب سيتادل بوك إير 13', 'c-ultrabooks', 'm-5', 540000, null],
  ['Erbil Fit Band 3', 'سوار أربيل الرياضي 3', 'c-watches', 'm-5', 45000, 55000],
  ['Wireless Mouse and Keyboard Set', 'طقم فأرة ولوحة مفاتيح لاسلكي', 'c-accessories', 'm-5', 35000, null],
  ['Frost Split AC 1.5 Ton', 'مكيف سبليت فروست 1.5 طن', 'c-home', 'm-6', 620000, 700000],
  ['Frost Split AC 2 Ton', 'مكيف سبليت فروست 2 طن', 'c-home', 'm-6', 780000, null],
  ['Frost Portable AC', 'مكيف فروست متنقل', 'c-home', 'm-6', 410000, null],
  ['Frost Ceiling Fan', 'مروحة سقفية فروست', 'c-home', 'm-6', 48000, null],
  ['Frost Voltage Stabiliser', 'منظم فولتية فروست', 'c-home', 'm-6', 60000, 72000],
  ['Sirwan S8 Smartphone', 'هاتف سيروان S8 الذكي', 'c-smartphones', 'm-7', 355000, null],
  ['Sirwan Kids Tablet', 'تابلت سيروان للأطفال', 'c-tablets', 'm-7', 120000, 150000],
  ['Goizha Fitness Band', 'سوار كويزة الرياضي', 'c-watches', 'm-7', 39000, null],
  ['Magnetic Car Phone Holder', 'حامل هاتف مغناطيسي للسيارة', 'c-accessories', 'm-7', 15000, null],
  ['Sirwan Game Controller', 'ذراع ألعاب سيروان', 'c-accessories', 'm-7', 42500, null],
  ['Hadba Washing Machine 9kg', 'غسالة الحدباء 9 كغم', 'c-home', 'm-8', 385000, 430000],
  ['Hadba Refrigerator 18ft', 'ثلاجة الحدباء 18 قدم', 'c-home', 'm-8', 720000, null],
  ['Hadba Gas Cooker 5 Burners', 'طباخ غاز الحدباء 5 عيون', 'c-home', 'm-8', 265000, null],
  ['Hadba Microwave 30L', 'مايكروويف الحدباء 30 لتر', 'c-home', 'm-8', 98000, 115000],
  ['Orbit Action Camera 4K', 'كاميرا أوربت أكشن 4K', 'c-cameras', 'm-1', 215000, 249000],
  ['Orbit Security Camera Indoor', 'كاميرا أوربت للمراقبة الداخلية', 'c-cameras', 'm-1', 48000, null],
  ['Sirwan Dash Camera', 'كاميرا سروان للسيارة', 'c-cameras', 'm-7', 72000, 89000],
  ['Citadel Webcam 1080p', 'كاميرا ويب سيتاديل 1080p', 'c-cameras', 'm-5', 35000, null],
  ['Zagros Wireless Earbuds', 'سماعات زاغروس اللاسلكية', 'c-headphones', 'm-3', 42000, 55000],
  ['Goizha Over-Ear Headphones', 'سماعات كويژة فوق الأذن', 'c-headphones', 'm-7', 78000, null],
  ['Citadel Gaming Headset', 'سماعة ألعاب سيتاديل', 'c-headphones', 'm-5', 65000, 79000],
  ['Tigris Bluetooth Speaker', 'مكبر صوت دجلة بلوتوث', 'c-accessories', 'm-3', 39000, null],
  ['Zagros Smartwatch Pro', 'ساعة زاغروس الذكية برو', 'c-watches', 'm-3', 125000, 149000],
  ['Nova Watch Lite', 'ساعة نوفا لايت', 'c-watches', 'm-1', 89000, null],
  ['Nova Tab 11', 'جهاز نوفا اللوحي 11', 'c-tablets', 'm-1', 310000, 359000],
  ['Citadel Tab Go', 'جهاز سيتاديل اللوحي جو', 'c-tablets', 'm-5', 165000, null],
  ['Hadba Electric Oven 45L', 'فرن كهربائي الحدباء 45 لتر', 'c-home', 'm-8', 95000, null],
  ['Gara Laptop Cooling Pad', 'قاعدة تبريد حاسوب گارا', 'c-accessories', 'm-4', 22000, 27000],
  ['Frost AC Outdoor Cover', 'غطاء الوحدة الخارجية لمكيف فروست', 'c-home', 'm-6', 18000, null],
  ['Atlas Kitchen Blender', 'خلاط أطلس للمطبخ', 'c-home', 'm-2', 54000, null],
]

const PHOTO_GROUP: Record<string, string> = {
  'c-phones': 'phones',
  'c-laptops': 'laptops',
  'c-headphones': 'headphones',
  'c-watches': 'smartwatches',
  'c-cameras': 'cameras',
  'c-home': 'home-appliances',
  'c-accessories': 'accessories',
}

/** Each demo category has one photo (demo_photos.dart), shared by its products. */
const photoFor = (categoryId: string) => `/demo/products/${PHOTO_GROUP[topCategoryOf(categoryId)!.id]}-1.jpg`

const stockStatusOf = (stock: number): StockStatus =>
  stock === 0 ? 'OUT_OF_STOCK' : stock < 6 ? 'LOW_STOCK' : 'IN_STOCK'

// MockData.seededStatus and seededHidden: the few demo products the two demo
// stores keep off sale, so each shelf tab has something in it.
const SEEDED_STATUS: Record<string, ProductStatus> = {
  'p-50': 'PENDING', // Nova
  'p-42': 'DRAFT',
  'p-41': 'REJECTED',
  'p-4': 'PENDING', // Atlas
  'p-10': 'DRAFT',
  'p-56': 'REJECTED',
}
/** Switched off by its store (the app's `isActive: false`), not taken down by Saba. */
const SEEDED_OFF = new Set(['p-51'])

const DESCRIPTION =
  'A demo product used while the backend is being built. Every field here travels through the same parsing the real API will use.'

function buildProduct(index: number): ProductRecord {
  const id = `p-${index + 1}`
  const first = index < FIRST_PRODUCTS.length ? FIRST_PRODUCTS[index] : undefined
  const row = first ?? MORE_PRODUCTS[index - FIRST_PRODUCTS.length]
  const [nameEn, nameAr, categoryId, , price, was] = row
  const originalPrice = was ?? undefined
  const stock = index % 7 === 5 ? 0 : 3 + ((index * 5) % 40)
  const photo = photoFor(categoryId)

  return {
    id,
    nameEn,
    nameAr,
    description: DESCRIPTION,
    price,
    originalPrice,
    discountPercentage: originalPrice === undefined ? undefined : Math.round((1 - price / originalPrice) * 100),
    currencyCode: 'IQD',
    stockStatus: stockStatusOf(stock),
    availableQuantity: stock,
    categoryId,
    brand: first ? BRANDS.find((b) => b.id === first[3]) : undefined,
    merchantId: first ? (index % 2 === 0 ? 'm-1' : 'm-2') : row[3],
    imageUrl: photo,
    images: [0, 1, 2].map((n) => ({ id: `${id}-img${n}`, url: photo, isPrimary: n === 0 })),
    warranty: '12 months manufacturer warranty',
    variants: first && first[6] !== 'plain' ? variantsFor(id, first[6], price, originalPrice, stock) : [],
    createdAt: daysAgo(first ? (FIRST_PRODUCTS.length - index) * 4 : 5 + (index - FIRST_PRODUCTS.length) * 2),
    // The demo's own products are approved from the start, but for those above.
    status: SEEDED_STATUS[id] ?? 'APPROVED',
    // The app's words for its seeded rejections.
    rejectionReason: SEEDED_STATUS[id] === 'REJECTED' ? 'Images do not meet the catalogue guidelines.' : undefined,
    isActive: !SEEDED_OFF.has(id),
    takenDown: false,
  }
}

/** A phone in three colours and two sizes; a laptop in two colours and two sizes, the larger dearer. */
function variantsFor(productId: string, sold: Sold, basePrice: number, originalPrice: number | undefined, stock: number): ProductVariant[] {
  const phone = sold === 'phone'
  const colors = phone ? ['Black', 'Silver', 'Blue'] : ['Silver', 'Black']
  const storages = phone ? ['128GB', '256GB'] : ['512GB', '1TB']
  const variants: ProductVariant[] = []
  for (const color of colors) {
    for (const storage of storages) {
      const extra = storage === storages.at(-1) ? (phone ? 80000 : 120000) : 0
      // One deliberately sold-out combination, as in the app.
      const variantStock = color === colors.at(-1) && storage === storages.at(-1) ? 0 : stock
      const n = variants.length
      variants.push({
        id: `${productId}-v${n}`,
        price: basePrice + extra,
        // The same saving on the dearer option.
        originalPrice: originalPrice === undefined ? undefined : originalPrice + extra,
        availableQuantity: variantStock,
        stockStatus: variantStock === 0 ? 'OUT_OF_STOCK' : 'IN_STOCK',
        options: { Color: color, Storage: storage },
      })
    }
  }
  return variants
}

/** A product a store added in the app and sent for review. */
function added(
  id: string,
  nameEn: string,
  nameAr: string,
  categoryId: string,
  merchantId: string,
  price: number,
  originalPrice: number | undefined,
  stock: number,
  createdAt: string,
  status: ProductStatus,
  rejectionReason?: string,
): ProductRecord {
  const photo = photoFor(categoryId)
  return {
    id,
    nameEn,
    nameAr,
    description: 'Sent for review from the store app.',
    price,
    originalPrice,
    discountPercentage: originalPrice === undefined ? undefined : Math.round((1 - price / originalPrice) * 100),
    currencyCode: 'IQD',
    stockStatus: stockStatusOf(stock),
    availableQuantity: stock,
    categoryId,
    merchantId,
    imageUrl: photo,
    images: [{ id: `${id}-img0`, url: photo, isPrimary: true }],
    variants: [],
    createdAt,
    status,
    rejectionReason,
    isActive: true,
    takenDown: false,
  }
}

const PRODUCTS: ProductRecord[] = [
  ...Array.from({ length: FIRST_PRODUCTS.length + MORE_PRODUCTS.length }, (_, i) => buildProduct(i)),

  // web-only demo: products stores sent for review, so the queue is not empty.
  added('p-new-1', 'Hadba Air Fryer 6L', 'قلاية هوائية الحدباء 6 لتر', 'c-home', 'm-8', 89000, 99000, 14, daysAgo(4, 2), 'PENDING'), // web-only demo
  { ...added('p-new-2', 'Zagros Z12 Smartphone', 'هاتف زاغروس Z12 الذكي', 'c-smartphones', 'm-3', 329000, undefined, 9, daysAgo(2, 6), 'PENDING'), brand: BRANDS[5] }, // web-only demo
  added('p-new-3', 'Frost Window AC 1 Ton', 'مكيف شباك فروست 1 طن', 'c-home', 'm-6', 350000, undefined, 5, daysAgo(1, 6), 'PENDING'), // web-only demo
  added('p-new-4', 'Citadel Mechanical Keyboard', 'لوحة مفاتيح ميكانيكية سيتاديل', 'c-accessories', 'm-5', 58000, undefined, 20, daysAgo(0, 5), 'PENDING'), // web-only demo
  added('p-new-5', 'Phone Ring Light', 'إضاءة حلقية للهاتف', 'c-accessories', 'm-7', 16000, undefined, 30, daysAgo(6), 'REJECTED', 'The photos show another brand’s logo. Use photos of your own stock.'), // web-only demo
]

// ---------------------------------------------------------------------------

const filterOf = (p: ProductRecord): ProductFilter => (p.takenDown ? 'TAKEN_DOWN' : (p.status as ProductFilter))

function withNames(p: ProductRecord): AdminProduct {
  const { merchantId, ...rest } = p
  const category = categoryById(p.categoryId)
  const brand = p.brand && BRANDS.find((b) => b.id === p.brand!.id)
  return {
    ...rest,
    brand: brand && { id: brand.id, name: brand.name, nameAr: brand.nameAr, isNew: brand.status === 'PENDING' },
    merchant: storeFace(merchantId),
    categoryName: category?.name ?? '',
    categoryNameAr: category?.nameAr ?? '',
  }
}

/**
 * GET /admin/products?status=&q=&categoryId=&storeId=
 * (categoryId and storeId are web-only, TODO.md). A draft has not been sent
 * yet, so it is its store's alone and never listed here.
 */
export function listProducts(
  query: {
    q?: string
    status?: ProductFilter
    categoryId?: string
    storeId?: string
  } & PageAsk,
): Promise<Paged<ListResult<AdminProduct, ProductFilter>>> {
  if (!USE_MOCK) return httpPage('/admin/products', { q: query.q, status: query.status, categoryId: query.categoryId, storeId: query.storeId }, query)
  return reply(() => {
    const found = PRODUCTS.filter(
      (p) =>
        p.status !== 'DRAFT' &&
        (!query.storeId || p.merchantId === query.storeId) &&
        (!query.categoryId || p.categoryId === query.categoryId || topCategoryOf(p.categoryId)?.id === query.categoryId) &&
        matches(query.q ?? '', p.nameEn, p.nameAr, storeFace(p.merchantId).storeName),
    )
    const items = found
      .filter((p) => !query.status || filterOf(p) === query.status)
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
      .map(withNames)
    return { ...pageOf(items, query), counts: countBy(found, (p) => [filterOf(p)]) }
  })
}

/** GET /admin/products/{id} (web-only route, TODO.md) */
export function getProduct(id: string): Promise<AdminProduct> {
  if (!USE_MOCK) return http('GET', productPath(id))
  return reply(() => withNames(find(id)))
}

/** POST /admin/products/{id}/approve — refused without an Arabic name. */
export function approveProduct(id: string): Promise<AdminProduct> {
  if (!USE_MOCK) return http('POST', productPath(id, 'approve'))
  return change(id, (p) => p.status === 'PENDING', (p) => {
    if (!p.nameAr.trim()) throw new ApiError('ARABIC_NAME_REQUIRED')
    return { status: 'APPROVED', rejectionReason: undefined }
  })
}

/** POST /admin/products/{id}/reject { reason } */
export function rejectProduct(id: string, reason: string): Promise<AdminProduct> {
  if (!USE_MOCK) return http('POST', productPath(id, 'reject'), { reason })
  return change(id, (p) => p.status === 'PENDING', () => ({ status: 'REJECTED', rejectionReason: requireReason(reason) }))
}

/** POST /admin/products/{id}/hide { reason } (web-only route, TODO.md): Saba takes it down, and the store is told why. */
export function takeDownProduct(id: string, reason: string): Promise<AdminProduct> {
  if (!USE_MOCK) return http('POST', productPath(id, 'hide'), { reason })
  return change(id, (p) => p.status === 'APPROVED' && !p.takenDown, () => ({ takenDown: true, takenDownReason: requireReason(reason) }))
}

/** POST /admin/products/{id}/unhide (web-only route, TODO.md): back in the shop. */
export function putBackProduct(id: string): Promise<AdminProduct> {
  if (!USE_MOCK) return http('POST', productPath(id, 'unhide'))
  return change(id, (p) => p.takenDown, () => ({ takenDown: false, takenDownReason: undefined }))
}

const productPath = (id: string, action?: string) => `/admin/products/${encodeURIComponent(id)}${action ? `/${action}` : ''}`

function change(
  id: string,
  allowed: (p: ProductRecord) => boolean,
  update: (p: ProductRecord) => Partial<ProductRecord>,
): Promise<AdminProduct> {
  return reply(() => {
    const product = find(id)
    if (!allowed(product)) throw new ApiError('WRONG_STATE')
    Object.assign(product, update(product))
    return withNames(product)
  })
}

function find(id: string): ProductRecord {
  const product = PRODUCTS.find((p) => p.id === id)
  if (!product) throw new ApiError('NOT_FOUND')
  return product
}

// Read by the other mock files, never by a screen.

export function countProductsOf(storeId: string): number {
  return PRODUCTS.filter((p) => p.merchantId === storeId && p.status !== 'DRAFT').length
}

export function waitingProducts(): AdminProduct[] {
  return PRODUCTS.filter((p) => p.status === 'PENDING')
    .sort((a, b) => a.createdAt.localeCompare(b.createdAt))
    .map(withNames)
}

/** The demo's product records themselves, for the catalogue mock to count and move (catalog.ts). */
export const demoProducts = (test: (p: ProductRecord) => boolean) => PRODUCTS.filter(test)

export function allProducts(): AdminProduct[] {
  return PRODUCTS.filter((p) => p.status !== 'DRAFT').map(withNames)
}

/** A store's own demo products, in catalogue order, for its seeded orders. */
export function seedShelf(storeId: string): ProductRecord[] {
  return PRODUCTS.filter((p) => p.merchantId === storeId && !p.id.startsWith('p-new-'))
}

/** What was on sale when the demo opened (MockData.startsOnSale): approved, switched on, not taken down. */
export const onSale = (p: ProductRecord) => p.status === 'APPROVED' && p.isActive && !p.takenDown
