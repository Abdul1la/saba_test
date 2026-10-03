import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saba_marketplace/core/config/api_endpoints.dart';
import 'package:saba_marketplace/core/location/governorate.dart';
import 'package:saba_marketplace/core/mock/mock_data.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/merchant/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:saba_marketplace/features/notifications/presentation/notifications_providers.dart';
import 'package:saba_marketplace/features/orders/domain/entities.dart';
import 'package:saba_marketplace/features/orders/presentation/orders_providers.dart';

/// One shopper, two stores, one checkout, through the real pipeline down to
/// the demo backend. A shopper's order used to stay in the shopper's account:
/// the stores' order screens listed invented orders, every store login opened
/// Nova Electronics, and nothing a store did reached the shopper.
const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final keys = <String, String>{};
  late AppPreferences preferences;

  setUp(() async {
    DioFactory.mockBackend.resetForTesting();
    keys.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    preferences = await AppPreferences.create();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          switch (call.method) {
            case 'write':
              keys[call.arguments['key'] as String] =
                  call.arguments['value'] as String? ?? '';
              return null;
            case 'read':
              return keys[call.arguments['key'] as String];
            case 'delete':
              keys.remove(call.arguments['key'] as String);
              return null;
            case 'readAll':
              return Map<String, String>.from(keys);
            case 'deleteAll':
              keys.clear();
              return null;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  Future<ProviderContainer> signedOut() async {
    final container = ProviderContainer(
      overrides: [appPreferencesProvider.overrideWithValue(preferences)],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    return container;
  }

  /// An in-stock product with no options, from [merchantId], cheap enough
  /// that two of one and one of another stay inside a first order's limit.
  String productOf(String merchantId) =>
      MockData.products.firstWhere(
            (product) =>
                (product['merchant'] as Map)['id'] == merchantId &&
                product['variants'] == null &&
                product['stockStatus'] != 'OUT_OF_STOCK' &&
                (product['price'] as num) <= 300000,
          )['id']
          as String;

  test(
    'a shopper buys from two stores, and each store sends its part',
    () async {
      final container = await signedOut();
      final auth = container.read(authControllerProvider.notifier);
      final client = container.read(apiClientProvider);
      final store = container.read(merchantRepositoryProvider);
      final orders = container.read(ordersRepositoryProvider);
      final inbox = container.read(notificationsRepositoryProvider);
      final nova = productOf('m-1');
      final atlas = productOf('m-2');

      Future<void> signIn(String email) async =>
          (await auth.signIn(email: email, password: 'Password1')).unwrap();
      Future<num> stockOf(String productId) async =>
          ((await client.get<Map<String, dynamic>>(
                ApiEndpoints.product(productId),
                decoder: (envelope) => envelope.dataAsMap,
              )).unwrap())['availableQuantity']
              as num;
      Future<List<String>> titles() async => [
        for (final each in (await inbox.fetch()).unwrap().items) each.title,
      ];

      // She buys two from Nova and one from Atlas, paying cash on delivery.
      await signIn('shopper@saba.app');
      final novaStock = await stockOf(nova);
      await client.command(
        ApiEndpoints.cartItems,
        data: <String, dynamic>{'productId': nova, 'quantity': 2},
      );
      await client.command(
        ApiEndpoints.cartItems,
        data: <String, dynamic>{'productId': atlas, 'quantity': 1},
      );
      (await client.command(
        ApiEndpoints.checkoutPlaceOrder,
        data: <String, dynamic>{'paymentMethodId': 'pm-cod'},
      )).unwrap();
      final placed = (await orders.fetchOrders()).unwrap().items.first;
      expect(
        placed.merchantNames,
        containsAll(['Nova Electronics', 'Atlas Home']),
      );
      expect(
        await stockOf(nova),
        novaStock - 2,
        reason: 'what was bought is still on the shelf',
      );

      // Nova has its part, from her, and nothing of Atlas's.
      await signIn('merchant@saba.app');
      final novaPart = (await store.orders(
        status: 'PENDING',
      )).unwrap().items.where((row) => row.orderNumber == placed.orderNumber);
      expect(novaPart, hasLength(1), reason: 'the order never reached Nova');
      expect(novaPart.single.customerName, 'Amina Saleh');
      expect(
        [for (final item in novaPart.single.items) item.productId],
        [nova],
        reason: "a store was sent another store's goods",
      );
      expect(await titles(), contains('New order ${placed.orderNumber}'));
      // Where it goes, in parts: a driver in Iraq finds the door by the
      // nearest landmark, and the store sees the city to plan the trip.
      final whereTo = (await store.order(
        novaPart.single.id,
      )).unwrap().shippingAddress;
      expect(
        whereTo?.landmark,
        'Behind Al-Mansour Mall',
        reason: 'the store never gets the nearest landmark',
      );
      expect(whereTo?.governorate, Governorate.baghdad);
      expect(whereTo?.phone, '+9647701234567');
      for (final step in ['CONFIRMED', 'PROCESSING', 'SHIPPED']) {
        (await store.updateOrderStatus(
          orderId: novaPart.single.id,
          status: step,
          courier: step == 'SHIPPED'
              ? const Courier(name: 'Haider Salim', phone: '+9647705550311')
              : null,
        )).unwrap();
      }

      // Nova has shipped, Atlas has not confirmed: the order is still
      // waiting, as its slowest store is. It read "Confirmed" (the tester).
      await signIn('shopper@saba.app');
      expect(
        (await orders.fetchOrder(placed.id)).unwrap().status,
        OrderStatus.pending,
        reason: 'the order ran ahead of its slowest store',
      );

      // Atlas is its own store now, with its own shelf and its own part.
      await signIn(MockData.secondMerchantEmail);
      expect(
        container.read(currentUserProvider)?.merchant?.storeName,
        'Atlas Home',
        reason: 'the second store login opened Nova',
      );
      final shelf = [
        for (final row in (await store.products()).unwrap().items) row.id,
      ];
      expect(shelf, contains(atlas));
      expect(shelf, isNot(contains(nova)), reason: "Atlas stocks Nova's goods");
      final atlasPart = (await store.orders(
        status: 'PENDING',
      )).unwrap().items.where((row) => row.orderNumber == placed.orderNumber);
      expect(atlasPart, hasLength(1), reason: 'the order never reached Atlas');
      expect(
        [for (final item in atlasPart.single.items) item.productId],
        [atlas],
      );
      (await store.updateOrderStatus(
        orderId: atlasPart.single.id,
        status: 'CONFIRMED',
      )).unwrap();

      // Back to her: each store's step is on her order, and she was told.
      await signIn('shopper@saba.app');
      var order = (await orders.fetchOrder(placed.id)).unwrap();
      expect(
        order.itemsByMerchant['Nova Electronics']!.first.status,
        OrderStatus.shipped,
        reason: "Nova's step never reached the shopper",
      );
      expect(
        order.itemsByMerchant['Atlas Home']!.first.status,
        OrderStatus.confirmed,
      );
      expect(
        order.status,
        OrderStatus.confirmed,
        reason: 'the order is as far along as its slowest store',
      );
      // Who is bringing Nova's part, for the shopper to call.
      expect(order.parts['m-1']?.courierName, 'Haider Salim');
      expect(order.parts['m-1']?.courierPhone, '+9647705550311');
      expect(order.shippingAddress?.area, 'Al-Mansour');
      expect(order.canCancel, isFalse, reason: 'cancellable after shipping');
      expect(
        await titles(),
        containsAll([
          'Your parcel from Nova Electronics is on its way',
          'Atlas Home confirmed your order',
        ]),
      );

      // Both deliver: the order has arrived and the cash has been paid.
      await signIn('merchant@saba.app');
      (await store.updateOrderStatus(
        orderId: novaPart.single.id,
        status: 'DELIVERED',
      )).unwrap();
      await signIn(MockData.secondMerchantEmail);
      for (final step in ['PROCESSING', 'SHIPPED', 'DELIVERED']) {
        (await store.updateOrderStatus(
          orderId: atlasPart.single.id,
          status: step,
          courier: step == 'SHIPPED'
              ? const Courier(name: 'Ali', phone: '+9647701112222')
              : null,
        )).unwrap();
      }
      await signIn('shopper@saba.app');
      order = (await orders.fetchOrder(placed.id)).unwrap();
      expect(order.status, OrderStatus.delivered);
      expect(order.paymentStatus, PaymentStatus.paid);
      expect(order.canReturn, isTrue);
    },
  );

  test('a shopper cancels, and the store sees it cancelled', () async {
    final container = await signedOut();
    final auth = container.read(authControllerProvider.notifier);
    final client = container.read(apiClientProvider);
    final orders = container.read(ordersRepositoryProvider);

    (await auth.signIn(
      email: 'shopper@saba.app',
      password: 'Password1',
    )).unwrap();
    await client.command(
      ApiEndpoints.cartItems,
      data: <String, dynamic>{'productId': productOf('m-1'), 'quantity': 1},
    );
    (await client.command(ApiEndpoints.checkoutPlaceOrder)).unwrap();
    final placed = (await orders.fetchOrders()).unwrap().items.first;
    (await orders.cancelOrder(
      orderId: placed.id,
      reason: 'CHANGED_MIND',
    )).unwrap();

    (await auth.signIn(
      email: 'merchant@saba.app',
      password: 'Password1',
    )).unwrap();
    final part = (await container.read(merchantRepositoryProvider).orders())
        .unwrap()
        .items
        .singleWhere((row) => row.orderNumber == placed.orderNumber);
    expect(
      part.status,
      'CANCELLED',
      reason: 'the store would still pack a cancelled order',
    );
  });
}
