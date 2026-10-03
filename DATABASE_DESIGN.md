# Saba backend: database design

Written 2026-09-26, before any backend code, for review.

**Built from** what the two front-ends actually send and read, not from a generic marketplace:

- `website/API_CONTRACT.md` and `website/PRE_BACKEND_AUDIT.md`: every admin route and field, and the 40 decisions (D1…D30).
- `BACKEND_READY.md`, `PROJECT_MAP.md`, `ADMIN_REQUIREMENTS.md`, `BUGS.md`: the rules that live only there.
- The app's demo server, `mobile/lib/core/mock/mock_api_interceptor.dart`. It answers every shopper and store route today, so it is the app's half of the contract: "What the demo server does is the contract" (`PROJECT_MAP.md` §7). Function names in backticks below (`_buildCart`, `_bill`, …) are its.

**Scope:** version 1 only. Seven categories, cash on delivery, one commission rate, phone accounts, stores delivering with their own drivers. §9 lists what was left out on purpose and what would bring each part back.

Questions **Q1–Q13** are in `BACKEND_PLAN.md` §2, with the answers of 2026-09-26 (§2.0). Q7 is still open.

---

## 1. Ground rules

| Rule | Why |
|---|---|
| **MySQL 8.4 LTS**, InnoDB, `utf8mb4`, collation `utf8mb4_0900_ai_ci` for names and text. Nothing below needs 8.4 over 8.0, so it also runs on the 8.0.44 already installed (Q2). | 8.0 reached end of life in April 2026. 8.4 is the supported line. |
| **Lowercase `snake_case`** for every table and column name. | This Windows server runs with `lower_case_table_names=1`. Linux servers are case-sensitive. Lowercase names move between the two unchanged. |
| **Every key is `id BIGINT UNSIGNED AUTO_INCREMENT`**, sent to the clients as a string. | Contract §1.5: ids are strings. Neither front-end builds or parses an id: no demo id (`m-1`, `p-42`, `c-phones`) appears outside the two mocks (checked). Private records are protected by ownership checks, not by hard-to-guess ids. |
| **Money is `BIGINT`, whole Iraqi dinars**, `CHECK (x >= 0)`. Every price a store types, every fee and every fixed coupon is a multiple of 250 (`CHECK (x % 250 = 0)`). | Contract §1.5: integers, IQD. The 250 rule is the app's (`_notInCashSteps`, `_deliveryProblem`, `_couponProblem`): cash can't be paid below the smallest note. |
| **Moments are `DATETIME(3)` in UTC.** Every pooled connection runs `SET time_zone = '+00:00'` when it opens. | `TIMESTAMP` ends in 2038 and converts with the session's zone. Setting the zone per connection, in code, keeps it right on any server we later deploy to. |
| **Calendar months are `DATE` columns** holding the month's first day **in Asia/Baghdad**, written by code at the moment the thing happens: `billing_month` when a part is delivered, `refund_month` when cash is handed back. | D5: the server decides months, in Baghdad. Iraq is UTC+3 all year, with no daylight saving since 2008, so a fixed offset is exact and MySQL needs no time-zone tables (Windows ships none). A delivery at `2026-08-31T22:00Z` is written `2026-09-01`. |
| **Closed lists are `VARCHAR` + `CHECK (col IN (…))`**, holding the contract's own strings, in `ascii_bin` so the check is case-exact. The 19 governorates are a small table instead. | A `CHECK` needs none of `ENUM`'s quirks (ENUM sorts by position, not by name). The governorates are referenced from five tables and carry names in both languages, so one table beats five copies of the list. |
| **Nothing a record points at is hard-deleted.** Users, stores, products and product options get a status or `deleted_at`. Everything else is deleted for real. | Orders, returns and bills must keep pointing at what they were about (spec §16). |
| **Search columns (`search_text`) hold words folded in code** exactly as the app's `lib/core/utils/search_text.dart` folds them, in collation `utf8mb4_bin`, matched with an escaped `LIKE`. | The app says it plainly: "The real backend must fold the same way, or search changes on launch day." Folding in code, rather than trusting a collation, makes the server match exactly what the app matches. `LIKE` over a few thousand rows is instant; §9 says when to move on. |
| **Every constraint has a name** (`uq_users_phone`, `ck_products_price`). | The error handler turns a refused write into the right field error by its name. A duplicate phone becomes `409` on `phone`, not a 500. |

---

## 2. The tables at a glance

| Group | Tables |
|---|---|
| People and sign-in | `governorates`, `users`, `refresh_tokens`, `otp_challenges`, `admin_actions` |
| Stores | `stores`, `store_delivery_governorates`, `featured_stores` |
| Catalogue | `categories`, `brands`, `products`, `product_images`, `product_skus`, `stock_movements`, `media_files` |
| Shopping | `addresses`, `carts`, `cart_items`, `wishlist_items`, `coupons` |
| Orders | `orders`, `order_store_parts`, `order_items`, `order_events`, `idempotency_keys` |
| After a sale | `returns`, `return_items`, `store_reviews`, `review_reports`, `reports` |
| Money | `bill_payments` |
| Talking | `notifications`, `device_tokens`, `conversations`, `messages`, `support_tickets`, `support_messages` |
| Home and search | `home_banners`, `search_terms` |
| Plumbing | `schema_migrations` |

40 tables (`device_tokens` came with S10, migration 0005; `reports` with migration 0008).

**The order core:**

```
users (shopper) ──< orders ──< order_store_parts >── stores ──< products ──< product_skus
                     │              │                                           ▲
                     │              └──< order_items ───────────────────────────┘
                     ├──< order_events
                     └──< returns ──< return_items >── order_items
```

One checkout makes **one `orders` row and one `order_store_parts` row per store** in it. "An order is one record, two views" (`BACKEND_READY.md`): the shopper reads the order, and each store reads only its own part.

---

## 3. Tables

`→ table` marks a foreign key. Unless a row says otherwise, a column is `NOT NULL`, and every table has `id` as its key. Every table that changes also has `created_at` and `updated_at` (`DATETIME(3)`), not repeated below.

### 3.1 People and sign-in

#### `governorates`

| Column | Type | Notes |
|---|---|---|
| `code` | VARCHAR(20), **key** | `BAGHDAD` … `HALABJA`: the app's `Governorate.apiValue` |
| `name_en`, `name_ar` | VARCHAR(40) | As the app writes them (`core/location/governorate.dart`): "Nineveh (Mosul)", "نينوى (الموصل)" |
| `sort_order` | TINYINT UNSIGNED, unique | The app's order, biggest cities first. `/stores/cities` answers in it. |

Written by the first migration. Every governorate column in the schema points here. The server loads the 19 once at start, for its own messages ("Doesn't deliver to Erbil") and for admin search in either language.

#### `users`

One row per account: shopper, store owner or Saba staff (spec §2: exactly three account types).

| Column | Type | Notes |
|---|---|---|
| `role` | VARCHAR(8) | `CUSTOMER`, `MERCHANT`, `ADMIN`. Set once. Public sign-up makes only the first two. An admin is made by a command-line script, never by an endpoint (spec §5). |
| `status` | VARCHAR(10) | `ACTIVE`, `SUSPENDED`, `DELETED`. The app knows five (D27); v1 only ever sets these three. |
| `full_name` | VARCHAR(50) | At most 50 (BUGS 119). Emptied when the account is deleted. |
| `full_name_ar` | VARCHAR(50), null | D27c. Sign-up asks one name, so usually empty. |
| `phone` | VARCHAR(16), null | E.164 (`+9647705550142`), normalised however it was typed: `0751…`, `+964 751…`, `964…`, spaces, Arabic digits (BUGS 108). Unique. Null only after deletion, which frees the number (BUGS 79). |
| `phone_digits` | VARCHAR(12), null | Generated and stored: the number without `+964` (`7705550142`). Admin phone search (contract §1.7). |
| `email` | VARCHAR(254), null | Unique. Optional: accounts are by phone (BUGS 121). Saba's staff sign in to the web with it. |
| `password_hash` | VARCHAR(255), null | scrypt, with its salt and cost inside the string. Null after deletion. |
| `governorate` | VARCHAR(20), null | → `governorates`. The shopper's home (D27b). |
| `country` | VARCHAR(40) | `Iraq` |
| `suspension_reason` | VARCHAR(500), null | Saba's own note. The shopper is not shown it (contract §3.11). |
| `phone_verified_at` | DATETIME(3), null | When the number was proven by a code; null: never (signed up while `PHONE_VERIFICATION=off`, 0011). With checks back on, such an account is asked for a code at its next sign-in. |
| `search_text` | VARCHAR(255) bin | Folded `full_name` and `full_name_ar` |
| `deleted_at` | DATETIME(3), null | |

