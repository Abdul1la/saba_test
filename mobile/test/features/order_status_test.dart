// One order, one status: what the shopper is told is what the store sees.
//
// A new order said "Confirmed" the moment it was paid for, while its store
// still had it as new and had not even called the shopper; its history
// said "Payment recorded" for a cash order nobody had paid; and when the
// store did confirm it, "Confirmed" appeared a second time. The two sides
// now start at the same place and move only when the store moves.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/mock/mock_data.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/checkout/domain/entities.dart';
import 'package:saba_marketplace/features/checkout/presentation/checkout_providers.dart';
import 'package:saba_marketplace/features/merchant/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:saba_marketplace/features/orders/domain/entities.dart';
import 'package:saba_marketplace/features/orders/presentation/orders_providers.dart';
import 'package:saba_marketplace/features/orders/presentation/widgets/order_notes.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _driver = Courier(name: 'Ali', phone: '+9647701112222');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final keys = <String, String>{};

  setUp(() {
    DioFactory.mockBackend.resetForTesting();
    keys.clear();
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

  Future<_Order> place({String language = 'en'}) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'saba.pref.onboarding_seen': true,
      'saba.pref.locale': language,
    });
    final container = ProviderContainer(
      overrides: [
        appPreferencesProvider.overrideWithValue(await AppPreferences.create()),
      ],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    final order = _Order(container);
    await order.signIn('shopper@saba.app');
    await order.buy();
    return order;
  }

  test('a new order waits for its store, and says so on both sides', () async {
    final order = await place();

    final shopper = await order.asShopper();
    expect(
      shopper.status,
      OrderStatus.pending,
      reason: 'the shopper is told "confirmed" before any store confirmed',
    );
    expect(
      shopper.items.map((item) => item.status),
      everyElement(OrderStatus.pending),
    );
    expect(shopper.canCancel, isTrue);

    // The store's own word for the same thing. Its screens say "New"; the
    // app reads it as the very status the shopper is shown.
    final part = await order.storePart();
    expect(part.status, 'PENDING');
    expect(OrderStatus.fromApi(part.status), shopper.status);
  });

  test('nothing is paid, and nothing is confirmed, at checkout', () async {
    final order = await place();
    final shopper = await order.asShopper();

    expect(shopper.paymentStatus, PaymentStatus.pending);
    expect(
      shopper.timeline.length,
      1,
      reason: 'the history invented a second step at checkout',
    );
    expect(shopper.timeline.single.status, OrderStatus.pending);
    expect(
      shopper.timeline.single.noteCode,
      'ORDER_RECEIVED',
      reason: 'the only step is the one that really happened',
    );
  });

  test(
    "the history is read in the reader's language, whoever wrote it",
    () async {
      // Placed in English; kept as a code, not an English sentence.
      final entry = (await (await place()).asShopper()).timeline.single;
      expect(entry.note, isNull);
      expect(
        timelineNote(const AppLocalizations(Locale('ar')), entry),
        'وصل الطلب',
        reason: 'an Arabic reader saw "Order received"',
      );
      expect(
        timelineNote(const AppLocalizations(Locale('en')), entry),
        'Order received',
      );
      // A cancel reason is a code too, and never shown as one.
      expect(
        timelineNote(
          const AppLocalizations(Locale('ar')),
          OrderTimelineEntry(
            status: OrderStatus.cancelled,
            occurredAt: DateTime(2026),
            reasonCode: 'CHANGED_MIND',
          ),
        ),
        const AppLocalizations(Locale('ar')).cancelReasonChangedMind,
      );
    },
  );

  test('only the store moves it, and the two sides never disagree', () async {
    final order = await place();
    final part = (await order.storePart()).id;

    // Every step the store takes, and what the shopper is told after it.
    for (final step in const [
      'CONFIRMED',
      'PROCESSING',
      'SHIPPED',
      'DELIVERED',
    ]) {
      await order.move(part, step);
      final shopper = await order.asShopper();
      final store = await order.storePart();

      expect(
        shopper.status,
        OrderStatus.fromApi(store.status),
        reason: 'after $step the two sides read differently',
      );
      expect(
        shopper.items.map((item) => item.status),
        everyElement(OrderStatus.fromApi(store.status)),
      );
      expect(
        shopper.timeline.last.status,
        OrderStatus.fromApi(step),
        reason: 'the store took a step the history does not show',
      );
    }

    final shopper = await order.asShopper();
    expect(
      shopper.timeline.where((e) => e.status == OrderStatus.confirmed).length,
      1,
      reason: '"Confirmed" is written twice',
    );
    // Cash, so it is paid when it arrives - not before.
    expect(shopper.paymentStatus, PaymentStatus.paid);
  });
}

/// One shopper's order, and the store's part of it.
class _Order {
  _Order(this.container);

  final ProviderContainer container;
  late final String id;

  /// A cheap, in-stock Nova product with no options.
  static final String product =
      MockData.products.firstWhere(
            (product) =>
                (product['merchant'] as Map)['id'] == 'm-1' &&
                product['variants'] == null &&
                product['stockStatus'] != 'OUT_OF_STOCK' &&
                (product['price'] as num) <= 300000,
          )['id']
          as String;

  Future<void> signIn(String email) async =>
      (await container
              .read(authControllerProvider.notifier)
              .signIn(email: email, password: 'Password1'))
          .unwrap();

  Future<void> buy() async {
    id =
        (await container
                .read(checkoutRepositoryProvider)
                .placeOrder(
                  selection: CheckoutSelection(
                    addressId: 'addr-1',
                    paymentMethodId: 'pm-cod',
                    buyNow: BuyNowLine(productId: product),
                  ),
                  idempotencyKey:
                      'status-${DateTime.now().microsecondsSinceEpoch}',
                ))
            .unwrap()
            .orderId;
  }

  /// The order as the shopper's app reads it.
  Future<Order> asShopper() async {
    await signIn('shopper@saba.app');
    return (await container.read(ordersRepositoryProvider).fetchOrder(id))
        .unwrap();
  }

  /// Nova's part of it, as the store's app reads it.
  Future<MerchantOrderRow> storePart() async {
    await signIn('merchant@saba.app');
    final rows =
        (await container.read(merchantRepositoryProvider).orders(status: null))
            .unwrap()
            .items;
    return rows.firstWhere((row) => row.orderNumber.isNotEmpty);
  }

  Future<void> move(String part, String step) async {
    await signIn('merchant@saba.app');
    (await container
            .read(merchantRepositoryProvider)
            .updateOrderStatus(
              orderId: part,
              status: step,
              courier: step == 'SHIPPED' ? _driver : null,
            ))
        .unwrap();
  }
}
