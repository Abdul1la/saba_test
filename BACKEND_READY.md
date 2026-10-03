# Backend-ready: how the screens stay fresh

Written 2026-09-23, at step 3 of the bug fixing. It explains how a screen knows something changed, what the backend has to provide to take this over, and what must not be broken while doing it.

## The problem it solves

A screen used to show whatever it had loaded when it was opened. An order just paid for was missing from My orders, an order's details kept the status they were opened with, and the dot on the bell was worked out once when the app started and never again.

## How it works now

```
something changes ──▶ "orders changed"  ──▶ every screen showing orders loads again
                      "notifications changed" ─▶ the list and the dot on the bell
```

Three small pieces:

| Piece | Where | What it does |
|---|---|---|
| `LiveTopic` | `mobile/lib/core/network/live_updates.dart` | The subjects a screen can show: `orders`, `notifications`. |
| `LiveUpdates` | same file | Announces a subject, and hands out a stream of those announcements. |
| `liveTopicProvider(topic)` | `mobile/lib/core/providers/core_providers.dart` | Counts the announcements for one subject. Anything that watches it loads again each time. |

**Who announces today:** the app itself. `ApiClient` (`core/network/api_client.dart`) announces after every call that is not a read, and the path says which subject it was: anything with `order`, `checkout` or `return` in it changes **orders** (and leaves the other side a **notification**); anything with `notification` in it changes **notifications**.

**Who listens:** the providers behind the screens — My orders, an order's details, the notification list, the dot on the bell, and on the store's side its orders, one order, the tab counts and the dashboard. Each one simply watches its subject, so nothing in the screens themselves had to change.

**Coarse on purpose:** an announcement says only *which subject* changed, never what exactly. Whoever shows that subject asks the server again. That cannot go stale or half-apply, and it is the same whether the change came from this phone or from someone else.

**Pull-to-refresh is still there** on My orders, an order's details, the notifications, the store's orders and its order details, as a backup a person can always use.

## What today's version cannot do

The app only hears about **its own** writes. On one phone, with one account signed in at a time, that is everything the demo can show: when the store confirms an order, the store's own screens update at once, and the shopper sees it as soon as her side loads again (signing in reloads everything that belongs to an account — see step 1 in `WORK-LOG.md`).

What is missing is someone **else** changing something while you are looking at it: the real store confirming your order from their own phone. That needs the backend.

## What the backend has to provide

1. **A per-user event channel.** A WebSocket (`/ws`) or SSE (`/events`) opened with the access token, carrying one small message per change:

   ```json
   { "topic": "orders", "id": "ord-123" }
   ```

   `topic` is all the app needs; `id` is welcome and ignored for now.

2. **Events for at least these.** For the shopper: her order's status changed, a return was answered, a notification was created. For the store: an order was placed with it, a shopper cancelled, a return was asked for, a notification was created.

3. **Addressed to one account.** A shopper must never receive a store's events, and one store must never receive another's — the same rule the data itself follows.

4. **At-least-once is fine, exactly-once is not needed.** An announcement means "ask again about this subject", so a repeat costs one request and a lost one is covered by pull-to-refresh.

5. **Reconnect.** The app reconnects with a growing wait, and announces every subject once it is back, so anything missed while offline is picked up.

6. **If push is not ready at launch:** poll instead — ask the server "anything new for me since X?" every 30 seconds while a screen is open, and announce the subjects it names. Nothing above changes.

## How to switch the app over

1. Write one service that opens the channel and calls `announce(topic)` for each message. It needs nothing else from the app.
2. Start it when an account signs in, stop it at sign-out (`accountIdProvider` in `features/auth/presentation/auth_providers.dart` already says who is signed in).
3. Leave `ApiClient`'s own announcement in place: it keeps this phone's screens instant even before the server's message arrives.
4. Nothing else changes: the screens, the providers, and the subjects stay as they are.

## What must not be broken while doing it