- **Unique:** `phone`, `email`.
- **Index:** `(role, status, created_at)`: the admin's shopper list, newest first.
- **Check:** `status = 'DELETED' OR phone IS NOT NULL`. A live account always has its number.

*Why no `customers`, `merchants`, `roles`, `permissions` or `user_roles` (spec §52):* v1 has three fixed roles and no per-permission staff. One column says it all. They come back with staff roles (Future).

#### `refresh_tokens`

| Column | Type | Notes |
|---|---|---|
| `user_id` | → `users` | |
| `token_hash` | BINARY(32), unique | SHA-256 of the token. The token itself (48 random bytes) exists only on the client. |
| `family_id` | BINARY(16) | Every token that descends from one sign-in. A token used again after it was rotated means it was copied, so the whole family is revoked. |
| `expires_at` | DATETIME(3) | 30 days (Q3) |
| `revoked_at` | DATETIME(3), null | Set by rotation, sign-out, suspension, deletion or a password reset |
| `replaced_by_id` | BIGINT UNSIGNED, null | The token it was rotated into |
| `user_agent` | VARCHAR(255), null | |
| `ip` | VARCHAR(45), null | |

- **Index:** `(user_id)`, `(family_id)`, `(expires_at)` for the hourly clean-up (migration 0009; before it the clean-up read the whole table). Rotated tokens stay until they expire, so one sent again is still recognised and its whole sign-in ended.

*Why stored rather than a second JWT:* sign-out, suspension and reuse detection all have to kill a token before it expires. The app already rotates ("the backend rotates refresh tokens, so persist the whole new pair", `auth_interceptor.dart`).

#### `otp_challenges`

One SMS code.

| Column | Type | Notes |
|---|---|---|
| `phone` | VARCHAR(16) | E.164 |
| `purpose` | VARCHAR(16) | `SIGN_UP`, `PASSWORD_RESET`, `OTHER`: the app's `OtpPurpose`. A sign-up code is refused for a number that has an account (409); a reset code for a number that has none (422 `phone`), as the demo does. Since 0011 also `SIGN_UP_NO_CODE` (a sign-up let through without an SMS while checks are off: no SMS sent, so it counts toward the address's 20 an hour but not the number's own limits) and `VERIFY_PHONE` (the code an unchecked account is asked for at sign-in). |
| `code_hash` | BINARY(32) | HMAC-SHA256 of the 6-digit code with a server secret. A plain hash of six digits is reversed in a second. |
| `attempts` | TINYINT UNSIGNED | Wrong tries. The sixth is refused (Q3). |
| `expires_at` | DATETIME(3) | 5 minutes (Q3) |
| `verified_at` | DATETIME(3), null | The right code was given |
| `consumed_at` | DATETIME(3), null | A registration used it. A second registration with the same token fails (BUGS 108, 168). |
| `ip` | VARCHAR(45), null | |

- **Index:** `(phone, purpose, created_at)`: the newest challenge, and how many were sent to a number this hour.

The `verificationToken` that `/auth/otp/verify` returns is a signed token, valid 15 minutes, naming this row and its phone. Registration checks the signature, the phone and `verified_at`, and sets `consumed_at` in the same transaction that creates the account. A made-up token can't pass, and one token makes one account.

A password reset sends the code itself (`token` in `/auth/reset-password`), so the reset checks the code against the newest unexpired `PASSWORD_RESET` row directly.

#### `admin_actions`

Who did what, and why. Written in the same transaction as every admin write (`ADMIN_REQUIREMENTS.md` §3, contract §5 "needed as soon as there is a real backend", spec §57). Nothing reads it in v1: the web's history view is Future. Each admin is their own `users` row, so the record is true from the first day.

| Column | Type | Notes |
|---|---|---|
| `admin_user_id` | → `users` | |
| `action` | VARCHAR(30) | `STORE_APPROVE`, `STORE_REJECT`, `STORE_SUSPEND`, `STORE_UNSUSPEND`, `PRODUCT_APPROVE`, `PRODUCT_REJECT`, `PRODUCT_TAKE_DOWN`, `PRODUCT_RESTORE`, `CUSTOMER_SUSPEND`, `CUSTOMER_UNSUSPEND`, `BILL_MARK_PAID`, `BILL_UNMARK_PAID`, `TICKET_REPLY`, `TICKET_STATUS`, `FEATURED_SAVE` |
| `entity_type`, `entity_id` | VARCHAR(20), VARCHAR(40) | |
| `reason` | VARCHAR(500), null | |
| `details` | JSON, null | For example the month and amount when a payment is undone |
| `ip` | VARCHAR(45), null | |

- **Index:** `(entity_type, entity_id, created_at)`, `(admin_user_id, created_at)`.

### 3.2 Stores

#### `stores`

One per store-owner account.

