# Saba — project map

A guide to how the app is built. This was written by reading the code; no code was changed. State as of 2026-09-22, commit `9ffe972` ("backup before bug audit").

## 1. What the app is

Saba is a marketplace app for Iraq with many stores. Shoppers buy from many stores in one cart, pay cash to each store's driver, and can return within 7 days. Stores run their shop from the same app.

- **Flutter 3.47**, Dart. State with **Riverpod 3**, navigation with **GoRouter 17**, network with **Dio**.
- **Demo mode (now):** there is no backend. A fake server inside the app answers every request (see section 6). The switch is `USE_MOCK_DATA` in `mobile/lib/core/config/app_config.dart`: it is off unless a build asks for the demo (`--dart-define=USE_MOCK_DATA=true`), and always off in a production build. `flutter test` runs against the demo (`mobile/test/flutter_test_config.dart`).
- **Two languages:** English and Arabic (right to left). **Light and dark theme.**
- About **58,600 lines** of Dart in `mobile/lib`, **61 test files** (500 tests), and **931 text keys** per language.

## 2. Roles

| Role | Who | Where they land | Tabs at the bottom |
|---|---|---|---|
| **Shopper** (`CUSTOMER`) | People who buy | Home (`/home`) | Home · Categories · Cart · Orders · Account |
| **Merchant** (`MERCHANT`) | A store owner | Dashboard (`/merchant`) | Dashboard · Products · Orders · Analytics · Account |
| **Admin** (`ADMIN`) | Saba staff | Demo admin (`/admin`) | none: one screen |

- The role comes from the server when the person signs in (`UserRole` in `features/auth/domain/entities.dart`).
- One place decides who may open which screen: `_redirect` and `RouteAccessTable` in `core/router/app_router.dart`.
  - A shopper who opens a store screen is sent to Home, and a store owner who opens a shopper tab is sent to the Dashboard.
  - Product, category, store and search pages are open to everyone, even when signed out.
- **Admin:** `admin@saba.app` (phone 0770 999 9999) signs in like anyone else and lands on one screen: what is waiting for an answer. It approves or rejects **new stores** and **new products**, and can start the demo again from scratch. Saba's staff cannot open the shopper or store screens, and nobody else can open `/admin` - the demo server refuses the routes too, not only the router.
- The real admin is a **web panel, still to be built**: `ADMIN_REQUIREMENTS.md` lists everything it has to cover (banners, the rule pages, support, money, a record of who approved what).

### How something becomes visible to shoppers

| | Waiting | Answered by | Then |
|---|---|---|---|
| **A new store** (opened in the app) | `PENDING` | an admin: approve or reject | `APPROVED` - the dashboard's "under review" banner goes, and it sells. `REJECTED` - it is told so. (`SUSPENDED` exists in the app and no screen sets it yet.) |
| **A new product** (added by a store) | `PENDING` | an admin: approve or reject | `APPROVED` - it is in search, its category, its store's page and Home, and can be bought. `REJECTED` - only its own store sees it. (`DRAFT` exists for a product not sent yet.) |

- The demo's own eight stores and 56 products are approved from the start.
- A product belongs to its **store**, not to whoever is signed in, so an admin can see it and a shopper can buy it whoever added it.

### Demo accounts

| Account | Phone | Role | Store |
|---|---|---|---|
| Amina Saleh, `shopper@saba.app` | 0770 123 4567 | Shopper, Baghdad | — |
| Omar, `merchant@saba.app` | 0771 123 4567 | Merchant | Nova Electronics (`m-1`) |
| Layla, `merchant2@saba.app` | 0780 123 4567 | Merchant | Atlas Home (`m-2`) |

- The demo server doesn't check passwords: any password signs in.
- New shoppers and stores can sign up by phone during a session. The code from the "SMS" is shown on screen in demo mode.

## 3. Folders

