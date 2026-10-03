# Saba backend

Node.js 24, TypeScript, Express 5, MySQL 8.0 on port 3307 for now (8.4 later: a new address in `.env`, then `npm run migrate`). The plan is `../BACKEND_PLAN.md`; the schema `../DATABASE_DESIGN.md`; the laptop setup `../SETUP_CHECKLIST.md`.

## Run it

```powershell
npm install
copy .env.example .env      # then the saba user's password in both addresses, and two secrets
npm run migrate             # brings the database in DATABASE_URL up to date
npm run dev                 # http://localhost:3000/api/v1/health, docs at /api/v1/docs
npm test                    # empties and rebuilds saba_test; never touches saba
npm run typecheck
npx tsx test/prove-schema.ts      # drops each constraint in turn; every one must be caught
npx tsx test/prove-code.ts accounts  # breaks each rule in the code in turn; every one must be caught
                            # suites: accounts, sms, fold, pricing, catalog, money, bills, buying, returns, config, stores (never two at once)
npm run create-admin -- --name "Saba admin" --email admin@saba.app --phone "0770 999 9999"
npm run seed                # the demo world (stores, products, orders, coupons, reviews, returns, paid bills, tickets, chats) on an empty database,
                            # or the later slices' parts on one seeded before them; never deletes; password saba12345
npm run housekeeping        # one run of the hourly clean-up (the server runs it by itself; this is for a host's scheduler)
```

**SMS codes** go to the server's log while developing (no SMS gateway yet): look for `SMS code for +964…`.

**Live updates**: `GET /api/v1/events` with the access token, Server-Sent Events (`BACKEND_PLAN.md` §10).

## Hosting it

**The step-by-step guide is [`../DEPLOYMENT.md`](../DEPLOYMENT.md)** (DigitalOcean: a Droplet with Caddy and systemd, Managed MySQL, Spaces). What follows is only what this folder decides.

- **The live database starts empty:** `npm run migrate`, then `npm run create-admin`. Never a copy of this laptop's database, and never `npm run seed`: this laptop's holds test stores, accounts, orders, reviews and searches (a "M2 Store 72587" selling, "M3 Phone" as the top search) that shoppers would see.
- **The public pages** the app stores link to: `public/delete-account.html` at `/delete-account` (Google Play's deletion page) and `public/privacy.html` at `/privacy`. Fill in their `{{…}}` blanks before launch (`DEPLOYMENT.md` §6 lists them).
- Every difference between this laptop and a server is an environment value; `.env.example` lists them all.
- `NODE_ENV=production` refuses to start without: `JWT_SECRET` and `OTP_SECRET` (different, 32+ characters), `CORS_ORIGINS`, `SMS_PROVIDER=otpiq` with its key, `TRUST_PROXY` (the number of proxies in front: `1` behind Caddy; `true` is refused), and `MEDIA_STORAGE=s3` with its `S3_…` settings and `MEDIA_BASE_URL`. It names the variable and never prints a value. The docs are off unless `DOCS_ENABLED=true`.
- A managed database needs TLS: `DATABASE_CA_FILE` is the path to its CA certificate.
- Push is optional: without `PUSH_PROVIDER=fcm` and `FCM_SERVICE_ACCOUNT_FILE` (Firebase's service-account JSON, kept out of git), the server starts and logs "Push notifications are OFF".
- `/api/v1/health` for the host's checks. On `SIGTERM` it stops taking requests, ends the live streams, finishes the rest and closes the database pool.
- One process only: the live updates and the sign-in limit live in memory; a second process needs Redis first (`BACKEND_PLAN.md` §12).

## Rules

- Every schema change is a new file in `migrations/` (`0004_…sql`). A migration that has run is never edited: the runner refuses it.
- A migration that fails part-way leaves what it created (MySQL can't roll back `CREATE TABLE`). On a development database: drop it, create it empty, migrate again.
- Only `src/config.ts` reads the environment.
- The server's own words live in `src/lib/i18n.ts`, in both languages; a missing Arabic entry fails the build and the tests.
