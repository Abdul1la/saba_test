# Saba: project status

Status on **2026-09-30**. The details are in `BACKEND_PLAN.md`, `BUGS.md` and
`WORK-LOG.md`.

Hosting is **decided** (2026-09-30): DigitalOcean for the server, the database
and the photos. The Android upload key is made and kept by whoever publishes
the app.

## 1. Done

**Backend** (`backend/`)

- All planned slices are built: accounts and SMS codes (S1), stores (S2),
  catalogue and search (S3), cart, checkout and orders (S4), returns (S5),
  bills and Finance (S6), chats and support tickets (S7), live updates at
  `/api/v1/events` (S8), ready to host (S9), push notifications (S10).
- The tests run against a real MySQL database. One test checks that every
  route is in the API documents.
- In production the server refuses to start without: the two secrets
  (different from each other), `CORS_ORIGINS`, `TRUST_PROXY`, OTPIQ for SMS,
  and object storage for photos (`MEDIA_STORAGE=s3`, its `S3_…` settings and
  `MEDIA_BASE_URL`).
- Added after S10: reported reviews reach Saba; a store owner can delete their
  account (shoppers could since S1), and support can do it for either from the
  website; Google Play's account-deletion page at `/delete-account`.
- Added 2026-10-01: Saba's own pages for categories, Home banners and brands,
  on the server, in the app and on the admin website. Stores pick a brand or
  type one, checked with its product.

**App** (`mobile/`)

- It talks to the real server. The demo is a separate build
  (`--dart-define=USE_MOCK_DATA=true`).
- Every journey was walked against the real server (M1 to M9 in `WORK-LOG.md`).
- The app's side of push is built, with the Firebase project's two files
  (2026-10-01). The app's ID is `com.sabacompany.sabamarketplace` on Android
  and iOS. iPhones need §2, item 4.

**Admin website** (`website/`)

- Every page uses the real server (W1 to W8): the dashboard, the approval
  queue, stores, the featured stores on Home, products, orders, customers,
  returns, Finance, support tickets, reported reviews, account deletion, and
  live updates.
- The demo is a separate build (`npm run dev:demo`).

## 2. Left before launch

Each needs a decision, an account or a text from the owner or the client:

1. **Hosting** (decided). DigitalOcean: one Droplet runs the
   API and Caddy (automatic HTTPS; it also serves the admin website's files on
   its own subdomain). A Managed MySQL database (daily backups kept 7 days,
   restore to any point in them; it requires TLS, so the server needs
   `DATABASE_CA_FILE`). Spaces for photos. About $26 to $32 a month in all.
   It also needs a domain name. How: `DEPLOYMENT.md`.