- **Each account's data is its own.** Everything that holds one account's data follows `accountIdProvider`, and sign-out drops it (step 1).
- **An order is one record, two views.** The shopper's order and the store's part of it always hold the same status; only the words differ ("جديد" on the store's side). See `PROJECT_MAP.md`.
- **Only the store moves an order along.** A new order is pending on both sides until its store confirms it (step 2).
- **Cash is paid at the door**, so an order is marked paid only when every part has been delivered.
- Demo mode keeps its own copy of all this on the phone (`core/mock/mock_state_saving.dart`). When the backend is ready, `USE_MOCK_DATA=false` turns the whole demo server off, saved copy included.

## Flash sales: the price is worked out when it is read

A store puts one of its products on a flash sale from its product list: a
sale price and an end. No review; the store owns its price. The app sends

```
POST   /merchants/me/products/:id/flash-sale   { "salePrice": 45000, "saleEndsAt": "2026-09-24T18:00:00Z" }
DELETE /merchants/me/products/:id/flash-sale   (ends it now)
```

- **One new field on a product, `saleEndsAt`.** The price before the sale
  becomes `originalPrice` and the sale price becomes `price`; while a sale
  runs, changing it keeps the original. A product sold in options takes the
  same amount off each option.
- **Refuse:** a sale price that is not a multiple of 250 IQD, or not lower
  than the price before the sale; an end that is not in the future; a
  product that is not the store's own. Field errors under `salePrice` and
  `saleEndsAt`.
- **The end has to be honoured when the price is read.** Once `saleEndsAt`
  has passed, every read - Home, a product's page, search, the cart, and
  above all checkout - must give the price from before the sale, with no
  `originalPrice` and no `saleEndsAt`. Either work it out on every read, or
  run a scheduled job that ends sales on time *and* still check on read, so
  a job running late never sells at an ended sale's price. The demo server
  ends any sale that is over before it answers each request
  (`_endSalesPast` in `core/mock/mock_api_interceptor.dart`).
- **Home's `FLASH_SALE` section:** every approved, shown, in-stock product
  whose sale has not ended, from every store, at an open store, the
  soonest to end first; the section's `endsAt` is the soonest end. When the
  countdown reaches zero the app asks for Home again.

## Routes and fields the app now reads (2026-09-25)

Not yet in `website/API_CONTRACT.md` (the web session owns it):

- `GET /stores/cities`: the governorate codes that have an open, approved
  store, e.g. `["BAGHDAD", "BASRA"]`. Home's city chips (D28): they can no
  longer come from the featured stores rail.
- Every product summary and cart group's `merchant` carries the store's
  current `governorate` and `logoUrl`, and a product's details carry
  `categoryName` (and `categoryNameAr`).
- `GET /merchants/me/store` returns `logoUrl`; `PUT` with `"logoUrl": null`
  removes it.
- The store dashboard's `rejectedCount`: products Saba did not approve.
- `GET /products/{id}` sent to the product's own store carries `isListed`
  (false when buyers cannot see it: hidden, waiting, rejected or taken
  down); a shopper never gets such a product. Missing means true.
- Already in the contract, now in the app's demo: `customerId` on every
  order (the shopper's and each store's copy; §5) and a ticket's
  `openedBy` `{kind, name, phone, storeId?}` (§3.8). A real server takes
  both from the session.
- Chart points (the dashboard's `salesSeries`, Analytics' `series`) carry
  `from` (ISO start) and `unit` (`DAY`, `WEEK`, `MONTH`); the app names
  them. The dashboard's is the last six months. Its `orderCount` and
  `orderCountDelta` are delivered orders, as Analytics' month.
- Order lines carry `paidUnitPrice`: the unit price after the store's
  coupon, shared over its lines by price. A return refunds that.
- A return is refused (422) for a line that already has one, or for more
  than was bought; a store's decline needs a `reason` code (`USED`,
  `INCOMPLETE`, `NOT_AS_SAID`, `OTHER`), kept as `rejectionReason`.
- The cart's `coupon` carries `applies` (false when it takes nothing off)
  and `minOrderAmount`; an order counts a coupon use only when it took
  something off. A code not started yet says when it starts.
- An order's status is its slowest store's step, but `CONFIRMED`, not
  `PENDING`, once any store has taken it.
- An unknown order and its invoice are 404, not an empty 200.
- **Refuse a sign-up without a valid verification token** (BUGS 108, 168):
  the app now needs the token to open the form, but a made-up one passes.
- `POST /orders/{id}/received` answering every delivered store settles the
  rating sheet's "did it arrive": `rating-due` skips an order whose
  delivered stores are all answered.

## Sharing a product: what is real now (2026-09-25)

**Today.** The share button on a product page copies two lines: the
product's name and `https://saba.app/product/<id>`
(`product_detail_screen.dart`, `_share`). Nothing is shared through the
phone's share sheet; it is a copy.

**Pasted into a new tab it does not open the product.**

- `saba.app` is written into the app and set up nowhere in this project.
  Whoever owns it, and whatever it serves, it is not a Saba page.
- Even hosted there, the path would not route: the web build uses hash
  addresses (`/#/product/p-1`), not `/product/p-1`.
- The ids are the demo's (`p-1`); the backend's will differ.
- The apps answer only `saba://...` links (Android intent filter, iOS URL
  scheme), used for email verification. Such a link works only where the
  app is installed, and chat apps such as WhatsApp do not make it tappable.

