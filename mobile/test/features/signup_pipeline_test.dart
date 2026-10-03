import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saba_marketplace/core/config/api_endpoints.dart';
import 'package:saba_marketplace/core/mock/mock_data.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/domain/entities.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/cart/presentation/cart_providers.dart';
import 'package:saba_marketplace/features/merchant/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:saba_marketplace/features/messaging/presentation/messaging_providers.dart';

/// Sign-up through the real pipeline, down to the demo backend:
///
///   AuthController → repository → Dio → MockApiInterceptor → mappers
///
/// The demo backend kept an email from sign-up and nothing else, and chose
/// the role by whether the address contained "merchant". A shopper who signed
/// up landed in the demo shopper's account under her name; a merchant who
/// signed up as omar@gmail.com landed in the shopper app. Store settings, for
/// its part, saved through the "open a store" branch and put the demo store
/// back under review. These pin all three.
const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = <String, String>{};
  late AppPreferences preferences;

  setUp(() async {
    DioFactory.mockBackend.resetForTesting();
    store.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    preferences = await AppPreferences.create();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
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

  /// A store as the backend returns it: to the merchant, or to a shopper.
  Future<Map<String, dynamic>> readStore(
    ProviderContainer container,
    String path,
  ) async {
    final result = await container
        .read(apiClientProvider)
        .get<Map<String, dynamic>>(
          path,
          decoder: (envelope) => envelope.dataAsMap,
        );
    return result.unwrap();
  }

  test('a new shopper is the account they created', () async {
    final container = await signedOut();

    final user =
        (await container
                .read(authControllerProvider.notifier)
                .registerCustomer(
                  const CustomerRegistration(
                    fullName: 'Sara Kareem',
                    email: 'sara@gmail.com',
                    password: 'Demo1234!',
                    phone: '+9647701111111',
                  ),
                ))
            .unwrap();

    expect(user.fullName, 'Sara Kareem', reason: 'signed in as the demo');
    expect(user.email, 'sara@gmail.com');
    expect(user.role.isMerchant, isFalse);
  });

  test('a new merchant is a merchant, with the store they described', () async {
    final container = await signedOut();

    final user =
        (await container
                .read(authControllerProvider.notifier)
                .registerMerchant(
                  const MerchantRegistration(
                    fullName: 'Omar Hadi',
                    email: 'omar@gmail.com',
                    password: 'Demo1234!',
                    phone: '+9647702222222',
                    storeName: 'Omar Phones',
                    businessType: 'INDIVIDUAL',
                    country: 'Iraq',
                    governorate: 'BASRA',
                  ),
                ))
            .unwrap();

    expect(user.role.isMerchant, isTrue, reason: 'landed in the shopper app');
    expect(user.fullName, 'Omar Hadi');
    expect(user.merchant?.storeName, 'Omar Phones');
    // The sign-up form says a new store waits for approval; so does the app.
    expect(user.merchant?.status, MerchantStatus.pending);

    // What they typed is what their settings screen and their public page say.
    final own = await readStore(container, ApiEndpoints.merchantStoreSettings);
    expect(own['storeName'], 'Omar Phones');
    expect(own['governorate'], 'BASRA');

    final public = await readStore(
      container,
      ApiEndpoints.merchantStore(user.merchant!.id),
    );
    expect(
      public['governorate'],
      'BASRA',
      reason: 'a shopper cannot see the city',
    );
    expect(public['country'], 'Iraq');
  });

  test('saving store settings keeps the store and its approval', () async {
    final container = await signedOut();
    final notifier = container.read(authControllerProvider.notifier);
    (await notifier.signIn(
      email: 'merchant@saba.app',
      password: 'Password1',
    )).unwrap();

    final saved = await container
        .read(apiClientProvider)
        .command(
          ApiEndpoints.merchantStoreSettings,
          method: 'PUT',
          data: <String, dynamic>{
            'storeName': 'Nova Mobile',
            'governorate': 'ERBIL',
          },
        );
    expect(saved.isOk, isTrue);

    final own = await readStore(container, ApiEndpoints.merchantStoreSettings);
    expect(own['storeName'], 'Nova Mobile', reason: 'the edit did not stick');
    expect(own['governorate'], 'ERBIL');

    // Signing in again reads the account fresh from the backend.
    final again = (await notifier.signIn(
      email: 'merchant@saba.app',
      password: 'Password1',
    )).unwrap();
    expect(
      again.merchant?.status,
      MerchantStatus.approved,
      reason: 'editing the store put it back under review',
    );
    expect(again.merchant?.id, 'm-1', reason: 'the store became a new one');
    expect(again.merchant?.storeName, 'Nova Mobile');

    final public = await readStore(
      container,
      ApiEndpoints.merchantStore('m-1'),
    );
    expect(public['governorate'], 'ERBIL');
  });

  // A merchant who signed up as "lolav" opened a dashboard showing the demo
  // store's 18,420,000 in revenue, its 142 orders and its 4.8 rating.
  test('a new store starts empty, and holds what the merchant adds', () async {
    final container = await signedOut();
    (await container
            .read(authControllerProvider.notifier)
            .registerMerchant(
              const MerchantRegistration(
                fullName: 'Lolav Aziz',
                email: 'lolav@gmail.com',
                password: 'Demo1234!',
                phone: '+9647703333333',
                storeName: 'lolav',
                businessType: 'INDIVIDUAL',
                country: 'Iraq',
                governorate: 'ERBIL',
              ),
            ))
        .unwrap();
    final repository = container.read(merchantRepositoryProvider);

    final dashboard = (await repository.dashboard()).unwrap();
    expect(dashboard.revenue, 0, reason: "the demo store's revenue");
    expect(dashboard.orderCount, 0);
    expect(dashboard.pendingOrders, 0);
    expect(dashboard.productCount, 0);
    expect(dashboard.outOfStockCount, 0);
    expect(dashboard.rating, isNull, reason: 'rated before selling anything');
    expect(dashboard.previousRevenue, isNull);
    expect(dashboard.salesSeries, isEmpty);

    expect((await repository.orders()).unwrap().items, isEmpty);
    expect((await repository.products()).unwrap().items, isEmpty);
    expect((await repository.inventory()).unwrap().items, isEmpty);
    final analytics = (await repository.analytics()).unwrap();
    expect(analytics.revenue, 0);
    expect(analytics.topProducts, isEmpty);
    final bills = (await repository.bills()).unwrap();
    expect(bills.current.owed, 0);
    expect(bills.past, isEmpty);

    final unread = await readStore(container, ApiEndpoints.unreadCount);
    expect(unread['count'], 0, reason: "the demo customer's notifications");

    // Their first product is on their shelf, waiting for review.
    final saved = await repository.saveProduct(
      const ProductDraft(
        name: 'Lolav Phone Case',
        nameAr: 'غطاء هاتف لولاف',
        categoryId: 'c-phone-cases',
        price: 15000,
        stock: 4,
      ),
    );
    expect(saved.isOk, isTrue);

    final shelf = (await repository.products()).unwrap().items;
    expect(shelf.map((p) => p.name), ['Lolav Phone Case']);
    expect(shelf.single.status, 'PENDING');
    expect((await repository.inventory()).unwrap().items, hasLength(1));
    expect((await repository.dashboard()).unwrap().productCount, 1);
    final full = (await repository.product(shelf.single.id)).unwrap();
    expect(full.name, 'Lolav Phone Case', reason: 'edit could not open it');
  });

  // A shopper who signed up opened My orders on two orders someone else had
  // placed earlier in the session: the demo backend held one order list, one
  // cart and one address book for everybody.
  test(
    'a new shopper starts empty, and the last account gets its own back',
    () async {
      final container = await signedOut();
      final notifier = container.read(authControllerProvider.notifier);
      final client = container.read(apiClientProvider);

      Future<List<Map<String, dynamic>>> list(String path) async =>
          (await client.get<List<Map<String, dynamic>>>(
            path,
            decoder: (envelope) => envelope.dataAsList,
          )).unwrap();

      (await notifier.signIn(
        email: 'shopper@saba.app',
        password: 'Password1',
      )).unwrap();
      expect(
        (await client.command(
          ApiEndpoints.cartItems,
          data: <String, dynamic>{'productId': 'p-2', 'quantity': 1},
        )).isOk,
        isTrue,
      );
      expect(
        (await client.command(ApiEndpoints.checkoutPlaceOrder)).isOk,
        isTrue,
      );
      await client.command(
        ApiEndpoints.cartItems,
        data: <String, dynamic>{'productId': 'p-5', 'quantity': 1},
      );
      expect(await list(ApiEndpoints.orders), hasLength(1));

      (await notifier.registerCustomer(
        const CustomerRegistration(
          fullName: 'Sara Kareem',
          email: 'sara@gmail.com',
          password: 'Demo1234!',
          phone: '+9647701111111',
        ),
      )).unwrap();
      expect(
        await list(ApiEndpoints.orders),
        isEmpty,
        reason: "the last shopper's orders",
      );
      expect(await list(ApiEndpoints.addresses), isEmpty);
      final cart = await readStore(container, ApiEndpoints.cart);
      expect(
        (cart['groups'] as List?) ?? const <dynamic>[],
        isEmpty,
        reason: "the last shopper's cart",
      );

      // Back to the first shopper: their order and their cart are still theirs.
      (await notifier.signIn(
        email: 'shopper@saba.app',
        password: 'Password1',
      )).unwrap();
      expect(await list(ApiEndpoints.orders), hasLength(1));
      final again = await readStore(container, ApiEndpoints.cart);
      expect((again['groups'] as List?) ?? const <dynamic>[], isNotEmpty);
    },
  );

  test('only a coupon that exists goes on', () async {
    final container = await signedOut();
    (await container
            .read(authControllerProvider.notifier)
            .signIn(email: 'shopper@saba.app', password: 'Password1'))
        .unwrap();
    final client = container.read(apiClientProvider);
    await client.command(
      ApiEndpoints.cartItems,
      data: <String, dynamic>{'productId': 'p-2', 'quantity': 1},
    );

    // p-2 is Atlas Home's; ATLAS5000 is Atlas's own code.
    final typo = await client.command(
      ApiEndpoints.cartCoupon,
      data: <String, dynamic>{'code': 'ATLAS500'},
    );
    expect(typo.isOk, isFalse, reason: 'a typo was "applied" at no discount');
    expect((await readStore(container, ApiEndpoints.cart))['coupon'], isNull);

    final real = await client.command(
      ApiEndpoints.cartCoupon,
      data: <String, dynamic>{'code': 'atlas5000'},
    );
    expect(real.isOk, isTrue);
    final cart = await readStore(container, ApiEndpoints.cart);
    expect((cart['coupon'] as Map)['code'], 'ATLAS5000');
    expect((cart['coupon'] as Map)['discountAmount'] as num, greaterThan(0));
  });

  // The cart asked for a code and nothing said where one comes from. The
  // stores' own coupons are offered now. Saba's own - SABA10, a first-order
  // WELCOME - wait for v2: a cash-only v1 has nothing to pay them from.
  test(
    "a new shopper is offered the stores' coupons, and none of Saba's",
    () async {
      final container = await signedOut();
      (await container
              .read(authControllerProvider.notifier)
              .registerCustomer(
                const CustomerRegistration(
                  fullName: 'Sara Kareem',
                  email: 'sara@gmail.com',
                  password: 'Demo1234!',
                  phone: '+9647701111111',
                ),
              ))
          .unwrap();
      final repository = container.read(cartRepositoryProvider);
      final client = container.read(apiClientProvider);

      final offers = (await repository.availableCoupons()).unwrap();
      expect(
        offers.where((o) => o.merchantId == null),
        isEmpty,
        reason: 'a Saba-wide coupon was offered in v1',
      );
      expect(offers.map((o) => o.code), containsAll(['NOVA10', 'ATLAS5000']));

      await repository.addItem(productId: 'p-2');
      for (final saba in ['SABA10', 'WELCOME']) {
        expect(
          (await repository.applyCoupon(saba)).isOk,
          isFalse,
          reason: "Saba's $saba still takes money off",
        );
      }
      final cart = (await repository.applyCoupon('atlas5000')).unwrap();
      expect(cart.totals.couponDiscount, 5000);
      expect(
        (await client.command(ApiEndpoints.checkoutPlaceOrder)).isOk,
        isTrue,
      );
    },
  );

  test('the demo store keeps its own figures', () async {
    final container = await signedOut();
    (await container
            .read(authControllerProvider.notifier)
            .signIn(email: 'merchant@saba.app', password: 'Password1'))
        .unwrap();
    final repository = container.read(merchantRepositoryProvider);

    // Six months of sales, not this month's revenue: on the 1st, before
    // anything is delivered, that is rightly nothing, and this test failed
    // every month there (BUGS 221). A new store's six months are empty.
    final dashboard = (await repository.dashboard()).unwrap();
    expect(
      dashboard.salesSeries.fold<num>(0, (sum, point) => sum + point.value),
      greaterThan(0),
    );
    expect((await repository.orders()).unwrap().items, isNotEmpty);
    expect((await repository.products()).unwrap().items, isNotEmpty);
  });

  // The chat was one-sided: a shopper had no way to start one, and a store's
  // inbox listed other stores instead of its customers.
  test('a shopper writes to a store, and the store answers', () async {
    final container = await signedOut();
    final notifier = container.read(authControllerProvider.notifier);
    final chats = container.read(messagingRepositoryProvider);

    (await notifier.registerCustomer(
      const CustomerRegistration(
        fullName: 'Sara Kareem',
        email: 'sara@gmail.com',
        password: 'Demo1234!',
        phone: '+9647701111111',
      ),
    )).unwrap();
    expect(
      (await chats.conversations()).unwrap(),
      isEmpty,
      reason: "another account's chats",
    );

    final chat = (await chats.startWithStore('m-1')).unwrap();
    expect(chat.title, 'Nova Electronics');
    (await chats.send(
      conversationId: chat.id,
      body: 'Is it in stock?',
    )).unwrap();

    // The store that was written to has it, from her, waiting.
    (await notifier.signIn(
      email: 'merchant@saba.app',
      password: 'Password1',
    )).unwrap();
    final inbox = (await chats.conversations()).unwrap();
    final fromHer = inbox.where((each) => each.id == chat.id);
    expect(fromHer, hasLength(1), reason: 'the store never got the message');
    expect(fromHer.single.title, 'Sara Kareem');
    expect(fromHer.single.unreadCount, 1);
    expect(
      inbox.map((each) => each.title),
      isNot(contains('Atlas Home')),
      reason: "a store's inbox listed another store",
    );
    final thread = (await chats.messages(chat.id)).unwrap().items;
    expect(thread.single.body, 'Is it in stock?');
    expect(thread.single.isMine, isFalse);
    (await chats.send(
      conversationId: chat.id,
      body: 'Yes, in blue and black.',
    )).unwrap();

    // Back to her: the answer is there, not yet read.
    (await notifier.signIn(
      email: 'sara@gmail.com',
      password: 'Demo1234!',
    )).unwrap();
    final mine = (await chats.conversations()).unwrap().single;
    expect(mine.title, 'Nova Electronics');
    expect(mine.lastMessage, 'Yes, in blue and black.');
    expect(mine.unreadCount, 1);
  });

  // A store's own coupon, end to end: the merchant makes it, a shopper sees
  // it and uses it on that store's things only, and the use is counted.
  test('a store makes a coupon, and a shopper uses it at that store', () async {
    final container = await signedOut();
    final notifier = container.read(authControllerProvider.notifier);
    final client = container.read(apiClientProvider);
    final store = container.read(merchantRepositoryProvider);
    final today = DateTime.now();

    // An in-stock product with no options, from each of two stores.
    String productOf(String merchantId) =>
        MockData.products.firstWhere(
              (product) =>
                  (product['merchant'] as Map)['id'] == merchantId &&
                  product['variants'] == null &&
                  product['stockStatus'] != 'OUT_OF_STOCK',
            )['id']
            as String;

    (await notifier.signIn(
      email: 'merchant@saba.app',
      password: 'Password1',
    )).unwrap();
    final existing = (await store.coupons()).unwrap();
    expect(existing.map((coupon) => coupon.code), contains('NOVA10'));

    final taken = await store.saveCoupon(
      MerchantCoupon(
        id: '',
        code: 'ATLAS5000',
        isPercentage: true,
        value: 5,
        startsAt: today,
      ),
    );
    expect(taken.isOk, isFalse, reason: "a store took another store's code");

    (await store.saveCoupon(
      MerchantCoupon(
        id: '',
        code: 'NOVA25',
        isPercentage: true,
        value: 25,
        startsAt: today,
        usageLimit: 1,
      ),
    )).unwrap();

    // A shopper is offered it, by the store's name; not one that has not
    // started yet.
    (await notifier.signIn(
      email: 'shopper@saba.app',
      password: 'Password1',
    )).unwrap();
    final offers =
        (await container.read(cartRepositoryProvider).availableCoupons())
            .unwrap();
    final nova25 = offers.where((offer) => offer.code == 'NOVA25');
    expect(nova25, hasLength(1), reason: 'the new coupon was not offered');
    expect(nova25.single.merchantName, 'Nova Electronics');
    expect(
      offers.map((offer) => offer.code),
      isNot(contains('WEEKEND15')),
      reason: 'a coupon that starts later was offered now',
    );

    // Not without that store's things in the cart.
    await client.command(
      ApiEndpoints.cartItems,
      data: <String, dynamic>{'productId': productOf('m-2'), 'quantity': 1},
    );
    final early = await client.command(
      ApiEndpoints.cartCoupon,
      data: <String, dynamic>{'code': 'NOVA25'},
    );
    expect(early.isOk, isFalse, reason: 'a store code went on another store');

    // With them, it takes a quarter off that store's part only.
    await client.command(
      ApiEndpoints.cartItems,
      data: <String, dynamic>{'productId': productOf('m-1'), 'quantity': 1},
    );
    (await client.command(
      ApiEndpoints.cartCoupon,
      data: <String, dynamic>{'code': 'NOVA25'},
    )).unwrap();
    final cart = await readStore(container, ApiEndpoints.cart);
    final nova = (cart['groups'] as List).cast<Map>().singleWhere(
      (group) => (group['merchant'] as Map)['id'] == 'm-1',
    );
    expect(
      ((cart['totals'] as Map)['couponDiscount'] as num).round(),
      ((nova['subtotal'] as num) * 25 / 100).round(),
      reason: 'the discount was not a quarter of that store part',
    );

    // Placing the order uses it; with a limit of one, it is then used up.
    (await client.command(ApiEndpoints.checkoutPlaceOrder)).unwrap();
    expect(
      (await container.read(cartRepositoryProvider).availableCoupons())
          .unwrap()
          .map((offer) => offer.code),
      isNot(contains('NOVA25')),
      reason: 'a used-up coupon was still offered',
    );
    (await notifier.signIn(
      email: 'merchant@saba.app',
      password: 'Password1',
    )).unwrap();
    final after = (await store.coupons()).unwrap().singleWhere(
      (coupon) => coupon.code == 'NOVA25',
    );
    expect(after.usedCount, 1);
    expect(after.statusAt(DateTime.now()), CouponStatus.usedUp);
  });
}
