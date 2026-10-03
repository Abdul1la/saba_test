import type { Request } from 'express'
import { z } from 'zod'
import type { Context } from '../app.js'
import type { Connection, Pool } from '../db/pool.js'
import { exec, one, rows } from '../db/sql.js'
import { withTransaction } from '../db/tx.js'
import { me } from '../http/auth.js'
import { AppError } from '../http/errors.js'
import { IdParams, optionalText, requiredText } from '../http/inputs.js'
import { route, type Api } from '../http/route.js'
import type { MessageKey, MessageParams } from '../lib/i18n.js'
import { keyOf, urlOf } from '../lib/storage.js'
import { likeTyped, ListQuery, pageSql, paged } from './admin-lists.js'
import { LISTED, refreshSearchText } from './products.js'

// Saba's own pages for categories, Home banners and brands (the user's call,
// 2026-10-01): until now they changed only in the database, and the live one
// starts with no banners and no brands. Every change leaves an admin_actions row.
//
// - A category is hidden (off Home, Browse, the filters and the stores'
//   picker; its products stay on sale) or deleted once empty: its products are
//   first moved to another category, as they are (no second review).
// - A brand deleted moves its products to another brand or to none. A brand a
//   store typed waits, PENDING, until Saba saves it or approves its product.
// - A banner opens a product, a store, a category or nothing. Home leaves it
//   off while that is gone, and Saba's list says so.
// Each change locks the category or brand first, then its products.

const TAG = 'Admin: catalogue'

/** SQL: banner `b`'s link still opens something shoppers can see; true without a link. */
export const BANNER_LINK_LIVE = `CASE b.link_type
    WHEN 'PRODUCT' THEN EXISTS (SELECT 1 FROM products p JOIN stores s ON s.id = p.store_id WHERE p.id = b.link_id AND ${LISTED})
    WHEN 'STORE' THEN EXISTS (SELECT 1 FROM stores s WHERE s.id = b.link_id AND s.status = 'APPROVED')
    WHEN 'CATEGORY' THEN EXISTS (SELECT 1 FROM categories c LEFT JOIN categories pc ON pc.id = c.parent_id
                                  WHERE c.id = b.link_id AND c.deleted_at IS NULL AND c.is_hidden = 0 AND COALESCE(pc.is_hidden, 0) = 0)
    ELSE TRUE END`

const AdminCategory = z
  .object({
    id: z.string(),
    name: z.string(),
    nameAr: z.string(),
    imageUrl: z.string().nullable(),
    parentId: z.string().nullable(),
    hidden: z.boolean(),
    /** Its own products, deleted ones left out (sub-categories count theirs). */
    productCount: z.number(),
    get children(): z.ZodArray<typeof AdminCategory> {
      return z.array(AdminCategory)
    },
  })
  .meta({ id: 'AdminCategory' })
type AdminCategory = z.infer<typeof AdminCategory>

const CategoryInput = z.object({
  name: requiredText(60),
  nameAr: requiredText(60),
  /** A top-level category's id, or null for a top-level one: two levels only. */
  parentId: z.string().nullable(),
  /** An upload's url (POST /media/upload), or null for none. */
  imageUrl: z.string().max(1000).nullable(),
})

const LinkType = z.enum(['PRODUCT', 'STORE', 'CATEGORY'])

const AdminBanner = z
  .object({
    id: z.string(),
    imageUrl: z.string().nullable(),
    titleEn: z.string().nullable(),
    titleAr: z.string().nullable(),
    subtitleEn: z.string().nullable(),
    subtitleAr: z.string().nullable(),
    /** What a tap opens, with its name as Saba reads it; null for nothing. */
    link: z.object({ type: LinkType, id: z.string(), name: z.string().nullable() }).nullable(),
    isActive: z.boolean(),
    /** Its link opens nothing now (removed, hidden, suspended): Home leaves it off. */
    linkBroken: z.boolean(),
  })
  .meta({ id: 'AdminBanner' })

