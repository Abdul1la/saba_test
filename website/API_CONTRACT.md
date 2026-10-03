# Saba admin web: API contract

What the admin web needs from the backend: every endpoint, what it takes, what it returns, and which page uses it.

**Where it comes from.** Each endpoint is a function in `website/src/data/*.ts`. The mock there answers with exactly these shapes, and the screens read nothing else. When a real endpoint answers the same way, the only thing to replace is the body of that function.

**Status of each endpoint:**

- **Built**: the web calls it today, against the mock.
- **Future**: listed in `TODO.md`, not built in the web yet. The shape is only a proposal.

**The mobile app.** Where the app already has a route or a field, this contract uses its names. The fields the app does not have yet are marked `web-only` in the types. Where the web and the app disagree today, the conflict is listed at the end (§6), with what to decide.

---

## 1. Conventions

These follow the mobile app (`mobile/lib/core/network/api_response.dart`, `core/errors/error_mapper.dart`), so one backend serves both.

### 1.1 Requests

- **Base.** The admin routes live under `/admin`. Sign-in (`/auth/login`) and categories (`/categories`) are the app's own routes.
- **Who may call.** Every `/admin` route needs `Authorization: Bearer <accessToken>` from an account with `role: "ADMIN"`.
  - No token, or an expired one: `401`.
  - Signed in, but not an admin: `403`. The app's demo server already answers this way.
- **Bodies.** JSON, UTF-8. The web sends a body only where an endpoint lists one.

### 1.2 Responses

