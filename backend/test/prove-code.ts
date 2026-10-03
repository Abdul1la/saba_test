// npx tsx test/prove-code.ts accounts
// For every rule a test file guards: break just that rule in the source, run
// the file, and expect it to fail. A test that still passes proves nothing.
// Each file is put back exactly as it was, whatever happens.
import { spawnSync } from 'node:child_process'
import { existsSync, readFileSync, rmSync, writeFileSync } from 'node:fs'

interface Mutation {
  rule: string
  file: string
  /** Each `from` must appear exactly once in the file. */
  edits: [from: string, to: string][]
  /** Only the tests whose names match this run (--test-name-pattern); all of them when missing. */
  tests?: string
}

const suites: Record<string, Mutation[]> = {
  accounts: [
    { rule: '964… and 00964… are the same number', file: 'src/lib/phone.ts', edits: [["else if (digits.startsWith('964')) digits = digits.slice(3)", '']] },
    { rule: 'Arabic digits are digits', file: 'src/lib/phone.ts', edits: [['const unit = digit.charCodeAt(0)', 'return digit; const unit = 0']] },
    { rule: 'a sign-up code is refused for a number with an account', file: 'src/modules/auth.ts', edits: [["if (purpose === 'SIGN_UP' && account)", "if (purpose === 'SIGN_UP' && !account && false)"]] },
    { rule: 'a reset code is refused for a number without one', file: 'src/modules/auth.ts', edits: [["if (purpose === 'PASSWORD_RESET' && !account) {", 'if (false) {']] },
    { rule: 'the 60-second resend wait', file: 'src/modules/auth.ts', edits: [['recent.since < OTP.resendSeconds', 'recent.since < 0']] },
    { rule: '5 codes a number an hour', file: 'src/modules/auth.ts', edits: [['>= OTP.perPhonePerHour', '>= 1000']] },
    { rule: 'only a sign-up code proves a number for sign-up', file: 'src/modules/auth.ts', edits: [["body.phone, ['SIGN_UP'], body.code", "body.phone, ['SIGN_UP', 'OTHER'], body.code"]] },
    { rule: 'the fifth wrong try uses the code up', file: 'src/modules/auth.ts', edits: [["if (row.attempts >= OTP.maxTries) return { ok: false, key: 'auth.codeTooManyTries' }", '']] },
    { rule: 'a code expires after 5 minutes', file: 'src/modules/auth.ts', edits: [['AND consumed_at IS NULL AND expires_at > NOW(3)', 'AND consumed_at IS NULL']] },
    { rule: "a proof is for its own number only", file: 'src/modules/auth.ts', edits: [['if (!proof || proof.phone !== body.phone) {', 'if (!proof) {']] },
    { rule: 'one proof makes one account', file: 'src/modules/auth.ts', edits: [['WHERE id = ? AND phone = ? AND verified_at IS NOT NULL AND consumed_at IS NULL', 'WHERE id = ? AND phone = ? AND verified_at IS NOT NULL']] },
    { rule: 'a token works only as its own kind', file: 'src/lib/tokens.ts', edits: [["return payload.typ === typ ? payload : null", 'return payload']] },
    { rule: 'only shoppers delete their account', file: 'src/modules/account.ts', edits: [["summary: \"Delete the shopper's account; refused while an order is open (Q9)\",\n    who: ['CUSTOMER'],", "summary: 'x',\n    who: 'signedIn',"]] },
    { rule: 'a suspended account is out at its next request', file: 'src/http/auth.ts', edits: [["account?.status !== 'ACTIVE'", '!account']] },
    { rule: 'a reused refresh token ends the whole sign-in', file: 'src/modules/auth.ts', edits: [['if (row.replaced_by_id !== null) await revokeFamily(conn, row.family_id)', '']] },
    { rule: "a suspended account can't refresh", file: 'src/modules/auth.ts', edits: [["if (account?.status !== 'ACTIVE') return null", 'if (!account) return null']] },
    { rule: 'an expired refresh token is refused', file: 'src/modules/auth.ts', edits: [['if (!row.live) return null', '']] },
    { rule: 'sign-out ends every token of the sign-in', file: 'src/modules/auth.ts', edits: [['if (row) await revokeFamily(pool, row.family_id)', "await exec(pool, 'UPDATE refresh_tokens SET revoked_at = NOW(3) WHERE token_hash = ?', [sha256(body.refreshToken)])"]] },
    { rule: "an admin's sign-in lasts 12 hours", file: 'src/modules/auth.ts', edits: [["user.role === 'ADMIN' ? REFRESH_TOKEN_SECONDS.admin", "user.role === 'NOBODY' ? REFRESH_TOKEN_SECONDS.admin"]] },
    { rule: 'a suspended account is refused at sign-in', file: 'src/modules/auth.ts', edits: [["if (account.status !== 'ACTIVE') throw new AppError(403", "if (false) throw new AppError(403"]] },
    { rule: '10 sign-in tries per 15 minutes', file: 'src/modules/auth.ts', edits: [['if (wait) throw tooManyTries(wait)', '']] },
    { rule: 'an unknown number is said on the phone field', file: 'src/modules/auth.ts', edits: [['if (!account && phone) {', 'if (false) {']] },
    { rule: 'codes off skips the code at sign-up only, never at reset', file: 'src/modules/auth.ts', tests: 'phone checks switched off', edits: [["if (purpose === 'SIGN_UP' && ctx.config.phoneVerification === 'off') {", "if (ctx.config.phoneVerification === 'off') {"]] },
    { rule: 'a sign-up without a code is kept unchecked', file: 'src/modules/auth.ts', tests: 'phone checks switched off', edits: [["!.purpose === 'SIGN_UP'", "!.purpose !== 'OTHER'"]] },
    { rule: 'codes back on: an unchecked account needs its code at sign-in', file: 'src/modules/auth.ts', tests: 'phone checks switched off', edits: [["if (!body.code) throw new AppError(403, 'PHONE_NOT_VERIFIED', 'auth.checkPhone')", "if (false) throw new AppError(403, 'PHONE_NOT_VERIFIED', 'auth.checkPhone')"]] },
    { rule: 'codes back on: an unchecked account is signed out at refresh', file: 'src/modules/auth.ts', tests: 'phone checks switched off', edits: [['if (mustCheckPhone(ctx, account)) return null', '']] },
    { rule: "a checked shopper's number is never freed", file: 'src/modules/admin-customers.ts', tests: 'phone checks switched off', edits: [["if (Number(held!.checked) === 1) throw new AppError(409, 'CONFLICT_ERROR', 'admin.numberChecked')", '']] },
    { rule: 'a reset signs every device out', file: 'src/modules/auth.ts', edits: [["        await exec(conn, 'UPDATE refresh_tokens SET revoked_at = NOW(3) WHERE user_id = ? AND revoked_at IS NULL', [\n          account.id,\n        ])\n", '']] },
    { rule: 'only a reset code resets a password', file: 'src/modules/auth.ts', edits: [["['PASSWORD_RESET'], body.token", "['PASSWORD_RESET', 'SIGN_UP', 'OTHER'], body.token"]] },
    { rule: 'a reset code works once', file: 'src/modules/auth.ts', edits: [['SET verified_at = NOW(3), consumed_at = NOW(3) WHERE id = ?', 'SET verified_at = NOW(3) WHERE id = ?']] },
    { rule: 'no sign-up as an admin', file: 'src/modules/auth.ts', edits: [["    governorate,\n  }\n\n  route(api, {\n    method: 'post',\n    path: '/auth/register/customer',", "    governorate,\n    role: z.string().optional(),\n  }\n\n  route(api, {\n    method: 'post',\n    path: '/auth/register/customer',"], ["handle: ({ req, body }) => register(ctx, req, 'CUSTOMER', body),", "handle: ({ req, body }) => register(ctx, req, (body.role as 'CUSTOMER') ?? 'CUSTOMER', body),"]] },
    { rule: 'store names compare without case or extra spaces', file: 'src/modules/stores.ts', edits: [["return storeName.trim().toLowerCase().replace(/\\s+/g, ' ')", 'return storeName']] },
    { rule: 'an email is kept lower-case', file: 'src/http/inputs.ts', edits: [['  .toLowerCase()\n  .max(254)', '  .max(254)']] },
    { rule: 'no account deletion with an open order (Q9)', file: 'src/modules/account.ts', edits: [['if (open.length > 0) {', 'if (false) {']] },
    { rule: 'a deleted account frees its number', file: 'src/modules/account.ts', edits: [["SET status = 'DELETED', phone = NULL, email = NULL", "SET status = 'DELETED', email = NULL"]] },
    { rule: 'a deleted account keeps no live token', file: 'src/modules/account.ts', edits: [["        await exec(conn, 'UPDATE refresh_tokens SET revoked_at = NOW(3) WHERE user_id = ? AND revoked_at IS NULL', [id])\n", '']] },
    { rule: "another shopper's address is not found (replace, default)", file: 'src/modules/account.ts', edits: [['${ADDRESS_SELECT} WHERE id = ? AND user_id = ?', '${ADDRESS_SELECT} WHERE id = ? AND (user_id = ? OR TRUE)']] },
    { rule: "another shopper's address is not found (delete)", file: 'src/modules/account.ts', edits: [["'DELETE FROM addresses WHERE id = ? AND user_id = ?'", "'DELETE FROM addresses WHERE id = ? AND (user_id = ? OR TRUE)'"]] },
    { rule: 'the first address is the default', file: 'src/modules/account.ts', edits: [['const isDefault = first || body.isDefault === true', 'const isDefault = body.isDefault === true']] },
    { rule: 'one default at a time', file: 'src/modules/account.ts', edits: [['if (isDefault) await clearDefault(conn, userId)\n        const inserted', 'const inserted']] },
  ],
  sms: [
    { rule: 'OTPIQ gets the number without +', file: 'src/lib/sms.ts', edits: [["phoneNumber: phone.replace(/^\\+/, ''),", 'phoneNumber: phone,']] },
    { rule: "OTPIQ's 429 means wait", file: 'src/lib/sms.ts', edits: [['if (response.status === 429) {', 'if (false) {']] },
    { rule: 'a code that could not be sent is withdrawn', file: 'src/modules/auth.ts', edits: [["        await exec(pool, 'DELETE FROM otp_challenges WHERE id = ?', [challenge.insertId])\n", '']] },
    { rule: 'a failed send is 503, not a silent success', file: 'src/modules/auth.ts', edits: [['        await ctx.sms(phone, sms)\n', '        await ctx.sms(phone, sms).catch(() => undefined)\n']] },
  ],
  fold: [
    { rule: 'أ إ آ ٱ fold to ا', file: 'src/lib/fold.ts', edits: [['      return 0x0627 // آ أ إ ٱ → ا', '      return c']] },
    { rule: 'ة folds to ه', file: 'src/lib/fold.ts', edits: [['      return 0x0647 // ة → ه', '      return c']] },
    { rule: 'ى ی ئ fold to ي', file: 'src/lib/fold.ts', edits: [['      return 0x064a // ى ی ئ → ي', '      return c']] },
    { rule: 'vowel marks and the tatweel are dropped', file: 'src/lib/fold.ts', edits: [['|| c === 0x0670 || c === 0x0640) return null', '|| c === 0x0670) return null']] },
    { rule: 'Arabic digits are 0-9', file: 'src/lib/fold.ts', edits: [['if (c >= 0x0660 && c <= 0x0669) return c - 0x0660 + 0x30', '']] },
    { rule: 'a leading ال is optional in a query word', file: 'src/lib/fold.ts', edits: [["word.length > 3 && word.startsWith('ال') ? word.slice(2) : word", 'word']] },
  ],
  pricing: [
    { rule: 'a sale is on only while its end is in the future', file: 'src/lib/pricing.ts', edits: [['product.sale_ends_at > now', 'product.sale_ends_at !== undefined']] },
    { rule: "during a sale each option comes down by the sale's amount", file: 'src/lib/pricing.ts', edits: [['return shown(optionPrice - saleOff(product, now), optionPrice)', 'return shown(optionPrice, optionPrice)']] },
    { rule: "a lasting markdown carries onto each option's original", file: 'src/lib/pricing.ts', edits: [['markdown === null ? null : optionPrice + markdown', 'null']] },
    { rule: 'low stock is 1 to 5', file: 'src/lib/pricing.ts', edits: [["stock <= 5 ? 'LOW_STOCK'", "stock <= 4 ? 'LOW_STOCK'"]] },
  ],
  catalog: [
    { rule: 'listed: approved only', file: 'src/modules/products.ts', edits: [["export const LISTED = `p.status = 'APPROVED' AND ", 'export const LISTED = `']] },
    { rule: "listed: the store's switch on", file: 'src/modules/products.ts', edits: [['AND p.is_active = 1 AND p.taken_down = 0 AND p.deleted_at IS NULL AND s.status', 'AND p.taken_down = 0 AND p.deleted_at IS NULL AND s.status']] },
    { rule: 'listed: not taken down', file: 'src/modules/products.ts', edits: [['AND p.taken_down = 0 AND p.deleted_at IS NULL AND s.status', 'AND p.deleted_at IS NULL AND s.status']] },
    { rule: 'listed: its store approved', file: 'src/modules/products.ts', edits: [["AND p.deleted_at IS NULL AND s.status = 'APPROVED'`", 'AND p.deleted_at IS NULL`']] },
    { rule: 'browsing: open stores only', file: 'src/modules/products.ts', edits: [['export const BROWSABLE = `${LISTED} AND s.is_open = 1`', 'export const BROWSABLE = `${LISTED}`']] },
    { rule: 'its own store opens a product that is not listed', file: 'src/modules/catalog.ts', edits: [['(loaded.row.listed !== 1 && !own)', 'loaded.row.listed !== 1']] },
    { rule: 'every stock change is in the ledger', file: 'src/modules/merchant-products.ts', edits: [["  await exec(conn, 'INSERT INTO stock_movements (sku_id, delta, reason, actor_user_id) VALUES (?, ?, ?, ?)', [\n    skuId,\n    to - from,\n    reason,\n    actor,\n  ])\n", '']] },
    { rule: 'a stock change is saved', file: 'src/modules/merchant-products.ts', edits: [["  await exec(conn, 'UPDATE product_skus SET stock = ? WHERE id = ?', [to, skuId])\n", '']] },
    { rule: 'an adjustment never goes below 0', file: 'src/modules/merchant-products.ts', edits: [['Math.max(0, sku.stock + body.quantity)', 'sku.stock + body.quantity']] },
    { rule: 'a product with options has no stock of its own to set', file: 'src/modules/merchant-products.ts', edits: [['if (!single || skus.length !== 1) throw', 'if (false) throw']] },
    { rule: 'options are matched by id', file: 'src/modules/merchant-products.ts', edits: [['String(sku.id) === variant.id && !kept.has(sku.id)', 'false']] },
    { rule: 'an option left out is marked deleted', file: 'src/modules/merchant-products.ts', edits: [["if (gone.length > 0) await exec(conn, 'UPDATE product_skus SET deleted_at = NOW(3) WHERE id IN (?)', [gone])", '']] },
    { rule: "a save during a sale adds the sale's discount back onto each option", file: 'src/modules/merchant-products.ts', edits: [['const optionPrice = variant.price == null ? base : variant.price + off', 'const optionPrice = variant.price == null ? base : variant.price']] },
    { rule: 'a save during a sale keeps the sale', file: 'src/modules/merchant-products.ts', edits: [['        if (saleIsOn(product, now)) {\n          base = body.originalPrice', '        if (false) {\n          base = body.originalPrice']] },
    { rule: 'a flash sale only on a listed product', file: 'src/modules/merchant-products.ts', edits: [["if (!listed) throw new AppError(409, 'CONFLICT_ERROR', 'product.notForSale')", '']] },
    { rule: 'a sale price below the normal price', file: 'src/modules/merchant-products.ts', edits: [["else if (sale >= normal) errors.salePrice", "else if (sale > normal) errors.salePrice"]] },
    { rule: 'no option below 250 in a sale', file: 'src/modules/merchant-products.ts', edits: [['cheapest.price - (normal - sale) < 250', 'cheapest.price - (normal - sale) < 0']] },
    { rule: 'a sale ends in the future', file: 'src/modules/merchant-products.ts', edits: [['|| ends <= new Date()) errors.saleEndsAt', ') errors.saleEndsAt']] },
    { rule: 'every product has its Arabic name', file: 'src/modules/merchant-products.ts', edits: [["throw fieldError('nameAr', 'product.nameAr')", "void fieldError('nameAr', 'product.nameAr')"]] },
    { rule: 'an original price above the price', file: 'src/modules/merchant-products.ts', edits: [["if (body.originalPrice <= body.price) throw fieldError('originalPrice', 'product.originalAbovePrice')", '']] },
    { rule: 'photos: its own uploads only', file: 'src/modules/merchant-products.ts', edits: [['        const allowed =\n          key !== null &&\n          ((await one', '        const allowed =\n          key !== null ||\n          ((await one']] },
    { rule: 'photos left out stay', file: 'src/modules/merchant-products.ts', edits: [['if (refs.images !== undefined) await saveImages(conn, product.id, refs.images)', 'await saveImages(conn, product.id, refs.images ?? [])']] },
    { rule: 'a description left out stays', file: 'src/modules/merchant-products.ts', edits: [['if (body.description != null) {', 'if (true) {']] },
    { rule: "the store's switch can't undo a takedown", file: 'src/modules/merchant-products.ts', edits: [["'UPDATE products SET is_active = ? WHERE id = ? AND taken_down = 0'", "'UPDATE products SET is_active = ? WHERE id = ?'"]] },
    { rule: 'submit only a draft or a rejected product', file: 'src/modules/merchant-products.ts', edits: [["WHERE id = ? AND status IN ('DRAFT', 'REJECTED')`", "WHERE id = ?`"]] },
    { rule: 'a deleted product leaves every wishlist', file: 'src/modules/merchant-products.ts', edits: [["        await exec(conn, 'DELETE FROM wishlist_items WHERE product_id = ?', [product.id])\n", '']] },
    { rule: "the shelf's low tab is 1 to 5", file: 'src/modules/merchant-products.ts', edits: [['stockOf(loaded) > 0 && stockOf(loaded) <= LOW_STOCK_AT_MOST', 'stockOf(loaded) <= LOW_STOCK_AT_MOST']] },
    { rule: 'search needs every word', file: 'src/modules/catalog.ts', edits: [['    for (const word of words) {\n      where.push', '    for (const word of words.slice(0, 1)) {\n      where.push']] },
    { rule: 'a name match before a category match', file: 'src/modules/catalog.ts', edits: [['const ranked = [...found.filter(named), ...found.filter((row) => !named(row))]', 'const ranked = [...found.filter((row) => !named(row)), ...found.filter(named)]']] },
    { rule: 'a category includes its sub-categories', file: 'src/modules/catalog.ts', edits: [["where.push('p.category_id IN (SELECT id FROM categories WHERE id = ? OR parent_id = ?)')", "where.push('p.category_id IN (SELECT id FROM categories WHERE id = ? OR id = ?)')"]] },
    { rule: 'in stock only', file: 'src/modules/catalog.ts', edits: [["if (query.inStock === 'true') where.push(IN_STOCK)", '']] },
    { rule: 'on sale only', file: 'src/modules/catalog.ts', edits: [["if (query.onSale === 'true') where.push(", "if (false) where.push("]] },
    { rule: 'deliverTo: only stores that deliver there', file: 'src/modules/catalog.ts', edits: [['JOIN store_delivery_governorates d ON d.store_id = s.id AND d.governorate = ?', 'JOIN store_delivery_governorates d ON d.store_id = s.id AND ? IS NOT NULL']] },
    { rule: 'a search counts once, on its first page, when it found something', file: 'src/modules/catalog.ts', edits: [['if (term && total > 0 && query.page === 1) {', 'if (term) {']] },
    { rule: "Home's flash sale: running sales only", file: 'src/modules/catalog.ts', edits: [['WHERE ${BROWSABLE} AND ${ON_SALE_NOW} AND ${IN_STOCK}', 'WHERE ${BROWSABLE} AND p.sale_price IS NOT NULL AND ${IN_STOCK}']] },
    { rule: "Home's rail: approved stores only", file: 'src/modules/catalog.ts', edits: [["WHERE s.status = 'APPROVED' ORDER BY f.position", 'ORDER BY f.position']] },
    { rule: 'the wishlist takes listed products only', file: 'src/modules/catalog.ts', edits: [["if (!listed) throw new AppError(404, 'NOT_FOUND_ERROR', 'product.notAvailable')", '']] },
    { rule: 'an admin reads both names', file: 'src/modules/catalog.ts', edits: [["const arabic = req.lang === 'ar' && user?.role !== 'ADMIN'", "const arabic = req.lang === 'ar'"]] },
    { rule: 'approving needs the Arabic name', file: 'src/modules/admin-products.ts', edits: [["throw new AppError(422, 'BUSINESS_RULE_ERROR', 'product.nameAr'", "if (false) throw new AppError(422, 'BUSINESS_RULE_ERROR', 'product.nameAr'"]] },
    { rule: 'an answer only from the right state', file: 'src/modules/admin-products.ts', edits: [['`UPDATE products SET ${step.set} WHERE id = ? AND ${step.when}`', '`UPDATE products SET ${step.set} WHERE id = ?`']] },
    { rule: 'the store is told of an answer', file: 'src/modules/admin-products.ts', edits: [['if (step.tell) {', 'if (false) {']] },
    { rule: 'an answer writes the audit row', file: 'src/modules/admin-products.ts', edits: [["[me(req).id, step.action, String(id), step.reason ?? null, req.ip ?? null],", "[me(req).id, step.action, '0', step.reason ?? null, req.ip ?? null],"]] },
    { rule: 'a taken-down product counts only as taken down', file: 'src/modules/admin-products.ts', edits: [["(row.taken_down === 1 ? 'TAKEN_DOWN' : row.status)", '(row.status)']] },
    { rule: 'the admin never sees drafts', file: 'src/modules/admin-products.ts', edits: [["WHERE p.status <> 'DRAFT' AND p.deleted_at IS NULL ${where}", 'WHERE p.deleted_at IS NULL ${where}']] },
    { rule: 'inShop says why not', file: 'src/modules/admin-products.ts', edits: [["        ? 'TAKEN_DOWN'\n", "        ? 'NOT_APPROVED'\n"]] },
  ],
  money: [
    { rule: 'a percentage rounds down to 250', file: 'src/lib/money.ts', edits: [['Number((BigInt(base) * BigInt(value)) / 25_000n) * 250', 'Math.round((base * value) / 25_000) * 250']] },
    { rule: 'a fixed amount takes at most the base', file: 'src/lib/money.ts', edits: [['return cashSteps(Math.min(value, base))', 'return cashSteps(value)']] },
    { rule: "a unit's paid price rounds down", file: 'src/lib/money.ts', edits: [['return Number((BigInt(unit) * BigInt(partSubtotal - partDiscount)) / (BigInt(partSubtotal) * 250n)) * 250', 'return Math.round((unit * (partSubtotal - partDiscount)) / (partSubtotal * 250)) * 250']] },
    { rule: 'cash steps round down', file: 'src/lib/money.ts', edits: [['return Math.floor(amount / 250) * 250', 'return Math.round(amount / 250) * 250']] },
    { rule: "a bill's month is Baghdad's", file: 'src/lib/money.ts', edits: [['Number(BAGHDAD_OFFSET.slice(0, 3)) * 3_600_000', '0']] },
    { rule: 'a bill takes the refunds off', file: 'src/lib/money.ts', edits: [['const base = sales - returned', 'const base = sales']] },
    { rule: 'refunds as big as the sales owe nothing', file: 'src/lib/money.ts', edits: [['const base = sales - returned\n  if (base <= 0) return 0\n', 'const base = sales - returned\n']] },
    { rule: 'a bill is to the nearest 250', file: 'src/lib/money.ts', edits: [['+ 12_500n) / 25_000n) * 250', ') / 25_000n) * 250']] },
  ],
  bills: [
    // bills.ts: each month's bill
    { rule: "a sale is the goods less the store's coupon", file: 'src/modules/bills.ts', tests: 'each month on its own', edits: [['SUM(subtotal - discount) AS sales', 'SUM(subtotal) AS sales']] },
    { rule: "a refund comes off its own month's bill", file: 'src/modules/bills.ts', tests: 'each month on its own', edits: [['const owed = billOwed(sales, returned, COMMISSION_PERCENT)', 'const owed = billOwed(sales, 0, COMMISSION_PERCENT)']] },
    { rule: 'the month under way is OPEN', file: 'src/modules/bills.ts', tests: 'each month on its own', edits: [["month === thisMonth ? 'OPEN' :", "false ? 'OPEN' :"]] },
    { rule: 'a closed month owing nothing is NONE', file: 'src/modules/bills.ts', tests: 'each month on its own', edits: [["owed === 0 ? 'NONE' : 'DUE'", "'DUE'"]] },
    { rule: 'a month marked paid is PAID', file: 'src/modules/bills.ts', tests: 'only a due month', edits: [["figures?.paidOn ? 'PAID' :", "false ? 'PAID' :"]] },
    { rule: 'this month is always on the bills', file: 'src/modules/bills.ts', tests: 'sold nothing has this month', edits: [['[...new Set([thisMonth, ...months.keys()])]', '[...new Set([...months.keys()])]']] },
    { rule: 'the paid day is noon in Baghdad', file: 'src/modules/bills.ts', tests: 'only a due month', edits: [['T12:00:00.000${BAGHDAD_OFFSET}', 'T00:00:00.000${BAGHDAD_OFFSET}']] },
    // what a closing store owes
    { rule: 'owed now counts this month so far', file: 'src/modules/bills.ts', tests: 'each month on its own', edits: [["bill.status === 'OPEN' || bill.status === 'DUE'", "bill.status === 'DUE'"]] },
    { rule: 'owed now counts every month due', file: 'src/modules/bills.ts', tests: 'each month on its own', edits: [["bill.status === 'OPEN' || bill.status === 'DUE'", "bill.status === 'OPEN'"]] },
    { rule: 'closing the store says what it owes', file: 'src/modules/stores.ts', tests: 'each month on its own', edits: [['owed: owedNow(await storeBills(pool, row.id)),', 'owed: 0,']] },
    // marking paid and not paid
    { rule: 'only a due month is marked paid', file: 'src/modules/bills.ts', tests: 'only a due month', edits: [["if (bill.status !== 'DUE') throw new AppError(409", "if (false) throw new AppError(409"]] },
    { rule: 'paid on a day after the month ended', file: 'src/modules/bills.ts', tests: 'only a due month', edits: [['day < addMonths(month, 1)', 'day < month']] },
    { rule: 'paid on a day not after today', file: 'src/modules/bills.ts', tests: 'only a due month', edits: [['|| day > today)', ')']] },
    { rule: 'the paid day is a real day', file: 'src/modules/bills.ts', tests: 'only a due month', edits: [['if (!real ||', 'if (false ||']] },
    { rule: 'a month is paid once, even at the same moment', file: 'src/modules/bills.ts', tests: 'only a due month', edits: [["if (duplicateKey(error) === 'uq_bill_payments_store_month') throw", 'if (false) throw']] },
    { rule: 'the payment keeps what the bill said', file: 'src/modules/bills.ts', tests: 'only a due month', edits: [['            bill.owed,\n            COMMISSION_PERCENT,\n', '            250,\n            COMMISSION_PERCENT,\n']] },
    { rule: 'marking paid writes the audit row', file: 'src/modules/bills.ts', tests: 'only a due month', edits: [["await audit(conn, req, 'BILL_PAID', store, month,", "void (conn, req, 'BILL_PAID', store, month,"]] },
    { rule: 'not paid only when it was paid', file: 'src/modules/bills.ts', tests: 'marked paid by mistake', edits: [["if (!paid) throw new AppError(409", "if (false) throw new AppError(409"]] },
    { rule: 'the payment is locked while it is undone', file: 'src/modules/bills.ts', tests: 'marked paid by mistake', edits: [['WHERE store_id = ? AND month = ? FOR UPDATE`', 'WHERE store_id = ? AND month = ?`']] },
    { rule: 'undoing a payment keeps what it said', file: 'src/modules/bills.ts', tests: 'marked paid by mistake', edits: [["await audit(conn, req, 'BILL_UNPAID', store, month,", "void (conn, req, 'BILL_UNPAID', store, month,"]] },
    // Finance
    { rule: 'still owed is what is due', file: 'src/modules/bills.ts', tests: 'one month:', edits: [["const stillOwedOf = (bill: Bill) => (bill.status === 'DUE' ? bill.owed : 0)", "const stillOwedOf = (bill: Bill) => (bill.status !== 'OPEN' ? bill.owed : 0)"]] },
    { rule: 'paid is what was marked paid', file: 'src/modules/bills.ts', tests: 'one month:', edits: [["const paidOf = (bill: Bill) => (bill.status === 'PAID' ? bill.owed : 0)", "const paidOf = (bill: Bill) => (bill.status !== 'OPEN' ? bill.owed : 0)"]] },
    { rule: 'the due filter: something still owed', file: 'src/modules/bills.ts', tests: 'one month:', edits: [["query.paid === 'DUE' ? row.stillOwed > 0", "query.paid === 'DUE' ? row.stillOwed >= 0"]] },
    { rule: 'every closed month: not this one', file: 'src/modules/bills.ts', tests: 'every closed month', edits: [["query.month === 'past' ? months.slice(1)", "query.month === 'past' ? months"]] },
    { rule: 'months added up are due while anything is', file: 'src/modules/bills.ts', tests: 'every closed month', edits: [["stillOwed > 0 ? 'DUE' : owed > 0 ? 'PAID' : 'NONE'", "owed > 0 ? 'PAID' : 'NONE'"]] },
    { rule: "this month is every store's bill now", file: 'src/modules/bills.ts', tests: 'every closed month', edits: [['const now = stores.map((store) => billFor(store, thisMonth))', 'const now = stores.map((store) => billFor(store, lastMonth))']] },
    { rule: 'last month: collected is what was paid', file: 'src/modules/bills.ts', tests: 'every closed month', edits: [['collected: add(before, paidOf)', 'collected: add(before, stillOwedOf)']] },
  ],
  buying: [
    // cart.ts: the one pricing function
    { rule: 'only a product for sale is charged', file: 'src/modules/cart.ts', tests: 'something run out', edits: [['const forSale = loaded.row.listed === 1 && store.approved && sku.deleted_at === null', 'const forSale = store.approved && sku.deleted_at === null']] },
    { rule: 'the subtotal counts only what can be bought', file: 'src/modules/cart.ts', tests: 'something run out', edits: [['if (priced.left > 0) part.subtotal += priced.lineTotal', 'part.subtotal += priced.lineTotal']] },
    { rule: 'a code no longer live takes nothing off', file: 'src/modules/cart.ts', tests: 'one use left', edits: [['if (applied?.live === 1) {', 'if (applied) {']] },
    { rule: "a code comes off its own store's things only", file: 'src/modules/cart.ts', tests: 'two stores: the code', edits: [['const base = part?.reach ? part.subtotal : 0', 'const base = parts.reduce((sum, p) => sum + (p.reach ? p.subtotal : 0), 0)']] },
    { rule: "only the code's store's part shows its discount", file: 'src/modules/cart.ts', tests: 'two stores: the code', edits: [['if (part) part.discount = discount', 'for (const p of parts) p.discount = discount']] },
    { rule: 'under its minimum a code takes nothing', file: 'src/modules/cart.ts', tests: 'under its minimum', edits: [['if (applied.min_order_amount === null || base >= applied.min_order_amount) {', 'if (true) {']] },
    { rule: 'a closed store brings nothing', file: 'src/modules/cart.ts', tests: "doesn't deliver there", edits: [['if (!store.approved || !store.open || !store.areas.has(city)) return null', 'if (!store.approved || !store.areas.has(city)) return null']] },
    { rule: 'a store brings only where it delivers', file: 'src/modules/cart.ts', tests: "doesn't deliver there", edits: [['if (!store.approved || !store.open || !store.areas.has(city)) return null', 'if (!store.approved || !store.open) return null']] },
    { rule: 'another city pays the outside fee', file: 'src/modules/cart.ts', tests: 'two stores: the code', edits: [['city === store.governorate ? [store.feeInside, store.timeInside] : [store.feeOutside, store.timeOutside]', '[store.feeInside, store.timeInside]']] },
    { rule: "a part that can't come is not in the total", file: 'src/modules/cart.ts', tests: "doesn't deliver there", edits: [['    if (!part.reach) continue\n    part.amountDue = part.subtotal - part.discount + part.reach.fee\n    subtotal += part.subtotal\n', '    subtotal += part.subtotal\n    if (!part.reach) continue\n    part.amountDue = part.subtotal - part.discount + part.reach.fee\n']] },
    { rule: 'total = subtotal − discount + delivery', file: 'src/modules/cart.ts', tests: 'NOVA10', edits: [['total: subtotal - discount + shipping,', 'total: subtotal + shipping,']] },
    { rule: 'refused when fewer are left than asked for', file: 'src/modules/cart.ts', tests: 'something run out', edits: [['if (line.left >= line.line.quantity) continue', 'if (line.left > 0) continue']] },
    { rule: 'the first-order limit', file: 'src/modules/cart.ts', tests: 'first order can be', edits: [['if (total <= FIRST_ORDER_LIMIT) return false', 'return false']] },
    { rule: 'only an order delivered and paid lifts the limit', file: 'src/modules/cart.ts', tests: 'first order can be', edits: [["status = 'DELIVERED' AND payment_status = 'PAID'", "status <> 'CANCELLED'"]] },
    { rule: "a store's code needs some of its things in the cart", file: 'src/modules/cart.ts', tests: 'applying', edits: [["if (atStore <= 0) throw fieldError('code', 'coupon.forStore', { store: coupon.store_name })", '']] },
    { rule: "a store's code needs its minimum to go on", file: 'src/modules/cart.ts', tests: 'under its minimum', edits: [['if (coupon.min_order_amount !== null && atStore < coupon.min_order_amount) {', 'if (false) {']] },
    { rule: 'only a live code goes on the cart', file: 'src/modules/cart.ts', tests: 'applying', edits: [['WHERE c.code = ? AND ${LIVE_COUPON}`', 'WHERE c.code = ?`']] },
    { rule: 'a code no longer live stops the order', file: 'src/modules/cart.ts', tests: 'one use left', edits: [['if (priced.coupon && priced.coupon.row.live !== 1) {', 'if (false) {']] },
    { rule: 'options are locked while an order is placed', file: 'src/modules/cart.ts', tests: 'one unit left', edits: [["WHERE id IN (?) ORDER BY id${lock ? ' FOR UPDATE' : ''}`", 'WHERE id IN (?) ORDER BY id`']] },
    // coupons.ts: the codes
    { rule: 'live: not paused', file: 'src/modules/coupons.ts', tests: 'applying', edits: [['`c.is_active = 1 AND c.starts_at', '`c.starts_at']] },
    { rule: 'live: started', file: 'src/modules/coupons.ts', tests: 'applying', edits: [['c.starts_at <= NOW(3) AND (c.ends_at', '(c.ends_at']] },
    { rule: 'live: not ended', file: 'src/modules/coupons.ts', tests: 'applying', edits: [['(c.ends_at IS NULL OR c.ends_at > NOW(3))', 'TRUE']] },
    { rule: 'live: uses left', file: 'src/modules/coupons.ts', tests: 'limit never goes below', edits: [['AND (c.usage_limit IS NULL OR c.used_count < c.usage_limit) AND', 'AND']] },
    { rule: 'a fixed code in steps of 250', file: 'src/modules/coupons.ts', tests: 'the rules: a code once', edits: [["if (input.discountType === 'FIXED' && input.value % 250 !== 0) throw fieldError('value', 'field.steps250')", '']] },
    { rule: 'a percentage of at most 90', file: 'src/modules/coupons.ts', tests: 'the rules: a code once', edits: [["if (input.discountType === 'PERCENTAGE' && input.value > 90) throw fieldError('value', 'coupon.percentMax')", '']] },
    { rule: "a limit can't go below the uses so far", file: 'src/modules/coupons.ts', tests: 'limit never goes below', edits: [['body.usageLimit !== null && body.usageLimit < row.used_count', 'false']] },
    { rule: "a coupon's day is Iraq's", file: 'src/http/inputs.ts', tests: 'a day picked on the phone', edits: [['`${full}${BAGHDAD_OFFSET}`', '`${full}Z`']] },
    // checkout.ts: placing the order
    { rule: 'one checkout per shopper at a time', file: 'src/modules/checkout.ts', tests: 'the same key twice', edits: [["        await one(conn, 'SELECT id FROM users WHERE id = ? FOR UPDATE', [userId])\n", '']] },
    { rule: 'the same key answers the same order', file: 'src/modules/checkout.ts', tests: 'the same key twice', edits: [['if (done) {', 'if (false) {']] },
    { rule: 'the same key with another body is refused', file: 'src/modules/checkout.ts', tests: 'the same key twice', edits: [["if (!hash.equals(done.request_hash)) throw new AppError(422, 'VALIDATION_ERROR', 'order.keyReused')", '']] },
    { rule: 'placing an order takes the stock', file: 'src/modules/checkout.ts', tests: 'NOVA10', edits: [["await exec(conn, 'UPDATE product_skus SET stock = stock - ? WHERE id = ?', [quantity, line.sku.id])", '']] },
    { rule: 'every stock taken is in the ledger', file: 'src/modules/checkout.ts', tests: 'NOVA10', edits: [["await exec(conn, \"INSERT INTO stock_movements (sku_id, delta, reason, part_id, actor_user_id) VALUES (?, ?, 'ORDER_PLACED', ?, ?)\", [", "void (conn, \"INSERT INTO stock_movements (sku_id, delta, reason, part_id, actor_user_id) VALUES (?, ?, 'ORDER_PLACED', ?, ?)\", ["]] },
    { rule: "a unit's paid price is its share after the code", file: 'src/modules/checkout.ts', tests: 'NOVA10', edits: [['paidUnitPrice(line.unitPrice, part.subtotal, part.discount),', 'line.unitPrice,']] },
    { rule: "a code's use is counted", file: 'src/modules/checkout.ts', tests: 'NOVA10', edits: [["if (coupon) await exec(conn, 'UPDATE coupons SET used_count = used_count + 1 WHERE id = ?', [coupon.id])", '']] },
    { rule: 'a use counts only when the code took something off', file: 'src/modules/checkout.ts', tests: 'under its minimum', edits: [['const coupon = priced.discount > 0 ? priced.coupon!.row : null', 'const coupon = priced.coupon?.row ?? null']] },
    { rule: 'what stops an order stops it', file: 'src/modules/checkout.ts', tests: 'something run out', edits: [['if (problem) throw new AppError(422, problem.code, problem.key, problem.params)', '']] },
    { rule: "a store that can't deliver stops the order", file: 'src/modules/checkout.ts', tests: "doesn't deliver there", edits: [['if (away) {', 'if (false) {']] },
    // orders.ts: the order from its parts, stock back
    { rule: 'the order is as far as its slowest live part', file: 'src/modules/orders.ts', tests: 'two stores: the order', edits: [['STAGE[part.status] < STAGE[slowest] ? part.status : slowest', 'STAGE[part.status] > STAGE[slowest] ? part.status : slowest']] },
    { rule: 'paid only when every live part has arrived', file: 'src/modules/orders.ts', tests: 'two stores: the order', edits: [["live.every((part) => part.status === 'DELIVERED') ? 'PAID' : 'PENDING'", "live.some((part) => part.status === 'DELIVERED') ? 'PAID' : 'PENDING'"]] },
    { rule: 'refused at the door, the order is refused', file: 'src/modules/orders.ts', tests: 'refused at the door', edits: [["status = parts.every((part) => part.status === 'REFUSED') ? 'REFUSED' : 'CANCELLED'", "status = 'CANCELLED'"]] },
    { rule: 'stock going back is saved', file: 'src/modules/orders.ts', tests: 'a decline needs', edits: [["await exec(conn, 'UPDATE product_skus SET stock = stock + ? WHERE id = ?', [line.quantity, line.sku_id])", '']] },
    { rule: 'stock going back is in the ledger', file: 'src/modules/orders.ts', tests: 'a decline needs', edits: [["await exec(conn, 'INSERT INTO stock_movements (sku_id, delta, reason, part_id, return_id, actor_user_id) VALUES (?, ?, ?, ?, ?, ?)', [", "void (conn, 'INSERT INTO stock_movements (sku_id, delta, reason, part_id, return_id, actor_user_id) VALUES (?, ?, ?, ?, ?, ?)', ["]] },
    { rule: 'no cancelling once a store is preparing it', file: 'src/modules/orders.ts', tests: 'no cancelling', edits: [['live.some((part) => STAGE[part.status] > STAGE.CONFIRMED)', 'live.some((part) => STAGE[part.status] > STAGE.SHIPPED)']] },
    { rule: 'a cancelled order is not cancelled again', file: 'src/modules/orders.ts', tests: 'cancel while no store', edits: [['if (live.length === 0 || live.some(', 'if (live.some(']] },
    { rule: "a shopper's cancel puts the stock back", file: 'src/modules/orders.ts', tests: 'cancel while no store', edits: [["await restock(conn, liveIds, 'ORDER_CANCELLED', userId)", '']] },
    // store-orders.ts: the transition table
    { rule: 'no skipping steps', file: 'src/modules/store-orders.ts', tests: 'only the table', edits: [["PENDING: ['CONFIRMED', 'CANCELLED'],", "PENDING: ['CONFIRMED', 'CANCELLED', 'SHIPPED', 'DELIVERED'],"]] },
    { rule: 'a confirmed part is not declined', file: 'src/modules/store-orders.ts', tests: 'only the table', edits: [["CONFIRMED: ['PROCESSING'],", "CONFIRMED: ['PROCESSING', 'CANCELLED'],"]] },
    { rule: 'a shipped part is not declined', file: 'src/modules/store-orders.ts', tests: 'only the table', edits: [["SHIPPED: ['DELIVERED', 'REFUSED'],", "SHIPPED: ['DELIVERED', 'REFUSED', 'CANCELLED'],"]] },
    { rule: 'delivered is an end', file: 'src/modules/store-orders.ts', tests: 'only the table', edits: [["SHIPPED: ['DELIVERED', 'REFUSED'],", "SHIPPED: ['DELIVERED', 'REFUSED'],\n  DELIVERED: ['REFUSED', 'CANCELLED'],"]] },
    { rule: 'a decline puts its stock back', file: 'src/modules/store-orders.ts', tests: 'a decline needs', edits: [["await restock(conn, [part!.id], 'PART_DECLINED', actor)", '']] },
    { rule: 'a refusal puts its stock back', file: 'src/modules/store-orders.ts', tests: 'refused at the door', edits: [["await restock(conn, [part!.id], 'PART_REFUSED', actor)", '']] },
    { rule: 'a decline needs its reason', file: 'src/modules/store-orders.ts', tests: 'a decline needs', edits: [["if (!reason) throw fieldError('reason', 'order.declineReason')", '']] },
    { rule: 'shipping needs the driver', file: 'src/modules/store-orders.ts', tests: 'shipping names the driver', edits: [["if (!name) throw fieldError('courierName', 'order.courier')", '']] },
    { rule: 'the order follows each step', file: 'src/modules/store-orders.ts', tests: 'only the table', edits: [['await rollUp(conn, order!.id, reason)', '']] },
    { rule: 'a store moves only its own parts', file: 'src/modules/store-orders.ts', tests: "another store's part", edits: [["(conn, 'SELECT id, order_id FROM order_store_parts WHERE id = ? AND store_id = ?'", "(conn, 'SELECT id, order_id FROM order_store_parts WHERE id = ? AND (store_id = ? OR TRUE)'"]] },
  ],
  returns: [
    // returns.ts: asking
    { rule: 'a refund is the price paid, not the shelf price', file: 'src/modules/returns.ts', tests: 'the refund is what was paid', edits: [['refund: item.paid_unit_price * line.quantity', 'refund: item.unit_price * line.quantity']] },
    { rule: 'a refund counts every unit returned', file: 'src/modules/returns.ts', tests: 'the refund is what was paid', edits: [['refund: item.paid_unit_price * line.quantity', 'refund: item.paid_unit_price']] },
    { rule: 'a return adds up all its lines', file: 'src/modules/returns.ts', tests: 'the refund is what was paid', edits: [['picked.reduce((sum, line) => sum + line.refund, 0)]', 'picked[0]!.refund]']] },
    { rule: "a return only on the shopper's own order", file: 'src/modules/returns.ts', tests: 'the refund is what was paid', edits: [["FROM orders WHERE id = ? AND customer_id = ? FOR UPDATE'", "FROM orders WHERE id = ? AND (customer_id = ? OR TRUE) FOR UPDATE'"]] },
    { rule: 'the order is locked while a return is asked for', file: 'src/modules/returns.ts', tests: 'each line once', edits: [["FROM orders WHERE id = ? AND customer_id = ? FOR UPDATE'", "FROM orders WHERE id = ? AND customer_id = ?'"]] },
    { rule: 'a line has one return', file: 'src/modules/returns.ts', tests: 'each line once', edits: [["if (item.returned === 1) throw ruleError('return.once')", '']] },
    { rule: 'a line once in a request', file: 'src/modules/returns.ts', tests: 'within 7 days', edits: [["if (!item || picked.some((done) => done.itemId === item.id)) throw itemsError('field.invalid')", "if (!item) throw itemsError('field.invalid')"]] },
    { rule: 'delivered lines, within the window, only', file: 'src/modules/returns.ts', tests: 'within 7 days', edits: [["if (!returnable(part, item, now)) throw ruleError('return.window', { days: RETURN_WINDOW_DAYS })", '']] },
    { rule: 'the window is 7 days', file: 'src/modules/orders.ts', tests: 'within 7 days', edits: [['now.getTime() - part.delivered_at.getTime() <= RETURN_WINDOW_DAYS * DAY_MS', 'now.getTime() - part.delivered_at.getTime() <= (RETURN_WINDOW_DAYS + 1) * DAY_MS']] },
    { rule: 'at most what was bought', file: 'src/modules/returns.ts', tests: 'within 7 days', edits: [["if (line.quantity > item.quantity) throw itemsError('return.tooMany')", '']] },
    { rule: 'one store at a time', file: 'src/modules/returns.ts', tests: 'within 7 days', edits: [["if (new Set(picked.map((line) => line.partId)).size > 1) throw ruleError('return.oneStore')", '']] },
    // returns.ts: the store's answer
    { rule: 'the return is locked while it is answered', file: 'src/modules/returns.ts', tests: 'the cash only after approval', edits: [["'SELECT id, customer_id, status FROM returns WHERE id = ? AND store_id = ? FOR UPDATE'", "'SELECT id, customer_id, status FROM returns WHERE id = ? AND store_id = ?'"]] },
    { rule: 'a store answers only its own returns', file: 'src/modules/returns.ts', tests: "another store's return", edits: [["'SELECT id, customer_id, status FROM returns WHERE id = ? AND store_id = ? FOR UPDATE'", "'SELECT id, customer_id, status FROM returns WHERE id = ? AND (store_id = ? OR TRUE) FOR UPDATE'"]] },
    { rule: 'no cash before approval', file: 'src/modules/returns.ts', tests: 'the cash only after approval', edits: [["REQUESTED: ['APPROVED', 'REJECTED'],", "REQUESTED: ['APPROVED', 'REJECTED', 'REFUNDED'],"]] },
    { rule: 'a declined return is an end', file: 'src/modules/returns.ts', tests: 'a decline needs', edits: [["APPROVED: ['REFUNDED'],", "APPROVED: ['REFUNDED'],\n  REJECTED: ['APPROVED', 'REFUNDED'],"]] },
    { rule: 'the cash is handed back once', file: 'src/modules/returns.ts', tests: 'approved, then the cash', edits: [["APPROVED: ['REFUNDED'],", "APPROVED: ['REFUNDED'],\n  REFUNDED: ['REFUNDED'],"]] },
    { rule: 'a decline needs its reason', file: 'src/modules/returns.ts', tests: 'a decline needs', edits: [["if (!reason) throw new AppError(422, 'VALIDATION_ERROR', 'order.declineReason'", "if (false) throw new AppError(422, 'VALIDATION_ERROR', 'order.declineReason'"]] },
    { rule: 'the cash handed back puts the stock back', file: 'src/modules/returns.ts', tests: 'approved, then the cash', edits: [["await putBack(conn, back, 'RETURN_REFUNDED', actor, ret.id)", '']] },
    { rule: 'only the returned quantity goes back', file: 'src/modules/returns.ts', tests: 'approved, then the cash', edits: [['SELECT oi.part_id, oi.sku_id, ri.quantity FROM return_items', 'SELECT oi.part_id, oi.sku_id, oi.quantity FROM return_items']] },
    { rule: 'the ledger row names its return', file: 'src/modules/returns.ts', tests: 'approved, then the cash', edits: [["await putBack(conn, back, 'RETURN_REFUNDED', actor, ret.id)", "await putBack(conn, back, 'RETURN_REFUNDED', actor)"]] },
    { rule: "a refund comes off its own month's bill", file: 'src/modules/returns.ts', tests: 'approved, then the cash', edits: [['[at, billingMonth(at), ret.id]', "[at, '2020-01-01', ret.id]"]] },
    // admin-returns.ts, admin-customers.ts: the money Saba sees
    { rule: 'the value leaves declined returns out', file: 'src/modules/admin-returns.ts', tests: 'cancellations and returns', edits: [["value: found.filter((row) => row.returnStatus !== 'REJECTED').reduce((sum, row) => sum + row.value, 0),", 'value: found.reduce((sum, row) => sum + row.value, 0),']] },
    { rule: 'a cancelled part is worth its goods less its code', file: 'src/modules/admin-returns.ts', tests: 'cancellations and returns', edits: [['value: part.subtotal - part.discount,', 'value: part.subtotal,']] },
    { rule: 'the return sheet shows the price paid for one', file: 'src/modules/admin-returns.ts', tests: 'a return in full', edits: [['unitPrice: line.paid_unit_price,', 'unitPrice: line.refund_amount,']] },
    { rule: 'spent: what the delivered parts came to', file: 'src/modules/admin-customers.ts', tests: 'customers: found by', edits: [['SELECT COALESCE(SUM(op.amount_due), 0)', 'SELECT COALESCE(SUM(op.subtotal - op.discount), 0)']] },
    { rule: 'spent: delivered parts only', file: 'src/modules/admin-customers.ts', tests: 'customers: found by', edits: [["WHERE o.customer_id = u.id AND op.status = 'DELIVERED') AS delivered", 'WHERE o.customer_id = u.id) AS delivered']] },
    { rule: 'spent: less refunded returns only', file: 'src/modules/admin-customers.ts', tests: 'customers: found by', edits: [["WHERE r.customer_id = u.id AND r.status = 'REFUNDED') AS refunded", 'WHERE r.customer_id = u.id) AS refunded']] },
    { rule: 'spent: less what was handed back', file: 'src/modules/admin-customers.ts', tests: 'customers: found by', edits: [['spent: Number(row.delivered) - Number(row.refunded),', 'spent: Number(row.delivered),']] },
  ],
  config: [
    { rule: 'production needs OTPIQ', file: 'src/config.ts', edits: [["if (production && values.SMS_PROVIDER !== 'otpiq') {", 'if (false) {']] },
    { rule: 'OTPIQ needs its key', file: 'src/config.ts', edits: [["if (values.SMS_PROVIDER === 'otpiq' && !values.OTPIQ_API_KEY) {", 'if (false) {']] },
    { rule: 'production needs two different secrets', file: 'src/config.ts', edits: [['if (production && values.JWT_SECRET === values.OTP_SECRET) {', 'if (false) {']] },
  ],
  stores: [
    { rule: 'admin routes are for admins only', file: 'src/modules/admin-stores.ts', edits: [["const ADMIN = ['ADMIN'] as const", "const ADMIN = ['ADMIN', 'MERCHANT'] as const"]] },
    { rule: 'an answer only from the right state (409)', file: 'src/modules/admin-stores.ts', edits: [['`UPDATE stores SET ${step.set} WHERE id = ? AND status = ?`', '`UPDATE stores SET ${step.set} WHERE id = ? AND ? IS NOT NULL`']] },
    { rule: 'a rejection or suspension needs a reason', file: 'src/modules/admin-stores.ts', edits: [['const Reason = z.object({ reason: requiredText(500) })', 'const Reason = z.object({ reason: z.string().trim().default(\'\') })']] },
    { rule: 'the store is told', file: 'src/modules/admin-stores.ts', edits: [['if (step.tell) {', 'if (false) {']] },
    { rule: 'a reactivated store is told, in its own words', file: 'src/modules/admin-stores.ts', edits: [["        tell: { title: 'notify.storeReactivated.title', body: 'notify.storeReactivated.body' },\n", '']] },
    { rule: 'every answer writes the audit row', file: 'src/modules/admin-stores.ts', edits: [["VALUES (?, ?, 'STORE', ?, ?, ?)`,\n        [me(req).id, step.action, String(id), step.reason ?? null, req.ip ?? null],", "VALUES (?, ?, 'STORE', ?, ?, ?)`,\n        [me(req).id, step.action, '0', step.reason ?? null, req.ip ?? null],"]] },
    { rule: 'the queue: waiting stores, oldest first', file: 'src/modules/admin-stores.ts', edits: [['"WHERE s.status = \'PENDING\'", [], \'s.submitted_at, s.id\'', '"WHERE s.status = \'PENDING\'", [], \'s.submitted_at DESC, s.id\'']] },
    { rule: 'a phone is found however it is typed', file: 'src/modules/admin-stores.ts', edits: [['return [national, `0${national}`, `964${national}`].some((form) => form.includes(typed))', 'return national.includes(typed.replace(/^0/, \'\'))']] },
    { rule: 'a phone needs 4 digits to match', file: 'src/modules/admin-stores.ts', edits: [['if (!/^\\d{4,}$/.test(typed)) return false', 'if (!/^\\d{3,}$/.test(typed)) return false']] },
    { rule: 'a city is found in either language', file: 'src/modules/admin-stores.ts', edits: [['store.businessAddress, ...governorateNames]', 'store.businessAddress]']] },
    { rule: 'a suspended store leaves the rail', file: 'src/modules/admin-stores.ts', edits: [["WHERE s.status = 'APPROVED' ORDER BY f.position", 'ORDER BY f.position']] },
    { rule: 'a suspended featured store keeps its place at the end', file: 'src/modules/admin-stores.ts', edits: [['const rail = [...ids, ...kept.map((row) => row.store_id).filter((id) => !ids.includes(id))]', 'const rail = [...ids]']] },
    { rule: 'the rail refuses a store not approved', file: 'src/modules/admin-stores.ts', edits: [['if (approved.length !== ids.length) {', 'if (new Set(ids).size !== ids.length) {']] },
    { rule: "a store's own city is always in its delivery", file: 'src/modules/stores.ts', edits: [['new Set<Governorate>([home, ...body.delivery.governorates])', 'new Set<Governorate>([...body.delivery.governorates])']] },
    { rule: 'fees in steps of 250', file: 'src/modules/stores.ts', edits: [['.refine((value) => value % 250 === 0,', '.refine((value) => value % 1 === 0,']] },
    { rule: 'other cities need their own fee and time', file: 'src/modules/stores.ts', edits: [['if (goesOut && (body.delivery.feeOutside == null', 'if (false && (body.delivery.feeOutside == null']] },
    { rule: 'store names compare without case or extra spaces', file: 'src/modules/stores.ts', edits: [["return storeName.trim().toLowerCase().replace(/\\s+/g, ' ')", 'return storeName']] },
    { rule: 'a logo is its own upload', file: 'src/modules/stores.ts', edits: [['const allowed =\n            logo !== null &&', 'const allowed =\n            true ||']] },
    { rule: 'an edited field replaces both languages', file: 'src/modules/stores.ts', edits: [['? [text, arabic] : [sent, null]', '? [text, arabic] : [sent, arabic]']] },
    { rule: 'store words in the asked language', file: 'src/modules/stores.ts', edits: [["return lang === 'ar' && arabic ? arabic : text", 'return text']] },
    { rule: 'the open switch is saved', file: 'src/modules/stores.ts', edits: [["await exec(pool, 'UPDATE stores SET is_open = ? WHERE id = ?', [body.isOpen, row.id])", '']] },
    { rule: 'only an approved store has a page', file: 'src/modules/stores.ts', edits: [["`${STORE_SELECT} WHERE s.id = ? AND s.status = 'APPROVED'`", '`${STORE_SELECT} WHERE s.id = ?`']] },
    { rule: 'city chips: open stores only', file: 'src/modules/stores.ts', edits: [["AND s.status = 'APPROVED' AND s.is_open = 1)", "AND s.status = 'APPROVED')"]] },
    { rule: 'city chips: approved stores only', file: 'src/modules/stores.ts', edits: [["AND s.status = 'APPROVED' AND s.is_open = 1)", 'AND s.is_open = 1)']] },
    { rule: "a shopper can't reach the store's own routes", file: 'src/modules/stores.ts', edits: [["summary: \"The store's settings and delivery terms\",\n    who: ['MERCHANT'],", "summary: 'x',\n    who: 'signedIn',"]] },
    { rule: 'uploads are for store owners and Saba', file: 'src/modules/media.ts', edits: [["await api.authenticate(req, ['MERCHANT', 'ADMIN'])", "await api.authenticate(req, 'signedIn')"]] },
    { rule: 'a photo is told by its bytes', file: 'src/lib/storage.ts', edits: [["if (bytes.subarray(0, 8).equals(", "if (bytes.length > 0 || bytes.subarray(0, 8).equals("]] },
    { rule: 'at most 5 MB', file: 'src/modules/media.ts', edits: [['export const MAX_UPLOAD_BYTES = 5 * 1024 * 1024', 'export const MAX_UPLOAD_BYTES = 50 * 1024 * 1024']] },
    { rule: "only its owner deletes an upload", file: 'src/modules/media.ts', edits: [["WHERE id = ? AND owner_user_id = ? AND deleted_at IS NULL", 'WHERE id = ? AND (owner_user_id = ? OR TRUE) AND deleted_at IS NULL']] },
    { rule: 'a photo in use is not deleted', file: 'src/modules/media.ts', edits: [["if (used) throw new AppError(409", "if (false) throw new AppError(409"]] },
    { rule: 'notifications: own only (read)', file: 'src/modules/notifications.ts', edits: [["FROM notifications WHERE user_id = ? ORDER BY id DESC", 'FROM notifications WHERE user_id > 0 OR user_id = ? ORDER BY id DESC']] },
    { rule: 'notifications: own only (mark read)', file: 'src/modules/notifications.ts', edits: [["WHERE id = ? AND user_id = ?', [", "WHERE id = ? AND (user_id = ? OR TRUE)', ["]] },
    { rule: 'the unread count counts unread', file: 'src/modules/notifications.ts', edits: [["WHERE user_id = ? AND is_read = 0',\n", "WHERE user_id = ?',\n"]] },
    { rule: 'read-all marks every one read', file: 'src/modules/notifications.ts', edits: [["'UPDATE notifications SET is_read = 1 WHERE user_id = ? AND is_read = 0'", "'UPDATE notifications SET is_read = 1 WHERE user_id = ? AND id < 0'"]] },
  ],
  'admin-catalog': [
    { rule: 'a hidden category takes no new product', file: 'src/modules/merchant-products.ts', tests: 'hidden:', edits: [["if (current?.category_id !== categoryId) throw fieldError('categoryId', 'category.hidden')", "if (false) throw fieldError('categoryId', 'category.hidden')"]] },
    { rule: 'a product already in a hidden category keeps it', file: 'src/modules/merchant-products.ts', tests: 'hidden:', edits: [["if (current?.category_id !== categoryId) throw fieldError('categoryId', 'category.hidden')", "if (true) throw fieldError('categoryId', 'category.hidden')"]] },
    { rule: "a category's new names reach its products' search", file: 'src/modules/admin-catalog.ts', tests: 'renamed or moved', edits: [["if (moved || renamed) await refreshSearchText(conn, 'c.id = ? OR c.parent_id = ?', [id, id])", '']] },
    { rule: "a parent's new names reach its sub-categories' products", file: 'src/modules/admin-catalog.ts', tests: 'renamed or moved', edits: [["'c.id = ? OR c.parent_id = ?'", "'c.id = ? OR c.id = ?'"]] },
    { rule: 'a category with products needs somewhere to move them', file: 'src/modules/admin-catalog.ts', tests: 'deleted: refused while', edits: [["if (query.moveTo === undefined) throw new AppError(409, 'CONFLICT_ERROR', 'category.hasProducts', { products: count })", '']] },
    { rule: 'a category with sub-categories is not deleted', file: 'src/modules/admin-catalog.ts', tests: 'deleted: refused while', edits: [["throw new AppError(409, 'CONFLICT_ERROR', 'category.hasChildren')", 'void 0']] },
    { rule: "a deleted category's products move first", file: 'src/modules/admin-catalog.ts', tests: 'deleted: refused while', edits: [["await exec(conn, 'UPDATE products SET category_id = ?, updated_at = updated_at WHERE category_id = ? AND deleted_at IS NULL', [target, id])", '']] },
    { rule: 'moved products keep their updated_at', file: 'src/modules/admin-catalog.ts', tests: 'deleted: refused while', edits: [["'UPDATE products SET category_id = ?, updated_at = updated_at WHERE", "'UPDATE products SET category_id = ? WHERE"]] },
    { rule: 'moved products are found by their new category', file: 'src/modules/admin-catalog.ts', tests: 'deleted: refused while', edits: [["await refreshSearchText(conn, 'p.category_id = ?', [target])", '']] },
    { rule: "a deleted brand's products move first", file: 'src/modules/admin-catalog.ts', tests: 'deleted: its products move', edits: [["await exec(conn, 'UPDATE products SET brand_id = ?, updated_at = updated_at WHERE brand_id = ?', [target, id])", '']] },
    { rule: 'a brand with products needs a choice', file: 'src/modules/admin-catalog.ts', tests: 'deleted: its products move', edits: [["if (count > 0 && query.moveTo === undefined) throw new AppError(409, 'CONFLICT_ERROR', 'brand.hasProducts', { products: count })", '']] },
    { rule: 'products move only to a checked brand', file: 'src/modules/admin-catalog.ts', tests: 'deleted: its products move', edits: [["\"SELECT id FROM brands WHERE id = ? AND status = 'APPROVED' FOR SHARE\"", "'SELECT id FROM brands WHERE id = ? FOR SHARE'"]] },
    { rule: 'approving a product approves its typed brand', file: 'src/modules/admin-products.ts', tests: 'a typed brand', edits: [["await exec(conn, \"UPDATE brands b JOIN products p ON p.brand_id = b.id SET b.status = 'APPROVED' WHERE p.id = ? AND b.status = 'PENDING'\", [id])", '']] },
    { rule: 'a typed brand waits for Saba', file: 'src/modules/merchant-products.ts', tests: 'a typed brand', edits: [["\"INSERT INTO brands (name, status) VALUES (?, 'PENDING') ON DUPLICATE KEY", "\"INSERT INTO brands (name, status) VALUES (?, 'APPROVED') ON DUPLICATE KEY"]] },
    { rule: 'a typed name finds its brand in Arabic too', file: 'src/modules/merchant-products.ts', tests: 'a typed brand', edits: [["'SELECT id FROM brands WHERE name = ? OR name_ar = ? LIMIT 1', [typed, typed]", "'SELECT id FROM brands WHERE name = ? LIMIT 1', [typed]"]] },
    { rule: 'a save waits for a category Saba is deleting', file: 'src/modules/merchant-products.ts', tests: 'saving while Saba deletes', edits: [['WHERE c.id = ? AND c.deleted_at IS NULL FOR SHARE`', 'WHERE c.id = ? AND c.deleted_at IS NULL`']] },
    { rule: 'a save waits for a brand Saba is deleting', file: 'src/modules/merchant-products.ts', tests: 'saving while Saba deletes', edits: [["if (!(await one(conn, 'SELECT id FROM brands WHERE id = ? FOR SHARE', [brandId])))", "if (!(await one(conn, 'SELECT id FROM brands WHERE id = ?', [brandId])))"]] },
  ],
}

