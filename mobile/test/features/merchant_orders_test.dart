import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/errors/result.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saba_marketplace/features/merchant/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';

/// The merchant fulfilment queue, through the real pipeline:
///
///   repository → Dio → MockApiInterceptor → mappers
///
/// Three things are checked here because all three were broken at once, and
/// each of them made the screen lie in a different way:
///
///   * the status filter was sent and ignored, so all eight tabs listed the
///     same eight orders;
///   * a status change replied 200 with an empty body onto a list that was
///     regenerated per request, so "Next: Confirmed" reported success and the
///     card stayed on New;
///   * there was no order detail at all, so nothing in the app ever showed
///     the merchant the items or the address they were meant to post to.
/// The only thing faked below the repository: the platform keystore has no
/// implementation in a test binding, and the auth interceptor reads it on
/// every request.
const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPreferences preferences;

  setUp(() async {
    DioFactory.mockBackend.resetForTesting();
    // Every request reads Accept-Language, which reaches this provider; left
    // unoverridden it throws and the whole call surfaces as a bare network
    // failure.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    preferences = await AppPreferences.create();
    final store = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          switch (call.method) {
            case 'write':
              store[call.arguments['key'] as String] =
                  call.arguments['value'] as String? ?? '';
              return null;
            case 'read':
              return store[call.arguments['key'] as String];
            case 'readAll':
              return Map<String, String>.from(store);
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [appPreferencesProvider.overrideWithValue(preferences)],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    return container;
  }

  MerchantRepository repository() =>
      makeContainer().read(merchantRepositoryProvider);

  test('a product opens for editing in its own category', () async {
    // The smartwatch was seen in the edit form under "Smartphones".
    final watch = (await repository().product('p-7')).unwrap();
    expect(watch.name, 'Nova Watch Series 4');
    expect(watch.categoryId, 'c-watches');
  });

  test('the status filter narrows the list instead of being ignored', () async {
    final repo = repository();

    final all = (await repo.orders()).unwrap();
    final preparing = (await repo.orders(status: 'PROCESSING')).unwrap();

    expect(all.items, isNotEmpty);
    expect(preparing.items, isNotEmpty);
    expect(preparing.items.length, lessThan(all.items.length));
    expect(preparing.items.every((o) => o.status == 'PROCESSING'), isTrue);
  });

  test('advancing an order actually moves it', () async {
    final repo = repository();

    final before = (await repo.orders(status: 'PENDING')).unwrap().items.first;
    expect(before.status, 'PENDING');

    final update = await repo.updateOrderStatus(
      orderId: before.id,
      status: 'CONFIRMED',
    );
    expect(update, isA<Ok<void>>());

    // Re-read the way the screen does, rather than trusting the reply.
    final after = (await repo.order(before.id)).unwrap();
    expect(after.row.status, 'CONFIRMED');

    // ...and it has left the tab it was in.
    final stillNew = (await repo.orders(status: 'PENDING')).unwrap();
    expect(stillNew.items.any((o) => o.id == before.id), isFalse);
  });

  // v1 has no delivery companies: the store names its own driver when it
  // ships, and there is no tracking number.
  test("the store's driver is kept at SHIPPED", () async {
    final repo = repository();

    // The step before shipping.
    final order = (await repo.orders(
      status: 'PROCESSING',
    )).unwrap().items.first;
    // Shipping says who is bringing it.
    expect(
      (await repo.updateOrderStatus(orderId: order.id, status: 'SHIPPED')).isOk,
      isFalse,
      reason: 'shipped with no one named to bring it',
    );
    (await repo.updateOrderStatus(
      orderId: order.id,
      status: 'SHIPPED',
      courier: const Courier(name: 'Ali Driver', phone: '+9647801112222'),
    )).unwrap();

    final after = (await repo.order(order.id)).unwrap();
    expect(after.row.status, 'SHIPPED');
    expect(after.courier?.name, 'Ali Driver');
    expect(after.courier?.phone, '+9647801112222');
  });

  test('a seeded shipped order has a driver, not a tracking number', () async {
    final repo = repository();
    final shipped = (await repo.orders(status: 'SHIPPED')).unwrap().items.first;
    final detail = (await repo.order(shipped.id)).unwrap();
    // Nova's own driver, as the admin web has him.
    expect(detail.courier?.name, 'Haider Salim');
    expect(detail.courier?.phone, '+9647705550311');
  });

  test('order detail carries what it takes to fulfil the order', () async {
    final repo = repository();

    final row = (await repo.orders()).unwrap().items.first;
    final detail = (await repo.order(row.id)).unwrap();

    expect(detail.row.orderNumber, row.orderNumber);
    expect(detail.items, isNotEmpty);
    expect(detail.items.first.quantity, greaterThan(0));
    expect(detail.shippingAddress, isNotNull);
    expect(detail.customerPhone, isNotNull);

    // The breakdown has to add up, or the screen is three numbers that
    // happen to sit near each other.
    final lines = detail.items.fold<num>(
      0,
      (sum, item) => sum + item.price * item.quantity,
    );
    expect(lines, detail.subtotal);
    expect(detail.subtotal + detail.shipping, detail.row.total);
  });

  test('a bucket fetches several statuses in one request', () async {
    final repo = repository();

    // "Preparing" is two states of the workflow at once, so the queue asks
    // for them together rather than firing two requests and stitching.
    final preparing = (await repo.orders(
      status: 'CONFIRMED,PROCESSING',
    )).unwrap();

    expect(preparing.items, isNotEmpty);
    expect(
      preparing.items.every(
        (o) => const {'CONFIRMED', 'PROCESSING'}.contains(o.status),
      ),
      isTrue,
    );
    expect(preparing.items.map((o) => o.status).toSet().length, greaterThan(1));
  });

  test('counts are reported per status, so a pill can carry its own', () async {
    final repo = repository();

    final counts = (await repo.orderCounts()).unwrap();
    final all = (await repo.orders()).unwrap();

    expect(counts, isNotEmpty);
    expect(
      counts.values.fold<int>(0, (sum, value) => sum + value),
      all.items.length,
    );
  });

  test('declining cancels the order and records why', () async {
    final repo = repository();

    final order = (await repo.orders(status: 'PENDING')).unwrap().items.first;
    final result = await repo.updateOrderStatus(
      orderId: order.id,
      status: 'CANCELLED',
      reason: 'Out of stock',
    );
    expect(result, isA<Ok<void>>());

    final after = (await repo.order(order.id)).unwrap();
    expect(after.row.status, 'CANCELLED');

    // ...and it has left the bucket the merchant was looking at.
    final stillNew = (await repo.orders(status: 'PENDING')).unwrap();
    expect(stillNew.items.any((o) => o.id == order.id), isFalse);
  });

  test('a queue card carries what the decision needs', () async {
    final repo = repository();

    final order = (await repo.orders(status: 'PENDING')).unwrap().items.first;

    // An item count and a total is enough to recognise an order and not
    // enough to answer one.
    expect(order.items, isNotEmpty);
    expect(order.customerArea, isNotNull);
    expect(order.paymentMethodLabel, isNotNull);
  });

  // The analytics tabs send ?period= and the backend dropped it, so Week,
  // Month and Year drew the same revenue over the same six bars — the same
  // fault as the status filter above, one screen across.
  test('the analytics period changes what comes back', () async {
    final repo = repository();

    final week = (await repo.analytics(period: 'week')).unwrap();
    final month = (await repo.analytics(period: 'month')).unwrap();
    final year = (await repo.analytics(period: 'year')).unwrap();

    // Counted from the store's orders: a year holds its month, and a week's
    // days add up to the week.
    expect(year.revenue, greaterThanOrEqualTo(month.revenue));
    expect(
      week.series.fold<num>(0, (sum, point) => sum + point.value),
      week.revenue,
    );

    // A week is drawn in days, a month in its weeks so far and a year in its
    // months so far; six bars for all three is how the old screen looked
    // identical whichever tab was chosen.
    final now = DateTime.now();
    expect(week.series, hasLength(7));
    expect(month.series, hasLength((now.day + 6) ~/ 7));
    expect(year.series, hasLength(now.month));

    // And asking twice gives the same answer, so pulling to refresh does not
    // redraw a different week.
    final again = (await repo.analytics(period: 'week')).unwrap();
    expect(
      again.series.map((point) => point.value).toList(),
      week.series.map((point) => point.value).toList(),
    );
  });
}
