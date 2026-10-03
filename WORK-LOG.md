# Work log

Running note of what was done, what was found, and what is still open.
Kept so nothing is lost between sessions. Reviewed at the end.

**Build order (standing decision):** frontend first, then backend. Demo mode is
the product for now; keep the one-flag backend seam intact.

**Rule:** a step is not finished while it still has a known gap or issue.

---

## Step 0 — Make the project build (closed)

The unzipped copy would not open. Three environment faults, none in the code.

| # | Fault | Fix |
|---|---|---|
| 1 | `mobile/` had no `.dart_tool/` — `flutter pub get` had never run here | ran `flutter pub get` |
| 2 | Flutter 3.41.8 (Dart 3.11.5) older than the project's `sdk: ^3.12.2` | upgraded Flutter to **3.47.5** |
| 3 | `android/local.properties` held the origin machine's paths (`C:\Users\GPC\…`) | deleted; Flutter regenerated it correctly |

Also removed 6 MB of stale `.gradle` / `.kotlin` cache shipped inside the zip.

---

## Step 1 — Sign-in navigation (closed)

**Reported:** tapping *Sign in* does not leave the sign-in screen.
`PROJECT-STATUS.md` §6.1 recorded it as a blocker with an **unconfirmed** cause
and two suspects: the router's `refreshListenable` wiring, or sign-in silently
failing.

**Both suspects were wrong**, each disproved by a test rather than by reading.
The router and redirect are correct, and demo mode answers `/auth/login` with
the right role.

### Actual cause

`TokenStorage.save()` and `clear()` had **no error handling**, while `read()`
directly above them did and documented why. The keystore write happens *after*
the credentials are accepted, so a `PlatformException` there escaped `signIn()`
and then `_submit()` — neither had a try/catch. `setState(() => _isSubmitting =
false)` never ran, so the button span forever: no error, no navigation, no
obvious Dart exception. Exactly the reported symptom.

### Fix

`lib/core/storage/token_storage.dart`, guarded once in the shared place, so all
**six** call sites are covered: login, register customer, register merchant,
token refresh, logout, delete account. The in-memory mirror is set first and
stays authoritative, so a keystore that refuses to write still leaves a usable
session for that run — the same tolerance `read()` already had.

### Why nothing caught it

`test/widget/login_screen_test.dart` mounts `LoginScreen` alone. It proves the
form calls the repository, but the router is not in that harness, so
**navigation had no test coverage at all.** Added:

| Test | Scope |
|---|---|
| `test/widget/app_signin_e2e_test.dart` | the whole app as `main()` mounts it; only platform channels faked |
| `test/widget/login_navigation_test.dart` | the real router, auth stubbed |
| `test/features/signin_pipeline_test.dart` | real controller → repository → Dio → mock → mappers |

The keystore case was verified to **fail without the fix and pass with it**, so
it is a real regression test, not a vacuous one.

**Verified:** `flutter analyze` → 0 issues · `flutter test` → **119/119**
(110 before) · `flutter build web --release` → succeeds on Flutter 3.47.5.

After F7: **123/123**.

---

## Findings — all closed

| # | Finding | Resolution |
|---|---|---|
| F1 | `SETUP.md` §2 claimed "nothing is machine-specific — no absolute paths". False; `local.properties` broke the transfer | corrected, with an explicit warning to delete it before copying |
| F2 | `SETUP.md` §3 pinned Flutter 3.44.2; project now runs 3.47.5 | restated as "3.44.2 minimum, verified on 3.47.5", keyed to the real `sdk: ^3.12.2` constraint |
| F3 | `dart` on PATH is a standalone **3.11.5**, not Flutter's **3.13.4**. `dart run tool/generate_localizations.dart` dies with `reserved exit code: 253` | confirmed by running both; command changed to `flutter pub run …` and a PATH section added. Generator output is byte-identical, so EN/AR were already in sync (438 keys) |
| F4 | Navigation had no test coverage | three tests added (above) |
| F5 | Not a git repository — no backup | `git init` + baseline commit `c2c89e0`, 362 files, 2.4 MB, no build output. Not pushed anywhere |
| F6 | Zip was made without `flutter clean`, which caused Step 0 | troubleshooting rows added for all three failures so the next transfer self-diagnoses |

---

## Step 2 — Phase 3: G18 product media + G19 variant editor (done)

### G18 — merchant product image and video upload

The G0 infrastructure was already built and even shipped
`MediaConstraints.productImages` / `.productVideos` presets, so this was
wiring, not building. Added to `merchant_product_form_screen.dart`: an image
slot (reorderable, first image is the main one) and a video slot. Slot ids are
keyed per product, so editing two products in one session cannot spill one
product's uploads into the other. An existing product's image is seeded into
the slot so editing does not look as though the picture was lost.

`ProductDraft` gained `imageUrls` / `videoUrls`, both omitted from the JSON
when empty.

**Demo-mode gap found and fixed:** the mock answered *every* upload with
`kind: IMAGE`, so a picked video came back as an image and would render as a
broken photo. It now reads the uploaded filename and answers `VIDEO` for
video extensions.

### G19 — variant matrix editor

New `VariantMatrixEditor`. The merchant declares option types with values
(Color: Red, Blue / Storage: 128GB, 256GB) and every combination becomes a row
with its own SKU, price and stock. Rows are keyed by an order-independent
signature, so editing an option regenerates the matrix **without losing what
was already typed into the rows that survive**. An empty price means "inherit
the product price". Editing a product that already has variants recovers the
option types from them, so the matrix opens populated.

`ProductDraft` gained `variants`; `ProductVariantDraft` is new.

### Two bugs my own tests caught before they shipped

| Bug | Fix |
|---|---|
| `TextEditingController` used after dispose — the option dialog's controllers were created in the calling method and disposed as soon as `showDialog` returned, but the dialog is still in the tree during its exit transition | extracted `_OptionDialog` as a StatefulWidget that owns its own controllers |
| `RenderFlex overflowed by 99732 pixels` in the dialog | bounded width + `SingleChildScrollView` around the dialog content |

**Verified:** `flutter analyze` → 0 issues · `flutter test` → **136/136**
(123 before, +13) · 450 localization keys, en + ar in sync.

---

## Step 3 — Phase 4: G5 returns, G6 invoice, G7 cancel reason (done)

**G5 — returns list and detail with refund tracking.** New `returns` domain
(`ReturnStatus` with all eight states from section 19, `RefundStatus`,
`ReturnSummary`, `ReturnDetail`, `RefundRecord`), repository, providers, a
tabbed paged list and a detail screen. The detail shows a progress trail from
Requested to Refunded; a rejected request leaves the trail and shows the
merchant's reason instead, because a progress bar that can never complete is a
lie. Refund tracking shows amount, status, destination, reference and either
the processed date or the expected one.

**G6 — invoice.** `Invoice` / `InvoiceLine` on the orders side,
`fetchInvoice`, and a screen reachable from any order. Every figure is the
server's: the invoice is never recomputed from its lines, so a historical
invoice keeps saying what was actually charged (section 16). There is a test
that feeds it a deliberately inconsistent total and asserts it is reported
unchanged.

**G7 — cancel reason.** Cancelling sent a hardcoded `'CUSTOMER_REQUEST'`.
It now opens a reason picker (5 reasons + optional note) that doubles as the
confirmation. The reason travels as a stable code (`CHANGED_MIND`, …) and the
free-text note separately, so the admin panel and reporting are never parsing
a translated sentence. `cancelOrder` gained an optional `note`.

**Demo-mode gaps found and fixed:** `/returns` answered `{}` so the list could
never populate, and `/orders/:id/invoice` returned the *order* rather than an
invoice. Both implemented, plus the cancel endpoint now records the reason and
note and appends a timeline entry.

**Verified:** `flutter analyze` → 0 issues · `flutter test` → **153/153**
(136 before, +17) · 497 localization keys, en + ar in sync.

---

## Step 4 - Phase 5: G2 reviews, G3 Q&A, G9 store reviews, G11 share/report (done)

**G2 - reviews list.** New `reviews` domain (Review, MerchantResponse,
RatingBreakdown, ProductQuestion, QuestionAnswer, ReportReason, ReviewSort),
repository, providers and a screen with the 1-5 histogram, sorting, star
filtering, photos, verified-purchase badges, seller replies and helpful votes.
Helpful voting is optimistic - the count moves immediately and rolls back on
failure, because a vote that waits for a round trip feels broken.

**G3 - product Q&A.** Paged question list with merchant answers marked, and an
ask dialog that owns its controller (the lesson from Phase 3).

**G9 - store reviews.** Reachable from the storefront header.
`ponytail:` a separate screen rather than a tab, because the storefront is one
paged grid and adding a TabBar would restructure it. Upgrade path noted in the
code.

**G11 - share and report.** Share copies a deep link to the clipboard, so **no
new dependency was added**; swap for `share_plus` if a native sheet is wanted.
Report uses one dialog shared by products and reviews, sending a stable code
plus optional free text.

**Demo-mode gaps found and fixed:** product reviews, merchant reviews and
questions all answered empty pages, so three of the four new screens could
never show anything. Seeded six reviews per product/store (with photos, a
seller reply and verified flags), two questions, plus working sort, star filter
and helpful votes that persist for the session.

**Verified:** `flutter analyze` -> 0 issues - `flutter test` -> **173/173**
(153 before, +20) - 533 localization keys, en + ar in sync.

---

## Step 5 - Phase 6: G13 preferences, G14 sessions, G15 email deep link (done)

**G12 push notifications is deliberately deferred to the backend phase.**
Decided with the user. It needs a Firebase project, `google-services.json`, an
APNs key and a paid Apple Developer account - none of which exist yet, and all
of which are useless without a server to send from. The `NotificationProvider`
interface the spec asks for (section 69) is what keeps this cheap later: G13's
channel model already names PUSH, so registering a device token is an addition,
not a rewrite.

**G13 - notification preferences.** New `notifications/domain` and
`notifications/data` layers (both folders existed but were empty; the whole
feature lived in one presentation file). Per-channel x per-category opt-ins,
sent as one document rather than a stream of single-cell edits, because a whole
document is what a backend can store in one transaction. Two levels: a master
switch per channel and a switch per category. Turning a master off **keeps** the
per-category choices, so turning it back on restores them instead of resetting
them - the reason the rows stay visible and greyed rather than hidden.
Toggling is optimistic and rolls back on failure.

`ponytail:` **security alerts cannot be switched off.** A customer silencing the
one message that would warn them about a stolen account defeats the point of
sending it. Enforced in the entity (`setCategory` is a no-op for it), not just
in the widget. Say the word if you want it configurable.

**G14 - active sessions.** `sessions` and `revokeSession` were dead endpoints.
Now: `UserSession` entity, mapper, data source, repository, controller and a
screen listing every signed-in device with platform, location, IP and last
active time; revoke one, or sign out all other devices. Treated as a security
feature throughout - every revocation is confirmed, and the list is always
**re-read from the server** after one rather than edited locally, because a list
claiming a device is gone while the server still honours its token is worse than
no list.

Revoking **this** device's session signs the user out here and clears the
keystore (new `AuthController.signOutLocally`), since the refresh token it just
killed was ours. That is the case the gap document names by name, and it has a
test.

**G15 - email verification deep link.** `verifyEmail` was dead. Now wired end to
end, and the screen handles being opened cold from an email on a device with no
session - the token is the credential, so `/verify-email` became
`RouteAccess.public`.

### Three real gaps found on the way, all fixed

| # | Gap | Fix |
|---|---|---|
| F8 | **Deep links had no OS plumbing at all.** No Android intent-filter, no iOS `CFBundleURLTypes`. `AppConfig.deepLinkScheme` existed but nothing could ever deliver a link to the app | intent-filter + `flutter_deeplinking_enabled` on Android, URL type + `FlutterDeepLinkingEnabled` on iOS |
| F9 | **The router threw deep links away.** `_redirect` parks every location on `/splash` while the session resolves, then sends splash to `home`. A cold start from an email always lands in exactly that window, so the destination *and its token* were silently lost every time | new `PendingDeepLink`, remembered on the way in and consumed once on the way out. Access is still re-checked, so a link to a protected screen still asks for sign-in |
| F10 | **Demo mode could not fail.** `_Reply` had no status code - every mock answer was a 200, so no screen's error path was reachable in demo mode | `_Reply.statusCode`; >= 400 is rejected as a real `DioException`. An expired verify token now genuinely fails |

Also: a custom scheme parses in a way the router cannot match -
`saba://verify-email?token=x` has an **empty path** and puts `verify-email` in
the *host*, so it would resolve to `/`. `normalizeDeepLink` rewrites it. Pure
function, six tests.

### The vacuous-test mistake, caught again

The first version of the splash regression test **passed with and without the
fix**. With no stored token the session restores instantly, so the app was never
in the loading state the test claimed to exercise. Rewritten to seed the
keystore first, which makes the restore a real round trip; it now asserts
`isLoading` as a precondition and **fails without the fix**. The rule from F7
held: a regression test that has not been seen to fail proves nothing.

One more found by the same discipline: `MockApiInterceptor` is a process-wide
singleton (`DioFactory`), correct for the app but it leaks demo state between
tests - a revocation in one test was visible in the next. Added
`resetForTesting()`.

**Verified:** `flutter analyze` -> 0 issues - `flutter test` -> **213/213**
(173 before, +40) - 574 localization keys, en + ar in sync - 47 screens.

---

## Phase 6.5 - Onboarding redesign (agreed, not yet built)

Decided with the user from three inspiration screenshots (a different app -
style reference only, not our product). Recorded before building so the
decisions survive.

### Build

| # | Screen / change | Detail |
|---|---|---|
| 1 | **Language screen** | First launch only, after splash. English / Arabic. No skip. Uses the already-present but unused `AppPreferences.onboardingSeen`. Also added to Profile |
| 2 | **Role screen** | Reached from "Create account", not on every launch. Two cards: I want to buy / I want to sell |
| 3 | Wizard step 1 | Phone number, `+964` default |
| 4 | Wizard step 2 | 6-digit SMS code with resend countdown |
| 5 | Wizard step 3 | Full name, email, password |
| 6 | Wizard step 4 (merchant only) | Store name, business type, city |
| 7 | Login screen | Merchant entry made clearer |
| 8 | Customer account | "Start selling" - become a merchant without a second account |
| 9 | Merchant dashboard | "Under review" banner + completion checklist (documents, logo, banner, payout) |
| 10 | Market defaults | Iraq `+964`, **IQD** formatted without decimals (`250,000` + symbol), Iraqi seed cities and demo names |
| 11 | Seed categories | All 33 from specification section 7, **grouped into a tree** (5 parents, 28 children, PDF names kept). Category-dependent attributes per section 8 |
| 12 | Shared widgets | Card row, step header with progress, wizard shell |
| 13 | Security alerts | Locked to the **verified credential**, not hard-coded to email (revision of the Phase 6 decision) |

Customer finishes in 3 steps, merchant in 4.

### Settled, do not revisit without a reason

- **Email + password stays the credential.** Phone + OTP is a verification step
  inside registration, not a replacement. Specification section 21 requires
  Email *and* Phone *and* Password; section 6 requires the same four for
  customers, and `CustomerRegistration` already carries phone.
- **Blue stays the brand** (`#1B6EF3`), orange stays the accent.
- **App name stays Saba.** App IDs are already real
  (`com.saba.saba_marketplace` / `com.saba.sabaMarketplace`), so nothing to fix.
- **No driver role.** Section 2 allows exactly three account types and there is
  no delivery module in the specification. Revisit with the backend.
- **New style on new screens only**, with the reusable pieces added to the
  design system so later screens inherit it. No mass restyle of the 47
  existing screens.

### Contract decisions made without asking

1. **Nothing is created until the wizard finishes.** Verifying the phone
   returns a short-lived *registration token*, not an account. Otherwise
   abandoning at step 3 leaves a verified phone attached to no user and the
   backend inherits orphan records. This goes in the mock, so the backend
   implements a contract that already exists.
2. Demo mode accepts any 6 digits, with a hint on screen.
3. Back is allowed between steps; closing the app restarts the wizard. Nothing
   is half-saved on the device.
4. A reinstall shows the language screen again - a fresh install genuinely has
   no saved choice.

### Why this goes before Phase 7

Phase 7 adds roughly four more screens on top of the current auth and the
current styling. Every screen built first is one more to rework, and the design
system should exist before it is needed, not after.

---

## Remaining frontend phases

From `docs/mobile-architecture.md` §8. Phases 1–2 (G0 media upload, G1 payment)
were done before this session.

| Phase | Gaps | What |
|---|---|---|
| ~~3~~ | ~~G18, G19~~ | **Done** — merchant product image upload, variant matrix editor |
| ~~4~~ | ~~G5, G6, G7~~ | **Done** — Returns list, invoice view, cancel reason |
| ~~5~~ | ~~G2, G3, G9, G11~~ | **Done** — Reviews list, product Q&A, store reviews, share/report |
| ~~6~~ | ~~G13, G14, G15~~ | **Done** — notification preferences, sessions, email deep link. **G12 push deferred to the backend phase** |
| **6.5 — next** | — | Onboarding redesign (agreed above): language screen, role screen, registration wizard, Iraq + IQD defaults, full category seed |
| 7 | G4, G8, G10, G16, G17 | Multiple wishlists, flash sales, search filters, attachments, map |
| 8 | G20 | Merchant promotions and coupons |
| 9 | G21–G23 | Loyalty, guest checkout, video — only on request |

**Rule for every new screen:** endpoint in `api_endpoints.dart`, route in
`RouteAccessTable`, strings in **both** `strings_en.dart` and `strings_ar.dart`
(then regenerate), and a matching mock response so demo mode stays complete and
the backend cutover stays one flag.

---

## Findings — F7 also closed

| # | Finding | Resolution |
|---|---|---|
| F7 | `AppPreferences` writes (`setLocale`, `setThemeMode`, `setOnboardingSeen`, recent searches) were unguarded, the same pattern `TokenStorage` had. `state = locale;` runs *after* the write, so a throw left the language unchanged and the tap dead | **Fixed.** All five writes routed through one `_write` helper that swallows a platform failure. Covered by `test/core/app_preferences_test.dart`, verified to fail on 3 tests without the guard |

> **Process note.** The first version of that test was **vacuous** — it mocked
> the wrong method channels, so the writes never actually failed and it passed
> with *and* without the guard. Rewritten to install a real
> `SharedPreferencesStorePlatform` whose writes throw. **A regression test that
> has not been seen to fail proves nothing; always remove the fix and watch it
> go red.**

---

## Known, accepted, not a defect

- The repo root still holds the unused `flutter create` scaffold (`lib/`,
  `android/`, `ios/`, …). `SETUP.md` §1 says it is safe to delete. Left in place
  deliberately — deleting it is a separate decision, and it is now in git either
  way. **Open `saba_test/mobile` in the IDE, not `saba_test`.**


---

# Redesign — Step 1: Home

Everything below is visual. No repository, provider, route or mapper changed
behaviour; the one arrangement decision is recorded under "Judgement calls".

## Components built

| Component | Token | Where it lives |
|---|---|---|
| Dark header card, greeting, 40px icon circle with unread dot, raised promo card, page dots | `card/header-dark` | `core/widgets/dark_header_card.dart` |
| Floating pill navigation, active white pill, ringed badge | `nav/pill` | `core/widgets/saba_nav_bar.dart` |
| Tappable search pill, circular icon button | `input/search`, `button/icon-circle` | `core/widgets/search_pill.dart` |
| Corner action button with in-place confirmation | `button/corner-action` | `core/widgets/app_button.dart` |
| Product card, card price block, no-image tile | `card/product` | `features/catalog/.../product_card.dart` |
| Discount badge, stock badge | badges | `core/widgets/price_text.dart` |
| Section header with "See all" and an optional badge | — | `core/widgets/section_header.dart` |

## Findings

| # | Finding | Resolution |
|---|---|---|
| F11 | Seven tokens named in the handoff with no value | **Five now closed from the design itself.** The four `semantic/*/soft` colours are drawn in the status badges (`success #E7F3ED`, `warning #FDF3E3`, `error #FBEDEA`, `info #E8F0F9`), and `text/on-dark` is drawn as pure white. Only `border/strong` and `overlay/scrim` are still derived |
| F12 | `card/product/image-ratio · 4:3` in the token list, but no card in the design is drawn at 4:3 — the grid card is 152x132 and the home rail card 140x118, both approximately 7:6 | Followed the **drawing**, because that is what was reviewed. `AppSizes.productCardImageRatio = 152 / 132`, with the conflict recorded in the constant's own doc comment. Ask the design which is authoritative |
| F13 | `button/corner-action/size · 40` in the token list; the home rail draws 38, the component page draws 40 | Used **40**, the component page being the authoritative drawing of the component |
| F14 | The design's Home has a filter chip row under the search bar. The app has no filtering on Home and no data to drive it | **Left out.** Building it would mean inventing logic in a visuals-only step. The `chip/filter` component gets built with Categories and Search, where filtering actually exists |
| F15 | Money was formatted as `$135.99` — USD demo data, two decimals, symbol leading. The design writes `250,000 IQD` and `250,000 د.ع` | **Fixed.** `IQD` takes zero decimals, three-letter marks follow the number while glyph currencies still lead it, and the digits are formatted against `en` in every locale so they stay Western — which is exactly what the design asks for. Demo prices moved to whole thousands of dinars |
| F16 | The floating nav covers the bottom of content, and nine tab screens had no `space/nav-safe` padding. The cart's sticky checkout bar and the merchant FAB sat underneath it | **Fixed** on all nine, plus the checkout bar and the FAB |
| F17 | `RatingStars` painted *every* star in the accent colour, including the empty ones, so a 4-of-5 row read as five full stars | **Fixed.** Empty stars use `star/empty`, and a product with no reviews shows five empty stars plus the words "No reviews yet" |

## Defects I introduced and fixed in the same step

1. **Card height was 8px short.** `ProductCard.heightFor` used the corner
   button's *visible* 40px instead of its 48px tap target, so every card
   overflowed. Fixed by giving every row in the card an exact height, so
   `heightFor` is a sum rather than an estimate. Six tests pin it; five of them
   were verified to fail with the bug reintroduced.
2. **A vacuous test, for the third time in this project.** "Every card is the
   same height" measured widgets under loose constraints, where a `Column` with
   the default `MainAxisSize.max` stretches to the full screen — both
   measurements returned 600. Fixed the *card* (it now sizes to its content)
   and the test (it measures intrinsic height). Verified red at 268.87 vs
   251.87 with the fixed name box removed.

## Judgement calls, overrulable

- **A banner section arriving first is drawn inside the dark header card**
  rather than below it, which is how the design composes the top of Home.
  Nothing else changed: the sections still come from the same provider in the
  same order, any section can still be absent, and a banner section that is not
  first still renders as its own strip.
- **The corner action button now shows on every product card** (it was opt-in
  and off by default). The design draws it on every card, and the logic behind
  it already existed. It confirms in place for 1.2s instead of firing a
  snackbar, so a customer adding four things is not interrupted four times. A
  failure still speaks.
- **The filter circle beside the search pill opens Search**, which is where
  filters live. The design puts a filter button there; Home has no filter of
  its own.
- **Badge text on a soft semantic background uses the plain semantic colour**,
  not the darker "on-soft" tone the design draws (`#7A4E06` and friends). Both
  pass contrast and the difference is imperceptible; four more tokens were not
  worth it.

## Verified

`flutter analyze` — 0 issues. `flutter test` — **246 passing**, up from 232.


---