```
saba_test/
├── mobile/                  ← THE APP (everything real is here)
│   ├── lib/
│   │   ├── main.dart        ← starts the app, loads saved settings first
│   │   ├── app.dart         ← MaterialApp: theme, language, router, text size limit (max 1.4)
│   │   ├── core/            ← shared by every feature
│   │   │   ├── config/      ← app_config (demo switch, API address), api_endpoints (every URL)
│   │   │   ├── constants/
│   │   │   ├── errors/      ← how failures are turned into messages
│   │   │   ├── localization/← strings_en.dart, strings_ar.dart → app_localizations.dart (generated)
│   │   │   ├── location/    ← Iraq's 19 governorates, the picker, store delivery rules
│   │   │   ├── mock/        ← THE DEMO SERVER: mock_api_interceptor.dart + mock_data.dart
│   │   │   ├── network/     ← Dio setup, auth token + refresh, response wrapper
│   │   │   ├── providers/   ← language, theme, API client, paging helper, session events
│   │   │   ├── router/      ← routes, guards, the two bottom-tab shells, deep links
│   │   │   ├── storage/     ← saved settings (shared_preferences), tokens (secure storage)
│   │   │   ├── theme/       ← colours, fonts (AppTypography), spacing, icons (SabaIcons)
│   │   │   ├── utils/       ← formatters (IQD, dates), validators, Iraqi phone, Arabic search folding
│   │   │   └── widgets/     ← 26 shared widgets: buttons, cards, headers, empty/error states…
│   │   └── features/        ← one folder per part of the app (next section)
│   ├── assets/              ← fonts (IBM Plex Sans Arabic, DM Serif Display, Amiri), icons (SVG), images
│   ├── test/                ← core/ (logic), features/ (flows), widget/ (screens) — 500 tests
│   ├── integration_test/    ← app_flows_test.dart (runs on a device)
│   ├── tool/                ← generate_localizations.dart (run after editing strings)
│   └── android/ ios/ web/   ← platform folders
├── docs/                    ← mobile-architecture.md, gap-closure-prompt.md
├── design/                  ← the design files (Saba Design System, Screens, Forms)
├── WORK-LOG.md              ← the history of every change, newest at the bottom
├── DESIGN_CHANGES.md        ← the Home redesign (parts A and B)
├── BUGS.md                  ← the bug audit
├── PROJECT_MAP.md           ← this file
└── PROJECT-STATUS.md, SETUP.md, README.md
```

## 4. Features (`mobile/lib/features/`)

Each feature follows the same pattern. Not every feature has every layer.

```
domain/        ← the data models (plain Dart classes) and the repository contract
data/          ← talks to the API: remote calls + mappers (JSON → model)
presentation/  ← Riverpod providers (…_providers.dart), screens/, widgets/
```

Some features (addresses, checkout, merchant, messaging, profile, search, support, wishlist) have an empty `data/` folder: their providers call the API client directly.

| Feature | Screens | Used by |
|---|---|---|
| `auth` | Splash, Language, Choose role, Login, Phone entry, OTP, Register shopper, Register store, Verify email | everyone |
| `home` | Home (banner, city chips, categories, flash sale, coupons, featured stores, all products) | shopper |
| `catalog` | Categories, Product list (category/search results), Product detail, Storefront | shopper (and signed out) |
| `search` | Search (recent + popular searches) | shopper |
| `cart` | Cart (grouped by store, coupons) | shopper |
| `checkout` | Checkout (address → delivery → cash), Order confirmation | shopper |
| `orders` | My orders, Order detail (per-store parts, timeline, call the driver), Invoice | shopper |
| `returns` | Request return, Return detail, return list | shopper (the store approves on its side) |
| `reviews` | Store reviews | shopper (the store reads them, and cannot change them) |
| `wishlist` | Wishlist | shopper |
| `addresses` | Addresses, Address form | shopper |
| `profile` | Account, Profile, Settings | shopper (the store has its own Account) |
| `notifications` | Notifications | both |
| `messaging` | Conversations, Conversation | both (a shopper ↔ a store) |
| `support` | Support tickets, New ticket, Ticket | both |
| `legal` | Terms, Privacy, Return policy | both |
| `media` | image picking and upload for product photos | merchant |
| `merchant` | Dashboard, Products, Product form (with variants), Inventory, Orders, Order detail, Analytics, What you owe Saba (payouts), Store settings (open/closed, delivery), Coupons + form, Account | merchant |

## 5. Data models (the main ones)

All in `features/<name>/domain/entities.dart`.

