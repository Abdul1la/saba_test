# The admin panel: what it has to do

Written 2026-09-23, at step 4 of the bug fixing. Saba's staff have no panel yet. The app now has a **demo admin** — one screen, reached by signing in as an admin account — so a client demo can show a store being approved. This file is what the real admin web app has to cover, and it is kept up to date as the app grows.

Keep this in step with `BACKEND_READY.md` (how screens stay fresh) and `PROJECT_MAP.md` (how the app is built).

## 1. What exists today (the demo stand-in)

| | |
|---|---|
| **Who** | `admin@saba.app`, phone 0770 999 9999, any password. Not shown on the sign-in screen with the other demo accounts. |
| **Where** | One screen at `/admin`, reached by signing in. Saba's staff cannot open the shopper or store screens, and nobody else can open `/admin`. |
| **What it does** | Lists new stores and new products waiting for an answer, with **Approve** and **Reject**; and, for the demo only, **Start the demo again**. |
| **Routes it uses** | `GET /admin/queue`, `POST /admin/stores/{id}/approve\|reject`, `POST /admin/products/{id}/approve\|reject`, `POST /admin/demo/reset` (demo only). The web admin can take the first three as they are. |
| **What it is not** | Not the real panel: no search, no history, no filters, no staff accounts, no money. |

## 2. What the real panel must cover

### 2.1 Stores
- **See** every store: waiting, approved, rejected, suspended; with its owner, phone, city, business type, and when it applied.
- **Approve / reject with a reason**, and **suspend / unsuspend** a store that is already selling (a suspended store's products must leave the shop).
- **Read the store's own words:** name, description, address, governorate, delivery settings.
- **Statuses:** `PENDING → APPROVED | REJECTED`, and `APPROVED ↔ SUSPENDED`. The app already knows all four (`MerchantStatus`).
- **The store is told** what happened, in its own language (the app shows it as a notification and on the dashboard's banner).

### 2.2 Products
- **See** every product waiting, with its store, price, stock, photos, category, and both names (Arabic is required).
- **Approve / reject with a reason.** Only an approved product is in the shop: search, categories, a store's page, Home.
- **Statuses:** `DRAFT → PENDING → APPROVED | REJECTED`. The app already knows all four, with labels.
- **Re-review after an edit:** a change to price, name or photos should come back for review (today an edit keeps the status it had — decide the rule).
- **Take a product down** (the shop's side of a suspension), without deleting the store's own copy.

### 2.2a Categories
- **Create, rename, reorder and retire categories**, in both languages,
  with the picture each one shows. In v1 they are fixed in the app's code
  (`MockData.categories`): seven top-level categories with a few
  sub-categories. The panel has to own them before the catalogue grows.
- A category with products in it cannot simply be deleted: its products
  need moving first.
- Product counts per category are worked out from the catalogue, never
  typed in - the demo's invented counts (Cameras "10", with one product)
  were removed for that reason.

### 2.3 Home and banners
- **Home banners:** upload a picture, give it a title and subtitle in both languages, set where it leads (a product, a category, a store, a search, or nowhere), order them, set start and end dates. Today they are fixed in the demo data and lead nowhere.
- **Which categories are on Home**, in what order, and the photo each one shows.
- **Featured stores:** which stores appear, in what order.
- **Flash sale:** in v1 it is the stores' own - a store puts a product on
  one from its product list, with a sale price and an end, and Home shows
  every sale still running. No admin approval: the store owns its price, so
  it owns the discount. The admin may later want to **see the sales
  running** (store, product, price before, sale price, end) and to **cap
  the discount** (say, no more than 70% off, or no sale longer than a
  week).

### 2.4 The rule pages
- **Terms, Privacy and the Return policy**, each in Arabic and English, with a "last updated" date. Today they are text inside the app (`features/legal/legal_screen.dart`), and a lawyer in Iraq has to read them before launch.
- The app reads them from the server, so the panel must be able to publish a new version without an app update.

### 2.5 People and orders (read, mostly)
- **Find a shopper or a store** by phone, name or order number, and see their orders — for support calls.
- **See one order** as both sides see it, with its history. **Never** change an order's status by hand: only a store moves an order along (see `PROJECT_MAP.md`). If a manual fix is ever needed, it must be written in the history as "changed by Saba".
- **Returns:** see them; step in only when a store and a shopper disagree.

### 2.6 Money
- **What each store owes Saba:** one rate for everyone, about 8%, billed monthly, of delivered sales minus returns. The panel shows each month's bill, what has been paid, and marks a payment received.
- Changing the rate is a Saba-wide decision: one setting, with a date it starts from.

### 2.7 Saba's own staff
- More than one admin, each with their own account; a record of who approved or rejected what, and when. Today there is one demo admin and nothing is recorded.

## 3. What the backend must provide

Everything above needs endpoints under `/admin`, all of them refusing anyone who is not staff (the demo server already answers `403 Admins only` — keep that shape). For each list: paging, a status filter and a search term.

```
GET  /admin/queue                          what is waiting (stores + products)
GET  /admin/stores?status=&q=&page=        every store
POST /admin/stores/{id}/approve            { reason? }
POST /admin/stores/{id}/reject             { reason }
POST /admin/stores/{id}/suspend            { reason }
GET  /admin/products?status=&q=&page=      every product
POST /admin/products/{id}/approve          { reason? }
POST /admin/products/{id}/reject           { reason }
GET/POST/PUT/DELETE /admin/banners         Home banners
GET/PUT             /admin/legal/{page}    terms, privacy, returns
GET  /admin/orders?q=&status=&page=        for support
GET  /admin/bills?month=                   what stores owe
POST /admin/bills/{id}/paid                a payment received
```

Also needed:
- **Every answer reaches the other side at once.** An approval creates a notification for the store and, for a product, changes what shoppers can find. With the event channel in `BACKEND_READY.md`, an approval should announce the subjects `stores`, `products` and `notifications`.
- **A record of every action**: who, what, when, and the reason.
- **Rejection reasons in both languages**, or a code the app translates.

## 4. Rules the panel must not break

1. **Only a store moves its own orders along.** Saba approves stores and products; it does not confirm or ship orders.
2. **A shopper's data belongs to the shopper.** Support may read an order, not sign in as them.
3. **Arabic is not optional.** A product without an Arabic name cannot be approved (the demo server already refuses to save one).
4. **One commission rate for every store** in v1.
5. **Nothing may sit waiting for ever.** Whatever the panel does, a store or product that has been waiting too long must be visible and answerable — that is the bug this step fixed (`BUGS.md` 1, 5 and 6).

## 5. Still missing after this step

- No history of who approved what. (A rejection's reason is now kept and
  sent to the store: `website/API_CONTRACT.md` 6.2.)
- No suspending a store or taking a product down once approved.
- No banners, no category or featured-store editing, no rule-page editing.
- No admin for support: no search across shoppers, orders or stores.
- One admin account only, and the demo admin's password is not checked (nothing in demo mode is).
