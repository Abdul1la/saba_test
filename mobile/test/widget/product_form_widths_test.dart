// The store's product form is one column: every box as wide as the others.
// In "Price and stock", Price and Original price sat side by side at half
// width and Stock under them at full width: three boxes, two widths, for no
// reason. (An option's own card keeps its price and stock side by side: two
// equal boxes, so a long list of options stays short.)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/app.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
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
          final key = call.arguments is Map ? call.arguments['key'] : null;
          switch (call.method) {
            case 'write':
              store[key as String] = call.arguments['value'] as String? ?? '';
            case 'read':
              return store[key as String];
            case 'readAll':
              return Map<String, String>.from(store);
          }
          return null;
        });
  });
  tearDown(() => DioFactory.mockBackend.resetForTesting());

  for (final language in ['en', 'ar']) {
    testWidgets('every box in the product form is as wide as the others '
        '($language)', (tester) async {
      tester.view.physicalSize = const Size(411 * 3, 914 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'saba.pref.onboarding_seen': true,
        'saba.pref.locale': language,
      });
      final preferences = await AppPreferences.create();
      final c = ProviderContainer(
        overrides: [appPreferencesProvider.overrideWithValue(preferences)],
        retry: (_, _) => null,
      );
      addTearDown(c.dispose);
      await tester.runAsync(() async {
        (await c
                .read(authControllerProvider.notifier)
                .signIn(email: 'merchant@saba.app', password: 'Password1'))
            .unwrap();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const SabaApp()),
      );
      c.read(appRouterProvider).push(AppRoutes.merchantProductForm);
      for (var i = 0; i < 18; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }

      // A new product: no options yet, so Stock is a box of its own.
      final l10n = AppLocalizations(Locale(language));
      expect(find.text(l10n.stock), findsOneWidget);
      final boxes = find.byType(TextField);
      final widths = <double>{
        for (var i = 0; i < boxes.evaluate().length; i++)
          tester.getSize(boxes.at(i)).width,
      };
      expect(boxes.evaluate().length, greaterThan(5), reason: 'not the form');
      expect(widths, hasLength(1), reason: 'widths: $widths');
    });
  }
}
