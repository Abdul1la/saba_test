// M5, against the real server: a return the store declined still read
// "Refund amount 260,000 IQD" in green on the shopper's returns list, and
// each line kept its amount on the return's page. Nothing comes back.
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
import 'package:saba_marketplace/core/utils/formatters.dart';
import 'package:saba_marketplace/core/widgets/filter_chip_row.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/cart/presentation/cart_providers.dart';
import 'package:saba_marketplace/features/checkout/presentation/checkout_providers.dart';
import 'package:saba_marketplace/features/merchant/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:saba_marketplace/features/orders/domain/orders_repository.dart';
import 'package:saba_marketplace/features/orders/presentation/orders_providers.dart';
import 'package:saba_marketplace/features/returns/presentation/returns_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _en = AppLocalizations(Locale('en'));

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
            case 'delete':
              store.remove(key as String);
            case 'readAll':
              return Map<String, String>.from(store);
            case 'deleteAll':
              store.clear();
          }
          return null;
        });
  });
  tearDown(() => DioFactory.mockBackend.resetForTesting());

  testWidgets('a declined return shows no refund', (tester) async {
    tester.view.physicalSize = const Size(411 * 3, 914 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'saba.pref.onboarding_seen': true,
      'saba.pref.locale': 'en',
    });
    final preferences = await AppPreferences.create();
    final c = ProviderContainer(
      overrides: [appPreferencesProvider.overrideWithValue(preferences)],
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);

    late String returnId;
    late num paid;
    await tester.runAsync(() async {
      final auth = c.read(authControllerProvider.notifier);
      (await auth.signIn(
        email: 'shopper@saba.app',
        password: 'Password1',
      )).unwrap();
      await c
          .read(cartControllerProvider.notifier)
          .addItem(productId: 'p-1', quantity: 1);
      final checkout = c.read(checkoutControllerProvider.notifier);
      await checkout.priceOrder();
      final orderId = (await checkout.placeOrder()).unwrap().orderId;

      (await auth.signIn(
        email: 'merchant@saba.app',
        password: 'Password1',
      )).unwrap();
      final nova = c.read(merchantRepositoryProvider);
      final part = (await nova.orders()).unwrap().items.first.id;
      for (final step in ['CONFIRMED', 'PROCESSING', 'SHIPPED', 'DELIVERED']) {
        (await nova.updateOrderStatus(
          orderId: part,
          status: step,
          courier: step == 'SHIPPED'
              ? const Courier(name: 'Ali', phone: '+9647701112222')
              : null,
        )).unwrap();
      }

      (await auth.signIn(
        email: 'shopper@saba.app',
        password: 'Password1',
      )).unwrap();
      final orders = c.read(ordersRepositoryProvider);
      final line = (await orders.fetchOrder(orderId)).unwrap().items.first;
      paid = line.paidUnitPrice;
      (await orders.requestReturn(
        orderId: orderId,
        lines: [ReturnLine(orderItemId: line.id, quantity: 1)],
        reason: 'DAMAGED',
      )).unwrap();
      returnId = (await c.read(returnsRepositoryProvider).fetchReturns())
          .unwrap()
          .items
          .first
          .id;

      (await auth.signIn(
        email: 'merchant@saba.app',
        password: 'Password1',
      )).unwrap();
      (await c
              .read(merchantRepositoryProvider)
              .answerReturn(returnId, 'REJECTED', reason: 'USED'))
          .unwrap();
      (await auth.signIn(
        email: 'shopper@saba.app',
        password: 'Password1',
      )).unwrap();
    });

    Future<void> settle() async {
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    final amount = Formatters.money(paid, locale: 'en', currencyCode: 'IQD');
    await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: const SabaApp()),
    );
    await settle();

    // The returns list.
    c.read(appRouterProvider).go(AppRoutes.orders);
    await settle();
    // The delivered order's rating sheet comes up first.
    if (find.text(_en.notNow).evaluate().isNotEmpty) {
      await tester.tap(find.text(_en.notNow));
      await settle();
    }
    // The filter row is built as it scrolls: Returns is its last chip.
    final tab = find.text(_en.returns);
    await tester.scrollUntilVisible(
      tab,
      200,
      scrollable: find
          .descendant(
            of: find.byType(TextFilterChips),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(tab);
    await settle();
    expect(
      find.text(_en.refundAmount),
      findsNothing,
      reason: 'a declined return lists $amount as coming back',
    );

    // Its page.
    c.read(appRouterProvider).go(AppRoutes.returnDetailPath(returnId));
    await settle();
    expect(find.text(_en.returnDeclineUsed), findsOneWidget);
    expect(
      find.text(amount, skipOffstage: false),
      findsNothing,
      reason: 'a declined line still shows $amount',
    );
  });
}
