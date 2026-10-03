import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';

/// Non-sensitive, device-local settings: theme, language, recent searches.
///
/// No business data is ever stored here — carts, orders and catalog data live
/// in MySQL and are always read through the API.
class AppPreferences {
  AppPreferences(this._prefs);

  static Future<AppPreferences> create() async =>
      AppPreferences(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  /// Every write goes through here.
  ///
  /// A settings write is best effort: the controller above sets its state
  /// *after* awaiting, so letting a platform failure escape would mean the
  /// theme or language silently never changes and the tap looks dead. Reads
  /// fall back to their defaults, so a lost write costs a preference, not
  /// correctness. Same reasoning as `TokenStorage.save`.
  Future<void> _write(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // Preference not persisted; the in-session value still applies.
    }
  }

  // ---------------------------------------------------------------- locale ---
  /// `null` means "follow the device locale".
  Locale? get locale {
    final code = _prefs.getString(StorageKeys.localeCode);
    if (code == null || code.isEmpty) return null;
    return Locale(code);
  }

  Future<void> setLocale(Locale? locale) => _write(() async {
    if (locale == null) {
      await _prefs.remove(StorageKeys.localeCode);
    } else {
      await _prefs.setString(StorageKeys.localeCode, locale.languageCode);
    }
  });

  // ----------------------------------------------------------------- theme ---
  ThemeMode get themeMode => switch (_prefs.getString(StorageKeys.themeMode)) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  Future<void> setThemeMode(ThemeMode mode) =>
      _write(() => _prefs.setString(StorageKeys.themeMode, mode.name));

  // ------------------------------------------------------------ onboarding ---
  bool get onboardingSeen =>
      _prefs.getBool(StorageKeys.onboardingSeen) ?? false;

  Future<void> setOnboardingSeen(bool value) =>
      _write(() => _prefs.setBool(StorageKeys.onboardingSeen, value));

  // ----------------------------------------------------------- governorate ---
  /// The shopper's city, as a governorate code; null until they choose.
  String? get governorate => _prefs.getString(StorageKeys.governorate);

  Future<void> setGovernorate(String code) =>
      _write(() => _prefs.setString(StorageKeys.governorate, code));

  // ----------------------------------------------------------- demo server ---
  /// What the demo server held when the app was last used (demo mode only).
  String? get demoServer => _prefs.getString(StorageKeys.demoServer);

  Future<void> setDemoServer(String document) =>
      _write(() => _prefs.setString(StorageKeys.demoServer, document));

  // ------------------------------------------------------- recent searches ---
  /// A device-local convenience only. Server-side search history is the source
  /// of truth for a signed-in customer.
  ///
  /// One list per account, and one for a guest: the phone may be shared, and
  /// what one person searched for is not the next one's to see.
  List<String> get recentSearches => recentSearchesOf(null);

  List<String> recentSearchesOf(String? account) =>
      _prefs.getStringList(_recentSearchesKey(account)) ?? const <String>[];

  Future<void> addRecentSearch(String term, {String? account}) async {
    final trimmed = term.trim();
    if (trimmed.isEmpty) return;
    final current = <String>[...recentSearchesOf(account)]
      ..removeWhere((e) => e.toLowerCase() == trimmed.toLowerCase())
      ..insert(0, trimmed);
    final capped = current.take(AppConstants.maxRecentSearches).toList();
    await _write(
      () => _prefs.setStringList(_recentSearchesKey(account), capped),
    );
  }

  Future<void> clearRecentSearches({String? account}) =>
      _write(() => _prefs.remove(_recentSearchesKey(account)));

  static String _recentSearchesKey(String? account) => account == null
      ? StorageKeys.recentSearches
      : '${StorageKeys.recentSearches}.$account';
}
