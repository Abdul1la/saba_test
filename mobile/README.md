# Saba Marketplace — Mobile App

The Flutter client for the Saba multi-vendor marketplace. It serves **customers**
and **merchants**. Administrators use the separate React web panel, not this app.

Built against the platform specification in `Production_Marketplace_Master_Development_Prompt.pdf`.

---

## 1. Prerequisites

| Tool | Version used | Check |
|---|---|---|
| Flutter | 3.44.1+ (stable) | `flutter --version` |
| Dart | 3.12+ (bundled) | `dart --version` |
| Android Studio / Xcode | for device builds | `flutter doctor` |

Run `flutter doctor` and resolve anything it flags before continuing.

## 2. Installation

```bash
cd mobile
flutter pub get
```

## 3. Configuration

The app takes no secrets. The only build-time settings are the API base URL and
the environment name, both passed with `--dart-define`:

| Define | Default | Purpose |
|---|---|---|
| `API_BASE_URL` | see below | REST base URL, **including** `/api/v1` |
| `APP_ENV` | `development` | `development` \| `staging` \| `production` |

When `API_BASE_URL` is not supplied the app picks a sensible local default:

| Target | Default base URL |
|---|---|
| Android emulator | `http://10.0.2.2:3000/api/v1` |
| iOS simulator, desktop, web | `http://localhost:3000/api/v1` |

Network request logging is on outside production and **never** prints tokens,
passwords or card fields — see `core/network/logging_interceptor.dart`.

## 4. Running

```bash
# Local backend, default URL
flutter run

# Explicit backend
flutter run --dart-define=API_BASE_URL=https://api.example.com/api/v1

# Staging build
flutter run --dart-define=APP_ENV=staging \
            --dart-define=API_BASE_URL=https://staging.example.com/api/v1
```

### Demo mode

The app talks to the **real server** unless a build asks for the demo, as
the admin web does. The demo (`--dart-define=USE_MOCK_DATA=true`) answers
every request from an in-app server with in-memory data, so every screen is
populated with no backend; every repository, mapper and screen above it is
the production code path, so the real parsing still runs. Demo mode is
forced off in production builds (`APP_ENV=production`).

```bash
# The demo: no server needed. Demo sign-ins are listed on the sign-in screen.
flutter run --dart-define=USE_MOCK_DATA=true

# Against a server on this computer (the Android emulator reaches it at 10.0.2.2).
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1
```

With no server running, every screen shows its **error state with a retry
button**, which is correct: the app holds no fallback data, so nothing can
appear to work when it does not.

## 5. Tests

```bash
flutter test                      # whole suite, against the demo server
flutter test test/core            # unit tests only
flutter test --coverage           # with coverage
```

`flutter test` runs against the demo server (`test/flutter_test_config.dart`).
The walks against a real server in `test/live/` are skipped unless asked for;
each file's header gives its command (`--dart-define=LIVE=true
--dart-define=USE_MOCK_DATA=false --dart-define=API_BASE_URL=...`).

## 6. Builds

A release talks to the real server: `APP_ENV=production` forces demo mode
off, and `API_BASE_URL` is the hosted server's address (with `/api/v1`).
Only a debug run falls back to this computer's server: a release or profile
build without `API_BASE_URL` (and not the demo) refuses to start.

```bash
flutter build apk --release       --dart-define=APP_ENV=production --dart-define=API_BASE_URL=https://<host>/api/v1
flutter build appbundle --release --dart-define=APP_ENV=production --dart-define=API_BASE_URL=https://<host>/api/v1
flutter build ipa --release       --dart-define=APP_ENV=production --dart-define=API_BASE_URL=https://<host>/api/v1
```

**Android release signing.** Whoever owns the Google Play account makes the upload key and keeps it:

```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

- Copy `android/key.properties.example` to `android/key.properties` and fill it in. Git ignores it and the `.jks` file.
- A release build without `android/key.properties` stops with an error. It never signs with the debug key, which Google Play refuses.
- Turn on Play App Signing at the first upload, so Google keeps the key that signs what shoppers install.

A demo build, for showing the app with no server, says so:

```bash
flutter build apk --release --dart-define=USE_MOCK_DATA=true
```

