// Every shopper screen, drawn, signed in, in both languages.
//
// The route sweep in no_overflow_test walks a signed-out visitor, so half the
// app was never reached: anything behind sign-in, and anything needing an
// order or a product id. That is how a Row asking for infinite height sat on
// the product page — the busiest screen in the app — until an unrelated test
// finally rendered it.
//
// These bodies assert almost nothing. Flutter fails a test on any overflow or
// thrown layout, and the point is to draw each screen with real data in it.
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
import 'package:saba_marketplace/features/cart/presentation/cart_providers.dart';
import 'package:saba_marketplace/features/checkout/presentation/checkout_providers.dart';
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
    testWidgets('every shopper screen draws in ${locale.languageCode}', (
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

      // A customer with a history, because an empty account draws empty
      // states and empty states are not what breaks.
      late String orderId;
      await tester.runAsync(() async {
        await container
            .read(authControllerProvider.notifier)
            .signIn(email: 'demo@saba.app', password: 'Password1');
        await container
            .read(cartControllerProvider.notifier)
            .addItem(productId: 'p-1', quantity: 2);

        final checkout = container.read(checkoutControllerProvider.notifier);
        await checkout.priceOrder();
        orderId = (await checkout.placeOrder()).unwrap().orderId;

        // A second line, so the cart is not empty once the order is placed.
        await container
            .read(cartControllerProvider.notifier)
            .addItem(productId: 'p-2', quantity: 1);
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const SabaApp()),
      );
      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }

      final routes = <String>[
        AppRoutes.home,
        AppRoutes.categories,
        AppRoutes.cart,
        AppRoutes.orders,
        AppRoutes.account,
        AppRoutes.search,
        AppRoutes.wishlist,
        AppRoutes.addresses,
        AppRoutes.addressForm,
        AppRoutes.notifications,
        AppRoutes.conversations,
        AppRoutes.supportTickets,
        AppRoutes.newSupportTicket,
        AppRoutes.profile,
        AppRoutes.settings,
        AppRoutes.checkout,
        AppRoutes.productDetailPath('p-1'),
        AppRoutes.storefrontPath('m-1'),
        AppRoutes.categoryProductsPath('c-1'),
        AppRoutes.merchantReviewsPath('m-1'),
        AppRoutes.orderDetailPath(orderId),
        AppRoutes.orderInvoicePath(orderId),
        AppRoutes.requestReturnPath(orderId),
        AppRoutes.orderConfirmationPath(orderId),
      ];

      for (final route in routes) {
        container.read(appRouterProvider).go(route);
        for (var i = 0; i < 16; i++) {
          await tester.pump(const Duration(milliseconds: 120));
        }

        // Drawing nothing also throws nothing. A route the guard sends
        // somewhere else would sail through this sweep untested, so each one
        // has to prove it is still where it was asked to go.
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
      }
    });
  }
}