- **Success envelope** (the app's §54):

  ```json
  { "success": true, "message": "", "data": { }, "meta": { } }
  ```

- **Lists** put the rows and their counts in `data`:

  ```json
  {
    "success": true,
    "data": {
      "items": [ ],
      "counts": { "all": 12, "PENDING": 2, "APPROVED": 8 }
    },
    "meta": { "page": 1, "perPage": 100, "total": 12, "totalPages": 1 }
  }
  ```

  - `counts` is how many rows of each status match the search, whatever the status filter. The filter chips show these numbers.
  - A status with no rows may be left out of `counts`; the web reads it as 0.
  - `all` is always sent.

- **Writes** (approve, reject, suspend…) return the record as it now is. After any write, the web asks again for everything on screen, so the record returned must already show the change.

### 1.3 Paging

**Built (2026-09-30, the reviewer's item 7): every admin list pages and searches in the database.** This covers `/admin/orders`, `/admin/customers`, `/admin/products`, `/admin/stores`, `/admin/tickets` and `/admin/after-sales`, and `/admin/reports`, `/admin/review-reports` and `/admin/brands` since 2026-10-01. Loading every row gets slow: at 50,000 orders, seconds and tens of MB per page load.

- **Query:** `page` (from 1) and `perPage` (1–100, default 50), next to the list's own filters.
- **Every answer is one page:** `data` is that page's usual object (`{items, counts, …}`), and `meta` is `{page, perPage, total, totalPages}`.
  - `total` counts the rows matching the list's filters (its status or kind included).
  - `counts` (and `byOpener`, `value`) stay the whole list's, within its search and filters, the same on every page.
  - The order is the list's usual one (newest first).
- **Without `page`:** page 1 (since 2026-09-30, once the web paged every list). No request gets the whole list at once.
- **The search box (`q`)** matches in the database as the web matched: the whole phrase, folded, in any one field, and a phone however it is typed. One small difference: a shopper's home area matches as typed (the database ignores case and accents), not folded.

### 1.4 Errors

The error body is the app's:

```json
{ "success": false, "code": "VALIDATION_ERROR", "message": "Write a reason.", "errors": { "reason": "Write a reason." } }
```

The web shows its own text, in the admin's language, for each case. It picks the case from the HTTP status, the `code` and the `errors` key:

| Case | HTTP | `code` | `errors` key | Web's code (`mock.ts` `ErrorCode`) |
|---|---|---|---|---|
| Not signed in, or token expired | 401 | `AUTHENTICATION_ERROR` | none | sign-in again |
| Signed in, not an admin | 403 | `AUTHORIZATION_ERROR` | none | `ADMINS_ONLY` |
| No such record | 404 | `NOT_FOUND_ERROR` | none | `NOT_FOUND` |
| Not allowed from the record's current state (already answered, already paid…) | 409 | `CONFLICT_ERROR` | none | `WRONG_STATE` |
| A required reason is blank | 422 | `VALIDATION_ERROR` | `reason` | `REASON_REQUIRED` |
| A ticket reply is blank | 422 | `VALIDATION_ERROR` | `body` | `MESSAGE_REQUIRED` |
| A payment day is outside the allowed range | 422 | `VALIDATION_ERROR` | `paidAt` | `BAD_DATE` |
| Approving a product with no Arabic name | 422 | `BUSINESS_RULE_ERROR` | `nameAr` | `ARABIC_NAME_REQUIRED` |
| No answer, or a 5xx | none | none | none | `NETWORK` (offers "Try again") |

**"Blank"** means empty or only spaces: the server trims before checking. Every reason and message is stored trimmed.

### 1.5 Values

| Kind | Format | Example |
|---|---|---|
| Ids | string | `"m-1"`, `"p-42"`, `"mo-3"` |
| Moments | ISO 8601 date-time, UTC | `"2026-09-24T09:21:00.000Z"` |
| Days (input only) | `YYYY-MM-DD` | `"2026-09-03"` |
| Months, in responses | the first day, a plain date with no time (§6.3) | `"2026-08-01"` |
| Months, in paths and queries | `YYYY-MM` | `"2026-08"` |
| Money | integer, IQD, no decimals | `246000` |
| `currencyCode` | always `"IQD"` in v1 | |
| Phones | E.164 | `"+9647705550142"` |
| Governorate | the app's `Governorate.apiValue` | `"BAGHDAD"` |

The 19 governorates: `BAGHDAD`, `BASRA`, `NINEVEH`, `ERBIL`, `SULAYMANIYAH`, `DUHOK`, `KIRKUK`, `NAJAF`, `KARBALA`, `BABYLON`, `ANBAR`, `DHI_QAR`, `DIYALA`, `SALAH_AL_DIN`, `WASIT`, `MAYSAN`, `QADISIYAH`, `MUTHANNA`, `HALABJA`.

### 1.6 Languages

- **Names come in both languages, whatever the request's language.** The admin reads and searches both. So a product sends `nameEn` and `nameAr`, and a category sends `name` (English) and `nameAr`.
- **Free text is returned as typed:** reasons, notes, ticket messages, store descriptions.
- **Codes are sent as codes** (statuses, reason codes, categories). The web translates them.

### 1.7 Search (`q`)

- **Case and letters.** The search ignores case. In Arabic it folds the common letter variants: أ إ آ → ا, ة → ه, ى → ي, and harakat are removed.
- **Governorates** match in either language. "Erbil" and "أربيل" both find `ERBIL`.
- **Phones** match however the admin typed them: `0770 555 0142`, `770 555 0142` and `+964 770 555 0142` all find `+9647705550142`.
  - Compare digits only, without the leading `0` or `964`.
  - Match once at least 4 digits are typed.

---

## 2. Shared types

Written as TypeScript. These are the exact field names on the wire.

- `?` means the field may be missing.
- `// web-only` marks a field the mobile app does not send yet (see `TODO.md` → New fields).

```ts
type Governorate = 'BAGHDAD' | 'BASRA' | … // the 19 in §1.5

// ----------------------------------------------------------------- stores
type StoreStatus = 'PENDING' | 'APPROVED' | 'REJECTED' | 'SUSPENDED' | 'CLOSED' // the app's MerchantStatus; no UNDER_REVIEW in v1 (§6.9). CLOSED: its owner's account was deleted

interface StoreDelivery {          // the store's own delivery settings, as the app keeps them
  governorates: Governorate[]      // where it delivers; its own governorate included
  feeInside: number                // IQD, inside its own governorate
  timeInside: string               // as the store typed it
  feeOutside: number               // IQD, to the other governorates it delivers to
  timeOutside: string
}

interface AdminStore {
  id: string
  storeName: string
  status: StoreStatus
  fullName: string                 // the owner (MerchantRegistration)
  phone: string                    // the owner's
  phoneVerified: boolean           // false: signed up while SMS codes were off, the number never checked (2026-10-01)
  email?: string
  businessAddress?: string
  description?: string
  descriptionAr?: string           // the Arabic twin, when the store has one
  country: string                  // "Iraq"
  governorate: Governorate
  logoUrl?: string
  bannerUrl?: string
  rating?: number                  // 0–5
  reviewCount: number
  delivery?: StoreDelivery
  submittedAt: string              // when it applied
  answeredAt?: string              // when Saba approved or rejected it
  rejectionReason?: string         // the name MerchantProductRow uses; the app sends it for stores too
  suspensionReason?: string        // web-only
  productCount: number             // its products, drafts not counted; worked out, never typed
  isOpen: boolean                  // the owner's open switch ("Close my store"); a closed store takes no orders
  deletionRequestedAt?: string     // the owner asked to delete the account; the store is closed until it is done or cancelled
  closedAt?: string                // CLOSED: when the account was deleted. The owner's name, phone and email are gone (phone is ""); orders, returns and bills keep the store's name
}

// --------------------------------------------------------------- products
type ProductStatus = 'DRAFT' | 'PENDING' | 'APPROVED' | 'REJECTED'
type StockStatus = 'IN_STOCK' | 'LOW_STOCK' | 'OUT_OF_STOCK'

interface ProductVariant {
  id: string
  price: number
  availableQuantity: number
  stockStatus: StockStatus
  options: Record<string, string> // e.g. { "Colour": "Black", "Storage": "256 GB" }
}

interface AdminProduct {
  id: string
  nameEn: string                   // the app's Product.nameEn
  nameAr: string                   // required before approval ('' if the store left it empty)
  description?: string
  price: number
  originalPrice?: number           // the price before a discount
  discountPercentage?: number
  currencyCode: string
  stockStatus: StockStatus
  availableQuantity: number
  categoryId: string
  categoryName: string             // English
  categoryNameAr: string           // the app's /admin routes send it
  brand?: { id: string; name: string; nameAr: string | null; isNew: boolean }  // isNew: typed by the store, checked with the product (§3.14)
  merchant: { id: string; storeName: string; status: StoreStatus }
  imageUrl?: string                // the main photo
  images: { id: string; url: string; isPrimary: boolean }[]
  warranty?: string
  variants: ProductVariant[]
  createdAt: string                // the web shows it as when it was sent for review
  status: ProductStatus
  rejectionReason?: string
  isActive: boolean                // the store's own on/off switch (the app's isActive)
  takenDown: boolean               // taken out of the shop by Saba; the store keeps its copy and can't undo it (§6.8)
  takenDownReason?: string         // the store is told why
  inShop: boolean                  // shoppers can buy it now (D-P1)
  notInShopReason?: 'NOT_APPROVED' | 'TAKEN_DOWN' | 'HIDDEN_BY_STORE' | 'STORE_NOT_APPROVED' | 'STORE_CLOSED' // set when inShop is false; a code the web translates
}

// ----------------------------------------------------------------- orders
type OrderStatus = 'PENDING' | 'CONFIRMED' | 'PROCESSING' | 'SHIPPED' | 'DELIVERED'
                 | 'CANCELLED' | 'REFUSED' | 'RETURNED' | 'REFUNDED'
// The store side's NEW is sent as PENDING on /admin routes. There is no PACKED (the app dropped it).
type PaymentStatus = 'PENDING' | 'PAID' | 'REFUNDED' | 'CANCELLED'

interface OrderAddress {           // the app's OrderAddress, as it was when the order was placed
  fullName: string
  phone?: string
  governorate?: Governorate
  area?: string
  street?: string
  landmark?: string
}

interface OrderItem {              // the app's OrderItem: a snapshot taken when the order was placed
  id: string
  productId?: string               // missing if the product was deleted later
  productName: string
  productNameAr?: string           // web-only
  imageUrl?: string
  quantity: number
  unitPrice: number
  lineTotal: number
  merchantId: string
  merchantName: string
}

interface OrderStep {              // the app's OrderTimelineEntry; send its other fields too
  status: OrderStatus              // (noteCode, storeName, reasonCode, note): the web reads these two
  occurredAt: string
}

interface OrderStorePart {         // the app's storeParts entry: one per store in the order (decided, §6.4)
  merchantId: string
  merchantName: string             // the store's name when the order was placed
  subtotal: number                 // this store's goods; with discount, shipping and deliveryTime, decided in Q7
  discount: number                 // this store's own coupon
  shipping: number                 // this store's delivery fee
  deliveryTime: string             // SAME_DAY, 1_2_DAYS, 2_3_DAYS, 3_5_DAYS or 5_7_DAYS
  cancellationReason?: string      // a code, §2.1; CUSTOMER_CANCELLED when the shopper cancelled
  amountDue: number                // what this store's driver collects at the door
  status: OrderStatus              // where this store's part has got to
  courierName?: string             // the store's own driver, named when it marks its part shipped
  courierPhone?: string
  received?: boolean               // the shopper's "did you receive it?"; the web does not read it
}

interface AdminOrder {
  id: string
  orderNumber: string              // "SB-200103"
  placedAt: string
  deliveredAt?: string
  status: OrderStatus              // for several stores: where the slowest live part has got to (the app's rule)
  paymentStatus: PaymentStatus
  isCashOnDelivery: boolean        // always true in v1
  paymentMethodLabel: string
  subtotal: number                 // goods
  shipping: number                 // delivery fees
  discount: number
  total: number
  currencyCode: string
  itemCount: number                // UNITS, not lines: 2 of one thing + 1 of another = 3 (the app's Order.itemCount)
  customerName: string
  customerPhone: string
  shippingAddress: OrderAddress
  storeParts: OrderStorePart[]     // one per store; each ships with its own driver (§6.4)
  timeline: OrderStep[]            // oldest first; the first is PENDING, when it was placed
  cancelledAt?: string             // web-only; set on CANCELLED
  cancelledBy?: 'SHOPPER' | 'STORE' // web-only
  cancelReason?: string            // a code, §2.1
  cancelNote?: string              // the shopper's own words, with OTHER
  merchantNames: string[]
  items: OrderItem[]
}
```

### 2.1 Reason codes

| Where | Codes |
|---|---|
| Shopper cancels (the app's `CancelReason`) | `CHANGED_MIND`, `FOUND_CHEAPER`, `DELIVERY_TOO_SLOW`, `ORDERED_BY_MISTAKE`, `OTHER` |
| Store declines (the app's `declineReasonCodes`) | `OUT_OF_STOCK`, `CANNOT_FULFIL`, `ADDRESS_PROBLEM`, `CUSTOMER_ASKED` |
| A store's part, when the shopper cancelled the order | `CUSTOMER_CANCELLED` (the app's `cancellationReason` on the part) |
| Return (the app's `ReturnReason`) | `DAMAGED`, `WRONG_ITEM`, `NOT_AS_DESCRIBED`, `MISSING_PARTS`, `CHANGED_MIND`, `OTHER` |
| Store declines a return (the app's `returnDeclineCodes`) | `USED`, `INCOMPLETE`, `NOT_AS_SAID`, `OTHER` |

The other types (bills, tickets, returns, customers…) are given with the endpoints that use them.

---

## 3. Endpoints

**Pages**, as the web names them:

- Sign-in
- Dashboard
- Approval queue
- Stores
- Products
- Orders
- Finance
- Support
- Featured stores
- Cancellations & returns
- Customers

**Sheets** are the detail panels that open over a page. Each one opens from any page that links to it.

### 3.1 Sign-in

#### `POST /auth/login`: Built (mock)

Used by: **Sign-in**. This is the app's own route.

- **Body:** `{ "email": string }` or `{ "phone": string }`, plus `"password": string`.
  - The web sends `email` when the text has an `@`.
  - Otherwise it sends `phone`, normalised to E.164 (`0770 999 9999` → `+9647709999999`).
- **Returns** the app's `AuthPayload`: `data.user` and the tokens (`accessToken`, `refreshToken`, and `expiresIn` or `accessTokenExpiresAt`).
  - The web reads these fields from `user`: `id`, `fullName`, `email`, `phone`, `role`.
- **Errors:**
  - Wrong login or password: `401`.
  - The account is not an admin: `403 AUTHORIZATION_ERROR`. The web says "Admins only".

**Today:** the mock checks no password and keeps no token. Tokens, refresh and sign-out are Future (§5).

### 3.2 Dashboard

#### `GET /admin/dashboard`: Built

Used by: **Dashboard**. It could instead be worked out from the list endpoints; this one call is simpler.

**Returns:**

```ts
{
  storesWaiting: number            // PENDING stores
  productsWaiting: number          // PENDING products
  stores: number                   // every store, any status
  products: number                 // every product except drafts
  orders: number                   // every order
  ordersByStatus: Partial<Record<OrderStatus, number>>
  recentOrders: AdminOrder[]       // the 5 newest, by placedAt
  waitingLongest: Waiting[]        // the 4 longest waiting, oldest first
}

interface Waiting {
  kind: 'store' | 'product'
  id: string
  name: string                     // store: storeName; product: nameEn
  nameAr?: string                  // product: nameAr
  owner: string                    // store: the owner's fullName; product: its store's name
  imageUrl?: string                // store: logoUrl; product: imageUrl
  since: string                    // store: submittedAt; product: createdAt
}
```

### 3.3 Approval queue

#### `GET /admin/queue`: Built (the app has it; see §6.1)

Used by: **Approval queue**, and the menu's count on every page.

**Returns:**

```ts
{
  stores: AdminStore[]      // PENDING, oldest submittedAt first
  products: AdminProduct[]  // PENDING, oldest createdAt first
}
```

Answering is done with the store and product endpoints below. The queue and the sheets both call them.

### 3.4 Stores

#### `GET /admin/stores?status=&q=&phoneVerified=`: Built

Used by: **Stores**.

- **`status`** (optional): `PENDING`, `APPROVED`, `REJECTED`, `SUSPENDED` or `CLOSED`.
- **`q`** (optional) matches `storeName`, the owner's `fullName`, `phone`, `email`, `businessAddress`, and the governorate in either language.
- **`phoneVerified`** (optional): `false` lists only stores whose owner's number was never checked; the counts follow it, as they follow `q`.
- **Returns** `{ items: AdminStore[], counts }`.
  - `items` are newest `submittedAt` first.
  - `counts` has the keys `all`, `PENDING`, `APPROVED`, `REJECTED`, `SUSPENDED` and `CLOSED`.

#### `GET /admin/stores/{id}`: Built

Used by: the **Store** sheet.

- **Returns** `AdminStore`.
- **Errors:** 404.

#### `POST /admin/stores/{id}/approve`: Built (the app has it; see §6.2)

Used by: **Approval queue** and the **Store** sheet, after the admin confirms.

- **Body:** none.
  - `ADMIN_REQUIREMENTS.md` allows an optional `{ reason }`; the web sends none.
- **Allowed from:** `PENDING`. Otherwise `409`.
- **Sets:** `status: APPROVED`, `answeredAt: now`.
- **The store is told** in a notification, as the app's demo does.
- **Returns** `AdminStore`.

#### `POST /admin/stores/{id}/reject`: Built (the app has it; see §6.2)

Used by: **Approval queue** and the **Store** sheet.

- **Body:** `{ "reason": string }`, required. Blank: `422`, `errors.reason`.
- **Allowed from:** `PENDING`. Otherwise `409`.
- **Sets:** `status: REJECTED`, `rejectionReason`, `answeredAt: now`.
- **The store is told**, with the reason.
- **Returns** `AdminStore`.

#### `POST /admin/stores/{id}/suspend`: Built

Used by: the **Store** sheet.

- **Body:** `{ "reason": string }`, required (422 if blank).
- **Allowed from:** `APPROVED`. Otherwise `409`.
- **Sets:** `status: SUSPENDED`, `suspensionReason`.
- **Its products leave the shop** until it is reactivated. It also leaves the featured rail (§3.9).
- **Returns** `AdminStore`.

#### `POST /admin/stores/{id}/unsuspend`: Built

Used by: the **Store** sheet.

- **Body:** none.
- **Allowed from:** `SUSPENDED`. Otherwise `409`.
- **Sets:** `status: APPROVED`, and clears `suspensionReason`.
- **Its approved products come back** to the shop.
- **The store is told** it is active again, in its own words ("Your store is active again"), not "Your store is approved" (decided 2026-09-26).
- **Why not reuse `/approve`:** that would send the store "Your store is approved" again.
- **Returns** `AdminStore`.

#### `POST /admin/stores/{id}/deletion`: Built

Used by: the **Store** sheet ("Delete account"). For an owner who asked support to delete their account (Google Play's deletion page points to support).

- **Body:** none.
- **Allowed from:** any status, once. Already asked (by the owner in the app, or by Saba), or already `CLOSED`: `409`.
- **Does what the owner's own button does:** the store closes now and gets `deletionRequestedAt`. It is deleted within the hour once it has no open orders or returns, its last return window has passed and every bill is paid; then it is `CLOSED`.
- **The owner is told** in the app ("Your store's account is being deleted"), so an owner who never asked can cancel it there.
- **Returns** `AdminStore`.

#### `POST /admin/stores/{id}/free-number`: Built

Used by: the **Store** sheet ("Free this number"), shown only when `phoneVerified` is `false`. For a number held by the wrong person, signed up while SMS codes were off (2026-10-01).

- **Body:** `{ reason }`: Saba's note, kept in the audit (`NUMBER_FREE`).
- **The owner is suspended at once** (signed out, can't sign in, so can't cancel), **and the store's deletion starts**, as `/deletion` does. The number is free once the store closes: at the next hourly run when nothing is left to finish.
- **A checked number** (`phoneVerified: true`): `409`, never freed this way. A `CLOSED` store: `404`.
- **Returns** `AdminStore`.

### 3.5 Products

#### `GET /admin/products?status=&q=&categoryId=&storeId=`: Built

Used by: **Products**, and the **Store** sheet (with `storeId`, to list that store's products).

- **`status`** (optional): `PENDING`, `APPROVED`, `REJECTED` or `TAKEN_DOWN`.
  - `TAKEN_DOWN` means `takenDown: true`.
  - `APPROVED` means approved and not taken down.
- **`q`** (optional) matches `nameEn`, `nameAr` and the store's name.
- **`categoryId`** (optional) matches the category itself, or any sub-category under it.
- **`storeId`** (optional): that store's products only.
- **`DRAFT` is never listed.** A draft has not been sent yet, so it belongs to its store alone.
- **Returns** `{ items: AdminProduct[], counts }`.
  - `items` are newest `createdAt` first.
  - `counts` has the keys `all`, `PENDING`, `APPROVED`, `REJECTED` and `TAKEN_DOWN`. Each product counts once: a taken-down one only under `TAKEN_DOWN`.

#### `GET /admin/products/{id}`: Built

Used by: the **Product** sheet.

- **Returns** `AdminProduct`.
- **Errors:** 404.

#### `POST /admin/products/{id}/approve`: Built (the app has it; see §6.2)

Used by: **Approval queue** and the **Product** sheet, after the admin confirms.

- **Body:** none.
- **Allowed from:** `PENDING`. Otherwise `409`.
- **Refused if `nameAr` is blank:** `422 BUSINESS_RULE_ERROR`, `errors.nameAr`.
- **Sets:** `status: APPROVED`, and clears `rejectionReason`.
- **The store is told.**
- **Returns** `AdminProduct`.

#### `POST /admin/products/{id}/reject`: Built (the app has it; see §6.2)

Used by: **Approval queue** and the **Product** sheet.

- **Body:** `{ "reason": string }`, required.
- **Allowed from:** `PENDING`.
- **Sets:** `status: REJECTED`, `rejectionReason`.
- **The store is told**, with the reason.
- **Returns** `AdminProduct`.

#### `POST /admin/products/{id}/hide`: Built

Used by: **Products** and the **Product** sheet.

- **Body:** `{ "reason": string }`, required.
- **Allowed from:** `APPROVED` and not taken down.
- **Sets:** `takenDown: true`, `takenDownReason`.
- **The store can't put it back** with its own switch (`isActive`); only Saba can (§6.8).
- **It leaves search, its category and its store's page.** The store keeps its copy and is told why.
- **Returns** `AdminProduct`.

#### `POST /admin/products/{id}/unhide`: Built

Used by: **Products** and the **Product** sheet.

- **Body:** none.
- **Allowed from:** `takenDown: true`.
- **Sets:** `takenDown: false`, and clears `takenDownReason`.
- **Returns** `AdminProduct`.

#### `GET /categories`: Built (the app's own route)

Used by: **Products** (the category filter).

**Returns** the tree the app already reads:

```ts
interface Category {
  id: string
  name: string                     // English
  nameAr: string
  imageUrl?: string
  parentId?: string                // optional: the nesting is what matters
  children: Category[]
}
```

### 3.6 Orders

**Read-only.** Only a store moves an order along; Saba never changes an order.

#### `GET /admin/orders?status=&q=`: Built

Used by: **Orders**, and the **Dashboard**'s status rows (which open Orders already filtered).

- **`status`** (optional): one status, or several separated by commas, e.g. `CONFIRMED,PROCESSING,SHIPPED`. The web's filter groups send several.
- **`q`** (optional) matches:
  - `orderNumber`, `customerName` and `customerPhone`
  - the store names
  - every item's `productName` and `productNameAr`
  - the delivery governorate, in either language
- **Returns** `{ items: AdminOrder[], counts }`.
  - `items` are newest `placedAt` first.
  - `counts` is per `OrderStatus`, plus `all`.

#### `GET /admin/orders/{id}`: Built

Used by: the **Order** sheet. It opens from Orders, the Dashboard, a Customer, Cancellations & returns and a Return.

- **Returns** `AdminOrder`. `timeline` and `storeParts` are required here: support calls each store's driver.
- **Errors:** 404.

### 3.7 Finance

**The rule** is the app's own (`MockApiInterceptor._bill`, the "What you owe Saba" screen). A bill is per store, per calendar month:

- **`sales`**: the store's delivered goods, less its own discount, for orders delivered in the month. The delivery fee is the store's own and is not counted.
- **`returned`**: cash the store handed back on returns refunded in the month.
- **`owed`**: 0 if `sales − returned ≤ 0`. Otherwise `round((sales − returned) × ratePercent / 100 / 250) × 250`, i.e. to the nearest 250 IQD.
  - A month whose refunds are bigger than its sales owes 0, and the difference is not carried to another month (decided 2026-09-27).
- **`ratePercent`** is 8 in v1, the same for every store.

**Bill status:**

- `OPEN`: the month under way.
- `NONE`: a closed month with nothing owed.
- `PAID`: Saba recorded the payment.
- `DUE`: any other closed month.

```ts
type BillStatus = 'OPEN' | 'DUE' | 'PAID' | 'NONE'

interface Bill {
  month: string                    // the first day, a plain date: "2026-08-01" (§6.3)
  orderCount: number               // orders delivered in the month
  sales: number
  returned: number
  owed: number
  status: BillStatus
  paidAt?: string                  // web-only; set only when PAID. The web shows the day.
}

interface FinanceStore {
  id: string
  storeName: string
  logoUrl?: string
  governorate: Governorate
  status: StoreStatus
}
```

**Stores in Finance:** those that can sell, or did. That is `APPROVED` and `SUSPENDED` stores, and a `CLOSED` one that delivered something, so its paid months stay in the totals. A store whose owner asked for deletion is deleted only once every bill is paid: its last month's bill is due when the month ends and is marked paid as any other; there is no "write off".

**Months in Finance:** from the first month anything was delivered, up to this month, newest first.

#### `GET /admin/finance?month=&paid=`: Built

Used by: **Finance**.

- **`month`** (required): `YYYY-MM`, or `past` for every closed month added up.
- **`paid`** (optional):
  - `DUE`: rows with `stillOwed > 0`.
  - `PAID`: rows whose `status` is `PAID`.

**Returns:**

```ts
{
  ratePercent: number
  months: string[]                 // every month as its first day ("2026-09-01"), newest first; the first is this month
  thisMonth: { month: string; orderCount: number; sales: number; owed: number }  // every store, so far
  lastMonth: { month: string; owed: number; collected: number; stillOwed: number }
  rows: FinanceRow[]               // filtered by `paid`; most still owed first, then most owed
  counts: { all: number; PAID: number; DUE: number }  // every store, `paid` ignored
  totals: { owed: number; paid: number; stillOwed: number }  // over `rows`
}
```

```ts
interface FinanceRow {
  store: FinanceStore
  orderCount: number
  sales: number
  returned: number
  owed: number
  paid: number                     // of owed, what is PAID
  stillOwed: number                // of owed, what is DUE
  status: BillStatus
  paidAt?: string                  // one month only
}
```

- **`thisMonth`** and **`lastMonth`** cover every store.
  - `lastMonth.collected` is the sum of its `PAID` bills.
  - `lastMonth.stillOwed` is the sum of its `DUE` bills.
- **With one month**, a row is that month's bill.
- **With `past`**, a row adds up every closed month:
  - `status` is `DUE` if anything is still owed, else `PAID` if anything was owed, else `NONE`.
  - `paidAt` is not sent.
- **`counts.PAID`** counts rows whose `status` is `PAID`.
- **`counts.DUE`** counts rows with `stillOwed > 0`.
- **`lastMonth`** is the calendar month before this one.
- **Errors:** `422`, `errors.month`, for a month later than this one or not written `YYYY-MM`.

#### `GET /admin/stores/{id}/bills`: Built

Used by: the **Bills** sheet.

- **Returns:**

  ```ts
  {
    store: FinanceStore
    ratePercent: number
    bills: Bill[]                  // this month, and every month with a delivery or a refund since the store was approved; newest first (§6.6)
    stillOwed: number              // the sum over DUE bills
  }
  ```

- **Errors:** 404 if the store is not approved or suspended.

#### `POST /admin/stores/{id}/bills/{month}/paid`: Built

Used by: the **Bills** sheet ("Mark as paid").

- **Body:** `{ "paidAt": "YYYY-MM-DD" }`, the day the money came in.
- **Pays the whole month.** Partial payments are Future (§5).
- **Allowed if:** the bill is `DUE`. Otherwise `409`. Two marks at the same moment pay it once; the other gets `409`.
- **The day must be:** on or after the first day of the next month, and not after today (Baghdad's calendar). Otherwise `422`, `errors.paidAt`. The bill is checked first, then the day.
- **`404`** if the store is not approved or suspended, or the month is later than this one.
- **Returns** the `Bill`, now `PAID`, with `paidAt` as a date-time for that day: 12:00 in Baghdad.

#### `DELETE /admin/stores/{id}/bills/{month}/paid`: Built

Used by: the **Bills** sheet ("Mark as not paid"), for a month marked paid by mistake.

- **Body:** none.
- **Allowed if:** the bill is `PAID`. Otherwise `409`.
- **Returns** the `Bill`, now `DUE`, with no `paidAt`.
- **Kept:** the server records who undid it, when, and what the payment said (the amount, the day, who marked it).

### 3.8 Support tickets

These are the app's own tickets (`features/support`). In the app, each account sees only its own; the admin sees everyone's.

```ts
type TicketStatus = 'OPEN' | 'IN_PROGRESS' | 'WAITING_FOR_CUSTOMER' | 'RESOLVED' | 'CLOSED'
type TicketCategory = 'ORDER' | 'PAYMENT' | 'DELIVERY' | 'RETURN' | 'PRODUCT' | 'ACCOUNT' | 'OTHER'
type OpenedBy = 'SHOPPER' | 'STORE'
```

**`WAITING_FOR_CUSTOMER`** means waiting for whoever opened the ticket. The web shows "Waiting for shopper" or "Waiting for store" from `openedBy.kind`.

**A reply from whoever opened the ticket** (the app's `POST /support/tickets/{id}/messages`) moves `WAITING_FOR_CUSTOMER` or `RESOLVED` back to `OPEN`, and sets `updatedAt`. A `CLOSED` ticket takes no replies from either side until Saba opens it again (§6.10).

```ts
interface TicketMessage {
  id: string
  body: string
  sentAt: string
  isFromCustomer: boolean          // false: Saba's answer
  authorName?: string              // for the customer's messages; Saba's are unsigned and shown as "Saba support"
}

interface Ticket {
  id: string
  reference: string                // "T-5011"
  subject: string
  category: TicketCategory
  status: TicketStatus
  createdAt: string
  updatedAt: string                // the last message, or the last status change
  lastMessage: string
  openedBy: { kind: OpenedBy; name: string; phone: string; storeId?: string }  // web-only; storeId for a store's ticket
  messages: TicketMessage[]        // oldest first
}

type TicketRow = Omit<Ticket, 'messages'> & { messageCount: number }
```

#### `GET /admin/tickets?status=&openedBy=`: Built

Used by: **Support**, and the menu's count of open tickets on every page (`status=OPEN`).

- **Both filters are optional.**
- **Returns:**

  ```ts
  {
    items: TicketRow[]                         // newest updatedAt first
    counts: { all; OPEN; IN_PROGRESS; … }     // by status, within `openedBy`; `status` ignored
    byOpener: { SHOPPER: number; STORE: number } // within `status`; `openedBy` ignored
  }
  ```

#### `GET /admin/tickets/{id}`: Built

Used by: the **Ticket** sheet.

- **Returns** `Ticket`.
- **Errors:** 404.

#### `POST /admin/tickets/{id}/messages`: Built

Used by: the **Ticket** sheet (Reply).

- **Body:** `{ "body": string }`, required, at most 4,000 characters. Blank: `422`, `errors.body`.
- **Refused on a `CLOSED` ticket:** `409`.
- **Adds** `{ isFromCustomer: false }` with no `authorName`, and sets `updatedAt: now` and `lastMessage`.
- **Which admin wrote it** is kept by the server but not sent: Saba's answers are unsigned. Showing it belongs with staff accounts (Future).
- **Whoever opened the ticket is notified** ("Saba support answered you"; a tap opens the ticket).
- **Returns** `Ticket`.

#### `POST /admin/tickets/{id}/status`: Built

Used by: the **Ticket** sheet (the Status menu, and "Close ticket").

- **Body:** `{ "status": TicketStatus }`.
- **Any status to any other.** A closed ticket can be opened again.
- **The same status again:** `409`.
- **Sets** `updatedAt: now`.
- **Whoever opened the ticket is notified**, in words for each status ("Saba support is waiting for your answer."). The server keeps who changed it and when.
- **Returns** `Ticket`.

### 3.9 Featured stores

The "Featured stores" rail on the app's home screen. Saba chooses which approved stores appear, and in what order.

#### `GET /admin/featured-stores`: Built

Used by: **Featured stores**.

**Returns:**

```ts
{
  stores: AdminStore[]   // every APPROVED store
  featured: string[]     // the rail's store ids, in order; approved stores only
}
```

#### `PUT /admin/featured-stores`: Built

Used by: **Featured stores** (Save).

- **Body:** `{ "storeIds": string[] }`, the whole rail in order. It may be empty.
- **Refused (`409`) if:** an id repeats, or a store is not `APPROVED`. The store may have changed status while the admin was editing.
- **A suspended store** that was featured keeps its place at the end of the rail. It comes back when the store is reactivated.
- **Returns** the same shape as the `GET`.

**For the app:** Home's stores section shows only these stores, in this order. **With none featured, there is no rail:** `/home/sections` leaves the section out (§6.11).

### 3.10 Cancellations and returns

**Read-only.** Shoppers and stores handle these in the app.

```ts
type ReturnStatus = 'REQUESTED' | 'APPROVED' | 'REJECTED' | 'REFUNDED' // the four v1 uses (§6.7)

interface AfterSale {             // one line: a cancelled store part (Q7), or a return
  id: string                      // the store part's id, or the return's; unique with kind
  kind: 'CANCELLED' | 'RETURNED'
  orderId: string                 // opens the order
  orderNumber: string
  item: { productName: string; productNameAr?: string; imageUrl?: string }  // the part's (or return's) first line
  more: number                    // how many more lines
  storeId: string
  storeName: string
  buyer: string                   // the shopper's name
  reason: string                  // a code, §2.1: the shopper's own cancel reason, or the store's decline code
  by: 'SHOPPER' | 'STORE'         // who cancelled (CUSTOMER_CANCELLED on the part is the shopper); a return is always SHOPPER
  returnStatus?: ReturnStatus     // returns only
  value: number                   // cancelled: that part's subtotal − discount; return: refundAmount
  at: string                      // cancelled: the part's cancelledAt; return: requestedAt
}
// A shopper cancelling a two-store order gives two lines. A part refused at the door is neither, and is not listed.
```

#### `GET /admin/after-sales?kind=&days=`: Built

Used by: **Cancellations & returns**.

- **`kind`** (optional): `CANCELLED` or `RETURNED`.
- **`days`** (optional): `7`, `30` or `90`, counted back from now on `at`. Without it: all time.
- **Returns:**

  ```ts
  {
    items: AfterSale[]           // filtered by kind and days; newest at first
    counts: { all: number; CANCELLED: number; RETURNED: number; openReturns: number }
    value: number
  }
  ```

- **`counts` and `value`** cover the period, whatever the `kind`.
  - `openReturns` counts returns that are `REQUESTED` or `APPROVED`.
  - **`value` leaves out `REJECTED` returns:** the shopper kept the item, so nothing was lost.

#### `GET /admin/returns/{id}`: Built

Used by: the **Return** sheet.

- **Returns:**

  ```ts
  interface AdminReturn {
    id: string
    orderId: string
    orderNumber: string
    status: ReturnStatus
    requestedAt: string
    reason: string                 // ReturnReason code
    merchantId: string
    merchantName: string
    customerName: string
    customerNameAr?: string
    items: {
      productName: string
      productNameAr?: string
      imageUrl?: string
      quantity: number
      unitPrice: number            // what the shopper paid for one, after the store's coupon: the lines add up to refundAmount (decided 2026-09-27)
      variantLabel?: string        // D19
    }[]
    refundAmount: number
    answeredAt?: string            // web-only: when the store approved or declined it
    refundedAt?: string            // set once REFUNDED: when the store handed the cash back
    description?: string           // D19: the shopper's own words
    rejectionReason?: string       // D19: the store's code when REJECTED: USED, INCOMPLETE, NOT_AS_SAID, OTHER
    timeline: { status: ReturnStatus; occurredAt: string }[]  // D19: its steps, oldest first
    photos: string[]               // D19: always [] in v1
    refund?: { amount: number; status: 'PENDING' | 'COMPLETED'; processedAt?: string }  // D6; none when REJECTED
  }
  ```

- **Errors:** 404.

### 3.11 Customers

These are the app's shoppers (`User` with role `CUSTOMER`). An order finds its shopper by phone today (see `customerId` in §5).

```ts
type CustomerStatus = 'ACTIVE' | 'SUSPENDED'  // the app's AccountStatus

interface Customer {
  id: string
  fullName: string
  fullNameAr: string               // web-only
  phone: string
  phoneVerified: boolean           // false: signed up while SMS codes were off, the number never checked (2026-10-01)
  governorate: Governorate
  status: CustomerStatus
  suspensionReason?: string        // web-only
  joinedAt: string                 // the app's createdAt
  orderCount: number               // every order they placed, any status
  spent: number                    // the amountDue of their DELIVERED store parts (delivery included), less refundAmount of their REFUNDED returns (Q7)
}
// A deleted account is not listed, counted or found: it has no name or number left (decided 2026-09-27). fullNameAr is '' when none was given.

interface CustomerAddress {        // the app's Address
  id: string
  label: string                    // "Home", "Work", or as typed
  fullName: string
  phone: string
  governorate: Governorate
  area: string
  areaAr?: string                  // web-only
  street?: string
  streetAr?: string                // web-only
  landmark: string
  landmarkAr?: string              // web-only
  isDefault: boolean
}

interface CustomerDetail extends Customer {
  addresses: CustomerAddress[]     // the default first
  orders: AdminOrder[]             // newest placedAt first
}
```

#### `GET /admin/customers?q=&status=&phoneVerified=`: Built

Used by: **Customers**.

- **`q`** (optional) matches `fullName`, `fullNameAr`, the home area in either language, the governorate in either language, and the phone (as §1.7).
- **`phoneVerified`** (optional): `false` lists only shoppers whose number was never checked; the counts follow it, as they follow `q`.
- **Returns** `{ items: Customer[], counts }`.
  - `items` are newest `joinedAt` first.
  - `counts` has the keys `all`, `ACTIVE` and `SUSPENDED`.

#### `GET /admin/customers/{id}`: Built

Used by: the **Customer** sheet. It opens from Customers, and from an Order ("Customer details").

- **Returns** `CustomerDetail`.
- **Errors:** 404.

#### `POST /admin/customers/{id}/suspend`: Built

Used by: the **Customer** sheet.

- **Body:** `{ "reason": string }`, required.
- **Allowed from:** `ACTIVE`.
- **Sets:** `status: SUSPENDED`, `suspensionReason`.
- **They can no longer sign in or order** (`AccountStatus.canUseApp`). Their orders so far stay as they are.
- **Every sign-in they had ends:** lifting the suspension later brings none of them back; they sign in again.
- **The reason is Saba's own note.** The shopper is not shown it.
- **Returns** `Customer`.

#### `POST /admin/customers/{id}/unsuspend`: Built

Used by: the **Customer** sheet.

- **Body:** none.
- **Allowed from:** `SUSPENDED`.
- **Sets:** `status: ACTIVE`, and clears `suspensionReason`.
- **Returns** `Customer`.

#### `DELETE /admin/customers/{id}`: Built

Used by: the **Customer** sheet ("Delete account"). For a shopper who asked support to delete their account (Google Play's deletion page points to support).

- **Body:** none.
- **Does what the shopper's own delete does, now:** their name, number, email, addresses, cart and wishlist go, and every sign-in ends. Their orders keep their own copy of the name, number and address they went to. They leave the Customers list.
- **Refused while an order is open:** `409`, naming the orders ("Order SB-100231 is still open. The account can be deleted once it is finished.").
- **Active or suspended shoppers only;** anyone else, or an account already deleted: `404`. A store owner's account goes with its store (`POST /admin/stores/{id}/deletion`).
- **Returns** `{}`.

#### `POST /admin/customers/{id}/free-number`: Built

Used by: the **Customer** sheet ("Free this number"), shown only when `phoneVerified` is `false`. For a number held by the wrong person, signed up while SMS codes were off (2026-10-01).

- **Body:** `{ reason }`: Saba's note, kept in the audit (`NUMBER_FREE`).
- **Deletes the shopper's account, as `DELETE` does,** so the number's owner can sign up with it. Refused while an order is open (`409`, as `DELETE`).
- **A checked number** (`phoneVerified: true`): `409`, never freed this way.
- **Returns** `{}`.

### 3.12 Reported reviews

Shoppers can report a store's review from the app, and since 2026-10-01 stores can too, a review about themselves included. Each reported review comes here with its reports, so a report always reaches someone: the app stores check this (decided before launch, 2026-09-29). One report per person and review: sent again while open, it stays as it was; sent again after Saba closed it, it opens again with the new words.

```ts
type ReviewReportStatus = 'OPEN' | 'DISMISSED' | 'REMOVED'
type ReportReason = 'COUNTERFEIT' | 'PROHIBITED' | 'MISLEADING' | 'OFFENSIVE' | 'SPAM' | 'OTHER'

interface ReportedReview {
  id: string                       // the review
  status: ReviewReportStatus       // REMOVED once removed; OPEN while a report waits; else DISMISSED
  store: { id: string; storeName: string }
  rating: number                   // 1–5
  body?: string                    // the review's words
  authorName?: string              // left out for a deleted account
  createdAt: string
  removedAt?: string
  lastReportedAt: string
  reports: {                       // newest first
    id: string
    reason: ReportReason
    description?: string           // the reporter's words
    reporterName?: string          // left out for a deleted account
    reporterRole: 'CUSTOMER' | 'MERCHANT'   // since 2026-10-01: stores report reviews too
    createdAt: string
    status: ReviewReportStatus
  }[]
}
```

#### `GET /admin/review-reports?status=&page=&perPage=`: Built

Used by: **Reported reviews**.

- **`status`** (optional): `OPEN`, `DISMISSED` or `REMOVED`.
- **Returns one page** (§1.3, since 2026-10-01): `data` is `{ items: ReportedReview[], counts }`, the latest report first, and `meta` is `{page, perPage, total, totalPages}`. `counts` has `all` and each status present, `status` ignored, the same on every page. Without `page`: page 1 of 50.

#### `POST /admin/review-reports/{id}/remove`: Built

- **Body:** none. `id` is the review's.
- **Removes the review:** it leaves the store's page and the store's rating; its open reports close as `REMOVED`. Kept in the server's audit (`REVIEW_REMOVE`).
- **Already removed:** `409`. Unknown: `404`.
- **Returns** `ReportedReview`.

#### `POST /admin/review-reports/{id}/dismiss`: Built

- **Body:** none.
- **Closes the review's open reports as `DISMISSED`**; the review stays. Kept in the audit (`REVIEW_REPORTS_DISMISS`).
- **Nothing open** (or the review was removed): `409`.
- **Returns** `ReportedReview`.

A new report, a removal and a dismissal tell admins' live streams `reviews` (§5).

### 3.13 Reports: products, stores and chats

Shoppers and stores report a product, a store or a chat from the app (Apple 1.2 and Google require it; reviews have their own reports, §3.12). Saba sees them grouped by what they are about. It acts with the tools it already has, then closes the reports:
- a product: take it down (§3.5);
- a store: suspend it (§3.4);
- a chat's shopper: suspend them (§3.11).

```ts
type ReportTarget = 'PRODUCT' | 'STORE' | 'CONVERSATION'
type ReportStatus = 'OPEN' | 'DISMISSED' | 'ACTIONED'   // ACTIONED: "handled"
type ReportReason = 'COUNTERFEIT' | 'PROHIBITED' | 'MISLEADING' | 'OFFENSIVE' | 'SPAM' | 'OTHER'

interface ReportedItem {
  id: string                  // the target: "PRODUCT-12", "STORE-3", "CONVERSATION-40"
  type: ReportTarget
  targetId: string
  status: ReportStatus        // OPEN while a report waits; else how the last one was closed
  title: string               // the product's name, the store's name, or "Shopper name · Store name"
  product?: { id: string; name: string; status: string; takenDown: boolean }
  store?: { id: string; storeName: string; status: string }   // a product's store, the store, or a chat's store
  customer?: { id: string; fullName: string }                 // a chat's shopper; left out for a deleted account
  lastReportedAt: string
  reports: {
    id: string
    reason: ReportReason
    description?: string
    reporterName?: string     // left out for a deleted account
    reporterRole: 'CUSTOMER' | 'MERCHANT'
    createdAt: string
    status: ReportStatus
    evidence?: {                // a chat report: its last 20 messages, oldest first, as they were when reported
      from: 'CUSTOMER' | 'STORE'
      body: string              // '' for a photo
      sentAt: string
      messageId?: string        // since 2026-10-01: for "Remove photo"
      photoUrl?: string         // a chat photo, signed for Saba, good for one to two hours: show it as an image
      photoRemoved?: 'ACCOUNT' | 'SABA'  // ACCOUNT: its sender deleted their account (photoUrl still opens while this report is open); SABA: Saba removed it
    }[]
  }[]                         // newest first
}
```

#### `GET /admin/reports?status=&type=&page=&perPage=`: Built

Used by: **Reports**.

- **`status`** (optional): `OPEN`, `DISMISSED` or `ACTIONED`. **`type`** (optional): `PRODUCT`, `STORE` or `CONVERSATION`.
- **Returns one page** (§1.3, since 2026-10-01): `data` is `{ items: ReportedItem[], counts }`, the latest report first, and `meta` is `{page, perPage, total, totalPages}`.
  - `counts` has `all` and one key per status present, within `type`, the same on every page.
  - `total` counts the targets matching `type` and `status`. Without `page`: page 1 of 50.

#### `POST /admin/reports/{type}/{targetId}/dismiss`: Built

- **Closes the target's open reports as `DISMISSED`**: nothing needed doing. Audit `REPORTS_DISMISS`.
- **Nothing open:** `409`. **No reports for it at all, or an unknown type:** `404`.
- **Returns** `ReportedItem`.

#### `POST /admin/reports/{type}/{targetId}/resolve`: Built

- **Closes the target's open reports as `ACTIONED`**, once Saba has acted. Audit `REPORTS_RESOLVE`. Same refusals as dismiss.
- **Returns** `ReportedItem`.

A new report after closing opens the target again, whether from someone new or from the same person (whose report then opens again with the new words, since 2026-10-01). A new report, a dismissal and a resolve tell admins' live streams `reports` (§5).

#### `POST /admin/messages/{messageId}/remove-photo`: Built

Used by: **Reports**, beside a photo in a chat's evidence (since 2026-10-01: shoppers and stores send photos in chats).

- **Body:** none. **Removes the photo** from the chat for both sides ("removed by Saba") and deletes its file. Audit `CHAT_PHOTO_REMOVE`.
- **Already removed:** `409`. Not a photo, or unknown: `404`.
- **Returns** `{}`. The evidence then shows `photoRemoved: 'SABA'` and no `photoUrl`.
- A deleted account's photos are removed by themselves; while a report is open they stay in its evidence (`photoRemoved: 'ACCOUNT'` with a `photoUrl`), and go once it is closed.

### 3.14 Categories, Home banners and brands

**Built (2026-10-01).** Until now these changed only in the database, and the live database starts with the 13 categories (no pictures), no banners and no brands. The user's decisions:
- **A category** is either **hidden** or **deleted**. Hidden: it leaves Home, Browse, the filters and the stores' category picker, but its products stay on sale and in search, and a product already in it may keep it. Deleted: only once it has no sub-categories, and its products are first moved to a category Saba picks. They move as they are: same status, no second review.
- **Two levels only:** a category and its sub-categories.
- **A brand** deleted moves its products to another checked brand or to no brand, as they are.
- **Stores pick a brand or type one.** A typed name that isn't on the list becomes a new brand (`PENDING`). It is checked with the product: approving the product approves the brand, and so does Saba saving the brand. Shoppers' Brands filter shows only brands of listed products, so only checked ones.
- **A banner** has a picture, optional words (each in both languages or neither), a link (a product, a store, a category or nothing) and on/off. Home shows the ones that are on, in Saba's order. One whose link opens nothing any more (the product taken down or not listed, the store not approved, the category hidden or deleted) is left off Home, and Saba's list marks it `linkBroken`. No banners: Home has no banner section.
- **Pictures** are uploaded first with `POST /media/upload` (now open to admins too); a save sends the upload's `url`. A picture must be an admin's upload, or the one the row already has.
- Every change here writes `admin_actions`.

```ts
interface AdminCategory {
  id: string
  name: string; nameAr: string
  imageUrl: string | null
  parentId: string | null      // null: top level
  hidden: boolean
  productCount: number         // its own products, deleted ones left out
  children: AdminCategory[]    // a top-level category's sub-categories; [] on a sub-category
}
interface AdminBanner {
  id: string
  imageUrl: string | null      // only old demo banners have none
  titleEn: string | null; titleAr: string | null
  subtitleEn: string | null; subtitleAr: string | null
  link: { type: 'PRODUCT' | 'STORE' | 'CATEGORY'; id: string; name: string | null } | null
  isActive: boolean
  linkBroken: boolean          // Home leaves it off
}
interface AdminBrand {
  id: string
  name: string; nameAr: string | null   // a typed brand has no Arabic name until Saba saves it
  status: 'APPROVED' | 'PENDING'        // PENDING: typed by a store, not checked yet
  productCount: number
}
```

#### Categories: Built

- **`GET /admin/categories`** returns `AdminCategory[]`: the top level in Saba's order, each with its sub-categories, hidden ones included, deleted ones not.
- **`POST /admin/categories`** `{ name, nameAr, parentId: string | null, imageUrl: string | null }` adds one last on its level and returns it. Shoppers see it and stores can pick it at once.
  - `parentId` must be a top-level category (else `422 parentId`: two levels).
  - A name its level already has, in either language and whatever its case: `422 name` or `nameAr`.
- **`PATCH /admin/categories/{id}`** takes any of `{ name, nameAr, parentId, imageUrl, hidden }`; what it leaves out stays.
  - A new `parentId` puts it last on that level. A category with sub-categories can't go under another.
  - New names or a new level reach its products' search at once.
  - `hidden` hides or shows it.
- **`POST /admin/categories/order`** `{ parentId: string | null, ids: string[] }` sets one level's order, first to last, and returns the whole `AdminCategory[]`. `ids` must be every category on that level, each once: else `409` (the page is out of date).
- **`DELETE /admin/categories/{id}?moveTo={categoryId}`** returns `{ moved: number }`.
  - With sub-categories: `409`.
  - With products and no `moveTo`: `409`, whose message says how many products. `moveTo` must be another live category (else `422 moveTo`).
  - The row stays in the database, deleted, for the deleted products that still name it.

#### Home banners: Built

- **`GET /admin/banners`** returns `AdminBanner[]` in Home's order, off ones included.
- **`POST /admin/banners`** `{ imageUrl, titleEn, titleAr, subtitleEn, subtitleAr, link: { type, id } | null, isActive }` adds one last and returns it.
  - `imageUrl` is required. The words may be null, each pair in both languages or neither (`422` on the missing one).
  - A link to something shoppers can't open now: `422 link`.
- **`PUT /admin/banners/{id}`**, same body, changes one; its place stays.
- **`POST /admin/banners/order`** `{ ids }` sets Home's order, every banner once (else `409`), and returns `AdminBanner[]`.
- **`DELETE /admin/banners/{id}`** removes one.

#### Brands: Built

- **`GET /admin/brands?q=&status=&page=&perPage=`** is one page (§1.3) of `{ items: AdminBrand[], counts }`: new ones (`PENDING`) first, then by name. `q` matches either name; `counts` has `all`, `APPROVED` and `PENDING`.
- **`POST /admin/brands`** `{ name, nameAr }` adds a checked brand. A name any brand has, in either language: `422 name` or `nameAr`.
- **`PUT /admin/brands/{id}`** `{ name, nameAr }` renames it (its products show the new name at once) and marks a new one checked.
- **`DELETE /admin/brands/{id}?moveTo={brandId|none}`** returns `{ moved: number }`. With products and no `moveTo`: `409`. `moveTo` must be another checked brand, or `none`.

The **product sheet's** `brand` (§3.5) also says `nameAr` and `isNew`: a typed brand waiting for its check.

---

## 4. Every endpoint at a glance

| Method | Path | Status | Used by |
|---|---|---|---|
| POST | `/auth/login` | Built (mock) | Sign-in |
| GET | `/admin/dashboard` | Built | Dashboard |
| GET | `/admin/queue` | Built | Approval queue; the menu count |
| GET | `/admin/stores` | Built | Stores |
| GET | `/admin/stores/{id}` | Built | Store sheet |
| POST | `/admin/stores/{id}/approve` | Built | Approval queue, Store sheet |
| POST | `/admin/stores/{id}/reject` | Built | Approval queue, Store sheet |
| POST | `/admin/stores/{id}/suspend` | Built | Store sheet |
| POST | `/admin/stores/{id}/unsuspend` | Built | Store sheet |
| POST | `/admin/stores/{id}/deletion` | Built | Store sheet |
| GET | `/admin/products` | Built | Products, Store sheet |
| GET | `/admin/products/{id}` | Built | Product sheet |
| POST | `/admin/products/{id}/approve` | Built | Approval queue, Product sheet |
| POST | `/admin/products/{id}/reject` | Built | Approval queue, Product sheet |
| POST | `/admin/products/{id}/hide` | Built | Products, Product sheet |
| POST | `/admin/products/{id}/unhide` | Built | Products, Product sheet |
| GET | `/categories` | Built | Products |
| GET | `/admin/orders` | Built | Orders, Dashboard |
| GET | `/admin/orders/{id}` | Built | Order sheet |
| GET | `/admin/finance` | Built | Finance |
| GET | `/admin/stores/{id}/bills` | Built | Bills sheet |
| POST | `/admin/stores/{id}/bills/{month}/paid` | Built | Bills sheet |
| DELETE | `/admin/stores/{id}/bills/{month}/paid` | Built | Bills sheet |
| GET | `/admin/tickets` | Built | Support; the menu count |
| GET | `/admin/tickets/{id}` | Built | Ticket sheet |
| POST | `/admin/tickets/{id}/messages` | Built | Ticket sheet |
| POST | `/admin/tickets/{id}/status` | Built | Ticket sheet |
| GET | `/admin/featured-stores` | Built | Featured stores |
| PUT | `/admin/featured-stores` | Built | Featured stores |
| GET | `/admin/after-sales` | Built | Cancellations & returns |
| GET | `/admin/returns/{id}` | Built | Return sheet |
| GET | `/admin/customers` | Built | Customers |
| GET | `/admin/customers/{id}` | Built | Customer sheet |
| POST | `/admin/customers/{id}/suspend` | Built | Customer sheet |
| POST | `/admin/customers/{id}/unsuspend` | Built | Customer sheet |
| DELETE | `/admin/customers/{id}` | Built | Customer sheet |
| GET | `/admin/review-reports` | Built | Reported reviews |
| POST | `/admin/review-reports/{id}/remove` | Built | Reported reviews |
| POST | `/admin/review-reports/{id}/dismiss` | Built | Reported reviews |
| GET | `/admin/reports` | Built | Reports |
| POST | `/admin/reports/{type}/{targetId}/dismiss` | Built | Reports |
| POST | `/admin/reports/{type}/{targetId}/resolve` | Built | Reports |
| GET | `/admin/categories` | Built | Categories |
| POST | `/admin/categories` | Built | Categories |
| PATCH | `/admin/categories/{id}` | Built | Categories |
| POST | `/admin/categories/order` | Built | Categories |
| DELETE | `/admin/categories/{id}` | Built | Categories |
| GET | `/admin/banners` | Built | Banners |
| POST | `/admin/banners` | Built | Banners |
| PUT | `/admin/banners/{id}` | Built | Banners |
| POST | `/admin/banners/order` | Built | Banners |
| DELETE | `/admin/banners/{id}` | Built | Banners |
| GET | `/admin/brands` | Built | Brands |
| POST | `/admin/brands` | Built | Brands |
| PUT | `/admin/brands/{id}` | Built | Brands |
| DELETE | `/admin/brands/{id}` | Built | Brands |
| POST | `/media/upload` | Built | Categories, Banners (pictures) |

---

## 5. Future

These are in `TODO.md` and not built in the web. The routes come from `ADMIN_REQUIREMENTS.md` §3 where it names one. Shapes are to be agreed before building.

### Needed as soon as there is a real backend

- **Tokens.** `POST /auth/refresh { refreshToken }` and `POST /auth/logout`, as the app uses them.
  - Every `/admin` call carries the token.
  - A `401` refreshes the token once, then sends the admin to sign-in.
  - Today the web keeps no token.
- **Paging.** `page` and `perPage` on every list, answered with `meta` (§1.3). The web pages the six lists (ea5ee37); Reports pages on the server since 2026-10-01.
- **Live updates.** The event channel in `BACKEND_READY.md` (`/ws` or `/events`, `{ "topic": "…" }`).
  - Today a screen refreshes only after the admin's own actions.
  - Topics the admin needs: `stores`, `products`, `orders`, `tickets`, `returns`, `bills`, `customers`.
  - **Built in the backend:** `GET /events`, Server-Sent Events, opened with the access token in the `Authorization` header (so the web reads it with `fetch`, not `EventSource`). One `data: {"topic": "orders", "id": "12"}` line per change an admin's pages show, sent after it is saved; a comment line every 25 seconds. The stream ends when the access token does: refresh it and open the stream again, then reload what is on screen.
- **`customerId` on every order.** Today the web finds the shopper by phone.
- **A record of who did what.** For every admin action: who, when, and the reason.
  - This includes undoing a payment.
  - It needs staff accounts: more than one admin, each signed in as themselves.

### Features not in this version

- **Partial payments.** Several payments per bill, each with an amount and a day, and a month that is partly paid. Perhaps `POST /admin/stores/{id}/bills/{month}/payments { amount, paidAt }`.
  - The web marks only a whole month paid, because the app knows only Due and Paid.
- **Home banners.** `GET/POST/PUT/DELETE /admin/banners`.
  - Each banner has a picture, a title and subtitle in both languages, where it leads, an order, and start and end dates.
  - The admin may also want to see the flash sales running.
- **Rule pages.** `GET/PUT /admin/legal/{page}` for `terms`, `privacy` and `returns`, each in both languages, with a "last updated" date.
- **Category management.** Create, rename, reorder and retire categories, with their pictures. A category with products in it cannot be deleted until they are moved.
- **Cities.** The list of governorates stores can deliver to.
- **Analytics.** Growth over time, top stores, top products, orders per city.
- **Admin notifications.** Announcements to shoppers or stores.
- **The commission rate.** One Saba-wide setting, with the date it starts from. It is 8% today.
- **Delivery companies and tracking numbers.**
  - In v1 each store delivers with its own driver, and names them (name and phone) when it ships.
  - The app already has `courierType: COMPANY` and `trackingNumber`. v1 does not use them, and the web shows neither.
- **Re-review after an edit.** Not decided. Nothing here depends on it.

---

## 6. Where the web and the app differ today

The app's demo server already answers some of these routes, or sends the same data in another shape. For each conflict, one side has to change.

### 6.1 `GET /admin/queue`: product shape (decided, done in the app)

**Decided:** the queue returns full `AdminProduct` records, with both `nameEn` and `nameAr`, and `AdminStore` records for stores (§3.3). An admin approving a product has to see what shoppers will see in either language.

- **The app's demo server does this** (mobile commit `f480d88`): full `AdminProduct` and `AdminStore` records, oldest first. Nothing under `/admin` is translated: the admin gets both names whatever language it asks in.
- **Its demo admin screen** shows a product in both languages.

### 6.2 Approve and reject (decided, done in the app)

**Decided:** reject takes `{ "reason": string }`, required, and keeps it as `rejectionReason` on the store or product. The store's notification carries it. A reject with no reason tells the store nothing. Approve and reject both return `AdminStore` or `AdminProduct` (§3.4, §3.5).

- **The app's demo server does this** (mobile commit `f480d88`):
  - reject requires the reason, trimmed; blank is `422`, `errors.reason`;
  - it keeps it as `rejectionReason` and puts it in the store's notification ("Reason: …");
  - answering twice is `409`, and approving a product with no Arabic name is `422`, `errors.nameAr`;
  - both answers return the full record, and errors carry the §1.4 codes.
- **In the app:** the demo admin screen asks why before rejecting. The store's product row and its "not approved" banner show Saba's reason.

### 6.3 A bill's `month` (decided)

**Decided:** every response writes a month as its first day, a plain date with no time: `"2026-08-01"`. That covers `Bill.month`, and `months`, `thisMonth.month` and `lastMonth.month` in `/admin/finance`. `/merchants/me/bills` does the same. Bills also have `PAID` and `paidAt`.

- **Paths and queries** name a month as `YYYY-MM`: `/admin/finance?month=2026-08`, `/admin/stores/{id}/bills/2026-08/paid`. Only the web builds these.
- **The web** keeps the first 7 characters of a month it reads (`"2026-08"`).
- **The app does not change.** It reads `month` with `DateTime.tryParse`, which reads `"2026-08-01"` as 1 August, the same as the `"2026-08-01T00:00:00.000"` its demo sends today. It shows "Paid" for any status but `DUE`, and it does not read `paidAt`.
- **Why not `"2026-08"`:** the app cannot read it (`tryParse` gives nothing), and would fall back to January 1970 without an error.
- **Why no time:** a UTC moment such as `"2026-07-31T21:00:00Z"` is 1 August in Baghdad but July to any reader that does not convert it. A plain date cannot slip into the wrong month.
- **`NONE`** (a closed month with nothing owed): the app shows "Paid" for it today. A small change in the app gives it its own label (not part of this contract).

### 6.4 Who delivers an order (decided)

**Decided:** the app's shape. Each order has `storeParts`, one per store, each with `merchantId`, `amountDue`, `status`, `courierName` and `courierPhone` (§2, `OrderStorePart`). An order from two stores can have two drivers. There is no single `courier` on the order.

- **`courierType` and `trackingNumber`** stay out of v1: delivery companies are Future (§5).
- **The web reads it this way:** its order sheet shows one driver per store part, named by store when an order has more than one.

### 6.5 Seeded demo data

The two demos have to show the same thing: the same stores, orders, bills, returns, drivers and shoppers. The mismatches left are listed in `TODO.md` under "Open questions". They are about demo data only, not about the contract.

### Decided 2026-09-25 (`PRE_BACKEND_AUDIT.md`)

Six decisions from the audit. This contract already describes the decided shape. Where the web's mock or the app still does it the old way, that is listed under each one: "web" and "app" are what has to change before the backend is used.

### 6.6 Which months a store's bills list (D4)

**Decided:** this month, and every month since the store was approved in which it delivered something **or** refunded something. A month with only a refund stays, so the refund is still taken off. No empty months from before the store existed.

- **Backend:** `GET /admin/stores/{id}/bills` and `GET /merchants/me/bills` both follow this rule.
- **Web:** nothing to change in the screens. Its mock lists every month since Saba's first delivery (`finance.ts`, `months()`).
- **App:** its demo lists only months with a delivery (`_sabaBills`). The screen needs no change.

### 6.7 Return statuses (D18)

**Decided:** v1 uses four: `REQUESTED`, `APPROVED`, `REJECTED`, `REFUNDED`. The store collects the item and hands the cash back in one visit, so there is no pickup, received or refund-pending step.

- **Backend:** sends only these four.
- **Web:** nothing to change.
- **App:** nothing to change. It keeps reading `PICKUP`, `RECEIVED`, `REFUND_PENDING` and `CLOSED`, and its demo never sends them.

### 6.8 "Taken down" by Saba, not "hidden" (D22)

**Decided:** Saba's own takedown is `takenDown` and `takenDownReason`. `isActive` stays the store's own on/off switch, the one the app's "Hide" button sets. A taken-down product is out of the shop whatever `isActive` says, and the store can't put it back; only Saba can.

- **Routes:** the paths stay `POST /admin/products/{id}/hide` and `/unhide`. Only the fields and the filter's value change (`TAKEN_DOWN`, §3.5).
- **Web:** rename `hidden`, `hiddenReason` and the `HIDDEN` filter in `types.ts`, `products.ts` and the screens that read them.
- **App:**
  - The store's product row shows "Taken down by Saba" with the reason.
  - Its Hide / Show switch is off for such a product.
  - The shop leaves it out.
  - Today it sends `hidden: false` (`_adminProduct`).

### 6.9 No `UNDER_REVIEW` (D-S1)

**Decided:** v1 has no `UNDER_REVIEW`. A store waiting for Saba is `PENDING`. Add it back only when a real step needs it (for example, "Saba asked for documents").

- **Web:** remove it from `StoreStatus` (`types.ts`) and from the store filters (`stores.ts`), and from the store badge's wording.
- **App:**
  - Remove `MerchantStatus.underReview` (`features/auth/domain/entities.dart`).
  - Remove its case on the store's account screen (`merchant_account_screen.dart`).
  - Remove it from the demo's `_waiting`.

### 6.10 A customer's reply reopens a ticket (D-T2)

**Decided:** a reply from whoever opened the ticket moves `WAITING_FOR_CUSTOMER` or `RESOLVED` back to `OPEN` (§3.8). A `CLOSED` ticket takes no replies.

- **Backend:** does this on `POST /support/tickets/{id}/messages`.
- **Web:** nothing to change. Its list is newest activity first, so a reopened ticket comes to the top.
- **App:** nothing for the screens. If its demo should show it, the demo's reply handler moves the status the same way. It never changes a ticket's status today.

### 6.11 Featured stores on Home (D28)

**Decided:** Home's stores section shows only the stores Saba featured, in Saba's order. With none featured there is no rail at all: `/home/sections` leaves the section out, rather than sending it empty.

- **Web:** nothing to change. It already warns before saving an empty rail.
- **App:**
  - **City chips (done in the app).** Home used to take its city chips from the stores in this same section (`home_screen.dart`, `cities`), so they would have lost cities and disappeared with the rail. They now come from their own route, `GET /stores/cities` (below).
  - **Empty section.** The app draws a heading over an empty rail if the section comes with no stores (`_MerchantCarousel`). With the section left out, that can't happen.
  - **The demo** (`_home`) now lists only the featured stores (every demo store to start) and leaves the section out when there are none.

#### `GET /stores/cities`: the app's route

Used by: the app's Home, for the city chips under the search bar (`storeCitiesProvider`). The admin web doesn't call it.

- **Returns** `Governorate[]`: each governorate with at least one open, approved store, once, in the app's order of governorates (`Governorate.values`, the biggest cities first). For example `["BAGHDAD", "BASRA"]`.
  - **Approved:** a store that is `PENDING`, `REJECTED` or `SUSPENDED` doesn't count.
  - **Open:** the store's own switch (`isOpen`) is on.
  - **A store's city** is its current `governorate`, so a store that moves city moves its chip.
- **Featured doesn't matter:** the list is the same whether a store is on the rail or not, and when there is no rail.
- **An empty list:** the app shows no chips.

### 6.12 Changes the app needs, in one place

For the mobile session, from §6.6–6.11:

| Decision | Change in the app | Needed |
|---|---|---|
| D22 | Read `takenDown` / `takenDownReason`; show it on the store's product row; lock the store's switch; leave it out of the shop | yes |
| D-S1 | Remove `UNDER_REVIEW` from `MerchantStatus`, the account screen and the demo | yes |
| D28 | City chips from their own source (`GET /stores/cities`); the demo's Home lists featured stores and leaves the section out when there are none | yes |
| D4 | The demo's bills list months with a delivery or a refund, since approval | demo only |
| D-T2 | The demo's ticket reply reopens a waiting or resolved ticket | demo only |
| D18 | nothing | no |