# Redesign — Step 1b: the icon set, and the corrections you caught

You compared the build against the design and the verdict was right: the
categories still looked like the old app, and the icons were Material's, not
the design's.

## The rule, written down

**The design decides how it looks. The app decides what it does.** A feature
that already exists keeps working exactly as it does, but it is *re-drawn* in
the design's language. When the design draws something the app has no data
for, say so — do not skip it silently and do not invent logic for it.

F14 was a misapplication of that rule: the chip row was read as "a filter we
do not have" and left out, when it is simply the categories, drawn the design's
way.

## Findings

| # | Finding | Resolution |
|---|---|---|
| F18 | Every icon in the app was Material's. The design ships **its own set** — 97 unique icons, 24x24, stroke 2, rounded caps. Material's family has a different weight and a different corner language, which is most of why the first pass still read as the old app | **Fixed.** All 97 extracted from the design files, normalised, and shipped as `assets/icons/*.svg`. `SabaIcons` names them, `SabaIcon` draws one in the current text colour. `flutter_svg` added |
| F14 | *(revised)* The category section was still the old grid of tiles | **Fixed.** Categories now render as `chip/filter` — the selected one expands into a dark pill over 180ms, the rest are 44 circles. Same data, same navigation. `categoryIcon()` picks an icon from the category name, with a stable positional fallback |
| F19 | Section titles truncated — "Shop by categ…" — because the title had `Flexible` and the trailing action had a `Spacer`, so the two split the free space and the title lost half its width | **Fixed.** `Expanded` on the title, no `Spacer` |
| F20 | The discount badge read "20% off". The design writes "−25%" | **Fixed.** `discountBadge` is now the glyph alone; `discountBadgeLabel` keeps the translated words for screen readers, and the badge carries it as its semantics label |
| F21 | The corner add-to-cart button never appeared, because it was gated on `isCustomer`, which is false when signed out. The design draws it on every card | **Fixed.** Gated on "not a merchant" instead. A signed-out tap lands on sign-in, which is where it was always going |
| F22 | Product images are all grey placeholders — the demo data points at `picsum.photos` and the emulator cannot reach it | **Closed, by the user's own suggestion.** No generated photos: the design already draws a product without a photograph as **line art of the thing itself** on the neutral tile. `iconForName()` reads the product name and picks from the design's own 97 icons, so a hoodie gets clothing, a phone gets a phone, a sofa gets furniture. Applies while loading and again if the image never arrives, so nothing jumps. Works offline, needs no assets beyond the icon set already shipped |

## Verified

`flutter analyze` — 0 issues. `flutter test` — **246 passing**.


---

# Redesign — Batch 1: the buying path (5 screens)

Product detail, cart, checkout, product list and search, re-drawn in the
design's language with their logic untouched.

| # | Finding | Resolution |
|---|---------|------------|
| F23 | Every product card overflowed by about 1px. `heightFor` added the corner button's **visible** 40px, but the button reserves a 48px tap target, so the card was 8px shorter than what it drew | **Fixed.** Every row of the card is now a fixed box and `heightFor` is their sum. Verified by breaking it: 5 of 6 tests go red without the fix |
| F24 | The card-height test was vacuous. It measured under loose constraints, where a `Column` with the default `MainAxisSize.max` stretches to the full screen, so both the reported and the actual height came back as 600 and the test could never fail | **Fixed in both places** — the card carries `mainAxisSize: min`, and the test measures intrinsic height. Verified red at 268.87 against 251.87. Saved as a standing rule: a regression test is not done until the fix has been broken and the test watched to fail |
| F25 | Arriving at a tab screen from Home left **white status-bar icons on a white page**, so the clock vanished. Page-title screens have no `AppBar`, so nothing claimed the status bar after the dark header card released it | **Fixed.** `PageTitle`, `SabaAppBar` and `ResultsHeader` each set their own `AnnotatedRegion<SystemUiOverlayStyle>` |
| F26 | The design's no-results screen *counts the fix* — "Remove the price filter · 6 results". The server does not report what each relaxation would return | **Open.** The buttons say what they do without counts, and the screen still names the cause. Needs one backend field, then one line per button |

## Judgement calls

- **List and search share one set of chrome.** Both are a list being narrowed,
  so both get the same header, the same removable chips and the same dead end.
  Two looks for one job is how screens drift apart.
- **Removing a chip removes only that filter.** Pinned by a test: a customer who
  drops "under 150,000" and silently loses "in stock" is being lied to.
- **The store name is on every result card.** On a multi-vendor marketplace, who
  is selling is part of the price.
- **Checkout is one scroll, three numbered cards**, not a four-page wizard. The
  only client-side gate left is `canPlaceOrder`, which has six tests on it.

## Verified

`flutter analyze` — 0 issues. `flutter test` — **265 passing**.

---

# Redesign — Batch 2: after the sale (10 screens)

Orders, order detail, invoice, returns, return detail, request return, reviews,
write review, store reviews and Q&A.

## What the screens became

| Screen | Before | Now |
|--------|--------|-----|
| Orders | `AppBar` + a **nine-tab** `TabBar` over nine `TabBarView` lists | A 32px page title, one scrolling row of status pills, **one** list |
| Order detail | A grey summary block first, the timeline last | A dark `card/header-dark` hero carrying the status and the tracking number, then the trail, then the receipt — the order a customer actually reads it in |
| Invoice | Three loose sections | A letterhead, the lines, the sum. Drawn as a document |
| Returns | `AppBar` + a six-tab `TabBar` | Same pill row as Orders, so the two halves of "after the sale" behave alike |
| Return detail | Sections with a tick-list | The same hero and trail as the order, with the refund amount leading its card |
| Request return | A dropdown of raw codes, button at the end of the scroll | Tick-rows for the reasons, a sticky bar that counts what is being sent back |
| Reviews | Material `PopupMenuButton` sort, `ChoiceChip` stars | The product list's own chrome: pills, a results bar, a sort sheet. The histogram bars filter when tapped |
| Write review | "Write a review" and a field labelled **Subject** | Says which product, asks "How was it?", fields labelled as a review |
| Q&A | A floating action button over the last answer | A sticky bar that says what it does |
| Store reviews | — | Redrawn on the shared review card |

## New shared components

`StatusTimeline` (the order trail and the return progress are one drawing),
`SectionCard` + `CardLine` (three private copies of a titled card became one),
`StatusBadge` (`card/badge` on the recovered `semantic/*/soft` tokens),
`TextFilterChips` (the word-labelled variant of `chip/filter`), `OptionSheet`
(one sort sheet for the whole app).

| # | Finding | Resolution |
|---|---------|------------|
| F27 | The return-reason dropdown held six bare strings and printed them by replacing underscores with spaces, so an Arabic customer chose between **"DAMAGED"** and **"WRONG ITEM"**. The cancel dialog next door had done this properly all along | **Fixed.** A `ReturnReason` enum carries the API code; six translated keys carry the words. Three tests pin it, verified red |
| F28 | The design's 97 icons include no **thumbs-up**, **flag** or **star**, and reviews need all three | **Fixed, with a caveat.** Six icons drawn to the set's own spec — 24x24, stroke 2, rounded caps: `star`, `star-filled`, `star-half`, `thumb-up`, `thumb-up-filled`, `flag`. The set is now 103. Ratings and the helpful vote no longer draw a single Material glyph. **These six are ours, not the design team's** — if Claude Design ships its own, replace the files and nothing else changes |
| F29 | Orders and Returns each built a list **per tab** — nine and six live paged providers for one screen | **Fixed.** One list, one pill row. Eight fewer subscriptions on Orders |
| F30 | `AppButton.icon` was typed `IconData`, so every button with an icon could only draw Material's | **Fixed at the root.** It now takes a `SabaIcons` path; six call sites updated |
| F31 | An empty filtered list said **"No orders yet"** to a customer with twelve orders | **Fixed.** A filtered dead end names the filter and offers "Show all". Same rule as the product list |
| F32 | The invoice printed **"Amount paid: Cash on delivery"** — the payment *method* under the amount's label — and never showed `paymentStatus`, which the entity had carried all along | **Fixed.** Correct label, and a paid/unpaid badge on the letterhead |
| F33 | `Invoice.downloadUrl` is parsed and never offered | **Deferred by decision, not missed.** Opening it needs a URL launcher the app does not depend on, and demo mode returns no URL, so the button could never work or be tested. Agreed with the user: wire it when the backend lands — one dependency and a button gated on `downloadUrl != null` |
| F34 | The sort sheet was still Material `RadioListTile`s | **Fixed.** One `OptionSheet` — a tick at the end of the row — used by both the product sort and the new review sort, so they cannot drift |
| F35 | Write review never said **which product** was being reviewed, which is unnerving when the order it came from had four things in it | **Fixed.** The product leads the screen |
| F36 | Its two fields were labelled **"Subject"** and "Write a review", lifted from the support ticket form | **Fixed.** Four new keys, EN + AR |

## A mistake worth recording

Creating `test/features/after_sale_test.dart` overwrote an existing file of the
same name holding **17 passing tests**. Nothing errored: analyze was clean and
the suite still said "all passed", because everything that survived passed. The
only signal was the total falling from 265 to 256 while 8 had just been added.
Recovered from git; the new tests now live in `after_sale_design_test.dart`.
The rule that came out of it: check a path exists before writing it, and
account for any drop in the test count.

## Verified

`dart format` — 204 files. `flutter analyze` — **0 issues**.
`flutter test` — **273 passing**, up from 265. Localization at **616 keys**,
English and Arabic in sync. All **103** icon files parse, carry the set's
viewBox and stroke, and every path starts with a move.

**Verified by eye is still owed.** The six new icons are valid SVG and sized to
the set, but only a run on a device shows whether the thumb and the flag
actually *look* right. Worth a glance next time the app is up.


---

# Redesign — Batch 3: the account (12 screens)

Account, profile, settings, change password, addresses, address form,
wishlist, compare, notifications, notification preferences, support and the
public storefront. This completes the redesign: all three batches are in.

## New shared pieces

`SabaTile` + `TileGroup` (Account, Settings and the notification preferences
each had their own `ListTile`, at three different row heights), `ChoiceRow`
(the tick row, now shared by the sort sheets and the settings screen),
`notificationIcon()` (one category-to-icon map instead of two).

**Eight more icons**, drawn to the set's spec: `lock`, `mail`, `sliders`,
`message`, `headset`, `trending-down`, `pencil`, `send`. The set is **111**.
A gear was deliberately *not* drawn — the set's `sun` is already a circle
ringed with spokes and the two collide at 20px, so Settings takes the existing
`globe`, which is what most of that screen is about anyway.

| # | Finding | Resolution |
|---|---------|------------|
| F37 | `AppTextField.prefixIcon` was typed `IconData`, so **21 call sites across 7 files** could only ever draw Material's icons. Same root cause as F30 | **Fixed at the type.** It takes a `SabaIcons` path; all 21 swapped |
| F38 | The wishlist grid sized its cards with `childAspectRatio: 0.56` — a guess, where the catalogue asks `ProductCard.heightFor`. A ratio cannot know the reader's text scale, which is exactly what overflowed every card in F23 | **Fixed**, and pinned by a test |
| F39 | `profile_screen.dart` built a `TextEditingController` **inside `build()`** for the read-only email field and never disposed it — one leaked controller per rebuild | **Fixed by deletion.** The email is a fact about the account, not a greyed-out input that invites a tap doing nothing |
| F40 | The settings language row was labelled with the **theme's** "System" string and subtitled "Language" | **Fixed.** Its own key, saying what it does |
| F41 | The 13-entry category-to-icon map existed **twice**, so a category could be a parcel in one screen and a box in the other | **Fixed.** One map, both read it |
| F42 | The address **nickname** field (Home, Work) was labelled "Default address" — directly above the switch that actually sets the default | **Fixed** |
| F43 | Compare's empty state borrowed the **search screen's** message | **Fixed** |
| F44 | The storefront grid guessed with `childAspectRatio: 0.6`. Third appearance of the same bug | **Fixed** |
| F45 | The support ticket category dropdown listed raw API codes — ORDER, PAYMENT, DELIVERY. **This is F27 again, in a different screen** | **Fixed.** A `TicketCategory` enum carries the code, seven translated keys carry the words, and it is now a sheet rather than a dropdown |
| F46 | Found *by the new test, not by reading*: the loading skeleton grid used `childAspectRatio: 0.62` while the real grid computes its height, so **every card jumped the moment the data arrived** | **Fixed.** `ProductGridSkeleton` takes the measured height; core cannot import a feature, so the number comes from the caller |

## What the test suite now pins

A guard test walks `lib/` and fails if any file pairs `childAspectRatio:` with
a product card. That bug has now appeared four times (F23, F38, F44, F46);
reading for it clearly does not work, so it is pinned instead. Comment lines
are ignored, so a note recalling the old value is not a false positive.

## Mistakes made in this batch

Two, both caught and fixed before the commit:

1. **An unescaped apostrophe** in an English string (`Mum's`) broke
   `strings_en.dart`. It survived several checks because I had been running
   **scoped** `flutter analyze lib/features/...`, which never looked at
   `lib/core`. Full analyze only, from here.
2. **A nonsense expression** left in a `Padding` on the storefront while
   thinking about edge-to-edge layout, and a doc comment on the compare screen
   claiming the label column stays put when it does not. Both removed — the
   comment now describes the real behaviour and names the limitation.

## Verified

`dart format` — 208 files. `flutter analyze` — **0 issues**.
`flutter test` — **280 passing**, up from 273. Localization at **635 keys**,
English and Arabic in sync. All **111** icons parse and carry the set's
viewBox and stroke. The two new fixes were each broken on purpose and watched
go red before being counted done.

---

# Batch 4 — fixing what four audits found, before redrawing anything else

Four control-honesty audits were run across the whole app (merchant; reviews /
search / wishlist / support / media; auth / profile / addresses /
notifications; cart / checkout / orders / returns / compare). They returned
roughly 80 findings. Every claim acted on below was re-verified by reading the
code first — the audits were treated as leads, not as truth.

## The pattern behind the findings

One habit, many times: **a widget answering a question nobody asked it.**
Stars asked "do I have a review count?" when the question was "what is the
rating?". Checkout asked "do I have totals?" when the question was "does this
customer have an address yet?". A merchant edit form asked "what is in my text
box?" and reported "this product has no description".

Nobody wrote these bugs. Correct decisions in separate files combined into
screens that lie. That is why reading one file never found them, and why the
count of "redesigned screens" was never going to.

## Fixed at the root

1. **Checkout could not be escaped.** `priceOrder()` returns early with no
   address, so `summary` stayed null, and the screen drew
   `AppErrorView(BusinessRuleFailure())` — whose Retry never renders, because
   a business-rule failure is not retryable. No retry, no bottom bar, and
   nothing ever called `priceOrder()` again. A customer with no saved address
   simply could not buy. Now: no-address draws an **Add address** action,
   a real failure draws a real error, and a `ref.listen` re-prices when the
   address list resolves a frame late.

2. **Back arrows that did nothing.** `maybePop()` on an empty history is
   silent. Order confirmation reaches order detail with `go`, which clears the
   stack, so the arrow after paying never worked. Added
   `context.popOrGo([fallback])` and rewired **8** back controls.

3. **Every rating drew as five grey stars.** `RatingStars` gated glyph *and*
   colour on `hasReviews`, so any caller that did not pass a count — review
   cards, the reviews header, and the product page, which passes
   `reviewCount: null` precisely because it prints the count itself — showed
   an empty row beside a perfectly good score. The rating now decides the
   stars; `hasReviews` decides only the words.

4. **111 icons never mirrored in Arabic.** An SVG does not honour
   `matchTextDirection`. `SabaIcon` now flips a curated set (`send`,
   `sign-out`). Deliberately **not** flipped: chevrons and arrows, which come
   in pairs every call site already picks by name, and `trending-up/down`,
   where the direction *is* the meaning. Removed the manual flip in support
   that would now double-flip, and replaced messaging's Material send icon.

5. **`lib/core` had 18 Material icons** — every empty state, every error
   state, every snackbar, the password eye, the retry button. The whole shared
   layer is now clean, which is what "the app still looks old" actually was.
   The generator was `EmptyStateView.icon` typed `IconData` — the **third**
   such parameter after `AppButton.icon` and `AppTextField.prefixIcon`.

6. **`SabaAppBar`'s trailing slot was a hard 48px**, so "Mark all as read" and
   "Clear all" were handed 32px and wrapped inside a 48-high bar.

## Also fixed

- Cart read "3 items" under a nav badge reading "7" — it counted lines, the
  badge counts units. `Cart.itemCount` existed and was not used.
- Compare and search-history **Clear all** deleted server-side state with no
  confirmation and discarded the `Result`, so a failed delete looked like a
  broken button. Both now confirm and report.
- The review report dialog's confirm button said **"Report product"**.
- An empty chat thread said **"No conversations yet"** while the customer was
  looking at one.
- The coupon field's return key was not gated on `_isBusy`; the button was.
- A **closed** return drew as one that had never started: `closed` is not in
  `ReturnStatus.progression`, so `indexOf` returned −1 and lit nothing —
  under a green "Closed" badge.
- Requesting a return with nothing ticked said "choose the product options
  first", on a screen with no options.
- **Check payment status** was a bare `invalidate` on a view that keeps its
  content during refresh: no spinner, no disable, and no visible response at
  all when nothing had changed.

## The guard

`test/features/design_system_test.dart` walks `lib/core` and fails on any
Material `Icons.` and on any `IconData` in a shared signature — both halves,
since fixing instances never held. It was broken on purpose and watched go red
(it named the exact file) before being counted done.

## Mistake made and caught

A `sed` swapping `EmptyStateView` icons also hit a merchant tile that still
takes `IconData`. `flutter analyze` caught it; that one line was reverted.

## Verified

`flutter analyze` — **0 issues**. `flutter test` — **282 passing** (280 plus
the two new guards; the count was watched, after destroying 17 tests with a
careless `Write` earlier in the project). Localization **642 keys**, English
and Arabic in sync.

## Not done, deliberately

`auth_scaffold.dart` still uses a Material `AppBar`, shared by six auth
screens. Those screens are blocked on the logo and will be redrawn together;
changing the chrome twice is waste. Q&A "Ask a question" and session revoke
still have no in-flight guard — both need a `ConsumerWidget` converted to
stateful, and are next. Categories is still the one main nav tab on old
chrome. The merchant side is untouched and is, per its audit, **more broken
than the shopper side** — redrawing it before fixing it would have made broken
things prettier.

---

# Batch 5 — the merchant order, end to end

## What was actually wrong

The merchant screens had an order *list* and nothing else, and the list was
lying in three separate ways at once.

**The status filter was sent and ignored.** The repository put `?status=` on
every request; the demo backend regenerated its eight orders from
`index % statuses.length` and never read the parameter. All eight tabs listed
the same eight orders. A merchant filtering to "Packed" saw the delivered ones
too.

**"Next: Confirmed" was a lie.** The status change replied `200` with an empty
body onto a list that was rebuilt per request, so the card re-read as its old
status. The merchant pressed the button, was told "Confirmed", and watched
nothing move — then pressed it again.

**There was no order detail.** `merchantOrderDetail` had a route constant, a
path helper and a `RouteAccess` entry, and no `GoRoute` and no screen. Nothing
in the app ever showed a merchant the items in an order or the address to post
it to. The one job the screen exists for could not be done from it.

## The fix

The demo backend now *stores* merchant orders (`_merchantOrderCache`, cleared
by `resetForTesting` like every other piece of demo state — the backend is one
instance for the whole process). The list filters by status, `GET .../:id`
returns one order with its items, customer, phone and destination, and the
`PATCH` mutates the stored row and keeps the tracking number.

`MerchantOrderDetail` wraps the existing `MerchantOrderRow` rather than
re-declaring its fields, so the card and the detail screen cannot disagree
about a status or a total. `MerchantOrderStatus` (label, tone, next) moved to
`merchant_widgets.dart` and `advanceMerchantOrder` to its own file: two copies
of a transition table is how a card and its detail screen end up offering
different next steps for the same order.

The orders list was redrawn in the design's language — `PageTitle` and
`TextFilterChips` in place of a Material `AppBar` and eight tabs, which is
also eight fewer live paged lists. Cards open the order. Status is a
`StatusBadge` with a tone, so the one order waiting on the merchant no longer
looks exactly like the seven that are not. An empty *filtered* list now offers
"All" instead of claiming the store has no orders.

`SabaAppBar` gained `backFallback`. It always fell back to the customer home,
which drops a merchant arriving by deep link out of their own store.

## Verified

`flutter analyze` — **0 issues**. `flutter test` — **286 passing** (282 plus
four new). The new tests were watched to fail: with the filter and the
mutation removed, three of the four go red. Localization **656 keys**, English
and Arabic in sync.

## Not done, deliberately

Nine merchant screens still use a Material `AppBar` — dashboard, products,
product form, inventory, analytics, payouts, store settings, account. Orders
and its new detail screen are the first two converted. The merchant dashboard
still shows six cards pointing at three destinations, each promising something
narrower than it opens, and metrics where "the server sent nothing" and a real
zero are drawn identically.

## Phase 6.5 — sign-up chain, the merchant door, and a route guard

**Sign-up is now phone → code → form**, for both roles.
`ChooseRoleScreen` → `PhoneEntryScreen` (`/register/phone?role=`) →
`OtpScreen` (`/register/otp`) → the role's register form, which receives the
verified number pre-filled and read-only plus the token that proves it.
The demo backend answers `POST /auth/otp/send` and `/auth/otp/verify`; the
code comes back in the response and is printed on screen, because a demo
build has no SMS gateway. Dropping `demoCode` is the whole difference from
the real contract.

**A customer can open a store.** `OpenStoreScreen` (`/account/open-store`),
reached from an Account row that only shows for non-merchants. Four fields;
logo, banner, documents and payout stay in Store settings, because a
fourteen-field wall is where sellers give up. The mock flips the account to
MERCHANT with status UNDER_REVIEW, which is what finally makes the existing
`PendingApprovalBanner` reachable — it was built and could never fire.

**`test/features/route_doors_test.dart`** fails when a route has no door.
Resolves path builders, so `conversationPath(id)` counts as the door for
`/messages/:id`. Exceptions are listed with a reason and checked for rot.

Also fixed: business types were title-cased from the API token and so read in
English inside Arabic; the demo user lived in Jordan, not Iraq.

303 tests pass, `flutter analyze` clean, 754 localization keys EN+AR.

**Not verified on device.** The Pixel_8 AVD (2 GB) ran out of memory
mid-walk — `lowmemorykiller` took the Android launcher and Chrome, then the
compositor wedged. Language, role and phone screens were confirmed by
screenshot before that; the code and Open-a-store steps were not.

## Entry screens — walked, and the layout bugs that walk found

`test/widget/auth_walkthrough_test.dart` (15) is the by-hand device walk,
written down: both languages, both roles, every link off the sign-in screen,
the failure path of every form, and sign-up completed end to end as a customer
and as a merchant.

`test/widget/no_overflow_test.dart` (26) renders 13 routes at a real phone's
411 points in both languages. The default test surface is 800x600 — wider than
tall — so everything fits on it and no layout bug is ever seen. Telling it the
truth found three, all of them in shared widgets, all of them on every screen:

  * `AppTextField`'s label had no give, so a long label pushed its required
    asterisk off the right edge. A required field whose asterisk is off-screen
    reads as optional. Now shrinks and ellipsises.
  * `SabaNavBar` overflowed with five merchant tabs, because the selected
    pill's label could not shrink — putting the last tab out of reach.
  * Five "Already have an account? / Sign in" rows overflowed. Now `Wrap`, so
    the link drops to its own line instead of off the screen.