**What a working share link needs.** Each of these is required, not
optional:

1. A domain Saba owns, on HTTPS (for example `saba.iq`).
2. A public product page at `https://<domain>/product/<id>`, served by the
   backend. It is what someone without the app sees, so it must show the
   product (name, photo, price, store) or say plainly that it is gone. It
   needs Open Graph tags (title, image, description) so WhatsApp, Telegram
   and Facebook show a preview. Either server-rendered, or the Flutter web
   app with path addresses (`usePathUrlStrategy`) and the server sending
   every `/product/...` path to `index.html`.
3. **Android App Links.** An `https` intent filter for the domain with
   `android:autoVerify="true"` and a `/product` path, and
   `https://<domain>/.well-known/assetlinks.json` naming the package and
   the SHA-256 fingerprint of the release signing key (Play App Signing's
   key once on the Play Store).
4. **iOS Universal Links.** The Associated Domains entitlement
   (`applinks:<domain>`), which needs the Apple Developer account and a
   provisioning profile, and
   `https://<domain>/.well-known/apple-app-site-association` (team id and
   bundle id, `/product/*`), served as JSON over HTTPS with no redirect.
5. **The app.** Build the link from one configured base address, not a
   string in the screen. The router already opens `/product/<id>`, and
   says "This product is not available" for an unknown one; it must also
   accept the https links from the two OSes.
6. **Without the app.** The page in 2 is the fallback, with store badges
   once the apps are listed.
7. Stable product ids from the backend, and a public read of a product that
   needs no sign-in.
8. Optional: the phone's share sheet (a `share_plus` dependency) in place
   of a copy.

**Possible before the backend and a real domain: nothing that makes a
shared link work.** Every piece above hangs on the domain, the public
product page, or the signing keys and Apple account. What could be done
now is preparation only, such as moving the base address into config. The
user's decisions (2026-09-25): build nothing yet, and hide the share button
until the domain, the public product page and the deep link files are in
place (BUGS.md 180). The product page has no share button now.

## Deleting a store's account (2026-09-29)

Apple (Guideline 5.1.1(v)) and Google Play both require that every account
made in the app can be deleted from the app, and both refuse closing or
deactivating instead. "Close my store" (2026-09-25) was only closing, so it
is gone from Edit Profile. The dashboard's switch still closes a store for
now.

**In the app.**

- A store's Edit Profile ends with "Delete account". It asks first, saying:
  - the store closes now;
  - what the deletion waits for. The last bill is the month of the last
    delivery, due when that month ends, so it takes at least until then;
  - an SMS says when it is done;
  - what is kept.
- The card then shows:
  - since when it was asked;
  - what is still left: orders, returns to settle, the return window, and
    what is owed. With nothing left, "deleted within the hour";
  - the SMS line;
  - "Keep my account".
- While it waits, the dashboard says "Closed: account being deleted" and has
  no switch.
- A shopper still deletes on the spot, refused while an order is open (Q9).

**The contract.** Sent to the backend session; the demo server answers it.

- `POST /merchants/me/deletion` → `StoreDeletion`. Asks for the deletion.
  Idempotent, and allowed for any store status. The store closes at once.
- `GET /merchants/me/deletion` → `StoreDeletion`. `requestedAt` is null when
  nothing was asked.
- `DELETE /merchants/me/deletion` → `{}`. Takes the request back while it
  waits. The store stays closed until the owner opens it.
- `StoreDeletion = {requestedAt, openOrders, openReturns, returnsOpenUntil,
  owed, currencyCode}`.
- `GET /customers/me` carries `merchant.deletionRequestedAt`.
- While it waits, `PATCH /merchants/me/store/open {"isOpen": true}` is
  refused (409).

**The server's side** (backend session):

- The hourly round deletes the account once:
  - no order or return is open;
  - the return window has passed;
  - nothing is owed.
- The owner's details go as a shopper's do. The store leaves the shop for
  good.
- Orders, invoices, returns and bills stay, with the store's name and the
  delivery details each order was sent to.
- One SMS goes out before the number is cleared (OTPIQ `custom`), in both
  languages. It is the only notice: no push, since the devices go with the
  account.
- The user's decisions (backend 9d255d9):
  - The last bill is the month's own bill, due when the month ends and
    marked paid as any other. There is no early bill and no write-off.
  - Never paid means never deleted: the store stays closed, and Saba keeps
    the owner's number to collect.
  - Product photos stay, since past orders show the same files. The logo
    and banner are deleted.
- A deleted store's number signs up again as new (sign-in says "no
  account"). Its chats keep the store's name, as orders do. Its replies to
  reviews go with its page.

