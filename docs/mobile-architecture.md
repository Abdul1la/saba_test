# Mobile Architecture & Decisions

How the Flutter client is built, and every place where a judgement call was made
against the platform specification. Section numbers below refer to the
specification PDF.

---

## 1. Layering

```
Widget (screen)
   ↓ watches
Riverpod provider / controller        ← all decisions live here
   ↓ calls
Repository interface   (domain/)      ← pure Dart, no Flutter, no Dio
   ↓ implemented by
Repository impl        (data/)        ← mappers + ApiClient
   ↓ uses
ApiClient → Dio → REST → backend → MySQL
```

Dependency direction is strictly inward. `domain/` imports nothing but Dart and
`meta`. A screen never sees Dio, JSON or a status code.

This satisfies the definition of done in section 72 for the client half of the
chain: UI → Riverpod → repository → Dio → REST endpoint.

## 2. Errors are values, not exceptions

Every repository method returns `Result<T>` — either `Ok<T>` or `Err<T>` holding
a typed `Failure`. Nothing throws into the presentation layer, so a call site
cannot silently drop an error.

`ErrorMapper` is the only place that knows about Dio. It converts:

- transport problems → `NetworkFailure`, `TimeoutFailure`, `CancelledFailure`
- HTTP statuses → `AuthenticationFailure` (401), `AuthorizationFailure` (403),
  `NotFoundFailure` (404), `ConflictFailure` (409), `ValidationFailure` (422),
  `ServerFailure` (5xx)
- a backend `code` field → the matching failure, **overriding** the bare status

That last rule matters: `409` alone cannot distinguish "not enough stock" from a
generic conflict, but `code: "INVENTORY_ERROR"` can. The failure names mirror the
backend error categories in section 66 exactly, so a failure keeps its meaning
from MySQL to the widget.

Field-level errors from section 54's envelope are attached to the failure and
rendered **on the input they belong to**, not in a generic banner.

## 3. The server is the authority

The app never computes or trusts money, permissions or stock:

- Cart mutations return the **recalculated cart**; totals are displayed, never derived.
- Checkout sends only ids and quantities (`CheckoutSelection.toJson`) — no prices,
  no totals, no merchant ids the client invented.
- `POST /checkout/review` re-prices on every change; the review step shows the
  server's figures.
- Stock caps on the quantity stepper come from the server and are advisory; the
  real check happens inside the backend transaction.
- `canSell`, `canCancel`, `canReturn` come from the API. Hiding a button is a
  courtesy, never the enforcement point.

## 4. Authentication

- Tokens live in the platform keystore (`flutter_secure_storage`), never in
  shared preferences, never in a provider that a widget could print.
- `AuthInterceptor` extends `QueuedInterceptor`, which gives **single-flight
  refresh**: ten simultaneous 401s cause one refresh, and the other nine notice
  the token already changed and simply replay.
- Refresh and replay use a **separate Dio instance** with no auth interceptor, so
  a refresh can never recurse.
- A rejected refresh token increments `sessionEventsProvider`; the auth
  controller watches that counter and signs out. This breaks what would
  otherwise be a dependency cycle between the network layer and the auth feature.
- A transport failure during session restore does **not** sign the user out — the
  splash screen shows the error with a retry, because being offline is not the
  same as being logged out.

## 5. Role separation (sections 51 and 58)

Customers and merchants get **different navigation shells**, not one shell with
hidden tabs. `RouteAccessTable` declares access for every route as data:

`public` · `guestOnly` · `authenticated` · `customerOnly` · `merchantOnly`

The router's single `redirect` enforces it. Two properties matter:

1. **Fails closed.** A route nobody classified defaults to `authenticated`, and
   anything under `/merchant` defaults to `merchantOnly`. A screen added without
   an access decision cannot accidentally ship as public.
2. **It is not security.** The backend authorizes every request independently.
   This table only keeps the UI coherent.

Covered by `test/core/route_access_test.dart`.

## 6. Pagination

`PagedNotifier<T>` is written once and reused by products, orders, notifications,
merchant products, inventory and merchant orders. A feature supplies `fetchPage`
and gets first-page loading, append, refresh and retry for free.

A failure while appending page 4 keeps pages 1–3 on screen and offers a retry for
just the failed page, rather than replacing the list with an error.

## 7. Localization (sections 15, 16, 60)

No user-facing string is written inline in a widget. `strings_en.dart` defines
which keys exist (438 today); `strings_ar.dart` must define all of them.
`tool/generate_localizations.dart` regenerates the typed accessor and exits
non-zero if the two tables disagree — so an untranslated string breaks the build
rather than shipping.

Arabic drives full RTL through `GlobalWidgetsLocalizations`. Layouts use
`PositionedDirectional`, `EdgeInsetsDirectional` and `AlignmentDirectional`
throughout, so mirroring is automatic. Dates, numbers and currency go through
`intl` with the active locale. The chosen language is also sent as
`Accept-Language`, so server error messages match the UI.

---

## 8. Decisions and deviations

Everything below is either a choice the specification left open, or a place where
it is ambiguous. Nothing here was dropped silently.

### 8.1 Changed on your instruction

| Topic | Specification | What was built | Why |
|---|---|---|---|
| Admin interface | Section 30 says admin is "completely separated"; section 58 implies admin routes inside Flutter; section 73 lists only `/mobile` and `/backend` | **No admin UI in the Flutter app.** Admin is a separate React web panel | You specified: app = Node + Dart + MySQL, admin panel = a website. This resolves the PDF's internal ambiguity |
| Admin sign-in on mobile | Not addressed | An `ADMIN` account that signs in here is **immediately signed out** with an explanation | An admin session inside a customer shell would be a privilege surface with no legitimate use |

