import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saba_marketplace/core/config/api_endpoints.dart';
import 'package:saba_marketplace/core/mock/mock_data.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/checkout/domain/entities.dart';
import 'package:saba_marketplace/features/checkout/presentation/checkout_providers.dart';
import 'package:saba_marketplace/features/merchant/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:saba_marketplace/features/orders/presentation/orders_providers.dart';

/// Saba v1 is paid in cash, to each store's own driver, through the real
/// pipeline down to the demo backend: cash is the only way to pay, each
/// driver is told their own amount, every amount is in steps of 250 IQD, and
/// a new shopper's first order is capped at 1,000,000 IQD.
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

  /// The in-stock products with no options from [merchantId], cheapest first.
  List<Map<String, dynamic>> shelfOf(String merchantId) =>
      MockData.products
          .where(
            (product) =>
                (product['merchant'] as Map)['id'] == merchantId &&
                product['variants'] == null &&
                product['stockStatus'] != 'OUT_OF_STOCK' &&
                MockData.startsOnSale(product['id']),
          )
          .toList()
        ..sort((a, b) => (a['price'] as num).compareTo(b['price'] as num));

  const home = CheckoutSelection(addressId: 'addr-1');
  const cash = CheckoutSelection(
    addressId: 'addr-1',
    paymentMethodId: 'pm-cod',
  );

  test('cash is the only way to pay; the card is coming soon', () async {
    final container = await signedOut();
    (await container
            .read(authControllerProvider.notifier)
            .signIn(email: 'shopper@saba.app', password: 'Password1'))
        .unwrap();
    final client = container.read(apiClientProvider);
    final checkout = container.read(checkoutRepositoryProvider);
    await client.command(
      ApiEndpoints.cartItems,
      data: <String, dynamic>{'productId': shelfOf('m-1').first['id']},
    );

    final summary = (await checkout.review(home)).unwrap();
    expect(
      [
        for (final method in summary.paymentMethods)
          (method.type, method.isEnabled),
      ],
      [(PaymentMethodType.cashOnDelivery, true)],
      reason: 'v1 takes cash, and offers nothing else',
    );
    expect(summary.tax, 0, reason: 'a tax Iraq does not charge was added');

    final byCard = await checkout.placeOrder(
      selection: const CheckoutSelection(
        addressId: 'addr-1',
        paymentMethodId: 'pm-card',
      ),
      idempotencyKey: 'card-attempt',
    );
    expect(byCard.isOk, isFalse, reason: 'an order was taken by card');
  });

  test(
    "each store's driver is told their own amount, in 250 IQD steps",
    () async {
      final container = await signedOut();
      final auth = container.read(authControllerProvider.notifier);
      final client = container.read(apiClientProvider);
      final checkout = container.read(checkoutRepositoryProvider);
      final store = container.read(merchantRepositoryProvider);
      final orders = container.read(ordersRepositoryProvider);
      Future<void> signIn(String email) async =>
          (await auth.signIn(email: email, password: 'Password1')).unwrap();

      // Enough from Nova for its 10% code, where 10% is not a whole step of
      // 250: 10% of 105,000 is 10,500, but of 123,000 it is 12,300.
      late Map<String, dynamic> nova;
      late int quantity;
      search:
      for (final product in shelfOf('m-1')) {
        for (var count = 1; count <= 3; count++) {
          final spend = (product['price'] as num) * count;
          if (spend >= 100000 && spend <= 600000 && (spend / 10) % 250 != 0) {
            nova = product;
            quantity = count;
            break search;
          }
        }
      }
      final atlas = shelfOf('m-2').first;

      await signIn('shopper@saba.app');
      await client.command(
        ApiEndpoints.cartItems,
        data: <String, dynamic>{'productId': nova['id'], 'quantity': quantity},
      );
      await client.command(
        ApiEndpoints.cartItems,
        data: <String, dynamic>{'productId': atlas['id']},
      );
      (await client.command(
        ApiEndpoints.cartCoupon,
        data: <String, dynamic>{'code': 'NOVA10'},
      )).unwrap();

      final summary = (await checkout.review(home)).unwrap();
      final novaPart = summary.groups.singleWhere((g) => g.merchantId == 'm-1');
      final atlasPart = summary.groups.singleWhere(
        (g) => g.merchantId == 'm-2',
      );
      final tenPercent = (nova['price'] as num) * quantity / 10;
      expect(
        novaPart.discount,
        (tenPercent / 250).floor() * 250,
        reason: 'the discount is not rounded down to 250 IQD',
      );
      expect(
        novaPart.amountDue,
        novaPart.subtotal - novaPart.discount + novaPart.shippingFee!,
      );
      expect(atlasPart.discount, 0, reason: "Nova's code took money off Atlas");
      expect(atlasPart.amountDue, atlasPart.subtotal + atlasPart.shippingFee!);
      expect(
        novaPart.amountDue! + atlasPart.amountDue!,
        summary.total,
        reason: "the drivers' amounts do not add up to the total",
      );
      for (final amount in [
        novaPart.amountDue!,
        atlasPart.amountDue!,
        summary.total,
      ]) {
        expect(amount % 250, 0, reason: '$amount cannot be paid in cash');
      }

      (await checkout.placeOrder(
        selection: cash,
        idempotencyKey: 'two-drivers',
      )).unwrap();
      final placed = (await orders.fetchOrders()).unwrap().items.first;
      final order = (await orders.fetchOrder(placed.id)).unwrap();
      expect(order.dueByStore, <String, num>{
        'm-1': novaPart.amountDue!,
        'm-2': atlasPart.amountDue!,
      }, reason: 'the order does not say what to pay each driver');

      // Nova's driver collects Nova's part, after Nova's own discount.
      await signIn('merchant@saba.app');
      final row = (await store.orders(
        status: 'PENDING',
      )).unwrap().items.singleWhere((r) => r.orderNumber == placed.orderNumber);
      expect(row.total, novaPart.amountDue, reason: 'the store collects wrong');
      expect((await store.order(row.id)).unwrap().discount, novaPart.discount);
    },
  );

  test(
    "a new shopper's first order is up to 1,000,000 IQD, until one has come",
    () async {
      final container = await signedOut();
      final auth = container.read(authControllerProvider.notifier);
      final client = container.read(apiClientProvider);
      final checkout = container.read(checkoutRepositoryProvider);
      final store = container.read(merchantRepositoryProvider);
      Future<void> signIn(String email) async =>
          (await auth.signIn(email: email, password: 'Password1')).unwrap();

      // Over the limit in one cart.
      final dear = shelfOf('m-1').last;
      final count = (1000001 / (dear['price'] as num)).ceil();
      expect(count, lessThanOrEqualTo(dear['availableQuantity'] as num));
      await signIn('shopper@saba.app');
      await client.command(
        ApiEndpoints.cartItems,
        data: <String, dynamic>{'productId': dear['id'], 'quantity': count},
      );

      final summary = (await checkout.review(home)).unwrap();
      expect(summary.canPlaceOrder, isFalse, reason: 'no first-order limit');
      expect(summary.warnings.single, contains('1,000,000 IQD'));
      expect(
        (await checkout.placeOrder(
          selection: cash,
          idempotencyKey: 'too-much',
        )).isOk,
        isFalse,
        reason: 'the server took an order over the limit',
      );

      // A small one first, bought now; Nova delivers it and is paid.
      (await checkout.placeOrder(
        selection: CheckoutSelection(
          addressId: 'addr-1',
          paymentMethodId: 'pm-cod',
          buyNow: BuyNowLine(productId: shelfOf('m-1').first['id'] as String),
        ),
        idempotencyKey: 'small-first',
      )).unwrap();
      await signIn('merchant@saba.app');
      final part = (await store.orders(status: 'PENDING')).unwrap().items.first;
      for (final step in ['CONFIRMED', 'PROCESSING', 'SHIPPED', 'DELIVERED']) {
        (await store.updateOrderStatus(
          orderId: part.id,
          status: step,
          courier: step == 'SHIPPED'
              ? const Courier(name: 'Ali', phone: '+9647701112222')
              : null,
        )).unwrap();
      }

      // Now she has received and paid for one, the big cart can go.
      await signIn('shopper@saba.app');
      expect(
        (await checkout.review(home)).unwrap().canPlaceOrder,
        isTrue,
        reason: 'the limit stayed after a delivered, paid order',
      );
      (await checkout.placeOrder(
        selection: cash,
        idempotencyKey: 'big-second',
      )).unwrap();
    },
  );

  test('a store prices and gives money off in steps of 250 IQD', () async {
    final container = await signedOut();
    (await container
            .read(authControllerProvider.notifier)
            .signIn(email: 'merchant@saba.app', password: 'Password1'))
        .unwrap();
    final store = container.read(merchantRepositoryProvider);
    final today = DateTime.now();

    ProductDraft priced(num price) => ProductDraft(
      name: 'Phone case',
      nameAr: 'غطاء هاتف',
      categoryId: 'c-1',
      price: price,
    );
    expect(
      (await store.saveProduct(priced(12300))).isOk,
      isFalse,
      reason: 'a price cash cannot pay was saved',
    );
    (await store.saveProduct(priced(12250))).unwrap();

    MerchantCoupon off(String code, num value) => MerchantCoupon(
      id: '',
      code: code,
      isPercentage: false,
      value: value,
      startsAt: today,
    );
    expect(
      (await store.saveCoupon(off('NOVA5100', 5100))).isOk,
      isFalse,
      reason: 'money off cash cannot hand back was saved',
    );
    (await store.saveCoupon(off('NOVA5000', 5000))).unwrap();

    // A code is the only one of its name on Saba - another store's too,
    // even one whose coupons nobody has opened yet.
    expect(
      (await store.saveCoupon(off('ATLAS5000', 5000))).isOk,
      isFalse,
      reason: "Nova took Atlas's code",
    );
  });
}
