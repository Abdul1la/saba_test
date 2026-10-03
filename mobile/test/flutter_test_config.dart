import 'dart:async';

import 'package:saba_marketplace/core/config/app_config.dart';

/// Loaded by `flutter test` before every test file. The suite runs against
/// the demo server, which the app itself no longer does by default; a run
/// against the real server says so with `--dart-define=USE_MOCK_DATA=false`
/// (the walks in `test/live/`).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AppConfig.demoForTests =
      !const bool.hasEnvironment('USE_MOCK_DATA') ||
      const bool.fromEnvironment('USE_MOCK_DATA');
  await testMain();
}
