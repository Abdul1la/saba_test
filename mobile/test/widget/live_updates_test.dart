// A screen shows what is true now, not what was true when it was opened.
//
// My orders kept the list it had loaded, so an order just paid for was not
// in it; an order's details kept the status it had loaded; and the dot on
// the bell was worked out once when the app opened and never again. Every
// change now says what subject it belongs to, and each screen showing that
// subject loads again by itself - the shopper's and the store's alike.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/app.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/checkout/domain/entities.dart';
import 'package:saba_marketplace/features/checkout/presentation/checkout_providers.dart';
import 'package:saba_marketplace/features/merchant/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:saba_marketplace/features/notifications/presentation/notifications_providers.dart';
import 'package:saba_marketplace/features/orders/domain/entities.dart';
import 'package:saba_marketplace/features/orders/presentation/orders_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final keys = <String, String>{};

  setUp(() {
    keys.clear();
    DioFactory.mockBackend.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_keystore, (call) async {
          final key = call.arguments is Map
              ? (call.arguments as Map)['key'] as String?
              : null;
          switch (call.method) {
            case 'write':
              keys[key!] = (call.arguments as Map)['value'] as String? ?? '';
            case 'read':
              return keys[key];
            case 'delete':
              keys.remove(key);
            case 'readAll':
              return Map<String, String>.from(keys);
            case 'deleteAll':
              keys.clear();
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_keystore, null);
    DioFactory.mockBackend.resetForTesting();
  });

  Future<_App> open(WidgetTester tester, String email) async {
    tester.view.physicalSize = const Size(411 * 3, 914 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues(<String, Object>{
      'saba.pref.onboarding_seen': true,
      'saba.pref.locale': 'en',
    });
    final container = ProviderContainer(
      overrides: [
        appPreferencesProvider.overrideWithValue(await AppPreferences.create()),
      ],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);

    final app = _App(tester, container);
    await app.signIn(email);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SabaApp()),
    );
    await app.settle();
    return app;
  }

  testWidgets('My orders shows an order paid for while it was open', (
    tester,
  ) async {
    final app = await open(tester, 'shopper@saba.app');
    await app.go(AppRoutes.orders);
    final before = app.orderIds();

    // Bought from somewhere else in the app - the list is still on screen.
    final order = await app.buy();
    await app.settle();

    expect(
      app.orderIds(),
      isNot(before),
      reason: 'My orders kept the list it had when it was opened',
    );
    expect(app.orderIds(), contains(order));
    expect(
      find.textContaining(app.numberOf(order)),
      findsWidgets,
      reason: 'the new order is not on screen',
    );
  });

  testWidgets('cancelling reaches the list and the details at once', (
    tester,
  ) async {
    final app = await open(tester, 'shopper@saba.app');
    final order = await app.buy();
    await app.go(AppRoutes.orders);
    // Opened on top of the list, the way a tap on it does: the list is
    // still there underneath, showing what it loaded.
    await app.push(AppRoutes.orderDetailPath(order));
    expect(app.detail(order).status, OrderStatus.pending);

    await app.run(
      () => app
          .read(ordersRepositoryProvider)
          .cancelOrder(orderId: order, reason: 'CHANGED_MIND'),
    );
    await app.settle();

    expect(
      app.detail(order).status,
      OrderStatus.cancelled,
      reason: 'the details kept the status they were opened with',
    );

    // Back to the list that was underneath: no pulling it down.
    await app.pop();
    expect(
      app.summary(order).status,
      OrderStatus.cancelled,
      reason: 'My orders still says the cancelled order is waiting',
    );
  });

  testWidgets("a store's own screens follow the step it just took", (
    tester,
  ) async {
    // The shopper buys, then hands the phone to the store, as a demo does.
    final shopper = await open(tester, 'shopper@saba.app');
    await shopper.buy();

    final app = await open(tester, 'merchant@saba.app');
    await app.go(AppRoutes.merchantOrders);
    await app.go(AppRoutes.merchantDashboard);
    final waiting = app.read(merchantDashboardProvider).requireValue;
    final part = await app.storePart();
    expect(part.status, 'PENDING');

    await app.run(
      () => app
          .read(merchantRepositoryProvider)
          .updateOrderStatus(orderId: part.id, status: 'CONFIRMED'),
    );
    await app.settle();

    expect(
      (await app.storePart()).status,
      'CONFIRMED',
      reason: "the store's orders kept the step before",
    );
    expect(
      app.read(merchantDashboardProvider).requireValue.pendingOrders,
      waiting.pendingOrders - 1,
      reason: 'the dashboard still counts it as waiting',
    );
  });

  testWidgets('the dot on the bell goes out when the notifications are read', (
    tester,
  ) async {
    final app = await open(tester, 'shopper@saba.app');
    await app.go(AppRoutes.home);
    expect(
      app.read(unreadNotificationCountProvider).requireValue,
      greaterThan(0),
      reason: 'the demo shopper has nothing unread to begin with',
    );

    await app.run(
      () => app.read(notificationsRepositoryProvider).markAllRead(),
    );
    await app.settle();

    expect(
      app.read(unreadNotificationCountProvider).requireValue,
      0,
      reason: 'the dot was worked out once and never again',
    );
  });
}

/// The app, running, with the things a test asks of it.
class _App {
  _App(this.tester, this.container);

  final WidgetTester tester;
  final ProviderContainer container;

  T read<T>(ProviderListenable<T> provider) => container.read(provider);

  Future<T> run<T>(Future<T> Function() body) async =>
      (await tester.runAsync(body)) as T;

  Future<void> settle() async {
    for (var i = 0; i < 18; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Future<void> go(String route) async {
    read(appRouterProvider).go(route);
    await settle();
  }

  Future<void> push(String route) async {
    read(appRouterProvider).push(route);
    await settle();
  }

  Future<void> pop() async {
    read(appRouterProvider).pop();
    await settle();
  }

  Future<void> signIn(String email) async {
    (await run(
      () => read(
        authControllerProvider.notifier,
      ).signIn(email: email, password: 'Password1'),
    )).unwrap();
    await settle();
  }

  /// Buys the cheapest thing in the demo shop; the order's id.
  Future<String> buy() async {
    final placed = await run(
      () => read(checkoutRepositoryProvider).placeOrder(
        selection: const CheckoutSelection(
          addressId: 'addr-1',
          paymentMethodId: 'pm-cod',
          buyNow: BuyNowLine(productId: 'p-1'),
        ),
        idempotencyKey: 'live-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await settle();
    return placed.unwrap().orderId;
  }

  Set<String> orderIds() => {
    for (final order in read(orderListProvider(null)).requireValue.items)
      order.id,
  };

  OrderSummary summary(String id) => read(
    orderListProvider(null),
  ).requireValue.items.firstWhere((order) => order.id == id);

  String numberOf(String id) => summary(id).orderNumber;

  Order detail(String id) => read(orderDetailProvider(id)).requireValue;

  /// Nova's part of the newest order, as the store's app reads it.
  Future<MerchantOrderRow> storePart() async {
    final rows = await run(
      () => read(merchantOrdersProvider(null).notifier).future,
    );
    return rows.items.first;
  }
}
