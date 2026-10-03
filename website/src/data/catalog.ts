import { savedLang } from '@/lib/i18n'
import { CATEGORIES } from './categories'
import { http, httpPage, searchOf, USE_MOCK } from './http'
import { ApiError, countBy, pageOf, reply } from './mock'
import { allProducts, BRANDS, demoProducts } from './products'
import { storeFace } from './stores'
import type { Category, PageAsk, Paged } from './types'

// Saba's own catalogue pages (API_CONTRACT.md §3.14): categories, Home's
// banners and brands, and the pictures they take. Every write keeps the
// server's words for a refusal: they name the field, the count, the clash.

export interface AdminCategory {
  id: string
  name: string
  nameAr: string
  imageUrl: string | null
  /** null: top level. Two levels only. */
  parentId: string | null
  /** Off Home, Browse, the filters and the stores' picker; its products stay on sale. */
  hidden: boolean
  /** Its own products (a sub-category counts its own). */
  productCount: number
  /** A top-level category's sub-categories; [] on a sub-category. */
  children: AdminCategory[]
}

export interface CategoryInput {
  name: string
  nameAr: string
  parentId: string | null
  imageUrl: string | null
}

export type LinkType = 'PRODUCT' | 'STORE' | 'CATEGORY'

export interface AdminBanner {
  id: string
  imageUrl: string | null
  titleEn: string | null
  titleAr: string | null
  subtitleEn: string | null
  subtitleAr: string | null
  /** What a tap opens, named as Saba reads it; null opens nothing. */
  link: { type: LinkType; id: string; name: string | null } | null
  isActive: boolean
  /** Its link opens nothing now (taken down, suspended, hidden): Home leaves it off. */
  linkBroken: boolean
}

/** Words in both languages or neither; a picture always. */
export interface BannerInput {
  imageUrl: string
  titleEn: string | null
  titleAr: string | null
  subtitleEn: string | null
  subtitleAr: string | null
  link: { type: LinkType; id: string } | null
  isActive: boolean
}

/** PENDING: a name a store typed, not checked by Saba yet. */
export type BrandStatus = 'APPROVED' | 'PENDING'

export interface AdminBrand {
  id: string
  name: string
  /** A typed brand has none until Saba saves it. */
  nameAr: string | null
  status: BrandStatus
  productCount: number
}

const WRITE = { serverWords: true }

// ------------------------------------------------------------- pictures ---

/** POST /media/upload: the picture's url, to send as an imageUrl. The demo keeps it in the page. */
export async function uploadImage(file: File): Promise<string> {
  if (USE_MOCK) return reply(() => URL.createObjectURL(file))
  const form = new FormData()
  form.append('file', file)
  form.append('kind', 'IMAGE')
  return (await http<{ url: string }>('POST', '/media/upload', form, WRITE)).url
}

// ----------------------------------------------------------- categories ---

/** GET /admin/categories: the top level in the shop's order, each with its sub-categories, hidden ones too. */
export function listAdminCategories(): Promise<AdminCategory[]> {
  if (!USE_MOCK) return http('GET', '/admin/categories')
  return reply(() => CATEGORIES.map(categoryFace))
}

/** POST /admin/categories: last on its level; shoppers see it at once. */
export function addCategory(input: CategoryInput): Promise<AdminCategory> {
  if (!USE_MOCK) return http('POST', '/admin/categories', input, WRITE)
  return reply(() => {
    const level = levelOf(input.parentId)
    namesFree(level, input)
    const category: Category = { id: `c-${Date.now()}`, ...input, children: [] }
    level.push(category)
    return categoryFace(category)
  })
}

/** PATCH /admin/categories/{id}: what it leaves out stays. A new level puts it last there. */
export function changeCategory(id: string, change: Partial<CategoryInput> & { hidden?: boolean }): Promise<AdminCategory> {
  if (!USE_MOCK) return http('PATCH', `/admin/categories/${encodeURIComponent(id)}`, change, WRITE)
  return reply(() => {
    const { category, level } = findCategory(id)
    const parentId = change.parentId === undefined ? (category.parentId ?? null) : change.parentId
    const target = levelOf(parentId)
    if (parentId === id || (parentId !== (category.parentId ?? null) && category.children.length > 0)) throw refusal(422, TWO_LEVELS)
    namesFree(target, { name: change.name ?? category.name, nameAr: change.nameAr ?? category.nameAr }, id)
    if (change.name !== undefined) category.name = change.name
    if (change.nameAr !== undefined) category.nameAr = change.nameAr
    if (change.imageUrl !== undefined) category.imageUrl = change.imageUrl
    if (change.hidden !== undefined) (change.hidden ? HIDDEN.add(id) : HIDDEN.delete(id))
    if (target !== level) {
      level.splice(level.indexOf(category), 1)
      category.parentId = parentId
      target.push(category)
    }
    return categoryFace(category)
  })
}