| Column | Type | Notes |
|---|---|---|
| `owner_user_id` | → `users`, unique | One account, one store in v1 |
| `store_name` | VARCHAR(40) | At most 40 (BUGS 119). Stays as typed: store names are proper nouns and have no Arabic twin. |
| `name_key` | VARCHAR(40) | The name lower-cased, trimmed, inner spaces made one. Unique together with `governorate`: two stores in one city can't share a name, other cities may (BUGS 120). The database refuses the duplicate, so two sign-ups at the same moment can't both win. |
| `status` | VARCHAR(10) | `PENDING`, `APPROVED`, `REJECTED`, `SUSPENDED`, and `CLOSED` once its owner's account was deleted (migration 0007). No `UNDER_REVIEW` (D-S1). |
| `rejection_reason`, `suspension_reason` | VARCHAR(500), null | |
| `submitted_at` | DATETIME(3) | When it applied |
| `answered_at` | DATETIME(3), null | When Saba approved or rejected it |
| `governorate` | → `governorates` | The store's city. Its products are where it is. |
| `country` | VARCHAR(40) | `Iraq` |
| `business_type` | VARCHAR(20), null | As sign-up sends it |
| `business_address`, `business_address_ar` | VARCHAR(200), null | The Arabic twin exists for seeded stores; the settings form is in one language. |
| `description`, `description_ar` | VARCHAR(1000), null | D24b |
| `logo_url`, `banner_url` | VARCHAR(500), null | A storage key from `media_files` (see §3.3). |
| `is_open` | BOOLEAN | The owner's own switch (D23): closed means no orders, and its products leave browsing. |
| `fee_inside`, `fee_outside` | INT, null | Delivery fee to its own governorate and to the others it serves. Multiples of 250. |
| `time_inside`, `time_outside` | VARCHAR(10), null | `SAME_DAY`, `1_2_DAYS`, `2_3_DAYS`, `3_5_DAYS`, `5_7_DAYS` |
| `rating_sum`, `rating_count` | INT UNSIGNED | Kept in step with `store_reviews` in the same transaction. `rating = sum / count`. |
| `search_text` | VARCHAR(500) bin | Folded name and business address, both languages (admin search; the owner's name, phone and email are searched through `users`) |
| `deletion_requested_at` | DATETIME(3), null | When the owner asked to delete the account; null again if they cancel. Kept once done. |
| `closed_at` | DATETIME(3), null | When the hourly run deleted it: the row stays for the orders, returns and bills that name it; its logo, banner, address and description are cleared, its products marked deleted, its codes deleted, and its owner's account deleted as a shopper's is. |

- **Unique:** `owner_user_id`; `(governorate, name_key)`.
- **Index:** `(status, submitted_at)` for the queue and the admin list; `(status, is_open, governorate)` for `/stores/cities`.
- **Checks:** fees `>= 0` and multiples of 250; `(fee_inside IS NULL) = (time_inside IS NULL)`, the same for outside; `status <> 'REJECTED' OR rejection_reason IS NOT NULL`; `status <> 'SUSPENDED' OR suspension_reason IS NOT NULL`; `CLOSED` exactly when `closed_at` is set, and a closed store is shut and was asked for (`ck_stores_closed`).

A new store has no fees and no delivery rows: it delivers nowhere until its owner says where and for how much (BUGS 88).

*Why one table for the owner's store and its settings (the spec lists `merchants`, `merchant_stores`, `merchant_documents`):* one owner, one store, and no documents in v1.

#### `store_delivery_governorates`

| Column | Type | Notes |
|---|---|---|
| `store_id` | → `stores`, cascade on delete | |
| `governorate` | → `governorates` | |

- **Key:** `(store_id, governorate)`. **Index:** `(governorate, store_id)`.

Always holds the store's own governorate once delivery is set ("It always delivers where it is", demo). *Why rows and not a JSON list:* the cart, checkout and `/products?deliverTo=` all ask "does this store deliver to X?", which is an indexed lookup here.

#### `featured_stores`

| Column | Type | Notes |
|---|---|---|
| `store_id` | → `stores`, **key** | |
| `position` | SMALLINT UNSIGNED, unique | |

Rules (contract §3.9 and the web's `featured.ts`):

- Home and `GET /admin/featured-stores` show only `APPROVED` stores, in `position` order.
- `PUT` writes the ids it was sent, in order, then keeps every previously featured store that is no longer approved (a suspended one) after them. That is how a suspended store "keeps its place at the end of the rail" and comes back when reactivated.
- One transaction: delete, then insert.

### 3.3 Catalogue

#### `categories`

| Column | Type | Notes |
|---|---|---|
| `parent_id` | → `categories`, null | Two levels only |
| `name`, `name_ar` | VARCHAR(60) | |
| `image_url` | VARCHAR(500), null | |
| `position` | SMALLINT UNSIGNED | |
| `is_hidden` | BOOLEAN | Saba hid it (0010): off Home, Browse, the filters and the stores' picker; its products stay on sale |
| `deleted_at` | DATETIME(3), null | Deleted by Saba once empty; the row stays for the deleted products that name it |

- **Index:** `(parent_id, position)`.

The 7 top-level categories and their 6 sub-categories (`MockData.categories`) are written by a **migration**, not by the dev seed: they are what v1 sells, in every environment, production included. No product count is stored: "a count nobody keeps true is worse than no count" (`MockData`). Saba adds, renames, moves, orders, hides and deletes them on its Categories page (2026-10-01, contract §3.14). A product's `search_text` holds its category's and parent's names, so a rename or a move rebuilds it for their products.

#### `brands`

| Column | Type | Notes |
|---|---|---|
| `name` | VARCHAR(60), unique | Unique whatever its case (the collation) |
| `name_ar` | VARCHAR(60), null | Null for a brand a store typed, until Saba saves it (0010) |
| `status` | `APPROVED` / `PENDING` | `PENDING`: typed by a store; approved with its product, or when Saba saves it |

Saba keeps the list on its Brands page (2026-10-01, contract §3.14). A store picks a brand or types one; a typed name that is no brand's, in either language, is added `PENDING`. `productCount` in `/brands` is counted when asked, over listed products, so only checked brands appear there.

#### `products`

| Column | Type | Notes |
|---|---|---|
| `store_id` | → `stores` | A product belongs to its store, not to whoever is signed in (`PROJECT_MAP.md` §2). |
| `category_id` | → `categories` | |
| `brand_id` | → `brands`, null | |
| `name_en` | VARCHAR(120), null | "The English name is the optional one" (demo). |
| `name_ar` | VARCHAR(120) | Required on every save: 3 or more characters with an Arabic letter (`_noArabicName`). Approval checks it again (contract §3.5). |
| `description`, `description_ar` | TEXT, null | |
| `warranty`, `warranty_ar` | VARCHAR(120), null | |
| `base_price` | BIGINT | The normal price |
| `compare_at_price` | BIGINT, null | What the form calls `originalPrice`: a price before the store's lasting discount. Above `base_price`. |
| `sale_price`, `sale_ends_at` | BIGINT, DATETIME(3), both null | A flash sale (`BACKEND_READY.md`). Both or neither. On while `sale_ends_at` is in the future. |
| `status` | VARCHAR(8) | `DRAFT`, `PENDING`, `APPROVED`, `REJECTED` |
| `rejection_reason` | VARCHAR(500), null | |
| `is_active` | BOOLEAN | The store's own on/off switch (D22) |
| `taken_down`, `taken_down_reason` | BOOLEAN, VARCHAR(500) null | Saba's takedown (D22). The store's switch can't undo it (409). |
| `option_colours` | JSON, null | Option value → colour, for the swatches (`optionColours`) |
| `size_guide` | TEXT, null | |
| `submitted_at` | DATETIME(3), null | The last "send for review". The admin's `createdAt` is this (contract: "the web shows it as when it was sent for review"), falling back to `created_at`. |
| `search_text` | VARCHAR(500) bin | Folded names, plus its category's and the parent category's names in both languages (the demo's `_found`) |
| `deleted_at` | DATETIME(3), null | |

- **Index:** `(store_id, status, deleted_at)`; `(category_id, status)`; `(status, submitted_at)` for the queue; `(sale_ends_at)` for Home's flash sale.
- **Checks:** `base_price > 0` and a multiple of 250; `compare_at_price` null or above `base_price` and a multiple of 250; the sale pair both-or-neither; `sale_price` above 0, below `base_price`, a multiple of 250; `status <> 'REJECTED' OR rejection_reason IS NOT NULL`; `NOT taken_down OR taken_down_reason IS NOT NULL`.

**For sale ("listed"), one rule** used by search, categories, a store's page, Home, related products, the wishlist, the cart and checkout (the demo's `_isListed`, BUGS 46): `status = 'APPROVED'`, `is_active`, not `taken_down`, not deleted, and its store `APPROVED`.

- **Browsing** (search, categories, Home, related, a store's page) also needs the store open: "a closed store's products … drop out" (`PROJECT_MAP.md` §7). The demo still lists them in search; the server follows the document.
- **A product's own page** opens for a listed product even when its store is closed, and says so (`merchant.isOpen`).
- **The store** can open any of its own products, listed or not (`isListed: false`).

**The price a shopper sees is worked out when it is read**, so an ended sale is never sold (`BACKEND_READY.md`: "the end has to be honoured when the price is read"):

- During a sale: `price = sale_price`, `originalPrice = base_price`.
- Otherwise: `price = base_price`, `originalPrice = compare_at_price`.
- `discountPercentage = round((1 − price / originalPrice) × 100)` when there is an original.

Nothing has to run on time: a sale whose end has passed is simply not a sale. A cleanup job may clear old sale columns; nothing depends on it.

#### `product_images`

| Column | Type | Notes |
|---|---|---|
| `product_id` | → `products`, cascade | |
| `url` | VARCHAR(500) | A storage key (see `media_files`) |
| `position` | TINYINT UNSIGNED | 0 is the main photo (`imageUrl`, `isPrimary`) |

- **Unique:** `(product_id, position)`.

#### `product_skus`: the things sold, and the only place stock lives

"Stock is kept per **thing sold**, not per product" (`PROJECT_MAP.md` §7). A product without options has exactly one row, with no options. A product with options has one row per option and no stock of its own: its figure is the sum.

| Column | Type | Notes |
|---|---|---|
| `product_id` | → `products` | |
| `options` | JSON, null | `{"Color": "Black", "Storage": "256GB"}`, as the store typed it. Null on the single row of a product without options. |
| `option_label` | VARCHAR(120), null | The values joined with " · " ("Black · 256GB"): what the cart, the order line and the inventory row show |
| `sku_code` | VARCHAR(40), null | |
| `price` | BIGINT, null | This option's normal price. Null on a no-options row: the product's `base_price` applies. |
| `image_url` | VARCHAR(500), null | |
| `stock` | INT | `CHECK (stock >= 0)`: the database refuses to go below zero |
| `deleted_at` | DATETIME(3), null | An option removed in an edit is marked, not deleted: old orders point at it |

- **Index:** `(product_id, deleted_at)`.
- **Checks:** `stock >= 0`; `price` null or above 0 and a multiple of 250.
- **An option's shown price:** its `price`, less the running sale's discount (`base_price − sale_price`) during a sale. **Its original:** its pre-sale price during a sale, or `price + (compare_at_price − base_price)` when the product has a lasting discount. This is the seed's own formula (`_variantsFor`, `_startSale`).
- **`stockStatus`:** 0 is `OUT_OF_STOCK`, 1–5 `LOW_STOCK`, 6 and up `IN_STOCK` (`_stockStatus`).

*Why one table for both kinds:* one row to lock and one rule at checkout. The API is unchanged: a product without options has no `variants`, and its cart lines have `variantId: null`, as today.

#### `stock_movements`

Every change to a `stock`, written in the same transaction.

| Column | Type | Notes |
|---|---|---|
| `sku_id` | → `product_skus` | |
| `delta` | INT | Never 0 |
| `reason` | VARCHAR(20) | `ORDER_PLACED`, `ORDER_CANCELLED`, `PART_DECLINED`, `PART_REFUSED`, `RETURN_REFUNDED`, `ADJUSTED`, `SET`, `PRODUCT_SAVED`, `SEEDED` |
| `part_id` | → `order_store_parts`, null | |
| `return_id` | → `returns`, null | |
| `actor_user_id` | → `users`, null | |

- **Index:** `(sku_id, created_at)`.

*Why:* bugs 77, 78 and 160 were all stock that moved wrongly, silently. The ledger makes every number explainable (spec §17's `inventory_transactions`).

#### `media_files`

| Column | Type | Notes |
|---|---|---|
| `owner_user_id` | → `users` | |
| `storage_key` | VARCHAR(200), unique | Generated by the server (`products/2026/09/<random>.jpg`), never the client's file name (spec §56) |
| `content_type` | VARCHAR(40) | Read from the file's first bytes, not trusted from the client |
| `byte_size` | INT UNSIGNED | |
| `deleted_at` | DATETIME(3), null | |

The product form and store settings send back the photo addresses they got from `/media/upload`. The server accepts only files that account uploaded itself, or that the product already has ("never trust client-supplied … ids", spec §51).

**Every `url` column holds a storage key, not a full address.** The full address is added when the record is sent: an Android emulator reaches this laptop as `10.0.2.2`, a browser as `localhost`, and production will use a file server (`BACKEND_PLAN.md` §9, item 8).

### 3.4 Shopping

#### `addresses`

| Column | Type | Notes |
|---|---|---|
| `user_id` | → `users` | |
| `label` | VARCHAR(30), null | "Home", "Work", or as typed; optional in the app's form (migration 0004) |
| `full_name`, `full_name_ar` | VARCHAR(50), `_ar` null | |
| `phone` | VARCHAR(16) | An Iraqi mobile, E.164 |
| `governorate` | → `governorates` | |
| `area`, `area_ar` | VARCHAR(100), `_ar` null | `area` required |
| `street`, `street_ar` | VARCHAR(150), null | |
| `landmark`, `landmark_ar` | VARCHAR(150), `_ar` null | `landmark` required |
| `instructions` | VARCHAR(300), null | D16 |
| `is_default` | BOOLEAN | |
| `default_for` | BIGINT UNSIGNED, null | Generated: `user_id` when `is_default`, otherwise null. **Unique**, so a shopper can't have two defaults. |

- **Index:** `(user_id)`.
- The server checks (WORK-LOG 2026-09-21): an Iraqi mobile, a known governorate, area and landmark present.
- The Arabic twins exist for seeded addresses only: the form is in one language (D16b).

#### `carts`

| Column | Type | Notes |
|---|---|---|
| `user_id` | → `users`, **key** | |
| `coupon_id` | → `coupons`, null | The one coupon applied to the cart |

#### `cart_items`

| Column | Type | Notes |
|---|---|---|
| `user_id` | → `users` | |
| `sku_id` | → `product_skus` | |
| `quantity` | SMALLINT UNSIGNED | 1 to 999 |
| `saved_for_later` | BOOLEAN | |

- **Unique:** `(user_id, sku_id, saved_for_later)`. Adding the same option again adds to its line; "Move to cart" onto a line that is already there adds the quantities.
- No price is stored in the cart. Each read prices it from the catalogue (`_buildCart`).

#### `wishlist_items`

| Column | Type | Notes |
|---|---|---|
| `user_id` | → `users` | |
| `product_id` | → `products` | |

- **Key:** `(user_id, product_id)`. Only the default list: the named-list routes are declared in the app but never called.

#### `coupons`

A store's own code. v1 has no Saba-wide coupons ("in a cash-only v1 there is nothing for Saba to pay them from", demo).

| Column | Type | Notes |
|---|---|---|
| `store_id` | → `stores` | |
| `code` | VARCHAR(15), unique | 3–15 letters or digits, upper-cased. Unique across all of Saba, because a code can be typed into any cart. |
| `discount_type` | VARCHAR(10) | `PERCENTAGE`, `FIXED` |
| `value` | INT | |
| `min_order_amount` | BIGINT, null | |
| `starts_at` | DATETIME(3) | |
| `ends_at` | DATETIME(3), null | |
| `usage_limit` | INT UNSIGNED, null | |
| `used_count` | INT UNSIGNED | |
| `is_active` | BOOLEAN | The store's pause |

- **Index:** `(store_id)`.
- **Checks:** `value > 0`; a percentage at most 90; a fixed value a multiple of 250; `ends_at > starts_at`; `usage_limit IS NULL OR used_count <= usage_limit`.
- **Live** means active, started, not ended, uses left (`_isLive`). A use counts only when the order took something off (BUGS 166).

### 3.5 Orders

#### `orders`: the shopper's order

| Column | Type | Notes |
|---|---|---|
| `order_number` | VARCHAR(12), unique, null | `SB-` followed by `100000 + id`, written in the same transaction as the insert (MySQL can't generate a column from an auto-increment one) |
| `customer_id` | → `users` | D14 |
| `status` | VARCHAR(10) | `PENDING`, `CONFIRMED`, `PROCESSING`, `SHIPPED`, `DELIVERED`, `CANCELLED`, `REFUSED`. Worked out from the parts and stored, in the same transaction as every part change (§6). Not `RETURNED` or `REFUNDED` (Q8). |
| `payment_status` | VARCHAR(10) | `PENDING`, `PAID`, `CANCELLED`. `PAID` once every live part is delivered (cash is paid at the door); `CANCELLED` when no part is coming. |
| `payment_method` | VARCHAR(4) | Always `COD` (D8) |
| `subtotal`, `discount`, `shipping`, `total` | BIGINT | As placed. Never worked out again: the invoice says what was charged. |
| `item_count` | SMALLINT UNSIGNED | Units, not lines |
| `coupon_id` | → `coupons`, null, set null on delete | |
| `coupon_code` | VARCHAR(15), null | Kept even if the coupon is deleted |
| `customer_name`, `customer_name_ar` | VARCHAR(50), `_ar` null | The address's name when placed: who the drivers ask for |
| `customer_phone` | VARCHAR(16) | The address's number when placed: who the drivers call |
| `customer_phone_digits` | VARCHAR(12) | Generated, for admin phone search |
| `ship_governorate` | → `governorates` | The address as it was. Editing an address later must not move a parcel already on its way. |
| `ship_area`, `ship_area_ar`, `ship_street`, `ship_street_ar`, `ship_landmark`, `ship_landmark_ar` | as `addresses` | |
| `instructions` | VARCHAR(300), null | The checkout's `deliveryInstructions`, else the address's (D16) |
| `placed_at` | DATETIME(3) | |
| `delivered_at` | DATETIME(3), null | When the last live part arrived |
| `cancelled_at`, `cancelled_by`, `cancel_reason`, `cancel_note` | null | Set when the whole order is called off. `cancelled_by` is `SHOPPER` or `STORE`; `cancel_reason` a code (contract §2.1); `cancel_note` the shopper's words with `OTHER`. |
| `rated_at` | DATETIME(3), null | The rating sheet was answered |
| `rating_skips` | TINYINT UNSIGNED | "Not now" presses. Asked three times at most (`_ratingAsks`). |
| `search_text` | TEXT bin | Folded number, customer name, store names, item names in both languages (admin search). `TEXT`, because an order has no limit on its lines. |

- **Index:** `(customer_id, placed_at)`; `(status, placed_at)`; `(placed_at)`.
- **Checks:** `total = subtotal − discount + shipping`; `discount <= subtotal`.

#### `order_store_parts`: one store's part

| Column | Type | Notes |
|---|---|---|
| `order_id`, `store_id` | → `orders`, → `stores` | Unique together |
| `status` | VARCHAR(10) | `PENDING` (the store screen's "New", D10), `CONFIRMED`, `PROCESSING`, `SHIPPED`, `DELIVERED`, `CANCELLED`, `REFUSED` |
| `subtotal`, `discount`, `shipping_fee`, `amount_due` | BIGINT | D7: each store's own money. `amount_due` is what its driver collects at the door. |
| `item_count` | SMALLINT UNSIGNED | |
| `delivery_time` | VARCHAR(10) | The store's promised time when the order was placed (`deliveryTime`) |
| `courier_name`, `courier_name_ar`, `courier_phone` | VARCHAR(50)/(50)/(16), null | The store's own driver, required when it marks the part shipped. `courierType` is always `DRIVER` (D-O1), so it is not stored. The Arabic twin exists for seeded orders (D15). |
| `cancellation_reason` | VARCHAR(20), null | A store's decline (`OUT_OF_STOCK`, `CANNOT_FULFIL`, `ADDRESS_PROBLEM`, `CUSTOMER_ASKED`) or `CUSTOMER_CANCELLED` |
| `received` | BOOLEAN, null | The shopper's "did you receive it?" |
| `confirmed_at`, `shipped_at`, `delivered_at`, `cancelled_at` | DATETIME(3), null | |
| `billing_month` | DATE, null | The Baghdad month of `delivered_at`: which bill this sale is on |

- **Unique:** `(order_id, store_id)`.
- **Index:** `(store_id, status, created_at)` for the store's queue; `(store_id, billing_month)` for bills; `(order_id)`.
- **Checks:** `amount_due = subtotal − discount + shipping_fee`; `(status = 'DELIVERED') = (billing_month IS NOT NULL)`; `status <> 'CANCELLED' OR cancellation_reason IS NOT NULL`; `status NOT IN ('SHIPPED', 'DELIVERED', 'REFUSED') OR (courier_name IS NOT NULL AND courier_phone IS NOT NULL)`.

#### `order_items`

| Column | Type | Notes |
|---|---|---|
| `order_id`, `part_id` | → `orders`, → `order_store_parts` | |
| `product_id`, `sku_id` | → `products`, → `product_skus` | Always kept: products and options are never hard-deleted |
| `product_name`, `product_name_ar` | VARCHAR(120), `_ar` null | Snapshot (spec §16): what it was called then |
| `variant_label` | VARCHAR(120), null | D11 |
| `sku_code` | VARCHAR(40), null | D11 |
| `image_url` | VARCHAR(500), null | |
| `store_name` | VARCHAR(40) | The store's name then (`merchantName`) |
| `unit_price` | BIGINT | The price per unit before the coupon |
| `paid_unit_price` | BIGINT | After the store's coupon, shared over its lines by price, rounded down to 250 (BUGS 161, 175). What a return gives back. |
| `quantity` | SMALLINT UNSIGNED | |
| `line_total` | BIGINT | |

- **Index:** `(order_id)`, `(part_id)`, `(product_id)`.
- **Checks:** `quantity > 0`; `line_total = unit_price × quantity`; `paid_unit_price <= unit_price`.
- A line's `status`, `deliveredAt` and `canReturn` are its part's, worked out when read (D9).

#### `order_events`: the timeline

| Column | Type | Notes |
|---|---|---|
| `order_id` | → `orders` | |
| `part_id` | → `order_store_parts`, null | A store's step |
| `status` | VARCHAR(10) | |
| `note_code` | VARCHAR(30), null | `ORDER_RECEIVED` |
| `reason_code` | VARCHAR(30), null | A cancel or decline reason |
| `note` | VARCHAR(500), null | The shopper's own words, as typed |
| `store_name` | VARCHAR(40), null | Whose step it was |
| `occurred_at` | DATETIME(3) | |

- **Index:** `(order_id, occurred_at)`.
- Words are codes the app translates (BUGS 51).

#### `idempotency_keys`

| Column | Type | Notes |
|---|---|---|
| `user_id` | → `users` | |
| `idem_key` | VARCHAR(64) | The app's `Idempotency-Key` header |
| `request_hash` | BINARY(32) | SHA-256 of the request body |
| `response` | JSON | The placed order, as it was answered |

- **Key:** `(user_id, idem_key)`.
- Written inside the place-order transaction. A retry of the same checkout gets the same order back, never a second one.
- The same key with a different body is refused (422).
- Only a placed order is kept. A refused checkout leaves nothing, so the shopper can fix the cart and try again.
- Deleted after 24 hours.

### 3.6 After a sale

#### `returns`

| Column | Type | Notes |
|---|---|---|
| `order_id`, `part_id`, `store_id`, `customer_id` | → their tables | One store per return: "Each store picks up its own things, so one store at a time" (demo) |
| `status` | VARCHAR(10) | `REQUESTED`, `APPROVED`, `REJECTED`, `REFUNDED` (D18) |
| `reason` | VARCHAR(20) | `DAMAGED`, `WRONG_ITEM`, `NOT_AS_DESCRIBED`, `MISSING_PARTS`, `CHANGED_MIND`, `OTHER` |
| `description` | VARCHAR(1000), null | The shopper's own words (D19) |
| `rejection_reason` | VARCHAR(12), null | The store's decline: `USED`, `INCOMPLETE`, `NOT_AS_SAID`, `OTHER` (`BACKEND_READY.md`) |
| `refund_amount` | BIGINT | The sum of paid unit prices times quantities |
| `requested_at` | DATETIME(3) | |
| `answered_at`, `refunded_at` | DATETIME(3), null | |
| `refund_month` | DATE, null | The Baghdad month the cash was handed back: which bill it comes off |

- **Index:** `(store_id, status, requested_at)`; `(customer_id, requested_at)`; `(store_id, refund_month)`; `(order_id)`.
- **Checks:** `(status = 'REFUNDED') = (refund_month IS NOT NULL)`; `status <> 'REJECTED' OR rejection_reason IS NOT NULL`.
- The return's steps and its `refund` block (`amount`, `status`, `processedAt`, D6) are built from its three moments. No second table.
- v1 returns carry no photos: the app sends none.

#### `return_items`

| Column | Type | Notes |
|---|---|---|
| `return_id` | → `returns` | |
| `order_item_id` | → `order_items`, **unique** | BUGS 160, held by the database: an order line takes one return, answered or not |
| `quantity` | SMALLINT UNSIGNED | At most what was bought |
| `refund_amount` | BIGINT | |

#### `store_reviews`

| Column | Type | Notes |
|---|---|---|
| `store_id`, `order_id`, `customer_id` | → their tables | Unique `(order_id, store_id)`: one rating per store per order |
| `rating` | TINYINT UNSIGNED | 1–5 |
| `body` | VARCHAR(1000), null | The one comment for the order |
| `removed_at`, `removed_by` | DATETIME(3), → `users`, null | Saba removed it (migration 0006): off the store's page and out of its rating. Both or neither (a CHECK) |

- **Index:** `(store_id, created_at)`.
- Stores are rated, never products (v1). Each review adds to `stores.rating_sum` and `rating_count` in its transaction; removing it takes them back out, in its own.

#### `review_reports`

| Column | Type | Notes |
|---|---|---|
| `review_id` | → `store_reviews` | |
| `reporter_user_id` | → `users` | Unique with `review_id` |
| `reason` | VARCHAR(20) | The app's `ReportReason` code |
| `description` | VARCHAR(500), null | The shopper's words (migration 0006; before it they were accepted and dropped) |
| `status` | VARCHAR(10) | `OPEN`, `DISMISSED` (the review stays) or `REMOVED` (the review went) |
| `handled_at`, `handled_by` | DATETIME(3), → `users`, null | When and by which admin; set exactly when the status isn't `OPEN` (a CHECK) |

- **Index:** `(status, created_at)`.
- The app's "Report" on a store review. Saba sees each reported review with its reports in the admin web, and removes the review or dismisses the reports (decided before launch, 2026-09-29: app stores check that a report reaches someone).

#### `reports`

A shopper's or a store's report of a product, a store or a chat (migration 0008; the reviewer's item 3: Apple 1.2 and Google). Reviews keep their own `review_reports`.

| Column | Type | Notes |
|---|---|---|
| `target_type`, `target_id` | VARCHAR(12), BIGINT UNSIGNED | `PRODUCT`, `STORE` or `CONVERSATION`, and its id (no foreign key: it points at one of three tables) |
| `reporter_user_id` | → `users` | Unique with the target: once per person |
| `reason` | VARCHAR(20) | The review reasons (a CHECK) |
| `description` | VARCHAR(500), null | Their words |
| `evidence` | JSON, null | A chat report: its last 20 messages, as they were, since Saba has no chat inbox |
| `status` | VARCHAR(10) | `OPEN`, `DISMISSED` or `ACTIONED` (Saba acted: took the product down, suspended the store or the shopper) |
| `handled_at`, `handled_by` | DATETIME(3), → `users`, null | Set exactly when the status isn't `OPEN` (a CHECK) |

- **Index:** `(status, created_at)`.

### 3.7 Money

#### `bill_payments`

A month Saba has recorded as paid by a store.

| Column | Type | Notes |
|---|---|---|
| `store_id` | → `stores` | |
| `month` | DATE | The month's first day |
| `paid_on` | DATE | The day the cash came in |
| `owed` | BIGINT | What the bill said when it was marked paid |
| `rate_percent` | TINYINT UNSIGNED | The rate then |
| `recorded_by` | → `users` | The admin |

- **Unique:** `(store_id, month)`. Marking a month twice is refused by the database itself (409).
- "Mark as not paid" deletes the row. `admin_actions` keeps who did it, when, and what the row said.

**Bills are not stored.** A month's bill is worked out from the store's delivered parts (`billing_month`) and refunded returns (`refund_month`), by the formula in §6. It can't drift: a part's month is fixed the moment it is delivered, and `DELIVERED` and `REFUNDED` are final, so a closed month never changes after it closes. Its status:

- `OPEN`: this month.
- `NONE`: a closed month with nothing owed.
- `PAID`: a row here.
- `DUE`: any other closed month.

The rate is 8% in v1, one constant in the server's rules. A changeable rate with a start date is Future (contract §5); `rate_percent` above already keeps each paid month's rate.

### 3.8 Talking

#### `notifications`

| Column | Type | Notes |
|---|---|---|
| `user_id` | → `users` | Who reads it. A store's notices go to its owner's account: one owner per store in v1. |
| `type` | VARCHAR(20) | `ORDER`, `SHIPPING`, `DELIVERY`, `PRODUCT_APPROVAL`, `STORE`, `MESSAGE`, `TICKET`, `PAYMENT` |
| `title_en`, `title_ar` | VARCHAR(300) | Written in both languages when made, sent in the one the app asks for |
| `body_en`, `body_ar` | VARCHAR(1000) | Room for a 500-character reason inside the sentence |
| `entity_type`, `entity_id` | VARCHAR(15), VARCHAR(40), null | What a tap opens (`BACKEND_READY.md`, "the ten things"): `ORDER`, `STORE_ORDER`, `RETURN`, `STORE_PRODUCT`, `STORE`, `CONVERSATION`, `TICKET` |
| `is_read` | BOOLEAN | |

- **Index:** `(user_id, id)` for newest first; `(user_id, is_read)` for the bell's count.

#### `device_tokens` (S10, migration 0005)

| Column | Type | Notes |
|---|---|---|
| `token` | VARCHAR(1024) ascii, unique | The phone's Firebase registration token. One row per token: when someone else signs in on the phone, it moves to them, so one account's pushes never reach the next |
| `user_id` | → `users` | |
| `platform` | VARCHAR(8) | `ANDROID` or `IOS` (a CHECK) |
| `language` | CHAR(2) | `en` or `ar` (a CHECK): the language its pushes are written in |

- **Index:** `(user_id)`. Deleted with the account; a token Firebase calls gone is deleted when it says so.
- Only some notifications push (`BACKEND_PLAN.md` §2.0 "S10"); the push is the notification row's own words and target, sent after the commit.

#### `conversations`

| Column | Type | Notes |
|---|---|---|
| `customer_id`, `store_id` | → `users`, → `stores` | Unique together |
| `customer_last_read_id`, `store_last_read_id` | BIGINT UNSIGNED, null | The last message each side has seen |
| `last_message_at` | DATETIME(3), null | |
| `customer_blocked_at`, `store_blocked_at` | DATETIME(3), null | When that side blocked the other (migration 0008). While either is set, nobody writes in the chat; each side lifts only its own. |

- **Index:** `(store_id, last_message_at)`, `(customer_id, last_message_at)`.
- A chat is between a shopper and a store only. The demo's "Saba Support" chat has no counterpart: support is tickets (`BACKEND_PLAN.md` §9, item 11).

#### `messages`

| Column | Type | Notes |
|---|---|---|
| `conversation_id` | → `conversations` | |
| `sender` | VARCHAR(8) | `CUSTOMER`, `STORE` |
| `body` | VARCHAR(2000), null | Null for a photo (0012) |
| `photo_key` | VARCHAR(100), null | A photo (0012): `chats/…`, kept privately, opened only through links the API signs |
| `photo_removed_at`, `photo_removed_by` | DATETIME(3), `ACCOUNT` / `SABA`, null | Its sender's account was deleted, or Saba removed it: shown as removed; the key stays until the file is gone |
| `photo_deleted_at` | DATETIME(3), null | The file was deleted: by the hourly run, which waits while an open report's evidence holds a photo its sender's deletion removed |
| `sent_at` | DATETIME(3) | |

- **Index:** `(conversation_id, id)`, `(photo_key)`, `(photo_removed_at)`.
- **Checks:** words or a photo; removed with who removed it, and deleted only once removed.
- Unread means the other side's messages after my last-read id.

#### `support_tickets`

| Column | Type | Notes |
|---|---|---|
| `reference` | VARCHAR(10), unique, null | `T-` followed by `5000 + id`, written in the same transaction |
| `opened_by_user_id` | → `users` | |
| `opened_by_kind` | VARCHAR(8) | `SHOPPER`, `STORE` |
| `store_id` | → `stores`, null | For a store's ticket |
| `opener_name`, `opener_phone` | VARCHAR(50), VARCHAR(16) | Taken from the session when opened (D-T1), kept so the ticket still says who opened it after an account is deleted |
| `subject` | VARCHAR(120) | |
| `category` | VARCHAR(10) | `ORDER`, `PAYMENT`, `DELIVERY`, `RETURN`, `PRODUCT`, `ACCOUNT`, `OTHER` |
| `status` | VARCHAR(20) | `OPEN`, `IN_PROGRESS`, `WAITING_FOR_CUSTOMER`, `RESOLVED`, `CLOSED` |
| `last_message` | VARCHAR(500) | The first 500 characters of the newest message, for the list |

- **Index:** `(opened_by_user_id, updated_at)`; `(status, updated_at)`; `(opened_by_kind, status)`.

#### `support_messages`

| Column | Type | Notes |
|---|---|---|
| `ticket_id` | → `support_tickets` | |
| `body` | VARCHAR(4000) | Trimmed; never blank |
| `is_from_customer` | BOOLEAN | |
| `author_user_id` | → `users` | For Saba's replies, the admin who wrote it. Not sent: Saba's replies are unsigned (contract §3.8). |
| `sent_at` | DATETIME(3) | |

- **Index:** `(ticket_id, id)`.

### 3.9 Home and search

#### `home_banners`

| Column | Type | Notes |
|---|---|---|
| `position` | SMALLINT UNSIGNED | |
| `title_en`, `subtitle_en`, `title_ar`, `subtitle_ar` | VARCHAR(120), null | Optional since 0010, each pair in both languages or neither |
| `image_url` | VARCHAR(500), null | Required on Saba's page; the demo banners have none |
| `link_type`, `link_id` | `PRODUCT` / `STORE` / `CATEGORY`, BIGINT; both null or neither | What a tap opens; no foreign key, so Home checks it is still there (0010) |
| `is_active` | BOOLEAN | |

The four demo banners come from the dev seed; the live database starts with none. Saba edits them on its Banners page (2026-10-01, contract §3.14). Home shows the active ones in order and leaves off one whose link opens nothing any more. With none, Home has no banner section.

#### `search_terms`

| Column | Type | Notes |
|---|---|---|
| `term_key` | VARCHAR(100), **key** | Folded |
| `display_text` | VARCHAR(100) | As first typed |
| `hits` | INT UNSIGNED | |

- **Index:** `(hits)`.
- Counted once per search that found something, on its first page: "Popular searches come from real searches that found something."

### 3.10 Plumbing

#### `schema_migrations`

| Column | Type | Notes |
|---|---|---|
| `version` | VARCHAR(100), **key** | The file name |
| `checksum` | BINARY(32) | A migration edited after it ran is refused |
| `applied_at` | DATETIME(3) | |

---

## 4. What the database holds by itself

The server checks all of these before it writes. The database holds them again, so a bug or a race can't break them.

| Rule | Held by |
|---|---|
| One account per phone number; a deleted account frees it | `uq_users_phone` (nulls allowed) |
| Two stores in one city can't share a name | `uq_stores_governorate_name_key` |
| Stock never below zero | `ck_product_skus_stock` |
| Every price, fee and fixed coupon in steps of 250 IQD | checks on `products`, `product_skus`, `stores`, `coupons` |
| One default address per shopper | unique generated `default_for` |
| A coupon code once across Saba; never used more than its limit | `uq_coupons_code`, `ck_coupons_usage` |
| An order adds up; each store's part adds up; each line adds up | checks on `orders`, `order_store_parts`, `order_items` |
| A delivered part always has its bill month, and only then | `ck_order_store_parts_billing_month` |
| A shipped part always has its driver | `ck_order_store_parts_courier` |
| An order line takes one return | `uq_return_items_order_item` |
| One rating per store per order | `uq_store_reviews_order_store` |
| A month is marked paid once | `uq_bill_payments_store_month` |
| A rejection, suspension or takedown always has its reason | checks on `users`, `stores`, `products`, `returns` |
| An order is `PAID` exactly when it is `DELIVERED`, and payment `CANCELLED` exactly when the order is `CANCELLED` or `REFUSED` | `ck_orders_paid`, `ck_orders_payment_cancelled` |
| An order's and each part's subtotal, discount and delivery fee are in steps of 250 IQD | `ck_orders_money_steps`, `ck_order_store_parts_money_steps` |
| A product has its Arabic name (at least 3 letters) | `ck_products_name_ar` |
| A product option has its label and its own price together, or neither (the product's single default option) | `ck_product_skus_options_label`, `ck_product_skus_options_price` |
| An SMS code is used only after it was verified | `ck_otp_challenges_consumed` |
| An upload is a JPEG, PNG or WebP picture | `ck_media_files_content_type` |
| A code (status, role, governorate, phone, coupon code) matches its list exactly: `pending` is refused where `PENDING` is allowed | code columns are `ascii` / `ascii_bin` |
| One checkout per idempotency key | key of `idempotency_keys` |
| One registration per SMS code | `consumed_at`, set by a conditional update |

**Rules across rows stay in the code** (the reviewer's item 15, 2026-09-30, checked and left): an order equal to the sum of its store parts; a store part equal to the sum of its lines; a refund at most what was paid; a return at most what was bought; an order delivered only when every part is done. A CHECK sees one row, so the database would need triggers. With binary logging on (always, on a managed MySQL), a trigger needs the `SUPER` privilege or the server setting `log_bin_trust_function_creators = 1`: this laptop's MySQL refused migration 0009's triggers, and it is not certain the hosted database allows that setting. A migration failing on the live database would stop the launch, so it wasn't safe. Each rule is kept by the one piece of code that writes those rows, and pinned by a test (buying: the numbers and the two-store order; returns: at most what was bought, the refund is what was paid). If the host's database is set up with `log_bin_trust_function_creators = 1` one day, the triggers can be added then.

---

## 5. Transactions and row locking

### 5.1 How

- **InnoDB's default isolation (`REPEATABLE READ`).** Every read that decides a write is a locking read (`SELECT … FOR UPDATE`) or a conditional update (`UPDATE … WHERE status = 'PENDING'` and check the affected rows).
- **One lock order, everywhere:** the shopper's `users` row → `coupons` → `stores` → `orders` → `order_store_parts` → `returns` → `product_skus` in ascending `id`. Two transactions that take locks in the same order can't wait on each other in a circle.
- **A deadlock is retried once** by the transaction helper (MySQL error 1213). Anything else fails and rolls back.
- **Events and notifications to other devices go out after the commit**, never inside the transaction. The notification *rows* are written inside it.

### 5.2 Which operations, and how each is kept safe

| Operation | Why it needs a transaction | Locks and guards |
|---|---|---|
| **Place an order** (money and stock) | The order, its parts and lines, the stock, the coupon count, the cart and the stores' notifications succeed or fail together | The shopper's `users` row `FOR UPDATE` (one checkout per shopper at a time), then the idempotency key (a finished key returns its stored order), then the coupon `FOR UPDATE` (live, uses left), the stores `FOR SHARE` (still approved and open, so a suspension can't slip in between), then each `product_skus` row `FOR UPDATE` in `id` order. Refuse if any has less stock than asked; else `stock = stock − qty`, one `stock_movements` row each. |
| **Shopper cancels** (stock) | Parts, stock, the order's status and payment together | The order `FOR UPDATE`, its parts `FOR UPDATE`. Only while every live part is `PENDING` or `CONFIRMED`, else 409. Stock back, `ORDER_CANCELLED` movements. |
| **Store moves its part** (stock and money) | The part, the order's status, payment and delivery time, the stock on decline or refusal, the bill month | The order `FOR UPDATE`, then the part `FOR UPDATE`. Transition table (below), else 409. `CANCELLED` and `REFUSED` put stock back; `DELIVERED` writes `delivered_at` and `billing_month`. |
| **Shopper asks for a return** (money) | The return and its lines together | The order `FOR UPDATE`. The unique `order_item_id` refuses a second return of a line, even from two requests at once. No stock moves yet. |
| **Store answers a return** (stock and money) | The status, `refund_month` and the stock together | The return `FOR UPDATE`. `REQUESTED` → `APPROVED` or `REJECTED` (reason required); `APPROVED` → `REFUNDED` (stock back, `RETURN_REFUNDED` movements). |
| **Store changes stock** | Stock and its ledger row together | A conditional update: `stock = GREATEST(0, stock + delta)` for an adjustment, a direct value for "set". |
| **Store saves a product** | The product, its images and options together | The product `FOR UPDATE`; options matched by id; removed options get `deleted_at`. |
| **Registration** | The code used once, the account, the store (for a store owner) | A conditional update sets `consumed_at` (0 rows means already used); unique phone and unique store name refuse duplicates. |
| **Refresh a token** | Rotate, or revoke the family on reuse | A conditional update: `revoked_at = now WHERE token_hash = ? AND revoked_at IS NULL`. |
| **Admin answers, suspends, takes down** | The record, the audit row and the notification together | A conditional update on the expected status; 0 rows is 404 or 409. |
| **Mark a bill paid or not paid** (money) | The payment row and the audit row together | The unique `(store_id, month)` refuses a second mark. |
| **Rate an order** | The review, the store's rating total, the order's `rated_at` together | Stores first (`rating_sum = rating_sum + ?`), then the order, as the lock order says. The unique `(order_id, store_id)` refuses a second rating. |
| **Save the featured rail** | Delete and insert together | No lock: the last save wins, and the rail is filtered by status when read. |

### 5.3 A store's part: the transitions the server allows

The demo accepts any status from the store. The server allows only these:

| From | To | Needs |
|---|---|---|
| `PENDING` | `CONFIRMED` | |
| `PENDING` | `CANCELLED` | A decline reason code. Stock goes back. |
| `CONFIRMED` | `PROCESSING` | |
| `PROCESSING` | `SHIPPED` | `courierName` and `courierPhone` (422 on the missing one) |
| `SHIPPED` | `DELIVERED` | |
| `SHIPPED` | `REFUSED` | The shopper refused it at the door. Stock goes back. |

`DELIVERED`, `CANCELLED` and `REFUSED` are ends. This is exactly what the store's screens offer: "Next" follows `NEW → CONFIRMED → PROCESSING → SHIPPED → DELIVERED`, Decline is shown only on a new order, "Refused at the door" only on a shipped one.

### 5.4 The test that proves it

Spec §62, kept as a permanent test: stock = 1, two shoppers place an order for it at the same moment. Exactly one succeeds, the other gets 422 `INVENTORY_ERROR`, and stock ends at 0 with one `ORDER_PLACED` movement. The same test is run for a coupon with one use left, and for one checkout sent twice with the same idempotency key.

---

## 6. The numbers, as whole-number arithmetic

Money never passes through a floating-point number. `⌊x⌋` rounds down.

| Number | Rule | Source |
|---|---|---|
| **Cash step** | `⌊x / 250⌋ × 250` | `_cashSteps` |
| **Coupon, percentage** | `base` is the store's buyable lines in the cart; `discount = ⌊base × value / 25000⌋ × 250` | `_buildCart` |
| **Coupon, fixed** | `min(value, base)` | `_buildCart` |
| **Coupon minimum** | Below `min_order_amount`, the discount is 0 and the coupon stays on the cart with `applies: false` | BUGS 166 |
| **Delivery fee** | The store's `fee_inside` when the address is in its governorate, else `fee_outside`; nothing when it doesn't deliver there or is closed | `_deliveryTerms` |
| **A store's part** | `subtotal` = its buyable lines; `discount` = the coupon's, if it is this store's; `amount_due = subtotal − discount + shipping_fee` | D7 |
| **The order** | `subtotal` = the parts' subtotals; `discount` = the coupon's; `shipping` = the parts' fees; `total = subtotal − discount + shipping`. No tax: Iraq charges no VAT on these goods. | `_buildCart` |
| **Paid unit price** | `⌊unit × (partSubtotal − partDiscount) / (partSubtotal × 250)⌋ × 250` | `_createOrder`, BUGS 161, 175 |
| **Refund** | Σ `paid_unit_price × quantity` over the returned lines | `_createReturn` |
| **A month's bill** | `sales` = Σ (`subtotal − discount`) of the store's parts delivered that month (the delivery fee is the store's own, not a sale); `returned` = Σ `refund_amount` of its returns refunded that month; `owed = 0` when `sales − returned ≤ 0`, else `⌊((sales − returned) × rate + 12500) / 25000⌋ × 250` (to the nearest 250) | `_bill`, contract §3.7, D7b |
| **First-order limit** | A shopper with no order that is both `DELIVERED` and `PAID` can place at most 1,000,000 IQD | `_overFirstOrderLimit` |
| **Return window** | A line can go back within 7 days of its part's `delivered_at`, once | `_applyReturnWindow` |

---

## 7. Worked out when read, never stored

Each of these is a query or a small function, so it can't disagree with the data it comes from:

- A product's shown price, original price, discount and sale state (§3.3).
- A product's stock (the sum of its options') and `stockStatus`.
- Whether a product is listed, browsable, and `inShop` for the admin (with the reason when not, D-P1).
- A line's status, `deliveredAt` and `canReturn`; an order's `canCancel` and `canReturn`.
- A return's steps and its `refund` block.
- Every bill, and Finance's rows, months and totals.
- The store's dashboard, analytics, inventory "reserved" and "sold", "still open" figures.
- A shopper's order count and total spent; a store's `productCount` (drafts not counted).
- Unread counts: notifications, chats.
- Every count in the admin's filter chips.

---

## 8. Reference data, seed data, admins

| What | How | Where it runs |
|---|---|---|
| The 19 governorates; the 7 categories and their 6 sub-categories | Migrations | Everywhere, production included |
| The demo world (Q10): 8 stores and their owners, 56 products with options and stock, the 3 demo accounts, brands, banners, featured stores, coupons, 3 months of delivered history with refunded returns, the demo photos | `npm run seed`, which refuses to run when `NODE_ENV=production` | Development and demos only |
| Saba's staff | `npm run create-admin`, a command-line script that asks for the name, email, phone and password | Anywhere; never through an endpoint |

---

## 9. Left out of v1, on purpose

| Spec §52 table | Why not in v1 | Comes back with |
|---|---|---|
| `roles`, `permissions`, `user_roles` | Three fixed roles | Staff roles |
| `customers`, `merchants`, `merchant_stores`, `merchant_documents` | Folded into `users` and `stores`; no documents | Store verification documents |
| `attributes`, `attribute_values`, `product_variant_attributes` | No product carries attribute data; the form doesn't collect it (Q5) | Attribute filters |
| `product_videos` | Videos are out of v1 | Product videos |
| `inventory`, `inventory_transactions` | `product_skus.stock` and `stock_movements` | — |
| `product_comparisons` | Compare is out of v1 | Compare |
| `payments`, `payment_transactions`, `refunds` | Cash only: payment status is on the order, the refund on the return | Cards and wallets (v2) |
| `shipments`, `shipment_tracking` | Stores' own drivers; no tracking numbers (BUGS 125) | Delivery companies |
| `coupon_usage` | No per-shopper coupon limit in v1 | Per-shopper limits, Saba-wide coupons |
| `promotions`, `flash_sales` | A flash sale is two product columns | Saba-run campaigns |
| Product `reviews`, `review_media`, `review_votes` | Stores are rated, not products | Product reviews |
| `loyalty_*`, `referrals` | Not in v1 | — |
| `commissions`, `merchant_payouts`, `payout_transactions` | Bills are worked out; payments are `bill_payments` | Partial payments (contract §5) |
| `homepage_sections` | Home is worked out from the data | An editable Home |
| `app_settings` | v1's rules are constants in one file | A rate the admin can change |

**Ceilings, and what replaces each:**

| Choice | Fine until | Then |
|---|---|---|
| `LIKE` search on folded columns | About 50,000 products | MySQL `FULLTEXT` with the `ngram` parser, or a search service |
| Bills worked out on every read | Thousands of stores | Store each closed month once, at the month's end |
| Events and rate limits held in the server's memory | One server process | Redis |
