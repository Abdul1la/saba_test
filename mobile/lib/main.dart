import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/network/dio_factory.dart';
import 'core/providers/core_providers.dart';
import 'core/push/firebase_push.dart';
import 'core/push/push_service.dart';
import 'core/storage/app_preferences.dart';

/// Entry point.
///
/// Preferences are loaded before the first frame so the app opens directly in
/// the saved language and theme instead of flashing the defaults.
Future<void> main() async {
  if (AppConfig.missingServerAddress) {
    throw StateError(
      'No server address: build with '
      '--dart-define=API_BASE_URL=https://<host>/api/v1 (mobile/README.md).',
    );
  }
  WidgetsFlutterBinding.ensureInitialized();

  final preferences = await AppPreferences.create();

  // Demo mode: the in-app server keeps its data on the phone, so every
  // account finds its own orders, cart and chats after the app is closed.
  if (AppConfig.isDemoMode) {
    DioFactory.mockBackend.keepOnDevice(
      saved: preferences.demoServer,
      save: (document) => unawaited(preferences.setDemoServer(document)),
    );
  }

  // Firebase where the build has its config files; no pushes where not, nor
  // in the demo, whose server sends none.
  final push = AppConfig.isDemoMode ? const NoPush() : await startPush();

  runApp(
    ProviderScope(
      overrides: [
        appPreferencesProvider.overrideWithValue(preferences),
        pushServiceProvider.overrideWithValue(push),
      ],
      // Riverpod 3 retries a failed provider automatically with backoff. That
      // is the wrong behaviour here: every screen already renders the failure
      // and offers an explicit retry, and a silent background retry would make
      // those screens look stuck on a spinner. Returning null disables it.
      retry: (_, _) => null,
      child: const SabaApp(),
    ),
  );
}
