// Several people use one phone, one after another, in ONE app session.
//
// Every earlier test started a fresh app for each account, so none could see
// what a real phone showed: the lists one account had opened stayed in the
// app for the next. A store that signed in after another opened on the other
// store's dashboard, orders and bill; a new shopper saw the last one's
// orders and notifications. Here the app keeps running while the accounts
// change - and, in the last test, is closed and opened again.
import 'package:flutter/material.dart';
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
import 'package:saba_marketplace/features/addresses/presentation/address_providers.dart';
import 'package:saba_marketplace/features/auth/domain/entities.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/cart/presentation/cart_providers.dart';
import 'package:saba_marketplace/features/checkout/domain/entities.dart';
import 'package:saba_marketplace/features/checkout/presentation/checkout_providers.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:saba_marketplace/features/notifications/presentation/notifications_providers.dart';
import 'package:saba_marketplace/features/orders/presentation/orders_providers.dart';
import 'package:saba_marketplace/features/wishlist/presentation/wishlist_providers.dart';
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

  /// The app, running, signed in as [email]. The same [preferences] stand
  /// for the same phone.
  Future<_Phone> openApp(
    WidgetTester tester,
    String email, {
    AppPreferences? preferences,
  }) async {
    tester.view.physicalSize = const Size(411 * 3, 914 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    if (preferences == null) {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'saba.pref.onboarding_seen': true,
        'saba.pref.locale': 'en',
      });
    }
    final phonePreferences = preferences ?? await AppPreferences.create();
    final container = ProviderContainer(
      overrides: [appPreferencesProvider.overrideWithValue(phonePreferences)],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);

    final phone = _Phone(tester, container, phonePreferences);
    await phone.signIn(email);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SabaApp()),
    );
    await phone.settle();
    return phone;
  }

  testWidgets("two shoppers on one phone never see each other's things", (
    tester,
  ) async {
    final phone = await openApp(tester, 'shopper@saba.app');
    final amina = phone.read(accountIdProvider);

    // Amina fills her account...
    await phone.run(
      () =>
          phone.read(cartControllerProvider.notifier).addItem(productId: 'p-1'),
    );
    await phone.favourite('p-2');
    final order = await phone.buy('p-3');
    await phone.run(
      () => phone.preferences.addRecentSearch('nova', account: amina),
    );
    // ...and opens her lists, so the app is holding them.
    for (final route in [
      AppRoutes.orders,
      AppRoutes.wishlist,
      AppRoutes.notifications,
      AppRoutes.addresses,
      AppRoutes.cart,
    ]) {
      await phone.go(route);
    }
    expect(phone.orderIds(), contains(order));
    expect(phone.wishlistIds(), contains('p-2'));
    expect(phone.cartProductIds(), contains('p-1'));
    expect(phone.notificationIds(), isNotEmpty);
    expect(phone.addressCount(), 1);

    // --- someone new signs up on the same phone ---------------------------
    await phone.signOut();
    await phone.signUpShopper(
      'Sara Kareem',
      'sara@gmail.com',
      '+9647701111111',
    );
    final sara = phone.read(accountIdProvider);
    expect(sara, isNotNull);
    expect(sara, isNot(amina), reason: 'two accounts, one id');

    for (final route in [
      AppRoutes.orders,
      AppRoutes.wishlist,
      AppRoutes.notifications,
      AppRoutes.addresses,
      AppRoutes.cart,
    ]) {
      await phone.go(route);
    }
    expect(phone.orderIds(), isEmpty, reason: "Sara sees Amina's orders");
    expect(phone.wishlistIds(), isEmpty, reason: "Sara sees Amina's wishlist");
    expect(phone.cartProductIds(), isEmpty, reason: "Sara sees Amina's cart");
    expect(
      phone.notificationIds(),
      isEmpty,
      reason: "Sara sees Amina's notifications",
    );
    expect(phone.addressCount(), 0, reason: "Sara sees Amina's addresses");
    await phone.go(AppRoutes.search);
    expect(
      find.text('nova'),
      findsNothing,
      reason: "Sara sees Amina's recent searches",
    );

    // --- Amina comes back, and everything is where she left it ----------
    await phone.signOut();
    await phone.signIn('shopper@saba.app');
    expect(phone.read(accountIdProvider), amina);
    for (final route in [
      AppRoutes.orders,
      AppRoutes.wishlist,
      AppRoutes.addresses,
      AppRoutes.cart,
    ]) {
      await phone.go(route);
    }
    expect(phone.orderIds(), contains(order));
    expect(phone.wishlistIds(), contains('p-2'));
    expect(phone.cartProductIds(), contains('p-1'));
    expect(phone.addressCount(), 1);
    await phone.go(AppRoutes.search);
    expect(find.text('nova'), findsOneWidget);
  });

  testWidgets('two stores on one phone each see only their own', (
    tester,
  ) async {
    final phone = await openApp(tester, 'merchant@saba.app');

    // Omar's Nova, opened: the app now holds its dashboard, shelf, orders
    // and bill.
    final nova = await phone.storeView();

    await phone.signOut();
    await phone.signIn('merchant2@saba.app');
    final atlas = await phone.storeView();

    // What the screens hold is Atlas's - what the server says Atlas has.
    expect(atlas, await phone.storeOnServer(), reason: "Layla sees Nova's");
    expect(
      atlas.products.intersection(nova.products),
      isEmpty,
      reason: "Layla's shelf holds Nova's products",
    );
    expect(atlas, isNot(nova));

    // And back: Nova as Omar left it.
    await phone.signOut();
    await phone.signIn('merchant@saba.app');
    expect(await phone.storeView(), nova);
  });

  testWidgets('two new stores on one phone are two stores', (tester) async {
    final phone = await openApp(tester, 'shopper@saba.app');
    await phone.signOut();

    await phone.signUpStore('Omar Hadi', 'omar@gmail.com', '+9647702222222');
    final first = phone.read(currentUserProvider)!.merchant!.id;
    final firstView = await phone.storeView();

    await phone.signOut();
    await phone.signUpStore('Lolav Aziz', 'lolav@gmail.com', '+9647703333333');
    final second = phone.read(currentUserProvider)!.merchant!.id;

    expect(second, isNot(first), reason: 'two new stores share one id');
    expect(await phone.storeView(), await phone.storeOnServer());
    expect(phone.read(currentUserProvider)!.merchant!.storeName, 'Lolav Aziz');

    await phone.signOut();
    await phone.signIn('omar@gmail.com');
    expect(phone.read(currentUserProvider)!.merchant!.id, first);
    expect(await phone.storeView(), firstView);
  });

  testWidgets("closing the app keeps every account's own things", (
    tester,
  ) async {
    // The phone's storage: what the demo server wrote, and how often.
    String? saved;
    var writes = 0;
    void save(String document) {
      saved = document;
      writes++;
    }

    DioFactory.mockBackend.keepOnDevice(saved: null, save: save);
    final phone = await openApp(tester, 'shopper@saba.app');
    await phone.run(
      () =>
          phone.read(cartControllerProvider.notifier).addItem(productId: 'p-1'),
    );
    await phone.favourite('p-2');
    final order = await phone.buy('p-3');
    expect(saved, isNotNull, reason: 'nothing was kept on the phone');

    // --- the app is closed: everything in memory is gone ------------------
    await tester.pumpWidget(const SizedBox());
    DioFactory.mockBackend.resetForTesting();
    final kept = saved;
    writes = 0;
    DioFactory.mockBackend.keepOnDevice(saved: kept, save: save);

    // Read back exactly: asking for something changes nothing, so nothing
    // new is written.
    final reopened = await openApp(
      tester,
      'shopper@saba.app',
      preferences: phone.preferences,
    );
    await reopened.run(
      () => reopened
          .read(apiClientProvider)
          .get<Object?>('/categories', decoder: (_) => null),
    );
    expect(writes, 0, reason: 'what was read back is not what was kept');

    for (final route in [
      AppRoutes.orders,
      AppRoutes.wishlist,
      AppRoutes.cart,
    ]) {
      await reopened.go(route);
    }
    expect(reopened.orderIds(), contains(order));
    expect(reopened.wishlistIds(), contains('p-2'));
    expect(reopened.cartProductIds(), contains('p-1'));

    // A store's step reaches the order Amina kept: it is still the one
    // order, not a copy.
    await reopened.signOut();
    await reopened.signIn('merchant@saba.app');
    final store = reopened.read(merchantRepositoryProvider);
    final part = (await reopened.run(
      () => store.orders(status: 'PENDING'),
    )).unwrap().items.first;
    (await reopened.run(
      () => store.updateOrderStatus(orderId: part.id, status: 'CONFIRMED'),
    )).unwrap();
    await reopened.signOut();
    await reopened.signIn('shopper@saba.app');
    final detail = (await reopened.run(
      () => reopened.read(ordersRepositoryProvider).fetchOrder(order),
    )).unwrap();
    expect(
      detail.timeline.map((entry) => entry.storeName),
      contains('Nova Electronics'),
      reason: "the store's step did not reach the kept order",
    );

    // Someone new on the reopened app starts with nothing.
    await reopened.signOut();
    await reopened.signUpShopper(
      'Sara Kareem',
      'sara@gmail.com',
      '+9647701111111',
    );
    await reopened.go(AppRoutes.orders);
    expect(reopened.orderIds(), isEmpty);
  });
}

