# Saba — bug list

Audit of 2026-09-22 at commit `9ffe972` ("backup before bug audit"). No code was changed.

**How it was checked:** by reading the code and tracing each flow from the screen to the demo server. None of these bugs has been seen running yet. The tests didn't catch them because each test starts a fresh app for every account.

🔴 Critical: breaks the app or would look very bad in a client demo · 🟠 Important: wrong behaviour, but the app works · 🟡 Small: design or text

---

## 🔴 Critical

### 1. ~~There is no admin panel~~ — **RESOLVED**: the admin web panel (`website/`) is the real admin. The in-app demo admin stays until the backend (145).
- **Where:** the whole app. `UserRole.admin` exists (`features/auth/domain/entities.dart`), but there is no admin screen, route or demo account. `_redirect` in `core/router/app_router.dart` treats every non-store account as a shopper.
- **What happens:** nothing can be shown for admin. An ADMIN account would land on the shopper's Home. The admin's jobs (approving stores and products, setting banners, editing the rules pages) can't be done anywhere; see bugs 5 and 6.
- **What should happen:** an admin panel, either the planned web panel or admin screens in the app, and a demo admin account.
- **Fix affects:** admin, plus the store side, which waits for approvals.

### 2. Switching stores on one phone shows the previous store's data — **FIXED (step 1)**
- **Where:** `features/merchant/presentation/merchant_providers.dart`: `merchantDashboardProvider`, `merchantProductsProvider`, `merchantProductCountsProvider`, `merchantInventoryProvider`, `merchantOrdersProvider`, `merchantOrderCountsProvider`, `merchantAnalyticsProvider`, `sabaBillsProvider`. Only `merchantCouponsProvider` follows the signed-in account.
- **What happens:**
  1. Sign in as Omar (Nova) and open the dashboard.
  2. Sign out, then sign in as Layla (Atlas).
  3. Layla sees Nova's dashboard, orders, products, analytics and bill until she pulls to refresh.

  Also: a shopper places an order, then the store signs in on the same phone. The store's Orders list, if it was opened earlier, doesn't show the new order.
- **What should happen:** every store screen shows only the signed-in store's data, fresh after each sign-in.
- **Fix affects:** merchant.

### 3. Switching shoppers on one phone shows the previous shopper's lists — **FIXED (step 1)**
- **Where:** `orderListProvider` (`features/orders/presentation/orders_providers.dart`), `notificationListProvider` (`features/notifications/…/notifications_providers.dart`), `returnListProvider` (`features/returns/…/returns_providers.dart`) and `supportTicketsProvider` (`features/support/…/support_providers.dart`). None of them is tied to who is signed in, and sign-out doesn't clear them.
- **What happens:**
  1. Amina opens My orders or Notifications.
  2. She signs out, and a new shopper signs up on the same phone.
  3. The new shopper sees Amina's orders, notifications, returns and support tickets until they pull to refresh.

  The notifications list is also used by stores, so a store can see a shopper's notifications the same way.
- **What should happen:** these lists are cleared at sign-out and loaded again for the new account.
- **Fix affects:** shopper and merchant.

### 4. A new order says "Confirmed" and "Payment recorded" before the store has confirmed it — **FIXED (step 2)**
- **Where:** `core/mock/mock_api_interceptor.dart` `_createOrder`. The order is saved with status `CONFIRMED` (line ~2387), and its timeline has "Order received" plus a `CONFIRMED` entry "Payment recorded" (lines ~2441–2451). The store's copy is saved as `NEW` (line ~2479).
- **What happens:**
  - Right after checkout, the shopper sees "Confirmed" while the store still sees "New" with its "Confirm (call first)" button.
  - The history says "Payment recorded" for a cash order nobody has paid.
  - When the store does confirm, a second "Confirmed" is added to the shopper's history.
- **What should happen:** the order is "Pending" (waiting for the store) until the store confirms. There is no payment line until the driver collects the cash, and only one "Confirmed", written when the store confirms.
- **Fix affects:** shopper and merchant (the same order has to read the same on both sides). Only the demo server changes; the rule is part of the future backend's contract.

---

## 🟠 Important

### 5. A new store stays "under review" forever — **FIXED (step 4)**
- **Where:** `mock_api_interceptor.dart`: sign-up calls `_openStore(body, status: 'PENDING')` (line ~806), and nothing ever sets the status to `APPROVED`.
- **What happens:** a store that signs up in the demo can never be approved, so the full "new store opens and sells" story can't be shown.
- **What should happen:** an admin approves it (bug 1). Until an admin panel exists, the demo needs some way to approve.
- **Fix affects:** merchant and admin.

### 6. A store's new product never reaches shoppers — **FIXED (step 4)**
- **Where:** `mock_api_interceptor.dart`. New products go into `_addedProducts` (line ~3411), which only the store's own screens read (`_findProduct`). The shopper catalogue, search and Home read only the built-in products (`_filteredSummaries` uses `MockData.productSummaries`). The comment says new products "wait for the catalogue team's review", and nobody can do that review.
- **What happens:** the store adds a product, but shoppers never see it anywhere. `_addedProducts` also belongs to the store's account, so the product disappears from the demo server's view when another account signs in.
- **What should happen:** after approval (or at once in the demo), the product appears in search, categories, the store page and Home.
- **Fix affects:** merchant, shopper and admin.

### 7. The bell's orange dot on Home never updates — **FIXED (step 3)**
- **Where:** `unreadNotificationCountProvider` (`features/notifications/…/notifications_providers.dart:137`) is loaded once and never refreshed. Nothing in the app reloads it; it is only used by the bell on Home (`home_screen.dart:212`).
- **What happens:** read every notification and the dot stays. The store ships an order and no dot appears, until the next sign-in.
- **What should happen:** the dot follows the real unread count: after reading, after a new notification, and when returning to Home.
- **Fix affects:** shopper.

### 8. A new order doesn't show in My orders if the list was opened earlier — **FIXED (step 3)**
- **Where:** `CheckoutController.placeOrder` (`features/checkout/presentation/checkout_providers.dart:387`) empties the cart and reloads the coupons, but not `orderListProvider`. The only place that reloads it is the cancel action in `order_detail_screen.dart:724`.
- **What happens:** open My orders, then buy something. My orders still shows the old list until you pull to refresh.
- **What should happen:** the new order is at the top straight away.
- **Fix affects:** shopper.

### 9. ~~After a language switch, open screens keep the old language's words~~ — **FIXED (text pass)**
- **Where:** every screen that shows the server's words, except Home (fixed in Part B).
- **What happens:** switch the language while, say, search results are open. Product names, section titles and statuses from the server stay in the old language until the screen is opened again.
- **What should happen:** everything on screen follows the new language.
- **Fix affects:** shopper and merchant.
- *Noted in Part B. The user decided not to fix it now.*

---

## 🟡 Small

### 10. ~~Arabic count grammar~~ — **FIXED (text pass)**
- **Where:** `itemsCount`, `cartSummary`, `itemsLabel` and `productsFound` in `core/localization/app_localizations.dart` (generated from `tool/generate_localizations.dart`), using `item` = منتج and `itemsWord` = منتجات.
- **What happens:**
  - Home says "40 منتج".
  - The cart says "2 منتجات" and "11 منتجات".
- **What should happen:** Arabic number grammar: 1 منتج, 2 منتجان, 3–10 منتجات, 11 and above منتجًا (for example "40 منتجًا").
- **Fix affects:** shopper (cart, Home) and possibly merchant (item counts on orders).

### 11. ~~English words from the demo server in Arabic mode~~ — **FIXED (text pass)**
- **Where:** `mock_api_interceptor.dart`:
  - ~~order history notes "Order received" and "Payment recorded"~~ — fixed in step 2: an order's history line is now written in the language the app asked for, and the false payment line is gone. **Still open:** "Return requested" (~2814);
  - chat titles "Saba Support" and "Store" (`_storeFace`, ~4542–4552);
  - the demo address label "Home" (~165);
  - the demo product questions and answers (~3054–3071).
- **What happens:** these show in English in Arabic mode.
- **What should happen:** Arabic words in Arabic mode, as the rest of the demo server already does. The questions and answers are shoppers' own words, so they may stay as written.
- **Fix affects:** shopper and merchant.

### 12. Recent searches are shared by every account on the phone — **FIXED (step 1)**
- **Where:** `core/storage/app_preferences.dart` (`recentSearches`, one list per phone).
- **What happens:** the next person to sign in on the phone sees the last person's searches.
- **What should happen:** clear them at sign-out, or keep one list per account.
- **Fix affects:** shopper.