const BannerInput = z.object({
  /** An upload's url (POST /media/upload). */
  imageUrl: z.string().trim().min(1, { error: 'field.required' }).max(1000),
  // Words are optional, each in both languages or neither.
  titleEn: optionalText(120),
  titleAr: optionalText(120),
  subtitleEn: optionalText(120),
  subtitleAr: optionalText(120),
  link: z.object({ type: LinkType, id: z.string() }).nullable(),
  isActive: z.boolean(),
})
type BannerInput = z.infer<typeof BannerInput>

interface BannerRow {
  id: number
  image_url: string | null
  title_en: string | null
  title_ar: string | null
  subtitle_en: string | null
  subtitle_ar: string | null
  link_type: z.infer<typeof LinkType> | null
  link_id: number | null
  is_active: number
  live: number
  link_name: string | null
}

const BANNER_SELECT = `
  SELECT b.id, b.image_url, b.title_en, b.title_ar, b.subtitle_en, b.subtitle_ar, b.link_type, b.link_id, b.is_active,
         ${BANNER_LINK_LIVE} AS live,
         CASE b.link_type
           WHEN 'PRODUCT' THEN (SELECT COALESCE(p.name_en, p.name_ar) FROM products p WHERE p.id = b.link_id)
           WHEN 'STORE' THEN (SELECT s.store_name FROM stores s WHERE s.id = b.link_id)
           WHEN 'CATEGORY' THEN (SELECT c.name FROM categories c WHERE c.id = b.link_id) END AS link_name
    FROM home_banners b`

const BrandStatus = z.enum(['APPROVED', 'PENDING'])

const AdminBrand = z
  .object({
    id: z.string(),
    name: z.string(),
    nameAr: z.string().nullable(),
    /** PENDING: typed by a store, not checked by Saba yet. */
    status: BrandStatus,
    /** Its products, deleted ones left out. */
    productCount: z.number(),
  })
  .meta({ id: 'AdminBrand' })
type AdminBrand = z.infer<typeof AdminBrand>

const BrandInput = z.object({ name: requiredText(60), nameAr: requiredText(60) })

interface BrandRow {
  id: number
  name: string
  name_ar: string | null
  status: AdminBrand['status']
  n: number
}

const BRAND_SELECT = `
  SELECT b.id, b.name, b.name_ar, b.status, (SELECT COUNT(*) FROM products p WHERE p.brand_id = b.id AND p.deleted_at IS NULL) AS n
    FROM brands b`

const brandOf = (row: BrandRow): AdminBrand => ({
  id: String(row.id),
  name: row.name,
  nameAr: row.name_ar,
  status: row.status,
  productCount: Number(row.n),
})

/** A new order for one list: every id on it, each once; otherwise the page is out of date. */
const Order = z.array(z.string()).max(500)

