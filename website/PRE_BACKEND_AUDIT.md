# Saba admin web: pre-backend audit

Written 2026-09-25, before the backend is built. It covers two things:

1. **Every fake thing in the admin web.** Each part works today only because the data is mock data. For each one: what it is, where it is, and what the backend has to provide instead.
2. **Every place where the admin web and the mobile app disagree.** Where the same data has two shapes or two rules, one of them has to win before the backend is built, or it gets built twice.

**How this was checked.** By reading code, not documents:

- the web's mock data (`website/src/data/*.ts`);
- the app's models and JSON readers (`mobile/lib/features/*`);
- the app's endpoint list (`core/config/api_endpoints.dart`);
- its network layer (`core/network/`, `core/errors/`);
- its demo server (`core/mock/mock_api_interceptor.dart`, `mock_data.dart`).

It was checked against `BACKEND_READY.md`, `PROJECT_MAP.md` and `website/API_CONTRACT.md`. App line numbers are as of commit `fcc459e`.

**Where the web stands:** `API_CONTRACT.md` describes every endpoint the web calls. This document is what that contract gets wrong, or leaves out, once the app is compared with it.

---

## Part 1. What is fake in the admin web

Everything below lives in `website/src/data/`. The screens never read anything else. Replacing the mock means replacing the body of each data function with a real request, as `API_CONTRACT.md` says. What follows is what that replacement has to bring with it.

### 1.1 The mock layer itself

| # | What is fake | Where | What the backend must provide |
|---|---|---|---|
| F1 | **The network.** Every answer waits 350–700 ms and comes back as a copy. `?mockError` on any page fakes a failure. | `mock.ts`, `reply()` | Real HTTP, with the envelope and error codes of `API_CONTRACT.md` §1.2–1.4. The web has to map real errors to its codes (`ErrorCode` in `mock.ts`). |
| F2 | **The database.** Every record is a variable in memory. A page reload puts everything back to how it started. | module-level arrays in every data file (`STORES`, `PRODUCTS`, `RETURNS`, `PAID`, …) | Storage that lasts. |
| F3 | **Sign-in.** No password is checked and no token is kept. The one admin is written into the code, and the "session" is that admin saved in `localStorage`. | `auth.ts` (`ADMIN`, `signIn`, `currentAdmin`) | `/auth/login` returning tokens, then `/auth/refresh` and `/auth/logout`, with every `/admin` call carrying the token. See D1: a non-admin is refused differently from what the contract says. |
| F4 | **Freshness.** After its own write, the web reloads everything on screen (`refreshAll`). It never hears about anyone else's change. | `lib/use-query.ts` | The event channel in `BACKEND_READY.md` (`/ws` or `/events`). Topics the admin needs: `stores`, `products`, `orders`, `returns`, `tickets`, `bills`, `customers`. Until then, polling every 30 seconds. |
| F5 | **Paging.** Every list returns every row. The largest has 117. | every `list…` function | `page` / `perPage` / `meta` (§1.3). See D30: the app always sends `page`. |
| F6 | **Search.** Done in the browser: lower-casing, a few Arabic letter folds, and phone digits matched without `0` / `964`. | `mock.ts` (`matches`, `fold`), `customers.ts` (`phoneMatches`), `stores.ts` | Server-side search exactly as §1.7 describes, with the app's full Arabic folding (`mobile/lib/core/utils/`). |
| F7 | **Status counts** on the filter chips. The browser counts them. | `countBy` in `mock.ts` | `counts` in every list response (§1.2). |
| F8 | **Dates.** Every seeded date is relative to now (`daysAgo`, `Date.now()`), so the demo moves forward a day every day. | all seed data | Real timestamps. |
| F9 | **Which month a sale falls in** is decided in the browser's own time zone. | `finance.ts` (`monthOf`, `startOf`) | Asia/Baghdad (UTC+3) on the server. See D5. |
| F10 | **Ids.** A shopper's id is made from the last 7 digits of their phone (`cu-5550142`): two phones ending alike would collide. Ticket messages get ids made up in the browser. | `people.ts:23` (`customerIdOf`), `tickets.ts` | Real ids, and `customerId` on every order (D14). |

### 1.2 Numbers the browser works out, which the server must work out