`test/features/fake_data_containment_test.dart` keeps the demo data in one
piece: nothing outside `lib/core/mock/` may touch it, the flag stays
compile-time, and exactly one network file installs the fake backend. Deleting
the demo data is deleting that folder plus two if-blocks — the test is the
promise it stays that way.

The sign-in screen now names the two demo accounts (shopper@saba.app,
merchant@saba.app) with one-tap fill, in demo builds only. The role was decided
by whether the address contained "merchant", which nobody could guess, so the
seller half was unreachable to anyone who had not been told.

Launch screen no longer shows Flutter's logo on a white field: dark #14181D
and Saba's tile, on the old window background and on Android 12+'s splash API.

344 tests, analyze clean, 758 keys EN+AR.

## Sign-up, restyled to the sent frames

Red asterisks gone. Almost every field on these forms is required, so the mark
was decoration on nearly all of them — and red, the colour the app uses for
things that have gone wrong, on a field nobody had touched. Only optional
fields carry a label now, which is what the frames do.

`SignUpStepHeader` / `SignUpStepScaffold`: progress segments, "Step 3 of 4", a
back control and a globe that switches language mid-form. Sign-up was a stack
of screens with no sense of length — you gave a phone number not knowing
whether two more questions were coming or ten.

The merchant sign-up is now four steps: phone, code, profile, store. Both
steps' forms stay built so a half-typed answer survives stepping back, and a
server rejection that belongs to step 3 sends you back to step 3 rather than
printing the reason on a field two taps away. A buyer's bar reads 3, a
seller's 4, from the first step.

Business type is a bottom sheet, not a `DropdownButtonFormField` — the one
place the old Material look survived: a grey list dropped over the middle of
the form, cropped by the screen edge, with none of the app's corners.

347 tests, analyze clean, 766 keys EN+AR.

## Shopper, part one: fewer steps to the same place

"Buy now" pushed the **cart**, so it was "Add to cart" with a longer name —
you still had to find and press Proceed. It goes to checkout now.

"Added to cart" was a message with nothing to press, leaving people to hunt
the cart tab to see what had happened. `AppSnackBar.success` takes an action;
the way on travels with the confirmation.

Reviews start from the stars. A delivered item shows five tappable stars, and
the star pressed is the star the review opens on — so the commonest review, a
rating with no words, is one tap instead of a screen load and a second
decision to leave.

Old-design stragglers in the shopper path, all replaced: five Material
`OutlinedButton`s (including the Add-to-cart half of the buy bar, the busiest
control in the app), two `Divider`s and a `LinearProgressIndicator` in the
filter sheet.

Checkout was audited and left alone — it already pre-selects the default
address and the server's shipping choice, and already picks addresses in a
sheet rather than a screen.

`route_doors_test` caught the new `writeReviewPath(id, rating:)` as unreachable.
The route was fine; the test tore nested quotes in half when reading builders.
It matches the normalised body now.

351 tests, analyze clean, 767 keys EN+AR.

## Shopper, part two — and three cuts withdrawn

`ShopHeader` (core): search, a heart, and a compare control that appears only
once two things are in it. Wishlist and Compare have left Account, where they
sat in the card under "Change password". They are not settings — you reach for
them while looking at something, and walking to Account to do it means leaving
what you were looking at. Home and Browse both use it.

Account's four cards now carry headings. Four unlabelled cards of identical
rows means reading all eleven to find one.

**Three of the seven proposed cuts were withdrawn after reading the code**,
rather than forced:

  * *Account is a wall of rows* — it was already four grouped cards. Only the
    headings were missing.
  * *Returns: screen to sheet* — the form is an item picker with a quantity
    per line and six reasons. A sheet that tall is worse than a screen, and it
    would hide the order the request is about.
  * *Support: new ticket as a sheet* — category, subject and a description
    that wants room. With a keyboard up a sheet leaves almost nothing, and
    list, detail and compose are three different things, not three steps.

Browse (category grid to a product list) is still held: it would overwrite a
screen whose look was signed off, and saving one tap is not worth overruling
that unseen.

351 tests, analyze clean, 770 keys EN+AR.

## Browse is a shop now, not a menu

Rebuilt to the chosen option: the categories are a strip across the top, the
products are underneath, and choosing a category filters in place instead of
pushing a screen. "All" is selected on arrival, so the tab opens on things
that can be bought rather than on a question. One tap to a product, was two.

Nothing was invented for it — the chips, the product cards, the results bar
and the sort sheet are the ones the results screen already uses, so sorting
means the same thing wherever it is done.

Caught while wiring it: `ResultsGrid` draws a sort control from the `onSort`
it is handed, and the first version passed an empty callback. That would have
shipped a button that does nothing, on a screen built to remove waste.

351 tests, analyze clean.

## Home and the product page

**Two hearts.** Home drew a wishlist heart in the dark header and another in
the search row a few pixels below — two identical controls going to the same
place on the same screen. The header keeps the bell, which is the app talking
to you, not a shopping tool.

**Banners that rippled and went nowhere.** Every home banner was wrapped in a
tap, but the handler returned silently when the banner carried no action — and
campaign banners often are just a picture. They are not given a tap now, so
they read as the pictures they are.

**Reviews moved onto the product page.** There was a card saying
"142 reviews · 4.6" that opened a list. What a buyer wants there is to read two
and decide; the card made them leave the page, read, and come back to a screen
that had lost its place. The top two reviews are inline now, with "See all"
still going to the full list and its filters. A product with none says so,
rather than showing a blank space that reads as a failure to load.

351 tests, analyze clean, 771 keys EN+AR.

## The two Home fixes, now under guard

They were not covered, because the demo feed has no banner without an action
and so there was nothing for a test to press. `home_promises_test.dart` hands
Home a feed of its own instead of waiting for one to turn up in the data: five
tests, each watched to fail with the fix removed.

Writing them found a second door into the same bug. `isNavigable` only asks
whether an action has a value, so a banner of type `URL` passed it, was given
a tap — and the switch that ran on press had no case for `URL` and returned in
silence. The check and the navigation were two functions that could disagree,
and did. They are one function now: `_destinationOf` returns the path or null,
the tap exists only when it returns a path, and the press goes exactly there.
`_leadsSomewhere` and `_handleBannerTap` are gone.

## The shop page

**Nothing was for sale above the fold.** Measured, not guessed: the first
product card ran from 670 to 948 on a 914-point phone, so it was cut off and
the whole shelf sat below the screen. The cause was Follow — a full-width
filled block under the description, the loudest control on a page whose job
is to sell. It moved onto the banner, opposite the back control, where it
costs no height at all. Shipping and returns lost their separate bordered box
and share the facts card with the reviews row. The store description is capped
at three lines so a chatty shop cannot push its own shelves off the screen.
The first card now ends at 866 — on screen, entire.

**Follow did nothing for a visitor.** Browsing without an account is allowed,
so a visitor met the button, pressed it, and got silence: the method returned
early when not signed in. Every other signed-in-only action in the app opens
sign-in; this one does too now.

**Two doors to the store reviews** — the rating beside the shop name and a
whole card lower down — are one door. The rating stayed as information rather
than becoming the control, because a rating is eighteen points tall and a
control has to be reachable by a thumb.

**The demo shops were in Jordan.** Amman and Irbid, on a marketplace for Iraq,
printed under the store name. Baghdad and Basra now. Fake data, still in the
one file, still deletable in one move.

358 tests, analyze clean, 771 keys EN+AR. `/store/:id` joined the overflow
sweep in both languages, since its header was rearranged and Follow changes
ends in Arabic.

## The cart

**Remove asked permission.** Two taps and a dialog to undo one tap, on the one
cart action that is trivially reversible, sitting beside "Save for later". It
goes at once now and says so with Undo. The dialog never protected against a
misplaced tap: by the time it appeared, the tap had already been aimed.

**The bar never said what you were about to pay.** The total lived in a card
in the list, so a cart longer than a screen let you press Checkout having
never seen it. It is on the bar now, pinned above the button.

**A sold-out line froze the whole cart.** Red text saying there was a stock
problem, a dead button beside it, and the only way forward was to scroll the
cart and remove each struck line by hand. The button is the way out now —
"Remove unavailable items", one tap — and turns back into Checkout after.

**An overflow that only appears when the cart is not empty.** "Save for later"
and "Remove" sat side by side with no give and ran 19 points off the card.
`no_overflow_test` had been sweeping `/cart` in both languages the whole time
and never saw it, because the demo cart is empty. Both actions and their
labels are Flexible now, and a filled cart is checked in Arabic.

## Checkout

**The pay button was waiting on a tap it never asked for.** Shipping adopted
the server's default on arrival; payment did not, so `canPlaceOrder` was false
and "Place order · 2,605,200 IQD" sat greyed out with nothing on screen saying
why. Payment now takes the first method the server lists and allows — the
server's own preference, the same reasoning shipping always used. It can still
be changed, and the line under the button always says which one is in force.

**The screen never said how much there was.** It could tell you the cost and
the arrival date without ever saying how many things were coming. The delivery
row leads with the count now, from `group.itemCount`, which the server was
already sending.

## Search inside a shop

Asked for, and built on what was already there: `ProductQuery` has had a
`search` field all along and the demo backend already narrows by `q` and
`merchantId` together. The field sits where the "Products" heading was — a
heading that named what was obviously underneath it and cost the same height —
so the fold the shop page just won is not given back. Debounced at the delay
the search screen uses. A search that matches nothing blames the search, not
the shop, because "this store has nothing listed" would be a lie.

Two bugs surfaced while making it work, and the second is the interesting one:

**A paged list changed shape when it emptied.** `PagedListView` returned a
bare `RefreshIndicator` when there was nothing to show and a
`NotificationListener` wrapping one when there was. Two different widget types
at the root of the same screen, so going from "some results" to "none" tore
down everything beneath it, header included. The search field lost the very
word that had just emptied the list, leaving a screen that said "nothing
matches" above an empty search box. One shape now, in both cases — this was in
shared infrastructure, so every screen with a paged list had it.

**The storefront dropped to a skeleton on every keystroke.** Each search term
makes a different provider, and a provider that has never run has no value, so
the body fell back to its loading skeleton — taking the search field with it
and closing the keyboard. The last good page is held and handed back while the
next is fetched, which is also what a shopper expects: the old results stay
until the new ones are ready.

## Noted, not touched

Banners of type `URL` still get no tap. Opening an external link needs
`url_launcher` and a decision about leaving the app; until that decision is
made they are drawn as the pictures they are. The user asked for this to be
left alone and flagged.

368 tests, analyze clean, 777 keys EN+AR.

## The end of the buy

**A red alert above the words "Order placed".** The confirmation screen's
comment claimed the headline reflected the payment; only the mark did. A
failed payment drew an error icon over a cheerful headline and a blanket
thank-you that read the same whether the money had moved or not. Mark,
headline and sentence are one statement now.

**Corrected mid-flight, by a test that was already there.** Removing the
payment's own box also removed the only place that said the payment had
succeeded — and "Order placed" is not that fact, as a cash order proves by
being true and unpaid at once. `payment_action_test` failed and was right to.
The payment keeps its line; what it lost is the bordered box and the duplicate
sentence. A failed payment is the exception, because there the headline *is*
the payment.

**The system back button did nothing.** `PopScope(canPop: false)` with no
handler swallows the gesture, which on Android reads as an app that has
frozen. Back now continues shopping.

**A tracking number nobody could copy.** The only thing anyone does with one
is paste it into a courier's site, and it was plain text — so the only way was
to read it off the screen and retype it. The card copies on tap.

**An ordered item could not be opened.** The one place in the app where a
product was drawn and led nowhere; seeing it again meant remembering its name
and searching. Both the picture and the name open it, and a line whose product
has since been deleted is drawn without a tap rather than with one that leads
to a missing page.

## Two layout faults the tests had never been in a position to see

**The rating stars ran off the card.** Added last session, inside the narrow
column beside the price, where a label and five targets do not fit. They have
their own line now. No test had ever opened an order with items in it.

**The product page asked for infinite height.** `_TrustGrid` is a Row with
`CrossAxisAlignment.stretch` inside a scroll view, which tells each child to
fill a height that is unbounded there. Not a squeezed layout — a thrown one,
on the busiest screen in the app, whenever a product carried a warranty, a
return policy or a delivery estimate. It is wrapped in `IntrinsicHeight` now,
which is what "as tall as the tallest" actually needs.

The route sweep had never drawn a product page. It does now, in both
languages, and going back to the broken Row turns both red.

373 tests, analyze clean, 779 keys EN+AR.

## The inbox

The banner bug again, in a second place. Every notification card was an
InkWell and `_open` returned in silence when the notification carried no
target — and for an unknown target type it fell through a `default: break`.
The same two questions, answered by two pieces of code that could disagree.

`_destinationOf` answers both now: it decides the chevron and it decides where
the tap goes. A card with somewhere to go says so; an announcement does not
pretend. Pressing either still marks it read, because that is worth a tap on
its own.

Found while fixing it: **no demo notification had a target at all**, so the
inbox could never show what opening one does and nothing exercised the branch.
Orders, shipping, price drops and messages now carry one; promotions and
sign-in notices deliberately do not, because they are messages, not doors.

377 tests, analyze clean, 779 keys EN+AR.

## Closing the shopper app

**A sweep that draws every screen, signed in, in both languages.** The old one
walked a signed-out visitor, so half the app was never reached. This one buys
something first, then visits all thirty-three routes — and each one has to
prove it is still where it was asked to go, because a route the guard
redirects away draws nothing and throws nothing and would pass either way.

**The address form asked every customer in Iraq to type "Iraq".** A blank
required field with one answer, collecting "iraq", "IRAQ" and "Irak" along the
way. `AppConfig.homeCountry` fills it in, and it stays editable.

**The review form demanded ten characters of prose.** The stars on a delivered
order open it already answered, because most reviews are a rating and nothing
else — and then Submit refused until something was written, so the one-tap
path ended at a wall. The body is optional now. Anything typed still has to be
worth reading, so "ok" is still refused.

**The invoice had never once drawn.** The screen's own comment says this is
what a customer forwards to an employer or keeps for a warranty claim. The
demo backend built its lines from `item['name']` and `item['price']`, while an
order line stores `productName` and `unitPrice` — so every field came back
null, the cast on the last one threw, and the client could only report it as a
failed request. Every order's invoice showed "No internet connection".

It also had no way to send it anywhere. Copy puts it on the clipboard as plain
text, which needs no new dependency and lands straight in the app people here
actually forward things with. `Invoice.downloadUrl` is still ignored; opening
it needs url_launcher, and that is a backend-phase decision.

## The trip, done by tapping

`shopper_journey_test` presses what is on the screen and nothing else: a
product on Home, its colour, its storage, Add to cart, the Cart in the
snackbar, the quantity, Checkout, Place order, View order.

It found what no route sweep could. **The "Cart" action on the add-to-cart
snackbar opened a blank screen.** It called `context.push` on `/cart`, and the
cart is a branch of the shell — pushing a shell branch imperatively leaves
go_router with a stack it cannot draw. `go` switches to the tab, which is what
the control meant. "See all" on the home categories row had the same push, and
the same fix. Those were the only two in the app.

384 tests, analyze clean, 781 keys EN+AR.

## Merchant app — render sweep, tapping journey, and ten screens audited

The merchant half had never been rendered by a test. The only merchant
coverage in the suite drove the repository and never built a widget, which is
exactly the gap that hid a thrown layout on the shopper product page for
weeks. Two new guards closed it:

* `test/widget/merchant_sweep_test.dart` — all ten screens plus the filtered
  order queue and the **edit** form, signed in as a merchant, in both
  languages. Each route proves it arrived (a redirect draws nothing and throws
  nothing) and each drains `tester.takeException()`, so a layout failure names
  the route that caused it instead of a disposed widget.
* `test/widget/merchant_journey_test.dart` — the job by touch only: the
  dashboard says orders are waiting, that row opens those orders, an order
  opens its packing slip, the address copies, the button moves the order on.

### Fixed

1. **`PageTitle` handed its trailing slot unbounded width.** A `Row` lays a
   non-flex child out with infinite width and `AppButton` expands by default,
   so the first button dropped into the documented action slot threw the whole
   screen away. Fixed in the shared widget, not the caller.
2. **`AppButton` labels wrapped to two lines.** The icon variant ellipsised;
   the plain one did not, inside a button whose height is pinned. Arabic and a
   raised system font scale both reach it.
3. **The product row overflowed 25px in Arabic.** The one product that is both
   out of stock and a draft carries a Restock button *and* all three icons,
   with a `Spacer` that cannot give way. Split into control | actions with the
   control flexible.
4. **The copy confirmation covered "Advance status".** A snackbar docks to the
   bottom of the Scaffold, which is where the sticky bar is, so confirming a
   copy swallowed every tap on the only button that screen exists for. Copy
   now confirms in place with a tick — the convention the product card's add
   button already used. Thirteen screens use `StickyBar`; the same overlap is
   possible on all of them and is noted below.
5. **Analytics ignored the period.** The screen sent `?period=week|month|year`
   and the backend dropped it, so all three tabs showed the same revenue over
   the same six bars — the same fault as the order status filter, one screen
   across. The series is now shaped per period and deterministic, so pulling
   to refresh no longer redraws a different week.
6. **Adjust stock prefilled but did not select.** Tapping a filled number
   field only moves the caret, so typing 5 over 18 saved 185 and the product
   oversold. Both stock sheets now open focused with the old figure selected.
7. **The edit form was built from the shelf row.** The row carries a name, a
   SKU, a price and a stock level, so a merchant edited a product without
   being shown its description, category or variants — and the picker was
   seeded with the single thumbnail, which made Save send a one-image list.
   Added `GET /merchants/me/products/:id`, `MerchantRepository.product(id)`
   and a real load, so the form arrives holding the whole record. The
   "blank means leave it alone" workaround on the description is gone with it:
   the field shows the truth, so blank can mean blank again.
8. **The media picker broke with more than one image.** A horizontal
   `ReorderableListView` throws a rendering assertion as soon as it holds two
   items, so the picker failed for any merchant running a screen reader the
   moment they added a second photograph — and no test could draw the field.
   Replaced with a plain list where a tap makes a picture the main one. The
   only thing the order carried was which picture comes first, and one tap
   beats dragging a tile across a strip inside a scrolling form.
9. **The demo moved to Iraq.** The customer's own saved address was still in
   Amman, so the checkout a client is shown delivered to another country; the
   sessions list claimed Jordan too. Guarded by a new case in
   `fake_data_containment_test.dart` that fails on the names, not a field.

### Found and not fixed

* **The dashboard's "return requests" row opens `?status=RETURNED`,** and no
  bucket in the queue holds that status, so `indexWhere` returns -1 and the
  merchant silently lands on "To confirm". It cannot fire in demo because
  `returnCount` is always 0, and merchant returns are already on the
  backend-phase list — but it is a wrong destination waiting for data.
* **A merchant cannot see their own storefront.** The screen exists and is
  public; there is simply no link to it from the merchant account.
* **Snackbars can cover a `StickyBar` on any of the thirteen screens that use
  one.** Fixed at the one place it swallowed a primary action; the general
  case needs either a floating snackbar with a margin or moving those bars to
  `Scaffold.bottomNavigationBar`, which is a wider change.
* **Payouts is read-only** — no way to request a transfer. The payout provider
  is a deferred backend item, so no control is better than a dead one.

391 tests, `flutter analyze` clean, 782 keys EN + AR in sync.
Still owed: nothing has been seen running on a device this session.

---

## Client-feedback pass (2026-09-21)

Screenshots from the client, fixed one by one. Root cause first, in the shared
widget where one existed, so every screen using it was fixed at once.

### Corrections to the section above

* **Withdrawn: "the copy snackbar covered Advance status."** That was only in
  the test harness, which drew the app without its theme; the real snackbar
  floats 96 points up. The in-place tick stays because it is better, not
  because of that. Comment and test wording corrected.
* **The first two "found and not fixed" items are fixed** (returns row, Visit
  store). The snackbar-over-StickyBar item was the harness artefact above.

### Fixed

1. **Flash sale has its own card** (`FlashSaleCard`): 2:1 image, store name,
   price beside the name, ringed heart and a full "Add to cart" pill that
   confirms in place. Every other rail keeps `ProductCard`. The price never
   truncates; it scales down whole at 7 figures and the 1.4x text cap.
2. **Every icon is Phosphor (MIT)**, same file names, so no screen changed.
   The selected nav tab draws a `-fill` twin (`SabaIcons.filled`), guarded by
   a test that fails if a nav icon has no twin. Old set kept in the session
   scratchpad as `icons_before_phosphor`.
3. **Nav bar overflowed by 4.5px**: all five tabs were `Flexible`, so the
   selected pill got a fifth like a bare icon. Only the selected one flexes.
4. **Every bottom sheet opened under the floating nav bar** (Mark as shipped,
   Set stock, Stock adjustment): `AppDialogs.bottomSheet` now uses the root
   navigator.
5. **Every dialog's Cancel was a stray word over a full-width bar** - the
   theme makes filled buttons full width, so action rows could not hold two.
   One `DialogActions` row (equal Cancel + action) in all five dialogs.
   "Add option" now validates instead of closing silently on an empty save.
6. **Snackbars with an action never went away** (Flutter 3.47: `persist`
   defaults to true when there is an action). `persist: false` in
   `AppSnackBar`; test watched red.
7. **Cart**: checkout bar measured the nav bar without the gesture inset and
   sat on it - `SabaNavBar.coveredHeight()` now; Remove / Save for later are
   real soft-filled pills.
8. **Product page buy bar** showed "Add ..." - total on its own line, the two
   buttons half width each.
