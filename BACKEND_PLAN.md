# Saba backend: build plan

Written 2026-09-26, before any backend code, for review. The schema is in `DATABASE_DESIGN.md`; what this laptop needs is in `SETUP_CHECKLIST.md`.

**What it serves:** the Flutter app (`mobile/`) and the admin web (`website/`), with no screen changed for the switch except the few listed in §8.3.

**Where the rules come from:** the admin half is `website/API_CONTRACT.md` with `website/PRE_BACKEND_AUDIT.md`. The app half has no contract document: it is the app's demo server, `mobile/lib/core/mock/mock_api_interceptor.dart`, which "is the contract" (`PROJECT_MAP.md` §7). Function names in backticks (`_buildCart`) are its. Rules found only in `BACKEND_READY.md` are marked **(BR)**.

---

## 1. Contents

1. Contents
2. Questions for you, documents that disagree, gaps I filled
3. Stack and libraries
4. Folder structure
5. How a request flows: auth, ownership, transactions, errors, language
6. Every endpoint
7. Build order: vertical slices
8. Switching the app and the web over
9. Things in the front-ends that are awkward to serve
10. Live updates
11. Tests
12. Deployable later without a rewrite

---

## 2. Questions for you

Each has my recommendation first. Q1–Q3 are needed before slice 0; the rest before the slice named.

| # | Question | Recommendation | Needed by |
|---|---|---|---|
| **Q1** | **How the code talks to MySQL.** Plain SQL through `mysql2`, migrations as numbered `.sql` files run by a small script, and `zod` schemas that both validate requests and generate the OpenAPI document. Or an ORM (Prisma, Drizzle). | **Plain SQL.** Row locks (`FOR UPDATE`, `FOR SHARE`) and conditional updates are the heart of orders and stock, and they are plain SQL anyway. One layer fewer to learn and debug. | S0 |
| **Q2** | **Which MySQL.** 8.0.44 is installed and running (service `MySQL80`, port **3307**). 8.4 LTS is also installed but not set up. | **Set up 8.4 LTS** on port 3306 before slice 0: 8.0 reached end of life in April 2026. Everything designed runs on both, so 8.0 works if you'd rather not now. | S0 |
| **Q3** | **Security defaults** (none are in the documents): access token 15 min; refresh token 30 days for the app and 12 hours for the admin web, rotated on every use; SMS code 6 digits, valid 5 min, resend after 60 s, 5 wrong tries; at most 5 codes per number and 20 per IP an hour; 10 sign-in tries per 15 min; the web keeps its refresh token in `localStorage` as it keeps its session today. | As written. The safer web option is an `httpOnly` cookie, which needs the web and the API on one site; worth it once it's hosted. | S1 |
| **Q4** | **A suspended store.** The contract says its products leave the shop and it leaves the rail. Not said: can the owner still sign in, and what happens to its open orders? | Owner still signs in (the app already knows the `SUSPENDED` status; how its dashboard words it is checked at M2). Orders it already **confirmed** can still be shipped and delivered, so shoppers get what they were promised. Its **new, unconfirmed** orders are cancelled at once (stock back, each shopper told). The full "Closing a store" design (BR: `CLOSING`/`CLOSED`, a final bill, removing personal data) waits for a later version: neither front-end has screens for it. | S2 |
| **Q5** | **The filter sheet's attribute chips** (RAM, CPU, Screen size). The app sends them (`attr_RAM=8`) and the demo ignores them: they filter nothing today, and no product carries that data. | **Send none** (`/categories/:id/attributes` answers `[]`), so the sheet shows only brand, price, stock and sale. Filters that do nothing are buttons that lie. | S3 |
| **Q6** | **"New" or `PENDING`** on the store's order screens. D10 decided the wire value is `PENDING`; the store screens still look for `NEW` (the workflow list, the "new" badge, the Decline button, the tab filter, the dashboard count). | **Change the app** before slice 4 goes live: a few lines in `merchant_widgets.dart`, `merchant_orders_screen.dart` and the order filters. Otherwise the server has to translate for the store routes forever. | S4 |
| **Q7** | **Orders from several stores in the admin's shapes.** The contract's after-sales row, a shopper's `spent` and `cancelledBy` were written for one store per order. | (a) Cancellations & returns lists **one row per cancelled store part** (its `id` is the part's; `orderId` opens the order). (b) `spent` is the amount of their **delivered parts** less refunds, not order totals (a declined part was never paid). (c) `OrderStorePart` also gets `subtotal`, `shipping`, `discount` (D7), `cancellationReason` and `deliveryTime`. | S5 |
| **Q8** | **`RETURNED` and `REFUNDED` orders.** No flow in the app ever sets them: a return has its own record and status, and the order stays `DELIVERED`. | Never set them in v1 (payment never `REFUNDED` either). The web's "Problems" filter will count 0 for those two. | S5 |
| **Q9** | **A shopper deletes their account with an order still open.** Nothing says what happens. (BUGS 183, the Terms saying "ask Support", stays yours.) | **Refuse** until every order is delivered or cancelled: 409 with a message the app shows. Cancelling their orders for them is the other option. | S1 |
| **Q10** | **Development seed data.** | The app's demo world (8 stores, an owner for each, 56 products, the 3 demo logins, 3 months of delivered history with refunded returns, coupons, banners, the featured rail) **plus** the web's own demo data (11 tickets, 8 cancelled orders, open returns, Hussein Karim suspended, Rana Salman), so every screen on both sides has something. Development only. | S3 |
| **Q11** | **SMS gateway for Iraq.** | Not needed on this laptop: codes print in the server's console. Needed before any real user. | Launch |
| **Q12** | **The in-app demo admin** (BUGS 145: delete it "when the backend work starts"). It works against the real server unchanged, except "Start the demo again", which has no real twin. | Delete it at step M2, once the web approves stores against the real server. | M2 |
| **Q13** | **Where it will be hosted.** | Later. It changes two small files (file storage, SMS) and the environment values, not the code (§12). | Launch |

### 2.0 Answered 2026-09-26

