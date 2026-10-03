// Nothing may run off the side of a phone.
//
// The default test surface is 800x600 — wider than it is tall — so every
// screen fits on it and no layout bug is ever seen. At a real phone's 411
// points wide, the shared text field's label pushed its required asterisk off
// the edge on every form in the app, and the merchant navigation bar pushed
// out its last tab. Neither was visible until the surface was told the truth.
//
// Flutter fails a test on any overflow, so these bodies assert nothing and
// rely on that. A test that only fails at the right size is worth more than
// one that always passes.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/app.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          _channel,
          (call) async => call.method == 'readAll' ? <String, String>{} : null,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  /// The screens someone meets before and just after signing in. A wider
  /// sweep belongs here later; these are the ones being signed off now.
  final routes = <String>[
    AppRoutes.login,
    AppRoutes.language,
    AppRoutes.registerPhone,
    // The sign-up forms open only with a verified number.
    AppRoutes.registerPath(
      merchant: false,
      phone: '+9647512223344',
      token: 'test-token',
    ),
    AppRoutes.registerPath(
      merchant: true,
      phone: '+9647512223344',
      token: 'test-token',
    ),
    AppRoutes.home,
    AppRoutes.categories,
    AppRoutes.cart,
    AppRoutes.orders,
    AppRoutes.account,
    // A shop page, whose header was just rearranged: the Follow pill now
    // shares the banner with the back control, and in Arabic it changes ends.
    AppRoutes.storefrontPath('m-1'),
    // The busiest screen in the app, and until now the sweep had never drawn
    // it — which is how a Row asking for infinite height stayed on it.
    AppRoutes.productDetailPath('p-1'),
  ];

  for (final locale in const [Locale('en'), Locale('ar')]) {
    for (final route in routes) {
      testWidgets('$route fits a phone in ${locale.languageCode}', (
        tester,
      ) async {
        // A Pixel 8 in logical pixels.
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

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const SabaApp(),
          ),
        );
        for (var i = 0; i < 14; i++) {
          await tester.pump(const Duration(milliseconds: 120));
        }

        container.read(appRouterProvider).go(route);
        for (var i = 0; i < 16; i++) {
          await tester.pump(const Duration(milliseconds: 120));
        }
      });
    }
  }
}