| Area | Models |
|---|---|
| People | `User`, `UserRole`, `AccountStatus`, `MerchantStatus`, `MerchantSummary`, `OtpChallenge`, `CustomerRegistration`, `MerchantRegistration` |
| Catalogue | `Category`, `Brand`, `Product`, `ProductSummary` (list cards), `ProductVariant`, `ProductMedia`, `ProductMerchant`, `StockStatus`; `ProductQuery` (search/filter/sort/city) |
| Cart | `Cart`, `CartMerchantGroup` (one per store), `CartItem`, `CartTotals`, `AppliedCoupon`, `CouponOffer` |
| Checkout | `CheckoutSummary`, `CheckoutGroup`, `CheckoutLine`, `ShippingOption`, `PaymentMethodOption`, `PlacedOrder`, `CheckoutSelection` |
| Orders | `Order`, `OrderSummary`, `OrderItem`, `OrderStatus`, `PaymentStatus`, `OrderStorePart` (each store's part), `OrderTimelineEntry`, `OrderAddress`, `Invoice` |
| Returns | `ReturnSummary`, `ReturnDetail`, `ReturnItem`, `ReturnStatus`, `RefundStatus`, `RefundRecord`, `ReturnReason`, `CancelReason` |
| Reviews | `Review`, `MerchantResponse`, `ReportReason` — of a **store**, never of a product |
| Home | `HomeSection`, `HomeSectionType`, `HomeBanner`, `FeaturedMerchant` |
| Store side | `MerchantDashboard`, `MerchantProductRow`, `InventoryRow`, `MerchantOrderRow`, `MerchantOrderDetail`, `Courier`, `MerchantAnalytics`, `SalesPoint`, `SabaBill`/`SabaBills` (what the store owes Saba), `ProductDraft`, `MerchantCoupon` |
| Other | `Address`, `Governorate` (`core/location`) |

A shopper's `Order` and a store's `MerchantOrderDetail` are **two views of the same purchase**: the shopper sees the whole order across stores, and each store sees only its own part.

## 6. How a screen gets its data

```
Screen (ConsumerWidget)
   │ ref.watch(someProvider)
   ▼
Provider (Riverpod)  ── caches the answer; ref.invalidate(...) makes it load again
   │
   ▼
Repository / ApiClient  (core/network/api_client.dart, URLs from core/config/api_endpoints.dart)
   │ Dio request, with the Accept-Language header set from the app's language
   ▼
DEMO:  MockApiInterceptor answers in memory (core/mock/)      REAL (later): the backend API
```

Nothing above the network layer knows it is a demo. Setting `USE_MOCK_DATA=false` sends the same requests to a real server.

## 7. How the shopper and store sides share data

There is no backend yet, so **the demo server inside the app is the shared database.** One copy of it lives for the whole app session (`DioFactory.mockBackend`), and every account reads the same copy. That is how a shopper's order reaches the store on the same phone.

### Kept once, read by both sides

| Data | Demo server field | Shopper side | Store side |
|---|---|---|---|
| Orders | `_placedOrders` (the shopper's copy) and `_storeOrders[storeId]` (each store's part) | Checkout writes both. My orders and Order detail read the shopper's copy | The store's Orders read its part. Each step (confirm, shipped with driver, delivered) is written back into the shopper's copy by `_storeMoved` |
| Notifications | `_events`, each with `to` = a shopper's email or `store:<id>`, in English and Arabic | "Your order was shipped"… | "New order"… |
| Which notifications were read | `_readNotifications` ("email/id") | yes | yes |
| Chats | `_chats` | Message a store | the store's inbox answers |
| Store coupons | `_storeCoupons[storeId]` | shown on Home, the cart and the store page; applied at checkout | the store creates, pauses and deletes them |
| Returns | `_storeReturns[storeId]` | Request return | the store approves and hands the cash back |
| Store open/closed | `_closedStores` | a closed store's products and flash offers drop out | the switch in Store settings |
| Delivery settings | `_storeDelivery[storeId]` | "Delivery available", the fee at checkout | Store settings → delivery |
| Stock | `_stockOverrides` | product page, cart limits | Inventory |
| Reviews, questions | `_reviews`, `_questions` | write and read | answer |

### Kept per account

`_switchAccount` sets these aside when someone else signs in, and gives them back when that account signs in again: the cart, coupon, wishlist, addresses, the shopper's order list, returns, support tickets, sign-up details, the store record, and the store's added products and profile edits.

### One order, one status, two words

A shopper's order and each store's part of it are the same thing seen from two sides, so they always hold the same status. Only the **words on screen** differ, on purpose:

| The status | The shopper reads | The store reads |
|---|---|---|
| `PENDING` / `NEW` (waiting for the store) | قيد الانتظار / Pending | جديد / New (clearer for a store owner; the user's choice) |
| `CONFIRMED` → `PROCESSING` → `SHIPPED` → `DELIVERED` | the same word on both sides | |

- **Only the store moves an order along**, from its Orders screen. The shopper can only cancel (while no store has gone past confirmed) or ask for a return after delivery.
- A whole order is **as far as its slowest store**, so an order from two stores says "Confirmed" while one of them has already shipped.
- Cash is marked **paid when every part has been delivered**, never before.

### Categories

Seven, fixed in code for v1 (`MockData.categories`): Phones (Smartphones,
Tablets), Laptops (Ultrabooks, Gaming laptops), Headphones, Smartwatches,
Cameras, Home appliances, Accessories (Cases & Covers, Chargers). No
category carries a product count: the catalogue is counted when asked.

### A merchant looking at their own shop

`isMyStoreProvider(merchantId)` (`merchant/presentation/widgets/
store_preview_bar.dart`) is true when the signed-in merchant owns the
store. The storefront and the product page ask it, and for their own
store show `StorePreviewBar` and none of the buyer's controls.

### Photos in demo mode

There is no file server, so `MediaRepositoryImpl` keeps an uploaded photo
as a `data:` URI when `AppConfig.useMockData` is on, and `AppNetworkImage`
draws it. Photos are shrunk as they are picked (1600px, quality 82) and
product cards are square. A real backend returns an https URL and none of
this runs.

### The demo's own pictures

The seed data (`MockData`) names bundled files, which `AppNetworkImage`
draws with `Image.asset`:

- `assets/images/products/<category>-<n>.jpg`: photos shared by a whole
  category, 800x800. The products of a category take them in turn, and
  the first is the category's own picture. They are made by
  `tool/demo_photos.py` from the originals in `saba_test/demo-photos/`
  (named `phones.jpg`, `phones-2.jpg`, `home-appliances.jpg`, ...), which
  also writes the count per category to `lib/core/mock/demo_photos.dart`.
  To add a variation: drop it in that folder and run the script again.
  The originals stay out of git; only the small copies ship.
- `assets/images/stores/*-logo.jpg` (512x512) and `*-banner.jpg`
  (1000x400): drawn by a script, the store's initial and its own colour,
  so there are no words to get wrong or translate.

The Home promos have no picture on purpose: their offer is in words, the
words switch to Arabic and a picture cannot, so the app draws the words.
`test/core/demo_images_test.dart` fails if a product, category or store has
no picture, names a file that is not there, or one over 200 KB.

### Stock: one number, in one place

Stock is kept per **thing sold**, not per product:

| The product | Where its stock lives |
|---|---|
| No options | its own count |
| Has options | each option's count; the product's figure is their **sum** |

The demo server keeps them in one map keyed by the option's id, or the
product's when it has no options (`_stockOverrides`, `_stockKey`). Everything
reads through `_productStock` / `_variantStock`, so the page, the card, the
shelf and the inventory row cannot disagree. Checkout refuses a cart holding
more than is left, and placing an order takes it from the right option.

### Seed data

`core/mock/mock_data.dart` holds 8 stores (`m-1` to `m-8`, in 6 cities), 56 products (with Arabic names), categories, brands, the Home banners, the demo users, and each demo store's past orders and bills.

### When the real backend comes

The same split applies on a server: one orders table with a per-store part, one notifications table addressed to a user or a store, and one chats table. The app's requests and models do not change. What the demo server does is the contract (see `WORK-LOG.md`, "backend phase to-do").

## 8. Where to change common things

| To change | Go to |
|---|---|
| Any text | `core/localization/strings_en.dart` **and** `strings_ar.dart`, then run `dart tool/generate_localizations.dart` |
| Colours, spacing | `core/theme/` (`app_colors`, `app_dimensions`) |
| Fonts (Home headings) | `core/theme/app_typography.dart`, one place (see `DESIGN_CHANGES.md`) |
| A new screen | add the route in `app_routes.dart` + `app_router.dart` (with its access in `RouteAccessTable`), its URL in `api_endpoints.dart`, and a demo answer in `mock_api_interceptor.dart` |
| Demo products, stores | `core/mock/mock_data.dart` |
| Who can open what | `_redirect` in `core/router/app_router.dart` |

## 9. Tests

- `flutter test` runs all 500 (about 3 minutes); `flutter analyze` checks the code. Both were clean at this commit.
- `test/widget/*_sweep_test.dart` open every shopper and store screen in both languages.
- `test/widget/home_redesign_test.dart` draws Home with the real fonts. Adding `--dart-define=SABA_SHOTS=true` saves pictures to `mobile/build/home_shots/`.
- Every new test was watched failing on broken code before it was trusted (see `WORK-LOG.md`).
