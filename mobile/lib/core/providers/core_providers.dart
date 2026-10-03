import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../localization/app_localizations.dart';
import '../network/api_client.dart';
import '../network/dio_factory.dart';
import '../network/live_updates.dart';
import '../storage/app_preferences.dart';
import '../storage/token_storage.dart';
import 'session_providers.dart';

/// Device preferences. Overridden in `main()` with the instance loaded before
/// the app starts, so every read afterwards is synchronous.
final appPreferencesProvider = Provider<AppPreferences>(
  (ref) => throw UnimplementedError(
    'appPreferencesProvider must be overridden in ProviderScope',
  ),
);

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

/// Selected language, or `null` to follow the device.
class LocaleController extends Notifier<Locale?> {
  @override
  Locale? build() => ref.read(appPreferencesProvider).locale;

  Future<void> setLocale(Locale? locale) async {
    await ref.read(appPreferencesProvider).setLocale(locale);
    state = locale;
  }
}

final localeControllerProvider = NotifierProvider<LocaleController, Locale?>(
  LocaleController.new,
);

/// Light, dark, or follow the system (specification section 17).
class ThemeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.read(appPreferencesProvider).themeMode;

  Future<void> setThemeMode(ThemeMode mode) async {
    await ref.read(appPreferencesProvider).setThemeMode(mode);
    state = mode;
  }
}

final themeControllerProvider = NotifierProvider<ThemeController, ThemeMode>(
  ThemeController.new,
);

/// Language code sent as `Accept-Language`, so the backend localizes its own
/// messages to match the UI.
final acceptLanguageProvider = Provider<String>((ref) {
  final locale = ref.watch(localeControllerProvider);
  if (locale != null) return locale.languageCode;
  final device = WidgetsBinding.instance.platformDispatcher.locale;
  final supported = AppLocalizations.supportedLocales.any(
    (candidate) => candidate.languageCode == device.languageCode,
  );
  return supported ? device.languageCode : 'en';
});

/// Bare client used for token refresh and request replay.
final refreshClientProvider = Provider<Dio>(
  (ref) => DioFactory.createRefreshClient(),
);

final dioProvider = Provider<Dio>((ref) {
  return DioFactory.create(
    tokenStorage: ref.watch(tokenStorageProvider),
    refreshClient: ref.watch(refreshClientProvider),
    currentLanguageCode: () => ref.read(acceptLanguageProvider),
    // Read lazily: this fires long after construction, so it cannot create a
    // dependency cycle between the network layer and the session controller.
    onSessionExpired: () async =>
        ref.read(sessionEventsProvider.notifier).reportExpired(),
  );
});

final apiClientProvider = Provider<ApiClient>((ref) {
  // The server answers in the reader's language, so a language switch makes
  // a new client, and everything that read through the old one reads again:
  // every repository is built on this, and every screen's data on a
  // repository. Only Home used to follow a switch; every other open screen
  // kept the old language until it was opened again.
  ref.watch(acceptLanguageProvider);
  return ApiClient(
    ref.watch(dioProvider),
    live: ref.watch(liveUpdatesProvider),
  );
});

/// What changed on the server, for the screens showing it.
final liveUpdatesProvider = Provider<LiveUpdates>((ref) {
  final live = LiveUpdates();
  ref.onDispose(live.dispose);
  return live;
});

/// How many times [topic] has changed since the app opened.
///
/// A list, a detail screen or a badge watches the topic it shows, so it
/// loads again the moment anything changes it - a store's step on an order,
/// a shopper cancelling one, a notification being read - without the person
/// pulling the screen down or opening it again.
class LiveTopicRevision extends Notifier<int> {
  LiveTopicRevision(this.topic);

  final LiveTopic topic;

  @override
  int build() {
    final subscription = ref.watch(liveUpdatesProvider).changes.listen((
      changed,
    ) {
      if (changed == topic) state = state + 1;
    });
    ref.onDispose(subscription.cancel);
    return 0;
  }
}

final liveTopicProvider =
    NotifierProvider.family<LiveTopicRevision, int, LiveTopic>(
      LiveTopicRevision.new,
    );
