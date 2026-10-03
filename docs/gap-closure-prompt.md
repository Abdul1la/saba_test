# Development brief — Mobile Phase 2: Gap Closure

A ready-to-use prompt for closing the 23 known gaps between the Flutter app and
the master specification. Hand this to an engineer or paste it to an AI
assistant.

**Phases 1 and 2 (G0 and G1) are already done** — see PROJECT-STATUS.md §4.4.
Start at Phase 3.

Section references like "§14" point at
`Production_Marketplace_Master_Development_Prompt.pdf`.

---

## 0. Role and objective

Act as a senior Flutter engineer continuing an existing production codebase.

The Saba marketplace mobile app (`mobile/`) is built and passing: 139 Dart
files, `flutter analyze` clean, 110 tests green, Android and web builds
succeeding. Customer and merchant experiences exist end to end against the REST
contract in §53.

Close the remaining gaps between the built app and the specification. This is
not a rewrite. You are extending a working system.

## 1. Non-negotiable constraints

Preserve the existing architecture:

1. Repositories return `Result<T>`. **Never throw into the presentation layer.**
2. `domain/` stays pure Dart — no Flutter, no Dio, no JSON.
3. Every new API path goes in `core/config/api_endpoints.dart`. Nowhere else.
4. Every new error maps through `ErrorMapper` into a typed `Failure`.
5. Every new user-facing string goes in `strings_en.dart` **and**
   `strings_ar.dart`, then run
   `dart run tool/generate_localizations.dart`. A missing translation must
   break the build.
6. Every new route gets an entry in `RouteAccessTable`. It fails closed; do not
   weaken that.
7. Every new list screen uses `PagedNotifier<T>` and `PagedListView`. Do not
   hand-roll pagination.
8. Every new screen renders loading, empty and error states via
   `AsyncStateView` / `EmptyStateView` / `AppErrorView`.
9. Never trust the client for price, total, role, stock, ownership or
   eligibility.
10. Keep `flutter analyze` at zero issues and all tests green after every gap.
11. **Demo mode:** new endpoints must also be answered by
    `core/mock/mock_api_interceptor.dart`, or the new screen will show an empty
    state in demo mode.

---

## 2. Already done

### G0 — Media upload infrastructure (§56) ✅

`MediaPicker` interface over `image_picker`/`file_picker`; `MediaRepository`
with multipart upload, progress and cancellation; pure-Dart `MediaValidator`
(MIME, extension, byte size, image dimensions); shared `MediaUploadField`
widget with pick, preview, reorder, remove, retry and progress. Uploads are
cancellable and a failed item never loses the others.

Endpoints added: `POST /api/v1/media/upload`, `DELETE /api/v1/media/:id`.

**Use this for every gap below that needs a file.** Do not write per-feature
upload code.

### G1 — Payment action handling (§14) ✅

`PaymentActionScreen` hosts the provider's page in an in-app browser.
`PaymentReturnDetector` recognises return and cancel URLs. The redirect result
is a navigation observation only — the order is re-read from the backend and
its `paymentStatus` is the only thing trusted. The app never renders a card
number, expiry or CVV.

---

## 3. Gaps — customer side

### G2 — Reviews, full (§20)

Only "write a review" exists. `productReviews`, `reviewHelpful`, `reportReview`
are declared but never called.

Add: paginated review list on product detail with rating-breakdown histogram,
verified-purchase badge, helpful votes and merchant responses; filter by stars;
sort by newest / most helpful; helpful voting (one per customer, optimistic with
rollback); report a review; photo and video upload on review creation (uses
**G0**); edit and delete your own review. A merchant must never be able to alter
a customer's rating anywhere in the UI.

### G3 — Product questions and answers (§8)

`productQuestions` is dead. Add a Q&A section to product detail: paginated
list, ask a question, see merchant answers, vote a question helpful.

### G4 — Wishlists, full (§18)

Only a single default list exists. `wishlists`, `wishlistItems`,
`wishlistItem`, `shareWishlist` are dead.

Add: multiple named wishlists (create, rename, delete); move an item between
lists; share a wishlist via a server-side link; price-drop and back-in-stock
alert opt-in per item, persisted server-side.

### G5 — Returns and refunds tracking (§19)

A return can be requested, then disappears. `returnRequest` and `refunds` are
dead.

Add: returns list covering the full state machine
`REQUESTED → APPROVED → REJECTED → PICKUP → RECEIVED → REFUND_PENDING →
REFUNDED → CLOSED`; return detail with a status timeline, the submitted reason
and photos; photo upload on the request (uses **G0**); a refund tracking view
(amount, method, expected date, state); show the return deadline and hide the
action once the window closes — the server still decides.

### G6 — Order invoice (§15)

`orderInvoice` is dead. Add invoice view and download/share from order detail.

### G7 — Cancel-order reason (§15)

The cancel action hardcodes `'CUSTOMER_REQUEST'`. Replace with a reason picker
plus an optional note, matching the backend's vocabulary.

### G8 — Flash sales screen (§40)

`flashSales` is dead; only a home rail exists. Add a dedicated screen: live
countdown, sale inventory remaining, per-customer quantity cap, and a clear
"sale ended" state driven by the server.

### G9 — Storefront reviews (§22)

`merchantReviews` is dead. Add a reviews tab to the storefront with the store
rating breakdown, and let a customer rate the store.

### G10 — Search filters outside a category (§11)

Dynamic filters currently require a `categoryId`, so plain search results get
no attribute filters. `searchFilters` is dead. Wire it so the backend returns
the facet set for the current result set.

### G11 — Share and report a product (§8)

`reportProduct` exists in the repository with **no caller**. Add the report UI
(reason + description). Add a share sheet via `share_plus` with a deep link.

---