### 13. ~~An old, unused Flutter project sits beside the app~~ — **FIXED (removed 2026-09-24, its own commit)**
- **Where:** `saba_test/lib/main.dart`, `saba_test/pubspec.yaml`, and `android/`, `ios/`, `web/` etc. at the root. The real app is `saba_test/mobile/`.
- **What happens:** nothing in the app, but opening or running the wrong project is easy.
- **What should happen:** remove it, or label it (only with the user's go).
- **Fix affects:** none (the project files).

---

## Found by the user on the screens (2026-09-22)

Listed here, not fixed, except where marked. Priorities are mine.

### Cart and checkout
14. ~~🟠 A store that doesn't deliver to the shopper's city is only said in tiny text in the cart; the shopper finds out at checkout, at a button that won't work.~~ — **FIXED (round 3)**. The store's card opens with the reason and "Change address" / "Save for later".
15. ~~🔴 The total counts products that cannot be delivered.~~ — **FIXED (money round)**
16. ~~🟡 The total is shown twice, with a big empty gap above the checkout button.~~ — **FIXED (round 3)**. The total is on the bar by the button only; the empty gap is gone.
17. ~~🟠 The warning box at checkout mixes two different things: the cash limit and "this store doesn't deliver here".~~ — **FIXED (round 3)**. A store that does not deliver is said on its own row; each warning has its own box.
18. ~~🟠 The greyed-out "تأكيد الطلب" button doesn't say why it can't be pressed.~~ — **FIXED (round 3)**. The grey button says why, under it.
19. ~~🟡 A store that can't deliver shows "—" as its delivery price.~~ — **FIXED (round 3)**. It says "No delivery here".

### Add address
20. ~~🟠 With +964 chosen, the number still starts with 0.~~ — **FIXED (money round)**
21. 🟡 The delivery instructions box is a different colour from the other fields.
22. ~~🟡 The "تعيين كافتراضي" switch looks switched off / disabled.~~ — **FIXED (round 3)**. A first address starts as the default; an off switch is a solid grey track.

### Orders and invoice
23. ~~🟠 The raw code "DELIVERY_TOO_SLOW" is shown instead of Arabic words.~~ — **FIXED (text pass)**
24. 🟡 ~~The order history says "Order received" and "Payment recorded" in English~~ — **FIXED (step 2)**, together with bugs 4 and the order-history part of 11.
25. ~~🟠 The invoice's status doesn't follow the order's real status.~~ — **FIXED (money round)**
26. ~~🟡 "(اختياري)" appears twice in the cancel sheet, and Cancel works without choosing a reason.~~ — **FIXED**: the double "(اختياري)" in the text pass; a cancel with no reason, or one not on the list, is now refused by the server as well as the sheet.
27. ~~🟠 A cancelled order still shows its total, with nothing saying that nothing will be paid.~~ — **FIXED (money round)**

### Everywhere
28. ~~🟡 Numbers are mixed: Arabic digits for dates, Western digits for prices.~~ — **FIXED (text pass)**
29. ~~🟡 Arabic number grammar: "2 منتجات من 2 متاجر" should be "منتجان من متجرين" (same as bug 10).~~ — **FIXED (text pass)**
30. ~~🟡 Category chips mix Arabic and English in Arabic mode.~~ — **FIXED (text pass)**
31. ~~🟠 The last row of the product grid is hidden behind the floating bottom bar.~~ — **FIXED (round 3)**. Scroll views clear the bar and the phone's gesture area.
32. ~~🟡 After a language switch, other screens keep the old language until reopened (same as bug 9).~~ — **FIXED (text pass)**
33. 🟡 The banner title is clipped on a 320 px phone at the largest text size — **already FIXED**, before the "Part B done - stable" commit.

## Found while working (2026-09-23)

### 34. ~~🟡 `PACKED` is a step nobody can reach~~ — **FIXED**. The word is gone from the app, the demo server and the tests: the shopper's status list, the store's "Preparing" tab, the labels and the strings.
- **Where:** `MerchantOrderStatus.workflow` in `merchant_widgets.dart` no longer has it, but `mock_api_interceptor.dart` (`_stage`) and `OrderStatus` still accept it, and `next()` sends a `PACKED` order to `SHIPPED`.
- **What happens:** nothing today: no button writes `PACKED`, and since 2026-09-23 no demo order starts in it either (the seed used to). The app still reads it - the labels, the "Preparing" tab, `next()` - because a real backend might send it. That reading is the dead weight left.
- **What should happen:** your decision later - either bring the step back on the store's screens, or drop the word everywhere.
- **Fix affects:** merchant and shopper.

## Found by the user on the screens (2026-09-23)

Seen in Chrome, second test session. Not fixed; for later rounds.

35. ~~🟠 Product options stay English in Arabic mode ("Black · 128GB") in the cart and on orders, and the demo store's own orders show English product names in Arabic.~~ — **FIXED (text pass)**
36. ~~🟡 Wrong plural: "Delivered sales (1 orders)".~~ — **FIXED (text pass)**
37. ~~🟡 "Email (optional) (Optional)" - the word is there twice in sign-up.~~ — **FIXED (text pass)**
38. ~~🟠 Text cut off at phone width: "Save for la…", "Pay on d…", "at least one num…".~~ — **FIXED (text pass)**
39. ~~🟡 The welcome screen talks about drivers, but v1 has no driver role.~~ — **FIXED (round 3)**. The drivers note is gone from the role screen.
40. ~~🟡 Mixed digits in Arabic: dates ٢٢ سبتمبر ٢٠٢٦ against money 129,000 (same family as 28).~~ — **FIXED (text pass)**
41. ~~🟠 The demo shopper's notifications talk about parcels shipped and orders confirmed that she does not have.~~ — **FIXED (round 3)**. Her seeded inbox has no orders or parcels in it; a tap opens at once.
42. ~~🟠 Both stores show the same customer question ("Sara Ahmed: Is this phone in stock in blue?"), which reads like shared data.~~ — **removed in v1**: questions and answers are gone from the product page.
43. ~~🔴 No product photos anywhere~~ — **FIXED (demo photos)**: every product, category and store has a picture.
44. ~~🟡 The browser console shows 26 errors, all of them the missing demo images~~ — **FIXED** with 43: every image the demo names exists, and a test checks it.
45. ~~🟠 Arabic digits typed into the phone field are dropped.~~ — **FIXED (money round)**
46. ~~🔴 A product the store hid is still on sale to shoppers.~~ — **FIXED (money round)**
47. ~~🟠 A wrong "−20%" badge on a 129,000 option.~~ — **FIXED (money round)**
48. ~~🟠 "refunds the customer" is said on a cash order, where the store hands the cash back.~~ — **FIXED (round 3)**. "Nothing was paid, so nothing is handed back."
49. ~~🟡 Order age badges read "19m" and "1ي".~~ — **FIXED (text pass)**

## Found by the user on the screens (2026-09-23, step 2 test session)

Seen in Chrome. Not fixed; for later rounds.

50. ~~🟠 Product pages show English in Arabic mode: "Ships in 2 business days", "12 months manufacturer warranty", and the whole description paragraph. Only the return-policy card is in Arabic. (The spec labels Brand / Model / Warranty are **removed in v1** with the specifications table; the rest is still open.)~~ — **FIXED (text pass)**
51. ~~🟠 A history note keeps the language it was written in, so an order placed in English still says "Order received" after switching to Arabic. To make it follow the reader, the demo server should keep a code and the app should translate it (the same fix as bug 9).~~ — **FIXED (text pass)**
52. ~~🟡 "إعادة الإرسال بعد 58s" - the English "s" for seconds on the Arabic OTP screen.~~ — **FIXED (text pass)**
53. ~~🟡 Two names for one thing: the favourites screen is titled المفضلة but its empty text says قائمة أمنياتك.~~ — **FIXED (text pass)**
54. ~~🟡 The store's order details print "SKU SKU-p-1"~~ — **FIXED (Part B)**: the SKU is no longer shown.
55. ~~🟡 Invoice headings do not match each other: a lowercase "items" next to "Totals".~~ — **FIXED (text pass)**
56. ~~🟠 Delivered orders stay in the store's "Shipped" tab, and its count does not drop (it stayed at 3 after a delivery).~~ — **FIXED (round 3)**. Delivered has its own tab.
57. ~~🟡 A product page shows "منتجات ذات صلة" and "منتجات مشابهة" with the same two products.~~ — **removed in v1**: one rail is left, "related products".
58. ~~🟡 "Warranty 12" on the spec row, with no unit.~~ — **removed in v1** with the specifications table.
59. ~~🟡 Text still cut off at phone width: "الدفع عند ا…", "Pay on del…", "Save for la…" (same family as 38).~~ — **FIXED (text pass)**

## Found by the user on the screens (2026-09-23, step 3 test session)

60. ~~🟠 Pull-to-refresh cannot be used with a mouse on Flutter web, and these screens have no refresh button, so on a laptop there is no manual refresh at all. It works with a finger on a phone. A refresh button would help web demos.~~ — **FIXED (round 3)**. Every paged list has a Refresh button on the web.
61. ~~🟡 The cancel dialog cuts off "Tell us more (optio…" and shows "(Optional)" twice (same family as 26 and 38).~~ — **FIXED (text pass)**
62. ~~🟡 A seeded demo notification reads "Your order is confirmed · The store is getting it ready" with no order number, right next to the real one for SB-100026, so it reads like a duplicate (same family as 41).~~ — **FIXED (round 3, with 41)**. A shopper's seeded inbox has no order notifications.
63. ~~🟠 A cancelled order's history shows the raw code CHANGED_MIND (confirmed again with a screenshot; same family as 23).~~ — **FIXED (text pass)**

## Fixed along the way

- 🔴 **Saba's own staff could never sign in** (found by the tester, 2026-09-23).
  `login_screen.dart` signed an admin straight back out with "admin accounts
  sign in through the web admin panel" - written before there was an admin
  screen, and left in place when step 4 built one. So `/admin`, approve and
  reject, and "Start the demo again" were all unreachable in the running app.
  Every admin test called the sign-in controller directly and never touched
  the screen, so nothing caught it. The guard is gone and the end-to-end
  sign-in test now signs in **through the form** as a shopper, a store and an
  admin.

- 🟡 **The store dashboard's order count changed by itself** (7, then 8, with nothing happening): an order placed at exactly "now" was counted as "not placed yet", and the demo store's newest sample order is placed at "now". Fixed in step 1 **because it was blocking**: it made the step's own test fail at random. `mock_api_interceptor.dart`, the dashboard's `placedIn`.

## Found by the tester on the screens (2026-09-23, version 1 session)

Not fixed; listed for a later round. The admin sign-in bug found in the same
session is fixed - see "Fixed along the way".

64. ~~🟠 Saving a product leaves you on the form~~ — **FIXED (Part B)**, as 76.
65. ~~🔴 An unknown product id (`/#/product/p1`) draws a blank product page priced in dollars ("0.00 $") with an Add to cart button, instead of a not-found screen. It is the only place in the app that shows USD.~~ — **FIXED (money round)**
66. ~~🟠 Checkout counts lines, not units: two of one phone reads "1 item" in the Delivery block, right above "2 × Nova X5 Smartphone".~~ — **FIXED (money round)**
67. ~~🟡 The order card cuts the payment line off at "Pay on d…" (same family as 38 and 59).~~ — **FIXED (text pass)**

## The tester's version 1 session (2026-09-23)

68. ~~🟠 **Two delivery prices for one purchase**~~ — **FIXED**. The page
    answered for the city the shopper *browses* from and checkout for the
    city their *address* is in. Both lines now read `deliveryCityProvider`:
    the default address's governorate, falling back to the browsing city for
    someone with no address saved.
69. ~~🟠 **A rejected store is still told it is awaiting approval**~~ —
    **FIXED**. The banner reads the store's real status: a rejected store
    gets a red banner saying Saba did not approve it, and a button to
    support. Saba still records no rejection *reason* — that is part of the
    real admin panel (`ADMIN_REQUIREMENTS.md` §5).
70. ~~🟠 **An approved store is never told**~~ — **FIXED**. The notice is
    addressed to `store:<id>`, the key a store's inbox actually reads, as the
    product approval always was.
71. ~~🟡 The admin queue names a store by its phone number, not its city.~~ — **FIXED (text pass)**
72. ~~🟡 "Rejected" is announced in the green success snackbar, the same as "Approved".~~ — **FIXED (text pass)**
73. ~~🟡 The reset confirm button is cut off at "Start the de…" (same family as 38, 59 and 61).~~ — **FIXED (text pass)**
74. ~~🟡 Search says "1 results" (same family as 10 and 36).~~ — **FIXED (text pass)**
75. ~~🟠 Nova's store inbox carries shopper notifications~~ — **FIXED
    (Part B)**: a store's seeded notifications are a store's (a new order,
    a product approved, a customer's message, this month's bill).
76. ~~🟠 Saving a product leaves you on the form~~ — **FIXED (Part B)**:
    saving goes to the products list. (64 is the same bug, fixed with it.)

## The tester's walk of Part A (2026-09-23)

Fixed in Part B, because they touch the same screens:

77. ~~🔴 The inventory sheet **added** instead of **set**~~ — **FIXED**. It
    asks for the new quantity and now sends the difference; stock can be
    brought down.
78. ~~🔴 Buying never took stock off an option~~ — **FIXED**. An order
    line did not record which option was bought, so the purchase came off
    the product's own count, which nothing reads once a product has
    options. A shelf of 3 could take orders for ever.
79. ~~🔴 A deleted account's number still signed in~~ — **FIXED**. The
    number is released, and signing in with a deleted account is refused.
80. ~~🟠 The card row was still in checkout~~ — **FIXED**. Part A removed
    the card page but not the demo server's "coming soon" card entry.
81. ~~🟠 A demo product sent for approval never reached the admin~~ —
    **FIXED**. It is in the queue, and approving or rejecting it works.
82. ~~🟠 The shelf kept a stale total after an option's stock changed~~
    — **FIXED**. The inventory sheet refreshes the shelf too.
83. ~~🟠 One product page gave three delivery speeds~~ — **FIXED**. The
    seller card's line - the store's own terms for the city the parcel goes
    to - is the only one. The product's "3 to 5 days", its "Ships in 2
    business days" and the store's free-text shipping words are gone.

Recorded, not fixed:

84. ~~🟠 Removed addresses (`/#/compare`, `/#/account/sessions`,
    `/#/account/password`, `/#/forgot-password`) show "You do not have
    permission to do that." on a screen with no way back and no app bar.
    A removed route should land on Home.~~ — **FIXED (round 3)**. An unknown address goes Home (after sign-in, if signed out).
85. ~~🟡 The rating sheet never names the store being rated.~~ — **FIXED (round 3)**. The store is named from the first question; the name was empty.
86. ~~🟡 Account's "Security and settings" section now holds a single row.~~ — **FIXED (round 3)**. Settings sits under "You".

## The tester's walk of Part B (2026-09-23)

Fixed before the client demo:

87. ~~🟠 "Only a few left" showed in the owner's own-store preview~~ —
    **FIXED**. The card keeps it for shoppers and drops it in the preview.
88. ~~🟠 "Set your delivery fee" was ticked on a brand-new store~~ —
    **FIXED**. The demo server gave every new store 5,000 IQD to its own
    city, which the owner never chose. A new store now delivers nowhere
    until its owner sets it, so the step stays open. Its products say
    "Doesn't deliver" to shoppers until then, which is true.
89. ~~🟡 A new store's preview said "No products found"~~ — **FIXED**. With
    products waiting, it says "Waiting for approval: your products show
    here once Saba approves them."
90. ~~🟡 One state, two names~~ — **FIXED**. Account's store badge said
    "Pending"; it now says "Waiting for approval" like everywhere else.
91. ~~🟡 "Add your first product" twice on the dashboard~~ — **FIXED**. The
    checklist keeps it. "Needs you today" is hidden for a store with no
    products and nothing else to do, so it doesn't say "Nothing needs you"
    under a checklist.

Recorded, not fixed:

92. ~~🟠 The shopper's product page lets you pick more than the stock until
    the page refreshes. The server has the right number.~~ — **FIXED (round 3)**. The product is fetched on each visit; the quantity never exceeds the stock.
93. 🟡 The own-store preview's product list would not scroll in Chrome,
    with the mouse wheel or by dragging. May be Chrome-only; needs a phone
    check.

## Found by the admin web session (2026-09-23)

94. ~~🟠 Every seeded store order charged a flat 5,000 IQD delivery, and some
    of Atlas's went to Erbil, where Atlas does not deliver~~ — **FIXED**.
    Each store's past orders go to its own city and one other it serves,
    and charge its own fee for that city.
96. ~~🟠 The admin web's Finance page bills each store for three past months,
    but the store's "What you owe Saba" said "No past months yet": the app's
    seed had only today's orders~~ — **FIXED**. The app now has the web's
    delivered orders from three months back (same numbers, dates, shoppers,
    items and fees), so the months and bills match. The app also has the
    web's refunded returns on that history, taken off the bill as the web
    does (Atlas, last month). The history buys only products that were on
    sale, and walks each store's whole shelf. The web needs the same change
    to match (see WORK-LOG, 2026-09-24).

## The money round (2026-09-24)

- **15:** a store that does not deliver to the address is left out of the
  total and says "Not in your total" with the reason.
- **46:** one rule decides what is for sale: approved and not hidden. The
  shop, search, categories, Home, related products, the wishlist, the cart
  and checkout follow it, and so does the store's shelf. Nova keeps one
  waiting, one draft, one rejected and one hidden product, Atlas one
  waiting, one draft and one rejected (`MockData.seededStatus`): 49 of the
  56 demo products are on sale.
- **65:** an unknown or unlisted product shows "This product is not
  available" with a way Home. The fallback currency is IQD.
- **66:** every count is of units.
- **47:** an option shows its own discount, on the page and in the cart.
- **25, 27:** a cancelled or refused order's payment is "cancelled", on the
  invoice too, and the order says nothing will be taken.
- **45:** Arabic and Persian digits become 0-9 in every field, and the phone
  check accepts them.
- **20:** after +964 a leading 0 is dropped, and nothing fills one in.

## The tester's check of the money round (2026-09-24)

Fixed now: checkout's "Cash to each driver" still listed a store that cannot
deliver, so the cash added up to more than the total (part of 15); and a store
had no way to hide its own product (part of 46) - there is now an eye on each
approved row of its shelf.

97. ~~🟡 Picking 256GB without a colour leaves the base price showing, with no
    hint to pick a colour until Add to cart. The colour swatches sit on the
    photo with no label.~~ — **FIXED (part 4)**. Each option has its name
    above it, the swatches left the photo, and "Please choose the product
    options first." shows until all are chosen.
98. ~~🟡 On a hidden product the store's preview bar says "This is how buyers
    see your store", though buyers cannot see it. Tapping a row in the
    store's product list does nothing.~~ — **FIXED**. On any product buyers
    cannot see, the bar says "Only you can see this product. Buyers
    can't."; a tap on a row opens it to edit, as the pencil does.
99. ~~🟠 A cancelled invoice has the Cancelled badge but not the "none of this
    will be charged" line, and still shows the total in full.~~ — **FIXED**.
    The line is there (and in the copied text), and the total is crossed
    out and grey.
100. ~~🟠 An unknown address (e.g. `/#/browse`) says "You do not have permission
    to do that." (same cause as 84).~~ — **FIXED (round 3)**. With 84.
101. ~~🟡 A brand-new account is greeted with "Welcome back".~~ — **FIXED**. Home says "Hello"; sign-in keeps "Welcome back".
102. ~~🟡 The first sign-up screen says "sellers and drivers reach you", and the
    role screen says "Drivers do not sign up here", though stores deliver
    their own orders in v1 (with 39).~~ — **FIXED (round 3)**. "Your number is how stores reach you"; the drivers note is gone.
103. ~~🟡 Demo data: "Lumen Book 14" (a laptop) has phone options (128GB/256GB,
    Black/Silver/Blue) and "Atlas" as its brand. "Nova Tab 11" shows a
    phone photo.~~ — **FIXED (132)**. Lumen brand, laptop options; photos
    are one per category, by the user's call.

## Round 3 (2026-09-24)

Fixed: 14, 16, 17, 18, 19, 22, 31, 39, 41, 48, 56, 60, 84, 85, 86, 92, and
100 and 102 with them. Not fixed: 21 - the delivery instructions box is the
same widget, fill and card as every other field on the form, and nothing in
the code makes it a different colour. The user's decisions (2026-09-24): 21
stays open until a phone check, with a screenshot if it still looks
different; 93 is left for a phone check; 34 is fixed; 13 is removed, on
its own commit.

## What the admin web needs from the app (2026-09-24, recorded, not fixed)

The user decides when.

104. ~~🟡 Home's store rail shows every store; it should show the admin's
     featured list.~~ — **FIXED (D28, a5334e8)**. Featured stores only; no
     rail when none.
105. ~~🟡 A support ticket does not record who opened it, a shopper or a store.~~
     — **FIXED**. `openedBy` `{kind, name, phone, storeId?}`, as §3.8.
106. ~~🟡 An order does not link to its customer by id.~~ — **FIXED**.
     `customerId` on the shopper's order and each store's copy; seeded
     orders use the web's `cu-` ids.

## The tester's walk of the auth screens (2026-09-24)

107. ~~🔴 Signing up with a number that already had an account took the
     account over: "Omar Second" on Ali First's number, and sign-in opened
     Omar for good~~ — **FIXED**. The number step says the number has an
     account and offers "Sign in instead", before any code is sent; and the
     server refuses to register over a number that has an account.
     "Sign in instead" now carries the number to the sign-in screen, so it
     is not typed twice.
108. 🔴 **Backend.** The code step can be skipped: the profile form trusts
     whatever token is in the link, and a made-up link showed "Number
     verified" for a number that never got a code. The real backend must
     check the verification token on register. Cannot be fixed in the app.
     **Also (the tester, 2026-09-24):** a hand-edited link with the number
     written as 07512223344 or +964 751 222 3344 and a fake code token made a
     SECOND account on the same number, where +9647512223344 was refused.
     It does not take the account over - sign-in still opens the original -
     but it leaves duplicate accounts nobody can reach. The backend must
     (1) verify the code token and (2) normalise every way of writing a
     number to one form before comparing. The demo server now does the
     second, with the user's go: 0751..., +964 751..., 964..., 00964...,
     spaces and Arabic digits are one number at sign-up, sign-in, the code
     and a reset, so a fake link can no longer make a second account there.
     Checking the token itself stays with the backend.
109. ~~After a wrong code, all six digits had to be deleted by hand~~ —
     **FIXED**. They clear, and the field takes the focus.
110. ~~The demo chips filled "07711234567", a 0 after +964~~ — **FIXED**.
111. ~~"Too short (2)" for a one-letter name~~ — **FIXED**. "Too short. Use
     at least 2 characters." / "قصير جداً. اكتب حرفين على الأقل."
112. ~~In Arabic, "+964" sat to the right of the number and read
     backwards~~ — **FIXED**. It is on the left in both languages.
113. ~~At 320 px the Nova chip was cut to "Nova Elec…"~~ — **FIXED**. The
     demo chips are one under the other.
114. ~~The store step said "Your store is awaiting approval" before the
     store existed~~ — **FIXED**. It says Saba checks the store after
     sign-up.
115. ~~The store's Edit profile labelled the phone "(Optional)" over "You
     sign in with this number"~~ — **FIXED**. A read-only field is never
     marked optional.
116. ~~The welcome (role) screen opened on an empty space~~ — **FIXED**. The
     logo is at the top.
117. ~~Wording~~ — **FIXED**. "أتسوّق" for the shopper; "I have a store" /
     "لدي متجر" for the store, not "merchant"; the phone step's Arabic
     rewritten; "until Saba approves it", not "an administrator"; no
     "Standard SMS rates may apply" (SMS is free to receive in Iraq); no
     drivers wording (with 39, 102).

The account changes, with the user's go (2026-09-24):

118. ~~A new password needed upper and lower case letters and a digit,
     awkward on an Arabic keyboard~~ — **FIXED**. At least 8 characters is
     the rule.
119. ~~No length limit on names: a 140-letter name was accepted and
     squashed unreadably on Home~~ — **FIXED**. A person's name is at most
     50 characters and a store's 40, in every form and on the server; Home
     cuts a name over 24 characters with "…" instead of shrinking it.
120. ~~A second "Nova Electronics" in Baghdad was created with no warning~~
     — **FIXED**. A store name is refused if another store in the same city
     has it, case and spaces aside, at sign-up and on a rename. Other cities
     may reuse it.
121. ~~Email at sign-up, and "Use email instead" at sign-in~~ — **CUT from
     v1**. Accounts are made and signed into by phone. The demo server still
     accepts an email sign-in, for the accounts made before this.
122. ~~No way back in after forgetting a password~~ — **FIXED**. "Forgot
     password?" on sign-in: the number, then the code sent to it with a new
     password. A code is sent only for a number that has an account.
     🔴 **Backend:** the real server must check the code before it changes
     the password (the demo signs in with any password, so it checks the
     code but keeps nothing).
123. ~~A shopper went through a role screen to sign up~~ — **FIXED**.
     "Create account", and a first launch after the language, go straight to
     the shopper's number step, which has the logo, "Open a store on Saba"
     and "Already have an account? Sign in". The role screen's route is
     gone; an old link goes Home. The screen and its strings were deleted
     with the user's go.
124. ~~Store sign-up took two screens and asked for a business address and
     a description~~ — **FIXED**. One screen: the owner's name, the store's
     name and city, the verified number and a password (3 steps in all, not
     4). The business address is now in store settings, beside the
     description.
125. ~~Shipped orders had a tracking number and no driver, though v1 has
     no delivery companies~~ — **FIXED**. The tracking number is gone from
     the app and its seed, and so is the "delivery company" choice when a
     store ships: the store names its own driver, a name and a phone. The
     seeded shipped and delivered orders carry each store's driver, as the
     admin web has them (Nova's Haider Salim, Atlas's Mustafa Adnan, ...).
126. ~~A store could not run a flash sale; Home's rail was any discounted
     product, counting down to midnight~~ — **FIXED**. "Flash sale" on each
     approved product in the store's list: a sale price in 250 IQD steps
     and an end; the row then says "Flash sale until 9:00 PM", and "End sale
     now" ends it. Home's rail is the sales still running, the soonest to end
     first, counting down to that one, and Home is asked for again at zero.
     An ended sale's price is the one from before, everywhere.
127. ~~A store's own approved product could never reach the flash sale~~ —
     **FIXED**. Home read the demo's products alone, where the product list
     also reads the ones stores added and Saba approved. Home's store cards
     counted the same way and now count them too.
128. ~~A deleted product could stay in the flash sale~~ — **already fixed**
     on the phone by 46 (4f1a829): the rail goes through the one "listed"
     rule, which leaves out deleted and hidden products. A test now holds
     it: a hidden or deleted product on a sale leaves Home.
129. ~~Phone numbers in two formats on one order: the driver
     "+9647705550311", the customer "+964 780 555 0117"~~ — **FIXED**. The
     app showed each number as it arrived. Every number on every screen now
     goes through one function, IraqiPhone.display: +964 770 555 0311,
     whatever form it came in (orders, addresses, checkout, the account,
     the store's order page and its call sheet, the code screens).
130. ~~"nova electronics " in Baghdad was refused, but the tester did not
     see why~~ — **FIXED**. The refusal was right and word for word the one
     "Nova Electronics" gets (now tested); it was written under the store
     name field, scrolled out of the form's window above "Create account".
     Every form now brings the first field with a problem into view, for its
     own checks and for the server's.
131. ~~On the smallest phone (320x568) the sign-up fields scrolled in a
     window 64 px tall, and in none with the keyboard up~~ — **FIXED**, with
     the user's go. The step's title now scrolls away with the fields; the
     top bar (back, progress, language) and the button stay pinned. With a
     keyboard up on that phone the store's sign-up and the shopper's profile
     step went from 0 px to 180 px to type in. Every other form was
     measured the same way and has room (the address form, profile and a
     new support ticket 163 px, the store's forms 244 px, sign-in 284 px); a
     test now holds all ten at 120 px or more.
132. ~~Demo products that made no sense (the tester)~~ — **FIXED**. The
     first twelve were worked out by formula: the 65W charger cost 519,000
     IQD and the phone 49,000; brands rotated, so the Lumen laptop was
     "Atlas" and Nova's air purifier "Kite"; the first four all had a
     phone's colours and sizes, laptops too; and Atlas Home sold phones and
     laptops while Nova sold Atlas's goods. Now the twelve are written out
     (price, brand, options), Atlas Home sells home appliances and Nova
     electronics. The northern stores' three misfits went too: Mosul
     Appliances' laptop stand, Erbil Cool Air's phone charger, a speaker
     under Headphones. Photos: one per category, as a placeholder, by the
     user's call - three rotated per category put an air fryer on a fridge
     and a keyboard on a charger. demo_catalogue_test holds it all.
133. ~~The store read "Out of stock" for Kite headphones that shoppers saw in
     stock, on the flash sale and in their carts~~ — **FIXED**. The shelf set
     its third product's stock to none so the "Out" tab had something in
     it; the shopper was never told. One stock now, the same on both sides;
     the "Out" tabs keep what really is out (Nova's p-41, Atlas's p-6).
134. ~~During a sale the sheet said "The price now is 61,250 IQD", the price
     before the sale~~ — **FIXED**. "The normal price is ...", and the
     refusal says "lower than the normal price".
135. ~~"End sale now" ended it at once~~ — **FIXED**. It asks first: every
     shopper's price changes.
136. ~~A hidden product showed "Flash sale" and took a sale~~ — **FIXED**.
     No button on a hidden product, and the server refuses one (409); a sale
     already running keeps its chip, and can only be ended.
137. ~~The seller card on a product page falls apart on a 320 px phone at
     the largest text size: the Message button takes the row, and "Sold by"
     and "Delivers to Baghdad" stand one letter per line~~ — **FIXED
     (part 4)**. Message has its own line under the store, and delivery its
     own block.
138. ~~Muted text was 2.9:1 on white (3.9:1 in dark mode), below the 4.5:1
     words need, and it carries words people read: the store under each
     product's name, crossed-out prices, dates, step counts~~ — **FIXED**.
     #626D79 in light mode (the admin web's value), #8795A6 in dark; the
     contrast tests now include it on a card, the page and a field.
139. ~~A store's new logo did not show after "Store updated"~~ — **FIXED**.
     The demo backend kept each store twice, as the demo began it and as
     its owner last saved it; saving wrote the second and almost every
     reply read the first. The settings reply did not even carry the logo,
     and the field opened empty. Now every reply reads the store as saved
     (`store_read_once_test.dart`), and the field opens with the logo.
140. ~~A store that moved city stayed under its old city on Home, and a
     store opened in the app showed under no city~~ — **FIXED** by 139:
     Home's city filter reads the store's city as saved.
141. ~~Settings looked empty: its lines started 50 px in, where an icon
     would be, and the options were in the hint grey~~ — **FIXED**. Lines
     start at the words; every option is in the text colour.
142. ~~The product page's discount was a bar across the screen~~ —
     **FIXED**. The badge centred its words with a Container alignment,
     which grows to the width offered; now sized to its words, a pill
     beside the price.
143. ~~A rejected product was only found by scrolling the shelf, and its
     edit form did not say why Saba said no~~ — **FIXED**. "Needs you
     today" counts them; the form shows Saba's reason at the top.
144. ~~The shopper's product reply had no category name~~ — **FIXED**, for
     the category pill.

## The tester's walk of the redesign (2026-09-25)

146. ~~🟠 The product page said 6,000 IQD to Baghdad for Nova, moved to
     Basra; the cart charged 3,000~~ — **FIXED**. The cart's fee read the
     store's first city (the read-twice root of 139); it reads the city as
     saved.
147. ~~🟠 "Did your order arrive?" came back after it was answered, and the
     order page asked too~~ — **FIXED**. One answer settles both: "Yes, it
     arrived" marks every delivered store received, stars or not, and an
     arrival answered on the order page is not asked again. Could not be
     reproduced with one single-store order; these were the two gaps.
148. ~~🟠 The dashboard said 10 orders and -12%, Analytics 3 and +40%, for
     the same month~~ — **FIXED**. One calculation: delivered orders,
     against the same days of last month.
149. ~~🟠 The city chip did not filter the flash sale~~ — **FIXED**.
150. 🟡 A kitchen photo on air conditioners, a kettle and a mixer; a
     security camera on a mirrorless one. **Kept, by decision
     (2026-09-25)**: one shared photo per category on every product. A
     shared photo reads as placeholder data, an empty one as broken (30 of
     56 had none when the photo went only where it fitted). They go when
     real stores upload their own.
151. ~~🟡 A store that cannot deliver said so only far down; Buy now
     worked~~ — **FIXED**: a red fact pill at the top, and both buttons off
     with the reason.
152. ~~🟡 Every product had a 12-month warranty, a 9,000 IQD case too~~ —
     **FIXED**: none for cases or anything under 20,000 IQD, 6 months for
     chargers and accessories.
153. ~~🟡 Colour circles had no names~~ — **FIXED**: named under each.
154. ~~🟡 The logo tile said "You have reached the maximum number of
     files", cut off~~ — **FIXED**: a full slot shows no add tile.
155. ~~🟡 Email on both account screens and in the Terms~~ — **FIXED**: the
     phone instead; Edit profile's email card and the rule pages' email
     lines are gone too.
156. ~~🟡 Chart labels "D-0", "W1" in Latin in Arabic; the dashboard chart one
     bar~~ — **FIXED**: points carry their start and the app names them;
     the dashboard shows six months.
157. ~~🟡 The rating sheet kept "Did your order arrive?" after yes~~ —
     **FIXED**: "How was your order?".
158. ~~🟡 The language screen's tagline sat at the start under a centred
     name~~ — **FIXED**.
159. ~~🟡 At 320 px and the largest text, "Headph / ones", and a tiny name in
     Home's header~~ — **FIXED**: words shrink rather than break; the
     name goes under the icons when they leave it no room.

## The tester's money round (2026-09-25)

160. ~~🔴 One item returned three times, refunded twice: Nova handed back
     290,000 on one 145,000 sale, and stock rose by 2~~ — **FIXED**. An
     order line takes one return, for at most what was bought; "Request a
     return" goes once it has one (`returns_money_test.dart`).
161. ~~🔴 A refund ignored the coupon: 145,000 back on headphones bought at
     130,500 with NOVA10~~ — **FIXED**. Each order line keeps
     `paidUnitPrice`, its price after the store's coupon; a return gives
     that back, and the bill takes that off.
162. ~~🟠 Checkout had no coupon line~~ — **FIXED**: it read `discount`, and
     the coupon is `couponDiscount`.
163. ~~🟠 Changing an option (M to L) gave it the old option's stock~~ —
     **FIXED**: a new option gets a new id.
164. ~~🟠 A store's own product showed the out-of-town fee and no city~~ —
     **FIXED**: it carries its store's city.
165. ~~🟠 A two-store invoice named one seller~~ — **FIXED**: each line
     names its store; an unknown order is "not found", not a blank invoice
     dated 1970.
166. ~~🟠 A coupon use was counted at 0 off; the chip stayed green under the
     minimum~~ — **FIXED**: amber with its minimum, and no use counted.
167. ~~🟠 "What you owe Saba" and the order page kept old numbers~~ —
     **FIXED**: a store's order step refreshes the bill and Analytics; a
     return closes its line at once.
168. ~~🟠 #/register/merchant opened bare skipped the code~~ — **FIXED in the
     app**: both sign-up forms need the number and its token, or go to the
     number step. 🔴 **Backend**, with 108: refuse a sign-up without a
     valid verification token.
169. ~~🟡 Return answers on one tap; no reason to decline~~ — **FIXED**:
     approve and "cash handed back" ask first; a decline picks a reason the
     shopper reads in their language, and the server refuses one without.
170. ~~🟡 A declined return showed a refund amount; the return page showed
     "DAMAGED" and three steps that never happen; the form did not say the
     refund~~ — **FIXED**.
171. ~~🟡 "not valid or has expired" for a coupon not started; no minimum on
     the chips~~ — **FIXED**: "This code starts on Sep 28"; "10% off · On
     orders over 100,000 IQD".
172. ~~🟡 A two-store order stayed "Pending" after one store delivered~~ —
     **FIXED**: confirmed once any store has taken it; each store's step
     is on its part.
173. ~~🟡 The home-city chip in delivery settings, dark on dark~~ — **FIXED**.
174. ~~🟡 "Did your order arrive?" still came back~~ — **FIXED**, the real
     cause this time: the shell asked each time it was built, and it is
     built again on the way back from any page outside it. Once an app
     opening per account now (reproduced first in `rate_store_test`).
     "14 orders vs 4" was a build from before 148; the Delivered button is
     there on a shipped order's page (now checked by a test).

## The tester's check of the money round (2026-09-25)

175. ~~🟠 Refunds of 130,565 and 170,185: no note is under 250~~ — **FIXED**.
     What was paid is rounded down to 250 as every cash amount is, so the
     refund, the store's "cash handed back" and the 8% bill are in steps.
176. ~~🟠 The arrival sheet still came back: "Yes, it arrived" saved
     nothing until stars were sent~~ — **FIXED**. Saved when tapped. The
     order page's "No" wrapped "N / o": even halves, one line each.
177. ~~🟡 "Return details" and "My products" stock only after a reload~~ —
     **FIXED**.
178. ~~🟡 The language screen lost its centring (the "start edge" rule was
     for the sign-in screens only), and five notes elsewhere with it~~ —
     **FIXED**: the language screen, and the notes under checkout's and
     the cart's buttons and the product form's, centred again.
179. ~~🟡 "Already have an account? Sign in" was small grey text~~ —
     **FIXED**: one centred link, set apart, 16 px and a full tap target,
     on the number step, sign-in and sign-up.
180. 🟠 **The share button copied a link that goes nowhere**
     (`https://saba.app/product/<id>`, a domain this project never set up). **Hidden,
     by decision (2026-09-25)**: better no button than a broken one. It
     comes back when the domain, the public product page and the deep link
     files (`assetlinks.json`, `apple-app-site-association`) are in place;
     what each needs is in BACKEND_READY.md, "Sharing a product".
181. ~~🟡 On the order page, "Yes, I got it" shrank to a tiny font beside a
     full-size "No"~~ — **FIXED**. The driver and the question were squeezed
     into the column beside the store's "Message" button. They now sit under
     the store's row, across the card, as even full-size halves.
182. ~~🟡 The driver's phone broke in two, "+964 770 555 / 9988", beside Call~~
     — **FIXED**: the number has its own line under the driver's name.
183. ~~🟡 The Terms and the app disagree on closing an account~~ —
     **FIXED** (2026-09-29): the Terms said "ask Support to close your
     account" and Privacy "ask Support to delete your account", which Apple
     does not accept, while the app deletes from its own button. Both now
     give the way in the app (Account, your name, Delete account), in both
     languages. Privacy has its own "Deleting your account": a shopper at
     once, a store once its orders, returns and last bill are finished, with
     an SMS when done. It says what goes, and what stays and why: orders,
     invoices, returns and bills, with the delivery details and the store's
     name.
184. ~~🟠 "Save for later" on the only item showed "Your cart is empty" and
     the item looked lost~~ — **FIXED**. It was saved: the demo backend kept
     the line and sent it as saved, and it is kept between openings. But the
     cart screen showed the empty state whenever nothing was left to buy,
     before its "Saved for later" section. Now, with only saved items, the
     cart shows them with "Move to cart"; the empty state is only for a cart
     with nothing saved either.

## The ten things (2026-09-26)

185. ~~🟠 A first launch went straight into sign-up~~ — **FIXED**: language,
     then sign-in, with "Create an account" under the button. "Sign in
     instead" on the number step now fills the number into that sign-in
     screen: the screen was reused and kept the old number.
186. ~~🟠 Related products ignored the category (headphones: an air fryer, a
     laptop)~~ — **FIXED**: only the same category.
187. ~~🟡 Empty fields gave no example~~ — **FIXED**: every empty field on
     both sides shows "e.g. …", money written "12,500". A number typed with
     commas ("12,250", the price form's own example) was refused as "not a
     number" on the product price, stock, variant, restock and inventory
     fields, and ignored in the price filter: one reading of a typed number
     now takes the commas everywhere. The store settings' photo label ran
     6.5 px off a 320 px phone in Arabic.
188. ~~🟡 Auth screens: the logo centred over words at the start edge;
     "Send code" against the field~~ — **FIXED**: the logo at the start
     edge on every auth screen, 40 px above "Send code".
189. ~~🟠 One timeline for a two-store order~~ — **FIXED**: a box per store,
     with its badge, a bar of four steps, its driver or its expected
     arrival, and its items; the order's badge follows the slowest store
     and says so.
190. ~~🟡 The return page left out an item not yet delivered, silently~~ —
     **FIXED**: "Not on this return", each item with why.
191. ~~🟡 The city chips sat under the search bar~~ — **FIXED**: right above
     "All products", filtering that grid only; the flash sale shows every
     city's again.
192. ~~🟠 "In stock only" kept a product sold out since the app opened~~ —
     **FIXED**: it reads the stock as it is now. The price range, "On sale"
     and the brand chips filtered correctly.
193. ~~🟡 The web's Refresh button~~ — **REMOVED**. A list reads itself
     again on coming back to it, or to the app; the pull stays. Product
     grids keep their place instead.
194. ~~🟠 Notifications that do not fire, or lead nowhere~~ — **FIXED**
     (2026-09-26):
     - Every notification opens what it is about: a store's new order,
       cancelled order, return request and "not received" its order; a
       return's answer the return; a product's answer or take-down the
       product's form; a store's answer its dashboard; a chat message the
       chat.
     - A chat message notifies the other side, both ways, and lights the
       bell.
     - The driver's number reads +964 770 111 2222.
     - Still open, for the backend: Support cannot reply in the demo, so a
       Support reply sends nothing (BACKEND_READY.md).

## The tester's check of the ten (2026-09-26)

195. ~~🟠 The order's badge said "Confirmed" while Atlas was still pending~~
     — **FIXED**: it follows the slowest store exactly, and the line under
     it says so: "The order shows the step of the store furthest behind".
196. ~~🟡 The store's Stock box held a real "0": 1,200 typed read
     "01,200"~~ — **FIXED**: empty with its example, on a new product and a
     new option row.
197. ~~🟡 Home's card said "available" after the last one was bought~~ —
     **FIXED**: product lists reload when an order changes stock, and search
     results and cards with options read the stock as it is now.
198. ~~🟡 The chat's "About order SB-100015:" could be split by a tap~~ —
     **FIXED**: it sits above the box, leads the first message, and a cross
     leaves it off.
199. ~~🟡 The demo's own notifications showed the last sign-in's time; Nova's
     list had "Nova Electronics answered you"~~ — **FIXED**: stamped once,
     when the demo starts; a store is told of a customer's message.
200. **Store order status NEW became PENDING** (BACKEND_PLAN.md 8.4), as the
     real server says it; the words stay "New" / "جديد". The saved demo's
     version went up, so a phone holding NEW orders starts fresh.

201. ~~🔴 Resend on the SMS code step skipped the sign-up check~~ — **FIXED**
     (from the backend session): it asked for a code without saying it was
     for sign-up, so a number that already had an account, refused on the
     first send, got a code on a resend. Resend now asks as sign-up too.

## Found by the backend session (2026-09-26)

202. 🟡 **Dead fields the app still declares.** Recorded, not fixed; for the
     mobile session.
     - `ProductDraft` in `features/merchant/domain/entities.dart` declares
       `barcode`, `lowStockThreshold` and `returnPolicy` (lines 494–527) and
       writes them in `toJson` (543, 546, 548). The product form never sets
       them (`merchant_product_form_screen.dart:244`), nor does any test, so
       nothing is sent. The three fields and their three `toJson` lines can
       go.
     - `merchant_store_settings_screen.dart` reads a `returnPolicy` (lines 37,
       50, 80) that the server never sends: returns are Saba's fixed 7 days,
       the same for every store.
     - **Keep** `lowStockThreshold` on the shelf and inventory rows
       (`entities.dart` 43–130, `merchant_providers.dart` 77, 99): the server
       sends 5 for the low-stock badge.

202. ~~🟠 The coupon edit form showed the day before, and saving moved the
     coupon a day earlier~~ — **FIXED** (from the backend session): the
     server's UTC days are read as this phone's days (`_dayOf` uses
     `.toLocal()`); Baghdad's midnight is 21:00 UTC the day before.

203. ~~🟠 A product refused on its photos or its options saved nothing and
     said nothing~~ — **FIXED** (M3, against the real server): the form
     shows the server's refusal only on its six fields; "Use at most 10"
     (images) or "Two options have the same choices" (variants) had nowhere
     to go. A refusal on anything else is now said in a message.

204. ~~🟡 The shelf offered a stock stepper and Restock on a product sold in
     options, and the server refused them~~ — **FIXED** (M3 step 8, from the
     backend session): shelf rows carry `hasVariants` (server 00de581, and
     the demo's rows); on those rows the stepper and Restock are left out.
     Their stock is set per option, in Inventory or the product form.

205. ~~🟠 A parcel refused at the door still asked for its cash~~ — **FIXED**
     (M4 step 10, against the real server): the shopper's order page read
     "Cash to the driver: 263,000 IQD" and the store's "Collect in cash" on a
     part refused at the door (the store's also on a cancelled one). The
     server keeps the part's amount; nothing is paid. Both now leave it out.

206. ~~🟡 The demo let something that had run out into the cart~~ —
     **FIXED** (M4, with the server's 2ef1cd4): the add is refused, "This
     has run out, so it can't go in the cart.", as the real server does.

207. ~~🟡 A store could not find its cancelled, declined or refused orders
     again~~ — **FIXED** (M4 step 11): the orders screen had four tabs, none
     for them. A "Cancelled" tab (cancelled and refused) now lists them, with
     no "Collect in cash" on their cards.

208. ~~🟠 A declined return still showed its refund~~ — **FIXED** (M5, against
     the real server): the returns list read "Refund amount 260,000 IQD" in
     green, and the return's page kept each line's amount, on a return the
     store had declined. The server sends what the return was for; nothing
     comes back. Both leave it out.

209. ~~🟠 "What you owe Saba" hid the paid day and a month's returns~~ —
     **FIXED** (M6, against the real server): a paid month said "Paid" (the
     server sends the day, `paidAt`), and a past month's line left out the
     cash handed back on returns, so Atlas's August read 1,005,000 in sales
     and 68,750 owed, not 8% of it. It now says "Paid Aug 4" and "Cash
     handed back on returns −145,000 IQD". Also: the dashboard's Arabic "1
     product not approved" line no longer puts a feminine pronoun after a
     masculine noun ("دون موافقة").

210. ~~🟠 A coupon refused on its limit or minimum saved nothing and said
     nothing~~ — **FIXED** (M9, against the real server): the coupon form
     showed the server's refusal only on its code, amount and dates, and a
     refusal on a field skips the message, so "at least 1" or "not below its
     uses" on the usage limit went unseen. The limit and minimum boxes now
     show the server's words, and a refusal on anything else is said in a
     message, as the product form does (BUGS 203).

211. ~~🔴 A release built from the README talked to the fake server~~ —
     **FIXED** (the tester, 2026-09-29): `USE_MOCK_DATA` defaulted to on and
     the README's release commands never turned it off. And two places read
     the raw switch instead of demo mode, so even `APP_ENV=production` kept
     a product photo on the phone as a `data:` address (the server refused
     the save) and turned live updates off. Now, as the web does: the real
     server unless a build asks for the demo (`USE_MOCK_DATA=true`); every
     place asks `isDemoMode`; the README's release commands set
     `APP_ENV=production` and the server's address. `flutter test` keeps
     the demo (`test/flutter_test_config.dart`).

212. ~~🔴 A store owner could not delete their account~~ — **FIXED in the
     app** (the tester, 2026-09-29; the server's part is with the backend
     session): Apple 5.1.1(v) and Google Play require deletion in the app
     for every account and refuse closing instead, and "Close my store" only
     closed. A store now asks from Edit Profile: it closes at once, the card
     says what the deletion waits for, and the owner can take it back. The
     dashboard has no open switch while it waits, and the server refuses to
     open the store. Design and contract: BACKEND_READY.md, "Deleting a
     store's account".
213. ~~🟡 The Arabic "Owed to Saba" spelled Saba "صبا"~~ — **FIXED**: "سبأ",
     as everywhere else in the app (it was the only one).
214. ~~🟡 The filter showed "Brands" over nothing~~ — **FIXED** (the backend
     session, the user's go): only the demo has brands; the store's product
     form sends none, so the live shop has none and the filter's Brands
     heading stood over an empty space. It shows only when there is a brand;
     brands added later bring it back.
215. ~~🟡 A deletion Saba started left the dashboard saying "Open for
     orders"~~ — **FIXED** (the backend's tester, admin web): the owner's app
     hears Saba's notice and reads the account again. That brought the
     deletion card and the dashboard's line, but not the dashboard's
     open/closed or the deletion's figures, which would be stale after a
     cancel. Both now read again when the account's deletion date changes.
     Flutter web has no live updates (known, the user's decision): a reload
     shows it there.
216. ~~🟠 In Chrome, photos showed and then went blank a moment later (black
     in the product form)~~ — **FIXED** (the user): the console filled with
     "WebGL: texImage2D: no image". The image package drew each picture from
     an `<img>` element, and Flutter's engine empties the element
     (`src = ''`) when one copy of a picture is let go while another is
     still on screen; the next redraw found no image. `AppNetworkImage` now
     has the package fetch the bytes on the web
     (`ImageRenderMethodForWeb.HttpGet`), which decodes a picture nothing
     empties. Phones never used that path. Seen in Chrome: product 60's
     photo stays, and no warning.
217. ~~🔴 Saving a product reset its stock~~ — **FIXED** (the reviewer;
     server cd6228c): every save set the stock again, so what sold while
     the edit form was open came back. The form now sends, with each stock,
     the number it showed (`stockBefore`). Unchanged, the stock stays; when
     the stock moved meanwhile, the save is refused, the form says so and
     shows the product again. And worse: any edit in the options table
     rebuilt its rows without their ids, so the save made every option new,
     deleted the old ones and their stock history. Each row keeps its id
     now. Walked on the real server: the untouched save changed nothing;
     the stale save was refused in both languages; the right one saved;
     the ids never changed.
218. ~~🟡 "Verify your email" could show and led nowhere~~ — **FIXED** (the
     reviewer; the user's decision): the server marks only staff emails as
     verified, and v1 sends no email, so an older account with an email saw
     a card to a screen that cannot work. The card is gone from Account. The
     /verify-email route and its screen stayed (gone since, 226), as do
     sign-in by email and the deep links. Sign-up already had no email box.
219. ~~🔴 No way to report a product, a store or a chat, nor to block anyone~~
     — **FIXED** (the reviewer; Apple 1.2, Google Play; backend 426336e):
     - a shopper's product page and store page have a flag (not on one's
       own);
     - a chat's menu has Report and Block/Unblock, on both sides;
     - a report asks why (the review report's reasons) and thanks;
     - a block stops the writing for both sides and keeps the chat readable;
       the box gives way to a line, with Unblock for the side that blocked;
     - a refusal to send (409) brings the line.
     Walked on the real server; nothing was left blocked.
220. ~~🟠 No push could reach a phone: the app had no Firebase~~ — **FIXED**
     (the reviewer's item 4):
     - Firebase starts where the build has the project's files; without
       them, and on the web, desktop and the demo, the app runs with no
       pushes;
     - a tapped push opens what its notification opens, also the one that
       opened a closed app (handed over once);
     - Android makes the `saba_default` channel the server names; iOS has
       the push entitlement and the background mode;
     - iOS 15.0 is now the minimum (13.0 before): Firebase requires it.
     Not seen on a phone yet: that needs the Firebase files, the Apple push
     key and a device (mobile/README.md, "Push (Firebase)").
221. ~~🟡 A test failed on the 1st of every month~~ — **FIXED** (the suite,
     1 October, 00:17): "the demo store keeps its own figures" checked this
     month's revenue. On the 1st, before anything is delivered, that is
     rightly nothing, as on the real server. The test now checks the
     dashboard's six months of sales, which a new store doesn't have. The
     app and the demo server are unchanged.
222. ~~🟡 A category Saba added, hid or renamed never reached an open app~~
     — **FIXED** (the backend's brief for Saba's categories page): the
     category tree was kept for the whole session, though its comment said
     a pull refreshed it; nothing did. The store's product form now reads
     it again when it opens, and Browse when it is pulled and when the app
     is reopened. Browse's chips show
     the picture Saba uploads. A product already in a hidden category keeps
     it, and the form says which.
223. ~~🔴 The Terms did not say what Apple 1.2 asks of an app with reviews
     and chats~~ — **FIXED** (the final review): a new section, "Reviews,
     messages and reports", in both languages: zero tolerance for
     objectionable content and abusive users, reports acted on quickly,
     abusive accounts removed. The Terms' way to Delete account now names My
     profile for a store owner, as the Privacy policy does.
224. ~~🟠 A guest who reported a review was asked why, then shown the
     server's refusal~~ — **FIXED** (the final review): a guest signs in
     first, as for every other report. A store may report a review now, its
     own store's included (backend c0c9ee6); the app already offered it.
225. ~~🟠 The app's Privacy policy was not the one Saba gives the stores~~ —
     **FIXED** (the final review): it left out OTPIQ, Google Firebase,
     DigitalOcean, the IP address and the phone's notification ID, and said
     a store's replies to reviews are deleted; there are none. It is now
     `backend/public/privacy.html` word for word, in both languages, its
     `{{…}}` blanks included, and a test fails when the two differ.
226. ~~🟡 A saba://verify-email link opened a screen that called a server
     route there is not~~ — **FIXED** (the final review): the route, the
     screen, their two server calls, the demo's answer and eight strings are
     gone; the link goes where any address the app does not have goes. And
     a new shopper was told "Verification email sent." on signing up, though
     Saba sends no email: no more.
227. ~~🟡 Three boxes, two widths, in the product form's "Price and stock"~~
     — **FIXED** (the user): Price and Original price sat side by side at
     half width, and Stock under them at full width. The section is one
     column now, as the rest of the form. The whole form was checked: every
     other box was already full width, the photo tiles share one size, and
     an option's card keeps its price and stock side by side as two equal
     boxes, so a long list of options stays short.
228. ~~🟡 The options hint promised each variant "its own SKU"~~ — **FIXED**
     (seen while checking 227): an option's card has a price and a stock
     box and no SKU box, and the server makes none. It now says each
     combination has its own price and stock, in both languages.

229. ~~🟢 SMS checks can be switched off at sign-up, with no app release~~ —
     **DONE** (the user's call; backend's brief 2026-10-01): a server setting
     (PHONE_VERIFICATION, on by default) so Saba pays for no SMS at launch.
     - Sign-up, checks off: `otp/send` returns a token and no code; the number
       step skips the code screen for the details form.
     - Sign-up, checks on: the code screen, as before.
     - Sign-in: an account whose number was never checked is refused 403
       PHONE_NOT_VERIFIED and sent to a code screen, then signs in with the
       code. New `PhoneNotVerifiedFailure` in the error mapper.
     - Password reset unchanged: always a code.
     - The code boxes are now the shared `OtpCodeField`. Demo server mirrors
       both modes behind `phoneChecks`. Tested both ways; four breaks red.
230. ~~🟢 Photos in chats, both ways~~ — **DONE** (the user's call; backend's
     brief 2026-10-01, server bdfea4f): a photo button by the message box
     (gallery or camera), shrunk to 1600px/q82 by the app's own picker; the
     server strips the GPS. The photo shows in the thread and opens full size
     with zoom; the chat list says "Photo"; a removed one shows "Photo
     deleted" or "Photo removed by Saba". A blocked chat refuses it (409).
     Message gained photoUrl/photoRemoved, Conversation lastMessageIsPhoto;
     the demo keeps the picture as a data URL. Tested; four breaks red.

## For the backend

95. 🟡 The store's product form has one box for the description, the
    warranty and the name in each language it shows. A store editing a
    product in Arabic saves Arabic as the words for both languages (the demo
    server then drops the old Arabic twin). The real product needs a field
    per language, and the form one box per language. Not fixed now, by
    decision.
145. ~~🟡 Delete the demo admin inside the app (0770 999 9999) when the
     backend work starts~~ — **DONE** at M2 (Q12, 2026-09-27): the admin
     screen, its route and "Start the demo again" are gone; an admin signing
     in is told to use the web panel. The demo server still answers the
     web's admin routes, which the tests use to play Saba's part.

## Taken out for version 1 (2026-09-23)

These are not bugs. They were working, half-working or not needed, and they
are gone so version 1 is small enough to finish. Any of them can come back.

**Shopper:** compare, report a product and the ⋮ menu that held them;
questions and answers; product reviews and product ratings (see the version-1
rating section in `PROJECT_MAP.md` - stores are rated instead); the
specifications table; two of the three identical rails ("frequently bought
together" and "similar products"); follow store; notification preferences;
active sessions; recently viewed; the card payment page and the greyed-out
"Card - coming soon" row; product videos.

**Merchant:** the specifications rows and the video field on the product
form. Forgot password went too, on the same reasoning as change password:
demo mode never checks a password at sign-in, so neither could do anything.

## Buttons that lied, now real (2026-09-23)

None of these are open any more. Each answered 200 and changed nothing:

- **Submit for approval** (the ✈ icon) moves a draft or a rejected product to
  waiting, and the row says so.
- **Deleting a demo product** takes it off the shelf and out of the shop.
- **Editing a demo product** keeps the category and the options it was given;
  they used to be accepted and dropped.
- **Adjusting an option's stock** in Inventory saves, and the sheet names the
  option it is changing ("Black · 128GB"), not just the product.
- **Delete account** empties the account and does not give it back at the
  next sign-in.
- **Change password** and **forgot password** were removed instead: demo mode
  accepts any password, so neither could be made true.

## Part B: the merchant side made usable (2026-09-23)

- **Categories:** seven (Phones, Laptops, Headphones, Smartwatches,
  Cameras, Home appliances, Accessories), 56 demo products spread over them
  and all 8 stores, and no invented counts.
- **A merchant's own store** opens as a preview: a "This is how buyers see
  your store" bar, and no cart, quantity, wishlist, share, coupons, Message
  or "only a few left".
- **The dashboard says what is true** - waiting for approval / open / closed
  by you / not approved - and a new store gets a three-step checklist.
- **The product form** asks less (no SKU, barcode, low-stock threshold or
  specifications), keeps the photo, sends one clear action, and goes back to
  the list after saving. Photos are square and capped on pick. The shelf has
  a "Waiting for approval" tab and chip.
- **Store settings and sign-up** lost business type, business address and
  free-text shipping; a store has a logo.

## One stock number (2026-09-23)

A product used to carry a count of its own beside its options' - 12 on the
page while the colours said 5, 4 and 3 - and only the product's own number
ever moved. Now:

- a product **without** options has its own count;
- a product **with** options has no count of its own: each option carries one,
  and the product's is their sum, everywhere it is shown;
- the store's product form hides the stock box once a product has options,
  and says stock is set per option;
- checkout refuses what has run out, and placing an order takes the stock
  from the right option.

**Kept:** the wishlist heart, and share - which now copies the product's name
with its link.

## The text pass (2026-09-23)

- **Counts** go through one helper, `AppLocalizations.counted`: English
  one/other, Arabic's six forms ("منتج واحد", "منتجان", "من متجرين",
  "3 منتجات", "11 منتجًا", "100 منتج"). The noun forms are in the
  translation files.
- **Digits** are Western everywhere: `Formatters` turns the Arabic-Indic
  digits of Flutter's Arabic dates back to 0-9.
- **A language switch** reaches every open screen: the API client, every
  list, the cart and the wishlist follow it.
- **An order's history** is kept as codes ("ORDER_RECEIVED", a cancel or
  decline reason) and said in the reader's language; a store declines with
  a code, not its own words.
- **The demo server** answers in Arabic for any field with an Arabic twin
  (description, warranty, a store's description and address, chat titles,
  the demo address, customers' names), option words ("Black · 128GB"), and
  its error messages.
- **Text** wraps or shrinks instead of being cut: buttons, the cart's row
  buttons, field labels, field errors, the payment line, checkout choices.

## Not checked in this pass

This pass was deliberately short, to save tokens. These areas weren't read in depth and may still hide bugs:
- the maths: cart, coupon, delivery fee and total compared on the shopper and store sides, and rounding to 250;
- coupon rules (minimum order, expiry, pause) against what checkout accepts;
- crash paths in the data mappers, and on empty lists;
- the store's product form with variants, inventory, and the return approve/refund steps;
- sign-up edge cases (wrong or expired code, Arabic digits in phone numbers), and dark mode.
