import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saba_marketplace/app.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';

/// The splash on a cold start (the user's call, 2026-10-05): a first launch
/// went straight to the language page and never showed it, and a returning
/// one showed it for a frame. It now stays [splashMinimum], then moves on.
const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    DioFactory.mockBackend.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_keystore, (call) async => null);
    splashMinimum = const Duration(milliseconds: 1500);
  });

  tearDown(() {
    splashMinimum = Duration.zero;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_keystore, null);
  });

  Future<ProviderContainer> launch(
    WidgetTester tester, {
    required bool returning,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'saba.pref.onboarding_seen': returning,
    });
    final preferences = await AppPreferences.create();
    final container = ProviderContainer(
      overrides: [appPreferencesProvider.overrideWithValue(preferences)],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SabaApp()),
    );
    return container;
  }

  String path(ProviderContainer c) =>
      c.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path;

  testWidgets('a first launch shows the splash, then asks the language', (
    tester,
  ) async {
    final container = await launch(tester, returning: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(path(container), AppRoutes.splash);

    await tester.pump(const Duration(milliseconds: 1300));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(path(container), AppRoutes.language);
  });

  testWidgets('a returning launch shows the splash too, then moves on', (
    tester,
  ) async {
    final container = await launch(tester, returning: true);
    await tester.pump(const Duration(milliseconds: 300));
    expect(path(container), AppRoutes.splash);

    await tester.pump(const Duration(milliseconds: 1300));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(path(container), isNot(AppRoutes.splash));
    // Home asks the demo server for its shelves: let those answers land.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  });
}