const name = process.argv[2] ?? ''
/** Optional: only the rules whose name contains this; "from:<text>" resumes at that rule. */
const only = process.argv[3]
const all = suites[name]
const start = only?.startsWith('from:') ? (all?.findIndex((m) => m.rule.includes(only.slice(5))) ?? -1) : -1
const mutations =
  start >= 0 ? all!.slice(start) : all?.filter((mutation) => !only || only.startsWith('from:') || mutation.rule.includes(only))
if (!mutations) {
  console.error(`Usage: npx tsx test/prove-code.ts <${Object.keys(suites).join('|')}>`)
  process.exit(2)
}

// A run that hangs (a server left open by a failing test) is stopped after
// 5 minutes and counts as failed; each test gets 1 minute.
const runTests = (pattern?: string) =>
  spawnSync(
    process.execPath,
    ['--import', 'tsx', '--test', '--test-timeout=60000', ...(pattern ? [`--test-name-pattern=${pattern}`] : []), `test/${name}.test.ts`],
    { encoding: 'utf8', timeout: 5 * 60_000 },
  )

// A file this script broke and never put back (it was killed mid-run) is put
// back first, from the copy kept beside it.
const BACKUP = 'test/.prove-backup.json'
if (existsSync(BACKUP)) {
  const { file, original } = JSON.parse(readFileSync(BACKUP, 'utf8')) as { file: string; original: string }
  writeFileSync(file, original)
  rmSync(BACKUP)
  console.error(`Restored ${file}, left broken by a run that was stopped.`)
}

