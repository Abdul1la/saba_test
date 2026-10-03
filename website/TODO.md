# Saba admin web: to do

Every page works against the real server in `backend/`. That covers sign-in with tokens, every list, sheet and action, and live updates (`src/data/events.ts`). Everything the old version of this file asked the backend for (fields, endpoints, decisions) is built: `API_CONTRACT.md` has each route. The demo build (`npm run dev:demo`) still answers from the mock in `src/data/`. `README.md` says how to run and build each.

## Not in this version

- **Staff accounts.** There is one admin today. Staff accounts bring:
  - a record of who did what: who approved, rejected or took something down, and who undid a payment;
  - which admin wrote each support reply.
- **Partial payments**: several payments against one month's bill. Today a whole month is marked paid.
- **The flash sale.** Featured stores and Home banners are done.
- **Rule pages**: terms, privacy and returns, in both languages.
- **Cities**: the list of governorates stores can deliver to.
- **Analytics**: growth over time, top stores and products, orders per city.
- **Admin notifications**: announcements to shoppers or stores.
- **Changing the commission rate.** It is 8% today.
- **Payouts.**
- **Delivery companies and tracking numbers.** In v1 each store delivers with its own driver, whom it names when it ships.
- **Dark theme.** The mobile app has one.