| # | Decision |
|---|---|
| Q1 | Plain SQL through `mysql2`; `.sql` migrations; `zod` for validation and OpenAPI. |
| Q2 | MySQL 8.4 LTS in the end; **for now the 8.0.44 already running on port 3307** (changed 2026-09-26, to move fast). Nothing designed needs 8.4; the move is a new `.env` address and `npm run migrate`, since development data is rebuilt by the migrations and the seed. The tests run on 8.4 before launch. |
| Q3 | As recommended. **Access token** 15 minutes. **Refresh token** 30 days in the app, 12 hours in the admin web, replaced on every use; a replaced token used again signs out every session from that sign-in. **SMS code** 6 digits, valid 5 minutes, a new one after 60 seconds, 5 wrong tries then a new code is needed; at most 5 codes per number and 20 per IP address an hour. **Sign-in** 10 tries per 15 minutes per number and address. **Passwords** at least 8 characters (BUGS 118), stored with scrypt. The web keeps its refresh token in `localStorage`. |
| Q4 | **A suspended store follows the same rule as "Close my store"** (BR): its products leave the shop and it takes no new orders, but the owner still signs in and must finish or cancel its open orders: a new order is declined with a reason, a confirmed one is carried to delivered (or refused at the door), through the same transition table. Returns stay open until each 7-day window passes, and the store must still answer them. Its bills keep being worked out, and the final bill is settled like any other. Saba forcing a cancel (BR) has no screen in the web, so it is not built. |
| Q6 | The app follows D10 and uses `PENDING` on the store's screens (§8.4 lists the changes, for the mobile session). |
| Q9 | A shopper with an open order can't delete the account: 409 `CONFLICT_ERROR`, with a message in their language naming the orders in the way ("Orders SB-100012 and SB-100015 are still open."). Open means not `DELIVERED`, `CANCELLED` or `REFUSED`. Once the last one is finished, deletion works as it does now. |
| Q10 | Seed every screen: the 8 stores and their owners, the 56 products, the 3 demo logins, a few months of delivered orders with their bills, returns in every state, cancelled orders, tickets, coupons, banners and the featured rail. Numbers, names, prices, drivers and customers follow the two demos (`MockData`, `_history`, `_historyReturnsOf`, the web's `orders.ts`, `returns.ts`, `tickets.ts`, `customers.ts`), so both can be compared with what you already know. |
| Q7 | **One row per store part** (decided 2026-09-26). Cancellations & returns lists each cancelled part as its own row (the part's id, its store, who cancelled it, its own value, `orderId` to open the order); a shopper cancelling a two-store order gives two rows. A customer's `spent` is their delivered parts' amounts less refunds. `OrderStorePart` carries `subtotal`, `shipping`, `discount`, `cancellationReason` and `deliveryTime`. Who cancelled a part comes from its reason: `CUSTOMER_CANCELLED` is the shopper, any other the store. The contract and the web change to match; the app doesn't. |
| Q5, Q8, Q12 | As recommended: no attribute chips in v1; orders never become `RETURNED`/`REFUNDED`; the in-app admin is deleted at M2. |
| §2.1 | All eight followed as written (confirmed 2026-09-26). |
| Missing Arabic | **A missing translation must be obvious, never a silent fall-back to English** (2026-09-26). The server's own words: every key must exist in both languages, checked when the code compiles and by a test; a key that is somehow missing is sent as a visible marker (`⟦key⟧`), never as the English text. |
| Q11 | **OTPIQ** (decided 2026-09-26). The server makes and checks every code; OTPIQ only delivers it (`POST https://api.otpiq.com/api/sms`, `smsType: verification`). `SMS_PROVIDER=log` while developing; production refuses to start without `otpiq` and its key. A code OTPIQ couldn't send is withdrawn and answered 503, so the shopper can ask again at once; OTPIQ's own 429 is passed on as a wait. |
| After S3 | (2026-09-26) The "back in the shop" notice stays. The contract gets `inShop` and `notInShopReason` (done). Store ratings come from real reviews (S4). Returns are Saba's fixed 7 days for every store, so nothing is kept per product; the app's leftover form fields are for the mobile session (BUGS 202). |
| S5 | (2026-09-27) **Deleted shoppers are left out of the admin's Customers** (list, counts and sheet): deleting an account wipes its name and number, so there is nothing to show; its orders stay under Orders. **The admin's return sheet shows each item at the price paid** (after the store's coupon), so its lines add up to the refund. |
| S6 | (2026-09-27) **A month whose refunds are as big as its sales owes 0, and nothing carries over** to another month, as `DATABASE_DESIGN.md` §6 and the contract have it. The commission rules stay as written: 8% for every store, on delivered goods less the store's own coupon, less the cash it handed back that month, to the nearest 250. |
| S10 | (2026-09-28) **Push notifications, a slice of its own** (§7), after the switch-over and before the launch. **Pushed: only what needs action or touches money.** The store: a new order, a return asked for, an order the shopper cancelled, and a shopper saying a parcel never came. The shopper: their order confirmed, shipped, delivered, or declined by the store, and a return's answer (approved, rejected, refunded). Both sides: chat messages. **Not pushed**, waiting in the notification list until the app is opened: an order being prepared, a parcel refused at the door, Saba's answers on products and stores, suspensions, ticket answers and status changes, and anything else. **Language:** the app sends the phone's language with its push address, and sends it again when the language changes; each push is in that language. **Built 2026-09-29, before Firebase's accounts exist:** everything but the real send, which waits for the service-account file. **Firebase is optional at start** (the user's call, 2026-09-29): without it the server starts and logs that push is off, so push never blocks a launch; SMS stays required, since a code sent nowhere is a real failure. |
| Before launch | (2026-09-29, after the pre-launch sweep) **Reported reviews reach Saba**: an admin list of reported reviews, each with its reports and the shopper's words; Saba removes the review (off the store's page and out of its rating) or dismisses its reports (it stays); both kept in `admin_actions`. **One more app round** (M9) for what the eight rounds never walked: the store's coupons, the store's reviews and "report", and "Buy now". **The app's email-verification leftover stays** (the user's call in the mobile session at M9: nothing can reach it, since the server always sends `isEmailVerified: true` and phone accounts have no email, and removing it reaches into sign-in's interface and tests). **M9 passed** (coupons, reviews and report, Buy now); from it, a coupon's usage limit of 0 is refused (an empty box is "no limit"), and Buy now's refusals no longer speak of the cart. **The rule pages stay app text for launch**, read by a lawyer; moving them to the server and the admin web is v2. **Banners, categories and brands are changed in the database for v1**; admin screens for them are v2. **The live database starts empty** (the migrations and `npm run create-admin`), never a copy of this laptop's, which holds test stores, orders and messages. |
| Before launch | (2026-09-29, the user's answers) **A store owner deletes their account** (Apple and Google refuse deactivation only). Asking closes the store at once and its switch stays shut until the owner cancels. The hourly run deletes it once its orders and returns are finished, the last return window has passed, and every bill is paid. **The final bill is the month's own bill:** due when the month ends and marked paid as any other; no change to the money rules. **Never paid: never deleted.** The store stays closed and Saba keeps the owner's number to collect; there is no "write off". **Product photos stay**, since past orders show the same files; the logo and banner are deleted. The store row stays as CLOSED, with its name, for the orders, returns and bills that name it; its page, products and codes go; the owner's account goes as a shopper's does, after one SMS in both languages (a failed SMS is logged, never a reason to stop). |
| Before launch | (2026-09-29, the user's answers) **Google Play's deletion page** (a web address where someone can ask for their account to be deleted without the app): the simple version, Saba's support email or WhatsApp number. **Written 2026-09-30 with blanks** (the email, the number and the records' keeping time are the client's, not decided yet): `/delete-account`; what to fill in is in §12. **Support then needs a way to do it: a delete button in the admin web. Built 2026-09-30** (the user's call: now, while it is fresh). For a shopper it does what `DELETE /customers/me` does (refused while an order is open); for a store it asks on the owner's behalf, as `POST /merchants/me/deletion` does, with the same waiting rules. Each needs an admin route, an `admin_actions` row, and the web's button. **The brand filter:** brands exist only in the demo data (the store's product form sends none and no admin route adds one), so the live shop starts with none. For v1 the app hides the filter's Brands section when `/brands` is empty; the server changes nothing. A brand box in the product form, with names Saba looks after, is v2, with the admin screens for brands. |
| Before launch | (2026-10-01, the user's answers; this replaces "admin screens for them are v2" above) **Saba's own pages for categories, Home banners and brands**, since the live database starts with no banners and no brands. **A category** is hidden (off Home, Browse, the filters and the stores' picker; its products stay on sale and in search, and a product already in it may keep it) or deleted once it has no sub-categories, its products first moved to a category Saba picks, as they are (no second review); two levels only. **A brand** deleted moves its products to another checked brand or to none, as they are; renaming it renames it everywhere. **Brands: call C.** A store picks a brand or types one; a typed name that is no brand's becomes a new brand waiting for Saba, checked with the product it came with (approving the product approves it), so stores never wait and shoppers' filter shows only checked brands. **A banner** has a picture, optional words in both languages, a link (a product, a store, a category or nothing) and on/off; Home shows the ones that are on, in Saba's order, leaves off one whose link opens nothing any more, and has no banner section when there are none. Contract §3.14. |
| Before launch | (2026-10-01, the user's answers) **SMS codes at sign-up can be switched off**, with one setting, `PHONE_VERIFICATION=off` (default `on`): the client won't pay for SMS at launch. Off, a sign-up gets its proof without a code, under the same limits (20 an address an hour), and its number is kept "not checked" (`users.phone_verified_at` null). **Password reset keeps its SMS code** (call A): skipping it would let anyone with a number take its account. **Back on** needs no code change and no app release: new sign-ups need the code, and each unchecked account is signed out at its next refresh and asked for a `VERIFY_PHONE` code at sign-in (403 `PHONE_NOT_VERIFIED`; the app's screen is built now). Admins are never asked. **Saba sees the unchecked accounts** and can **free a number** held by the wrong person, only one never checked: a shopper's account is deleted, a store's owner suspended and its deletion started. |
| Before launch | (2026-10-01, the user's answers) **Photos in chats, both ways**: one photo a message, no caption; checked as uploads are (an image, 5 MB at most), its GPS location removed, kept privately (`chats/`, never public), and opened only through links the API signs, good for one to two hours. The other side is told "Sent a photo". Block and report cover them; a chat report keeps its photos as evidence. **A deleted account's chat photos go** with it (shown as removed at once, the files at the hourly run), **but one an open report shows stays until Saba closes the report**, so deleting an account never destroys evidence. **Saba can remove a photo** from the Reports page (Apple 1.2). Photos only: no files. |
| Still open | Q13 waits for the launch. |

### 2.1 Where the documents disagree, and what I followed

Tell me if any should go the other way.

| # | Disagreement | Followed |
|---|---|---|
| 1 | A non-admin signing in: contract §3.1 says 403; the audit's D1 (later) says sign-in succeeds and the web refuses. | **D1.** Contract §3.1 still needs its edit. |
| 2 | An unknown number at sign-in: contract §3.1 says 401; the app shows "No account uses this number" on the phone field (422, BUGS 107, 121). | **The app:** 422 `errors.phone` for an unknown number, 401 for a wrong password. The web treats both as "wrong login". |
| 3 | The contract's types lack the fields the audit says the app wins on: D7, D8, D11, D15, D16, D19, D21, D23, D24b, D27, D-P1 (`inShop`). | **The audit.** The server sends them all; extra fields break nothing. The contract needs them added. |
| 4 | Error `errors`: a list in the spec (§54), a map in the contract (§1.4). | **The contract** (the app reads both). |
| 5 | `ADMIN_REQUIREMENTS.md` §3 routes (`/admin/bills`, approve with `{reason?}`, reasons "in both languages, or a code"). | **The contract**, which is later and is what the web calls. Reasons are free text as typed. |
| 6 | Closed stores in search: `PROJECT_MAP.md` §7 says their products drop out; the demo still lists them. | **The document.** |
| 7 | "Closing a store" (BR) merges suspension and closing into `CLOSING`/`CLOSED`; the contract has `SUSPENDED` with suspend and unsuspend. | **The contract** for v1 (Q4). |
| 8 | Admin search matches the whole phrase inside one field (the web's `matches`); the app's search needs every word, anywhere (`SearchText.matches`). | **Each keeps its own:** admin lists match as the web does, shopper and store searches as the app does. |

### 2.2 Gaps I filled with a default

| Gap | Default |
|---|---|
| Order and ticket numbers | `SB-` + (100000 + id); `T-` + (5000 + id) |
| Sorting the app offers but the demo ignores | `relevance`: products whose name matches before those found only by category, then newest. `best_selling`: units delivered. |
| Paging | App lists: 20 a page, at most 100. Admin lists: `page` and `perPage` (default 50, at most 100), searched, counted and paged in the database (2026-09-30, the reviewer's item 7); without `page`, page 1 (the web pages every list; contract §1.3). |
| A shopper's governorate at sign-up | Required (v1 scope: governorate "at sign-up"). |
| A new product's status | `PENDING`, as the demo: the form has no "save as draft". |
| Search history (`GET`/`DELETE /search/history`) | As the demo: an empty list, and clearing does nothing; recent searches stay on the phone. |
| Email verification routes | Not built: email is out of v1, and the screen opens only from an email nobody sends. |
| Photo thumbnails | The photo itself: the app already shrinks photos to 1600 px before sending. |
| Uploads | Images only (JPEG, PNG, WebP, told by their first bytes), at most 5 MB. Videos are out of v1. |
| A deleted product | Leaves every cart and wishlist in the same transaction. |
| `paidAt` on a bill | The paid day at 12:00 Baghdad time, as the web's mock does, so the web shows the same day in any time zone. |
| Found in S1 | **Only a sign-up code proves a number for sign-up.** The code screen's resend sent no `purpose` until the app fixed it (077fe92, BUGS 201); the server accepted `OTHER` codes until then and now takes `SIGN_UP` only. **`isEmailVerified`** is `true` only for Saba's staff (changed 2026-09-30, the reviewer's item 13: it was `true` for every email, never checked, so one person could take another's). With no email checks in v1, **sign-up keeps no email for shoppers and stores**; they sign in by phone. Demo accounts made before keep theirs. In production nobody but staff has an email, so the app's verify-email card never shows. **Sign-out ends the whole sign-in** (the token's family), not only the token sent: the app may refresh on the way to sign-out and send the old one. **The address nickname** is optional, as in the app's form (migration 0004). **Rate limits:** sign-in tries are counted in memory; SMS codes are counted from `otp_challenges`, so those limits survive a restart. |
| Found in S3 | **`inShop` and `notInShopReason`** (D-P1 named no field for the reason): `NOT_APPROVED`, `TAKEN_DOWN`, `HIDDEN_BY_STORE`, `STORE_NOT_APPROVED`, `STORE_CLOSED`, a code the web translates; the contract needs the line. **Putting a taken-down product back tells the store** ("… is back in the shop"), as reactivating a store does. **The form's `lowStockThreshold`, `barcode` and `returnPolicy` are not kept**: low stock is 1–5 for every product (DATABASE_DESIGN.md §3.3), and neither of the others has a column. **A field the form leaves out stays** (`description`, `warranty`, `images`); one it sends replaces both languages. **The seed** (`npm run seed`, empty database only): every demo account signs in with `saba12345`; the stores' ratings come from the reviews S4's seed writes (the user's call, 2026-09-26: real reviews over the demo's totals). |
| Found in S2 | **`owed` waits for S6.** "Close my store" answers `openOrders` and `returnsOpenUntil` from the tables now; `owed` (commission this month plus months due) is added with the bills in S6, after the commission review. The app reads a missing `owed` as 0, which is true until orders exist (S4). **Unsuspending tells the store** "Your store is active again", its own words, never a second "approved" (decided 2026-09-26; contract §3.4 has the line). **The store's settings form sends the whole form**; a field left empty is omitted, so `PUT` treats a missing `description` or `businessAddress` as cleared. **A logo** is accepted only as the store's own upload or the logo it already has, by the address's path, so `10.0.2.2` and `localhost` name the same file. **Admin store search** matches the web's `matches` in code (a few hundred rows); a phone matches any written form once 4 digits are typed. |
| Found in S4 | **A code that is no longer live stays on the cart, taking nothing off** (`applies: false`), and stops checkout until it is taken off (`coupon.gone`), so a shopper is never charged more than the review showed; the demo dropped it silently. A code **under its minimum** takes nothing and does not stop the order (the demo's rule). **Before an address is chosen** the cart delivers to the default address's city, else the account's (the app's `deliveryCityProvider`). **A coupon's day** comes from the phone without a zone ("2026-09-30T23:59:59.000") and is read on Iraq's clock; the server answers in UTC. **Reviews name the reviewer "Amina S."** on the public store page. **A store's decline tells the shopper "Nothing is charged for it"**: cash on delivery, nothing was paid (BUGS 48); the demo said it "comes back to you". **A delivered part's bill month** is fixed when it is delivered, on Iraq's calendar. **Placing an order** reads stock, a coupon's uses and a store's standing under their locks; `ck_product_skus_stock` and `ck_coupons_usage` hold the limits again. **The seed** adds the demo's orders (eight of today per store, the delivered history since three months back numbered SB-190001…), its three coupons, the 15 shoppers behind them, and reviews on three delivered orders in four; the stores' ratings are those reviews. Today's orders buy only what is on sale (the demo's could buy a draft). `npm run seed` adds this to a database seeded before S4, deleting nothing. |
| Found in S5 | **Asking for a return locks the order**, so a second request for the same line waits and is told "This item already has a return"; the unique line in `return_items` stays underneath. **The cash handed back puts back only what was returned** (2 of 3, not the line), each with a ledger row naming the return, and is on the bill of the month it happened, on Iraq's calendar. **A declined return has no refund block** (`refund: null`; the app already hides it), and **no return promises a refund day**: the demo made one up three days ahead. **The shopper is told the store's reason** for declining ("Order SB-…: It has been used."), as with a declined order; the demo said "Message them to ask why". **Cancellations & returns**: a part the shopper cancelled carries their own reason (`FOUND_CHEAPER`…), a store's decline its code; a part refused at the door is neither, so it is not listed. **A customer's `spent`** counts each delivered part's `amountDue`, the delivery fee included: what they paid at the door. **Suspending a shopper ends every sign-in**, so lifting it later brings no old session back. **The seed** adds the web's 8 cancelled orders (SB-180001…), a return on every ninth delivered order in every state (the refunded ones are the app's `_historyReturnsOf`), Hussein Karim suspended, and Rana Salman, who has not ordered yet; `npm run seed` adds them to a database seeded in S4. |
| Found in S6 | **A chart's points start on a plain Baghdad date** (`from: "2026-09-01"`), as a bill's month does (contract §6.3): a phone set to another time zone still names the right day or month. **"Return requests" on the store's dashboard** counts returns waiting for its answer (`REQUESTED`); the demo counted orders marked `RETURNED`, which never happens (Q8). **Last month's same stretch** never runs past last month's end: on 31 March it is the whole of February, "28 days" (the demo ran into March). **Analytics' best sellers** are the five products with the most units delivered in the period that are still on the shelf; **its cancellations** are the store's parts placed in the period that were cancelled or refused; **an average order** is rounded to the dinar. **`owed` on "Close my store"** is this month so far plus every month still due. **Marking a month paid** checks the bill first (409 unless `DUE`), then the day (422); four marks at once pay it once (the unique month underneath). **Undoing it** keeps what the payment said in `admin_actions` (`BILL_UNPAID`: the amount, the day, the rate, who recorded it). **Finance's `month`** can be any month up to this one (a later one is 422), and **`lastMonth`** is the calendar month before this one. **The seed** marks paid what the web's demo does: every month before last by every store, a few days into the month after, and last month by every other store; `npm run seed` adds them to a database seeded in S5. |
| Found in S7 | **Chats:** a shopper starts one only with an approved store (404 otherwise); a chat already there stays open to both sides whatever happens to the store. Two starts at once make one chat (the pair is unique). A chat nobody has written in is not listed. **What you wrote, you have read**, so only the other side's messages count as unread. **The other side is told** "Message from …" with the message, cut to 80 characters, as the demo does. **A deleted shopper** stays in the store's inbox as "Deleted account", in its language. **Tickets:** the app's own limits hold on the server (a subject of 4 to 120 characters, a description of 10 to 2,000; a reply at most 2,000; Saba's at most 4,000). Its first message is the description, and it is opened in the account's name, or the store's for a store. **A reply and a close at the same moment:** the reply is one conditional update, so a ticket closed a moment ago takes nothing (409 "This ticket is closed…"). **The opener is told** of Saba's answer and of each status change, in words per status; each status change is kept in `admin_actions`. **The seed** adds the web's eleven tickets and the app's chats (Amina with Nova, Nova's answer unread, and with Atlas; Nova's inbox with Sara, still waiting, and Yousef Karim of Erbil in place of the demo's "Ali Hassan", who is not a shopper here); `npm run seed` adds them to a database seeded in S5 or S6. |
| Found in S8 | **A stream ends when its access token does** (15 minutes at most), and at once when Saba suspends the shopper or the shopper deletes the account; the app reconnects with a fresh token and announces every topic, as `BACKEND_READY.md` says. **Every notification also tells its reader's stream** (`notifications`), from the one place notifications are written, so none is missed. **Beyond the table**, a store or a shopper signing up and a product sent for review tell Saba's admins (`stores`, `customers`, `products`), so the queue and the lists change without a reload (W8). **Each change is told once per account**, even when one transaction names it twice; **a rolled-back change tells nobody**. **A stream that fails to take a message is ended**; the change behind it is saved and stands. **Stopping the server ends every stream first**, so it stops at once instead of waiting out its 10 seconds. Not covered by a test (it takes real time): the 25-second comment. |
| Found in S9 | **Rate limits, reviewed:** the public routes that cost money or guard an account are limited. SMS codes: 60 seconds apart, 5 a number and 20 an address an hour, counted in the database so a restart doesn't reset them. A code: 5 wrong tries. Sign-in: 10 tries per 15 minutes per address and login, in memory. A refresh token is 48 random bytes, too many to guess, and sign-up needs a phone proof. Everything else is a public read or needs a live account, which a suspension ends at its next request. **Not limited in the server:** public reads and signed-in writes. The host's proxy should cap requests per address at launch. **Housekeeping** runs a minute after start, then hourly, and as `npm run housekeeping` for a host's scheduler. It deletes request keys after 24 hours (`DATABASE_DESIGN.md` §3.5); SMS codes after a day, a default: nothing reads one past its hourly count and the 15-minute proof; and refresh tokens once expired. **Production also refuses the same value for both secrets.** **Every route is in the OpenAPI document**, checked both ways by a test: 139 on the API's router (107 for the app, `/events` and `/health` among them, and 32 under `/admin`), plus the two docs routes, 141 as planned. **A production start** without a secret exits with the variable's name and prints no secret; with everything present it listens, the docs off. **Left for the launch (Q13):** the host, a managed MySQL 8.4 and the tests run on it, OTPIQ's live key, file storage and `MEDIA_BASE_URL`, `TRUST_PROXY`, the proxy's request cap. |

---

## 3. Stack and libraries

Node.js, TypeScript, Express and MySQL are chosen. The rest is my proposal (Q1). Versions are pinned when the project is made, and checked against Node 24 then.

| Need | Choice | Why |
|---|---|---|
| Runtime | Node.js 24 LTS | Installed (24.15.0); supported until April 2028 |
| Language | TypeScript, `strict` | The same major version as the web |
| HTTP | Express 5 | Chosen. Version 5 passes errors thrown in async handlers to the error handler by itself. |
| MySQL | `mysql2`, a promise pool | `?` placeholders only, never string-built SQL |
| Migrations | Numbered `.sql` files and a small runner that records each with a checksum | Plain SQL is what reviewers read; a changed file is caught |
| Validation, API docs | `zod`, `@asteasolutions/zod-to-openapi`, `swagger-ui-express` | One schema validates a request and documents it, so the OpenAPI can't drift |
| Access tokens | `jose` (JWT, HS256) | Small, maintained, no dependencies |
| Passwords | `node:crypto` scrypt | Built into Node, on OWASP's list, no native build on Windows |
| Logs | `pino`, `pino-http` | Structured JSON; tokens, passwords and codes redacted |
| Headers, CORS, rate limits | `helmet`, `cors`, `express-rate-limit` | |
| Uploads | `multer` | |
| Running while developing | `tsx` (watch mode) | |
| Tests | `node:test`, run through `tsx`, calling the app over HTTP, against a real MySQL test database | Locks, constraints and transactions are what need testing; a mocked database can't |

Not used: an ORM, a query builder, Redis (one process; §12), Docker (not needed on this laptop), a job queue (nothing has to run on time: §5.6).

---

## 4. Folder structure

A new `backend/` beside `mobile/` and `website/`.

```
backend/
├── package.json, tsconfig.json, .env.example, README.md
├── migrations/                 0001_schema.sql (all of DATABASE_DESIGN.md), 0002_governorates.sql,
│                               0003_categories.sql, … then one file per later change
├── scripts/
│   ├── migrate.ts              runs migrations/ in order, records each in schema_migrations
│   ├── seed.ts                 the development world (Q10); refuses to run in production
│   └── create-admin.ts         makes a Saba staff account; the only way one is made
├── seed-media/                 the demo photos the seed copies into storage
├── src/
│   ├── server.ts               reads the config, opens the pool, listens, shuts down cleanly
│   ├── app.ts                  builds the Express app (no listen), so tests can start it
│   ├── config.ts               the only reader of process.env; refuses to start with a bad value
│   ├── rules.ts                business constants: 8 %, 7 days, 1,000,000 IQD, 250, name lengths, stock thresholds
│   ├── db/
│   │   ├── pool.ts             the pool; each connection set to UTC
│   │   └── tx.ts               withTransaction(fn): begin, commit, roll back, one retry on deadlock
│   ├── http/
│   │   ├── envelope.ts         ok(), page(), list() — the one response shape
│   │   ├── errors.ts           AppError and its kinds, each with status and code
│   │   ├── error-handler.ts    the one place an error becomes a response
│   │   ├── validate.ts         zod for body, query and params
│   │   ├── auth.ts             requireAuth, optionalAuth, requireRole
│   │   ├── language.ts         Accept-Language → req.lang
│   │   ├── rate-limits.ts
│   │   └── openapi.ts          /openapi.json and /docs
│   ├── lib/
│   │   ├── fold.ts             port of the app's search_text.dart
│   │   ├── phone.ts            port of the app's iraqi_phone.dart (normalise, display)
│   │   ├── money.ts            the formulas of DATABASE_DESIGN.md §6
│   │   ├── baghdad.ts          Baghdad day and month (fixed +03:00)
│   │   ├── i18n.ts             the server's own words, in English and Arabic
│   │   ├── localise.ts         x ← xAr for shoppers and stores asking in Arabic
│   │   ├── events.ts           who is listening, and publishing after a commit (§10)
│   │   ├── notify.ts           writes a notification row in both languages
│   │   ├── storage.ts          put / remove / address of a file (this laptop's disk for now)
│   │   └── sms.ts              send a code (the console for now)
│   └── modules/
│       ├── auth/  account/  catalog/  home/  search/  media/
│       ├── cart/  checkout/  orders/  returns/  reviews/
│       ├── store/              everything under /merchants/me
│       ├── messaging/  notifications/  support/  events/
│       └── admin/              everything under /admin
│           each module: routes.ts   HTTP only: validate, call the service, answer
│                        service.ts  rules, ownership, transactions
│                        repo.ts     SQL only
│                        schemas.ts  zod: requests, responses, OpenAPI
└── test/                       one file per slice, plus concurrency.test.ts
```

---

## 5. How a request flows

```
app / web ──▶ /api/v1/...
   request id → log line (redacted) → security headers → CORS allow-list → JSON body (1 MB) → language
   → router
       /auth/*               public, rate-limited
       catalogue, Home       public; reads the token if there is one
       shopper routes        signed in, role CUSTOMER
       /merchants/me/*       signed in, role MERCHANT; the store is the session's
       /admin/*              signed in, role ADMIN
   → validate (zod)          422 VALIDATION_ERROR, errors.{field}
   → service                 business rules, ownership, transactions
   → repo                    SQL, given the transaction's connection
   → envelope                { success, message, data, meta }
   any error ─▶ error handler ─▶ { success: false, code, message, errors }
```

### 5.1 Authentication

- **Access token:** a JWT (HS256, 15 minutes) with the account id, role and its sign-in (`sid`, the refresh tokens' family), sent as `Authorization: Bearer`.
- **Every signed-in request reads the account's row** (one query: role and status, and whether the token's sign-in is still live: not revoked, not expired). A suspended or deleted account gets 401. Its refresh tokens were revoked when it was suspended, so the app's refresh fails and it goes back to sign-in, where the sign-in answers 403 "This account is suspended". A suspension takes effect at once, not 15 minutes later.
- **An ended sign-in ends its access tokens at once** (the user's call, 2026-09-28, after M5): signing out, a suspension, a password reset or a reused refresh token. Lifting a suspension brings none back. A token made before `sid` existed is refused once; the app and the web renew on that 401 by themselves.
- **Refresh tokens** are rotated on every use; a reused one revokes its family (`DATABASE_DESIGN.md` §3.1).
- **Roles** are checked on the router, once per group of routes. A shopper can't reach a store route or an admin route (403).
- **Admins** are made only by `npm run create-admin`.

### 5.2 Ownership

- Every private read and write names its owner **in the query**: `WHERE id = ? AND customer_id = ?`, `WHERE id = ? AND store_id = ?`.
- The store id **always comes from the session**, never from the request.
- Not yours looks exactly like not there: **404**, so ids reveal nothing ("An order that is not this shopper's is not found", demo).
- Photos and logos: only files the same account uploaded (`DATABASE_DESIGN.md` §3.3).
- Prices, totals, stock, roles and who someone is are never taken from the client (spec §51).

### 5.3 Transactions

- Only services open transactions, through `withTransaction(fn)`. Repositories are handed its connection.
- Which operations, which locks, in which order: `DATABASE_DESIGN.md` §5.
- Events to other devices go out **after** the commit (§10).

### 5.4 Errors

The contract's body (§1.4) and the app's codes (`error_mapper.dart`):

| Case | HTTP | `code` |
|---|---|---|
| A field is wrong or missing | 422 (400 for a wrong SMS code, as the demo) | `VALIDATION_ERROR`, with `errors.{field}` |
| Not signed in, token expired | 401 | `AUTHENTICATION_ERROR` |
| Wrong role, or a suspended account signing in | 403 | `AUTHORIZATION_ERROR` |
| No such record, or not yours | 404 | `NOT_FOUND_ERROR` |
| Not allowed from the record's state; a duplicate | 409 | `CONFLICT_ERROR` |
| A business rule (Arabic name, first-order limit, doesn't deliver there) | 422 | `BUSINESS_RULE_ERROR` |
| Out of stock at checkout | 422 | `INVENTORY_ERROR` |
| Too many tries | 429 | — |
| Anything else | 500 | — (no stack, no SQL, no path) |

A write the database refuses is turned into the right field error by the constraint's name: `uq_users_phone` → 409 on `phone`; `uq_stores_governorate_name_key` → 422 on `storeName`.

### 5.5 Language

- `Accept-Language` beginning with `ar` means Arabic; anything else English.
- **For shoppers and stores**, every field with an Arabic twin (`name`/`nameAr`, `description`/`descriptionAr`, …) is sent in the asked language, the twin still included (the demo's `_inArabic`).
- **For admins, never**: both names, always (contract §1.6), on the shared `/categories` and `/auth/login` too.
- **The server's own words** come from one file in both languages (`lib/i18n.ts`): error messages, notification texts, Home's titles, delivery times, the payment label, "Doesn't deliver to Erbil", coupon descriptions. Dates in Arabic keep Western digits (`ar-u-nu-latn`; BUGS 28).

### 5.6 On the wire

| What | Form |
|---|---|
| Ids | Strings |
| Money | Whole IQD, integers |
| Moments | ISO 8601, UTC, milliseconds: `2026-09-24T09:21:00.000Z` |
| Months | Responses: the first day, a plain date `2026-08-01`. Admin paths and queries: `2026-08` (contract §6.3). |
| Phones | E.164 (D13); each screen formats them |
| Governorates | Codes |
| App lists | `data: [...]`, `meta: {page, perPage, total, totalPages}` |
| Admin lists | `data: {items, counts}`, and a `meta` of `{page, perPage, total, totalPages}`; no `page` means page 1 |

Nothing has to run on a clock: flash sales end when read, bills are worked out when read, the return window is checked when read. One housekeeping timer deletes expired idempotency keys, SMS codes and refresh tokens; missing it breaks nothing. The same hourly run deletes each store whose owner asked and has nothing left to finish (§6.5); missing a run only delays it.

---

## 6. Every endpoint

All under `/api/v1`. **Who:** Public · Shopper · Store · Admin · Signed in (any role). **Tx:** runs in one transaction. **Slice:** when it is built (§7).

### 6.1 Sign-in and account

| Method | Path | Who | What the server does | Tx | Slice |
|---|---|---|---|---|---|
| POST | `/auth/otp/send` | Public | `{phone, purpose?}` → `{expiresInSeconds: 60}` (the resend wait). `SIGN_UP` for a number with an account: 409. `PASSWORD_RESET` for one without: 422 `phone`. Never sends `demoCode`. | | S1 |
| POST | `/auth/otp/verify` | Public | `{phone, code}` → `{verificationToken}` (15 min, one use). Wrong code: 400 `errors.code`. | | S1 |
| POST | `/auth/register/customer` | Public | Checks the token and its phone (BUGS 108, 168), name ≤ 50, password ≥ 8, governorate. An `email` sent is not kept (reviewer 13). → the account and tokens. | ✓ | S1 |
| POST | `/auth/register/merchant` | Public | As above, plus `storeName` (≤ 40, unique in its city) and the store's governorate. → the account with `merchant {id, storeName, status: PENDING}`. | ✓ | S1 |
| POST | `/auth/login` | Public | `{phone or email, password}` → `{user, accessToken, refreshToken, expiresIn}` (the app reads the user under `user` or flat, and the tokens beside it). Any role (D1). | | S1 |
| POST | `/auth/refresh` | Public | `{refreshToken}` → a new pair. | ✓ | S1 |
| POST | `/auth/logout` | Signed in | Revokes that refresh token. | | S1 |
| POST | `/auth/reset-password` | Public | `{phone, token (the SMS code), password}`: checks the code (BUGS 122), sets the password, signs every device out. | ✓ | S1 |
| GET | `/customers/me` | Signed in | The account, with `merchant {id, storeName, status, rejectionReason, logoUrl, rating, deletionRequestedAt}` for a store owner. Every role uses this path. | | S1 |
| PATCH | `/customers/me` | Signed in | `{fullName?, governorate?}` only. A new phone number needs an SMS check, so it is ignored. | | S1 |
| DELETE | `/customers/me` | Shopper | Refused (409) while an order is open, naming those orders (Q9). Otherwise deletes the account: name and number cleared, number freed, tokens revoked, cart, wishlist and addresses removed; orders keep their copies; their support tickets keep what was said, not their name or number (reviewer 14). A store owner asks through `/merchants/me/deletion` instead (§6.5). | ✓ | S1 |
| GET | `/customers/me/addresses` | Shopper | The default first | | S1 |
| POST | `/customers/me/addresses` | Shopper | An Iraqi mobile, a known governorate, area and landmark present. The first is the default. | ✓ | S1 |
| PUT | `/customers/me/addresses/:id` | Shopper | Replaces it | ✓ | S1 |
| DELETE | `/customers/me/addresses/:id` | Shopper | | | S1 |
| PUT | `/customers/me/addresses/:id/default` | Shopper | | ✓ | S1 |

Not built: `/auth/verify-email`, `/auth/verify-email/resend` (§2.2).

### 6.2 Catalogue, Home, search (public)

| Method | Path | What the server does | Slice |
|---|---|---|---|
| GET | `/categories` | The tree (contract §3.5) | S3 |
| GET | `/categories/:id` | One, with its children; 404 if none (the demo answered `{}`) | S3 |
| GET | `/categories/:id/attributes` | `[]` in v1 (Q5) | S3 |
| GET | `/brands` | Brands with a listed product (in `categoryId` when sent), `productCount` counted | S3 |
| GET | `/products` | Listed, browsable products. `q` (every word, folded), `categoryId` (with its sub-categories), `merchantId`, `governorate` (the store's city), `deliverTo` (adds `deliveryAvailable`), `brandIds`, `minPrice`/`maxPrice` (on the shown price), `inStock` (stock now), `onSale` (has an original price), `sort`, paging. A search that found something counts once toward popular searches. | S3 |
| GET | `/search` | The same as `/products` | S3 |
| GET | `/search/suggestions` | Up to 8 product names matching `q`, in the asked language | S3 |
| GET | `/search/popular` | The 6 most-searched terms that found something | S3 |
| GET, DELETE | `/search/history` | Shopper. `[]`; clearing does nothing (§2.2) | S3 |
| GET | `/products/:id` | Full product: photos, `variants` with stock, `categoryName(Ar)`, `merchant {…, governorate, logoUrl, delivery, isOpen, rating}`. `isWishlisted` for a signed-in shopper; its own store also gets it unlisted, with `isListed: false`. Otherwise 404 "This product is not available." | S3 |
| GET | `/products/:id/related` | Up to 6 listed products of the same category, not itself | S3 |
| GET | `/home/sections` | `BANNER` (if any), `CATEGORY`, `FLASH_SALE` (running sales, open stores, in stock, soonest end first, with `endsAt`), `COUPONS` (no items), `MERCHANT` (the featured, approved stores in order, with product counts). An empty section is left out (D28). Titles in the asked language. | S3 |
| GET | `/stores/cities` | Governorates with an open, approved store, in the app's order (contract §6.11) | S2 |
| GET | `/merchants/:id/store` | A store's public page: rating, delivery terms, `isOpen`. 404 unless approved. | S2 |
| GET | `/merchants/:id/reviews` | Its reviews, newest first, paged | S4 |
| GET | `/merchants/:id/coupons` | Its live coupons, as offers | S3 |
| GET | `/coupons` | Every live store coupon, as offers (Home's strip, the cart) | S3 |
| POST | `/reviews/:id/report` | Shopper. Kept once per shopper per review | S4 |
| POST | `/reports` | Shopper or store. `{targetType: PRODUCT, STORE or CONVERSATION, targetId, reason (the review reasons), description?}`: kept once per person and target; never your own product or store; only a product or store shoppers can see, only your own chat (404 otherwise). A chat report keeps its last 20 messages as evidence. Saba sees it in its Reports (contract §3.13). Apple 1.2 (the reviewer's item 3) | Before launch |
| POST | `/media/upload` | Store. Multipart `file` + `kind=IMAGE` → `{id, url, thumbnailUrl, kind}` | S2 |
| DELETE | `/media/:id` | Store, own. Refused while a product or the store still uses it | S2 |

### 6.3 Cart, wishlist, checkout (Shopper)

The cart, checkout review and place-order use **one pricing function**, so the three can't disagree (§9, item 16).

| Method | Path | What the server does | Tx | Slice |
|---|---|---|---|---|
| GET | `/cart` | Groups by store with `deliversHere`, fee, time, `amountDue`; saved lines; totals; the coupon `{code, discountAmount, description, applies, minOrderAmount}`. Delivery to the default address's governorate. | | S4 |
| POST | `/cart/items` | `{productId, variantId?, quantity}`: listed products only. The same option again adds to its line. | | S4 |
| PATCH | `/cart/items/:id` | `{quantity}` | | S4 |
| DELETE | `/cart/items/:id` | | | S4 |
| POST | `/cart/items/:id/save-for-later`, `/move-to-cart` | Moving onto an existing line adds the quantities | ✓ | S4 |
| POST | `/cart/coupon` | `{code}`: must exist and be live (one not started says when it starts); a store's code needs that store's things, and its minimum. 422 `errors.code` otherwise. | | S4 |
| DELETE | `/cart/coupon` | | | S4 |
| GET, POST | `/wishlist/items` | List; `{productId}` adds | | S3 |
| DELETE | `/wishlist/items/:productId` | | | S3 |
| POST | `/checkout/review` | `{addressId?, deliveryInstructions?, shipping[], paymentMethodId?, items? (Buy now)}` → `canPlaceOrder`, `warnings` (out of stock, first-order limit), a group per store with its one shipping option, totals, `paymentMethods: [COD]` | | S4 |
| POST | `/checkout/place-order` | `Idempotency-Key` required; the same body. 422 for: not cash; anything out of stock or no longer listed (`INVENTORY_ERROR`, naming it); over the 1,000,000 IQD first-order limit; a store that doesn't deliver there or is closed; no address. Makes the order, its parts, lines and first timeline step; takes the stock; counts the coupon use only if it took something off; empties the cart unless Buy now; tells each store. → `{order, requiresPaymentAction: false}` | ✓ | S4 |

### 6.4 The shopper's orders and returns (Shopper, own only)

| Method | Path | What the server does | Tx | Slice |
|---|---|---|---|---|
| GET | `/orders` | `status`, paged, newest first. Each with `storeParts` (status, money, driver, `received`, `deliveryTime`) and lines carrying their part's status too (D9: both, until the app reads the part's) | | S4 |
| GET | `/orders/rating-due` | The oldest delivered order still to rate (skipped fewer than 3 times, a delivered part not yet answered), or `{}` | | S4 |
| GET | `/orders/:id` | With `canCancel`, `canReturn` per line, the timeline | | S4 |
| GET | `/orders/:id/invoice` | From the order's own figures; `sellerName` only when one store | | S4 |
| POST | `/orders/:id/cancel` | `{reason (the list), note?}`: only while no store is past Confirmed (409). Every live part `CANCELLED` with `CUSTOMER_CANCELLED`, stock back, each store told. | ✓ | S4 |
| POST | `/orders/:id/received` | `{merchantId, received}`. "No" tells the store. | | S4 |
| POST | `/orders/:id/rating` | `{received, ratings {storeId: 1–5}, comment?}`. One review per store per order; "not received" tells the stores instead. | ✓ | S4 |
| POST | `/orders/:id/rating-skipped` | | | S4 |
| POST | `/returns` | `{orderId, reason, description?, items [{orderItemId, quantity}]}`: one store's lines, delivered within 7 days, each line once, at most what was bought. Refund = the paid unit prices. Tells the store. | ✓ | S5 |
| GET | `/returns` | `status`, paged | | S5 |
| GET | `/returns/:id` | 404 when not theirs (the demo answered `{}`) | | S5 |

### 6.5 The store's own side (Store; always the session's store)

| Method | Path | What the server does | Tx | Slice |
|---|---|---|---|---|
| GET | `/merchants/me/store` | Its settings and delivery terms | | S2 |
| PUT | `/merchants/me/store` | Name (≤ 40, unique in its city), description, business address, governorate, `logoUrl` (its own upload, or `null` to remove), `delivery` (fees in steps of 250, times from the list, its own city always included). An edited field replaces both languages (§9, item 5). | ✓ | S2 |
| PATCH | `/merchants/me/store/open` | `{isOpen}` → `{isOpen, openOrders, owed, returnsOpenUntil}` (BR). Opening is refused (409) while its owner's account deletion is asked | ✓ | S2 |
| GET | `/merchants/me/deletion` | `StoreDeletion {requestedAt (null: not asked), openOrders, openReturns, returnsOpenUntil, owed, currencyCode}`: what is left before the account can go (§2.0 Before launch) | | Before launch |
| POST | `/merchants/me/deletion` | Asks to delete the owner's account, any store status: the store closes now; asked twice, the first day stands. → `StoreDeletion`. The hourly run deletes it when all four figures are nothing | | Before launch |
| DELETE | `/merchants/me/deletion` | Cancels while it waits; the store stays closed until its owner opens it. → `{}` | | Before launch |
| GET | `/merchants/me/dashboard` | This month so far (Baghdad) against the same days last month; to confirm, low, out, rejected counts; the six-month `salesSeries` with `from` and `unit`; rating (`_merchantDashboard`) | | S6 |
| GET | `/merchants/me/products` | `status`, `filter` (waiting, low, out, hidden), `q`, paged; rows with `takenDown` and Saba's reason, and `hasVariants` (sold in options: no stock stepper on the shelf; added at M3) | | S3 |
| GET | `/merchants/me/products/counts` | `{all, waiting, low, out, hidden}` | | S3 |
| POST | `/merchants/me/products` | A new product, `PENDING`: Arabic name, category, prices in steps of 250, its own photos, options | ✓ | S3 |
| GET | `/merchants/me/products/:id` | Its own product in full, any status | | S3 |
| PUT | `/merchants/me/products/:id` | Keeps its status and any running sale (§9, item 4). Options matched by id; a new option gets a new id (BUGS 163); removed options are marked deleted. **A stock changes only when the store changed it** (the reviewer's item 1, 2026-09-30): each stock (`stock`, and each existing option's) comes with `stockBefore`, the number the form showed. Missing or equal: the stock stays, so units sold while the form was open stay sold. Different while the stock moved underneath: 409, naming what is left now. A new option starts at the stock sent. **An approved product whose names, words, category, brand, photos or option names change goes back to `PENDING`** (the reviewer's item 8, 2026-09-30): out of the shop until Saba approves it again; prices, stock and codes change without a review. | ✓ | S3 |
| DELETE | `/merchants/me/products/:id` | Marked deleted; leaves carts and wishlists | ✓ | S3 |
| POST | `/merchants/me/products/:id/submit` | `DRAFT` or `REJECTED` → `PENDING` | | S3 |
| POST | `/merchants/me/products/:id/visibility` | `{isActive}`; 409 when Saba took it down | | S3 |
| PATCH | `/merchants/me/products/:id/stock` | `{stock}`, for a product without options | ✓ | S3 |
| POST, DELETE | `/merchants/me/products/:id/flash-sale` | `{salePrice, saleEndsAt}`: listed products only (409); steps of 250; below the normal price; the end in the future; every option still ≥ 250. `DELETE` ends it now. | | S3 |
| GET | `/merchants/me/inventory` | A row per thing sold: available, reserved (in open parts), sold (delivered) | | S3 |
| POST | `/merchants/me/inventory/:id/adjust` | `{quantity}`, a change, never below 0 | ✓ | S3 |
| GET | `/merchants/me/orders` | `status` (a comma list), paged; its parts only | | S4 |
| GET | `/merchants/me/orders/counts` | Per status | | S4 |
| GET | `/merchants/me/orders/:id` | The part, its lines, the shopper's name, address and phone, and its returns | | S4 |
| PATCH | `/merchants/me/orders/:id/status` | `{status, reason?, courierName?, courierPhone?}` through the transition table (`DATABASE_DESIGN.md` §5.3). Tells the shopper. | ✓ | S4 |
| PATCH | `/merchants/me/returns/:id` | `{status, reason?}`: approve, decline (reason required), cash handed back (stock returns). Tells the shopper. | ✓ | S5 |
| GET, POST | `/merchants/me/coupons` | List; create (code unique across Saba) | | S4 |
| PUT, PATCH, DELETE | `/merchants/me/coupons/:id` | Edit; pause or resume `{isActive}`; delete | | S4 |
| GET | `/merchants/me/analytics` | `period` week, month or year, on Baghdad's calendar (`_merchantAnalytics`) | | S6 |
| GET | `/merchants/me/bills` | `{currencyCode, ratePercent, current, past[]}`: this month and every month since approval with a delivery or a refund (D4); `OPEN`, `DUE`, `PAID`, `NONE`; months as plain dates | | S6 |

### 6.6 Messages, notifications, support, live updates

| Method | Path | Who | What the server does | Slice |
|---|---|---|---|---|
| GET | `/messages/conversations` | Shopper or Store | A shopper's chats, or the store's inbox; only chats with a message in them | S7 |
| POST | `/messages/conversations` | Shopper | `{merchantId}` → the chat with that store, made if new | S7 |
| GET | `/messages/conversations/:id` | Its two sides | 404 otherwise | S7 |
| GET, POST | `/messages/conversations/:id/messages` | Its two sides | Newest first, paged; `{body}` (not blank, ≤ 2000) tells the other side | S7 |
| POST | `/messages/conversations/:id/read` | Its two sides | | S7 |
| POST | `/messages/conversations/:id/block` | Its two sides: this side blocks the other. While either side has, nobody writes in the chat (409 "Messages are off in this chat: it's blocked."); it stays readable. `Conversation` gains `blocked` and `blockedByMe`. Blocking is chat only: a blocked shopper can still buy. Apple 1.2 (the reviewer's item 3) | | Before launch |
| DELETE | `/messages/conversations/:id/block` | Its two sides: this side's block ends; the other side's stands | | Before launch |
| GET | `/notifications` | Signed in | Paged, newest first, in the asked language, each with its target | S2 |
| GET | `/notifications/unread-count` | Signed in | `{count}` | S2 |
| PATCH | `/notifications/:id` | Signed in, own | Marks it read | S2 |
| POST | `/notifications/read-all` | Signed in | | S2 |
| PUT | `/devices` | Shopper or store | `{token, platform: ANDROID or IOS, language: en or ar}`: this phone's push address. One row per token: one already known moves to this account. Sent at sign-in, when Firebase gives a new token, and when the app's language changes | S10 |
| DELETE | `/devices` | Shopper or store | `{token}`: forgotten at sign-out; only the account's own | S10 |
| GET, POST | `/support/tickets` | Shopper or Store | Own tickets; `{subject, category, description}` opens one, `openedBy` from the session | S7 |
| GET | `/support/tickets/:id` | Its opener | | S7 |
| GET, POST | `/support/tickets/:id/messages` | Its opener | A reply reopens `WAITING_FOR_CUSTOMER` or `RESOLVED`; `CLOSED` is 409 (D-T2) | S7 |
| GET | `/events` | Signed in | The live channel (§10) | S8 |
| GET | `/health` | Public | The database answers | S0 |
| GET | `/openapi.json`, `/docs` | Public, off in production unless switched on | | S0 |

### 6.7 Admin (Admin only): the contract's 34

Shapes are the contract's, plus the fields in §2.1 row 3. Every write also writes `admin_actions`.

| Method | Path | Contract | Also | Tx | Slice |
|---|---|---|---|---|---|
| POST | `/auth/login` | §3.1 | D1 | | S1 |
| GET | `/admin/stores` | §3.4 | `isOpen`, `descriptionAr`; `deletionRequestedAt` while the owner's deletion waits, and `status` CLOSED with `closedAt` once done (its number and name are gone) | | S2 |
| GET | `/admin/stores/{id}` | §3.4 | | | S2 |
| POST | `/admin/stores/{id}/approve` | §3.4 | Tells the store | ✓ | S2 |
| POST | `/admin/stores/{id}/reject` | §3.4 | Tells the store, with the reason | ✓ | S2 |
| POST | `/admin/stores/{id}/suspend` | §3.4 | No new orders; the owner still signs in and finishes its open ones (Q4) | ✓ | S2 |
| POST | `/admin/stores/{id}/unsuspend` | §3.4 | No "approved" notice | ✓ | S2 |
| POST | `/admin/stores/{id}/deletion` | §3.4 | At the owner's request through support: what the owner's own button does (§6.5); once, else 409; the owner is told and can cancel | ✓ | Before launch |
| GET | `/admin/queue` | §3.3 | Stores in S2, products added in S3 | | S2 |
| GET | `/admin/featured-stores` | §3.9 | | | S2 |
| PUT | `/admin/featured-stores` | §3.9 | Keeps a suspended one at the end | ✓ | S2 |
| GET | `/admin/review-reports` | §3.12 | Reported reviews, the latest report first, each with its reports; `status` OPEN, DISMISSED or REMOVED; counts | | Before launch |
| POST | `/admin/review-reports/:id/remove` | §3.12 | The review leaves the store's page and its rating; its open reports close as REMOVED; twice is 409 | ✓ | Before launch |
| POST | `/admin/review-reports/:id/dismiss` | §3.12 | Its open reports close; the review stays; nothing open is 409 | ✓ | Before launch |
| GET | `/categories` | §3.5 | Both names | | S3 |
| GET | `/admin/products` | §3.5 | `descriptionAr`, `warrantyAr`, `sku`, `saleEndsAt`, option fields, `inShop` with its reason | | S3 |
| GET | `/admin/products/{id}` | §3.5 | | | S3 |
| POST | `/admin/products/{id}/approve` | §3.5 | | ✓ | S3 |
| POST | `/admin/products/{id}/reject` | §3.5 | | ✓ | S3 |
| POST | `/admin/products/{id}/hide` | §3.5, §6.8 | Takedown; tells the store | ✓ | S3 |
| POST | `/admin/products/{id}/unhide` | §3.5 | | ✓ | S3 |
| GET | `/admin/orders` | §3.6 | `paymentMethodType`, Arabic fields, `instructions`, per-part money, lines' `variantLabel` and `sku` | | S4 |
| GET | `/admin/orders/{id}` | §3.6 | | | S4 |
| GET | `/admin/dashboard` | §3.2 | | | S5 |
| GET | `/admin/after-sales` | §3.10 | Q7 | | S5 |
| GET | `/admin/returns/{id}` | §3.10 | D19: the shopper's words, the store's reason, steps, options; D6's `refund` | | S5 |
| GET | `/admin/customers` | §3.11 | All five statuses (D27) | | S5 |
| GET | `/admin/customers/{id}` | §3.11 | | | S5 |
| POST | `/admin/customers/{id}/suspend` | §3.11 | Revokes their tokens | ✓ | S5 |
| POST | `/admin/customers/{id}/unsuspend` | §3.11 | | ✓ | S5 |
| DELETE | `/admin/customers/{id}` | §3.11 | At the shopper's request through support: what their own delete does, now; 409 while an order is open; shoppers only | ✓ | Before launch |
| GET | `/admin/finance` | §3.7 | | | S6 |
| GET | `/admin/stores/{id}/bills` | §3.7, §6.6 | | | S6 |
| POST | `/admin/stores/{id}/bills/{month}/paid` | §3.7 | | ✓ | S6 |
| DELETE | `/admin/stores/{id}/bills/{month}/paid` | §3.7 | | ✓ | S6 |
| GET | `/admin/tickets` | §3.8 | | | S7 |
| GET | `/admin/tickets/{id}` | §3.8 | | | S7 |
| POST | `/admin/tickets/{id}/messages` | §3.8 | Tells the opener (`TICKET`) | ✓ | S7 |
| POST | `/admin/tickets/{id}/status` | §3.8 | Tells the opener | ✓ | S7 |

Not built: `/admin/demo/reset` (demo only).

**141 routes** in all (a route is a method and a path): the 105 behind the app's shopper and store screens; the 32 under `/admin` (the contract's 34, less the two it shares with the app; the in-app demo admin uses five of them); and `/events`, `/health` and the two docs routes. `api_endpoints.dart` declares 112 paths; the 22 that nothing in the app calls are left out: named wishlists, promotions, the checkout's step-by-step routes, `/merchants/:id/products` (a store's page uses `/products?merchantId=`) and the like.

---

## 7. Build order: vertical slices

Each slice is **schema-backed, tested, documented in OpenAPI, and clicked through in both front-ends** before the next begins. The whole reviewed schema goes in at slice 0 (`0001_schema.sql`), so no slice waits on another's tables; later changes are new migrations.

A slice is **done** when: its tests pass (each regression test watched failing with its fix removed first); its routes are in `/docs`; its journeys pass in the app's live build and the web's live build (§8); and the demo builds of both still work.

| Slice | Builds | Its tests prove | Switch step |
|---|---|---|---|
| **S0 Foundation** | Project, config, pool, migration runner, the schema, governorates and categories, error handler, envelope, logging, language, `withTransaction`, `/health`, `/docs`, the test harness, the seed script's frame | A clean database migrates; a changed migration is refused; errors come out in the contract's shape; the log never shows a token | — |
| **S1 Accounts** | SMS codes, sign-up for both roles, sign-in, refresh, sign-out, reset, `/customers/me`, addresses, delete, `create-admin`, rate limits | A made-up or reused verification token fails; `0751…` and `+964 751…` are one number; a rotated refresh token used again revokes the family; a suspended account is out at its next request; nobody can sign up as an admin | M1, W1 |
| **S2 Stores and Saba's answers** | Store settings and logo upload, the open switch, the public store page, store cities, notifications (all four routes), the admin's stores, queue (stores), featured rail | 409 from the wrong state, 422 without a reason; the store is told; the audit row is written; a duplicate name in the same city is refused, in another city accepted; a suspended featured store drops off and comes back at the end | M2, W2 |
| **S3 Catalogue** | Products with photos and options, submit, visibility, stock, inventory, flash sales, the public catalogue, search, Home, wishlist, the admin's products and queue (products); the dev seed's stores and catalogue (Q10), which each later slice extends with its own records | The one "listed" rule everywhere; the Arabic name rule; steps of 250; an ended sale's price is the old one on every read; search folds like the app (its own cases, ported); a taken-down product can't be switched back on by its store | M3, W3 |
| **S4 Buying** | Cart, coupons (store and cart), checkout review, place-order, the shopper's orders, cancel, received, ratings, store reviews, the store's orders and steps, the admin's orders | Every formula of `DATABASE_DESIGN.md` §6 against the demo's own numbers; **two shoppers, one unit left: one order**; the same key twice: one order; the first-order limit; the transition table; stock back on decline, refusal and cancel; paid only when every live part is delivered | M4, W4 |
| **S5 Returns and people** | Returns, the store's answers, the admin's dashboard, after-sales, return detail, customers and their suspension | One return per line, even at the same moment; refunds at the paid price; the 7-day window; a suspended shopper can't sign in or order | M5, W5 |
| **S6 Money** | The store's bills, dashboard and analytics; the admin's Finance, a store's bills, marking paid and not paid | A delivery at `2026-08-31T22:00Z` is on September's bill; a refund in a later month comes off that month; `OPEN`, `NONE`, `DUE`, `PAID`; the paid day's range (422), paying twice (409) | M6, W6 |
| **S7 Talking** | Chats, tickets (both sides), Saba's replies and status changes | Only the two sides of a chat can read it; a reply reopens a waiting ticket; a closed one takes none; the opener is told | M7, W7 |
| **S8 Live updates** | `/events` and the publishing after each commit | A store's step reaches the shopper's open channel; one store never receives another's events | M8, W8 |
| **S9 Ready to host** | Rate limits reviewed, a test that every route is in the OpenAPI, production start-up checks (secrets present, docs off), README | A production start with a missing secret refuses to run | — |
| **S10 Push** (built 2026-09-29; the real send waits for Firebase's service-account file) | A migration for `device_tokens` (account, token, platform, language). `PUT /devices` (token, platform, language), sent at sign-in and again when the language changes; `DELETE /devices` (token) at sign-out. A push sender beside the SMS one: `PUSH_PROVIDER=log` while developing, `fcm` with Firebase's service-account file (HTTP v1) in production. Each push: the notification's title and text, `data {notificationId, targetType, targetId}` as strings, Android channel `saba_default`. Sent after the commit through the outbox, as the live updates are (§10), for the kinds in §2.0 S10 only, with the notification's own title, text and target in the phone's language. A token Firebase calls dead is deleted | Only the listed kinds are pushed; a rolled-back change pushes nothing; a push that fails never undoes the change; the push is in the phone's language; a token moves to whoever signs in on that phone, so one account's pushes never reach the next; a deleted account and a suspended shopper get none, while a suspended store's owner still does, since it still works its open orders (Q4); production starts without Firebase and logs that push is off (the user's call, 2026-09-29) | M10 |

**Why this order:** everything needs an account; products belong to approved stores; orders need products; returns and bills read orders. Each slice builds the app's side and the admin's side of the same data together, so every slice ends with something both front-ends can show.

**S10 needs from you before it starts:** a Firebase project (free) and its two config files, one for Android and one for iPhone; a paid Apple Developer account ($99 a year) and its push key, added to Firebase; and Firebase's service-account file (Firebase console, Project settings, Service accounts: the HTTP v1 API needs it; the old "server key" was shut down in 2024), kept out of git and named in `FCM_SERVICE_ACCOUNT_FILE`. No Apple key reaches the server: the APNs key is uploaded into Firebase. **M10, for the mobile session:** Firebase's messaging package; asking the user's permission, and working on without it; sending the push address at sign-in and on a language change, removing it at sign-out; a tap on a push opening what the same notification opens in the list. It is tried on a real Android phone (or an emulator with Google Play) and a real iPhone; Chrome can't. The admin web changes nothing. **No on/off switches in the app in v1:** its preferences screen was taken out for v1, so the phone's own settings silence Saba. **v2: a switch per kind of push in the app** (decided 2026-09-28). The phone can only turn every Saba push off, so a store tired of chat messages also loses new-order pushes, the one it can't miss. Huawei phones without Google services get no pushes; their notification list still works.

---

## 8. Switching the app and the web over

### 8.1 The app

**The switch is per build, not per screen.** `USE_MOCK_DATA` is set when the app is built, and the demo server answers every request or none. Mixing is not safe: the demo server keeps its own world, with its own ids and its own idea of who is signed in, so a real sign-in followed by demo products would pair a real account with stores that don't exist. So:

- **The demo build stays exactly as it is** until the very end: `flutter run`, as today. Demos keep working throughout.
- **The live build** points at this laptop:
  - Android emulator: `flutter run --dart-define=USE_MOCK_DATA=false` (the app already uses `http://10.0.2.2:3000/api/v1` there).
  - Chrome: the same flag; `http://localhost:3000/api/v1`.
  - A phone on the same Wi-Fi: add `--dart-define=API_BASE_URL=http://<laptop's IP>:3000/api/v1`.
- After each slice, its journeys are clicked through in the live build. Screens of slices not built yet show their error state, which is expected there.

| Step | After | Journeys in the live build |
|---|---|---|
| **M1** | S1 | Sign up as a shopper (the code prints in the server's console), sign out and in, forgot password, edit profile, addresses, delete the account. Sign up a store: it lands on "Waiting for approval". |
| **M2** | S2 | Sign in as that store: settings, logo, delivery terms, open and closed. Approve it from the web (W2); sign in again: approved. Its public page; the city chips. Delete the in-app admin (Q12). |
| **M3** | S3 | The store adds a product with photos and options and sends it; the web approves it; the shopper finds it in search, its category, Home and the store's page. A flash sale; the wishlist; filters and sorting. |
| **M4** | S4 | A two-store cart, a coupon, checkout (the first-order limit, a store that doesn't deliver), place the order. The store confirms, ships with its driver, delivers; the shopper sees each step (pull to refresh until M8), the order turns paid, the rating sheet asks. Also: cancel, a store's decline, refused at the door. |
| **M5** | S5 | A return: requested, approved, cash handed back; the stock is back. |
| **M6** | S6 | The dashboard and analytics; "What you owe Saba" after the web marks a month paid; closing the store shows what is still open. |
| **M7** | S7 | A chat both ways; a ticket, and Saba's reply from the web. |
| **M8** | S8 | The live-updates service: the store confirms on one device, the shopper's open screen changes on another. |
| **End** | all | Every journey passes live. Then your call: keep the demo build for sales demos (production builds already force it off), or delete the demo server. |

### 8.2 The web

The web has no switch today: each function in `src/data/*.ts` returns mock data. Its switch is the same idea as the app's.

1. **Once, at W1:** add `src/data/http.ts` (the base address from `VITE_API_BASE_URL`; the token; the envelope; a 401 refreshes once and then goes to sign-in; real errors mapped to the web's own `ErrorCode`, contract §1.4) and `VITE_USE_MOCK` (default `true`).
2. **Each data file gets its live version beside its mock,** chosen by the flag, in slice order. The contract says "the only thing to replace is the body of that function", and the screens don't change.
3. **The default build stays on the mock** until every step passes; then the default flips and the mock files go.
4. In the live build, pages not converted yet still show mock data, whose ids don't exist on the server. A link from one of them into a live sheet fails. That is only in the live build, only during the build-out.

| Step | After | Data files | Check |
|---|---|---|---|
| **W1** | S1 | `auth.ts` | Sign in by email or phone; a non-admin is refused and signed out (D1); sign-out; an expired token refreshes |
| **W2** | S2 | `stores.ts`, `queue.ts` (stores), `featured.ts` | Approve, reject, suspend, unsuspend; the store sees it in the app |
| **W3** | S3 | `products.ts`, `categories.ts`, `queue.ts` (products) | Approve, reject, take down, restore |
| **W4** | S4 | `orders.ts`, `dashboard.ts` | Orders, filters, the order sheet with each store's driver |
| **W5** | S5 | `customers.ts`, `people.ts`, `returns.ts` | Customers, suspension, cancellations and returns |
| **W6** | S6 | `finance.ts` | Finance matches the store's "What you owe Saba", month by month |
| **W7** | S7 | `tickets.ts` | Reply, change status; the shopper is told |
| **W8** | S8 | `lib/use-query.ts` | Another admin's or a store's change appears without a reload |
| **W9** | later | every list | Paging, once lists pass a few hundred rows (contract §5) |

### 8.3 Front-end changes the switch needs

| Where | Change | When |
|---|---|---|
| App | Read `PENDING` where the store's order screens look for `NEW` (Q6, D10; the list is in §8.4) | Before M4 |
| App | A live-updates service: open `/events` at sign-in, close at sign-out, announce each topic (BR, "How to switch the app over"); and reload the signed-in account when a `STORE` notification arrives (§9, item 7) | M8 |
| App | Delete the in-app demo admin and its reset (Q12, BUGS 145) | M2 |
| App | The coupon form takes a date's day before converting it: the server sends UTC, and `_dayOf` in `merchant_coupons_screen.dart` reads the UTC day, so a coupon starting on the 26th in Iraq (21:00 UTC on the 25th) opens as the 25th, and saving it moves it a day earlier. `.toLocal()` first. | Before M4 |
| App | Remove the three dead `ProductDraft` fields and the settings screen's `returnPolicy` (BUGS 202) | Any time |
| Web | `http.ts`, `VITE_USE_MOCK`, the live bodies (§8.2); refuse a non-admin at sign-in (D1); treat a 422 at sign-in as "wrong login" (§2.1 row 2) | W1–W8 |
| Web | Read the stream with `fetch` (§9, item 12) | W8 |
| Both, optional | Show the new fields: D7, D8, D11, D15, D16, D19, D21, D23, D27 (web); `storeParts[].status` (D9) and one box per language on the product form (BUGS 95) (app). None blocks the switch. | Any time |

### 8.4 For the mobile session: `PENDING` on the store's screens (Q6, D10)

The store's screens keep saying "New" / "جديد"; only the value they compare with changes. Found by searching the app for `'NEW'`:

| File | Line | Change |
|---|---|---|
| `lib/features/merchant/presentation/widgets/merchant_widgets.dart` | 31 | The workflow starts at `'PENDING'`, not `'NEW'` |
| same | 49 | The label case `'NEW' =>` becomes `'PENDING' =>`, still `l10n.orderStatusNew` |
| `lib/features/merchant/presentation/screens/merchant_orders_screen.dart` | 42 | The "To confirm" tab asks for `['PENDING']` |
| same | 244 | `isNew` compares with `'PENDING'` (the badge and the Decline button) |
| `lib/features/merchant/presentation/screens/merchant_dashboard_screen.dart` | 317 | "To confirm" opens the orders with `status: 'PENDING'` |
| `lib/features/merchant/presentation/merchant_providers.dart` | 153 | The fallback status is `'PENDING'` |
| `lib/core/mock/mock_api_interceptor.dart` | its six `'NEW'` | The demo writes and counts store parts as `PENDING` too (`_createOrder`, the seed's statuses, the dashboard count, `_stage`, `_storeMoved`), so demo and live agree |
| `lib/core/mock/mock_state_saving.dart` | its version | Raise the saved document's version, so a phone holding parts saved as `NEW` starts the demo fresh instead of losing them from the "To confirm" tab |
| Tests | `cash_checkout`, `merchant_orders`, `order_journey`, `order_status`, `store_delivery`, `two_stores`, `orders`, `account_switch`, `live_updates`, `merchant_journey`, `merchant_sweep` | `'NEW'` becomes `'PENDING'` |
| Keep | `lib/features/orders/domain/entities.dart:22`, `test/features/cart_and_orders_test.dart:209` | The shopper's reader still accepts `NEW` as pending: harmless, and its test stays |

Done when: the store's queue, badge, Decline button, dashboard count and tabs work in the demo as before, and a test that looks for `PENDING` in the "To confirm" tab fails with the old `'NEW'` put back.

Nothing else changes: tokens, refresh, `Idempotency-Key`, `Accept-Language`, paging and every path are already real in the app, and the web's screens read only its data functions.

---

## 9. Things in the front-ends that are awkward to serve

Found while reading the code, before the build. Each has the plan's answer.

1. **The server speaks the app's language.** The app shows `name`, `description` and the rest as they arrive; the demo swaps in `nameAr` and friends when the app asks in Arabic. So every shopper and store response goes through one localising step, and every sentence the server writes (every error message, every notification, Home's titles, delivery times, "Doesn't deliver to Erbil", coupon descriptions, "This code starts on Sep 28") exists in both languages. → `localise.ts` and `i18n.ts`; admins are never localised (§5.5).
2. **The store's order screens say `NEW`** where the decided value is `PENDING` (D10). → Q6.
3. **The shopper's order screens read a status per line**, not per store part (D9). → The server sends both: each line carries its part's status.
4. **Editing a price during a flash sale.** The store's form loads `price` (which is the sale price during a sale) and `originalPrice` (the normal price), and saves them back as they are, options included. → While a sale runs, the server reads a saved `price` as the sale price and `originalPrice` as the normal price, and adds the sale's discount back onto each option's price. The demo does the same arithmetic (`_endSale`). (The demo also loses a store's lasting `originalPrice` once a sale ends; separate columns keep it.)
5. **The product form writes one language into both** (BUGS 95): one box each for description and warranty, in whichever language the app is in. → As the demo: a field that is edited replaces both languages, until the form gets one box per language.
6. **Option names are free text** ("Color: Black", typed by the store, in one language). The demo translates nine fixed words (`_optionWordsAr`). → Stored as typed; the same nine words translated, for the seed's products. Arabic shoppers see an English-typed option in English.
7. **A store's approval doesn't reach an open app.** The dashboard's banner reads the signed-in account, which loads only at sign-in, and the app's live topics are just `orders` and `notifications`. → The notification arrives; the banner changes at the next sign-in until the app reloads the account on a `STORE` notification (§8.3).
8. **Photo addresses.** The demo's photos are files inside the app (`assets/images/…`); the web has its own copies; an emulator reaches this laptop as `10.0.2.2`, a browser as `localhost`. → The database keeps storage keys; the full address is made per request while developing, and from `MEDIA_BASE_URL` in production. The seed copies the demo photos into storage, so both front-ends load the same files.
9. **Orders from several stores** don't fit the admin's after-sales row, a shopper's `spent`, or `cancelledBy`. → Q7.
10. **Filter chips that filter nothing** (RAM, CPU, Screen size). → Q5.
11. **The demo's "Saba Support" chat** has no real counterpart: Saba has no chat inbox, and support is tickets. → Chats are shopper-and-store only; the Support chat disappears in the live build.
12. **A browser's `EventSource` can't send the `Authorization` header.** → The web reads the stream with `fetch`, which can; the app uses Dio's streaming.
13. **Search history.** The app asks the server for it and to clear it; the demo answers empty. The Arabic "clear" text promises it goes "from this device and from your account". → Served as the demo (§2.2).
14. **SMS.** Sign-up and reset need a real gateway for Iraq. → OTPIQ (Q11); the server log on this laptop until its key is set.
15. **`/customers/me` is every role's "who am I"**, a store owner's and an admin's included. → Kept as the path; the server answers for every role.
16. **The cart, checkout review and place-order must price identically,** Buy now included, or the shopper sees one total and pays another. → One pricing function (`DATABASE_DESIGN.md` §6), used by all three.
17. **The shared routes and the admin's language.** A browser sends `Accept-Language` by itself, so an admin whose browser is in Arabic would get `/categories` translated. → Admins are never localised, on any route.
18. **Demo ids and demo dates don't carry over.** `m-1`, `p-42`, `cu-5550142` don't exist on the server, and the demo's dates move with the calendar. → Neither front-end hard-codes an id (checked). The seed makes its own ids and dates relative to the day it runs.
19. **`deliveryInstructions`.** The app sends it at checkout; the demo ignores it and copies the address's instead. → The checkout's value wins, else the address's.
20. **The demo accepts any status from a store** (it could jump `NEW` to `DELIVERED`). → The transition table (`DATABASE_DESIGN.md` §5.3), matching exactly what the screens offer.
21. **A bill's paid day** is a day, sent as a moment. → 12:00 Baghdad of that day (§2.2).
22. **"Start the demo again"** in the in-app admin has no real twin. → Q12.
23. **A suspended shopper has no screen of their own.** → Signed out at their next request; sign-in shows "This account is suspended" in their language.

---

## 10. Live updates

What `BACKEND_READY.md` asks for, built as **Server-Sent Events** at `GET /events`.

- **Opened with the access token.** The server keeps, in memory, who has a stream open.
- **One small message per change**: `{"topic": "orders", "id": "123"}`. `topic` is all the app needs; `id` is welcome and ignored (BR).
- **Sent after the commit**, to the accounts the change is about, never to anyone else: a shopper never gets a store's events, and one store never another's.
- **At-least-once is enough.** A repeat costs one request; a lost one is covered by pull-to-refresh and by the app announcing every topic when it reconnects.
- **A comment line every 25 seconds** keeps proxies from closing a quiet stream.

| Change | The shopper | The store | Admins |
|---|---|---|---|
| Order placed | `orders` | `orders`, `notifications` | `orders` |
| A store's step | `orders`, `notifications` | `orders` | `orders` (and `bills` on a delivery, added at W8) |
| Cancelled by the shopper | `orders` | `orders`, `notifications` | `orders` |
| Return asked, answered, refunded | `orders`, `notifications` | `orders`, `notifications` | `returns` (and `bills` on a refund) |
| Store or product answered, suspended, taken down | — | `notifications` | `stores` or `products` |
| Chat message | `notifications` | `notifications` | — |
| Ticket reply or status | `notifications` | `notifications` | `tickets` |
| Bill marked paid or not | — | — | `bills` |
| Shopper suspended | — | — | `customers` |

*Ceiling:* held in one process's memory. With two server processes, the same code publishes through Redis instead (§12).

---

## 11. Tests

- **`node:test` through `tsx`**, calling the real app over HTTP, against a real MySQL database `saba_test`, migrated from zero at the start of each run and emptied between test files.
- **Per slice**, the cases listed in §7, written from the documents' rules: each rule's test names the document line it holds.
- **Every regression test is watched failing** with its fix removed before it counts: the rule this project already works by.
- **The concurrency tests** (`DATABASE_DESIGN.md` §5.4) run in every full run.
- **The formulas** (`DATABASE_DESIGN.md` §6) are tested against the demo's own arithmetic on the same inputs: NOVA10 on 145,000 headphones leaves 130,500 (BUGS 161); refunds come in steps of 250 (BUGS 175); a two-store order bills each store only its own part (D7b).
- **A route test**: every route is in the OpenAPI document, and every non-public route answers 401 without a token.

---

## 12. Deployable later without a rewrite

**Everything that differs between this laptop and a server is an environment value** (`.env` here, the host's settings there). `config.ts` reads and checks them at start; nothing else reads `process.env`.

| Variable | This laptop | Notes |
|---|---|---|
| `NODE_ENV` | `development` | `production` turns off `/docs` and the seed, and requires every secret |
| `PORT`, `API_PREFIX` | `3000`, `/api/v1` | What the app already expects |
| `DATABASE_URL` | `mysql://saba:…@127.0.0.1:3306/saba` | Port 3307 if you stay on 8.0 (Q2) |
| `DATABASE_URL_TEST` | `…/saba_test` | Tests only |
| `DB_POOL_SIZE` | `10` | |
| `DATABASE_CA_FILE` | Empty | The managed database's CA certificate (a file path): the server and the migrations then connect with TLS and check it (2026-09-30) |
| `JWT_SECRET` | 48 random bytes | |
| `OTP_SECRET` | 48 random bytes | |
| `CORS_ORIGINS` | Empty: in development any `http://localhost` port is allowed, because Flutter web picks a new port each run | In production, a list; nothing else is allowed |
| `MEDIA_STORAGE`, `MEDIA_DIR`, `MEDIA_BASE_URL` | `disk`, `./storage`, empty (made per request while developing) | **`s3` required in production** (2026-09-30, the reviewer's item 5: a server's disk is lost with it and isn't backed up); `MEDIA_BASE_URL` is then the bucket's CDN address |
| `S3_ENDPOINT`, `S3_REGION`, `S3_BUCKET`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY` | Empty | DigitalOcean Spaces (decided 2026-09-30): `https://fra1.digitaloceanspaces.com`, `fra1`, the bucket, a Spaces key pair. Each photo is uploaded public to read and cached for good (`aws4fetch` signs the requests) |
| `SMS_PROVIDER`, `OTPIQ_API_KEY`, `OTPIQ_CHANNEL`, `OTPIQ_SENDER_ID` | `log`, empty, `auto`, empty | `otpiq` and a `sk_live_` key in production (Q11) |
| `PUSH_PROVIDER`, `FCM_SERVICE_ACCOUNT_FILE` | `log`, empty | `fcm` and the service-account file's path; without them the server starts with push off and says so (S10) |
| `TRUST_PROXY` | `false` | **Required in production** (2026-09-30, the reviewer's item 4): the number of proxies in front, `1` behind one HTTPS proxy (Caddy on the same machine), or `false` when the server faces the internet. Unset behind a proxy, every shopper shares the proxy's address and one set of SMS and sign-in limits. `true` (trust any address a client claims) is refused in production |
| `LOG_LEVEL` | `info` | |
| `DOCS_ENABLED` | `true` | |

Fixed in the code, not settings (the plan once listed them as variables): the token lifetimes (`rules.ts`: access 15 minutes, refresh 30 days in the app and 12 hours in the admin web, Q3) and the upload limit (5 MB, `media.ts`).

**What changes on the day it is hosted, and nothing else** (the step-by-step is `DEPLOYMENT.md`; hosting decided 2026-09-30: DigitalOcean for the server, the database and the photos):

| Part | Now | Then |
|---|---|---|
| Files | `MEDIA_STORAGE=disk`: this laptop's disk | `MEDIA_STORAGE=s3`: DigitalOcean Spaces (built) |
| SMS | `SMS_PROVIDER=log`: the code goes to the server's log | `SMS_PROVIDER=otpiq` with the live key (built; the key is the client's) |
| MySQL | This laptop | DigitalOcean Managed MySQL, over TLS (`DATABASE_CA_FILE`); the same migrations |
| HTTPS | None on localhost | Caddy in front on the same machine; `TRUST_PROXY=1` |
| More than one process | In-memory events and rate limits | Redis behind `events.ts` and the rate limiter |
| Housekeeping | A timer in the process | The same function from the host's scheduler |
| The database's contents | This laptop's test and demo data | **Empty**: `npm run migrate`, then `npm run create-admin`. Never a copy of this laptop's database, and never `npm run seed` (demo data, development only) |
| Google Play's deletion page | `backend/public/delete-account.html`, served at `/delete-account`, with four `{{…}}` blanks | The blanks filled in (below), and its address given to Google Play |

**The deletion page: what to fill in** (the client's decisions; `backend/public/delete-account.html`, replace each blank everywhere it appears):

| Blank | What goes there | Example |
|---|---|---|
| `{{SUPPORT_EMAIL}}` | Saba's support email | `support@saba.iq` |
| `{{WHATSAPP}}` | Saba's support WhatsApp number, digits only, in international form, no `+` and no spaces (the page shows it with a `+` and links to `wa.me`) | `9647701234567` |
| `{{RECORDS_KEPT_EN}}` | How long orders, invoices, returns and bills are kept after a deletion, in English: the lawyer's answer | `5 years` |
| `{{RECORDS_KEPT_AR}}` | The same, in Arabic, read as "we keep them for …" | `خمس سنوات` |

Then, in the Google Play Console: **App content → Data safety → "Delete account URL"**: `https://<the API's domain>/delete-account`. The page names the app (Saba, سبأ), gives the steps (in the app, and through support without it), and says what is deleted, what is kept and for how long, as Google asks. Check it answers before submitting: no `{{` left on the page.

Also ready from day one: `/health` for the host's checks, a clean shutdown on `SIGTERM` (stop taking requests, finish the ones in flight, close the pool), structured logs on standard output, and no secret in the repository (`.env` stays out of git; `.env.example` lists every variable).