/// One phone with the app open on it.
class _Phone {
  _Phone(this.tester, this.container, this.preferences);

  final WidgetTester tester;
  final ProviderContainer container;
  final AppPreferences preferences;

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

  Future<void> signIn(String email) async {
    (await run(
      () => read(
        authControllerProvider.notifier,
      ).signIn(email: email, password: 'Password1'),
    )).unwrap();
    await settle();
  }

  Future<void> signOut() async {
    await run(() => read(authControllerProvider.notifier).signOut());
    await settle();
  }

  Future<void> signUpShopper(String name, String email, String phone) async {
    (await run(
      () => read(authControllerProvider.notifier).registerCustomer(
        CustomerRegistration(
          fullName: name,
          email: email,
          password: 'Demo1234!',
          phone: phone,
        ),
      ),
    )).unwrap();
    await settle();
  }

  Future<void> signUpStore(String name, String email, String phone) async {
    (await run(
      () => read(authControllerProvider.notifier).registerMerchant(
        MerchantRegistration(
          fullName: name,
          email: email,
          password: 'Demo1234!',
          phone: phone,
          storeName: name,
          businessType: 'INDIVIDUAL',
          country: 'Iraq',
          governorate: 'BASRA',
        ),
      ),
    )).unwrap();
    await settle();
  }