/** POST /admin/categories/order: one level's whole order; 409 when the page is out of date. */
export function orderCategories(parentId: string | null, ids: string[]): Promise<AdminCategory[]> {
  if (!USE_MOCK) return http('POST', '/admin/categories/order', { parentId, ids }, WRITE)
  return reply(() => {
    reorder(levelOf(parentId), ids)
    return CATEGORIES.map(categoryFace)
  })
}

/** DELETE /admin/categories/{id}?moveTo=: its products move first, as they are. 409 with sub-categories, or products and no moveTo. */
export function deleteCategory(id: string, moveTo?: string): Promise<{ moved: number }> {
  if (!USE_MOCK) return http('DELETE', `/admin/categories/${encodeURIComponent(id)}?${searchOf({ moveTo })}`, undefined, WRITE)
  return reply(() => {
    const { category, level } = findCategory(id)
    if (category.children.length > 0) throw refusal(409, HAS_CHILDREN)
    const products = demoProducts((p) => p.categoryId === id)
    if (products.length > 0) {
      if (moveTo === undefined) throw refusal(409, hasProducts(products.length))
      if (moveTo === id || !tryFind(moveTo)) throw refusal(422, ['Choose another category.', 'اختر قسماً آخر.'])
      for (const p of products) p.categoryId = moveTo
    }
    level.splice(level.indexOf(category), 1)
    HIDDEN.delete(id)
    return { moved: products.length }
  })
}

// --------------------------------------------------------------- banners ---

/** GET /admin/banners: in Home's order, off ones too. */
export function listBanners(): Promise<AdminBanner[]> {
  if (!USE_MOCK) return http('GET', '/admin/banners')
  return reply(() => BANNERS.map(bannerFace))
}

/** POST /admin/banners: last on Home. A link to something shoppers can't open now: 422. */
export function addBanner(input: BannerInput): Promise<AdminBanner> {
  if (!USE_MOCK) return http('POST', '/admin/banners', input, WRITE)
  return reply(() => {
    const banner = { id: `bn-${Date.now()}`, ...checkedBanner(input) }
    BANNERS.push(banner)
    return bannerFace(banner)
  })
}

/** PUT /admin/banners/{id}: the whole banner; its place stays. */
export function changeBanner(id: string, input: BannerInput): Promise<AdminBanner> {
  if (!USE_MOCK) return http('PUT', `/admin/banners/${encodeURIComponent(id)}`, input, WRITE)
  return reply(() => {
    const index = BANNERS.findIndex((b) => b.id === id)
    if (index < 0) throw new ApiError('NOT_FOUND')
    BANNERS[index] = { id, ...checkedBanner(input) }
    return bannerFace(BANNERS[index])
  })
}

/** POST /admin/banners/order: Home's whole order; 409 when the page is out of date. */
export function orderBanners(ids: string[]): Promise<AdminBanner[]> {
  if (!USE_MOCK) return http('POST', '/admin/banners/order', { ids }, WRITE)
  return reply(() => {
    reorder(BANNERS, ids)
    return BANNERS.map(bannerFace)
  })
}

/** DELETE /admin/banners/{id} */
export function deleteBanner(id: string): Promise<unknown> {
  if (!USE_MOCK) return http('DELETE', `/admin/banners/${encodeURIComponent(id)}`, undefined, WRITE)
  return reply(() => {
    const index = BANNERS.findIndex((b) => b.id === id)
    if (index < 0) throw new ApiError('NOT_FOUND')
    BANNERS.splice(index, 1)
    return {}
  })
}

// ---------------------------------------------------------------- brands ---

/** GET /admin/brands?q=&status=&page= : new ones first, then by name; the counts are the whole search's. */
export function listBrands(query: { q?: string; status?: BrandStatus } & PageAsk): Promise<Paged<{ items: AdminBrand[]; counts: Partial<Record<BrandStatus, number>> & { all: number } }>> {
  if (!USE_MOCK) return httpPage('/admin/brands', { q: query.q, status: query.status }, query)
  return reply(() => {
    const q = (query.q ?? '').trim().toLowerCase()
    const found = BRANDS.filter((b) => !q || b.name.toLowerCase().includes(q) || (b.nameAr ?? '').includes(q))
    const items = found
      .filter((b) => !query.status || b.status === query.status)
      .sort((a, b) => Number(b.status === 'PENDING') - Number(a.status === 'PENDING') || a.name.localeCompare(b.name))
      .map(brandFace)
    return { ...pageOf(items, query), counts: countBy(found, (b) => [b.status]) }
  })
}

