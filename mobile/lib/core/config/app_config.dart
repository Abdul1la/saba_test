import 'package:flutter/foundation.dart';

/// Application environments. Selected at build time via `--dart-define=APP_ENV=...`.
enum AppEnvironment { development, staging, production }

/// Central, build-time application configuration.
///
/// Nothing here is a secret: the mobile app never holds JWT secrets, payment
/// credentials or any other privileged value. Every sensitive decision is made
/// by the backend.
class AppConfig {
  const AppConfig._();

  static const String _apiBaseUrlOverride = String.fromEnvironment(
    'API_BASE_URL',
  );
  static const String _environmentName = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );

  /// Demo mode: answer every request from an in-memory fixture instead of the
  /// network, so the whole UI is navigable with no server.
  ///
  /// Off unless a build asks for it with `--dart-define=USE_MOCK_DATA=true`,
  /// as the web's demo build does: it defaulted to on, and the release
  /// commands never turned it off, so a release would have talked to the
  /// fake server (the tester). Nothing above the network layer changes:
  /// repositories, mappers and screens are the same code either way.
  static const bool _useMockData = bool.fromEnvironment('USE_MOCK_DATA');

  /// Set by `test/flutter_test_config.dart`: the test suite runs against the
  /// demo server unless a run asks for the real one.
  @visibleForTesting
  static bool demoForTests = false;

  static bool get useMockData => _useMockData || demoForTests;

  /// What every part of the app asks. Forced off in production builds, so a
  /// release can never ship fixtures.
  static bool get isDemoMode => useMockData && !isProduction;

  static AppEnvironment get environment => switch (_environmentName) {
    'production' => AppEnvironment.production,
    'staging' => AppEnvironment.staging,
    _ => AppEnvironment.development,
  };

  static bool get isProduction => environment == AppEnvironment.production;

  /// A build that would fall back to localhost, which on a phone is the
  /// phone itself (the reviewer): not a debug run, not the demo (it needs no
  /// server), and built without API_BASE_URL. `main` refuses to start it.
  static bool get missingServerAddress => needsServerAddress(
    debug: kDebugMode,
    demo: isDemoMode,
    address: _apiBaseUrlOverride,
  );

  @visibleForTesting
  static bool needsServerAddress({
    required bool debug,
    required bool demo,
    required String address,
  }) => !debug && !demo && address.isEmpty;

  /// Base URL of the REST API, including the version segment.
  ///
  /// Override for any environment with:
  /// `flutter run --dart-define=API_BASE_URL=https://api.example.com/api/v1`
  /// Only a debug run falls back to localhost ([missingServerAddress]).
  static String get apiBaseUrl {
    if (_apiBaseUrlOverride.isNotEmpty) return _apiBaseUrlOverride;
    if (kIsWeb) return 'http://localhost:3000/api/v1';
    // The Android emulator reaches the host machine through 10.0.2.2.
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:3000/api/v1';
    }
    return 'http://localhost:3000/api/v1';
  }

  static const Duration connectTimeout = Duration(seconds: 20);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration sendTimeout = Duration(seconds: 30);

  /// Default page size for paginated endpoints.
  static const int defaultPageSize = 20;

  /// Fallback currency. The API returns the authoritative currency code on
  /// every priced resource; this is only used when one is missing. Saba
  /// sells in Iraqi dinars only: it was USD, and a product that did not
  /// exist was priced "0.00 $".
  static const String fallbackCurrencyCode = 'IQD';

  /// The market this app is built for.
  ///
  /// Only ever a starting value: a new address opens with it filled in rather
  /// than asking every customer in the country to type the name of their own
  /// country. The field stays editable, so shipping somewhere else the day
  /// the business decides to needs no code change here.
  static const String homeCountry = 'Iraq';

  /// Disabled in production, and it never logs tokens or credentials.
  static bool get enableNetworkLogging => !isProduction;

  /// Custom scheme used for deep links back into the app.
  static const String deepLinkScheme = 'saba';
}
