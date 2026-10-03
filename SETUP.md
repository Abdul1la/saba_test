# Setup: Saba on a laptop

How to run all three parts on one computer: MySQL, the backend, the admin
website and the app, with demo data. To put Saba live, read
[DEPLOYMENT.md](DEPLOYMENT.md) instead.

Checked against the code on 2026-09-30. The project is built on Windows 11.
The commands work in PowerShell, and in a Mac or Linux terminal unless a line
says otherwise.

## 1. Install

| Tool | Version | For |
|---|---|---|
| Node.js | 24 (`backend/package.json` asks for 24 or newer) | the backend and the admin website |
| MySQL | 8.0 or 8.4 (the plan's target is 8.4 LTS) | the database |
| Flutter | stable, with Dart 3.12.2 or newer (`mobile/pubspec.yaml`); built here with Flutter 3.47.5 | the app |
| Android Studio | a recent one | the Android SDK, an emulator, and a JDK (17 or newer; Android Studio includes one) |
| Chrome | any | the admin website, and the app's web build |

npm comes with Node. Use npm: each folder has a `package-lock.json`.

If you copy the project folder by hand, leave out `node_modules/`,
`mobile/build/`, `mobile/.dart_tool/` and `mobile/android/local.properties`.
They are made again; `local.properties` holds the other computer's paths.

## 2. Create the databases

1. Sign in to MySQL as root: `mysql -u root -p` (add `--port 3307` or your
   port if MySQL is not on 3306). On Windows, `mysql` is not on the PATH at
   first: `SETUP_CHECKLIST.md` §3 adds it.
2. Run this, with a password of your own:

   ```sql
   CREATE DATABASE saba      CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
   CREATE DATABASE saba_test CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
   CREATE USER 'saba'@'localhost' IDENTIFIED BY 'choose-a-password';
   GRANT ALL PRIVILEGES ON saba.*      TO 'saba'@'localhost';
   GRANT ALL PRIVILEGES ON saba_test.* TO 'saba'@'localhost';
   ```

`saba` is for development. `saba_test` is emptied by every test run: never
point the tests at `saba`.

## 3. Start the backend

1. In `backend/`:

   ```
   npm install
   copy .env.example .env
   ```

   On a Mac or Linux: `cp .env.example .env`.
2. Make two secrets. Run this twice; each run prints one:

   ```
   node -e "console.log(require('node:crypto').randomBytes(48).toString('base64url'))"
   ```

3. Edit `backend/.env`:

   | Line | Write |
   |---|---|
   | `DATABASE_URL` | `mysql://saba:<your password>@127.0.0.1:3306/saba` |
   | `DATABASE_URL_TEST` | the same, but ending in `/saba_test` |
   | `JWT_SECRET` | the first secret |
   | `OTP_SECRET` | the second secret |

   `.env.example` has port 3307, because the author's MySQL runs there. Write
   your MySQL's port. A password with `@ : / #` in it must be URL-encoded.

   Leave the other lines as they are: they are the development values (SMS
   codes and pushes go to the server's log, photos to `backend/storage/`; the
   empty `S3_…` lines are for the live server).
4. Create the tables. It prints the migration files it ran:

   ```
   npm run migrate
   ```

5. Add the demo data (a laptop only, never the live server). It prints the
   demo accounts; every one uses the password `saba12345`. The seed only fills
   an empty database, and never deletes anything.

   ```
   npm run seed
   ```

6. Start the server. It listens on port 3000 and restarts when you change the
   code. Keep this window open: it shows the server's log.

   ```
   npm run dev
   ```

7. Check it: http://localhost:3000/api/v1/health answers with
   `"status":"ok"`. The API documents are at http://localhost:3000/api/v1/docs.

**An admin account.** The seed already made one: `admin@saba.app` (or
`0770 999 9999`), password `saba12345`. To add your own admin, run the command
below after the seed (the seed refuses a database that already has accounts).
It asks for the password (8 characters or more). This command is the only way
to make an admin: nobody can sign up as one.

```
npm run create-admin -- --name "Your name" --email you@example.com --phone "0770 000 0001"
```

**SMS codes on a laptop.** No SMS is sent (`SMS_PROVIDER=log`). When someone
signs up or asks for a new password, the code is printed in the server's log,
in a line with `SMS code for +964…: 123456`. A number gets one code a minute,
and 5 at most in an hour.

## 4. Start the admin website

1. Start the backend first (step 3).
2. In `website/`:

   ```
   npm install
   npm run dev
   ```

3. Open http://localhost:5173. It calls `http://localhost:3000/api/v1`. For
   another address, write `VITE_API_BASE_URL=<the address>` in
   `website/.env.local` (git ignores it) and start `npm run dev` again.
4. Sign in with `admin@saba.app` (or `0770 999 9999`) and `saba12345`. Only
   admin accounts can sign in here.

## 5. Start the app

1. Start the backend first (step 3).
2. In `mobile/`: `flutter pub get`.
3. Run it:

   | Where | Command | The app calls |
   |---|---|---|
   | Android emulator (start one first: Android Studio, Device Manager) | `flutter run` | `http://10.0.2.2:3000/api/v1` (10.0.2.2 is the laptop, seen from the emulator) |
   | Chrome | `flutter run -d chrome` | `http://localhost:3000/api/v1` |
   | A real Android phone, by USB, with USB debugging on | `adb reverse tcp:3000 tcp:3000`, then `flutter run --dart-define=API_BASE_URL=http://localhost:3000/api/v1` | the laptop, through the USB cable |

   The first two addresses are the defaults in
   `mobile/lib/core/config/app_config.dart`.
   `--dart-define=API_BASE_URL=…` replaces them. `adb` is in the Android SDK's
   `platform-tools` folder.
4. Sign in with a phone number and `saba12345`: `0770 123 4567` (a shopper) or
   `0771 123 4567` (a store). The app has no email sign-in. Saba's staff
   can't use the app: it signs them out and tells them to use the website.

Notes:

- The first Android build takes several minutes.
- In Chrome the app gets no live updates (by decision). Reload the page to see
  changes made elsewhere.
- The USB way needs no Wi-Fi or firewall change: `adb reverse` makes the
  phone's `localhost:3000` the laptop's. Run it again after you reconnect the
  cable. `WORK-LOG.md` records no run on a real phone yet.
- Open the `mobile/` folder in Android Studio, not the repository root.

## 6. Try one journey

1. In the app, sign up as a new store. The SMS code is in the server's log.
2. In the website, open the Approval queue and approve the store.
3. In the app, the store now has a notification: it is approved.

## 7. Tests

- Backend, in `backend/`: `npm test` (it empties and rebuilds `saba_test`,
  never `saba`) and `npm run typecheck`.
- App, in `mobile/`: `flutter test` (it runs against the app's demo server,
  so no backend is needed) and `flutter analyze`.
- After you add, remove or rename a key in
  `mobile/lib/core/localization/strings_en.dart` or `strings_ar.dart`, in
  `mobile/`: `dart run tool/generate_localizations.dart`. It stops with an
  error when the two files' keys differ.

## 8. When something goes wrong

| What you see | What to do |
|---|---|
| `npm run migrate` says `ECONNREFUSED`, `Access denied` or `Unknown database` | MySQL is not running, step 2 is not done, or the password or the port in `DATABASE_URL` is wrong. |
| The server stops at start with `Invalid configuration` | The line it names is missing or wrong in `backend/.env`. The secrets need 32 characters or more. |
| `npm run seed` says the database already has data | The seed fills only an empty database. To start again, as MySQL's root: `DROP DATABASE saba;` then the `CREATE DATABASE saba …` line of step 2 (the `saba` user keeps its rights). Then `npm run migrate` and `npm run seed`. |
| Every screen of the app shows an error and a Retry button | The backend is not running (check http://localhost:3000/api/v1/health), or the app calls the wrong address (step 5). |
| The Android build fails on paths from another computer | Delete `mobile/android/local.properties` and build again. Flutter writes a new one. |
| Gradle wants another Java | Point Flutter at Android Studio's JDK: `flutter config --jdk-dir "<Android Studio folder>/jbr"`. |

## 9. The demo, with no server

The app and the website each have a demo build. It answers from demo data
inside it: no backend, no MySQL.

- App, in `mobile/`: `flutter run --dart-define=USE_MOCK_DATA=true`. The
  sign-in screen lists demo accounts; any password works.
- Website, in `website/`: `npm run dev:demo` (the file `.env.demo` sets
  `VITE_USE_MOCK=true`). Sign in with `admin@saba.app` or `0770 999 9999` and
  any password. A page reload undoes your changes.
