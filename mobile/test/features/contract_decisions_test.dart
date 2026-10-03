// API_CONTRACT.md 6.6-6.11, the decisions that change the app: Saba's
// takedown apart from the store's switch (D22), no UNDER_REVIEW (D-S1),
// Home's stores rail showing only featured stores while its city chips keep
// every city (D28), and in the demo: bills for refund-only months (D4) and
// a customer's reply reopening a ticket (D-T2).
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saba_marketplace/core/config/api_endpoints.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/domain/entities.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/checkout/domain/entities.dart';
import 'package:saba_marketplace/features/checkout/presentation/checkout_providers.dart';

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

  test('D22: Saba takes a product down, apart from the store', () async {
    final container = await signedOut();
    await as(container, 'admin@saba.app');
    (await data(
      container,
      '/admin/products/p-1/hide',
      method: 'POST',
      body: {'reason': 'Listed in the wrong category'},
    )).unwrap();

    // Out of the shop.
    await as(container, 'shopper@saba.app');
    final shop = await data(container, '${ApiEndpoints.products}?pageSize=100');
    expect([
      for (final p in shop as List) (p as Map)['id'],
    ], isNot(contains('p-1')));

    // The store sees it, with why, and cannot put it back.
    await as(container, 'merchant@saba.app');
    final rows = await data(container, '/merchants/me/products?pageSize=100');
    final row = (rows as List).cast<Map>().singleWhere((r) => r['id'] == 'p-1');
    expect(row['takenDown'], isTrue);
    expect(row['takenDownReason'], 'Listed in the wrong category');
    final back = await data(
      container,
      '/merchants/me/products/p-1/visibility',
      method: 'POST',
      body: {'isActive': true},
    );
    expect((back as dynamic).isOk, isFalse);

    // Only Saba can.
    await as(container, 'admin@saba.app');
    (await data(
      container,
      '/admin/products/p-1/unhide',
      method: 'POST',
    )).unwrap();
    await as(container, 'shopper@saba.app');
    final again = await data(
      container,
      '${ApiEndpoints.products}?pageSize=100',
    );
    expect([for (final p in again as List) (p as Map)['id']], contains('p-1'));
  });

  test('D-S1: a store waiting for Saba is PENDING, nothing else', () {
    expect(
      MerchantStatus.values.map((s) => s.name),
      isNot(contains('underReview')),
    );
    expect(MerchantStatus.fromApi('UNDER_REVIEW'), MerchantStatus.unknown);
  });

  test(
    'D28: the rail is the featured stores; the city chips keep every city',
    () async {
      final container = await signedOut();
      await as(container, 'admin@saba.app');
      (await data(
        container,
        '/admin/featured-stores',
        method: 'PUT',
        body: {'storeIds': <String>[]},
      )).unwrap();

      await as(container, 'shopper@saba.app');
      final sections = await data(container, '/home/sections') as List;
      expect(
        sections.map((s) => (s as Map)['type']),
        isNot(contains('MERCHANT')),
        reason: 'an empty rail was sent',
      );
      final cities = await data(container, ApiEndpoints.storeCities) as List;
      expect(cities, containsAll(['BAGHDAD', 'BASRA', 'DUHOK']));

      await as(container, 'admin@saba.app');
      // Refused (409): an id twice, or a store Saba has not approved.
      for (final refused in [
        ['m-2', 'm-2'],
        ['m-nowhere'],
      ]) {
        final reply = await data(
          container,
          '/admin/featured-stores',
          method: 'PUT',
          body: {'storeIds': refused},
        );
        expect((reply as dynamic).isOk, isFalse, reason: '$refused was kept');
      }
      Future<Object?> featured() async =>
          (await data(container, '/admin/featured-stores') as Map)['featured'];
      expect(await featured(), isEmpty);
      (await data(
        container,
        '/admin/featured-stores',
        method: 'PUT',
        body: {
          'storeIds': ['m-2'],
        },
      )).unwrap();
      expect(await featured(), ['m-2']);
      await as(container, 'shopper@saba.app');
      final rail = (await data(container, '/home/sections') as List)
          .cast<Map>()
          .singleWhere((s) => s['type'] == 'MERCHANT');
      expect(
        [for (final s in rail['items'] as List) (s as Map)['id']],
        ['m-2'],
      );
    },
  );

  test('D4: a month with only a refund stays on the bills', () async {
    final container = await signedOut();
    await as(container, 'merchant2@saba.app');

    // Atlas's demo, with a refund in May, a month it delivered nothing.
    String? document;
    final backend = DioFactory.mockBackend
      ..keepOnDevice(saved: null, save: (saved) => document = saved);
    await data(container, '/merchants/me/bills');
    final state = jsonDecode(document!) as Map<String, dynamic>;
    ((state['storeReturns'] as Map)['m-2'] as List).add(<String, dynamic>{
      'id': 'may-refund',
      'status': 'REFUNDED',
      'refundAmount': 50000,
      'refund': {'completedAt': DateTime(2026, 5, 20).toIso8601String()},
    });
    backend.keepOnDevice(saved: jsonEncode(state), save: (_) {});

    final bills = await data(container, '/merchants/me/bills') as Map;
    final may = (bills['past'] as List).cast<Map>().where(
      (bill) => '${bill['month']}'.startsWith('2026-05'),
    );
    expect(may, hasLength(1), reason: 'the refund-only month was left out');
    expect(may.single['orderCount'], 0);
    expect(may.single['returned'], 50000);
    expect(may.single['owed'], 0);
  });

  test('D-T2: the customer\'s reply reopens a waiting or resolved ticket; '
      'a closed one takes none', () async {
    final container = await signedOut();
    await as(container, 'shopper@saba.app');
    final ticket =
        (await container
                .read(apiClientProvider)
                .post<dynamic>(
                  ApiEndpoints.supportTickets,
                  data: {
                    'subject': 'Late order',
                    'category': 'ORDER',
                    'description': 'Where is it?',
                  },
                  decoder: (envelope) => envelope.data,
                ))
            .unwrap();
    final id = '${(ticket as Map)['id']}';

    Future<void> saba(String status) async {
      await as(container, 'admin@saba.app');
      (await data(
        container,
        '/admin/tickets/$id/status',
        method: 'POST',
        body: {'status': status},
      )).unwrap();
      await as(container, 'shopper@saba.app');
    }

    Future<dynamic> reply() => data(
      container,
      ApiEndpoints.supportTicketMessages(id),
      method: 'POST',
      body: {'body': 'Any news?'},
    );

    Future<Object?> status() async =>
        (await data(container, ApiEndpoints.supportTicket(id))
            as Map)['status'];

    for (final waiting in ['WAITING_FOR_CUSTOMER', 'RESOLVED']) {
      await saba(waiting);
      expect(await status(), waiting);
      ((await reply()) as dynamic).unwrap();
      expect(await status(), 'OPEN', reason: '$waiting did not reopen');
    }

    await saba('CLOSED');
    expect(((await reply()) as dynamic).isOk, isFalse);
    expect(await status(), 'CLOSED');
    final thread =
        await data(container, ApiEndpoints.supportTicketMessages(id)) as List;
    expect(thread, hasLength(3), reason: 'the closed ticket took the reply');
  });

  // BUGS 105: a ticket records who opened it, as API_CONTRACT.md 3.8 has it.
  test('a ticket says whether a shopper or a store opened it', () async {
    final container = await signedOut();
    Future<Map> open(String who) async {
      await as(container, who);
      return (await container
                  .read(apiClientProvider)
                  .post<dynamic>(
                    ApiEndpoints.supportTickets,
                    data: {
                      'subject': 'Help',
                      'category': 'OTHER',
                      'description': 'Please help.',
                    },
                    decoder: (envelope) => envelope.data,
                  ))
              .unwrap()
          as Map;
    }

    expect((await open('shopper@saba.app'))['openedBy'], {
      'kind': 'SHOPPER',
      'name': 'Amina Saleh',
      'phone': '+9647701234567',
    });
    expect((await open('merchant@saba.app'))['openedBy'], {
      'kind': 'STORE',
      'name': 'Nova Electronics',
      'phone': '+9647711234567',
      'storeId': 'm-1',
    });
  });

  // BUGS 106: an order names its customer by id (API_CONTRACT.md 5), on the
  // shopper's copy and the store's.
  test("an order carries its customer's id", () async {
    final container = await signedOut();
    await as(container, 'shopper@saba.app');
    final placed =
        (await container
                .read(checkoutRepositoryProvider)
                .placeOrder(
                  selection: const CheckoutSelection(
                    addressId: 'addr-1',
                    paymentMethodId: 'pm-cod',
                    buyNow: BuyNowLine(productId: 'p-11'),
                  ),
                  idempotencyKey: 'customer-id',
                ))
            .unwrap();
    final mine =
        await data(container, ApiEndpoints.order(placed.orderId)) as Map;
    expect(mine['customerId'], 'cu-1234567');

    // Every store copy of it, and the seeded ones, named the same way.
    for (final store in ['merchant@saba.app', 'merchant2@saba.app']) {
      await as(container, store);
      final rows =
          (await data(container, '${ApiEndpoints.merchantOrders}?pageSize=200')
                  as List)
              .cast<Map>();
      for (final row in rows) {
        if (row['orderNumber'] == mine['orderNumber']) {
          expect(row['customerId'], 'cu-1234567');
        } else {
          expect(row['customerId'], matches(RegExp(r'^cu-\d{7}$')));
        }
      }
    }
  });

  // A shopper's id is the admin web's, cu- and the phone's last seven
  // digits, so the same person is the same record on both sides. The id
  // keys every list the app keeps per account, so each must stay its own.
  test(
    "a shopper has the admin web's id; stores and email accounts keep theirs",
    () async {
      final container = await signedOut();
      String? id() => container.read(accountIdProvider);

      await as(container, 'shopper@saba.app');
      expect(id(), 'cu-1234567');
      await as(container, 'merchant@saba.app');
      expect(id(), 'u-merchant');
      await as(container, 'merchant2@saba.app');
      expect(id(), 'u-merchant-2');

      // A new shopper, by the number they signed up with.
      final auth = container.read(authControllerProvider.notifier);
      await auth.signOut();
      (await auth.registerCustomer(
        const CustomerRegistration(
          fullName: 'Ali First',
          password: 'Demo1234!',
          phone: '07512223344',
        ),
      )).unwrap();
      expect(id(), 'cu-2223344');
      final me = await data(container, ApiEndpoints.me) as Map;
      expect(me['id'], 'cu-2223344', reason: 'the server and the app differ');

      // An old email-only account has no number of its own: it must not
      // borrow Amina's, or it would open her cached lists.
      await as(container, 'old@example.com');
      expect(id(), 'u-old@example.com');
    },
  );

  // The tester: the dashboard said 10 orders and -12%, Analytics 3 orders
  // and +40%, for the same 2,353,000 IQD this month.
  test('the dashboard and Analytics count this month the same way', () async {
    final container = await signedOut();
    for (final store in ['merchant@saba.app', 'merchant2@saba.app']) {
      await as(container, store);
      final board =
          await data(container, ApiEndpoints.merchantDashboard) as Map;
      final month =
          await data(
                container,
                '${ApiEndpoints.merchantAnalytics}?period=month',
              )
              as Map;
      expect(board['revenue'], month['revenue'], reason: store);
      expect(board['orderCount'], month['orderCount'], reason: store);
      expect(board['previousRevenue'], month['previousRevenue'], reason: store);
    }
  });

  // The tester: the dashboard's chart was one bar. Its six months carry
  // their starts, for the app to name in the reader's language.
  test("the dashboard's chart has the store's months, each dated", () async {
    final container = await signedOut();
    await as(container, 'merchant@saba.app');
    final board = await data(container, ApiEndpoints.merchantDashboard) as Map;
    final series = (board['salesSeries'] as List).cast<Map>();
    expect(series, hasLength(6));
    expect(
      series.where((point) => (point['value'] as num) > 0).length,
      greaterThan(1),
      reason: 'one bar',
    );
    expect(series.every((point) => point['from'] != null), isTrue);
  });
}