export function adminCatalogRoutes(api: Api, ctx: Context): void {
  const { pool } = ctx
  const url = (req: Request, key: string | null) => (key === null ? null : urlOf(req, ctx.config.mediaBaseUrl, key))

  /** [imageUrl]'s storage key: an admin's own upload, or the picture the row already has ([current]). */
  async function imageKey(db: Pool | Connection, imageUrl: string | null, current: string | null, field: string): Promise<string | null> {
    if (imageUrl === null) return null
    const key = keyOf(imageUrl, ctx.config.mediaBaseUrl)
    if (key !== null && key === current) return key
    const uploaded =
      key !== null &&
      (await one(
        db,
        "SELECT m.id FROM media_files m JOIN users u ON u.id = m.owner_user_id WHERE m.storage_key = ? AND m.deleted_at IS NULL AND u.role = 'ADMIN'",
        [key],
      ))
    if (!uploaded) throw fieldError(field, 'media.notUploaded')
    return key
  }

  async function audit(conn: Connection, req: Request, action: string, type: string, id: number | string, details: object | null = null) {
    await exec(conn, 'INSERT INTO admin_actions (admin_user_id, action, entity_type, entity_id, details, ip) VALUES (?, ?, ?, ?, ?, ?)', [
      me(req).id,
      action,
      type,
      String(id),
      details === null ? null : JSON.stringify(details),
      req.ip ?? null,
    ])
  }

  /** Refused unless [ids] is every one of [current], each once. */
  function sameList(current: number[], ids: string[]): void {
    const wanted = new Set(ids)
    if (wanted.size !== ids.length || ids.length !== current.length || current.some((id) => !wanted.has(String(id)))) {
      throw new AppError(409, 'CONFLICT_ERROR', 'admin.listChanged')
    }
  }

  // ------------------------------------------------------------ categories ---

  async function categories(req: Request): Promise<AdminCategory[]> {
    const found = await rows<{
      id: number
      parent_id: number | null
      name: string
      name_ar: string
      image_url: string | null
      is_hidden: number
      n: number
    }>(
      pool,
      `SELECT c.id, c.parent_id, c.name, c.name_ar, c.image_url, c.is_hidden,
              (SELECT COUNT(*) FROM products p WHERE p.category_id = c.id AND p.deleted_at IS NULL) AS n
         FROM categories c WHERE c.deleted_at IS NULL ORDER BY c.position, c.id`,
    )
    const out = (row: (typeof found)[number]): AdminCategory => ({
      id: String(row.id),
      name: row.name,
      nameAr: row.name_ar,
      imageUrl: url(req, row.image_url),
      parentId: row.parent_id === null ? null : String(row.parent_id),
      hidden: row.is_hidden === 1,
      productCount: Number(row.n),
      children: found.filter((child) => child.parent_id === row.id).map(out),
    })
    return found.filter((row) => row.parent_id === null).map(out)
  }

  async function categoryOf(req: Request, id: number): Promise<AdminCategory> {
    const tree = await categories(req)
    return [...tree, ...tree.flatMap((category) => category.children)].find((category) => category.id === String(id))!
  }

  /** [text] as a parent: a live top-level category other than [self] (two levels only). */
  async function parentOf(conn: Connection, text: string | null, self: number | null): Promise<number | null> {
    if (text === null) return null
    const id = /^\d{1,15}$/.test(text) ? Number(text) : 0
    const parent = await one<{ parent_id: number | null }>(conn, 'SELECT parent_id FROM categories WHERE id = ? AND deleted_at IS NULL FOR SHARE', [id])
    if (!parent || id === self) throw fieldError('parentId', 'field.invalid')
    if (parent.parent_id !== null) throw fieldError('parentId', 'category.twoLevels')
    return id
  }

  /** Refused when another live category on [parentId]'s level has either name (ignoring case and accents). */
  async function categoryNamesFree(conn: Connection, parentId: number | null, name: string, nameAr: string, self: number | null) {
    const taken = await one<{ en: number }>(
      conn,
      'SELECT name = ? AS en FROM categories WHERE deleted_at IS NULL AND parent_id <=> ? AND id <> ? AND (name = ? OR name_ar = ?) LIMIT 1',
      [name, parentId, self ?? 0, name, nameAr],
    )
    if (taken) throw fieldError(taken.en ? 'name' : 'nameAr', 'category.nameTaken')
  }

  /** The place after the last on [parentId]'s level. */
  async function lastPlace(conn: Connection, parentId: number | null): Promise<number> {
    const row = await one<{ n: number | null }>(conn, 'SELECT MAX(position) AS n FROM categories WHERE parent_id <=> ? AND deleted_at IS NULL', [parentId])
    return Number(row?.n ?? 0) + 1
  }

  route(api, {
    method: 'get',
    path: '/admin/categories',
    tag: TAG,
    summary: 'Every category and sub-category in their order, both names, hidden ones too, their products counted',
    who: ['ADMIN'],
    response: z.array(AdminCategory),
    handle: ({ req }) => categories(req),
  })

  route(api, {
    method: 'post',
    path: '/admin/categories',
    tag: TAG,
    summary: 'A new category, last on its level; shoppers see it and stores can pick it at once',
    who: ['ADMIN'],
    body: CategoryInput,
    response: AdminCategory,
    async handle({ req, body }) {
      const id = await withTransaction(pool, async (conn) => {
        const parentId = await parentOf(conn, body.parentId, null)
        await categoryNamesFree(conn, parentId, body.name, body.nameAr, null)
        const image = await imageKey(conn, body.imageUrl, null, 'imageUrl')
        const inserted = await exec(conn, 'INSERT INTO categories (parent_id, name, name_ar, image_url, position) VALUES (?, ?, ?, ?, ?)', [
          parentId,
          body.name,
          body.nameAr,
          image,
          await lastPlace(conn, parentId),
        ])
        await audit(conn, req, 'CATEGORY_CREATE', 'CATEGORY', inserted.insertId)
        return inserted.insertId
      })
      return categoryOf(req, id)
    },
  })

  route(api, {
    method: 'patch',
    path: '/admin/categories/:id',
    tag: TAG,
    summary: 'Rename, move to another level (last there), change the picture, hide or show; what it leaves out stays',
    who: ['ADMIN'],
    params: IdParams,
    body: CategoryInput.partial().extend({ hidden: z.boolean().optional() }),
    response: AdminCategory,
    async handle({ req, params, body }) {
      const id = idOf(params.id)
      await withTransaction(pool, async (conn) => {
        const row = await one<{ parent_id: number | null; name: string; name_ar: string; image_url: string | null; is_hidden: number; position: number }>(
          conn,
          'SELECT parent_id, name, name_ar, image_url, is_hidden, position FROM categories WHERE id = ? AND deleted_at IS NULL FOR UPDATE',
          [id],
        )
        if (!row) throw notFound()
        const parentId = body.parentId === undefined ? row.parent_id : await parentOf(conn, body.parentId, id)
        const moved = parentId !== row.parent_id
        // Two levels: a category with sub-categories stays on top.
        if (moved && parentId !== null && (await one(conn, 'SELECT id FROM categories WHERE parent_id = ? AND deleted_at IS NULL LIMIT 1', [id]))) {
          throw fieldError('parentId', 'category.twoLevels')
        }
        const name = body.name ?? row.name
        const nameAr = body.nameAr ?? row.name_ar
        await categoryNamesFree(conn, parentId, name, nameAr, id)
        const image = body.imageUrl === undefined ? row.image_url : await imageKey(conn, body.imageUrl, row.image_url, 'imageUrl')
        const hidden = body.hidden ?? row.is_hidden === 1
        await exec(conn, 'UPDATE categories SET parent_id = ?, name = ?, name_ar = ?, image_url = ?, is_hidden = ?, position = ? WHERE id = ?', [
          parentId,
          name,
          nameAr,
          image,
          hidden,
          moved ? await lastPlace(conn, parentId) : row.position,
          id,
        ])
        const renamed = name !== row.name || nameAr !== row.name_ar
        // Products are found by their category's and its parent's names: its own and its sub-categories'.
        if (moved || renamed) await refreshSearchText(conn, 'c.id = ? OR c.parent_id = ?', [id, id])
        if (hidden !== (row.is_hidden === 1)) await audit(conn, req, hidden ? 'CATEGORY_HIDE' : 'CATEGORY_SHOW', 'CATEGORY', id)
        if (moved || renamed || image !== row.image_url) await audit(conn, req, 'CATEGORY_EDIT', 'CATEGORY', id)
      })
      return categoryOf(req, id)
    },
  })

  route(api, {
    method: 'post',
    path: '/admin/categories/order',
    tag: TAG,
    summary: "One level's new order, first to last: every category on it (parentId null for the top level)",
    who: ['ADMIN'],
    body: z.object({ parentId: z.string().nullable(), ids: Order }),
    response: z.array(AdminCategory),
    async handle({ req, body }) {
      await withTransaction(pool, async (conn) => {
        const parentId = body.parentId === null ? null : /^\d{1,15}$/.test(body.parentId) ? Number(body.parentId) : 0
        const level = await rows<{ id: number }>(conn, 'SELECT id FROM categories WHERE parent_id <=> ? AND deleted_at IS NULL FOR UPDATE', [parentId])
        sameList(
          level.map((row) => row.id),
          body.ids,
        )
        for (const [index, id] of body.ids.entries()) await exec(conn, 'UPDATE categories SET position = ? WHERE id = ?', [index + 1, Number(id)])
        await audit(conn, req, 'CATEGORY_ORDER', 'CATEGORY', parentId ?? 'TOP')
      })
      return categories(req)
    },
  })

  route(api, {
    method: 'delete',
    path: '/admin/categories/:id',
    tag: TAG,
    summary: 'Delete a category with no sub-categories; its products first move to moveTo, as they are (409 without it)',
    who: ['ADMIN'],
    params: IdParams,
    query: z.object({ moveTo: z.string().optional() }),
    response: z.object({ moved: z.number() }),
    handle: ({ req, params, query }) =>
      withTransaction(pool, async (conn) => {
        const id = idOf(params.id)
        if (!(await one(conn, 'SELECT id FROM categories WHERE id = ? AND deleted_at IS NULL FOR UPDATE', [id]))) throw notFound()
        if (await one(conn, 'SELECT id FROM categories WHERE parent_id = ? AND deleted_at IS NULL LIMIT 1', [id])) {
          throw new AppError(409, 'CONFLICT_ERROR', 'category.hasChildren')
        }
        const count = Number((await one<{ n: number }>(conn, 'SELECT COUNT(*) AS n FROM products WHERE category_id = ? AND deleted_at IS NULL', [id]))!.n)
        let target: number | null = null
        if (count > 0) {
          if (query.moveTo === undefined) throw new AppError(409, 'CONFLICT_ERROR', 'category.hasProducts', { products: count })
          target = /^\d{1,15}$/.test(query.moveTo) ? Number(query.moveTo) : 0
          if (target === id || !(await one(conn, 'SELECT id FROM categories WHERE id = ? AND deleted_at IS NULL FOR SHARE', [target]))) {
            throw fieldError('moveTo', 'field.invalid')
          }
          // As they are: the same status (no second review), and their updated_at stays.
          await exec(conn, 'UPDATE products SET category_id = ?, updated_at = updated_at WHERE category_id = ? AND deleted_at IS NULL', [target, id])
          await refreshSearchText(conn, 'p.category_id = ?', [target])
        }
        // The row stays, deleted, for the deleted products that still name it.
        await exec(conn, 'UPDATE categories SET deleted_at = NOW(3) WHERE id = ?', [id])
        await audit(conn, req, 'CATEGORY_DELETE', 'CATEGORY', id, target === null ? null : { movedTo: String(target), products: count })
        return { moved: count }
      }),
  })

  // --------------------------------------------------------------- banners ---

  const bannerOf = (req: Request, row: BannerRow): z.infer<typeof AdminBanner> => ({
    id: String(row.id),
    imageUrl: url(req, row.image_url),
    titleEn: row.title_en,
    titleAr: row.title_ar,
    subtitleEn: row.subtitle_en,
    subtitleAr: row.subtitle_ar,
    link: row.link_type === null ? null : { type: row.link_type, id: String(row.link_id), name: row.link_name },
    isActive: row.is_active === 1,
    linkBroken: Number(row.live) !== 1,
  })

  const bannerById = async (req: Request, id: number) => bannerOf(req, (await one<BannerRow>(pool, `${BANNER_SELECT} WHERE b.id = ?`, [id]))!)

  /** A save's banner, checked: an admin's picture, words in both languages or neither, a link that opens something now. */
  async function bannerValues(conn: Connection, body: BannerInput, current: string | null) {
    for (const [en, ar] of [
      ['titleEn', 'titleAr'],
      ['subtitleEn', 'subtitleAr'],
    ] as const) {
      if ((body[en] === null) !== (body[ar] === null)) throw fieldError(body[en] === null ? en : ar, 'field.required')
    }
    const image = await imageKey(conn, body.imageUrl, current, 'imageUrl')
    if (body.link === null) return { image, linkType: null, linkId: null }
    const linkId = /^\d{1,15}$/.test(body.link.id) ? Number(body.link.id) : 0
    const found = await one<{ live: number }>(conn, `SELECT ${BANNER_LINK_LIVE} AS live FROM (SELECT ? AS link_type, ? AS link_id) b`, [
      body.link.type,
      linkId,
    ])
    if (Number(found?.live) !== 1) throw fieldError('link', 'banner.linkGone')
    return { image, linkType: body.link.type, linkId }
  }

  route(api, {
    method: 'get',
    path: '/admin/banners',
    tag: TAG,
    summary: "Home's banners in their order, off ones too, each saying whether its link still opens something",
    who: ['ADMIN'],
    response: z.array(AdminBanner),
    handle: async ({ req }) => (await rows<BannerRow>(pool, `${BANNER_SELECT} ORDER BY b.position, b.id`)).map((row) => bannerOf(req, row)),
  })

  route(api, {
    method: 'post',
    path: '/admin/banners',
    tag: TAG,
    summary: 'A new banner, last on Home',
    who: ['ADMIN'],
    body: BannerInput,
    response: AdminBanner,
    async handle({ req, body }) {
      const id = await withTransaction(pool, async (conn) => {
        const values = await bannerValues(conn, body, null)
        const last = await one<{ n: number | null }>(conn, 'SELECT MAX(position) AS n FROM home_banners FOR UPDATE')
        const inserted = await exec(
          conn,
          `INSERT INTO home_banners (position, image_url, title_en, title_ar, subtitle_en, subtitle_ar, link_type, link_id, is_active)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          [Number(last?.n ?? 0) + 1, values.image, body.titleEn, body.titleAr, body.subtitleEn, body.subtitleAr, values.linkType, values.linkId, body.isActive],
        )
        await audit(conn, req, 'BANNER_CREATE', 'BANNER', inserted.insertId)
        return inserted.insertId
      })
      return bannerById(req, id)
    },
  })

  route(api, {
    method: 'put',
    path: '/admin/banners/:id',
    tag: TAG,
    summary: 'Change a banner: its picture, words, link and on or off; its place stays',
    who: ['ADMIN'],
    params: IdParams,
    body: BannerInput,
    response: AdminBanner,
    async handle({ req, params, body }) {
      const id = idOf(params.id)
      await withTransaction(pool, async (conn) => {
        const row = await one<{ image_url: string | null }>(conn, 'SELECT image_url FROM home_banners WHERE id = ? FOR UPDATE', [id])
        if (!row) throw notFound()
        const values = await bannerValues(conn, body, row.image_url)
        await exec(
          conn,
          `UPDATE home_banners SET image_url = ?, title_en = ?, title_ar = ?, subtitle_en = ?, subtitle_ar = ?, link_type = ?, link_id = ?, is_active = ?
            WHERE id = ?`,
          [values.image, body.titleEn, body.titleAr, body.subtitleEn, body.subtitleAr, values.linkType, values.linkId, body.isActive, id],
        )
        await audit(conn, req, 'BANNER_EDIT', 'BANNER', id)
      })
      return bannerById(req, id)
    },
  })

  route(api, {
    method: 'post',
    path: '/admin/banners/order',
    tag: TAG,
    summary: "Home's new banner order, first to last: every banner",
    who: ['ADMIN'],
    body: z.object({ ids: Order }),
    response: z.array(AdminBanner),
    async handle({ req, body }) {
      await withTransaction(pool, async (conn) => {
        const all = await rows<{ id: number }>(conn, 'SELECT id FROM home_banners FOR UPDATE')
        sameList(
          all.map((row) => row.id),
          body.ids,
        )
        for (const [index, id] of body.ids.entries()) await exec(conn, 'UPDATE home_banners SET position = ? WHERE id = ?', [index + 1, Number(id)])
        await audit(conn, req, 'BANNER_ORDER', 'BANNER', 'ALL')
      })
      return (await rows<BannerRow>(pool, `${BANNER_SELECT} ORDER BY b.position, b.id`)).map((row) => bannerOf(req, row))
    },
  })

  route(api, {
    method: 'delete',
    path: '/admin/banners/:id',
    tag: TAG,
    summary: 'Remove a banner from Home',
    who: ['ADMIN'],
    params: IdParams,
    response: z.object({}),
    handle: ({ req, params }) =>
      withTransaction(pool, async (conn) => {
        const id = idOf(params.id)
        const gone = await exec(conn, 'DELETE FROM home_banners WHERE id = ?', [id])
        if (gone.affectedRows === 0) throw notFound()
        await audit(conn, req, 'BANNER_DELETE', 'BANNER', id)
        return {}
      }),
  })

  // ---------------------------------------------------------------- brands ---

  const brandById = async (id: number) => brandOf((await one<BrandRow>(pool, `${BRAND_SELECT} WHERE b.id = ?`, [id]))!)

  /** Refused when another brand has either name in either language (a typed name finds its brand by both). */
  async function brandNamesFree(conn: Connection, name: string, nameAr: string, self: number | null) {
    const taken = await one<{ en: number }>(
      conn,
      'SELECT (name = ? OR name_ar = ?) AS en FROM brands WHERE id <> ? AND (name IN (?, ?) OR name_ar IN (?, ?)) LIMIT 1',
      [name, name, self ?? 0, name, nameAr, name, nameAr],
    )
    if (taken) throw fieldError(taken.en ? 'name' : 'nameAr', 'brand.nameTaken')
  }

  route(api, {
    method: 'get',
    path: '/admin/brands',
    tag: TAG,
    summary: 'Brands: new ones (typed by stores) first, then by name; counts per status; a page',
    who: ['ADMIN'],
    query: z.object({ q: z.string().max(100).optional(), status: BrandStatus.optional(), ...ListQuery }),
    response: z.object({ items: z.array(AdminBrand), counts: z.record(z.string(), z.number()) }),
    async handle({ query }) {
      const q = query.q?.trim()
      const search = q ? 'b.name LIKE ? OR b.name_ar LIKE ?' : 'TRUE'
      const params = q ? [likeTyped(q), likeTyped(q)] : []
      const counts: Record<string, number> = { all: 0 }
      for (const row of await rows<{ status: string; n: number }>(pool, `SELECT b.status, COUNT(*) AS n FROM brands b WHERE ${search} GROUP BY b.status`, params)) {
        counts[row.status] = Number(row.n)
        counts.all! += Number(row.n)
      }
      const found = await rows<BrandRow>(
        pool,
        `${BRAND_SELECT} WHERE (${search})${query.status ? ' AND b.status = ?' : ''} ORDER BY b.status = 'PENDING' DESC, b.name, b.id${pageSql(query)}`,
        query.status ? [...params, query.status] : params,
      )
      return paged({ items: found.map(brandOf), counts }, query, query.status ? (counts[query.status] ?? 0) : counts.all!)
    },
  })

  route(api, {
    method: 'post',
    path: '/admin/brands',
    tag: TAG,
    summary: 'A new brand in both languages; stores can pick it at once',
    who: ['ADMIN'],
    body: BrandInput,
    response: AdminBrand,
    async handle({ req, body }) {
      const id = await withTransaction(pool, async (conn) => {
        await brandNamesFree(conn, body.name, body.nameAr, null)
        const inserted = await exec(conn, "INSERT INTO brands (name, name_ar, status) VALUES (?, ?, 'APPROVED')", [body.name, body.nameAr])
        await audit(conn, req, 'BRAND_CREATE', 'BRAND', inserted.insertId)
        return inserted.insertId
      })
      return brandById(id)
    },
  })

  route(api, {
    method: 'put',
    path: '/admin/brands/:id',
    tag: TAG,
    summary: 'Rename a brand in both languages; its products show the new name at once. Saved by Saba, a new one is checked',
    who: ['ADMIN'],
    params: IdParams,
    body: BrandInput,
    response: AdminBrand,
    async handle({ req, params, body }) {
      const id = idOf(params.id)
      await withTransaction(pool, async (conn) => {
        const row = await one<{ status: AdminBrand['status'] }>(conn, 'SELECT status FROM brands WHERE id = ? FOR UPDATE', [id])
        if (!row) throw notFound()
        await brandNamesFree(conn, body.name, body.nameAr, id)
        await exec(conn, "UPDATE brands SET name = ?, name_ar = ?, status = 'APPROVED' WHERE id = ?", [body.name, body.nameAr, id])
        await audit(conn, req, row.status === 'PENDING' ? 'BRAND_APPROVE' : 'BRAND_EDIT', 'BRAND', id)
      })
      return brandById(id)
    },
  })

  route(api, {
    method: 'delete',
    path: '/admin/brands/:id',
    tag: TAG,
    summary: 'Delete a brand; its products move to moveTo (a checked brand) or to none (moveTo=none), as they are (409 without it)',
    who: ['ADMIN'],
    params: IdParams,
    query: z.object({ moveTo: z.string().optional() }),
    response: z.object({ moved: z.number() }),
    handle: ({ req, params, query }) =>
      withTransaction(pool, async (conn) => {
        const id = idOf(params.id)
        if (!(await one(conn, 'SELECT id FROM brands WHERE id = ? FOR UPDATE', [id]))) throw notFound()
        const count = Number((await one<{ n: number }>(conn, 'SELECT COUNT(*) AS n FROM products WHERE brand_id = ? AND deleted_at IS NULL', [id]))!.n)
        if (count > 0 && query.moveTo === undefined) throw new AppError(409, 'CONFLICT_ERROR', 'brand.hasProducts', { products: count })
        let target: number | null = null
        if (query.moveTo !== undefined && query.moveTo !== 'none') {
          target = /^\d{1,15}$/.test(query.moveTo) ? Number(query.moveTo) : 0
          if (target === id || !(await one(conn, "SELECT id FROM brands WHERE id = ? AND status = 'APPROVED' FOR SHARE", [target]))) {
            throw fieldError('moveTo', 'field.invalid')
          }
        }
        // Deleted products too (the key needs it), as they are: no second review, their updated_at stays.
        await exec(conn, 'UPDATE products SET brand_id = ?, updated_at = updated_at WHERE brand_id = ?', [target, id])
        await exec(conn, 'DELETE FROM brands WHERE id = ?', [id])
        await audit(conn, req, 'BRAND_DELETE', 'BRAND', id, count > 0 ? { movedTo: target === null ? 'none' : String(target), products: count } : null)
        return { moved: count }
      }),
  })
}

function idOf(text: string): number {
  if (!/^\d{1,15}$/.test(text)) throw notFound()
  return Number(text)
}

function notFound(): AppError {
  return new AppError(404, 'NOT_FOUND_ERROR', 'error.notFound')
}

function fieldError(field: string, key: MessageKey, params?: MessageParams): AppError {
  return new AppError(422, 'VALIDATION_ERROR', key, params, { [field]: { key, params } })
}