**Push (Firebase).** The app has the Firebase project's files (project `saba-marketplace`, 2026-10-01): `android/app/google-services.json`, and `ios/Runner/GoogleService-Info.plist`, which is in the Runner target. The app's ID is `com.sabacompany.sabamarketplace` on both platforms, as in Firebase. A build without those files would run with no pushes. Still needed:

- **Apple push key:** upload the APNs key (`.p8`) in Firebase, under Project settings, Cloud Messaging. Until then, iPhones get no pushes.
- **Apple Developer:** the App ID `com.sabacompany.sabamarketplace` needs Push Notifications. The app already carries the entitlement (`Runner.entitlements`) and the remote-notification background mode, so without that capability iOS signing fails.
- **Server:** it sends through FCM with a service account (backend `.env`, `PUSH_PROVIDER=fcm`). That file never goes in the repository.

Pushes arrive on the Android channel `saba_default` ("Orders and messages"). A tapped push opens what its notification opens in the list. Firebase needs iOS 15.0, so the app does too.

## 7. Localization

English and Arabic, with full RTL.

`lib/core/localization/strings_en.dart` is the source of truth for **which keys
exist**; `strings_ar.dart` must define every one of them. After editing either:

```bash
dart run tool/generate_localizations.dart
```

The generator rewrites `app_localizations.dart` and **exits non-zero** if a key
is missing from, or extra in, the Arabic table. Wire it into CI to make an
untranslated string impossible to merge.

## 8. Project structure

```
lib/
├── core/                  # cross-cutting, no feature knowledge
│   ├── config/            # AppConfig, ApiEndpoints (every REST path)
│   ├── constants/         # storage keys, header names, limits
│   ├── errors/            # Failure hierarchy, ErrorMapper, Result
│   ├── network/           # Dio factory, interceptors, typed ApiClient
│   ├── storage/           # secure token storage, device preferences
│   ├── theme/             # tokens, Material 3 light/dark themes
│   ├── localization/      # generated strings + failure messages
│   ├── router/            # routes, access table, guards, shells
│   ├── providers/         # DI, session events, pagination base class
│   ├── utils/             # validators, formatters, JSON readers
│   └── widgets/           # the design system
├── features/<feature>/
│   ├── domain/            # entities + repository interfaces (pure Dart)
│   ├── data/              # mappers + repository implementations
│   └── presentation/      # providers (Riverpod) + screens + widgets
├── app.dart               # MaterialApp.router, theme and locale wiring
└── main.dart              # entry point
```

Dependency direction is strictly inward: `presentation → domain ← data`.
Nothing in `domain/` imports Flutter, Dio or JSON.

## 9. Architecture notes

See [`../docs/mobile-architecture.md`](../docs/mobile-architecture.md) for the
full write-up. The short version:

- **The server is the authority.** The app sends identifiers and quantities,
  never prices, totals, roles or merchant ids. Every total shown comes from a
  server response (specification sections 13 and 20).
- **Repositories return `Result`, never throw.** Errors are values, so no call
  site can forget to handle one.
- **One error model end to end.** `ErrorMapper` turns HTTP statuses and backend
  error codes into typed failures; the UI renders them through one widget, so
  loading, empty and error states look the same everywhere.
- **Role separation is structural.** Customers and merchants get different
  navigation shells. `RouteAccessTable` declares who may open each route and
  **fails closed** for any route nobody classified.
- **Tokens never leave the keystore.** The interceptor refreshes them with
  single-flight locking and replays the original request once.
- **Business logic is out of widgets.** Screens read providers and render; the
  decisions live in controllers and repositories.

## 10. Production checklist

Before shipping:

- [ ] Build with `--dart-define=APP_ENV=production` (disables request logging)
- [ ] Point `API_BASE_URL` at an **HTTPS** host
- [ ] Replace the placeholder app icons and splash screen
- [x] The app's ID: `com.sabacompany.sabamarketplace`, Android and iOS (2026-10-01; it can never change once published)
- [ ] Add certificate pinning if your threat model calls for it
- [ ] Confirm the backend sets `Accept-Language`-aware error messages
- [ ] Run `flutter test` and `flutter analyze` in CI, plus the localization generator
