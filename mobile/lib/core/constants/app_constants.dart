/// Keys used for persisted values. Tokens live in the secure keystore, never in
/// plain preferences.
class StorageKeys {
  const StorageKeys._();

  // Secure storage (Keychain / Keystore).
  static const String accessToken = 'saba.auth.access_token';
  static const String refreshToken = 'saba.auth.refresh_token';
  static const String accessTokenExpiry = 'saba.auth.access_token_expiry';

  // Non-sensitive preferences.
  static const String localeCode = 'saba.pref.locale';
  static const String themeMode = 'saba.pref.theme_mode';
  static const String onboardingSeen = 'saba.pref.onboarding_seen';
  static const String recentSearches = 'saba.pref.recent_searches';
  static const String governorate = 'saba.pref.governorate';

  /// Demo mode only: the in-app server's data, as one JSON document.
  static const String demoServer = 'saba.demo.server';
}

/// Header names shared with the backend.
class ApiHeaders {
  const ApiHeaders._();

  static const String authorization = 'Authorization';
  static const String acceptLanguage = 'Accept-Language';
  static const String idempotencyKey = 'Idempotency-Key';
  static const String requestId = 'X-Request-Id';
  static const String clientPlatform = 'X-Client-Platform';
  static const String clientVersion = 'X-Client-Version';
}

class AppConstants {
  const AppConstants._();

  static const Duration searchDebounce = Duration(milliseconds: 350);
  static const Duration snackBarDuration = Duration(seconds: 3);
  static const int maxRecentSearches = 10;
  static const int maxCompareItems = 4;
  static const int minPasswordLength = 8;

  /// A person's name and a store's name, at most. A 140-letter name was
  /// accepted and squashed unreadably on Home.
  static const int maxPersonNameLength = 50;
  static const int maxStoreNameLength = 40;
  static const int maxCartQuantityPerItem = 99;

  /// Refresh the access token this long before it actually expires.
  static const Duration tokenRefreshLeeway = Duration(seconds: 30);
}