| # | Number | Where | Backend |
|---|---|---|---|
| F11 | Dashboard: counts, orders by status, recent orders, "waiting longest" | `dashboard.ts` | `GET /admin/dashboard`, or the list endpoints' `counts` and `meta.total` |
| F12 | Every bill: 8% of delivered sales less refunds, to the nearest 250 IQD; the months; this month and last month; paid and still owed | `finance.ts` | `GET /admin/finance` and `GET /admin/stores/{id}/bills`, worked out from real orders and refunds. See D3–D7 for the rule. |
| F13 | The commission rate, written into the code as `8` | `finance.ts:14` (`RATE_PERCENT`) | Send `ratePercent` (the app already reads it from `/merchants/me/bills`). |
| F14 | Payments recorded on bills: a map in memory, with the older months paid on made-up days | `finance.ts` (`PAID` and the block marked web-only demo) | Stored payments, each with a day and who recorded it (the record of who did what: Future). |
| F15 | A shopper's order count and total spent, and their orders, found by **phone** | `customers.ts` (`withTotals`, `getCustomer`) | Worked out on the server by `customerId` (D14). |
| F16 | A store's `productCount` | `stores.ts` | Counted on the server, drafts left out. |
| F17 | Cancellations and returns: the list, the counts, and the value lost (declined returns left out) | `returns.ts` (`afterSales`, `listAfterSales`) | `GET /admin/after-sales` |
| F18 | The approval queue, oldest first | `queue.ts` | `GET /admin/queue`. The app answers it already. |

### 1.3 Rules only the mock enforces

The server has to refuse each of these itself. The web's checks are only there to help the admin.

| # | Rule | Where in the web |
|---|---|---|
| F19 | Reject, suspend and hide need a reason. A blank one, or only spaces, is refused, and the reason is stored trimmed. | `requireReason` in `mock.ts` |
| F20 | A product can't be approved without an Arabic name. | `products.ts`, `approveProduct` |
| F21 | Each action is allowed only from the right state, otherwise `409`: approve and reject only while waiting; suspend only when approved; unsuspend only when suspended; hide only an approved product that isn't hidden; mark paid only a closed, due month; undo only a paid one. | `change()` in `stores.ts`, `products.ts`, `customers.ts`; `finance.ts` |
| F22 | The day a bill was paid has to fall after the month ended and not after today, counted by the calendar day. | `finance.ts`, `markBillPaid` |
| F23 | A ticket reply can't be blank. A closed ticket takes no replies until it is opened again. | `tickets.ts` |
| F24 | Only approved stores can be featured. A suspended one drops off the rail until it is reactivated. | `featured.ts` |

### 1.4 What an admin action should cause, which the mock only claims

The web changes its own record and nothing else. The backend has to make each of these happen:

| # | Admin action | What must follow | Today in the app |
|---|---|---|---|
| F25 | Suspend a store | Its products leave the shop, search, carts and Home. It can't take orders. It is told why. | Nothing sets `SUSPENDED` (D26) |
| F26 | Suspend a shopper | They can't sign in or order (`AccountStatus.canUseApp`). They are told why. | `canUseApp` is defined (`features/auth/domain/entities.dart:46`) and used nowhere |
| F27 | Hide a product | It leaves the shop. The store keeps its copy and is told why. | No hide route; `hidden` is always `false` |
| F28 | Choose the featured stores | Home's "Featured stores" rail shows them, in that order | Home lists every store (D28) |
| F29 | Mark a bill paid, or undo it | The store's "What you owe Saba" shows it (the app shows "Paid" for any status but `DUE`) | The app never receives `PAID` (D3) |
| F30 | Reply to a ticket, or change its status | The customer sees the reply and is notified | Each account sees only its own tickets; there is no admin route |
| F31 | Approve or reject | The store is notified, with the reason | **Done in the app** (§6.2) |
| F32 | Every action | A record of who did it, when, and why | Future: needs staff accounts |

### 1.5 Pictures and fixed lists