// Every edit must find its text exactly once, checked before anything runs.
const unmatched = mutations.flatMap((mutation) => {
  const text = readFileSync(mutation.file, 'utf8')
  return mutation.edits
    .map(([from]) => [from, text.split(from).length - 1] as const)
    .filter(([, count]) => count !== 1)
    .map(([from, count]) => `${mutation.rule}: "${from.slice(0, 60)}" found ${count} times in ${mutation.file}`)
})
if (unmatched.length > 0) {
  console.error(unmatched.join('\n'))
  process.exit(2)
}

// Unbroken, the file must pass: otherwise every mutation below would look "caught".
if (runTests().status !== 0) {
  console.error(`test/${name}.test.ts fails before anything is broken. Fix it first.`)
  process.exit(2)
}

let missed = 0
for (const mutation of mutations) {
  const original = readFileSync(mutation.file, 'utf8')
  let broken = original
  for (const [from, to] of mutation.edits) {
    const count = broken.split(from).length - 1
    if (count !== 1) {
      console.error(`${mutation.rule}: expected one "${from.slice(0, 60)}" in ${mutation.file}, found ${count}`)
      process.exit(2)
    }
    broken = broken.replace(from, () => to)
  }
  writeFileSync(BACKUP, JSON.stringify({ file: mutation.file, original }))
  try {
    writeFileSync(mutation.file, broken)
    const caught = runTests(mutation.tests).status !== 0
    if (!caught) missed += 1
    console.log(`${caught ? 'caught    ' : 'NOT CAUGHT'}  ${mutation.rule}`)
  } finally {
    writeFileSync(mutation.file, original)
    rmSync(BACKUP)
  }
}
console.log(`\n${mutations.length - missed} of ${mutations.length} rules proved.`)
process.exitCode = missed === 0 ? 0 : 1
