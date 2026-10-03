# Saba

Saba (سبأ) is a marketplace for Iraq. Many stores sell in one app. Shoppers pay
cash when the order arrives, and each store delivers with its own driver. Saba's
staff approve stores and products, answer support, and bill each store a
monthly commission.

| Who | Uses |
|---|---|
| Shoppers | the mobile app |
| Store owners | the same mobile app (its store screens) |
| Saba's staff | the admin website |

The app and the website are in English and Arabic.

## The three parts

State on 2026-09-30:

| Folder | What it is | State |
|---|---|---|
| `backend/` | The API: Node 24, TypeScript, Express 5, MySQL 8 | Built and tested. All planned slices (S0 to S10) are done, and the tests run against a real MySQL. Push sends through Firebase once its key file is on the server (`DEPLOYMENT.md` 5.2). |
| `mobile/` | The Flutter app for shoppers and stores | Connected to the backend. Every journey was walked against the real server (M1 to M9). |
| `website/` | The React admin website for Saba's staff | Connected to the backend. Every page uses the real server (W1 to W8). |

How the parts fit:

- The app and the website call the same API (`/api/v1`). Data is kept in MySQL. Photos are kept on the server's disk on a laptop, and in object storage when live.
- The server decides prices, stock, commission and who may do what. The front ends only show it.
- Live updates reach open screens through `/api/v1/events`.
- SMS codes go through OTPIQ, and pushes through Firebase. On a laptop, both only go to the server's log.

The app and the website also have a demo build that needs no server
([SETUP.md](SETUP.md), last section).

## Not live yet

What is left before launch (details in [PROJECT-STATUS.md](PROJECT-STATUS.md)):

1. The accounts: DigitalOcean (decided 2026-09-30: the server, the database and the photos), a domain, Google Play and Apple.
2. The Android upload key, made and kept by whoever publishes the app (decided 2026-09-30).
3. Firebase, for push notifications.
4. The OTPIQ live key, for SMS codes.
5. The blanks on the public pages (support email, WhatsApp number, how long records are kept, the company's name, the policy's date), and a lawyer's reading of the Terms and Privacy.

[DEPLOYMENT.md](DEPLOYMENT.md) lists exactly what to ask the client for.

## Read more

| File | What is in it |
|---|---|
| [DEPLOYMENT.md](DEPLOYMENT.md) | Putting Saba live: server, database, photos, app builds |
| [SETUP.md](SETUP.md) | Running all three parts on a laptop |
| [PROJECT-STATUS.md](PROJECT-STATUS.md) | What is done, what is left, what v1 does not do |
| [BACKEND_PLAN.md](BACKEND_PLAN.md) | The backend plan: decisions (§2), endpoints (§6), build order (§7), hosting values (§12) |
| [DATABASE_DESIGN.md](DATABASE_DESIGN.md) | The database schema |
| [website/API_CONTRACT.md](website/API_CONTRACT.md) | The API the admin website uses |
| [backend/README.md](backend/README.md), [mobile/README.md](mobile/README.md), [website/README.md](website/README.md) | The commands of each part |
| [BACKEND_READY.md](BACKEND_READY.md) | What the app expects for live updates and push |
| [BUGS.md](BUGS.md), [WORK-LOG.md](WORK-LOG.md) | History: every bug found, every step taken |

Older, and partly out of date: `PROJECT_MAP.md` (a map of the app's code, from
before the backend), `docs/` (the app's first architecture notes), and
`Production_Marketplace_Master_Development_Prompt.pdf` (the first
specification; v1 differs from it, and the plan and the schema say where).

## Demo accounts

These exist only in a database filled by `npm run seed` (demo data, for a
laptop). The live database never has them. Every one uses the password
`saba12345`.

| Account | Phone | Email |
|---|---|---|
| Shopper: Amina Saleh | 0770 123 4567 | shopper@saba.app |
| Store: Nova Electronics (Omar) | 0771 123 4567 | merchant@saba.app |
| Store: Atlas Home (Layla) | 0780 123 4567 | merchant2@saba.app |
| Saba admin (website only) | 0770 999 9999 | admin@saba.app |

The app signs in with the phone number. The website takes the email or the
phone.

## Folders

```
saba_test/
├── backend/    the API (migrations/ is the schema; scripts/ is migrate, seed, create-admin, housekeeping; public/ the public pages)
├── mobile/     the Flutter app: open this folder in Android Studio, not the root
├── website/    the admin website
├── design/     the design system and screen designs
├── docs/       older notes on the app
└── *.md        the documents above
```