/** POST /admin/brands: a checked brand; stores can pick it at once. */
export function addBrand(input: { name: string; nameAr: string }): Promise<AdminBrand> {
  if (!USE_MOCK) return http('POST', '/admin/brands', input, WRITE)
  return reply(() => {
    brandNamesFree(input)
    const brand = { id: `b-${Date.now()}`, ...input, status: 'APPROVED' as const }
    BRANDS.push(brand)
    return brandFace(brand)
  })
}

/** PUT /admin/brands/{id}: renamed on every product at once, and a new one is checked. */
export function changeBrand(id: string, input: { name: string; nameAr: string }): Promise<AdminBrand> {
  if (!USE_MOCK) return http('PUT', `/admin/brands/${encodeURIComponent(id)}`, input, WRITE)
  return reply(() => {
    const brand = BRANDS.find((b) => b.id === id)
    if (!brand) throw new ApiError('NOT_FOUND')
    brandNamesFree(input, id)
    Object.assign(brand, input, { status: 'APPROVED' })
    return brandFace(brand)
  })
}

/** DELETE /admin/brands/{id}?moveTo=ID|none: its products move first, as they are. 409 with products and no moveTo. */
export function deleteBrand(id: string, moveTo?: string): Promise<{ moved: number }> {
  if (!USE_MOCK) return http('DELETE', `/admin/brands/${encodeURIComponent(id)}?${searchOf({ moveTo })}`, undefined, WRITE)
  return reply(() => {
    const index = BRANDS.findIndex((b) => b.id === id)
    if (index < 0) throw new ApiError('NOT_FOUND')
    const products = demoProducts((p) => p.brand?.id === id)
    if (products.length > 0) {
      if (moveTo === undefined) throw refusal(409, hasProducts(products.length, true))
      const target = BRANDS.find((b) => b.id === moveTo && b.id !== id && b.status === 'APPROVED')
      if (moveTo !== 'none' && !target) throw refusal(422, ['Choose another checked brand, or none.', 'اختر علامة تجارية أخرى مُراجَعة، أو بلا علامة.'])
      for (const p of products) p.brand = target
    }
    BRANDS.splice(index, 1)
    return { moved: products.length }
  })
}

// ----------------------------------------------------------- the demo's ---

const HIDDEN = new Set<string>()

/** A refusal in the server's words, in the admin's language. */
const refusal = (status: 409 | 422, [en, ar]: [string, string]) => new ApiError(status === 409 ? 'WRONG_STATE' : 'UNEXPECTED', undefined, savedLang() === 'ar' ? ar : en)
const TWO_LEVELS: [string, string] = ['Categories have two levels: a category and its sub-categories.', 'للأقسام مستويان فقط: القسم وأقسامه الفرعية.']
const HAS_CHILDREN: [string, string] = ['It still has sub-categories. Delete or move them first.', 'ما زالت فيه أقسام فرعية. احذفها أو انقلها أولاً.']
const hasProducts = (n: number, brand = false): [string, string] =>
  brand
    ? [`It still has ${n} products. Choose a brand to move them to, or none.`, `ما زالت لها ${n} من المنتجات. اختر علامة تجارية لنقلها إليها، أو بلا علامة.`]
    : [`It still has ${n} products. Choose a category to move them to.`, `ما زال فيه ${n} من المنتجات. اختر قسماً لنقلها إليه.`]

const same = (a: string | null | undefined, b: string | null | undefined) => !!a && !!b && a.trim().toLowerCase() === b.trim().toLowerCase()

function categoryFace(c: Category): AdminCategory {
  return {
    id: c.id,
    name: c.name,
    nameAr: c.nameAr,
    imageUrl: c.imageUrl ?? null,
    parentId: c.parentId ?? null,
    hidden: HIDDEN.has(c.id),
    productCount: demoProducts((p) => p.categoryId === c.id).length,
    children: c.children.map(categoryFace),
  }
}

function levelOf(parentId: string | null): Category[] {
  if (parentId === null) return CATEGORIES
  const parent = CATEGORIES.find((c) => c.id === parentId)
  if (!parent) throw refusal(422, TWO_LEVELS)
  return parent.children
}

