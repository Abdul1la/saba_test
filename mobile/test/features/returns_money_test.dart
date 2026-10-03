// The tester's money round (2026-09-25): returns lost real money. One pair
// of headphones went back three times and was refunded twice, and every
// refund ignored the store's coupon, so the store handed back more cash than
// it took and its 8% bill was cut too much. These hold both shut.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saba_marketplace/core/config/api_endpoints.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/checkout/domain/entities.dart';
import 'package:saba_marketplace/features/checkout/presentation/checkout_providers.dart';
import 'package:saba_marketplace/features/merchant/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:saba_marketplace/features/orders/domain/orders_repository.dart';
import 'package:saba_marketplace/features/orders/presentation/orders_providers.dart';
import 'package:saba_marketplace/features/orders/presentation/widgets/order_notes.dart';
import 'package:saba_marketplace/features/returns/domain/entities.dart';

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

  Future<dynamic> data(
    ProviderContainer container,
    String path, {
    String method = 'GET',
    Object? body,
  }) async {
    final client = container.read(apiClientProvider);
    if (method == 'GET') {
      return (await client.get<dynamic>(
        path,
        decoder: (envelope) => envelope.data,
      )).unwrap();
    }
    return (await client.command(path, method: method, data: body));
  }

  Future<void> as(ProviderContainer container, String email) async =>
      (await container
              .read(authControllerProvider.notifier)
              .signIn(email: email, password: 'Password1'))
          .unwrap();

  /// Amina buys Kite headphones (145,000, Nova) with NOVA10, and Nova
  /// delivers them. The order's id and its line.
  Future<(String, Map)> boughtWithCoupon(
    ProviderContainer container, {
    List<String> products = const ['p-5'],
  }) async {
    await as(container, 'shopper@saba.app');
    final client = container.read(apiClientProvider);
    for (final id in products) {
      (await client.command(
        ApiEndpoints.cartItems,
        data: {'productId': id, 'quantity': 1},
      )).unwrap();
    }
    (await client.command(
      ApiEndpoints.cartCoupon,
      data: {'code': 'NOVA10'},
    )).unwrap();
    final orderId =
        (await container
                .read(checkoutRepositoryProvider)
                .placeOrder(
                  selection: const CheckoutSelection(
                    addressId: 'addr-1',
                    paymentMethodId: 'pm-cod',
                  ),
                  idempotencyKey: 'coupon-return',
                ))
            .unwrap()
            .orderId;

    await as(container, 'merchant@saba.app');
    final rows =
        await data(container, '${ApiEndpoints.merchantOrders}?pageSize=50')
            as List;
    final part = (rows.first as Map)['id'] as String;
    for (final step in const [
      'CONFIRMED',
      'PROCESSING',
      'SHIPPED',
      'DELIVERED',
    ]) {
      (await container
              .read(merchantRepositoryProvider)
              .updateOrderStatus(
                orderId: part,
                status: step,
                courier: step == 'SHIPPED'
                    ? const Courier(name: 'Haider Salim', phone: '07705550311')
                    : null,
              ))
          .unwrap();
    }
    await as(container, 'shopper@saba.app');
    final order = await data(container, ApiEndpoints.order(orderId)) as Map;
    return (orderId, (order['items'] as List).first as Map);
  }

  Future<dynamic> ask(
    ProviderContainer container,
    String orderId,
    Object? itemId,
    int quantity,
  ) => container
      .read(ordersRepositoryProvider)
      .requestReturn(
        orderId: orderId,
        reason: 'DAMAGED',
        lines: [ReturnLine(orderItemId: '$itemId', quantity: quantity)],
      );

  test('an item is returned once, for at most what was bought', () async {
    final container = await signedOut();
    final (orderId, line) = await boughtWithCoupon(container);

    expect(
      ((await ask(container, orderId, line['id'], 2)) as dynamic).isOk,
      isFalse,
      reason: 'two returned of one bought',
    );
    ((await ask(container, orderId, line['id'], 1)) as dynamic).unwrap();
    expect(
      ((await ask(container, orderId, line['id'], 1)) as dynamic).isOk,
      isFalse,
      reason: 'the same item returned a second time',
    );
    final order = await data(container, ApiEndpoints.order(orderId)) as Map;
    expect(
      ((order['items'] as List).single as Map)['canReturn'],
      isFalse,
      reason: '"Request a return" is still on the order',
    );
  });

  test(
    'a refund is what was paid after the coupon, once, and once on the bill',
    () async {
      final container = await signedOut();
      await as(container, 'merchant@saba.app');
      final stockBefore =
          ((await data(container, ApiEndpoints.product('p-5'))
                  as Map)['availableQuantity']
              as num);
      final returnedBefore =
          (((await data(container, ApiEndpoints.merchantBills)
                      as Map)['current']
                  as Map)['returned']
              as num);

      final (orderId, line) = await boughtWithCoupon(container);
      // 145,000 less NOVA10's 10%.
      expect(line['paidUnitPrice'], 130500);
      ((await ask(container, orderId, line['id'], 1)) as dynamic).unwrap();
      final request =
          ((await data(container, ApiEndpoints.returns) as List).first as Map);
      expect(
        request['refundAmount'],
        130500,
        reason: 'the coupon was not taken off',
      );

      await as(container, 'merchant@saba.app');
      for (final step in const ['APPROVED', 'REFUNDED']) {
        (await data(
                  container,
                  ApiEndpoints.merchantReturn('${request['id']}'),
                  method: 'PATCH',
                  body: {'status': step},
                )
                as dynamic)
            .unwrap();
      }
      // Refunded twice is refused.
      expect(
        ((await data(
                  container,
                  ApiEndpoints.merchantReturn('${request['id']}'),
                  method: 'PATCH',
                  body: {'status': 'REFUNDED'},
                ))
                as dynamic)
            .isOk,
        isFalse,
      );
      final bill =
          (await data(container, ApiEndpoints.merchantBills) as Map)['current']
              as Map;
      expect((bill['returned'] as num) - returnedBefore, 130500);
      // One sold, one back: the shelf is where it started.
      expect(
        (await data(container, ApiEndpoints.product('p-5'))
            as Map)['availableQuantity'],
        stockBefore,
      );
    },
  );

  // The tester: size M changed to L, and Red/L reopened with Red/M's
  // leftover stock - a new option took the id of the one in its place.
  test(
    'a changed option is a new option, with none of the old stock',
    () async {
      final container = await signedOut();
      await as(container, 'merchant@saba.app');
      Map option(String size, int stock, [Object? id]) => {
        'id': ?id,
        'stock': stock,
        'options': [
          {'name': 'Color', 'value': 'Red'},
          {'name': 'Size', 'value': size},
        ],
      };
      final draft = {
        'name': 'Test Tee',
        'nameAr': 'قميص تجريبي',
        'price': 20000,
        'categoryId': 'c-accessories',
      };
      final client = container.read(apiClientProvider);
      final made = (await client.post<Map<String, dynamic>>(
        ApiEndpoints.merchantOwnProducts,
        data: {
          ...draft,
          'variants': [option('S', 1), option('M', 2)],
        },
        decoder: (envelope) => envelope.dataAsMap,
      )).unwrap();
      final before = {
        for (final v in made['variants'] as List)
          ((v as Map)['options'] as Map)['Size']: v['id'],
      };

      final edited = (await client.put<Map<String, dynamic>>(
        ApiEndpoints.merchantOwnProduct('${made['id']}'),
        data: {
          ...draft,
          'variants': [option('S', 1, before['S']), option('L', 0)],
        },
        decoder: (envelope) => envelope.dataAsMap,
      )).unwrap();
      final large = (edited['variants'] as List).cast<Map>().singleWhere(
        (v) => (v['options'] as Map)['Size'] == 'L',
      );
      expect(
        before.values,
        isNot(contains(large['id'])),
        reason: 'L took an old id',
      );
      expect(large['availableQuantity'], 0);
    },
  );

  // The tester: Nova's own "Test Tee" said 6,000 to Baghdad from Baghdad,
  // with no city pill; checkout charged 3,000.
  test(
    "a store's own product names its city, and its fee is checkout's",
    () async {
      final container = await signedOut();
      await as(container, 'merchant@saba.app');
      final client = container.read(apiClientProvider);
      final made = (await client.post<Map<String, dynamic>>(
        ApiEndpoints.merchantOwnProducts,
        data: {
          'name': 'Test Tee',
          'nameAr': 'قميص تجريبي',
          'price': 20000,
          'stock': 5,
          'categoryId': 'c-accessories',
        },
        decoder: (envelope) => envelope.dataAsMap,
      )).unwrap();
      await as(container, 'admin@saba.app');
      (await data(
                container,
                '/admin/products/${made['id']}/approve',
                method: 'POST',
              )
              as dynamic)
          .unwrap();

      await as(container, 'shopper@saba.app');
      final seller =
          (await data(container, ApiEndpoints.product('${made['id']}'))
                  as Map)['merchant']
              as Map;
      expect(seller['governorate'], 'BAGHDAD', reason: 'no city on the page');
      (await client.command(
        ApiEndpoints.cartItems,
        data: {'productId': made['id'], 'quantity': 1},
      )).unwrap();
      final cart = await data(container, ApiEndpoints.cart) as Map;
      final nova = (cart['groups'] as List).cast<Map>().singleWhere(
        (g) => (g['merchant'] as Map)['id'] == 'm-1',
      );
      expect(nova['shippingFee'], (seller['delivery'] as Map)['feeInside']);
    },
  );

  // The tester: a two-store invoice said "Sold by Nova Electronics" over
  // Atlas's air fryer too; and an unknown order opened a blank invoice
  // dated 1970.
  test(
    'an invoice names the store of each line; an unknown one is not found',
    () async {
      final container = await signedOut();
      await as(container, 'shopper@saba.app');
      final client = container.read(apiClientProvider);
      for (final id in ['p-5', 'p-2']) {
        (await client.command(
          ApiEndpoints.cartItems,
          data: {'productId': id, 'quantity': 1},
        )).unwrap();
      }
      final orderId =
          (await container
                  .read(checkoutRepositoryProvider)
                  .placeOrder(
                    selection: const CheckoutSelection(
                      addressId: 'addr-1',
                      paymentMethodId: 'pm-cod',
                    ),
                    idempotencyKey: 'two-stores-invoice',
                  ))
              .unwrap()
              .orderId;
      final invoice =
          (await container.read(ordersRepositoryProvider).fetchInvoice(orderId))
              .unwrap();
      expect(invoice.sellerName, isNull, reason: 'one seller for two stores');
      expect(invoice.lines.map((line) => line.merchantName).toSet(), {
        'Nova Electronics',
        'Atlas Home',
      });
      expect(
        (await container.read(ordersRepositoryProvider).fetchInvoice('nope'))
            .isOk,
        isFalse,
        reason: 'a blank invoice for an order that is not there',
      );
    },
  );

  // The tester: the cart fell under NOVA10's minimum, the chip stayed
  // green, and the order counted a use at 0 off (13 to 14).
  test('a coupon that takes nothing off says so, and is not used up', () async {
    final container = await signedOut();
    await as(container, 'merchant@saba.app');
    Future<num> uses() async {
      final coupons =
          await data(container, ApiEndpoints.merchantCoupons) as List;
      return (coupons.cast<Map>().singleWhere(
            (c) => c['code'] == 'NOVA10',
          )['usedCount']
          as num);
    }

    final before = await uses();
    await as(container, 'shopper@saba.app');
    final client = container.read(apiClientProvider);
    final shelf =
        (await data(container, '${ApiEndpoints.products}?pageSize=100') as List)
            .cast<Map>();
    final cheap = shelf.firstWhere(
      (p) =>
          (p['merchant'] as Map)['id'] == 'm-1' &&
          p['hasOptions'] != true &&
          (p['price'] as num) < 100000,
    );
    (await client.command(
      ApiEndpoints.cartItems,
      data: {'productId': 'p-5', 'quantity': 1},
    )).unwrap();
    (await client.command(
      ApiEndpoints.cartCoupon,
      data: {'code': 'NOVA10'},
    )).unwrap();
    // The headphones go; something under the minimum stays.
    final cart = await data(container, ApiEndpoints.cart) as Map;
    final line = ((cart['groups'] as List).first as Map)['items'] as List;
    (await client.command(
      '${ApiEndpoints.cartItems}/${(line.first as Map)['id']}',
      method: 'DELETE',
    )).unwrap();
    (await client.command(
      ApiEndpoints.cartItems,
      data: {'productId': cheap['id'], 'quantity': 1},
    )).unwrap();
    final under =
        (await data(container, ApiEndpoints.cart) as Map)['coupon'] as Map;
    expect(under['applies'], isFalse, reason: 'the chip says it is on');
    expect(under['minOrderAmount'], 100000);

    (await container
            .read(checkoutRepositoryProvider)
            .placeOrder(
              selection: const CheckoutSelection(
                addressId: 'addr-1',
                paymentMethodId: 'pm-cod',
              ),
              idempotencyKey: 'coupon-under-minimum',
            ))
        .unwrap();
    await as(container, 'merchant@saba.app');
    expect(await uses(), before, reason: 'a use counted at 0 off');
  });

  // The tester: a return was declined on one tap, with no reason for the
  // shopper; the return page printed "DAMAGED" and three steps that never
  // happen.
  test('a declined return says why, in words; v1 has three steps', () async {
    final container = await signedOut();
    final (orderId, line) = await boughtWithCoupon(container);
    ((await ask(container, orderId, line['id'], 1)) as dynamic).unwrap();
    final request =
        (await data(container, ApiEndpoints.returns) as List).first as Map;

    await as(container, 'merchant@saba.app');
    Future<dynamic> decline([String? reason]) => data(
      container,
      ApiEndpoints.merchantReturn('${request['id']}'),
      method: 'PATCH',
      body: {'status': 'REJECTED', 'reason': ?reason},
    );
    expect(((await decline()) as dynamic).isOk, isFalse, reason: 'no reason');
    ((await decline('USED')) as dynamic).unwrap();

    await as(container, 'shopper@saba.app');
    final mine =
        (await data(container, ApiEndpoints.returns) as List).first as Map;
    expect(mine['rejectionReason'], 'USED');
    const en = AppLocalizations(Locale('en'));
    expect(reasonLabel(en, 'USED'), en.returnDeclineUsed);
    expect(reasonLabel(en, 'DAMAGED'), en.returnReasonDamaged);
    expect(ReturnStatus.progression, [
      ReturnStatus.requested,
      ReturnStatus.approved,
      ReturnStatus.refunded,
    ]);
  });

  // The order follows its slowest store, exactly: the tester first found
  // "Pending" after one store had delivered, and it was changed to
  // "Confirmed" once any store moved - which then read "Confirmed" while
  // Atlas had not confirmed. Each store's own step is in its box.
  test('a two-store order waits for its slowest store', () async {
    final container = await signedOut();
    await as(container, 'shopper@saba.app');
    final client = container.read(apiClientProvider);
    for (final id in ['p-5', 'p-2']) {
      (await client.command(
        ApiEndpoints.cartItems,
        data: {'productId': id, 'quantity': 1},
      )).unwrap();
    }
    final orderId =
        (await container
                .read(checkoutRepositoryProvider)
                .placeOrder(
                  selection: const CheckoutSelection(
                    addressId: 'addr-1',
                    paymentMethodId: 'pm-cod',
                  ),
                  idempotencyKey: 'two-stores-pending',
                ))
            .unwrap()
            .orderId;

    await as(container, 'merchant@saba.app');
    final rows =
        await data(container, '${ApiEndpoints.merchantOrders}?pageSize=50')
            as List;
    final part = (rows.first as Map)['id'] as String;
    for (final step in const [
      'CONFIRMED',
      'PROCESSING',
      'SHIPPED',
      'DELIVERED',
    ]) {
      (await container
              .read(merchantRepositoryProvider)
              .updateOrderStatus(
                orderId: part,
                status: step,
                courier: step == 'SHIPPED'
                    ? const Courier(name: 'Haider Salim', phone: '07705550311')
                    : null,
              ))
          .unwrap();
    }
    await as(container, 'shopper@saba.app');
    final order = await data(container, ApiEndpoints.order(orderId)) as Map;
    expect(
      order['status'],
      'PENDING',
      reason: 'Atlas has not confirmed, and the order said it had',
    );
    expect(
      [for (final item in order['items'] as List) item['status']],
      containsAll(['DELIVERED', 'PENDING']),
      reason: "each store's own step",
    );
  });

  // The tester: refunds of 130,565 and 170,185 - no note is under 250.
  // NOVA10 on headphones and a watch: a share that is not a whole step.
  test('what was paid, and so every refund, is in steps of 250', () async {
    final container = await signedOut();
    await as(container, 'shopper@saba.app');
    final shelf =
        (await data(container, '${ApiEndpoints.products}?pageSize=100') as List)
            .cast<Map>();
    final watch = shelf.firstWhere(
      (p) =>
          (p['merchant'] as Map)['id'] == 'm-1' &&
          p['hasOptions'] != true &&
          p['id'] != 'p-5' &&
          (p['price'] as num) % 1000 != 0,
      orElse: () => shelf.firstWhere(
        (p) =>
            (p['merchant'] as Map)['id'] == 'm-1' &&
            p['hasOptions'] != true &&
            p['id'] != 'p-5',
      ),
    );
    final (orderId, _) = await boughtWithCoupon(
      container,
      products: ['p-5', '${watch['id']}'],
    );
    final order = await data(container, ApiEndpoints.order(orderId)) as Map;
    for (final line in (order['items'] as List).cast<Map>()) {
      expect((line['paidUnitPrice'] as num) % 250, 0, reason: '$line');
      expect(
        line['paidUnitPrice'] as num,
        lessThanOrEqualTo(line['unitPrice'] as num),
      );
    }
    final first = (order['items'] as List).first as Map;
    ((await ask(container, orderId, first['id'], 1)) as dynamic).unwrap();
    final request =
        (await data(container, ApiEndpoints.returns) as List).first as Map;
    expect((request['refundAmount'] as num) % 250, 0);
    expect(((request['refund'] as Map)['amount'] as num) % 250, 0);
  });
}
