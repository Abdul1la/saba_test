import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';

/// A settings write is best effort. The controllers set their state *after*
/// awaiting the write, so a platform failure that escapes would leave the theme
/// or language silently unchanged and the tap looking dead -- the same shape as
/// the sign-in bug that `TokenStorage.save` caused.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    preferences = await AppPreferences.create();
  });

  /// Installs a store whose every write fails.
  void breakTheStore() =>
      SharedPreferencesStorePlatform.instance = _ThrowingStore();

  tearDown(() {
    SharedPreferencesStorePlatform.instance =
        InMemorySharedPreferencesStore.withData(<String, Object>{});
  });

  test('a failing store does not throw out of the setters', () async {
    breakTheStore();

    await expectLater(
      preferences.setThemeMode(ThemeMode.dark),
      completes,
      reason: 'setThemeMode must swallow a platform failure',
    );
    await expectLater(preferences.setLocale(const Locale('ar')), completes);
    await expectLater(preferences.setLocale(null), completes);
    await expectLater(preferences.setOnboardingSeen(true), completes);
    await expectLater(preferences.addRecentSearch('phone'), completes);
    await expectLater(preferences.clearRecentSearches(), completes);
  });

  test('the language still changes when the write fails', () async {
    final container = ProviderContainer(
      overrides: [appPreferencesProvider.overrideWithValue(preferences)],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);

    expect(container.read(localeControllerProvider), isNull);
    breakTheStore();

    await container
        .read(localeControllerProvider.notifier)
        .setLocale(const Locale('ar'));

    expect(
      container.read(localeControllerProvider),
      const Locale('ar'),
      reason: 'the UI must switch to Arabic even if the preference is lost',
    );
  });

  test('the theme still changes when the write fails', () async {
    final container = ProviderContainer(
      overrides: [appPreferencesProvider.overrideWithValue(preferences)],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    breakTheStore();

    await container
        .read(themeControllerProvider.notifier)
        .setThemeMode(ThemeMode.dark);

    expect(container.read(themeControllerProvider), ThemeMode.dark);
  });

  test('writes still persist when the store works', () async {
    await preferences.setThemeMode(ThemeMode.dark);
    await preferences.setLocale(const Locale('ar'));
    await preferences.addRecentSearch('laptop');

    final reloaded = await AppPreferences.create();
    expect(reloaded.themeMode, ThemeMode.dark);
    expect(reloaded.locale, const Locale('ar'));
    expect(reloaded.recentSearches, contains('laptop'));
  });
}

/// Every write fails; reads return nothing.
class _ThrowingStore extends SharedPreferencesStorePlatform {
  @override
  Future<bool> clear() async => throw Exception('store unavailable');

  @override
  Future<Map<String, Object>> getAll() async => <String, Object>{};

  @override
  Future<bool> remove(String key) async => throw Exception('store unavailable');

  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      throw Exception('store unavailable');
}
