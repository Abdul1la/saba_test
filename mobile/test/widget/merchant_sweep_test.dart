// Every merchant screen, drawn, signed in as a merchant, in both languages.
//
// Ten screens and not one of them had ever been rendered by a test: the only
// merchant coverage in the suite drives the repository and never builds a
// widget. That is exactly the gap that hid a Row asking for infinite height on
// the product page for weeks, so this closes the same gap on the other half of
// the app before anything else is judged.
//
// These bodies assert almost nothing on purpose. Flutter fails a test on any
// overflow or thrown layout, and the point is to draw each screen with real
// data in it.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/app.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/merchant/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = <String, String>{};

  setUp(() {
    store.clear();
    DioFactory.mockBackend.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_keystore, (call) async {
          switch (call.method) {
            case 'write':
              store[call.arguments['key'] as String] =
                  call.arguments['value'] as String? ?? '';
              return null;
            case 'read':
              return store[call.arguments['key'] as String];
            case 'delete':
              store.remove(call.arguments['key'] as String);
              return null;
            case 'readAll':
              return Map<String, String>.from(store);
            case 'deleteAll':
              store.clear();
              return null;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_keystore, null);
    DioFactory.mockBackend.resetForTesting();
  });

  for (final locale in const [Locale('en'), Locale('ar')]) {
    testWidgets('every merchant screen draws in ${locale.languageCode}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(411 * 3, 914 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues(<String, Object>{
        'saba.pref.onboarding_seen': true,
        'saba.pref.locale': locale.languageCode,
      });
      final preferences = await AppPreferences.create();
      final container = ProviderContainer(
        overrides: [appPreferencesProvider.overrideWithValue(preferences)],
        retry: (_, _) => null,
      );
      addTearDown(container.dispose);

      // The mock hands out a merchant account to any address with "merchant"
      // in it, and every /merchant route is merchantOnly — signed in as a
      // customer this sweep would test the redirect, not the screens.
      late MerchantProductRow existing;
      await tester.runAsync(() async {
        await container
            .read(authControllerProvider.notifier)
            .signIn(email: 'merchant@saba.app', password: 'Password1');
        existing = (await container.read(merchantRepositoryProvider).products())
            .unwrap()
            .items
            .first;
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const SabaApp()),
      );
      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }

      final routes = <String>[
        AppRoutes.merchantDashboard,
        AppRoutes.merchantProducts,
        AppRoutes.merchantOrders,
        // The queue arrives filtered when it is opened from a dashboard
        // number, which is a different first frame from the bare tab.
        AppRoutes.merchantOrdersPath(status: 'PENDING'),
        AppRoutes.merchantAnalytics,
        AppRoutes.merchantAccount,
        AppRoutes.merchantProductForm,
        AppRoutes.merchantInventory,
        AppRoutes.merchantPayouts,
        AppRoutes.merchantStoreSettings,
        AppRoutes.merchantOrderDetailPath('mo-1'),
      ];

      for (final route in routes) {
        container.read(appRouterProvider).go(route);
        for (var i = 0; i < 16; i++) {
          await tester.pump(const Duration(milliseconds: 120));
        }

        // Drawing nothing also throws nothing. A merchant route the guard
        // sends to sign-in would sail through this sweep untested, so each
        // one has to prove it is still where it was asked to go.
        expect(
          container
              .read(appRouterProvider)
              .routerDelegate
              .currentConfiguration
              .uri
              .path,
          Uri.parse(route).path,
          reason: '$route was redirected away instead of drawn',
        );

        // Flutter records a layout failure instead of throwing it at the
        // line that caused it, so by the time the test dies the widget is
        // disposed and the report names no file. Draining it here pins the
        // failure to the route that produced it.
        expect(
          tester.takeException(),
          isNull,
          reason: '$route threw or overflowed while drawing',
        );
      }

      // The form above opened empty, which is the new-product case. Editing
      // is the one merchants actually use, it is a different widget tree —
      // every field arrives populated and the variant matrix has rows in it —
      // and nothing had ever drawn it.
      container
          .read(appRouterProvider)
          .go(AppRoutes.merchantProductForm, extra: existing);
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      expect(
        tester.takeException(),
        isNull,
        reason: 'the product form threw or overflowed while editing',
      );
    });
  }
}