9. **Account (both roles)**: group titles were jammed into the card corner
   (`TileGroup` gave its title the rows' zero padding) - titles sit above the
   card, with an optional subtitle; coloured icon tiles; the phone number is
   LTR-isolated here and on four other screens (guarded by a source scan);
   phone inputs type left to right.
10. **Analytics**: "Today" removed; revenue on a dark card like the
    dashboard's, with growth vs the previous period; coloured metrics; ranked
    top products. Chart labels now match the period.
11. **Merchant screens**: Inventory card redesigned (and `StatusBadge` no
    longer stretches full width anywhere); My products header - Add product
    at the end (`PageTitle` action was flexed to the middle), search box
    without "(Optional)"; Edit product in six coloured section cards, category
    picked from a sheet (`PickerField` + scrollable `OptionSheet`), and the
    photo hint no longer says "drag".
12. **Returns live in My orders**: one Returns pill replaces the "Returned" and
    "Refunded" pills and the header link; an order shows its own return. The
    separate Returns screen and `/returns` list route are deleted.
13. **Sign-up**: OTP is six boxes over one real field (paste and SMS autofill
    still work), centred; short steps and the role choice are centred
    (`CenteredScroll`, scrolls rather than squeezes); Login has colour.
    Country/City removed from shopper sign-up, Country from merchant sign-up
    (the market is Iraq; `AppConfig.homeCountry` is sent).
14. **Demo backend kept only the email at sign-up** and chose the role by
    whether it contained "merchant": a new merchant landed in the shopper app
    as "Amina Saleh", and every new shopper was her. Store settings saved
    through the "open a store" branch and put the demo store back under
    review; reads always returned the demo record. One `_ownStore` record now;
    shoppers see the merchant's city on the store page. Three pipeline tests,
    all red against the old mock.

### Notes

* The emulator shows no soft keyboard because its AVD has `hw.keyboard=yes`.
  Not an app bug.
* The laptop ran out of memory and disk while building: 7 GB free on C:.
  Reclaimable: Temp 7.4 GB, Gradle caches 11 GB, AVD 11 GB, build 2.2 GB.
  Nothing deleted without the user's go.

406 tests pass, `flutter analyze` clean (app, tests and integration tests),
788 keys EN + AR in sync. Not yet seen on a device: the emulator died with the
disk full, and the client is checking this build themselves.

- **Account header (2026-09-21):** the shopper Account screen now opens with the same dark `DarkHeaderCard` as Home. It holds the title, the identity (orange initials avatar, white name, muted email/phone; tap → profile) and "Open a store" / "My store" as an `OnDarkRaisedCard`. The white identity card and the separate store card are gone. The merchant Account is unchanged. 406 tests pass, analyze clean.

### Same day, later (2026-09-21)

- **New accounts saw someone else's data (root cause: demo backend).** The mock held one cart, order list, address book, wishlist, messages and so on for the whole session, and served the demo store's figures to every merchant. Now:
  - Each account keeps its own data (`_AccountSnapshot`, set aside by email on an account switch and given back on the next sign-in).
  - A new account starts empty, with no notifications and no conversations.
  - A new store has empty dashboard, orders, products, inventory, analytics and payouts, and no reviews on its public page.
  - Products a merchant adds are kept: create, edit, delete, stock, and the full record for the edit form.
- **Dashboard:** "Add your first product" appears when the shelf is empty (instead of "Nothing needs you right now"). Saving a product now also refreshes the counts, dashboard and inventory, not only the list.
- **Account headers:** the shopper Account and merchant Account both open with the dark header. The merchant one has a square store tile and status badge, and "Visit store" as the raised card.
- **Wishlist and Compare** are now also rows in Account › Your account. Before, they were only an unlabelled heart beside search, plus a button that appears after two products are compared.
- **"Open a store" removed** (user decision; spec §5/§21 have separate customer and merchant sign-ups). Removed: the screen, route, mock POST branch and 9 strings, and the role screen's "You can always add a store later".
- **Coupons:** the mock "applied" any code, typos included, at no discount. Now only a real code works (demo: `SABA10`); anything else gets "This code is not valid or has expired" (EN/AR). Open item: nothing in the app tells shoppers a code exists. Spec §6 wants coupon promotions on Home, §27 merchant coupons, §39 marketplace and first-order coupons.
- Tests: 5 new pipeline tests (new store empty and keeps added products; demo store keeps its figures; new shopper empty and the previous account gets its data back; only a real coupon applies). Each was watched failing against the old behaviour. **410 pass, analyze clean, 781 keys EN+AR.**
- **Coupons, where to get them (user chose Cart + Home):**
  - New `GET /coupons` returns the signed-in shopper's usable coupons as structured fields (code, PERCENTAGE/FIXED, value, min order, first-order only). The app writes "10% off" / "خصم 10%" itself, so the wording is correct in both languages.
  - Cart: offer chips under the code field; one tap applies.
  - Home: a `COUPONS` section (admin places it; the offers come per account from `/coupons`) with a Copy button on each card.
  - Demo: `SABA10` (10% off, anyone) and `WELCOME` (5,000 IQD off, only until the first order; refused after it).
  - The mock now reads Accept-Language for its coupon messages.
  - Tests: a pipeline test (the first-order rule) and three widget tests (chip applies in one tap, Arabic wording, Copy copies and says so); each watched red.
  - Shopper-journey test now scrolls to Home's first product card; the new section pushes it below the lazily built area.
  - **414 pass, analyze clean, 788 keys.**
- **Home top (user's picks):**
  - The black header keeps the greeting and bell. Under them, 4 full-photo banners, admin-controlled from `/home`, with page dots. A tap does nothing (owner's rule); the header-banner tests now pin that.
  - Search stays next. Categories are now round photos with the name under, in 2 rows that slide sideways; tapping one opens its products.
  - No photos yet (the image generator was down). A banner shows its own colour and its words; a category shows its icon on its own colour. `AppNetworkImage` gained a `fallback`. Photo sizes are in `assets/images/README.md`: `promo-1..4.jpg` at 1200x500, category photos round.
  - The mock sends banner words in Arabic when asked.
- **Cart totals:** the coupon amount now shows on the Discount line; before, the lines didn't add up with a coupon on. Test added, watched red.
- **Purchase-flow audit** (read from the code, not run on a device) found: a card add skips variants; sign-in loses what you were doing; the checkout wording contradicts itself (escrow vs cash on delivery); cash on delivery is described as "waiting on the payment provider"; "Payment status: Approved" on orders; "Delivery, 1 stores". Waiting for the user's go.
- **414 pass, analyze clean.**

## 2026-09-21 — Chat with a store, white Home header

**Chat (spec §43, customer ↔ merchant).** Before this, a shopper had no way to start a chat: the only way in was Account > Messages, which listed only chats the demo had already written. The chat screen was titled "Messages", and a merchant's inbox listed other stores instead of its customers.
- **Message** button on the product page (seller card), the store page (next to Follow) and each store in an order. It opens the chat with that store, or starts one (`POST /messages/conversations {merchantId}`). Signed out, it opens sign-in. Merchants don't see it.
- Home and the merchant dashboard: a chat icon next to the bell, with a dot when something is unread. Account > Messages (shopper and merchant): an unread-count badge.
- The chat is titled with the other side's name (`GET /messages/conversations/:id`). An empty list says where a chat starts.
- Demo server: chats are stored once (`_chats`) and are no longer part of each account's saved data. What a shopper writes shows in that store's inbox under the shopper's name, and the store's reply comes back to the shopper as unread. A new shopper or new store starts with no chats. The demo store m-1 has two seeded customers (Sara Ahmed, still waiting; Ali Hassan, answered).
- To see both sides on a phone: sign in as a shopper, open a product, tap **Message** and send. Sign in as `merchant@saba.app`, open Messages and reply. Sign back in as the shopper.

**Home header is white** (product owner's choice, Home only). Account, the merchant screens, Order details and Return details stay black. Home overrides the header's colour tokens locally. `DarkHeaderCard`'s status-bar icons now follow the card colour: dark on white, light on black.

Tests: 417 pass; analyze clean; 791 keys EN+AR. New tests: "a shopper writes to a store, and the store answers"; "Message on a product opens the chat with its store" (Home chat icon, product Message, store name as the chat title); "the header on Home is white, with dark status-bar icons". I watched each one fail by breaking the fix it covers. Not yet seen on a phone.

## 2026-09-21 (later) — Merchant replies, simpler buying steps

**Merchant sees and answers chats**
- The dashboard's "Needs you today" lists customers waiting for a reply ("1 customer is waiting for your reply", with the name and last message). With one waiting, the tap opens that chat; with more, it opens Messages.
- Tapping Message on a product or order starts the chat with "About <product>: " or "About order <number>: " already in the box, with the keyboard up. Nothing is sent until the shopper presses send.

**Buying steps (approved by the user)**
- **Card with options:** the card's bag button on a product with options now opens the product page with "Please choose the product options first". Before, it added the product with no options chosen. `ProductSummary.hasOptions` comes from `hasVariants`/`variants`.
- **Sign-in (real bug found by a test):** signing in from a pushed sign-in page (for example, Add to cart while signed out) left the sign-in form on screen after a correct sign-in. The router's redirect only sees the page underneath. Fix: `LoginScreen` closes itself after the frame, because the auth refresh would otherwise put it back, and the product page comes back as it was. A sign-in asked for by a protected page (for example, /orders) now carries `?from=` and goes on to that page. The purchase-flow audit's claim that sign-in "drops you on Home" was wrong; it was worse.
- **Checkout:**
  - Each store's items are listed.
  - One payment sentence, under the pay button; it follows the chosen method. The escrow line that sat under Cash on delivery is gone.
  - The title says "Delivery" for one store, and the subtotal line says "Subtotal".
  - Wording is plain: "Pay in cash when your order arrives", "Saba holds your payment and pays the store only after you receive your order", and "Each store sends its own parcel".
- **Demo delivery prices:** in IQD and the same as the cart (standard = the cart's fee; Express = 10,000). Choosing Express now changes the total. Before, the options said 9.99 and 19.99, and Express changed nothing.
- **Cash on delivery:**
  - Orders carry `paymentMethodType`.
  - The confirmation says "Have the cash ready: you pay when it arrives", shows "Pay on delivery", and has no "Check payment status".
  - The orders list says "Paid", "Pay on delivery", "Awaiting payment" or "Payment failed", not "Payment: Approved/Rejected".
  - The failed-payment text no longer promises a retry that doesn't exist.

Tests: **422 pass, analyze clean, 799 keys EN+AR.** New tests (each watched red):
- the waiting-customer row;
- the chat first words;
- a card with options;
- sign-in from a product;
- sign-in from a protected page;
- delivery prices and Express;
- checkout lists the items;
- the cash confirmation.

The old test that pinned "waiting on the payment provider" for cash orders was updated to the new behaviour.

**Not done:** "Buy now" still checks out the whole cart. The merchant Coupons screen (approved) is not started.

## 2026-09-21 (later) — Buy now alone; merchant coupons

**Buy now:** checks out that one product (with its options and quantity) and leaves the cart untouched.
- It opens `/checkout?product=…&variant=…&quantity=…`, and the checkout request carries `items`. The demo server prices only that line, with no cart coupon, and doesn't clear the cart.
- Checkout's item list now comes from the server's pricing (`CheckoutGroup.lines`), not the cart, so it's right both ways.
- **Bug found:** the checkout controller rebuilds when the address list arrives, which dropped Buy now and priced the whole cart. The line is now kept on the controller (`_buyNow`).

**Merchant coupons (spec §27/§39)**
- **Merchant side:** Store tab → Coupons (`/merchant/coupons`).
  - The list is drawn as tickets: a coloured stub with the discount, then the code, status (Active / Scheduled / Paused / Ended / Used up), dates, and a usage bar ("12 of 50 used"). The ⋮ menu has Edit, Pause/Resume and Delete (with a confirm).
  - New/edit form (`/merchant/coupons/form`): a live preview of the shopper's card, the code (capitals, with a Suggest button), % or IQD, the value, an optional minimum order, start and end dates (the end runs to the close of that day), and an optional usage limit.
  - API: `GET/POST /merchants/me/coupons`, and `PUT/PATCH/DELETE /merchants/me/coupons/:id`.
- **Shopper side:**
  - A store's running coupons are offered with the store's name ("At Nova Electronics · …"), on Home and in `/coupons`.
  - The cart only offers a store's coupon when that store's items are in it.
  - The store page shows a sticker on the banner ("NOVA10 · 10% off +1"); tapping it opens all of them with Copy buttons. It's a sticker because a strip of cards pushed the first product off the screen, which a test caught.
  - Public API: `GET /merchants/:id/coupons`.
- **Rules (demo server):**
  - A code is unique across Saba.
  - A percentage is at most 90.
  - The end date must be after the start.
  - A coupon is live only when it isn't paused, has started, hasn't ended and has uses left.
  - A store coupon needs that store's items in the cart and meets the minimum on that store's part, and it discounts only that store's part.
  - A placed order counts one use.
  - Demo coupons: Nova has NOVA10 (running) and WEEKEND15 (starts in 3 days); Atlas has ATLAS5000.

Tests: **426 pass, analyze clean, 839 keys EN+AR.** New tests:
- Buy now (the cart is untouched);
- a store coupon end to end (made, taken code refused, offered, not usable at another store, a quarter off that store only, counted, used up);
- the merchant makes one from the Store tab (with the preview);
- the store page sticker.

Each was watched red, including 6 rule breaks. Two older tests were updated for the new behaviour: the Saba-only coupon list, and store coupons now beside it. Not seen on a phone yet.

## 2026-09-21 (later) — Shopper Account audit

**Inventory.** The Account screen has:
- a header (name, email and phone, which opens the profile);
- You: Addresses, Wishlist, Compare;
- Get help: Notifications, Messages, Support;
- Security and settings: Change password, Active sessions, Notification preferences, Settings;
- Sign out.

**Broken, fixed (each watched red):**
- **Edit profile:** a saved name or phone was forgotten on the next account read. The demo server now keeps `_profileEdits`, per account, in the snapshot.
- **Mark all as read:** the dots came back on the next fetch. The server now remembers read notifications per account, and the unread count follows.
- **Notifications:** every body read "Demo notification while the backend is being built." It now has real words in EN/AR.
- **Notification preferences:** showed a shopper "Store approval" and "Product approval". These are hidden unless the account is a merchant.
- **Active sessions:** a red X beside "This device" signed you out in one slip. Other devices now get a "Sign out" button in words; this device has none (Sign out is on Account).
- **Address card:** the new bottom row ran 9px past the card on a phone. A test caught it; it's two flexible text buttons now.

**Removed:** the "My profile" row, which went to the same place as the name at the top.

**Design:**
- **Addresses:** calmer cards (green border and "Default" badge for the default one), a coloured pin tile, the whole card opens edit (with a pencil), and "Set as default" and "Delete" in words.
- **Notifications:** each kind has its own colour (blue orders, green delivery, orange offers, amber security). Unread cards are warmer. Times read "Today, 6:29 PM" / "Yesterday, …".
- **Sessions:** the app's own cards, with a coloured device tile and a "This device" badge.
- **Edit profile:** "Delete account" is its own red card at the bottom, with what it does.
- **Address form:** "State or province" is now "Governorate" (Arabic already said المحافظة).

Tests: **432 pass, analyze clean, 841 keys EN+AR.** New `test/widget/account_screens_test.dart` uses every screen: profile save survives a re-read; address add, set default and delete; sessions; shopper preferences; notifications mark all read; change password; language.

**Not changed, noted:** the phone number can be edited without re-verifying it by SMS. That's a backend rule (it needs an OTP step); flagged for the backend phase.

## 2026-09-21 (later) — White tops everywhere, Messages list, address buttons

**Every black header is now white, shopper and merchant.** `WhiteHeader` (in `core/widgets/dark_header_card.dart`) points the header tokens at the page's light colours. It wraps the widget that *builds* each header, because the headers read their text colours above the card. Applied to: Home (its inline override moved into it), Account, Order detail, Return detail, Merchant dashboard, Merchant account, and the Merchant analytics revenue card. Secondary text on it is `onSurfaceVariant`, not the too-light muted grey. Not changed: the bottom nav bar, dark chips, and the full-screen dark language picker at first launch.

**Messages list:** a single white card of rows. Each chat has a coloured initials tile (square for a store, round for a customer; there are no store logos in `assets/images/stores/` yet, so every chat showed a grey silhouette). Unread chats have a bold name and message, an orange time and a count pill. Times read "4:12 PM" / "Yesterday" / "Sep 18". Demo data: every store's chat held the same two lines; each now has its own question and answer.

**Address card:** bigger pin tile, 16px title, and the address and phone at 14px with their own icons. Three coloured buttons, icon above word: Edit (blue), Set as default (green, hidden on the default one), Delete (red). They replace the small grey pencil and plain links.

Tests: **435 pass, analyze clean.** New in `account_screens_test.dart`: shopper tops are white (Account, Order), store tops are white (Dashboard, Store account, Analytics), and each chat is its own with initials and an unread count. The address test now taps Edit. All five were broken on purpose and went red.

## 2026-09-21 (later) — Shopper and stores connected (demo only, no backend)

**Before:** a shopper's order stayed in the shopper's account. The store Orders screen showed invented orders, and every store login opened Nova Electronics. Nothing a store did reached the shopper.

**Now** (all in `mock_api_interceptor.dart` / `mock_data.dart`):
- **Two store logins:** `merchant@saba.app` (Omar, Nova Electronics, m-1) and new `merchant2@saba.app` (Layla Kareem, Atlas Home, m-2). Each has its own shelf, inventory, settings, orders and coupons. The sign-in demo buttons are now Shopper / Nova Electronics / Atlas Home.
- **One checkout splits per store:** `_storeOrders` is shared state, like chats. Each store gets its part (its lines, its delivery fee, the shopper's name, phone and address, the payment method) as `NEW`, plus a "New order SB-…" notification. The store's demo history now lists only its own products.
- **Store steps reach the shopper** (`_storeMoved`): that store's lines take its status; the order is as far along as its slowest store (a store that declined is left out). The step is added to the timeline, with tracking. Cancel is allowed until a store starts preparing. Return opens once something is delivered. Cash on delivery is marked paid when everything has arrived. The shopper gets a notification per step. The order page shows each store's status under its name.
- **A shopper's cancel reaches the stores** that haven't started, and they are notified.
- **Stock:** buying lowers the shared stock that the product page, lists, cart and store shelf all read (`_withStock`). Product-level only; `ponytail:` note for per-option stock.
- Notifications: `_events`, per inbox (an email, or `store:<id>`), in EN/AR, shown above the demo list and counted in the bell.

Tests: new `test/features/two_stores_test.dart`. One shopper buys from both stores. Each store sees only its part, Nova ships, Atlas confirms, the shopper sees both and is notified, then both deliver and the cash is marked paid. A shopper cancel reaches the store. Seven links were broken on purpose and all went red. `auth_walkthrough_test` now taps the "Nova Electronics" button.

**Open, the owner's decision:**
1. The money split: commission, when a store is paid. Payouts still show demo numbers.
2. Cash with two drivers: show how much to pay each driver.
3. Who pays for a Saba-wide coupon.
4. The real refund when a store declines a card-paid part.
5. Cancelling one store's part.

**Drivers:** the spec has no driver role. The designs show both a store's own driver and "Saba delivery", with drivers added by the admin. For now each store moves its own delivery; Saba drivers wait for the backend and the web admin.

## 2026-09-22 — v1 part 1 of 9: Governorates

The v1 plan is agreed with the owner:
- cash only;
- stores deliver;
- one commission rate, billed monthly;
- login by phone with email optional;
- 7-day returns;
- a 1,000,000 IQD first-order cash limit.

The web admin and the launch come after the whole app is done.

**Built:**
- `core/location/governorate.dart`: Iraq's 19 governorates (Halabja is the 19th, since 2025) with codes and EN/AR names, the main city in brackets. `fromApi` also reads old city words and finds "Mosul"/"الموصل" as Nineveh.
- `core/location/governorate_picker.dart`: the list in the app's `OptionSheet`, `GovernorateField` (the app's `PickerField`), the `StoreCity` line, and `shopperGovernorateProvider` (kept in preferences).
- **Home:** a "📍 Deliver to Erbil ▾" / "Choose your city" button under the greeting.
- **Stores:** the city is required at store sign-up and in Store settings, picked from the list. The country and free-text city fields are gone, and the API field is `governorate` (code). Every store card shows the city: Home's Featured stores and the product page's seller card. The store page says "Basra · Corniche Street, Al-Ashar" (the address when given).
- Demo data: Nova is in Baghdad and Atlas in Basra, each with a street address.

Tests: **443 pass, analyze clean, 845 keys.** New: `test/core/governorate_test.dart` and `test/widget/city_test.dart`. The store sign-up walkthrough now has to pick a city. Eight breaks all went red.

## 2026-09-22 — v1 part 2 of 9: Sign in by phone, email optional

- **Sign in:** phone first (+964 fixed, number pad), with "Use email instead" one tap away. The number goes to the API in one form, `+9647XXXXXXXXX`, through the new `core/utils/iraqi_phone.dart` (`IraqiPhone.normalize`; `Validators.iraqiPhone`). The shared `IraqiPhoneField` is used at sign-up, sign-in and reset. The demo buttons fill in phone numbers: Amina 0770 123 4567, Nova 0771 123 4567, Atlas 0780 123 4567.
- **Sign up:** email optional for shoppers and stores. For shoppers, the **city (governorate) is required**, and Home then shops from it.
- **Forgot password:** by phone by default. The SMS code (the same OTP endpoint as sign-up) and a new password go on one screen, and email-link reset is still one tap away. Before, reset was email only, so a phone-only account could never get back in.
- **Profile:** the city is picked from the list and the country field is gone. **The phone is read-only**, because it is the login: changing it needs an SMS check, so it goes through support. This covers must 43 in the simplest safe way.
- The account header shows the phone when there's no email; the "verify your email" banner only shows when there's an email. The coupons and chat providers are keyed to `(email, phone)`.
- **Home's city button** uses the device's choice, else the account's city.
- **Demo backend:** login by phone (an unknown number gets "No account uses this number", in EN/AR), phone-only sign-up accounts, reset checks the code, profile saves `governorate`.
  - **Bug fixed:** the demo dropped `errors` from rejected replies, so every server field error became a banner and never showed on its field. It now passes them through.

Tests: **448 pass, analyze clean, 851 keys.** New: `test/features/phone_sign_in_test.dart` (demo phones; unknown number; sign-up without email then back by phone; city on profile; SMS reset right and wrong code). The walkthroughs now sign up without an email, must pick a city, and reset by phone. Eleven breaks all went red.

**Not done, by design:** asking the city "once for old accounts". v1 launches with no old accounts, since every sign-up now asks. Guests already browse Home, search, products and stores freely; the cart still asks to sign in, because a guest cart would need merging logic. Revisit if wanted.

## 2026-09-22 — v1 part 3 of 9: Addresses the Iraqi way

- **Address form:**
  - **Who:** name, and a phone for the driver ("The driver calls this number…"). This is the shared `IraqiPhoneField` (+964, Iraqi mobiles only), saved as `+9647XXXXXXXXX`.
  - **Where:** the governorate from the list, the area or neighbourhood, and the **nearest landmark** (both required), plus an optional street, alley and house no.
  - **Gone:** country, state, city typing, building, apartment and postal code.
  - A new address **starts filled in** with the shopper's name, number and city (Home's city, else the account's), so most people only type where it is. `IraqiPhone.local` shows a saved number as 0770… in the field.
- **Address entity:** `governorate` (enum, API code), `area`, `landmark`, `street?`. `formattedIn(languageCode)` gives "Street 14, House 7, Al-Mansour, Baghdad", with the city in the app's language.
- **Where it shows:**
  - The address card has a landmark line.
  - Checkout's card and picker show the city in the app's language.
  - The order page shows "Nearest landmark: …" and the invoice has the localized city.
- **Store side:** the store's order page now gets the address **in parts** (`MerchantOrderDetail.shippingAddress` is an `OrderAddress`, parsed by the same `OrderMappers.address`). It shows the address, the nearest landmark and the shopper's note, and the driver needs all three. The order list shows the area.
- **Demo backend:**
  - Amina's address is Al-Mansour, Baghdad, "Behind Al-Mansour Mall".
  - An order copies the address fields as they are at purchase, and each store's part carries the same copy.
  - The sample store orders use Karrada (Baghdad) and Ainkawa (Erbil) with landmarks.

Tests: **448 pass, analyze clean, 857 keys.**
- The "country is prefilled" test is replaced: a new address starts with her name, number and city; there is no country or postcode field; the area and landmark are required; a non-Iraqi number is refused.
- The add-address test picks Basra and checks what's saved and shown.
- The two-store test checks that the store gets the landmark, city and phone.
- Eleven breaks all went red.

**For the backend:** validate the address server-side (Iraqi mobile, a known governorate code, area and landmark present). The demo stores what it's sent.

## 2026-09-22 — v1 part 4 of 9: Cash-only checkout

- **Cash only:** checkout offers Cash on delivery, and "Credit or debit card" greyed out with "Coming soon" (bilingual, from the server). The wallet row is gone. The line under the pay button always says to pay in cash, and the escrow sentence and strings (`escrowNote`, `heldInEscrow`) are removed. The server refuses a non-cash order, and every order is saved as cash (`COD`, pending until delivered).
- **What to pay each driver:**
  - **Server:** every store part carries `discount` and `amountDue` (subtotal − its own coupon + its delivery), and the order total is the sum of the parts. `CheckoutGroup.amountDue`/`discount`.
  - **Checkout:** with two or more stores, a "Cash to each driver" block under the total lists each store beside its amount.
  - **Shopper's order page:** "Cash to the driver: X" under each store (from `storeParts` → `Order.dueByStore`), "Paid to the driver" once delivered, nothing when cancelled.
  - **Store side:** the order card and order page say **"Collect in cash"** with the part's amount after its own discount. The order page shows the store's coupon discount.
- **Steps of 250 IQD:** percentage discounts are rounded down to 250. Store prices (product price, original price, variant prices) and fixed-amount coupons must be multiples of 250, checked on the form (`Validators.cashPrice`/`optionalCashPrice`) and by the server. Demo prices were already whole thousands.
- **First-order limit:** a shopper with no delivered-and-paid order can order up to 1,000,000 IQD. Review returns `canPlaceOrder: false` plus the reason (EN/AR), the pay button is disabled with the reason shown, and place-order refuses. Once one order is delivered and paid, the limit lifts. The demo shopper starts with no orders, so the limit applies to her until one of her orders is delivered.
- **No Saba coupons in v1:** SABA10 and WELCOME are removed. Store coupons (NOVA10, ATLAS5000, the stores' own) stay.
- **Decision made in this part — no tax line:** the demo added an invented 16% "tax" to every order. It is removed, because Iraq has no VAT on these goods and the per-driver amounts must add up to the total. The app still shows a tax row if a backend ever sends one.
- **Bugs found and fixed:**
  - A coupon code was only checked against stores whose coupons had already been loaded, so Nova could take "ATLAS5000". It is now checked against every store.
  - The cart's applied-coupon pill overflowed with a long store name; the text now shortens with "…".

Tests: **455 pass, analyze clean, 861 keys.**
- New `test/features/cash_checkout_test.dart`: cash only and card refused; each driver's amount with 250 rounding, the store collecting its part; the first-order limit and its lifting after a delivered order; 250-step prices and coupons, and the code clash.
- `checkout_test`: the per-driver block, "Coming soon", the order page's cash lines, the store card's "Collect in cash", and the button disabled over the limit.
- `merchant_journey_test`: "Collect in cash" on the store order page, and the product form refusing 12,300.
- The old Saba-coupon tests now use store coupons. The "settled payment" test now pays by delivery. The two-store test uses products under the limit.
- 17 breaks all went red; the coupon overflow was seen failing before the fix.

**Later (part 5):** delivery fees become store settings (in steps of 250), and the store's order list will show the customer's city.

## 2026-09-22 — v1 part 5 of 9: Each store's own delivery

- **Store settings → Delivery** (new section):
  - which governorates the store delivers to, as 19 chips plus "All of Iraq" and "Only my city"; its own city is always on;
  - a **fee in its own city** and a **time** for it;
  - when it goes elsewhere, a **fee to other cities** and a **time** for that.
  - Fees are 0 (free) or steps of 250 (`Validators.cashFee`). Times are picked from Same day, 1–2, 2–3, 3–5 or 5–7 days.
  - The server checks the same rules and always keeps the store's own city.
- **`core/location/store_delivery.dart`:** the `DeliveryTime` enum (with its labels), `StoreDelivery` (`to(city, storeCity)` gives the fee and time, or null) and the `StoreDeliveryLine` widget.
- **The shopper sees it before buying:** on the product page (under the store card) and on the store page: "Delivers to Baghdad · 3,000 IQD · 1–2 days", or **"Doesn't deliver to Erbil"**, for the shopper's city.
- **`shopperCityProvider`** (the Home choice, else the sign-up city) is now the one source used by Home, a new address and these lines.
- **Checkout:**
  - Each store's part is priced by the chosen address's city, at that store's own fee and time. Standard/Express and "free over 200,000" are gone; they were invented for every store alike.
  - A store that doesn't deliver there is marked in its block: "Doesn't deliver to Erbil. Take its items out, or choose another address." A warning names it, the pay button is disabled, and the server refuses the order.
  - When the address is in a different city from Home's, a note says the order goes to the address's city.
  - The order's estimated delivery is the slowest store's time.
- **Store order cards** show the customer's area and city ("Karrada, Baghdad").
- **Demo stores:**
  - Nova (Baghdad) delivers everywhere: 3,000 IQD and 1–2 days in Baghdad, 6,000 IQD and 3–5 days elsewhere.
  - Atlas (Basra) delivers to Basra, Maysan, Dhi Qar, Muthanna and Baghdad: 2,000 IQD same day in Basra, 5,000 IQD and 2–3 days elsewhere.
  - A new store starts with its own city only, at 5,000 IQD and 1–2 days.
  - Settings are shared across accounts, so what a store saves reaches every shopper's checkout.
- **Bug fixed across 9 forms:**
  - **The bug:** each form's fields sat in a lazy list, and a form only checks fields that are built. A mistake scrolled out of sight was never reported on Save.
  - **Which forms:** address, coupon, product, store settings, change password, profile, return request, review and support.
  - **The fix:** each is now a scroll view over a column.
  - **What it exposed:** two layouts that no test had ever drawn (fixed). "(optional)" beside a label now shrinks with "…" in narrow fields (the product-variant table), and the "All of Iraq / Only my city" buttons sit on their own line.

Tests: **461 pass, analyze clean, 880 keys.**
- New `test/features/store_delivery_test.dart`: pricing by the address's city, including another city's fee, totals and the driver's amount; an undeliverable store blocked in review and refused on placing; the customer's city on the store's order; a store saving its delivery (bad fee, no fee for other cities, own city kept) and the shopper's product page and checkout following it; the fee rule.
- Screen tests:
  - `city_test`: the product page and store page lines, following the Home city; the store settings Delivery section, with a bad fee caught on Save.
  - `checkout_test`: the undeliverable store, the disabled button and the city note.
  - `merchant_journey_test`: the product form now catches a bad price on Save, which is the form fix.
- The Express test is now "the store's own fee, the same the cart charged".
- 18 breaks all went red, including putting the product form back on a lazy list. One break first stayed green: the totals weren't checked. The test now checks them.

**Not done, by choice:** Home's "Featured stores" cards don't carry the delivery mark. The product page and the store page (where you decide) do. A per-store minimum order and vacation mode were not in the v1 list; the Open/Closed switch comes in part 7.

## 2026-09-22 — v1 part 6 of 9: The order journey

- **Store steps:** New → **Confirm** → Preparing → **Shipped** → **Delivered** or **Refused**. "Packed" is gone from the steps; an old packed order still goes on to Shipped.
  - **Confirm** opens "Call the shopper first…", with a Call button and "I called them: confirm". The order row now carries `customerPhone`.
  - **Shipped** asks "Who delivers it?": my driver, or a delivery company. It needs a name and an Iraqi phone; a company can add a tracking number. The server refuses Shipped without them.
  - Once shipped, the order page shows who delivers, with a Call button, and the bar offers **Refused at the door** (with a confirm step) beside **Delivered**.
  - **Returns** show on the store's order page: Approve and pick up / Decline, then "Picked up, cash handed back".
- **Shopper:**
  - Each store's part on the order page shows "Driver: Ali · +964… [Call]" (or the company and its tracking number) once shipped.
  - After delivery it asks **"Did you receive it?"** Yes, or No. A no tells the store to call ("Order X: not received").
  - A **Refused** status (chip and label).
  - The return form says 7 days, and cash back from the store.
- **New `core/widgets/call_button.dart`:** `callNumber` opens the dialer, or copies the number where there is none. **Added dependency: `url_launcher` 6.3.2** (Flutter's own package).
- **Demo backend:**
  - **Stock comes back** when a part is declined, refused or cancelled by the shopper, and when a returned item is collected.
  - **Reviews and returns open only on delivery.** Items start with `canReview`/`canReturn` false, and the server refuses a review of anything not received.
  - **Returns:** allowed 7 days after delivery (`deliveredAt`), one store's items at a time, refunded in cash. The store sees them (`_storeReturns`, the same records the shopper holds) and moves them Requested → Approved → Refunded, or Rejected; any other step is refused. The shopper is told each step.
  - Store parts carry the courier to the shopper's order (`storeParts`).
- **Bugs fixed:**
  - A return request read `price` and `name`, which order lines don't have, so **every refund was 0 IQD and every item "Item"**.
  - Three layouts that broke on a phone: the Call button forced infinite width in a row, because the app's buttons are full-width; the received question and buttons ran off the screen; and the returns list's "Refund amount" row overflowed once amounts were real.
  - A setState-during-build error showed up only when a test switched accounts before the app was drawn. With the app on screen, switching doesn't trigger it (checked), so it's not user-facing. That test now switches after the app is up.

Tests: **467 pass, analyze clean, 903 keys.**
- New `test/features/order_journey_test.dart`: shipping names who delivers and the shopper gets the number; stock back on decline, refuse and cancel; refused status; a review waits for delivery; the "not received" note reaches the store; a return is refused before delivery, has the right amount, name and cash method, and goes to the store, which can't hand cash back before approving; the item returns to stock; the shopper sees it refunded.
- Screen tests:
  - `orders_test`: the driver is named, Call dials `tel:+964…`, and "Did you receive it?" answers once.
  - `merchant_journey_test`: the ship sheet refuses an empty name and phone, the driver shows, and Refused at the door works. The store's confirm now goes through the call step.
- Updated tests ship with a named courier; returns and reviews happen after delivery.
- 22 breaks all went red. One of my breaks was wrong at first (operator precedence left it unbroken); once corrected, it went red.

**Not covered by a screen test:** the store's return card buttons (the pipeline test drives the same calls).

## 2026-09-22 — v1 part 7 of 9: Store money and dashboard

- **"What you owe Saba"** replaces the payouts page (same route, same Account tile, new label). It shows this month's amount and the lines behind it: delivered sales (N orders), cash handed back on returns, Saba's share (8%), and what you owe. A short note explains how the amount is worked out, and past months are listed as Due or Paid.
  - The math: 8% of delivered goods (the subtotal minus the store's own discount, with no delivery fee), minus the cash returned, rounded to the nearest 250 IQD. An order counts in the month it was **delivered**; delivery now records `deliveredAt`.
  - Payout and PayoutSummary are gone, replaced by SabaBill and SabaBills. The endpoint is `/merchants/me/bills`.
- **Real numbers on the dashboard and analytics.** They are worked out from the store's own orders and start at zero; the made-up 18,420,000 revenue is gone. Week, month and year are all real, and the top products are ranked by quantity sold. Inventory's reserved and sold counts come from real orders.
- **Open/Closed switch** on the dashboard (approved stores only). A closed store shows a "Closed right now" badge on its storefront. Its product pages say it can't take orders, the buy bar is off, and the server refuses the order at checkout. Endpoint: `/merchants/me/store/open`.
- **The Arabic product name is required.** The form has "Name in Arabic" first (it must contain Arabic letters), then "Name in English" (optional). The server refuses a save without it (`errors.nameAr`). Arabic readers now see `nameAr` everywhere the demo sends a name.
- **Bug fixed:** a store's edits to its own demo products were **not kept**. They are now saved in place, and reset restores the originals.
- **Look (the user's screenshots):**
  - The language screen is now white, with a black logo box and black buttons. The status-bar icons turn dark so they still show.
  - On "How will you use Saba?", the two role cards are bigger (56px icon, 17pt title, more padding), and the chosen card's icon fills orange.
  - Continue uses a new `AppButtonSize.large`: 58 tall, with a 16pt bold label. Other buttons are unchanged.

Tests: **472 pass, analyze clean, 921 keys.**
- `order_journey_test`: the 8% math (returns taken off, delivered only, 250 steps); a closed store takes no orders and the product page is told; the Arabic name is required and Arabic readers see it.
- `merchant_journey_test`: the switch closes the store and the owe page opens from Account; the form refuses English letters as the Arabic name.
- `merchant_orders_test`: the analytics test now checks the real numbers.
- 19 breaks all went red. One break at first didn't compile; a corrected break went red.

**Not covered:** no screen test for the shopper's closed-store badge or note (the pipeline test covers the `isOpen` data). "Paid" months never appear in the demo; the web admin will mark them later.

## 2026-09-22 — v1 part 8 of 9: Home and search

- **Home shows only what is true.** The demo server now builds Home from the catalogue and the orders:
  - banners (untouched), categories, your coupons;
  - **On sale**: a lower price the store set itself;
  - **Best sellers**: ranked by *delivered* quantity, and hidden until something is delivered;
  - **New on Saba**: newest first;
  - Stores and Brands.
  - Products that are out of stock, or from a closed store, stay off Home.
  - Removed: the **flash sale**, whose countdown restarted on every launch, and **"Trending"**, a fixed slice of the product list. The flash-sale card is kept in the app for a real sale later.
  - Section titles come in the reader's language. They were English only, so Arabic readers saw "Trending now".
  - The Stores row shows each store's real product count. It said 22 and 18; each store has 6.
- **Arabic search:** new `lib/core/utils/search_text.dart` (`SearchText`).
  - It treats these as the same: أ/إ/آ/ٱ and ا; ة and ه; ى, ی and ئ as ي; ؤ and و; ک and ك; vowel marks and tatweel are ignored; Arabic and Persian digits count as 0–9.
  - A leading ال is optional, and every word typed must match, in any order.
  - It matches the product's name in both languages and its category's name. The demo's brands and stores don't line up with the product names (brand "Lumen" on "Nova X5 Pro"), so it doesn't match those.
  - The store's own product search uses it too.
- **Demo data:** Arabic names for the 12 products (with أ, ة and a shadda in them on purpose) and for every category; a date added (`createdAt`) for each product; `nameEn` kept, so the store's form shows both names.
- **Popular searches** are real: what people searched for and found, most often first, and hidden until there is one. They were four fixed English words.
- **Bugs fixed:**
  - "Newest" sorted ids as text, so p-9 came before p-12. It now sorts by date added.
  - Arabic readers saw English section titles on Home, English product names, and English suggestions.
  - The seeded "Flash sale starts now" notification is now "Welcome to Saba: pay in cash when your order arrives…".

Tests: `test/core/search_text_test.dart` (2), and 2 in `order_journey_test`: Home shows only what is true, and search finds Arabic however it is typed. 22 breaks all went red. One break at first stayed green: the check that a search which found nothing isn't counted. Popular shows only the top six, so the unfound word was cut off either way. The test was tightened, and the break then went red.

## 2026-09-22 — v1 part 9 of 9: Final check

- **Rule pages:** Terms of use, Privacy policy and Return policy, in English and Arabic, at `/legal/terms|privacy|returns` (`lib/features/legal/legal_screen.dart`). Everyone can open them, signed in or not.
  - Every rule written there is one the app enforces: 7 days, cash back from the store, cancel until the store starts preparing, a first-order limit of 1,000,000 IQD, and 8% a month for stores.
  - **The wording is plain, not legal. A lawyer in Iraq should read it before launch.**
  - Reached from:
    - Account → About Saba (all three);
    - Account while signed out (links under Sign in);
    - both sign-up forms ("Creating an account means you agree to Saba's rules:");
    - the store's Account (Terms and Privacy).
- **One return rule, everywhere.** The product page and the storefront promised "14-day" and "30-day returns" (demo text from stores). Both now show Saba's rule, "7 days to return, cash back". Stores can no longer type their own return policy on the product form or in store settings; a line states the rule instead.
- **Demo-mode guard:**
  - Production already turns the demo server off, and the demo sign-in buttons show only in demo mode.
  - **New:** a code sent by SMS (`demoCode`) is taken from the server only in a demo build (`OtpChallenge.fromJson(json, demo:)`). A real server sending one by mistake would otherwise put every sign-in code on screen.
  - To check a production build: `flutter test --dart-define=APP_ENV=production test/core/demo_guard_test.dart`.
  - Also fixed: a stray doc comment and `@immutable` that sat on the wrong class in `auth/domain/entities.dart`.
- **Two search-page bugs, found while writing the phone checklist:**
  - After one search, opening Search again showed an empty box, but the page acted on the old word: its suggestions, and no Recent or Popular. The typed word (`searchTermProvider`) outlived the page. It now clears when the page closes.
  - Popular searches were read once for the life of the app, so a new search never appeared there. They are now read each time the page opens.

Tests: new `test/core/demo_guard_test.dart`; `account_screens_test`: the rule pages from Account signed in and out, in Arabic, the 7-day rule on the product and store pages, a store with no return field, and a search that shows under Popular with Recent back; `auth_walkthrough_test`: sign-up shows and opens the rules, for shoppers and stores. 13 breaks all went red (11 for the part, plus one for each search fix).
- The full run found one old test broken by part 8: part 7's "a product is not saved without its name in Arabic" opened a demo product and expected an empty Arabic name. Since part 8, the demo products have one. The test now checks the form opens with the Arabic name, then clears it and expects "required". Both of those went red when broken.

Full run: **482 pass, analyze clean, 928 keys.** v1 (parts 1–9) is built in demo mode. Not yet seen on a phone.

### Phone checklist (v1, all nine parts)
1. Fresh install: a white language screen, then the role choice with big boxes and a big Continue.
2. Sign up as a shopper by phone. The code shows on screen (demo only). You have to pick a city, and the rules line is under the form.
3. Home: no flash sale and no countdown. On sale, New on Saba and Stores (6 products each) are there. In Arabic, the titles and product names are Arabic.
4. Search in Arabic: ساعه, اطلس, منقي, الكاميرا and ٦٥ each find their product. Go back to the search page and the word is under Popular searches.
5. Buy something (cash). The first-order limit is 1,000,000 IQD. Pay each store's driver separately.
6. As the store (0771 123 4567): Confirm (call first), then Shipped (name the driver), then Delivered. On Home, Best sellers now shows it.
7. As the shopper: "Did you receive it?", then Return within 7 days. The store approves, then hands the cash back.
8. The store: What you owe Saba is 8% of delivered sales minus returns. Try the Open/Closed switch, and a product without an Arabic name (refused).
9. Account → About Saba: Terms, Privacy and Return policy, in both languages. The product and store pages say "7 days to return, cash back".

## 2026-09-22 — Home redesign, part A of B: cities, every product, flash sale back

Asked for by the user with a reference screenshot; approved with "approve all". No impact on the store or admin screens: there are no admin screens, and the store screens share nothing that changed. Nova and Atlas keep the same twelve products, and new things are only added alongside, never changed.
- **Demo data:** 6 new stores (Zakho Mobile and Duhok Home Center in Duhok; Citadel Electronics and Erbil Cool Air in Erbil; Slemani Gadgets in Sulaymaniyah; Mosul Appliances in Nineveh), each with its own delivery settings, and 28 new products with Arabic names. That makes 40 products across 6 cities.
  - A product's city is its store's city.
  - The first 12 products are assigned to their stores as before (not by position in the list), so the store logins look exactly the same.
- **City chips under the search bar:** "All cities" plus each city that has a store. The picked chip is orange with an icon. A chip filters only the product grid (`governorate` on `/products`); where the shopper is delivered to doesn't change.
- **All Products grid after Featured Stores:**
  - A Filters button (the existing filter sheet) and "N found", which follows both the city and the filters.
  - Two columns of the new `ShowcaseProductCard` (Home only): a large square photo, the heart on it, an orange "-20%", the name, the price, and "Delivery available" when the store delivers to the shopper's city.
  - Cards are built as they scroll into view, and the next page loads before the end.
- **Flash sale is back:** a daily sale of products whose store really lowered the price, ending at midnight in Iraq. Its card style is unchanged, and a closed store's offers drop out.
- **Removed from Home:** Best sellers, Brands, On sale and New on Saba. Featured Stores shows all 8 stores, with their real product counts.
- **Tests:**
  - `order_journey_test`: a new flash sale and stores test, and a city test (9 in Duhok; delivery answered per store). Part 8's Home test was replaced.
  - `account_screens_test`: the Home chips on screen (40, then Duhok's 9 with only m-3 and m-4, the card's -20% and heart, and paging to product 40).
  - `shopper_journey_test`: now taps the new card.
  - 11 breaks all went red.
- A 3 px overflow in the new card's price row was fixed before it could ship: row heights now come from the theme's own line heights.

Tests: **484 pass, analyze clean, 931 keys.** Part B (the top bar, the heart by search, "Deliver to", fonts, polish) waits for the user's OK.

## 2026-09-22 — Home redesign, part B of B: top bar, search row, fonts, polish

The full picture, and the effect on store screens, is in `DESIGN_CHANGES.md`.
- **Globe icon** in the top bar, before messages and notifications (both unchanged). One tap switches Arabic and English. Home then reads its data again in the new language: `homeFeedProvider` follows `acceptLanguageProvider`, and the grid reloads its list. Before, a switch left the server's English titles and product names on screen.
- **"Deliver to …" removed** from the header. The shopper's city (`shopperCityProvider`) now comes from the profile first when signed in. Otherwise a city picked with the old button would have won over the profile for good, with nothing on screen left to change it.
- **The heart beside the search is removed on Home** (`ShopHeader.showWishlist`, off on Home only). Categories keeps its heart.
- **Fonts:** DM Serif Display (English) and Amiri Bold (Arabic) for Home's headings: the greeting name and every section title. Body text, labels and prices stay IBM Plex Sans Arabic.
  - The fonts are bundled for offline use, with their OFL licence files.
  - They are chosen in one place, `AppTypography.heading`, and the steps to switch Arabic to Cairo Bold are there.
  - fontTools confirmed both fonts cover every character the app uses.
- **Bugs found and fixed:**
  - **The greeting name was invisible** (white on the white header). Its style was built outside the header's own theme. `DarkHeaderGreeting` now always takes the name's colour from the header.
  - **On a 320 px phone the name was cut to "Ami…"**, because the globe took room in that row. Home's greeting now shrinks to fit (`shrinkToFit`).
  - **At the largest text size, section titles were cut** ("Shop by cat…"). Home's titles may now take two lines (`SectionHeader.titleMaxLines`).
  - **Featured Stores overflowed** by 3 px (English) and 11 px (Arabic) at large text: part A's longer store names wrap to two lines in a row that was a fixed 172 px. The row now grows with the text size, and is still 172 at normal size.
  - **Arabic category icons were wrong** (سماعات showed a sofa), since part 8 gave categories Arabic names and the icon picker knew only English words. `iconForName` now knows the Arabic words too. English is unchanged.
- **Tests:**
  - New `test/widget/home_redesign_test.dart` draws Home with the real fonts. It covers the globe (direction, titles, chips and the grid's first product name switching both ways, and the heading fonts in each language), messages and notifications still opening, the fonts being declared and bundled, the greeting being readable and whole, titles being whole at 1.4, and no overflow on small, large-text and large phones in both languages, scrolled to product 40.
  - New `test/core/icon_for_name_test.dart`.
  - Updated for the removals: `home_promises_test` (no heart on Home), `city_test` (no city button; the profile city wins; the delivery lines follow a profile change), `auth_walkthrough_test` (the sign-up city is the shopper's city), and `account_screens_test` (Categories keeps its heart).
  - 15 breaks all went red. One at first stayed green: the font check matched "family: Amiri" inside "family: AmiriX". It now matches the whole line, and the break went red.
- `--dart-define=SABA_SHOTS=true` saves pictures of Home to `mobile/build/home_shots/`; they were used to check it by eye.

Tests: **498 pass, analyze clean.**

## 2026-09-22 — After Part B: the banner's words at the largest text size

The user's answers to Part B's open points:
- **Banner clipping:** a bug, so fixed, with the banner's look unchanged.
  - The demo banners have no photograph (`assets/images/stores/` is empty), so the phone draws each one as a coloured card with its words.
  - On a 320 px phone at text size 1.4, the Arabic title's second line was cut in half, and the one-line subtitle lost its end.
  - The subtitle may now take two lines like the title. When the words are taller than the card, they shrink together (`FittedBox`, scale down only); their width and wrapping are unchanged. At normal text size Home is pixel-identical to before.
  - New test in `home_redesign_test`, run in English and Arabic: every banner text is whole and drawn at its full height. Both breaks went red: the old layout ("clipped") and the subtitle held to one line ("cut").
- **Categories title in the heading font:** kept, for consistency.
- **Other screens keeping the old language after a switch:** not fixed now; it goes on the bug list (`BUGS.md`).

Tests: **500 pass, analyze clean.** Committed as "Part B done - stable".

## 2026-09-22 — Bug audit (no code changed)

- Backup first: commit `9ffe972` "backup before bug audit", tag `backup-before-bug-audit`.
- `BUGS.md`: 13 bugs found by reading the code (4 critical, 5 important, 4 small), with the areas not yet checked listed at the end.
- `PROJECT_MAP.md`: the app's structure, roles, folders, data models, and how the shopper and store sides share data.
- The parallel review agents were stopped (usage limit, then to save tokens); the pass was finished by hand.

## 2026-09-22 — Bug fixing, step 1: every account's data is its own

Bugs #2 and #3 from `BUGS.md`, plus #12. The app kept one account's lists for the whole session, so the next person to sign in on the same phone opened on them.
- **One thing to follow:** `accountIdProvider` (`features/auth/presentation/auth_providers.dart`) is the signed-in account's id, or null. Every repository but sign-in's own watches it, and so does every list and controller that reads its repository once in `build`: orders, notifications, returns, support, addresses, cart, wishlist, compare, checkout, chats, sessions, notification settings, uploads, the search box, Home's city and filter choice, and every store list (dashboard, shelf, stock, orders, counts, analytics, bill, settings, coupons). A sign-out or a different sign-in drops them all at once - on an open screen too.
- **Each account its own id.** Every shopper was `u-customer`, so the app could not tell one from the next. The three demo people keep their ids; any other account is named by the email or phone it signed up with.
- **Each new store its own id.** Every store opened in the app was `m-new`, so two new stores would have shared orders, coupons and delivery settings.
- **Recent searches** are kept per account (and one list for a guest), not one list for the phone.
- **The demo server is kept on the phone** (`core/mock/mock_state_saving.dart`, `MockApiInterceptor.keepOnDevice`, hooked up in `main.dart`): its whole state is written as one JSON document after each request that changed something, and read back when the app starts. So closing the app no longer loses an account's orders, cart, chats or its store's work, exactly as a real server would keep them. An order is one record shared by the shopper's list and the store's order book, and a return is shared with its store; the document writes such a record once and points at it from everywhere else, so a store's step still reaches the shopper's own copy after a restart. A document from an older version of the app is dropped rather than half-read.
- **Tests:** new `test/widget/account_switch_test.dart` - four tests, all inside ONE running app: two shoppers on one phone, two stores, two new stores, and closing and reopening the app. This is what the old tests could not see, because each started a fresh app per account. 9 breaks all went red.
- **Fixed because it was blocking:** the store dashboard's order count changed by itself (7, then 8). An order placed at exactly "now" counted as "not placed yet", and the demo store's newest sample order is placed at "now", so the number depended on the clock. Noted in `BUGS.md`.
- Also updated `test/features/fake_data_containment_test.dart`: the new file is demo data and lives in `lib/core/mock`, where that test says it belongs.

Tests: **504 pass, analyze clean.**

## 2026-09-23 — Bug fixing, step 2: one order, one status

Bug #4 from `BUGS.md`, and the order-history part of #11. A new order said "Confirmed" the moment it was paid for, while its store still had it as new and had not called the shopper yet.
- **A new order waits for its store.** The shopper's order and its lines are written `PENDING` at checkout, not `CONFIRMED`. The store's part stays `NEW`, which the app reads as the same status.
- **Only the store confirms it**, from its own screen, as it always did. Because the false entry is gone, the store's "Confirmed" is now the only one in the history, instead of the second.
- **No payment line at checkout.** "Payment recorded" was written the moment the order was placed, on a cash order nobody had paid. Cash is still marked paid when every part has been delivered, which is when the drivers have collected it.
- **The history line is written in the language the app asked for** ("Order received" / "وصل الطلب"), like the rest of the demo server's own words. What an order already holds is not rewritten later, the same way its "Cash on delivery" label is not.
- **Two words, one status, by the user's choice:** the store's screens keep saying "جديد" (clearer for a store owner) while the shopper reads "قيد الانتظار". The status underneath is the same on both sides, and `PROJECT_MAP.md` now says so.
- **`PACKED` left as it is**, by the user's choice, and written down as bug 34 so it can be decided later.
- **Tests:** new `test/features/order_status_test.dart` - four tests: a new order waits for its store and both sides say so; nothing is paid or confirmed at checkout; the history line follows the language; and one order walked CONFIRMED → PROCESSING → SHIPPED → DELIVERED where, after every step, the shopper's status, the lines' statuses and the store's own status agree, "Confirmed" appears exactly once, and cash is paid only on delivery. 4 breaks all went red.
- No existing test had to be changed: the whole suite went from 506 to 510 without touching one.

Tests: **510 pass, analyze clean.**

## 2026-09-23 — Bug fixing, step 3: a screen shows what is true now

Bugs #7 and #8 from `BUGS.md`. The whole design, and what the backend has to provide to take it over, is in `BACKEND_READY.md`.
- **One announcement, both sides.** `LiveTopic` names the subjects a screen can show - `orders` and `notifications` - and `LiveUpdates` (`core/network/live_updates.dart`) announces one when it changes. `liveTopicProvider(topic)` counts those announcements, and every list, detail screen and badge showing that subject watches it, so it loads again by itself.
- **Who announces:** `ApiClient`, after every call that is not a read; the path says the subject. So a shopper cancelling, a store confirming, a notification being read - each reaches every screen showing it, on whichever side of the app is open.
- **Coarse on purpose:** an announcement says only which subject changed, never what. Whoever shows it asks the server again, so nothing can go half-applied or stale, and a repeated announcement costs one request.
- **Now following their subject:** My orders, an order's details, the notification list and the dot on the bell; and on the store's side its orders, one order, the tab counts and the dashboard.
- **Pull-to-refresh** was already on all five screens and is kept as the backup.
- **Tests:** new `test/widget/live_updates_test.dart` - an order paid for while My orders is open appears in it (and on screen); cancelling from the details reaches both the details and the list underneath; a store's step reaches its own orders and its dashboard's "waiting" count; and the dot on the bell goes out when the notifications are read. 6 breaks all went red.
- Nothing else changed: the screens themselves were not touched.

Tests: **514 pass, analyze clean.**

## 2026-09-23 — Bug fixing, step 4: Saba's own side, so someone can say yes

Bugs #5 and #6 from `BUGS.md`, and the demo half of #1. What the real web admin has to cover is in `ADMIN_REQUIREMENTS.md`.
- **A demo admin that signs in like anyone else:** `admin@saba.app`, phone 0770 999 9999, not listed with the other demo accounts on the sign-in screen. It lands on one screen at `/admin`: what is waiting, with Approve and Reject. Saba's staff cannot open the shopper or store screens, and nobody else can open `/admin` - the demo server refuses `/admin/...` to anyone who is not an admin (`403 Admins only`), the same check a real server makes, so the web panel can take these routes as they are.
- **A new store no longer waits for ever.** Opening a store writes it into a shared review list, which an admin sees and answers: approved, and the "under review" banner goes; rejected, and the store is told. The status is kept where the store cannot set it itself, and it survives every account switch and a restart.
- **A product a store adds now reaches shoppers** once an admin approves it: it is in search, its category, its store's page and Home, and it can be bought. Before, nobody could approve it and nobody could see it.
- **A product belongs to its store, not to whoever is signed in** (`_storeProducts`). It used to sit in the signed-in account's own things, so it vanished when anyone else signed in and no admin could ever have seen it. The whole catalogue - the product page, its options, search, the category filter, the cart and stock - now looks products up in one place, so an approved product behaves like any other.
- **Starting the demo again:** one button on the admin screen, behind a confirmation that says what it removes. Everything goes back to the first day and is written to the phone at once, then the admin is signed out. Asked for by the user before step 2.
- **Tests:** new `test/widget/admin_demo_test.dart` - five: only Saba's staff reach the admin screen (and they reach nothing else); the server itself refuses anyone else; a new store waits, is approved, and is told - and a rejected one too; a store's product is invisible until it is approved, then it is in the shop and its store sees it approved; and the demo can be started again. 8 breaks all went red.
- Two guard tests earned their keep and were told about the new arrangement: the saved-state test (a store's shelf is worked out from the shared list) and the reachable-routes test (the admin screen is reached by signing in, not by a link).

Tests: **519 pass, analyze clean.**

## 2026-09-23 — version 1, group 1: what the app does without

Deletion, not rework. Gone entirely — screens, routes, providers, repository
methods, demo-server routes, translations and tests:

- **Compare** (the whole `features/compare/` folder, the header control, the
  Account row and the ⋮ entry).
- **Report a product**, and with it the ⋮ menu itself.
- **Questions and answers** on the product page.
- **Product reviews and product ratings** — everywhere: the product page, the
  cards, search sorting and the "4+ stars" filter. A card now names the store
  instead, which is the useful thing on a marketplace. Stores keep their
  rating; group 2 makes shoppers give it.
- **The specifications table** (and the rows that fed it on the store's
  product form).
- **Two of the three identical rails**: "frequently bought together" and
  "similar products" are gone, "related products" stays.
- **Follow store.**
- **Notification preferences** and **active sessions**.
- **Recently viewed** (an endpoint and a repository method no screen used).
- **The card payment page**, the return/cancel markers behind it, and the
  greyed-out "Card — coming soon" row. `webview_flutter` went with it.
- **Product videos**, on the store's form and in the shopper's gallery, and
  the video picking underneath.
- **Change password**, brought forward from group 3: demo mode does not check
  a password at sign-in, so there is nothing a change could mean.

Kept: the wishlist heart, and **share**, which now copies the product's name
with its link rather than a bare URL.

461 tests pass (519 before; 58 went with their features) and analyze is clean.
104 string keys removed from both tables, which leaves 840.

## 2026-09-23 — fix: Saba's own staff could not sign in

The tester found it: `login_screen.dart` signed an admin straight back out
with "admin accounts sign in through the web admin panel". That guard was
written before there was an admin screen, and step 4 built one without
removing it — so `/admin`, approve and reject, and "Start the demo again"
were unreachable in the running app for a whole step.

Nothing caught it because every admin test called `signIn` on the auth
controller, which never touches the sign-in screen. The end-to-end sign-in
test now signs in **through the form** as all three roles — a shopper, a
store and Saba's staff — so the same blind spot cannot come back.

Watched red: with the guard put back, the new test fails on `Expected:
'/admin'`.

462 tests pass, analyze clean.

## 2026-09-23 — version 1, groups 3 and 4

**Group 3 — every button that lied is real or gone.** Submit for approval
moves a product; deleting a demo product takes it off the shelf and out of
the shop; editing one keeps the category and options it was given; delete
account really empties the account and does not hand it back at the next
sign-in. Change password and forgot password were **removed** instead — demo
mode accepts any password at sign-in, so neither could be made true. That
took the forgot and reset screens, their routes, endpoints and tests.

**Group 4 — one stock number.** Stock is kept per thing sold: a product
without options has its own count, a product with options has none of its own
and its figure is the sum of theirs. The inventory sheet names the option it
is changing; an option's adjustment saves (it used to be written under the
option's id and read back from the product's); the store's form hides the
stock box once a product has options; checkout refuses what has run out and
an order takes the stock from the right option.

466 tests pass, analyze clean.

## 2026-09-23 — the tester's three fixes

- **One delivery price.** The product page answered for the city the shopper
  browses from; checkout charged for the city their address is in. Both lines
  now read `deliveryCityProvider`: the default address's governorate, falling
  back to the browsing city when no address is saved.
- **A rejected store is told so.** The banner reads the real status: a red
  banner saying Saba did not approve it, and a button to support. No rejection
  reason is recorded yet — that belongs to the real admin panel.
- **An approved store hears about it.** The notice was addressed to the
  owner's email; a store's inbox is keyed `store:<id>`, so it went where
  nothing reads. Fixed, as the product approval always was.

469 tests pass, analyze clean. Each fix watched failing first.

## 2026-09-23 — Part B, and the tester's walk of Part A

Part B, five groups: seven categories with a real spread; a merchant's own
shop as a preview; a dashboard that says what is true plus a setup
checklist; a shorter product form whose photo stays; trimmed settings and
sign-up, a store logo, merchant-only notifications.

Then the tester's findings on Part A: the stock sheet set instead of added;
an option bought now comes off that option (an order line never recorded it);
a deleted account's number is released and the account refused; the card row
really gone; demo products sent for approval reach the admin; the shelf
refreshes after a stock change; one delivery speed per product page.

473 tests pass, analyze clean.

## 2026-09-23 — the tester's walk of Part B

Part B passed. Five small fixes before the client demo:

- The owner's own-store preview no longer shows "Only a few left".
- A new store is no longer handed a 5,000 IQD delivery fee it never chose,
  so "Set your delivery fee" stays open until the owner sets one.
- A new store's empty preview says its products are waiting for approval.
- Account's store badge says "Waiting for approval", not "Pending".
- "Add your first product" shows once on the dashboard, in the checklist.

Recorded for later (BUGS.md 92–93): the product page lets a shopper pick
more than the stock until it refreshes; the preview list would not scroll in
Chrome.

## 2026-09-23 — demo photos

Every product, category and store drew a grey tile: the demo named files in
assets/images/ that were never there.

- Product and category photos: the user's seven, one per category, cropped
  square, 800x800, compressed. Every product of a category shares its photo
  for now. `tool/demo_photos.py` makes them from `saba_test/demo-photos/`
  and counts them; a variation (`phones-2.jpg`) is one file and one run.
- Store logos and banners: drawn by script, each store's initial and colour.
- Home promos: no picture on purpose, so their words show in both languages.
- `test/core/demo_images_test.dart` fails if anything has no picture, names
  a missing file, or one over 200 KB. assets/images/ is 512 KB in all.

Canva's image generator made one good test photo and then refused every
call after four parallel agents hit it; nothing from it is in the app.

## 2026-09-23 — one card design everywhere

One `ProductCard` (the flash sale keeps its own), one `StoreCard`, one
`OrderCard` for both sides with one status colour map, and one
`SectionHeader` style. Removed: `ShowcaseProductCard`, `ProductListTile`
(unused), Home's `_MerchantCard`, the product page's store card body, both
`_OrderCard`s, the store's `_StatePill`/`_WaitingPill`, `_homeTitle`.
What looks different is listed in DESIGN_CHANGES.md. 478 tests pass.

## 2026-09-23 — two doc inconsistencies (from the admin web session)

- PROJECT_MAP.md said 40 demo products; there are 56. Fixed in both places.
- Seed orders no longer start in PACKED, which nothing writes (BUGS.md 34).
  The app still reads PACKED in case a real backend sends it; BUGS.md 34
  now says so. Two tests that used PACKED as "the step before shipping" use
  PROCESSING. 478 tests pass.

## 2026-09-23 — text and language pass

Counts agree with their nouns in both languages (one helper, Arabic's six
forms); every number is in Western digits; a language switch reaches every
open screen; an order's history is kept as codes and read in the reader's
language; the demo server answers in Arabic for every field with an Arabic
twin, option words and its error messages; the Arabic comma in Arabic;
duplicated "(optional)" gone; one name for favourites; the admin queue shows
a store's city; a rejection is not announced in green; buttons shrink and
labels wrap instead of being cut. BUGS.md marks 9-11, 23, 28-30, 32, 35-38,
40, 49-53, 55, 59, 61, 63, 67, 71-74, and half of 26. 485 tests pass.

## 2026-09-23 — seed delivery, a required cancel reason

- A store's seeded orders go to its own city and one other it delivers to,
  and charge its own fee for that city: no more flat 5,000, and no Atlas
  order in Erbil (BUGS.md 94).
- A cancel needs a reason from the list; the server refuses one without
  (BUGS.md 26).
- Recorded for the backend: the product form saves one language into both
  (BUGS.md 95). Store names stay English, as proper nouns. 488 tests pass.

## 2026-09-24 — critical and money bugs

15 (total leaves out stores that cannot deliver), 46 (one "for sale" rule
for the shop, the cart, checkout and the store's shelf; 49 of 56 demo
products on sale), 65 (not-found product screen; IQD fallback), 66 (units,
not lines), 47 (an option's own discount), 25 and 27 (a cancelled order's
payment and invoice say nothing is owed), 45 (Arabic and Persian digits in
every field), 20 (no 0 after +964). test/features/money_bugs_test.dart holds
each one; each was watched failing without its fix. 495 tests pass.

## 2026-09-24 — past months for "What you owe Saba"

The seed now has each demo store's delivered orders from three months back,
the same fixed arithmetic as the admin web's history (website orders.ts), so
both show the same orders and months (BUGS.md 96). Checked by running the
web's own code beside the app's: Nova's 11 and Atlas's 12 orders and their
bills match, except Atlas's last month, where the web subtracts a refund
only it has. A phone with saved demo data needs a reset to see them.
497 tests pass.

## 2026-09-24 — refunds and on-sale products in the history

- The app seeds the web's refunded returns on the history (every ninth
  delivered order, from the fifth; the fourth declined; refunded five days
  after delivery), and a seeded order shows its return. Only the refunded
  ones: the web's still-open ones are not in the app.
- The history buys only what was on sale (MockData.startsOnSale), one
  product after another per store. For the web to match, three changes:
  products.ts gives p-50 PENDING, p-42 DRAFT, p-41 REJECTED, p-4 PENDING,
  p-10 DRAFT, p-56 REJECTED and hides p-51; historyOrders filters its shelf
  to APPROVED and not hidden; and it picks
  `shelf[(nth + line) % shelf.length]`, where nth is that store's own count
  of orders made so far, not `n * 3`. Checked on a patched copy of the web:
  Nova's and Atlas's orders, refunds and bills are identical (Atlas, August:
  a 108,000 IQD refund, 246,000 IQD owed). 497 tests pass.

## 2026-09-24 — the tester's two fixes, and round 3

- Checkout's cash split leaves out a store that cannot deliver (15); a
  store hides and shows its own product from its shelf (46). 97-103
  recorded.
- Round 3 (BUGS.md): cart and checkout say plainly which store cannot come
  and what to do (14, 17, 18, 19), one total and no gap (16); the default
  switch (22); lists clear the floating bar on phones with a gesture area
  (31); no drivers on the role screen (39, 102); the shopper's seeded inbox
  (41); decline wording on a cash order (48); a Delivered tab (56); a
  Refresh button on paged lists on the web (60); unknown addresses go Home
  (84, 100); the rating sheet names the store (85); Account's one-row
  section (86); the product page's stock (92). 21 not found in the code.

## 2026-09-24 — PACKED gone (BUGS.md 34)

The status nothing could reach is out of the app, the demo server, the
strings, the tests and PROJECT_MAP: the shopper's statuses, the store's
"Preparing" tab and the labels. An order that ever arrived as PACKED would
read as an unknown status. 21 and 93 wait for a phone check, by the user's
decision. 505 tests pass.

## 2026-09-24 — the old root Flutter project removed (BUGS.md 13)

With the user's go, on its own commit: the `flutter create` counter app at
the repo root - lib/, test/, android/, ios/, macos/, windows/, linux/, web/,
pubspec.yaml, pubspec.lock, analysis_options.yaml, .metadata - and its
untracked build output and .dart_tool/. Kept, by the user's choice: .idea/
and saba_test.iml (local IDE files, not in git). README, SETUP and
PROJECT_MAP no longer describe it.

## 2026-09-24 — sign-up could take over an account (BUGS.md 107)

A second sign-up on a number re-pointed the number to the new account. Now
the code request for a sign-up says so (`purpose: SIGN_UP`), and a number
with an account is refused (409) before a code is sent; the number step
says "This number already has an account" with "Sign in instead". Register
refuses a taken number as well, so nothing overwrites an account. Signing
in and password reset still get codes. Tests that signed up on the demo
shopper's own number now use a free one. 507 tests pass.

## 2026-09-24 — the auth walk: the fixes that do not touch accounts

Wrong codes clear themselves; the demo chips fill numbers without the 0 and
stack full width; "Too short" says how many characters in words (a counted
"character" noun); +964 sits before the number in Arabic; the store form
says what happens after sign-up instead of "awaiting approval"; a read-only
field is never "(Optional)"; the role screen has the logo; Home says
"Hello"; the Arabic and "store" wording; no SMS-rates note. BUGS.md 101,
108-117. The account-changing items wait for the user's go.

## 2026-09-24 — the auth walk, the account changes (with the user's go)

Seven steps, each its own commit with a test that fails without it:
- 118: a password needs 8 characters; the case and digit rule is gone.
- 119: names at most 50 characters (a person) and 40 (a store), in every
  form and on the server; Home cuts a greeting name over 24 with "…".
- 120: a store name is refused if another store in the same city has it
  (case and spaces aside), at sign-up and on a rename.
- 121: email is out of sign-up and sign-in; accounts are by phone. The demo
  server still accepts an email sign-in for older accounts.
- 122: "Forgot password?" is back, by phone: number, code, new password. A
  code goes only to a number with an account (OtpPurpose). The real backend
  must check the code.
- 123: shoppers go straight to the number step, which has the logo, "Open a
  store on Saba" and sign in. The role screen's route is removed (the route
  guard would not allow an unreachable one); its file awaits the user's go.
- 124: store sign-up is one screen (name, store name, city, number,
  password); the business address moved to store settings.
513 tests pass, analyze clean.

## 2026-09-24 — the store's driver, not a tracking number (BUGS.md 125)

v1 has no delivery companies. Out of the app: the tracking number (the
shopper's copy card, the store's line, the models, the PATCH field), the
"delivery company" choice in the ship sheet, and their strings. The seed's
shipped and delivered orders carry the store's own driver instead, the same
eight as the admin web's DRIVERS table, with Arabic names; the shopper is
told "Haider Salim brings it" when a store ships. 514 tests pass.

## 2026-09-24 — auth follow-ups from the tester

- "Sign in instead" carries the number to sign-in (AppRoutes.signInWith).
- The code screen checked after the tester saw it stop at "580" once: a
  test now types a code a digit at a time after a wrong one, with the focus
  kept throughout, and reaches the form. Not reproduced; the file was being
  edited when it was seen.
- BUGS.md 108: the backend must also normalise numbers before comparing (a
  fake link with 0751... made a second account).

## 2026-09-24 — one number, however it is written; the role screen deleted

- The demo server keeps and compares every number in one form
  (IraqiPhone.normalize): 0751..., +964 751..., 964..., 00964..., spaces and
  Arabic digits are one number at sign-up, sign-in, the code and a reset.
  Found on the way: the code request put "+" before the typed digits, so a
  number written with its 0 became "+0751..." and matched nothing. Numbers
  in an older saved demo are brought to the one form when it loads.
- The role screen's file and its six strings are deleted (nothing routed
  to it since 123).
515 tests pass, analyze clean.

## 2026-09-24 — stores run their own flash sales (BUGS.md 126-128)

- **Store side:** "Flash sale" on each approved row of the product list
  opens a sheet: a sale price (250 IQD steps, lower than the price now),
  an end date and time, and "End sale now" while one runs. The row shows
  "Flash sale until 9:00 PM". No admin approval.
- **Data:** one new product field, `saleEndsAt`; the price before becomes
  `originalPrice`, the sale price `price`, and options come down by the
  same amount. The demo server ends every sale that is over before it
  answers a request, so no screen, cart or checkout reads an ended sale's
  price.
- **Home:** the rail is the sales still running, from the demo's products
  and the approved ones stores added (127), without deleted or hidden ones
  (128, already so), the soonest to end first. One countdown, to the
  soonest end - the card's look stays as it is - and at zero the app asks
  for Home again. Seven demo products start on a sale ending 3 to 30 hours
  after the app opens (p-7 and p-1 Nova, p-21, p-37, p-45, p-31, p-22);
  p-1 is sold in options, so the rail shows that case too.
- Notes: BACKEND_READY.md (the price on read, or a job that still checks on
  read); ADMIN_REQUIREMENTS.md (see running sales, cap the discount).
521 tests pass, analyze clean.

## 2026-09-24 — one way to show a number; a refused field comes into view (129, 130)

- IraqiPhone.display: every number the app shows is +964 770 555 0311,
  however it arrived. The demo server sends customers' numbers spaced and
  drivers' as stored, and the app showed each as it came.
- "nova electronics " in Baghdad was already refused with the exact name's
  message (the test now says word for word). The tester missed it because
  it was under a field scrolled out of view. Every form's check
  (validateAndReveal, 14 screens) now scrolls the first field with a
  problem into view, after the fields are built again, so the server's
  answer counts too.
- Found: on a 320x568 phone the sign-up form's window is 64 px tall (131,
  open).

## 2026-09-24 — room to type on a small phone (BUGS.md 131)

The sign-up step scaffold pinned the step's title above the fields; now
only the top bar and the button are pinned and the title scrolls with the
fields. Measured on 320x568 with a 260 px keyboard: store sign-up and the
shopper's profile step 0 -> 180 px; the other eight forms already had
163-284 px. keyboard_room_test holds all ten at 120 px or more.

## 2026-09-24 — the admin answers as the contract says (API_CONTRACT.md 6.1, 6.2)

- GET /admin/queue returns full records: products as AdminProduct (nameEn
  and nameAr, the category in both languages, the store and its status,
  photos, options, status, rejectionReason, isActive), stores as AdminStore
  (owner, phone, city, submittedAt, answeredAt, rejectionReason, product
  count), oldest first. Nothing under /admin is turned into Arabic: the
  admin reads both names whatever it asks in.
- Reject takes { reason }, required and trimmed (blank: 422, errors.reason);
  it is kept as rejectionReason and the store's notification says it.
  Answering twice is 409; approving a product with no Arabic name is 422
  errors.nameAr. Both answers return the full record. Errors carry the
  contract's code.
- In the app: the demo admin screen shows a product in both languages and
  asks why before a rejection; the store's shelf row and its "not approved"
  banner show Saba's reason. A new store's review keeps its owner's name,
  number and country; a new product its createdAt.

## 2026-09-24 — "Nothing to pay" on a past month

The store's past months said "Due" for a month with nothing owed: the demo
sends DUE for every past month, and a backend may send NONE. The badge now
goes by the amount - nothing owed says "Nothing to pay" in grey - and only
then by the status (the admin web's change, applied as given).

## 2026-09-24 — demo products that make sense (BUGS.md 132)

- The first twelve products are a written table, not a formula. Ids and
  stores keep their places (p-1 Nova, p-2 Atlas, ...), so the seeded
  statuses, stock and history still line up. Nova: X5 phone 329,000 (was
  389,000), Lumen Book 14 675,000, Kite Audio Studio 145,000, Nova Watch
  Series 4 189,000 (was 229,000), Orbit Mirrorless Camera 950,000, the 65W
  charger 25,000. Atlas Home: air fryer 95,000, steam iron 32,000, robot
  vacuum 265,000, stand mixer 145,000, espresso machine 185,000, rice
  cooker 45,000.
- Options: the phone in three colours and 128GB/256GB; the laptop in
  Silver/Black and 512GB/1TB (+120,000). Nothing else has options.
- Photos: one per category, as a placeholder (the user's call): the extra
  -2 and -3 photos are deleted, from demo-photos/ and assets/, and the
  script rerun. "Tab" and لوحي now draw a tablet where there is no photo.
- p-48 speaker moved to Accessories; p-53 is Mosul Appliances' electric
  oven and p-55 Erbil Cool Air's outdoor AC cover.
- The admin web ports this catalogue: it has to take the same table, or
  the two sides' orders and bills differ.

## 2026-09-24 — from the tester's report: one stock, the sheet, hidden products (133-136)

- The store's shelf and the shopper read one stock (the shelf zeroed its
  third product for its "Out" tab).
- The sale sheet calls the price without the sale "the normal price".
- "End sale now" asks first.
- A hidden product has no Flash sale button, and the server refuses one;
  a sale already running can still be ended.

## 2026-09-24 — design pass, part 1: colours

- The orange becomes a purple palette, set in `app_colors.dart` and
  `app_theme.dart` only. Purple is anything tapped, amber is heat (flash
  sale, discounts, countdowns, stars), and green and red are unchanged.
  The full palette in both modes is in DESIGN_CHANGES.md.
- Dark mode has its own values: a lighter purple with dark ink on it, dark
  purple tints, a deep-navy page and a lifted amber.
- Contrast is pinned: `design_tokens_test.dart` checks every pairing with
  the WCAG formula in both modes. Seen red: putting white back as dark
  mode's ink on colour fills fails three of them.
- Fixed on the way (unreadable before, in dark mode): white snack-bar words
  on green, blue and red; "Added to cart" white on green; fixed white on
  purple fills; white on Home's banner and on the store's coupon stubs.
- `test/widget/design_shots_test.dart` draws every shopper, store and
  sign-in screen in both languages and both modes to build/design_shots/.
  It is skipped unless run with `--dart-define=SABA_SHOTS=true`.

## 2026-09-24 — design pass, part 2: typography everywhere

- One heading hierarchy in `AppTypography`: screen title 30, bar title 20,
  a name 24, a section 21, a section in a card or sheet 18. The shared
  title widgets (PageTitle, SabaAppBar, SectionHeader, SectionCard,
  StepHeader), dialogs, sheets and the custom headings on every screen use
  it. Card titles, body and prices stay in Plex; so do numbers used as
  titles.
- Arabic headings are 18% larger: Amiri at the English size looked timid.
- The store's product list prices use the price style, not a grey caption.
- Checked at 320 px x1.4 in both languages: the product name broke a word,
  so it keeps the section size until part 4; the dashboard's store name
  now shrinks to fit. The seller card's collapse there was already so
  (BUGS.md 137, for part 4).
- Setting dialog titles once in `app.dart`'s builder made a test fail
  (setState during build in ConnectedProductCard): it wrapped every
  English build in a new Theme. Titles are set on the four dialogs instead.
- `design_pass_test.dart`: every title widget and a dialog use the heading
  font in both languages, with a screen title over a section over a card
  section, and the Arabic size lift. Seen red: the bar title back in Plex
  and the lift removed fail three tests.

## 2026-09-24 — design pass, part 3: button hierarchy

- Three levels: primary (solid purple, one per screen), secondary (purple
  outline on white), tertiary (purple words), plus red for removing or
  cancelling. The tonal secondary and the outline variant were one level
  in two looks; now `AppButtonVariant` is primary, secondary, text, danger
  and dangerText.
- Demoted: the cart's Apply and Save for later, the coupon Copy, the
  address card's Edit and Set as default, the store's Restock, the two
  language buttons. Decline on the store's queue is red words.
- A chip that cannot be changed is grey with readable words (Material drew
  it purple, words faded).
- Missed in part 2 and fixed here: the product form's section titles and
  the empty and error screens' titles.
- Left as it is, and asked in DESIGN_CHANGES: a filled Confirm on every
  waiting order in the store's queue.
- Tests: `design_pass_test.dart` checks the three levels and the red, and
  that no fourth look is left; `cart_test.dart` checks checkout is the
  cart's one filled button (seen red with Apply filled again).

## 2026-09-24 — muted text readable (BUGS.md 138)

- The admin web session found its muted grey was 2.9:1 on white. The app's
  `textMuted` was the same #8A99AB, and it is used for words people read,
  not only hints. Now #626D79 (as the admin's) and #8795A6 in dark mode.
- `design_tokens_test.dart` checks muted text on a card, the page and a
  field in both modes; the old values fail all six.

## 2026-09-25 — parts 1-3 approved; pictures of every screen

- The user approved parts 1-3 and kept "Confirm" filled on the store's
  orders queue: one primary per screen is about hierarchy, not counting.
- `design_shots_test.dart` now covers every screen (47: shopper, store,
  sign-in and admin) at phone size, 411 x 914. A long page gets up to three
  more pictures, scrolled. Each checks that it was not redirected. It
  writes `build/design_shots/index.html`, a row per screen with English
  and Arabic, light and dark side by side, built from the run's own
  pictures only.


## 2026-09-25 — the new logo

- The logo files were screenshot crops (the icon 221 px, the lockups
  blurred, backgrounds baked in), so all seven were rebuilt: the mark as
  SVG paths (`SabaMark`), the name as text in the app's language
  (`SabaLogo`), in purple, white and navy. Details in DESIGN_CHANGES.
- Wired into: the app icons (Android adaptive + older PNGs, iOS, web and
  favicon, via `tool/app_icons.py`), both launch screens (purple), the
  splash screen, sign-in and the phone step, the language screen, Home's
  header, every store-logo placeholder, the store's dashboard tile (now
  its saved logo, the user's answer 1) and the invoice (navy).
- Removed: the old logo tile, the "س" tile, the old Android launch tile,
  Flutter's icons, and eight unused bag/store icon files.
- Web: the page title and install name are "Saba", not the package name.
- Tests: `saba_logo_test.dart` (the name per language, white in dark mode,
  the mark as the store placeholder, the Android icon drawn from the same
  paths); seen red with the dark-mode rule and the placeholder broken.

## 2026-09-25 — fixes before part 4, then part 4

- Fixes (commit f3a01e5): Settings rows; the store read once in the demo
  backend (logo, name, city; BUGS 139-140); city on cards and cart lines;
  start-aligned sign-in and notes; policy pages; "Welcome to Saba";
  rejected products on the dashboard and in the edit form.
- Part 4: the product page in nine blocks with the fact pills; the
  discount a pill (BUGS 142); BUGS 137 fixed; the category name added to
  the product reply (BUGS 144).
- Tests: `before_part4_fixes_test.dart`, `store_read_once_test.dart`,
  `product_page_test.dart`, and checks added to the cart, Home city and
  sign-in tests; three older tests now scroll to the blocks they read.

## 2026-09-25 — API_CONTRACT 6.8-6.11 in the app

- D22: `takenDown` / `takenDownReason` on the store's product row ("Taken
  down by Saba: reason", a red badge), its Hide switch locked, and out of
  the shop. The demo gained `POST /admin/products/{id}/hide|unhide`, and a
  store's own switch is refused (409) on a taken-down product.
- D-S1: `MerchantStatus.underReview`, its badge and the demo's
  UNDER_REVIEW are gone; waiting is PENDING only.
- D28: Home's city chips come from their own route, `GET /stores/cities`
  (every open, approved store's city), before the rail changed. The demo's
  rail is the featured stores (`GET|PUT /admin/featured-stores`, all demo
  stores to start) and is left out when none are featured.
- D4 (demo): the bills list each month since the store began with a
  delivery or a refund; a refund-only month stays, owing 0. The seeded
  months are unchanged (no refund-only month in them).
- D-T2 (demo): the customer's reply moves WAITING_FOR_CUSTOMER or
  RESOLVED back to OPEN and sets `updatedAt` and `lastMessage`; a CLOSED
  ticket refuses it (409). The demo gained `POST /admin/tickets/{id}/status`
  (API_CONTRACT 3.8) so Saba can move one. The ticket list now refreshes
  after a reply, so its badge follows.
- D18: nothing needed.
- Atlas's August bill in the app: 68,750 IQD (1,005,000 delivered less
  145,000 refunded, 8%, to the nearest 250), the same as the admin web.
- Tests: `contract_decisions_test.dart` (D4 and D-T2 watched fail with
  their fix taken out).

## 2026-09-25 — BUGS 98, 99, 105, 106

- 99: a cancelled invoice says "none of this will be charged" and crosses
  its total out; the note is one widget (`CardNote`) with the order page's.
- 98: the owner's preview bar says buyers can't see a product that is not
  listed (the product reply's new `isListed`); a shelf row opens the edit
  form on tap.
- 105, 106: the demo records a ticket's `openedBy` and each order's
  `customerId`, as API_CONTRACT.md has them.
- Tests: `orders_test` (invoice), `before_part4_fixes_test` (bar, row),
  `contract_decisions_test` (ticket, order); each watched fail without its
  fix.

## 2026-09-25 — a shopper's id is the admin web's

- The demo names a shopper `cu-` and the last seven digits of their own
  number, as the web does (`website/src/data/people.ts`): Amina is
  `cu-1234567`, where she was `u-customer`. Stores and the admin keep
  their ids. An old email-only account has no number of its own and keeps
  `u-<email>`: it borrows Amina's number, and would have shared her id and
  her cached lists.
- Known limit: seven digits can repeat across numbers (0770 123 4567 and
  0780 123 4567 are both `cu-1234567`). Two such shoppers would share an
  id, and the app keys each account's lists by it. Both sides should use
  the whole number when the backend comes.
- Recent searches kept on a phone under `u-customer` stay there.

## 2026-09-25 — the tester's walk of the redesign (BUGS 146-159)

- Fee from the store's saved city; one "did it arrive" answer for the sheet
  and the order page; one calculation for the dashboard and Analytics; the
  city chip filters the flash sale. Photos only where they fit left 30 of
  56 with none; put back, by the user's call, to one shared photo per
  category on every product (BUGS 150).
- Smaller: a no-delivery pill and locked buttons; warranties by kind;
  named colour circles; no "maximum number of files" tile; no email on the
  account screens, Edit profile or the rule pages; chart labels in the
  reader's language and six months on the dashboard; "How was your
  order?"; the language tagline centred; no broken words at 320 px, and
  the header name under the icons when there is no room.
- Tests: store_read_once (fee), rate_store (two), contract_decisions
  (numbers, chart), city (flash sale), product_page (no delivery, warranty, colour names),
  account_screens (no email), before_part4_fixes (Arabic chart labels),
  home_redesign (320 px). Each checked against the old code where it
  could fail.

## 2026-09-25 — the tester's money round (BUGS 160-174)

- Returns: one per order line, at most what was bought, refunding
  `paidUnitPrice` (after the coupon); proved by `returns_money_test.dart`
  against the old code (three returns and 145,000 there).
- Checkout's coupon line; new options get new ids; a store's own product
  names its city; one seller per invoice only when there is one; unknown
  orders 404; coupons count a use only at a discount, amber under the
  minimum, "starts on" when early, minimum on the chips; the bill and
  Analytics refresh after an order step; sign-up forms need a verified
  number; return answers confirm, a decline gives a reason; the return
  page in words and v1's three steps; a two-store order confirmed once a
  store takes it; the dark home-city chip.
- "Did your order arrive?" coming back: reproduced (Not now, then a product
  and back Home), fixed as once an app opening per account.

## 2026-09-25 — refunds in 250s, the arrival answer kept, centring, links, share

- Paid prices round down to 250; "Yes, it arrived" is saved when tapped;
  the order page's answers are even halves; "Return details" and "My
  products" refresh (BUGS 175-177).
- The language screen centred again, and five notes outside the auth
  screens that the "start edge" pass had moved (BUGS 178). One
  `AuthSwitchLink` for "Sign in", "Sign up" and "Open a store on Saba"
  (BUGS 179).
- Share: investigated, not built (BUGS 180; BACKEND_READY.md).

## 2026-09-25 — the share button hidden

- The product page's share button is gone, with its copy-link code and
  its two strings, until Saba has a domain, a public product page and the
  deep link files (the user's decision; BUGS.md 180, BACKEND_READY.md
  "Sharing a product"). A test holds it off the page.

## 2026-09-25 — the order page's driver line and answers

- The driver and "Did you receive it?" moved out of the narrow column beside
  "Message" to the card's full width. The number has its own line, and the
  answers are `AppButton` halves at full size (BUGS 181-182).
  `order_page_layout_test` checks this with the app's real fonts on a
  360-wide phone, in English and Arabic; it failed on the old layout. Full
  suite: 658 passed.

## 2026-09-25 — "Close my store" in place of "Delete account" for stores

- A store's Edit Profile has "Close my store". It uses the existing
  open/closed switch, and the account stays. The demo's reply says what is
  still open: orders, what is owed to Saba, and the last day for returns.
  The app shows it after closing. Shoppers keep "Delete account".
- Test in `account_screens_test`; it failed on the old screen, where a store
  saw "Delete account".
- BACKEND_READY.md "Closing a store" has the full design, and BUGS.md 183
  records the Terms/Privacy contradiction.

## 2026-09-26 — saved for later no longer hidden by the empty cart

- The only item saved for later was kept, but the cart's empty state hid
  it. The empty state now needs nothing saved as well; otherwise the saved
  section shows, with "Move to cart" (BUGS 184). A test in `cart_test`
  saves the only item, sees it, and moves it back; it failed on the old
  screen.

## 2026-09-26 — the ten things

- Sign-in first after the language; the logo at the start edge; room above
  "Send code" (BUGS 185, 188).
- Related products from the same category (186). "In stock only" reads the
  stock now; the other filters checked and working (192). The city chips
  above "All products", the flash sale unfiltered (191).
- An example in every empty field, both sides, and typed commas read
  everywhere (187). The return page says why an item is missing (190).
- A box per store on an order, with a four-step bar (189).
- The web's Refresh button gone; lists reload on coming back (193).
- Notifications walked, both sides, both languages: reported, not built
  (194).
- New or changed tests: `home_filters_test` (new), `entry_flow_test`,
  `order_page_layout_test`, `orders_test`, `city_test`,
  `keyboard_room_test`, `web_refresh_test`; `auth_walkthrough_test` and
  `home_redesign_test` follow the new first screen and the chips' new place.
  Full suite: 692 passed, 20 skipped. Each new check was watched failing on the
  old code.

## 2026-09-26 — notifications lead somewhere, and chats notify

- Every notification opens what it is about: a store's order, a return, the
  store's product (a new route opens its form by id), the store's
  dashboard, a chat. A chat message notifies the other side, both ways; the
  driver's number reads +964 770 111 2222 (BUGS 194). Support replies are
  left for the backend.
- Tests: `notification_targets_test` (new) walks each event to its target;
  `account_screens_test` taps a store's new order, its product and a
  shopper's return and checks the screen that opens. Both failed on the old
  code.

## 2026-09-26 — the tester's check of the ten; NEW becomes PENDING

- The order follows its slowest store exactly (BUGS 195); an empty stock box
  (196); lists reload on a stock change, search and option cards read live
  stock (197); the chat's "About…" above the box (198); the demo's own
  notifications keep their time and their side (199).
- The store's new-order status value is PENDING (BACKEND_PLAN.md 8.4, BUGS
  200); the shopper's side still reads NEW as pending.
- Tests: `two_stores_test`, `keyboard_room_test`, `home_filters_test`,
  `store_chat_test`, `notification_targets_test`, `merchant_journey_test`
  ("To confirm" lists PENDING), `returns_money_test` (the old "not pending
  once a store moved" rule reversed). Each new check failed on the old code.
  Full suite: 698 passed, 20 skipped, then the one reversed test fixed and
  its file rerun.

## 2026-09-26 — Resend asks for a sign-up code

- The code step's Resend sends `purpose: SIGN_UP`, as the first send does
  (BUGS 201). Test in `entry_flow_test`: a number with an account on the code
  step, Resend is refused; it got a new code on the old screen.

## 2026-09-27 — coupon days in local time

- The coupon form reads its days in local time (BUGS 202). New
  `coupon_dates_test`: a coupon sent in UTC opens on its own days and saves
  them unmoved; on the old form it showed the day before (the machine is
  UTC+3, as Iraq is).

## 2026-09-27 — M1: accounts against the real server

- Walked with the app's own account, profile and address code against the
  live backend (`test/live/m1_accounts_walk_test.dart`), in English and
  Arabic; SMS codes read from the server's log. Every step of M1 passed; no
  app change was needed.
- Opened every main screen, shopper and store, against it
  (`test/live/screens_walk_test.dart`): each opened, and the server refused
  no request it should have answered.
- Both walks are skipped unless run with `--dart-define=LIVE=true` (flags in
  the files). Full suite in the demo build: 701 passed, 23 skipped.

## 2026-09-27 — M2: a store's settings against the real server; in-app admin gone

- `test/live/m2_store_walk_test.dart`, in phases (waiting / approved /
  suspended): a new test store's settings, delivery terms, logo, name
  rules, open and closed, in English and Arabic, all passed against the
  live backend. The approved and suspended phases wait for the web (W2).
- The in-app demo admin deleted (Q12, BUGS 145): screen, route, "Start the
  demo again". An admin session counts as signed out in the router, and
  sign-in tells Saba's staff to use the web panel. Tests answer as the web
  through `test/support/saba_web.dart`. Full suite: 695 passed, 20 skipped.

- M2 after the web answered (2026-09-28): the store signs in approved; its
  three notifications (approved, suspended, active again) arrived in English
  and Arabic, each opening the store's dashboard; the shopper sees its public
  page (name, delivery, 0 products) and Baghdad among the city chips. The
  suspended state itself was not seen from the app: the store was already
  active again when the walk ran.
- M2 suspended (2026-09-28): store 15 suspended on the real server; the owner
  signs in, the app reads it as suspended, the dashboard and the account say
  "Suspended" with no open switch, and the notice arrived in English and
  Arabic. M2 is fully walked.

## 2026-09-28 — M3: products, from the shelf to the shopper, against the real server

- `test/live/m3_products_walk_test.dart`, in phases (add / answered /
  takendown / restored), on M2's test store (id 15): M3 Phone (57) and M3
  Case (58). Every refusal, the web's answers and their notifications,
  search (Arabic with ا, category name, suggestions), Smartphones and
  Phones, the store page, related, filters and sorting, wishlist, flash
  sale, stock, hide and show, taken down and restored, closed and open,
  delete, in English and Arabic: all passed. M3 Case deleted; M3 Phone left
  for M4.
- App fix: BUGS 203 (a refusal on photos or options was silent).
- Step 11 seen on screen: `test/widget/closed_store_page_test.dart`, a
  saved product of a closed store opens from the wishlist and says the
  store is closed, with no way to buy (red-checked).
- Server notes sent: the reason's double full stop (fixed in 04b0a55); a
  photo not uploaded is refused as "Not valid."; a two-letter Arabic name is
  refused as "Write the product name in Arabic."
- Step 8's known note, fixed (BUGS 204, the backend session's
  `hasVariants`): a product sold in options has no stepper or Restock on
  the shelf, in the demo and on the real server (M3 Phone checked,
  `PHASE=shelf`). M3 Case was already deleted, so the stepper on a product
  without options is checked in the demo only.

## 2026-09-28 — M4: buying, from the cart to delivered, against the real server

- `test/live/m4_buying_walk_test.dart`, in phases (place / zakho / deliver
  / rating / cancel). Orders: SB-100166 (both stores, delivered, rated),
  SB-100167 (one charger, for the rating sheet), SB-100168 cancelled,
  SB-100169 declined, SB-100170 refused at the door. Steps 1-10 passed; M3
  Phone's stock came back each time.
- App fixes: BUGS 205 (no cash asked for a refused or cancelled part), 206
  (the demo refuses what has run out, as the server now does).
- The rating rule stays: a "yes" on the order page is not asked for stars
  (the user, 2026-09-28).
- Steps 11-12: the store's tabs and counts, and an order's page (name,
  address, landmark, phone, driver), on the real screens in English and
  Arabic. BUGS 207: a "Cancelled" tab. M4 done; full suite 700 passed.

## 2026-09-28 — M5: returns against the real server

- `test/live/m5_returns_walk_test.dart` (returns / before / suspended /
  unsuspended). Return 12 (Kite headphones, refunded 130,500 = the price
  after NOVA10; stock back only at REFUNDED) and 13 (M3 Phone, declined
  USED; stock unchanged). Every refusal, Ahmed's 7-day window, Arabic:
  passed. App fix: BUGS 208 (no refund shown on a declined return).

## 2026-09-28 — M6: the store's money screens against the real server

- `test/live/m6_money_walk_test.dart` (money / bills / close / screens).
  Every bill of Nova, Atlas and M2 Store matches the backend's figures and
  the 8% rule worked out again in the test; Atlas's August paid on 15 Sep
  and back to due; closing Atlas (7 open orders, 170,250 owed, returns
  until 3 Oct) and open again; dashboard counts against the orders and
  shelf tabs; analytics series summing to their totals. App fix: BUGS 209.

## 2026-09-28 — M7: chats and support tickets against the real server

- `test/live/m7_chats_walk_test.dart` (chats / tickets / answered / waiting
  / closed / reopened). Chats: order, unread for one side only, 1-2,000
  characters, "Message from ..." cut to 80, two sides only, "Message the
  store" reusing its chat and unlisted until written in. Tickets T-5012
  (Amina) and T-5013 (M2 Store): refusals, Saba's unsigned answers, waiting,
  closed (409), open again; all in Arabic too. No app change. The walk signs
  each account in once: the server allows 10 sign-ins per phone in 15
  minutes.

## 2026-09-28 — M8: live updates from the real server

- `core/network/live_channel.dart`: `GET /events` through the app's own Dio
  (token attached and renewed as for any request), each `data:` line's
  topic announced, others ignored; every topic announced after each
  (re)connect; again at once after a normal end, after 1, 2, 4... 30 s after
  a failure; a stream that ends within 5 s counts as a failure.
  `liveChannelProvider` opens it for the signed-in account (never in demo
  mode), closes it at sign-out or a switch, and on a store's STORE
  notification reloads the account (BACKEND_PLAN §9 item 7). Tested with a
  fake connection (red-checked).
- `test/live/m8_live_walk_test.dart`: all nine steps passed against the
  real server (steps 6 and 7 on a copy on :3002). Orders SB-100171/172/173,
  ticket T-5014.
- Known limitation, by decision (the user, 2026-09-28): no live updates on
  Flutter web. Dio's browser adapter reads a response whole, so the
  stream's changes would arrive only when it ends. The app ships to phones,
  which stream; Chrome was only for testing.

## 2026-09-28 — S10 push, the app's side, before Firebase

- The user split S10: the server part to the backend session (it waits for
  the user's own go), the app part here. `PushService` with `NoPush` until
  Firebase; the phone's address sent at sign-in, on a language change and
  on a new token, taken back at sign-out; a tapped push opens what its
  notification opens (one shared `notificationDestination`). Contract in
  BACKEND_READY.md, "Push notifications, the app's side". Tested with a
  stand-in push service, each part red-checked.

## 2026-09-29 — M9: the screens no round walked, against the real server

- `test/live/m9_walk_test.dart` (report / removed / coupons / buynow). The
  store's coupons (unique code, steps of 250, at most 90%, pause, edit,
  delete; the discount on the store's own goods; the days read as Baghdad
  days), reporting a review (Saba removed 72, dismissed 62's report), and
  Buy now (the one item, no coupon, the cart left alone, the first-order
  limit, idempotent) all passed, in Arabic too.
- `test/widget/report_dialog_test.dart`: the report sheet had no test; a
  reason is required, the words go with it, in both languages.
- Step 0 (removing the email-verification leftovers) not done, by the
  user's decision: it reaches the account screen, sign-in and the
  deep-link tests, and nothing can reach the screen today.

## 2026-09-29 — the release switch (BUGS 211)

- The app talks to the real server unless a build asks for the demo; photo
  upload and live updates ask `isDemoMode`; README's builds corrected;
  `test/core/release_switch_test.dart` (red-checked three ways). Full suite
  715 passed.


## 2026-09-29 — deleting a store's account (BUGS 212), Terms and Privacy (183)

- Apple 5.1.1(v) and Google Play: every account deletes itself in the app;
  closing is not enough. The user approved deletion by request. The
  server's part went to the backend session. The user is deciding two
  things with it: whether the final bill is due at once or at the month's
  end, and whether product photos stay.
- App: a store's Edit Profile has "Delete account" in place of "Close my
  store". It asks first (how long, the SMS, what is kept), then shows what
  the deletion waits for and "Keep my account". The dashboard says "Closed:
  account being deleted" and hides the switch. `StoreDeletion` replaces
  `StoreClosing`; the repository has `deletion`, `requestDeletion` and
  `cancelDeletion`, and `close()` is gone (the M2 and M6 walks use
  `setOpen(false)`). The demo server answers the routes and refuses to open
  a store that is being deleted.
- The Terms and Privacy give the way in the app, not "ask Support", and say
  what is kept, in both languages. The Arabic "صبا" is now "سبأ" (213).
- The public deletion page Google wants is recorded for when there is a
  domain: BACKEND_READY.md, "Deleting a store's account".
- Tests: `account_screens_test` "a store asks for its account to be
  deleted" (red four ways); `before_part4_fixes_test` "the Terms and
  Privacy send deletion to the app" (en, ar; red on the old wording).

## 2026-09-29 — store deletion against the real server; the Brands filter (BUGS 214)

- The user's decisions (backend 9d255d9):
  - the last bill is the month's own bill, due when the month ends;
  - never paid means never deleted, with no write-off;
  - product photos stay; the logo and banner go;
  - the SMS is the only notice.
- Wording changed to match:
  - Delete account now says the last bill is for the month of the last
    delivery, due when that month ends.
  - Privacy now says a deleted store's messages keep its name, and its page,
    products and replies to reviews go.
- `test/live/store_deletion_walk_test.dart` (phases ask and deleted) passed
  on :3000 with a new test store, "Deletion Walk 30038" (id 16, waiting for
  approval, never sold):
  - asked: closed at once; asking twice kept the first day; the account
    carries the date;
  - the switch was refused (409) in en and ar;
  - cancelled: still closed, and the switch worked again;
  - asked again, then deleted by the hourly step;
  - the SMS went in both languages;
  - the old session opened the app signed out;
  - sign-in with the number: "no account, sign up";
  - the store page: 404. A waiting store has no page before deletion either;
    the backend's tester checks an approved store (id 17).
- The M2 store (id 15) stopped the walk before any write: it sold this
  month.
- The filter shows Brands only when there are some (BUGS 214, the user's
  go through the backend session); red-checked on the old sheet.

## 2026-09-30 — a deletion Saba starts reaches the store's screens (BUGS 215)

- The backend's tester found that after Saba started a store's deletion from
  the admin web, Flutter web kept stale screens. The web build has no live
  updates (the user's decision), so a reload is expected there.
- On phones, the STORE notice already reloads the account (proved in M8 for
  a suspension), which brings the deletion card and the dashboard's line.
- The dashboard's open/closed and the deletion's figures did not reload
  with the account. Both now reload when the account's deletion date
  changes.
- Test: `store_is_told_test` "a deletion asked from elsewhere reaches the
  store's screens"; red with either reload removed.

## 2026-09-30 — photos went blank in Chrome (BUGS 216)

- The user, in Chrome: product 60's photos showed, then went blank a
  moment later, and were black in the Edit product form.
- The server sent all three photos (200, CORS right), and they are ordinary
  JPEGs.
- The console (read over Chrome's debug port) had dozens of "WebGL:
  texImage2D: no image". The engine's `ImageElementImageSource` empties its
  `<img>` when released, and the package's default web path uses one.
- `AppNetworkImage` now uses `ImageRenderMethodForWeb.HttpGet`.
  `cached_network_image_platform_interface` is named in pubspec for the
  enum; it was already installed with the package.
- Seen after a restart: the photo stays, with no warnings.
- `test/widget/network_image_web_test.dart` checks the setting; it fails
  without it.

## 2026-09-30 — the reviewer's list, the app's part

- Item 8: `report_dialog.dart` differed only in its line endings, so it was
  restored.
- Item 6 (2ad7182): the store deletion message and card say an unpaid bill
  stops it.
- Item 7 (e7e9a87): a build that isn't debug or the demo, and has no
  API_BASE_URL, refuses to start.
- Item 1, stock (BUGS 217):
  - `stockBefore` is sent for the product and for each option the form
    loaded.
  - The options editor keeps each row's id.
  - A 409 is said, and the product is read again.
  - The demo server mirrors the rule (`_savedStocks`).
- Tests: `product_stock_save_test.dart` has three tests, red five ways.
  `test/live/stock_save_walk_test.dart` passed on :3000 and left the stock
  as it found it.
- Item 5 (c31e68a, BUGS 218): the user chose to remove Account's "Verify
  your email" card.
- Backend 2af9579 (54ff3c4): an approved product's form says what sends it
  back to review. Stock-only saves kept M3 Phone approved on :3000. The
  server fixed the Arabic text and brand being cleared (9e47be1).
- Item 3, report and block (BUGS 219):
  - the flag on the product and store pages, the chat menu, and the blocked
    line;
  - `reportToSaba` and `sendReport` in report_dialog.dart;
  - the demo server mirrors it: `_report`, and a block per side on `_Chat`.
- Tests: `report_and_block_test.dart` has four tests, red seven ways.
  `test/live/report_block_walk_test.dart` passed on :3000.

## 2026-10-01 — push through Firebase (the reviewer's item 4, BUGS 220)

- `firebase_core` 4.15.0 and `firebase_messaging` 16.7.0.
- `core/push/firebase_push.dart`:
  - `FirebasePush` gives the token, its refreshes, the permission request
    and taps, including the push that opened the app, handed over once;
  - `startPush()` returns `NoPush` on the web and desktop, and when Firebase
    cannot start (no config files).
- `main.dart` uses `NoPush` in the demo, and `startPush()` otherwise.
- `PushTap.fromData` reads the server's data.
- Android:
  - Google's plugin (4.5.0) is applied only when `app/google-services.json`
    exists;
  - `MainActivity` makes the `saba_default` channel, which the manifest names
    as the default;
  - the channel's name is in both strings.xml files.
- iOS:
  - `Runner.entitlements` (`aps-environment`) and the remote-notification
    background mode;
  - the deployment target went from 13.0 to 15.0, because Firebase's
    packages declare 15.0. Flutter raises its generated Swift package to the
    project's target.
- Checked:
  - Gradle configures without the file;
  - with a stand-in file, the debug build's dry run includes
    `processDebugGoogleServices`. The stand-in was removed. No APK was built.
- Tests:
  - `test/core/push_start_test.dart` has three tests, red three ways;
  - `flutter analyze` finds no issues;
  - the full suite: 734 passed and 37 skipped. The one failure was a test
    that fails on the 1st of each month, fixed next (BUGS 221).
- Not seen on a phone: that needs the Firebase files and a device.

## 2026-10-01 — a test that failed on the 1st of each month (BUGS 221)

- "The demo store keeps its own figures" (`signup_pipeline_test`) checked
  this month's revenue. At 00:17 on 1 October the month had nothing
  delivered yet, which is right.
- The test now sums the dashboard's six months of sales. The demo's history
  fills the three months before, and a new store's six months are empty.
- Checked:
  - green at 00:18 on the 1st, when the old check failed;
  - red when the demo store is taken for a new one (`_isNewStore`), then
    restored.

## 2026-10-01 — Firebase's files in the app, and the app's ID (push)

- The user put Firebase's two files beside the repository. Both were made
  for `com.sabacompany.sabamarketplace`; the app was `com.saba.saba_marketplace`
  (Android) and `com.saba.sabaMarketplace` (iOS). The user chose the Firebase
  ID for the app, since it can never change once published. They also chose
  to commit the two files, which Firebase treats as public IDs.
- Android: `applicationId` is the new ID. The namespace (the code's package)
  stays. `google-services.json` is in `android/app/`.
- iOS: the bundle ID in the Xcode project (Runner and RunnerTests).
  `GoogleService-Info.plist` is in `ios/Runner/`, added to the Runner group
  and its Resources phase, as Xcode would.
- Checked:
  - Gradle's `processDebugGoogleServices` passed and made Firebase's values.
    It fails when no client matches the package. No APK was built.
  - iOS was not built (no Mac).
- Docs: mobile/README (push, the launch checklist), DEPLOYMENT (1, 5.2 and
  5.4, which now also say the App ID needs Push Notifications),
  PROJECT-STATUS and BACKEND_READY.
- Gradle warns that `firebase_core` applies the Kotlin Gradle plugin, which
  a future Flutter will refuse. Nothing to do until `firebase_core` updates.
- Left: Apple's push key in Firebase and Push Notifications on the App ID
  (iPhones). A real push test needs the app built on a phone.

## 2026-10-01 — four fixes the user listed (the app's part)

- #1, "Report on a store owner's own store page": not reproduced. The store
  page hides Report and Message when `isMyStoreProvider` says the store is
  the reader's own, the same check the product page uses. The call site
  passes `onReport` unconditionally, but the header hides it. The account's
  store id and the page's id are the same on the server (`users.ts`).
  `report_and_block_test` "a store does not report its own product or store"
  already covers it: it went red with the check broken, then was restored.
  No change.
- #2: DEPLOYMENT §3.4 now checks the database with `VERIFY_IDENTITY`, as
  the API connects (Node checks the host name), so a certificate that
  doesn't name the private host fails there, not at the API's start.
- #3 (coupon and stock lock order) and #4 (paging `/admin/reports`) are
  server code: sent to the backend session, and #4's page to the web
  session.

## 2026-10-01 — the app follows Saba's admin pages for brands, categories and banners

From the backend session's brief (the user asked for the admin pages; the
server runs on :3000).

- Store's product form:
  - A brand box: as the store types, it offers the brands from
    `GET /merchants/me/brands` whose name holds the text, in either
    language.
    - Picking one sends `brandId`; another name is sent as `brandName`.
    - A box left alone sends neither, so the brand stays; an emptied box
      sends `brandId: null`.
  - A product in a category Saba hid shows it by name (`categoryName`) and
    keeps it. A 422 on `categoryId` shows under the field.
- Shopper:
  - Home's banners open their link (product, store or category); a banner
    with none stays a picture. Title and subtitle may be missing. The mapper
    read flat keys the server never sent, so no link could work.
  - With no banner section, Home already left no gap.
  - Browse's chips show the picture Saba uploads, with the icon until it
    loads.
  - The category tree is read again when the store's product form opens,
    on Browse's pull and when the app is reopened (BUGS 222). The form
    reads the store's brands again too.
  - The brands filter reads Saba's brands again when it opens. They were
    kept for the session too.
  - These are read again, not auto-disposed: an auto-disposed provider
    left Riverpod's dispose timer pending in tests that swap containers.
  - Brand names already come in the reader's language from the server.
- The demo server mirrors all of it:
  - `/merchants/me/brands`;
  - brand saves: a name matches whatever its case, in either language; a new
    one waits for Saba's check and stays off `/brands`;
  - hidden categories (tests set them; the demo has no admin);
  - one linked banner ("Home and kitchen" opens its category);
  - `categoryName` on the store's own product.
- Checked on :3000, read only, as the M2 test store:
  - `/merchants/me/brands` is `[{id, name, nameAr}]`;
  - product 57 has `brand: null`, `categoryId` 8 and `categoryName`
    Smartphones;
  - banners carry `link`;
  - `/categories` names come in the reader's language.
- Tests:
  - `admin_pages_follow_test.dart` has nine tests, red ten ways: each brand
    rule; the hidden category shown, refused, and read again by the form;
    Browse on reopening; the banner tap and its mapper.
  - `home_promises_test` asserted that no banner ever opens. It now checks
    the rule the user approved: a linked banner opens, and one with no
    link, or a web address, stays a picture.
  - `demo_state_saved_test`: the demo saves the brands stores typed.
  - The full suite: 744 passed, 37 skipped; `flutter analyze` is clean.

## 2026-10-01 — the brand box against the real server (the backend's walk)

- `test/live/brand_walk_test.dart` passed on :3000, using the app's own save
  and Saba's admin calls as the dev admin. Product 58, named in the brief,
  had been deleted by its store, so the walk added a waiting product of its
  own to M2 (61, "Brand Walk Case") and deleted it at the end:
  - a checked brand picked from the list (Atlas) was saved by its id, and
    the product stayed PENDING;
  - "Walk Brand 01" typed: the product shows it, Saba lists it waiting
    (id 8), and the admin product view marks it `isNew`;
  - "walk brand 01": same id, and no second brand;
  - box emptied: no brand;
  - Saba deleted brand 8 (`moveTo=none`, 200); the store deleted 61.
- End state, checked separately: M2 shows only 57 (APPROVED, no brand), the
  brands are the five checked ones, and 61 is a 404. No app change.
- The hidden-category case was skipped at the backend's request: hiding a
  category changes the shop for everyone. The server's tests cover it.

## 2026-10-01 — the final review: Terms, review reports, privacy, the email link

- Terms (Apple 1.2; BUGS 223): a new section, "Reviews, messages and
  reports", in English and Arabic: zero tolerance for objectionable content
  and abusive users, reports acted on quickly, abusive accounts removed. The
  way to Delete account now names My profile for a store owner.
- Review reports (BUGS 224): a guest signs in first, as for products, stores
  and chats. A store may report a review now, its own store's too (backend
  c0c9ee6); the app already offered it.
- Privacy (BUGS 225): the app's page is `backend/public/privacy.html` word
  for word, in both languages, made from it rather than typed:
  - its `{{…}}` blanks are kept, so DEPLOYMENT §6's fill-in must cover
    `legal_screen.dart` too (asked of the backend);
  - the Arabic WhatsApp number is held left to right, as the page's
    `dir="ltr"` holds it;
  - the date line says 1 October 2026.
- The email link (BUGS 226): the /verify-email route, its screen, the two
  server calls, the demo's answer and eight strings are gone; the link goes
  Home, as any address the app does not have. Sign-up no longer says
  "Verification email sent.".
- Tests:
  - `legal_pages_test` (new, 4): the privacy page against the web page, and
    the Terms' three sentences, each in both languages;
  - `report_and_block_test` +2: a guest's review report goes to sign-in; a
    store reports a review of its own store;
  - `deep_link_navigation_test`: the email link goes Home; the link tests
    use `/search?q=` now;
  - the fakes, lists and comments that named the email check.
  - Seven breaks all went red.
  - The full suite: 746 passed, 38 skipped; `flutter analyze` is clean;
    931 keys.

## 2026-10-01 — the product form: one width for every box

- "Price and stock" is one column, as the rest of the form: Price and
  Original price sat side by side at half width, and Stock under them at
  full width (BUGS 227). The price's helper line now fits on one line.
- The whole form was checked, also in pictures (design shots, en and ar):
  every other box was already full width, and the photo tiles share one
  size. An option's card keeps price and stock side by side: two equal
  boxes, so a long list of options stays short.
- Seen on the way: the options hint promised each variant "its own SKU",
  and the form has no SKU box (BUGS 228). Fixed in both languages.
- Test: `product_form_widths_test` (en, ar): every box in a new product's
  form has one width. On the old layout it read 345 and 166.5.
- The full suite: 748 passed, 38 skipped; `flutter analyze` is clean.

## 2026-10-01 — SMS checks can be switched off, and verify at next sign-in

- The backend added a server setting, PHONE_VERIFICATION (on by default), so
  Saba pays for no SMS at launch; the app follows either way with no release.
- Sign-up: `otp/send {SIGN_UP}` may now answer with a `verificationToken`
  (and `expiresInSeconds: 0`), meaning no code was sent. The number step then
  skips the code screen and goes straight to the details form with that token
  as `phoneVerificationToken`. When the token is absent, the code screen, as
  before. Password reset is unchanged: it always sends a code.
- Verify at next sign-in: `login` can answer 403 PHONE_NOT_VERIFIED for an
  account whose number was never checked (it signed up while checks were
  off). The app sends it to a new screen, `VerifyPhoneScreen`, which sends a
  `VERIFY_PHONE` code and signs in again with it; a wrong or expired code
  comes back on the `code` field. The number and password ride in `extra`,
  never a URL. New failure `PhoneNotVerifiedFailure` (403, code
  PHONE_NOT_VERIFIED) in the error mapper.
- The code boxes are now a shared widget, `OtpCodeField`, used by the sign-up
  code screen and the verify screen; `DemoCodeNote` moved with it.
- Demo server mirrors all of it: a `@visibleForTesting phoneChecks` flag
  (default on), the token on a checks-off sign-up, an unverified set for
  accounts made while off, and the 403 / code-check on login.
- Tests: `phone_verification_test` (4): checks-off skips the code screen,
  checks-on shows it, and verify-at-sign-in lets a right code in and refuses
  a wrong one. Four breaks went red. Strings +3 (934 keys), analyze clean.

## 2026-10-03 — photos in chats, both ways

- A photo button by the message box (gallery or camera), shrunk by the app's
  own MediaPicker to 1600px at quality 82, as product photos; the server
  strips the GPS. Shopper to store and store to shopper, photos only.
- A photo shows in the thread and opens full size with pinch-to-zoom; a
  signed link that has expired (404) reloads the thread once for a fresh one.
- The chat list says "Photo" where a photo is the last message. A removed
  photo shows "Photo deleted" (its sender's account went) or "Photo removed
  by Saba", no image. Blocked chats refuse a photo (409), same as a message.
- Message gained photoUrl and photoRemoved; Conversation gained
  lastMessageIsPhoto. The repo posts multipart `file` to
  /messages/conversations/:id/photos; in the demo it keeps the picture as a
  data URL (no file server), as product photos do.
- Privacy page already carried the three new sentences (10c5282).
- Tests: `chat_photos_test` (2): a photo sent shows in the thread, opens the
  viewer, and reads "Photo" in the list; a removed photo leaves the right
  line. Four breaks went red. Strings +4 (938 keys), analyze clean.

## 2026-10-03 — chat photos walked against the real server

- `test/live/photo_walk_test.dart` passed on :3000 (backend bdfea4f): as the
  shopper Amina, a real PNG sent to her chat with the M2 store came back with
  an empty body, isPhoto true, and a signed photoUrl; the link fetched with no
  auth returned HTTP 200 image/png; the thread read the same photoUrl back and
  the conversation card read lastMessageIsPhoto true, lastMessage null; a
  text/plain file was refused 422 on the file field. The link is http on the
  local dev server (https in production); the app loads whatever URL it is
  given. LIVE-only, skipped in the normal suite.