  /// Adds [product] to the wishlist, as the heart does.
  Future<void> favourite(String product) async {
    (await run(() => read(wishlistRepositoryProvider).add(product))).unwrap();
    await run(() => read(wishlistControllerProvider.notifier).refresh());
  }

  /// Buys one [product], cash, to the account's first address; the order id.
  Future<String> buy(String product) async {
    final addresses = await run(() => read(addressListProvider.future));
    final placed = await run(
      () => read(checkoutRepositoryProvider).placeOrder(
        selection: CheckoutSelection(
          addressId: addresses.first.id,
          paymentMethodId: 'pm-cod',
          buyNow: BuyNowLine(productId: product),
        ),
        idempotencyKey: 'buy-$product-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    return placed.unwrap().orderId;
  }

  Set<String> orderIds() => {
    for (final order in read(orderListProvider(null)).requireValue.items)
      order.id,
  };

  Set<String> wishlistIds() => {
    for (final product in read(wishlistControllerProvider).requireValue)
      product.id,
  };

  Set<String> cartProductIds() => {
    for (final item in read(cartControllerProvider).requireValue.allItems)
      item.productId,
  };

  Set<String> notificationIds() => {
    for (final notification in read(
      notificationListProvider,
    ).requireValue.items)
      notification.id,
  };

  int addressCount() => read(addressListProvider).requireValue.length;

  /// What the store screens hold, after opening each one.
  Future<_Store> storeView() async {
    for (final route in [
      AppRoutes.merchantDashboard,
      AppRoutes.merchantProducts,
      AppRoutes.merchantOrders,
      AppRoutes.merchantPayouts,
    ]) {
      await go(route);
    }
    return _Store(
      dashboard: _dashboard(read(merchantDashboardProvider).requireValue),
      products: {
        for (final row in read(
          merchantProductsProvider((filter: null, query: null)),
        ).requireValue.items)
          row.id,
      },
      orders: read(merchantOrderCountsProvider).requireValue,
      bill: read(sabaBillsProvider).requireValue.current.owed,
    );
  }

  /// The same, asked of the server directly.
  Future<_Store> storeOnServer() async {
    final store = read(merchantRepositoryProvider);
    return _Store(
      dashboard: _dashboard((await run(store.dashboard)).unwrap()),
      products: {
        for (final row in (await run(
          () => store.products(filter: null, query: null, page: 1),
        )).unwrap().items)
          row.id,
      },
      orders: (await run(store.orderCounts)).unwrap(),
      bill: (await run(store.bills)).unwrap().current.owed,
    );
  }

  static List<num> _dashboard(dynamic board) => [
    board.revenue as num,
    board.orderCount as num,
    board.productCount as num,
    board.pendingOrders as num,
  ];
}

/// What one store's screens show.
@immutable
class _Store {
  const _Store({
    required this.dashboard,
    required this.products,
    required this.orders,
    required this.bill,
  });

  final List<num> dashboard;
  final Set<String> products;
  final Map<String, int> orders;
  final num bill;

  @override
  bool operator ==(Object other) =>
      other is _Store &&
      _same(dashboard, other.dashboard) &&
      _same(products.toList()..sort(), other.products.toList()..sort()) &&
      _same(_counts(orders), _counts(other.orders)) &&
      bill == other.bill;

  static List<String> _counts(Map<String, int> counts) =>
      [for (final entry in counts.entries) '${entry.key}=${entry.value}']
        ..sort();

  static bool _same(List<Object> a, List<Object> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((same) => same);

  @override
  int get hashCode => Object.hash(bill, products.length, orders.length);

  @override
  String toString() =>
      'dashboard $dashboard, ${products.length} products, '
      '${orders.length} orders, bill $bill';
}
