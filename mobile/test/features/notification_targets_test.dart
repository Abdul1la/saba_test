// Every notification leads to what it is about (the user). Only a shopper's
// order steps did: a store tapping "New order", the one it taps most, and a
// return's, a product's or a store's answer opened nothing. And a chat
// message told nobody, so a store missed a shopper's question unless it
// happened to open its chats.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import '../support/saba_web.dart';
import 'package:saba_marketplace/features/auth/domain/entities.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/cart/presentation/cart_providers.dart';
import 'package:saba_marketplace/features/checkout/presentation/checkout_providers.dart';
import 'package:saba_marketplace/features/merchant/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:saba_marketplace/features/messaging/presentation/messaging_providers.dart';
import 'package:saba_marketplace/features/notifications/presentation/notifications_providers.dart';
import 'package:saba_marketplace/features/orders/domain/orders_repository.dart';
import 'package:saba_marketplace/features/orders/presentation/orders_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _shopper = 'shopper@saba.app';
const _store = 'merchant@saba.app';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => DioFactory.mockBackend.resetForTesting());
  tearDown(() => DioFactory.mockBackend.resetForTesting());

  Future<ProviderContainer> as(String email) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'saba.pref.onboarding_seen': true,
      'saba.pref.locale': 'en',
    });
    final c = ProviderContainer(
      overrides: [
        appPreferencesProvider.overrideWithValue(await AppPreferences.create()),
      ],
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);
    (await c
            .read(authControllerProvider.notifier)
            .signIn(email: email, password: 'Password1'))
        .unwrap();
    return c;
  }

  /// The newest notification in [email]'s inbox whose title has [words].
  Future<AppNotification> told(String email, String words) async {
    final c = await as(email);
    final inbox = (await c.read(notificationsRepositoryProvider).fetch())
        .unwrap()
        .items;
    return inbox.firstWhere(
      (n) => n.title.contains(words),
      orElse: () => fail('$email was not told "$words"'),
    );
  }

  Future<String> placeOrder() async {
    final c = await as(_shopper);
    await c
        .read(cartControllerProvider.notifier)
        .addItem(productId: 'p-1', quantity: 1);
    final checkout = c.read(checkoutControllerProvider.notifier);
    await checkout.priceOrder();
    return (await checkout.placeOrder()).unwrap().orderId;
  }

  /// Nova's part of the newest order, and Nova's repository.
  Future<(MerchantRepository, String)> novaPart() async {
    final repo = (await as(_store)).read(merchantRepositoryProvider);
    return (repo, (await repo.orders()).unwrap().items.first.id);
  }

  test(
    'an order, its return and its cancelling each lead to the order',
    () async {
      await placeOrder();
      final (nova, part) = await novaPart();
      final newOrder = await told(_store, 'New order');
      expect((newOrder.targetType, newOrder.targetId), ('STORE_ORDER', part));

      for (final step in ['CONFIRMED', 'PROCESSING', 'SHIPPED', 'DELIVERED']) {
        (await nova.updateOrderStatus(
          orderId: part,
          status: step,
          courier: step == 'SHIPPED'
              ? const Courier(name: 'Ali', phone: '+9647701112222')
              : null,
        )).unwrap();
      }
      // The driver's number as every number is written.
      final onItsWay = await told(_shopper, 'on its way');
      expect(onItsWay.body, contains('+964 770 111 2222'));
      expect(onItsWay.targetType, 'ORDER');

      final shopper = await as(_shopper);
      final orders = shopper.read(ordersRepositoryProvider);
      final orderId = (await orders.fetchOrders()).unwrap().items.first.id;
      final order = (await orders.fetchOrder(orderId)).unwrap();
      (await orders.requestReturn(
        orderId: orderId,
        lines: [ReturnLine(orderItemId: order.items.first.id, quantity: 1)],
        reason: 'DAMAGED',
      )).unwrap();
      final asked = await told(_store, 'Return request');
      expect((asked.targetType, asked.targetId), ('STORE_ORDER', part));

      final (store, _) = await novaPart();
      final returnId = (await store.order(part)).unwrap().returns.single.id;
      (await store.answerReturn(returnId, 'APPROVED')).unwrap();
      final answered = await told(_shopper, 'will pick up');
      expect((answered.targetType, answered.targetId), ('RETURN', returnId));

      // Cancelled by the shopper: the store's part of that order.
      final second = await placeOrder();
      final (_, secondPart) = await novaPart();
      (await (await as(_shopper))
              .read(ordersRepositoryProvider)
              .cancelOrder(orderId: second, reason: 'CHANGED_MIND'))
          .unwrap();
      final cancelled = await told(_store, 'was cancelled');
      expect(
        (cancelled.targetType, cancelled.targetId),
        ('STORE_ORDER', secondPart),
      );
    },
  );

  test('a chat message tells the other side, both ways', () async {
    final shopper = await as(_shopper);
    final chats = shopper.read(messagingRepositoryProvider);
    final chat = (await chats.startWithStore('m-1')).unwrap();
    (await chats.send(
      conversationId: chat.id,
      body: 'Is it in black?',
    )).unwrap();
    final toStore = await told(_store, 'Message from');
    expect((toStore.targetType, toStore.targetId), ('CONVERSATION', chat.id));
    expect(toStore.body, 'Is it in black?');

    final store = await as(_store);
    (await store
            .read(messagingRepositoryProvider)
            .send(conversationId: chat.id, body: 'Yes, black is in stock.'))
        .unwrap();
    final toShopper = await told(_shopper, 'Message from Nova Electronics');
    expect(
      (toShopper.targetType, toShopper.targetId),
      ('CONVERSATION', chat.id),
    );
  });

  test("Saba's answers lead to the product and to the store", () async {
    final store = await as(_store);
    (await store
            .read(merchantRepositoryProvider)
            .saveProduct(
              const ProductDraft(
                name: 'Walk One',
                nameAr: 'منتج تجريبي',
                categoryId: 'c-1',
                price: 12250,
                description: 'A product for the walk, ten letters.',
              ),
            ))
        .unwrap();

    final admin = await as('admin@saba.app');
    final queue =
        (await admin
                .read(apiClientProvider)
                .get<Map<String, dynamic>>(
                  adminQueuePath,
                  decoder: (e) => e.dataAsMap,
                ))
            .unwrap();
    final productId = '${((queue['products'] as List).last as Map)['id']}';
    expect(
      await admin.read(adminAnswersProvider).product(productId, approve: true),
      isNull,
    );
    final approved = await told(_store, 'is approved');
    expect(
      (approved.targetType, approved.targetId),
      ('STORE_PRODUCT', productId),
    );

    // A new store, answered.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'saba.pref.onboarding_seen': true,
      'saba.pref.locale': 'en',
    });
    final opening = ProviderContainer(
      overrides: [
        appPreferencesProvider.overrideWithValue(await AppPreferences.create()),
      ],
      retry: (_, _) => null,
    );
    addTearDown(opening.dispose);
    (await opening
            .read(authControllerProvider.notifier)
            .registerMerchant(
              const MerchantRegistration(
                fullName: 'Walk Owner',
                password: 'Password1',
                phone: '+9647505550101',
                storeName: 'Walk Store',
                businessType: 'INDIVIDUAL',
                governorate: 'BAGHDAD',
              ),
            ))
        .unwrap();
    final storeId = opening.read(currentUserProvider)!.merchant!.id;
    // The demo serves one session at a time: Saba signs in again.
    final saba = await as('admin@saba.app');
    expect(
      await saba.read(adminAnswersProvider).store(storeId, approve: true),
      isNull,
    );
    await opening.read(authControllerProvider.notifier).signOut();
    (await opening
            .read(authControllerProvider.notifier)
            .signIn(phone: '+9647505550101', password: 'Password1'))
        .unwrap();
    final inbox = (await opening.read(notificationsRepositoryProvider).fetch())
        .unwrap()
        .items;
    final storeTold = inbox.firstWhere((n) => n.title.contains('approved'));
    expect(storeTold.targetType, 'STORE');
  });

  // The tester: the demo's own "Welcome" and "A new order" showed the time
  // of the last sign-in, and Nova's list had "Nova Electronics answered
  // you" - a store written to by itself.
  test("the demo's own notifications keep their time and their side", () async {
    Future<Map<String, DateTime>> canned() async {
      final store = await as(_store);
      final inbox = (await store.read(notificationsRepositoryProvider).fetch())
          .unwrap()
          .items;
      expect(
        inbox.map((n) => n.body),
        isNot(contains(contains('Nova Electronics answered'))),
      );
      return {
        for (final n in inbox)
          if (n.id.startsWith('n-')) n.id: n.createdAt,
      };
    }

    final first = await canned();
    expect(first, isNotEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(await canned(), first, reason: 'stamped again at each reading');
  });
}