### 8.1b Demo mode — added later, on the product owner's instruction

| Topic | Specification | What was built | Why |
|---|---|---|---|
| Fake responses | Section 70 forbids "fake API responses" | **Demo mode**: one `MockApiInterceptor` at the Dio layer answers the real contract from in-memory data | The owner asked for a fully navigable UI before the backend existed |

Why it is placed at the Dio layer rather than as fake repositories:

- every repository, mapper, provider and screen above it is the production code
  path, so the real parsing runs and a mapping bug surfaces now;
- switching it off is one flag (`USE_MOCK_DATA=false`) and changes no screen;
- nothing in the app "knows" it is in demo mode;
- it is **force-disabled in production builds**, so fixtures cannot ship.

It lives entirely in `mobile/lib/core/mock/` (two files) plus one `isDemoMode`
branch in `dio_factory.dart`. Deleting those removes it completely.

### 8.2 Choices the specification left open

| Topic | Specification wording | Decision | Rationale |
|---|---|---|---|
| Guest checkout | Section 13: "Guest checkout **where appropriate**" | Browsing is public; **cart, checkout and orders require sign-in** | Guest carts and later order-claiming add real complexity for little early value. The architecture does not prevent adding it |
| Languages | Section 60: "multiple languages" | English + Arabic | RTL is required by section 15, which implies an RTL language. Adding a third is a data change, not a code change |
| Currency | Not specified | Configurable, default `USD`; the API's per-resource currency code always wins | The backend is the authority on currency |
| Merchant browsing | Sections 2 and 58 require strict separation | Merchants may view public catalog pages, but **cart, checkout, wishlist and customer orders are blocked** for them | Separation of *data and permissions*, not a ban on seeing the storefront |
| Card entry | Section 14: never store raw card data | The app **never renders a card form**; a card payment hands off to the provider's own flow | The only way to genuinely never touch card data |
| Riverpod auto-retry | Not addressed | **Disabled** app-wide | Riverpod 3 retries failed providers silently with backoff, which would leave screens spinning instead of showing the error + retry that every screen already provides |

### 8.3 Built to a narrower scope than the specification describes

These are real gaps, listed so nothing looks finished that is not.

**Two have since been closed** — see `gap-closure-prompt.md` for the full
brief and the remaining order:

| Gap | Status |
|---|---|
| Media upload infrastructure (section 56) | ✅ built: picker interface, upload with progress and cancellation, validation, shared `MediaUploadField` |
| Payment action handling (section 14) | ✅ built: provider page in an in-app browser, payment status re-read from the server, never inferred from the redirect |

The merchant product form still does not *use* the upload field — that is
gap G18, the next phase.

| Area | Specification | Built | Missing |
|---|---|---|---|
| Wishlists | Section 18: **multiple** wishlists, price-drop and back-in-stock alerts, sharing | One default wishlist, add/remove/move-to-cart | Named lists UI, alert opt-in UI, share |
| Merchant media | Section 24: manage images and videos | Product create/edit with all text, pricing, stock and dynamic attributes | **Image/video upload UI** (needs a file picker and the storage endpoint) |
| Merchant promotions | Section 27: discounts, coupons, flash sales, BMSM, free shipping | API surface defined in `ApiEndpoints` | No merchant promotion screens |
| Reviews | Section 20: list, images, helpful votes, moderation, merchant responses | Write a review; rating and count on product detail | No review list screen, no photo upload, no helpful votes |
| Product Q&A | Section 8 | Endpoint defined | No UI |
| Notifications | Section 45 | In-app list, read/unread, deep links | **No push registration** (needs FCM/APNs), no preferences screen |
| Flash sales | Section 40 | Home rail with live countdown | No dedicated flash-sale screen |
| Loyalty / referrals | Sections 41–42 (41 marked **Optional**) | Not built | Deferred by agreement |
| Phone verification | Section 5: "phone verification **architecture**" | Not built | The PDF asks for architecture, which is a backend concern |
| Share / report product | Section 8 | Report endpoint defined | No share sheet (needs `share_plus`), no report UI |
| Product variants (merchant) | Section 10 | Variants are fully **displayed and purchasable** on the customer side | The merchant form creates a simple product; a variant matrix editor is not built |

### 8.4 Not applicable to a frontend

Sections 4 (database), 17 (inventory transactions), 29 and 37 (financial
calculation), 55 (idempotency enforcement), 57 (audit logs), 65 (server logging),
68 (background jobs) and 69 (provider adapters) are backend responsibilities.

The client does its part where one exists: it sends an `Idempotency-Key` header
on order placement (section 55) so a retry cannot create a duplicate order, and
it sends `Accept-Language` so server messages are localized.

### 8.5 Dependency versions

`go_router` is pinned to `^17.5.0` and `shimmer`/`cached_network_image` to their
3.x lines. Their newest releases depend on `material_ui` 1.3.0, which uses a
`meta` annotation that does not compile against Flutter 3.44.1. The pinned
versions are API-equivalent for everything this app uses.

---

## 9. Definition of done, honestly

Section 72 defines a feature as complete only when the whole chain is connected
down to MySQL. **That cannot be true of any feature yet, because the backend does
not exist.**

What is true today: every screen is wired to a real repository, calling a real
`ApiClient`, against the documented endpoints from section 53, with real
validation, error handling, loading, empty and error states — and **no mock data
anywhere**. Point the app at a backend that implements the contract and the
flows work. Until then, every screen honestly shows its error state.