2. **Photo storage.** In production the server requires object storage
   (`MEDIA_STORAGE=s3`) and refuses the default, photos on its own disk.
   Recommended: a Spaces bucket (item 1). It needs `S3_ENDPOINT`,
   `S3_REGION`, `S3_BUCKET`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY` and
   `MEDIA_BASE_URL` (the bucket's CDN address).
3. **Android signing.** Whoever publishes the app makes the upload key and keeps it (decided). With Play App
   Signing, Google holds the app signing key, and the upload key signs what
   is sent to Google Play. A release build reads the key from
   `mobile/android/key.properties` (made from `key.properties.example`; git
   ignores it and the `.jks` file) and stops with an error without it. Steps:
   `mobile/README.md` §6.
4. **Firebase, for push.** The project `saba-marketplace` exists, and the app
   has its two files. Still needed: an APNs key from Apple (a paid Apple
   Developer account) uploaded to Firebase, Push Notifications on the App ID
   `com.sabacompany.sabamarketplace`, and on the live server the
   service-account file (`PUSH_PROVIDER=fcm`, `FCM_SERVICE_ACCOUNT_FILE`).
   Without Firebase the server still starts, with push off, and says so in
   its log.
5. **OTPIQ live key** (`sk_live_…`), for SMS codes: `SMS_PROVIDER=otpiq`,
   `OTPIQ_API_KEY`, and `OTPIQ_CHANNEL` and `OTPIQ_SENDER_ID` if wanted. In
   production the server refuses to start without it.
6. **The public pages' blanks.** Replace each one everywhere it appears:
   - both pages: `{{SUPPORT_EMAIL}}`, `{{WHATSAPP}}` (digits only,
     international form, no `+`), `{{RECORDS_KEPT_EN}}`, `{{RECORDS_KEPT_AR}}`
     (how long order records are kept);
   - the privacy policy only: `{{COMPANY_NAME_EN}}`, `{{COMPANY_NAME_AR}}` (who
     runs Saba, as named on Google Play and the App Store), `{{POLICY_DATE}}`
     (the day the page last changed, in digits, like 2026-10-15).

   The pages are `backend/public/delete-account.html` (`/delete-account`) and
   `backend/public/privacy.html` (`/privacy`). The privacy policy names
   DigitalOcean as the host; if Saba is hosted elsewhere, change that line in
   both languages. When done, no `{{` is left on either page.
7. **A lawyer** reads the Terms and Privacy in the app and `privacy.html`, and
   says how long order records are kept (that answer fills the `RECORDS_KEPT`
   blanks).

From a review before launch, on 2026-09-30:

- Done: `TRUST_PROXY` is required in production (`1` behind Caddy);
  `DATABASE_CA_FILE` connects to the managed database with TLS and checks its
  certificate; `tsx` is a runtime package, so a server installs with
  `npm ci --omit=dev`; photos in object storage, required in production; a
  release of the app without `API_BASE_URL` refuses to start; an Android
  release is signed with the upload key, never the debug key (which Google
  Play refuses); report and block (Apple's rule 1.2) on the server.
- Also done on the server: the privacy policy at `/privacy`; the admin lists
  paged and searched in the database; an edited approved product goes back
  to review; a coupon's use comes back when its order never happens; saving a
  product never resets its stock; emails are no longer marked checked.
- Since done in the app and the website (2026-10-01): report and block, the
  website paging every list, and push in the app (it sends once Firebase's
  key is on the server, `DEPLOYMENT.md` 5.2).

On launch day:

- **The live database starts empty:** `npm run migrate`, then
  `npm run create-admin`. Never a copy of a laptop's database, and never
  `npm run seed` (demo data).
- Give Google Play the deletion page's address,
  `https://<the API's domain>/delete-account`. Give Google Play and the App
  Store the privacy page's address, `https://<the API's domain>/privacy`.
- Run the backend tests once on the live database's MySQL version, never on
  the live database (`DEPLOYMENT.md`, the end of 2.3; so far they ran on
  8.0.44).
- Cap requests per address at the proxy: Caddy with the `caddy-ratelimit`
  plugin (`DEPLOYMENT.md` 3.9).
- A staff member who leaves: `npm run suspend-admin` (`DEPLOYMENT.md` 9).

## 3. What only the demo data had

The live shop fills itself as stores and shoppers use it. These come only
from the demo seed:

- **Brands.** The live shop has none at first. Saba adds them on the admin
  website's Brands page; stores pick from that list or type a new name, which
  waits there, marked "New", until Saba checks it with its product. The app's
  filter hides its Brands part while none has a product on sale.
- **Category pictures.** The 13 categories come from the migrations; their
  pictures only from the seed. Saba adds them on the Categories page.
- **Featured stores.** None at first, so Home leaves that row out. Saba's
  staff choose them in the admin website.
- **Home banners.** None at first. Saba adds them on the Banners page: a
  picture, optional words in both languages, what a tap opens, on or off.
  With none, the server leaves the banner strip out, and Home shows the rest
  as usual.

Saba must fill these three before the launch (`DEPLOYMENT.md` 10.1).

- **The Arabic twins** (`description_ar`, `business_address_ar`, `area_ar`,
  `full_name_ar` and the other `*_ar` columns of stores, products, accounts
  and addresses). Stores and shoppers type in one language. The server keeps
  that text, the Arabic twin stays empty, and both languages show the same
  text. Product names are the other way round: every product must have an
  Arabic name, and the English name may be empty (English readers then see
  the Arabic one).

## 4. Known limits of v1

On purpose. The sources: `BACKEND_PLAN.md` §2.0, §7, §8.2 and §12,
`DATABASE_DESIGN.md` §9, and `WORK-LOG.md` (the app's web build).

- Cash on delivery only. Cards and wallets are v2.
- The Terms and Privacy are text inside the app. `privacy.html` repeats the
  Privacy text for the store listings: change one, change the other. One
  text on the server, edited on the admin website, is v2.
- Push has no switch per kind in the app: the phone's settings turn all of
  Saba's pushes on or off (a switch per kind is v2). Huawei phones without
  Google services get no pushes.
- One server process: live updates and sign-in limits live in its memory.
  More than one process needs Redis.
- The app's web build is for testing only. It gets no live updates (by
  decision); phones do.
- The server pages the admin lists (`page`, `perPage`); the website is
  switching to it.
- Not in v1: email sign-in or email checks in the app (it signs in by
  phone), product videos, product reviews (stores are rated instead),
  attribute filters, compare, delivery companies and tracking numbers,
  Saba-wide coupons. One commission rate for every store: 8%.