**Terms and Privacy** (BUGS 183) now say this, not "ask Support".

**Google's public deletion page, once there is a domain.** Google Play also
wants a web page where anyone can ask for their account to be deleted
without the app. It is linked from the Play Console's Data safety form. The
page must:

- load without errors, and name the app (Saba) or its developer as the Play
  listing does;
- put the way to ask for deletion first on the page, easy to find;
- let someone ask without reinstalling the app;
- give the steps in the app too: Account → tap your name → Delete account;
- say what is deleted, what is kept and for how long, in the same words as
  Privacy.

How someone asks is a choice for later. There are two ways:

- **The least:** a Support contact (email or WhatsApp) for a request with
  the phone number. Support checks it and deletes from the admin web, which
  has no such button yet.
- **Better:** the phone number and an SMS code on the page, then the same
  deletion as in the app. This needs a server route that works without
  signing in, and a page on the website.

## The ten things: what the backend must match (2026-09-26)

- **Related products** (`GET /products/{id}/related`): the product's own
  category only, listed and not the product itself. The store and the
  brand do not count.
- **"In stock only"** (`inStock=true` on `/products`): the stock as it is
  now, after orders and the store's own changes, not the catalogue's first
  count.
- **Each store's part of an order** (`storeParts[]`): also its
  `deliveryTime` (`1_2_DAYS`, ...), for "Expected: 1–2 days" in its box
  before it ships. The order's own `status` must stay the slowest store's,
  as My orders shows it.
- **Numbers typed with commas**: the app sends plain numbers; nothing
  changes on the server.
- **Notifications** (BUGS.md 194): every one carries a target the app
  opens when it is tapped, `entityType` + `entityId`, in both languages:
  - `ORDER` + the shopper's order id: the order's steps.
  - `STORE_ORDER` + the store's part id (`/merchants/me/orders/{id}`): a
    new order, an order cancelled by the shopper, a return requested, a
    parcel not received.
  - `RETURN` + the return id: a return approved, declined, cash given back.
  - `STORE_PRODUCT` + the product id: a product approved, rejected or taken
    down.
  - `STORE` (no id needed): the store approved or rejected.
  - `CONVERSATION` + the chat id: a chat message, to the other side, both
    ways (not for chats with Support).
  - `TICKET` + the ticket id: **still to build** - Support's reply to a
    ticket, and a ticket's status changing. The demo has no route for
    Support to reply, so neither is sent today.
  - A phone number in a notification's words is written as
    +964 770 111 2222.


## Push notifications, the app's side (S10 / M10, 2026-09-28)

Built in the app before Firebase, so the server side can be finished and
tested against it. Agreed with the backend session.

- **`PUT /devices`**, signed in: `{"token", "platform": "ANDROID" | "IOS",
  "language": "en" | "ar"}`. Sent after sign-in, whenever the push service
  gives the phone a new address, and when the app's language changes.
  Idempotent; the same token moves to whoever signs in on that phone.
- **`DELETE /devices`**, signed in: `{"token"}`. Sent at sign-out before the
  session is revoked; best effort (5 seconds), sign-out never waits on it.
- **Each push**: `notification {title, body}` in the device's language, and
  `data {"notificationId", "targetType", "targetId"}` (strings). A tap opens
  exactly what the same notification opens in the list
  (`notification_destination.dart`) and marks it read. Android channel:
  `saba_default`.
- **In the app today**: `core/push/push_service.dart` (`PushService`, with
  `NoPush` standing in, and `PushDevice`), `push_registration.dart`, the
  sign-out step in `AuthController.signOut`, and the tap in `app.dart`. The
  web and desktop builds send nothing. The demo server keeps the addresses
  like the real one (`pushAddresses`).
- **Firebase is in** (2026-09-30):
  - `core/push/firebase_push.dart`: token, token refresh, permission, and
    taps, including the one that opened the app, handed over once.
  - `startPush()` in `main.dart`: a build without the config files, the web,
    desktop and the demo run with `NoPush`.
  - Android: Google's plugin only with `app/google-services.json`, and the
    `saba_default` channel made in `MainActivity`.
  - iOS: `Runner.entitlements` (`aps-environment`) and the remote-notification
    background mode. The app now needs iOS 15.0 (13.0 before), as Firebase
    does.
  - The project's two files are in the app (2026-10-01). The app's ID is
    `com.sabacompany.sabamarketplace` on both platforms, as in Firebase.
  - What is left: Apple's push key in Firebase, Push Notifications on the
    App ID, and the live server's service-account file (mobile/README.md,
    Builds, "Push (Firebase)").
