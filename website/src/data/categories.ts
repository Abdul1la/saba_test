import { http, USE_MOCK } from './http'
import { reply } from './mock'
import type { Category } from './types'

// Mirrors MockData.categories: the seven v1 categories. The demo's Categories
// page changes this same tree (catalog.ts), as Saba's does the server's.
const photo = (group: string) => `/demo/products/${group}-1.jpg`

export const CATEGORIES: Category[] = [
  {
    id: 'c-phones',
    name: 'Phones',
    nameAr: 'هواتف',
    imageUrl: photo('phones'),
    children: [
      { id: 'c-smartphones', name: 'Smartphones', nameAr: 'هواتف ذكية', parentId: 'c-phones', children: [] },
      { id: 'c-tablets', name: 'Tablets', nameAr: 'أجهزة لوحية', parentId: 'c-phones', children: [] },
    ],
  },
  {
    id: 'c-laptops',
    name: 'Laptops',
    nameAr: 'حواسيب محمولة',
    imageUrl: photo('laptops'),
    children: [
      { id: 'c-ultrabooks', name: 'Ultrabooks', nameAr: 'حواسيب نحيفة', parentId: 'c-laptops', children: [] },
      { id: 'c-gaming-laptops', name: 'Gaming laptops', nameAr: 'حواسيب ألعاب', parentId: 'c-laptops', children: [] },
    ],
  },
  { id: 'c-headphones', name: 'Headphones', nameAr: 'سماعات', imageUrl: photo('headphones'), children: [] },
  { id: 'c-watches', name: 'Smartwatches', nameAr: 'ساعات ذكية', imageUrl: photo('smartwatches'), children: [] },
  { id: 'c-cameras', name: 'Cameras', nameAr: 'كاميرات', imageUrl: photo('cameras'), children: [] },
  { id: 'c-home', name: 'Home appliances', nameAr: 'أجهزة منزلية', imageUrl: photo('home-appliances'), children: [] },
  {
    id: 'c-accessories',
    name: 'Accessories',
    nameAr: 'إكسسوارات',
    imageUrl: photo('accessories'),
    children: [
      { id: 'c-phone-cases', name: 'Cases & Covers', nameAr: 'أغطية وحافظات', parentId: 'c-accessories', children: [] },
      { id: 'c-chargers', name: 'Chargers', nameAr: 'شواحن', parentId: 'c-accessories', children: [] },
    ],
  },
]

/** GET /categories — the tree the app already reads. */
export function listCategories(): Promise<Category[]> {
  if (!USE_MOCK) return http('GET', '/categories')
  return reply(() => CATEGORIES)
}

/** The top-level category a category id sits under (itself, if top-level). */
export function topCategoryOf(id: string): Category | undefined {
  return CATEGORIES.find((top) => top.id === id || top.children.some((child) => child.id === id))
}

/** A category or sub-category by id, synchronously, for seed data. */
export function categoryById(id: string): Category | undefined {
  for (const top of CATEGORIES) {
    if (top.id === id) return top
    const child = top.children.find((c) => c.id === id)
    if (child) return child
  }
  return undefined
}