| # | What | Where | Backend |
|---|---|---|---|
| F33 | Product photos: one file per category, served by the web itself | `public/demo/products/*.jpg`, `photoFor` in `products.ts` | URLs from the media store (`/media/upload`) |
| F34 | Store logos and banners | `public/demo/stores/` | The same |
| F35 | The seven categories, written into the code | `categories.ts` | `GET /categories` (the app's route). Category management is Future. |
| F36 | `currencyCode: "IQD"` and the "Cash on delivery" label | `orders.ts` | From the order (see D8) |

### 1.6 Demo data the app does not have

Everything marked `// web-only demo` in the code. None of it may reach a real database; it is listed so nobody copies it into a seed without meaning to.

| File | Web-only demo data |
|---|---|
| `stores.ts` | Owners for stores m-3 to m-8, application dates, the waiting and rejected stores, the suspended store with its reason (33 marks) |
| `products.ts` | The five products waiting in the queue (`p-new-1` to `p-new-5`) |
| `orders.ts` | The eight cancelled orders (`SB-180001` on). The app's seed has no cancelled orders. |
| `returns.ts` | Returns still requested, approved or declined. The app seeds only refunded ones (`_historyReturnsOf`). |
| `tickets.ts` | Eleven tickets. The app's seed has none (`_tickets` starts empty, `mock_api_interceptor.dart:255`). |
| `customers.ts` | Rana Salman (no orders yet), Sara's second address, Hussein Karim suspended, and the Arabic name of Amina Saleh, the app's demo shopper |
| `finance.ts` | The months already marked paid |

**Not committed:** the new product list (`products.ts`, `types.ts`, `detail-sheets.tsx`) is waiting for the mobile session to confirm Atlas's August bill is 68,750. The tables above describe the files as they are on disk.

**Now matching the app, and left off the list above:** the order history, each store's delivery fee on seeded orders, the drivers, and no tracking numbers. The app has since matched the web on all of these (`_history`, `_seededPart`, `_storeDrivers` in `mock_api_interceptor.dart`). `TODO.md` "Open questions" still lists some of them; they can come off it.

---

## Part 2. Where the web and the app disagree

**Already decided,** in `API_CONTRACT.md` §6:

- 6.1: the queue sends full records;
- 6.2: reject takes a reason;
- 6.3: a bill's month is written as its first day;
- 6.4: one driver per store part.

6.1 and 6.2 are done in the app. The items below are new.

For each one, the table gives what the web expects, what the app has, and a recommendation for which should win.

- **App** means the web changes. **Web** means the app, or the backend's shape, changes.
- **Decide** means it is a product question for you, not a technical one.

### 2.1 Sign-in, errors, lists

| # | Subject | The web expects | The app has | Should win |
|---|---|---|---|---|
| D1 | **A non-admin signing in** | `POST /auth/login` answers `403 AUTHORIZATION_ERROR` for any account that isn't an admin (`API_CONTRACT.md` §3.1) | The same route signs in shoppers and stores. It can't refuse them. | **App.** Login succeeds and returns `user.role`. The web refuses anything but `ADMIN` itself and signs out, and every `/admin` route answers `403` to a non-admin. Fix §3.1. |
| D29 | **Error bodies** | Every error has `code` (§1.4) | The demo's `403` for a non-admin has only `message`, and its `404`s have an empty body (`mock_api_interceptor.dart:676-678, 743, 779, 795`) | **Web.** The backend always sends `code`. The app handles both, since it falls back to the HTTP status (`error_mapper.dart:71-87`). |
| D30 | **Paging** | Sends no `page` and expects every row (§1.3) | Always sends `page` and `perPage` (`api_client.dart:158-172`). Reads `meta.page`, `perPage`, `total`, `totalPages`, flat or under `meta.pagination`. | **Both work** if the backend follows §1.3: no `page` means every row. Once lists grow, the web should page too. |

**Checked and matching:**

- The envelope `{success, message, data, meta}`.
- Lists as `data.items`: the app reads `data` as an array, or `items` / `results` / `records` / `rows` inside it (`api_response.dart:129-146`), so the web's `{items, counts}` works for both.
- Field errors as a map (the app also accepts a list).
- Error codes: the app's are a superset of the web's.

### 2.2 Stores

| # | Subject | The web expects | The app has | Should win |
|---|---|---|---|---|
| D23 | **Open or closed** | Nothing. "In the shop" (`detail-sheets.tsx:284-291`) says yes for a closed store's products. | A store closes itself (`/merchants/me/store/open`). Its products leave the shop (`_closedStores`; `isOpen` on the store, `mock_api_interceptor.dart:1842`). | **App.** Add `isOpen` to `AdminStore`. The web shows "Closed by its owner", and "In the shop" checks it. |
| D24 | **What `/admin` sends for a store** | The full `AdminStore`: owner, email, address, description, logo, banner, rating, review count, delivery | `_adminStore` (`mock_api_interceptor.dart:636-656`) leaves out email, address, description, logo, banner and rating, and sends `reviewCount: 0`. It knows only stores that signed up in the app, and counts only products added in the app. | **Web.** The backend sends the full record for every store. |
| D24b | **A store's description in Arabic** | `description` only | `descriptionAr` beside it (`mock_data.dart:217`) | **App.** The admin gets both (§1.6). Add `descriptionAr`. |
| D26 | **Suspension** | Stores and shoppers get suspended, with a reason, and it has effects (F25, F26) | Nothing sets `SUSPENDED`, and nothing enforces it. `_adminProduct` sends the store's status as its review status, or `APPROVED`. | **Web.** Build suspension as F25 and F26 describe. |
| D-S1 | **`UNDER_REVIEW`** | Shown and filtered as waiting | Counted as waiting (`_waiting`, `mock_api_interceptor.dart:799`). Nothing sets it. | **Decided:** dropped for v1, `PENDING` only; it comes back only if a real step needs it. **The web and the app both change** (§6.9). |

**Checked and matching:** `StoreStatus` values, `rejectionReason`, `answeredAt`, `submittedAt`, delivery terms (`governorates`, `feeInside`/`feeOutside`, `timeInside`/`timeOutside`), the approve and reject routes, `409` on answering twice, and `422 errors.reason`.

### 2.3 Products

| # | Subject | The web expects | The app has | Should win |
|---|---|---|---|---|
| D21 | **Fields the admin route leaves out** | `nameEn`/`nameAr`, `description`, `warranty` | Products carry `descriptionAr`, `warrantyAr`, `sku`, `barcode`, `saleEndsAt`, and on options `sku`, `originalPrice`, `discountPercentage`, `imageUrl`. `_adminProduct` (`mock_api_interceptor.dart:582-633`) drops them all. | **App.** Add `descriptionAr`, `warrantyAr` and `sku` (the admin reads both languages and needs a code to talk to the store), plus `saleEndsAt` and the option fields. |
| D21b | **Flash sales** | `price` and `originalPrice` read as a normal discount | During a flash sale, `price` **is** the sale price, `originalPrice` is the price before it, and `saleEndsAt` says until when (`BACKEND_READY.md`) | **App.** With `saleEndsAt` the web can say "Flash sale until …". Without it, the admin takes a one-day price for the real one. |
| D22 | **"Hidden" means two things** | `hidden`: Saba took the product out of the shop, with `hiddenReason` | In the store's app, "hide" is the store's own switch: `isActive: false`, `/merchants/me/products/{id}/visibility`, `MockData.seededHidden` | **Decided:** Saba's is `takenDown` / `takenDownReason`; `isActive` stays the store's. **The web and the app both change** (§6.8). |
| D-P1 | **What "in the shop" means** | Approved, switched on, not hidden, store approved (`inShop`, `detail-sheets.tsx:284`) | The same, and also the store is open (D23), with stock handled per option | **App.** One rule, on the server. Send `inShop: boolean` with the reason, rather than each side working it out. |

**Checked and matching:** `ProductStatus`, `StockStatus`, low stock under 6, `rejectionReason`, `categoryName` / `categoryNameAr`, `brand`, `images`, `merchant`, `isActive`, `422 errors.nameAr` without an Arabic name, and categories (`id`, `name`, `nameAr`, `children`).

### 2.4 Orders

| # | Subject | The web expects | The app has | Should win |
|---|---|---|---|---|
| D8 | **Cash on delivery** | `isCashOnDelivery: boolean` | Works it out from `paymentMethodType: "COD"` (or `paymentType`, `CASH_ON_DELIVERY`), `orders_repository_impl.dart:37-44`. The demo sends `paymentMethodType: "COD"`. | **App.** Send `paymentMethodType`. The web reads it instead. |
| D9 | **Where a store's part has got to** | `storeParts[].status` | The shopper's reader ignores a part's `status` (`orders_repository_impl.dart:90-98`) and keeps a status on each **line** (`items[].status`). The demo writes both (`mock_api_interceptor.dart:4879`). | **Web.** One status per store part. The app reads it there, and line statuses go. |
| D10 | **`NEW` or `PENDING`** | `PENDING` on `/admin` | The store's own record says `NEW` (`mock_api_interceptor.dart:4866`). The shopper's says `PENDING`. The app reads both as the same. | **Web.** Store `PENDING` only. "New" is only the store screen's word for it (`PROJECT_MAP.md` §7). |
| D11 | **Which option was bought** | `OrderItem` has no option | Lines carry `variantId`, `variantLabel` ("Blue / 256GB") and `sku` (`mock_api_interceptor.dart:3180-3186`) | **App.** Add `variantLabel` and `sku` to the web's `OrderItem`. Support has to know which phone was sent. |
| D12 | **One line, two shapes** | `productName`, `productNameAr`, `unitPrice`, `lineTotal` | The shopper's order sends those names. The store's order sends `name`, `nameAr`, `price` and no `lineTotal` (`_seededPart`, `mock_api_interceptor.dart:5130-5139`). The app reads either. | **Web.** The backend sends one line shape everywhere. `productNameAr` isn't web-only any more: the shopper's order sends it (`mock_api_interceptor.dart:3184`). |
| D13 | **The shopper's phone on a store's order** | E.164, `+9647705550142` (§1.5) | Formatted for display, `+964 770 555 0142` (`customerPhone: displayPhone`, `mock_api_interceptor.dart:5208`) | **Web.** E.164 on the wire. Each screen formats it. |
| D14 | **Which shopper placed an order** | Found by phone; the contract asks for `customerId` | Found by `customerEmail` (`mock_api_interceptor.dart:3307, 4977`). A shopper who signed up by phone may have no email. | **Neither: `customerId`** on every order. |
| D15 | **Arabic on an order** | None | The store's order sends `customerNameAr`, `areaAr`, `streetAr`, `landmarkAr`, `courierNameAr`, `paymentMethodLabelAr` (`mock_api_interceptor.dart:5201-5229`) | **App.** The admin reads both languages (§1.6). Add them to `AdminOrder`, `OrderAddress` and `OrderStorePart`. |
| D16 | **Delivery instructions** | `OrderAddress` has none | `instructions` on the address and the order (`orders_repository_impl.dart:200`) | **App.** Add `instructions`. The driver reads them, so support should too. |
| D7 | **Money per store** | One `subtotal`, `shipping`, `discount` per order. Each store part has only `amountDue`. | Each store's part has its own `subtotal`, `shipping` and `discount`: its own coupon only (`mock_api_interceptor.dart:2389-2390, 5193-5195`) | **App.** Add `subtotal`, `shipping` and `discount` to `OrderStorePart`. A two-store order needs them, and so do bills (D7b). |
| D-O1 | **`courierType`** | Out of v1 (§6.4) | The store's part sends `courierType: "DRIVER"` | **Either.** Harmless; the web ignores it. Keep `"DRIVER"` so delivery companies can come later. |

**Checked and matching:**

- `OrderStatus` values; `REFUSED`, `RETURNED` and `REFUNDED` are known to both.
- `PaymentStatus` values the web uses; the app knows more, and `PROCESSING`, `FAILED` and `PARTIALLY_REFUNDED` would show as unknown on the web.
- `itemCount` counts units.
- `placedAt`, `deliveredAt`, `orderNumber`, and the timeline fields.
- `storeParts` with `merchantId`, `amountDue`, `courierName`, `courierPhone`, `received`.
- The shopper's cancel reasons and the store's decline reasons.
- The drivers' names and phones: the same eight on both sides.

### 2.5 Bills

| # | Subject | The web expects | The app has | Should win |
|---|---|---|---|---|
| D2 | **The store's bills route** | `API_CONTRACT.md` §6.3 names it `/merchant/bills` | `/merchants/me/bills` (`api_endpoints.dart`) | **App.** A typo in the contract; fix §6.3. |
| D3 | **Bill statuses** | `OPEN`, `DUE`, `PAID`, `NONE`, and `paidAt` | Sends only `OPEN` and `DUE` (`mock_api_interceptor.dart:5707-5716`). Reads only whether it is `DUE`. | **Web.** The backend sends all four. The app already shows "Paid" for any status but `DUE`, and "Nothing to pay" when nothing is owed. |
| D4 | **Which months a store's bills list** | Every month from the first delivery anywhere until now. A month with nothing is `NONE`. | Only months in which the store delivered something (`_sabaBills`, `mock_api_interceptor.dart:5720-5725`) | **Decided:** months with a delivery or a refund, since the store was approved. The web's month picker keeps its own list across all stores (`API_CONTRACT.md` §6.6). |
| D5 | **Where a month starts** | The browser's time zone | The phone's time zone (`DateTime(month.year, month.month)`) | **Neither.** The server decides, in Asia/Baghdad. A delivery at `2026-08-31T22:00Z` belongs to September. |
| D6 | **The day a refund counts** | `refundedAt` at the top of the return | `refund.completedAt` inside the return (`mock_api_interceptor.dart:5686-5690`). The app's reader also takes `processedAt` or `refundedAt` there (`returns_repository_impl.dart:61-65`). | **App.** The refund is its own record, `refund: {amount, status, processedAt, …}`. The web reads the day from there. |
| D7b | **A store's sales** | For every delivered order holding one of the store's lines, the **whole order's** `subtotal - discount` (`finance.ts:83-87`) | Each store's **own part**: its `subtotal` less its own coupon (`_sales`, `mock_api_interceptor.dart:5663-5690`) | **App.** The web's rule only works because every demo order comes from one store: a two-store order would be billed to both stores in full. The bill comes from the server anyway (F12). |
| D-B1 | **The month written in a bill** | `"2026-08-01"` (decided, §6.3) | The demo still sends `"2026-08-01T00:00:00.000"`, local time (`mock_api_interceptor.dart:5703`) | **Decided.** The backend sends the plain date. The app reads both. |
| D-B2 | **The shape around the bills** | `/admin/stores/{id}/bills` gives `{store, ratePercent, bills[], stillOwed}` | `/merchants/me/bills` gives `{currencyCode, ratePercent, current, past[]}` | **Both.** Two routes for two readers is fine, as long as each bill in them has the same fields. |

**Checked and matching:** 8%, rounding to the nearest 250 IQD, the delivery fee left out of sales, and a month that is negative after refunds owes 0.

### 2.6 Returns

| # | Subject | The web expects | The app has | Should win |
|---|---|---|---|---|
| D18 | **Return statuses** | `REQUESTED`, `APPROVED`, `REJECTED`, `REFUNDED` | Also `PICKUP` (or `PICKUP_SCHEDULED`), `RECEIVED`, `REFUND_PENDING` and `CLOSED` (`features/returns/domain/entities.dart:16-24`) | **Decided:** v1 uses the four. The app keeps reading the others (§6.7). |
| D19 | **What the admin sees of a return** | Items, reason, refund amount, `answeredAt` | Also the shopper's own words (`description`), the store's reason for declining (`rejectionReason`), photos (`photos`), steps (`timeline`) and the option on each item (`variantLabel`), in `returns_repository_impl.dart:79-110` | **App,** for all five: support can't judge a dispute without them. `answeredAt` is web-only; the timeline can give it. |

**Checked and matching:** return reasons, the 7-day window, one store per return, and `refundAmount`.

### 2.7 Shoppers

| # | Subject | The web expects | The app has | Should win |
|---|---|---|---|---|
| D27 | **A shopper's statuses** | `ACTIVE`, `SUSPENDED` | `ACTIVE`, `INACTIVE`, `SUSPENDED`, `PENDING_VERIFICATION`, `DELETED` (`features/auth/domain/entities.dart:38-42`) | **App.** The web shows and filters all five. |
| D27b | **Where a shopper lives** | `governorate` | `User.city`, but `Address.governorate` | **Web.** `governorate` everywhere, one of the 19 values. |
| D27c | **Other fields** | `fullNameAr`, `joinedAt`, `suspensionReason`; no email | `User` has `email` (required), `avatarUrl`, `country`; no Arabic name, no date joined | **Both:** `fullNameAr`, `createdAt` and `suspensionReason` added to `User`; `email` optional, since a shopper can sign up with a phone only. |
| D16b | **An address** | `label`, `area`/`areaAr`, `street`/`streetAr`, `landmark`/`landmarkAr`, `isDefault` | `label`, `area`, `street`, `landmark`, `instructions`, `isDefault`, `latitude`, `longitude`; no Arabic | **Both:** the Arabic stays (the app's seed has it; `User` doesn't), and `instructions` is added (D16). |

### 2.8 Home and tickets

| # | Subject | The web expects | The app has | Should win |
|---|---|---|---|---|
| D28 | **The "Featured stores" rail** | Saba's list, in Saba's order (`PUT /admin/featured-stores`) | Home's `MERCHANT` section lists every store (`mock_api_interceptor.dart:2119-2124`). Nothing reads a featured list. | **Web.** `/home/sections` sends the featured stores, in order. **Decided:** with none chosen there is no rail; the section is left out. **The app changes:** its city chips come from this section today (§6.11). |
| D-T1 | **Who opened a ticket** | `openedBy {kind, name, phone, storeId}` | Nothing: each account sees only its own | **Web.** An admin route has to say who opened each ticket. |
| D-T2 | **A shopper replying to "Waiting for customer"** | The status stays until the admin changes it | Nothing moves a ticket's status | **Decided:** a reply from whoever opened it moves `WAITING_FOR_CUSTOMER` or `RESOLVED` back to `OPEN`. A closed ticket takes no replies (§6.10). |

**Checked and matching (tickets):** the five statuses, the seven categories, `reference`, `subject`, `createdAt`, `updatedAt`, `lastMessage`, and messages (`body`, `sentAt`, `isFromCustomer`, `authorName`).

---

## Part 3. What to fix in the documents

Once the decisions are made:

- **`API_CONTRACT.md`:**
  - §3.1 (D1);
  - §6.3's route name (D2);
  - add the fields the app wins on:
    - D7: per-part money;
    - D8: `paymentMethodType`;
    - D11: `variantLabel`, `sku`;
    - D15: the Arabic on orders;
    - D16: `instructions`;
    - D19: the return fields;
    - D21: product fields, `saleEndsAt`;
    - D23: `isOpen`;
    - D27: the shopper statuses.
- **`TODO.md`:**
  - Move `productNameAr` off "New fields": the app sends it now (D12).
  - Take the order history, seeded fees and drivers off "Open questions": the app has matched them.
- **The app** (for the mobile session):
  - D3, D9, D10 and D12, and suspension (D26);
  - Home's rail (D28);
  - a phone always in E.164 (D13).

---

## Summary

| | Count |
|---|---|
| Fake things in the web (Part 1) | 36, in six groups |
| Web and app disagreements (Part 2), beyond the four in §6 | 40 |
| Of those, the app's way should win | 16 |
| The web's way should win | 11 |
| Neither: a server rule (D5) or a new field (D14) | 2 |
| Both, or either, can stand | 5 |
| Already decided, not yet done in the app's demo (D-B1) | 1 |
| Your decision | 5: D4, D18, D22, D-S1, D-T2, and the question in D28. **All decided 2026-09-25** (below). |

The decisions are made. After them, the biggest risks for the backend are:

- **D7 / D7b, money per store part.** Without it, a two-store order would be billed to both stores in full.
- **D1, the admin sign-in.**
- **D14, `customerId`.**
- **D5, where a month starts.**

---

## Decided 2026-09-25

All six as recommended. The details, and what each side has to change, are in `API_CONTRACT.md` §6.6–6.12.

| # | Decision | The web changes | The app changes |
|---|---|---|---|
| D4 | A store's bills list this month, and every month with a delivery or a refund since the store was approved | mock only (`finance.ts`) | demo only (`_sabaBills`) |
| D18 | v1 uses four return statuses: `REQUESTED`, `APPROVED`, `REJECTED`, `REFUNDED` | no | no: it keeps reading the others |
| D22 | Saba's takedown is `takenDown` / `takenDownReason`; `isActive` stays the store's switch, and a taken-down product stays out of the shop whatever it says | **yes:** rename `hidden`, `hiddenReason`, the `HIDDEN` filter | **yes:** show it on the store's row, lock the store's switch, leave it out of the shop |
| D-S1 | No `UNDER_REVIEW` in v1; waiting is `PENDING` | **yes:** `StoreStatus`, the store filters | **yes:** `MerchantStatus.underReview`, the account screen, the demo's `_waiting` |
| D-T2 | A reply from whoever opened a ticket moves `WAITING_FOR_CUSTOMER` or `RESOLVED` back to `OPEN`; a closed ticket takes no replies | no | demo only |
| D28 | Home shows only the featured stores, in Saba's order; with none, the section is left out | no | **yes:** the city chips need their own source first; the demo's Home |

**Found while recording D28:** the app builds Home's city chips from the stores in the same section as the rail (`home_screen.dart`, `cities`). Before that section shows only the featured stores, the chips need a source of their own, or they lose cities and disappear with the rail.