function tryFind(id: string): { category: Category; level: Category[] } | undefined {
  for (const top of CATEGORIES) {
    if (top.id === id) return { category: top, level: CATEGORIES }
    const child = top.children.find((c) => c.id === id)
    if (child) return { category: child, level: top.children }
  }
  return undefined
}

function findCategory(id: string) {
  const found = tryFind(id)
  if (!found) throw new ApiError('NOT_FOUND')
  return found
}

function namesFree(level: Category[], input: { name: string; nameAr: string }, self?: string) {
  if (level.some((c) => c.id !== self && (same(c.name, input.name) || same(c.nameAr, input.nameAr)))) {
    throw refusal(422, ['Another category here already has this name.', 'يوجد قسم آخر هنا بهذا الاسم.'])
  }
}

function brandNamesFree(input: { name: string; nameAr: string }, self?: string) {
  const names = [input.name, input.nameAr]
  if (BRANDS.some((b) => b.id !== self && names.some((n) => same(n, b.name) || same(n, b.nameAr)))) {
    throw refusal(422, ['Another brand already has this name.', 'توجد علامة تجارية أخرى بهذا الاسم.'])
  }
}

/** Every id on the list, each once, puts the list in that order; anything else is an out-of-date page. */
function reorder<T extends { id: string }>(list: T[], ids: string[]) {
  if (new Set(ids).size !== ids.length || ids.length !== list.length || list.some((x) => !ids.includes(x.id))) {
    throw refusal(409, ['The list changed while you were ordering it. Refresh and try again.', 'تغيّرت القائمة أثناء ترتيبها. حدّث الصفحة وحاول مرة أخرى.'])
  }
  list.sort((a, b) => ids.indexOf(a.id) - ids.indexOf(b.id))
}

const brandFace = (b: (typeof BRANDS)[number]): AdminBrand => ({
  id: b.id,
  name: b.name,
  nameAr: b.nameAr,
  status: b.status,
  productCount: demoProducts((p) => p.brand?.id === b.id).length,
})

type DemoBanner = Omit<BannerInput, 'link'> & { id: string; link: BannerInput['link'] }

// web-only demo: one banner on Home, one switched off.
const BANNERS: DemoBanner[] = [
  {
    id: 'bn-1',
    imageUrl: '/demo/products/phones-1.jpg',
    titleEn: 'New phones, delivered by your city’s stores',
    titleAr: 'هواتف جديدة، تصلك من متاجر مدينتك',
    subtitleEn: 'Cash when it arrives',
    subtitleAr: 'الدفع عند الاستلام',
    link: { type: 'CATEGORY', id: 'c-phones' },
    isActive: true,
  },
  {
    id: 'bn-2',
    imageUrl: '/demo/products/home-appliances-1.jpg',
    titleEn: null,
    titleAr: null,
    subtitleEn: null,
    subtitleAr: null,
    link: { type: 'STORE', id: 'm-2' },
    isActive: false,
  },
]

/** What a banner's link opens now, and its name; undefined when it opens nothing shoppers can see. */
function linkTarget(link: NonNullable<BannerInput['link']>): string | undefined {
  if (link.type === 'PRODUCT') {
    const p = allProducts().find((x) => x.id === link.id)
    return p && p.status === 'APPROVED' && p.isActive && !p.takenDown && p.merchant.status === 'APPROVED' ? p.nameEn : undefined
  }
  if (link.type === 'STORE') {
    const s = storeFace(link.id)
    return s.status === 'APPROVED' ? s.storeName : undefined
  }
  const found = tryFind(link.id)
  const parentHidden = !!found?.category.parentId && HIDDEN.has(found.category.parentId)
  return found && !HIDDEN.has(link.id) && !parentHidden ? found.category.name : undefined
}

function bannerFace(b: DemoBanner): AdminBanner {
  const name = b.link ? linkTarget(b.link) : undefined
  return { ...b, link: b.link && { ...b.link, name: name ?? null }, linkBroken: !!b.link && name === undefined }
}

function checkedBanner(input: BannerInput): Omit<DemoBanner, 'id'> {
  if (!input.imageUrl) throw refusal(422, ['Add a picture.', 'أضف صورة.'])
  if (input.link && linkTarget(input.link) === undefined) {
    throw refusal(422, ['This no longer opens anything shoppers can see. Choose another link.', 'هذا لم يعد يفتح شيئاً يراه المتسوقون. اختر رابطاً آخر.'])
  }
  return input
}
