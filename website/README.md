# Saba admin (web)

Saba's admin panel. It talks to the backend at `VITE_API_BASE_URL`: the dev server defaults to `http://localhost:3000/api/v1` (the server in `backend/`), and a build without it is refused. The demo build answers from mock data in `src/data/` instead, with no server at all.

```bash
npm install
npm run dev          # http://localhost:5173, the real server (start it first: npm run dev in backend/)
VITE_API_BASE_URL=https://… npm run build   # type-check and build to dist/, for the real server at that address
npm run dev:demo     # the demo: mock data, no server
npm run build:demo   # the demo, built to dist/
```

- **The real server:** sign in with `admin@saba.app` or `0770 999 9999`, and `saba12345` (the seed's admin).
- **The demo:** `admin@saba.app` or `0770 999 9999` with any password, as in the mobile app's demo. The demo mode is `.env.demo` (`VITE_USE_MOCK=true`).

## How it went live

Each data file got its live version beside its mock, in steps (BACKEND_PLAN.md §8.2): sign-in (W1; `src/data/http.ts`, `auth.ts`), stores, the approval queue and the featured rail (W2; `stores.ts`, `queue.ts`, `featured.ts`), products and categories (W3; `products.ts`, `categories.ts`), orders and the dashboard (W4; `orders.ts`, `dashboard.ts`), customers, cancellations and returns (W5; `customers.ts`, `returns.ts`), Finance and the bills (W6; `finance.ts`), support tickets (W7; `tickets.ts`), live updates (W8; `events.ts`: while signed in, the screens a change is about reload by themselves), Reported reviews (`reviews.ts`: reviews shoppers report in the app, removed or dismissed here; API_CONTRACT.md §3.12), Reports (`reports.ts`: reported products, stores and chats, marked handled once Saba has acted, or dismissed; §3.13), and the shop's Categories, Brands and Home banners (`catalog.ts`; §3.14), which Saba fills before the launch. Sign in with `admin@saba.app` or `0770 999 9999` and `saba12345`. Every page is live; the default switched from the mock to the real server once all eight steps passed. The six long lists (orders, customers, products, stores, tickets, cancellations and returns) page on the server, 50 rows a page (W9; `httpPage` in `http.ts`, `Pager` in `blocks.tsx`; API_CONTRACT.md §1.3).

## Where things are

- `src/data/`: one file per resource. Every function is async and returns the shapes in `types.ts` (the mobile app's field names and statuses): from the server through `http.ts`, or in the demo from its mock body beside it. The screens don't know which.
- `src/pages/`: Dashboard, Approval queue, Stores, Products, Orders, Sign-in.
- `src/components/`: the app frame, the detail sheets, the approve/reject actions and the design blocks (`blocks.tsx`). `ui/` is shadcn/ui.
- `src/lib/i18n.tsx`: every word in English and Arabic. The status words are the mobile app's.

## The demo's mock data

- The 8 stores, 56 products, 7 categories and 16 orders mirror `mobile/lib/core/mock/`. Extra items made up for the web are marked `// web-only demo`.
- Add `?mockError` to any address to make every request fail and see the error states.
- Changes made in the panel go back to their first state on a page reload.
- Photos (`public/demo/`) and fonts (`public/fonts/`) are copies of the mobile app's files. DM Serif Display, Amiri and IBM Plex Sans Arabic are all under the SIL Open Font License.

`TODO.md` lists what comes next and what is not in this version.