## 4. Gaps — account and platform

### G12 — Push notifications (§45)

No push registration exists at all. Add FCM/APNs registration, device-token
upload, foreground and background handlers, notification tap → deep link, and a
permission request with a graceful denial path. Keep it behind a
`NotificationProvider` interface (§69) so the vendor can change without
touching the domain.

### G13 — Notification preferences (§45)

`notificationPreferences` is dead. Add a preferences screen: per-channel (push
/ in-app / email / SMS) × per-category toggles, persisted server-side.

### G14 — Session management and revocation (§5)

`sessions` and `revokeSession` are dead. Add a screen listing active sessions
with device, location and last-active time; allow revoking one session or all
others. This is a security feature — treat it as one.

### G15 — Email verification deep link (§5)

The verify-email screen only resends and polls. `verifyEmail` (POST with token)
is dead. Handle `saba://verify-email?token=…`, post the token, refresh the
session.

### G16 — Attachments in support and messaging (§43, §44)

Both are text-only. Add attachment upload and preview to support tickets and
conversations (uses **G0**).

### G17 — Address geolocation (§46, §47)

`Address.latitude` / `longitude` exist and are never populated. Add an optional
map picker behind a `MapsProvider` interface. **Do not hard-wire a single map
vendor** (§47).

---

## 5. Gaps — merchant side

### G18 — Product media management (§24)

A merchant can create a product but **cannot attach a single image**. The most
visible gap in the merchant experience. Using **G0**: multi-image upload,
drag-to-reorder, set primary image, delete, and video upload where supported.

### G19 — Product variant editor (§10, §24)

Customers can buy variants; merchants cannot create them. Add a variant matrix
editor: pick option axes from the category's variant attributes, generate
combinations, edit per-variant SKU, barcode, price, discount, stock, weight,
dimensions and image.

### G20 — Promotions and coupons (§27, §39)

`merchantPromotions` and `merchantCoupons` are dead. Add create/edit/list for
product discounts, store discounts, coupons (percentage, fixed, minimum order,
maximum discount, usage limit, per-customer limit, validity window,
first-order-only, free shipping), flash-sale participation, and
buy-more-save-more. All coupon validation stays server-side.

---

## 6. Optional — only if explicitly requested

- **G21 — Loyalty (§41) and referrals (§42).** §41 is marked *Optional* and no
  endpoints are declared. If asked: points balance, tiers, redemption,
  immutable points history, referral code and link, tracking and rewards.
- **G22 — Guest checkout (§13).** Currently a deliberate deferral. If required:
  guest cart, guest order placement, order claiming on later sign-up. State the
  abuse-prevention approach before building.
- **G23 — Video playback (§8).** Product videos render as thumbnails only. Add
  inline playback.

---

## 7. Testing requirements (§61)

Every gap ships with tests. At minimum:

- **G2** — vote optimistic update rolls back on failure; a merchant cannot
  alter a rating.
- **G5** — every return state renders; the deadline-expired path hides the
  action.
- **G14** — revoking the current session signs the user out.
- **G18 / G19** — the variant matrix produces the expected combinations;
  per-variant fields round-trip.
- Widget tests for every new form: empty, invalid, server field error, and RTL
  rendering.

---

## 8. Definition of done (§72)

A gap is closed only when **all** of these are true:

- [ ] UI exists and is reachable from a real navigation path
- [ ] It calls a real endpoint declared in `ApiEndpoints`
- [ ] Route access is declared in `RouteAccessTable`
- [ ] Input is validated client-side, and **server field errors land on the
      right field**
- [ ] Loading, empty and error states exist, with retry where retrying helps
- [ ] All strings are in both language files, and RTL is verified
- [ ] Demo mode answers the new endpoint
- [ ] Tests exist and pass
- [ ] `flutter analyze` reports zero issues
- [ ] No parsed field is left unread, and no repository method is left uncalled

### How these gaps were found — re-run this check before declaring done

Two mechanical checks surfaced every gap in this document:

1. **An endpoint declared but never called is an unbuilt screen.** Extract the
   names from `api_endpoints.dart` and grep the rest of `lib/` for
   `ApiEndpoints.<name>`. At the time of the audit: 108 declared, 32 never
   called, of which 20 were genuine gaps and 12 were false alarms (the data
   arrives embedded in another response).
2. **A field parsed but never read is a dead feature.** This is how G1 was
   found: `requiresPaymentAction` and `paymentActionUrl` were parsed from JSON
   and never used by any widget, which meant card payment could not complete.

A third check is worth repeating: grep for capabilities the app claims but has
no dependency for — `image_picker`, `share_plus`, `firebase`, `url_launcher`,
`webview`, `MultipartFile`. Their absence is how the five upload-blocked gaps
were identified.

---

## 9. Implementation order

| Phase | Gaps | Why this order |
|---|---|---|
| ~~1~~ | ~~G0~~ | ✅ done — five gaps were blocked on it |
| ~~2~~ | ~~G1~~ | ✅ done — online payment was broken |
| **3** | G18, G19 | A merchant cannot list a real product without images or variants |
| 4 | G5, G6, G7 | Post-purchase is a dead end today |
| 5 | G2, G3, G9, G11 | Social proof drives conversion |
| 6 | G12, G13, G14, G15 | Retention and account security |
| 7 | G4, G8, G10, G16, G17 | Remaining feature completeness |
| 8 | G20 | Merchant growth tools |
| 9 | G21–G23 | Only on request |

---

## 10. A caveat worth keeping in mind

These are gaps in the **frontend**. Several of them — G1's payment
verification, G5's return state machine, G20's coupon rules — are mostly
backend work, and the mobile screens cannot be finished until that backend
exists. Nothing in this app is "done" by §72 until the chain reaches MySQL.
