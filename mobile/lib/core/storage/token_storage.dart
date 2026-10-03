import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/app_constants.dart';

/// A pair of JWTs as issued by `POST /auth/login` and `POST /auth/refresh`.
class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    this.accessTokenExpiresAt,
  });

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    final expiresAt = json['accessTokenExpiresAt'] ?? json['expiresAt'];
    final expiresIn = json['expiresIn'] ?? json['accessTokenExpiresIn'];

    DateTime? expiry;
    if (expiresAt != null) {
      expiry = DateTime.tryParse(expiresAt.toString())?.toUtc();
    } else if (expiresIn != null) {
      final seconds = int.tryParse(expiresIn.toString());
      if (seconds != null) {
        expiry = DateTime.now().toUtc().add(Duration(seconds: seconds));
      }
    }

    return AuthTokens(
      accessToken: (json['accessToken'] ?? json['access_token'] ?? '')
          .toString(),
      refreshToken: (json['refreshToken'] ?? json['refresh_token'] ?? '')
          .toString(),
      accessTokenExpiresAt: expiry,
    );
  }

  final String accessToken;
  final String refreshToken;
  final DateTime? accessTokenExpiresAt;

  bool get isValid => accessToken.isNotEmpty && refreshToken.isNotEmpty;

  /// True once the access token is inside the refresh leeway window.
  bool get isAccessTokenExpired {
    final expiry = accessTokenExpiresAt;
    if (expiry == null) return false;
    return DateTime.now()
        .toUtc()
        .add(AppConstants.tokenRefreshLeeway)
        .isAfter(expiry);
  }

  /// Never include the token values themselves in logs or crash reports.
  @override
  String toString() =>
      'AuthTokens(access: <redacted>, refresh: <redacted>, '
      'expiresAt: $accessTokenExpiresAt)';
}

/// Persists JWTs in the platform keystore (Android Keystore / iOS Keychain).
///
/// Tokens are never written to shared preferences, never logged and never
/// exposed to the widget tree.
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// In-memory mirror so the request interceptor does not hit the keystore on
  /// every single call.
  AuthTokens? _cached;

  Future<AuthTokens?> read() async {
    if (_cached != null) return _cached;
    try {
      final accessToken = await _storage.read(key: StorageKeys.accessToken);
      final refreshToken = await _storage.read(key: StorageKeys.refreshToken);
      if (accessToken == null ||
          refreshToken == null ||
          accessToken.isEmpty ||
          refreshToken.isEmpty) {
        return null;
      }
      final rawExpiry = await _storage.read(key: StorageKeys.accessTokenExpiry);
      _cached = AuthTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
        accessTokenExpiresAt: rawExpiry == null
            ? null
            : DateTime.tryParse(rawExpiry),
      );
      return _cached;
    } catch (_) {
      // A corrupted or inaccessible keystore must not crash startup; the user
      // simply has to sign in again.
      return null;
    }
  }

  /// The in-memory mirror is set first and is authoritative for this run, so a
  /// keystore that refuses to write still leaves a usable session: the user is
  /// signed in now and simply has to sign in again after a restart.
  ///
  /// Letting the platform exception escape instead would surface as a sign-in
  /// button that spins forever -- the write happens after the credentials were
  /// already accepted, so there is nothing left to report to the user. [read]
  /// tolerates the same failure for the same reason.
  Future<void> save(AuthTokens tokens) async {
    _cached = tokens;
    try {
      await _storage.write(
        key: StorageKeys.accessToken,
        value: tokens.accessToken,
      );
      await _storage.write(
        key: StorageKeys.refreshToken,
        value: tokens.refreshToken,
      );
      await _storage.write(
        key: StorageKeys.accessTokenExpiry,
        value: tokens.accessTokenExpiresAt?.toIso8601String(),
      );
    } catch (_) {
      // Persistence is best effort; the session above is not.
    }
  }

  /// Drops the session locally first, so a keystore that refuses to delete
  /// still signs the user out of this run rather than throwing out of logout.
  Future<void> clear() async {
    _cached = null;
    try {
      await _storage.delete(key: StorageKeys.accessToken);
      await _storage.delete(key: StorageKeys.refreshToken);
      await _storage.delete(key: StorageKeys.accessTokenExpiry);
    } catch (_) {
      // Nothing to recover: the tokens are already gone from memory.
    }
  }

  /// Synchronous view for the interceptor's fast path.
  AuthTokens? get cached => _cached;
}
