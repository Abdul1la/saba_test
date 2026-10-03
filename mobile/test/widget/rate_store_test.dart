// A shopper rates the store that delivered, not the product.
//
// Version 1 took product reviews out: a shopper who has just taken a parcel
// from a driver knows how the store did, not how good the kettle is. So one
// sheet, for one delivered order, asking whether it came and giving a row of
// stars to each store that was in it - and the store's rating moves.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/app.dart';
import 'package:saba_marketplace/core/config/api_endpoints.dart';
import 'package:saba_marketplace/features/orders/presentation/orders_providers.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/catalog/presentation/screens/storefront_screen.dart';
import 'package:saba_marketplace/features/checkout/domain/entities.dart';
import 'package:saba_marketplace/features/checkout/presentation/checkout_providers.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:saba_marketplace/features/reviews/presentation/rate_order_providers.dart';
import 'package:saba_marketplace/features/reviews/presentation/widgets/rate_order_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _en = AppLocalizations(Locale('en'));

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

  testWidgets('nothing is asked until an order has been delivered', (
    tester,
  ) async {
    final app = await open(tester, 'shopper@saba.app');
    expect(
      await app.run(() => app.read(orderToRateProvider.future)),
      isNull,
      reason: 'a shopper with nothing delivered was asked to rate it',
    );

    await app.buy();
    // Asked again, not read back from what the first answer left behind:
    // the sheet is offered once when the app opens, so the provider holds
    // its answer, and a test that did not ask again proved nothing.
    expect(
      await app.askAgain(),
      isNull,
      reason: 'asked about an order the store has not even confirmed',
    );
  });

  testWidgets('the sheet asks once the parcel has arrived, and rates stores', (
    tester,
  ) async {
    final app = await open(tester, 'shopper@saba.app');
    final order = await app.buy();
    await app.deliverIt();

    final due = await app.run(() => app.read(orderToRateProvider.future));
    expect(due, isNotNull, reason: 'a delivered order is not asked about');
    expect(due!.orderId, order);
    expect(
      due.stores.map((store) => store.id),
      contains('m-1'),
      reason: 'the store that delivered is not on the sheet',
    );

    // The app asked by itself when the shopper came back to it: one sheet,
    // the question first, then a row of stars per store and one Submit.
    expect(
      find.byType(RateOrderSheet),
      findsOneWidget,
      reason: 'the app did not ask about a delivered order on its own',
    );
    expect(find.text(_en.didYourOrderArrive), findsOneWidget);
    // And about which store, before anything is answered (BUGS.md 85).
    expect(due.stores.first.storeName, 'Nova Electronics');
    expect(
      find.descendant(
        of: find.byType(RateOrderSheet),
        matching: find.textContaining('Nova Electronics'),
      ),
      findsOneWidget,
      reason: 'the sheet does not say which store it is asking about',
    );
    await tester.tap(find.text(_en.yesItArrived));
    await app.settle();

    await tester.tap(find.byKey(const ValueKey<String>('rate-m-1-5')));
    await app.settle();
    await tester.tap(find.text(_en.submit));
    await app.settle();

    expect(
      await app.run(() => app.read(orderToRateProvider.future)),
      isNull,
      reason: 'the same order is asked about again after being rated',
    );
  });

  // The tester: the sheet and the order page kept asking after "Yes, it
  // arrived". Both ask one thing, and one answer settles it for both.
  testWidgets('one answer to "did it arrive" stops both questions', (
    tester,
  ) async {
    final app = await open(tester, 'shopper@saba.app');
    final client = app.read(apiClientProvider);

    // One order from Nova and Atlas, both delivered.
    final shelf = (await app.run(
      () => client.get<List<dynamic>>(
        ApiEndpoints.products,
        queryParameters: {'pageSize': 100},
        decoder: (envelope) => envelope.data as List<dynamic>,
      ),
    )).unwrap().cast<Map>();
    for (final store in ['m-1', 'm-2']) {
      final product = shelf.firstWhere(
        (p) => (p['merchant'] as Map)['id'] == store && p['hasOptions'] != true,
      );
      (await app.run(
        () => client.command(
          ApiEndpoints.cartItems,
          data: {'productId': product['id'], 'quantity': 1},
        ),
      )).unwrap();
    }
    final order = (await app.run(
      () => app
          .read(checkoutRepositoryProvider)
          .placeOrder(
            selection: const CheckoutSelection(
              addressId: 'addr-1',
              paymentMethodId: 'pm-cod',
            ),
            idempotencyKey: 'two-stores',
          ),
    )).unwrap().orderId;
    await app.deliverIt();
    await app.deliverIt(store: 'merchant2@saba.app');

    // Yes, it arrived; stars for Nova alone.
    expect(find.byType(RateOrderSheet), findsOneWidget);
    await tester.tap(find.text(_en.yesItArrived));
    await app.settle();
    expect(find.text(_en.howWasYourOrder), findsOneWidget);
    expect(find.text(_en.didYourOrderArrive), findsNothing);
    await tester.tap(find.byKey(const ValueKey<String>('rate-m-1-4')));
    await app.settle();
    await tester.tap(find.text(_en.submit));
    await app.settle();

    expect(await app.askAgain(), isNull, reason: 'the sheet asks again');
    final parts = (await app.run(
      () => app.read(ordersRepositoryProvider).fetchOrder(order),
    )).unwrap().parts;
    expect(
      parts.values.map((part) => part.received),
      everyElement(isTrue),
      reason: 'the order page asks again about the store given no stars',
    );
  });

  // The tester, again: the sheet kept coming back on Home and Account. The
  // shell asked each time it was built, and it is built again on the way
  // back from a page outside it; with a second order delivered, that was
  // the sheet again at once.
  testWidgets(
    'the sheet is shown once an app opening, however the shell is rebuilt',
    (tester) async {
      final app = await open(tester, 'shopper@saba.app');
      await app.buy();
      await app.deliverIt();
      await app.buy();
      await app.deliverIt();
      expect(find.byType(RateOrderSheet), findsOneWidget);
      await tester.tap(find.text(_en.notNow));
      await app.settle();

      final router = app.read(appRouterProvider);
      for (final route in [
        AppRoutes.productDetailPath('p-1'),
        AppRoutes.home,
        AppRoutes.account,
        AppRoutes.home,
      ]) {
        router.go(route);
        await app.settle();
        expect(
          find.byType(RateOrderSheet),
          findsNothing,
          reason: 'back at $route',
        );
      }
    },
  );

  // The tester: "Yes, it arrived" only moved on to the stars and saved
  // nothing; closed there, the order was asked about again at every
  // opening, and the order page asked "Did you receive it?" too.
  testWidgets('"Yes, it arrived" is kept even when no stars follow', (
    tester,
  ) async {
    final app = await open(tester, 'shopper@saba.app');
    final order = await app.buy();
    await app.deliverIt();
    expect(find.byType(RateOrderSheet), findsOneWidget);
    await tester.tap(find.text(_en.yesItArrived));
    await app.settle();
    // Closed at the stars, nothing rated.
    Navigator.of(tester.element(find.byType(RateOrderSheet))).pop();
    await app.settle();

    expect(await app.askAgain(), isNull, reason: 'asked again');
    final parts = (await app.run(
      () => app.read(ordersRepositoryProvider).fetchOrder(order),
    )).unwrap().parts;
    expect(
      parts.values.map((part) => part.received),
      everyElement(isTrue),
      reason: 'the order page asks "Did you receive it?" again',
    );
  });

  testWidgets('answered on the order page, the sheet does not ask', (
    tester,
  ) async {
    final app = await open(tester, 'shopper@saba.app');
    final order = await app.buy();
    await app.deliverIt();
    (await app.run(
      () => app
          .read(ordersRepositoryProvider)
          .confirmReceived(orderId: order, merchantId: 'm-1', received: true),
    )).unwrap();
    expect(await app.askAgain(), isNull, reason: 'the sheet asks again');
  });

  testWidgets("the store's rating moves, and its own dashboard shows it", (
    tester,
  ) async {
    final app = await open(tester, 'shopper@saba.app');
    final before = await app.storeRating('m-1');

    await app.buy();
    await app.deliverIt();
    final due = await app.run(() => app.read(orderToRateProvider.future));
    await app.run(
      () => app
          .read(rateOrderProvider)
          .rate(
            orderId: due!.orderId,
            stars: <String, int>{'m-1': 1},
            comment: 'Late, and the box was open.',
          ),
    );

    expect(
      await app.storeRating('m-1'),
      lessThan(before),
      reason: 'one star from a shopper did not move the store',
    );

    // The store reads it on its own dashboard, and has no way to change it.
    await app.signOut();
    await app.signIn('merchant@saba.app');
    final dashboard = await app.run(
      () => app.read(merchantDashboardProvider.future),
    );
    expect(dashboard.rating, isNotNull);
    expect(dashboard.rating, lessThan(before));
  });

  testWidgets('put off three times, an order stops being asked about', (
    tester,
  ) async {
    final app = await open(tester, 'shopper@saba.app');
    await app.buy();
    await app.deliverIt();

    for (var asked = 0; asked < 3; asked++) {
      final due = await app.run(() => app.read(orderToRateProvider.future));
      expect(due, isNotNull, reason: 'stopped asking after $asked times');
      await app.run(() => app.read(rateOrderProvider).notNow(due!.orderId));
    }

    expect(
      await app.run(() => app.read(orderToRateProvider.future)),
      isNull,
      reason: 'a shopper who has said "not now" three times is still asked',
    );
  });

  testWidgets('"not yet" rates nobody and tells the store', (tester) async {
    final app = await open(tester, 'shopper@saba.app');
    final before = await app.storeRating('m-1');
    await app.buy();
    await app.deliverIt();

    final due = await app.run(() => app.read(orderToRateProvider.future));
    await app.run(() => app.read(rateOrderProvider).notArrived(due!.orderId));

    expect(
      await app.storeRating('m-1'),
      before,
      reason: 'a parcel that never came still changed the store\'s rating',
    );
    expect(
      await app.run(() => app.read(orderToRateProvider.future)),
      isNull,
      reason: 'asked again about an order that never arrived',
    );
  });
}

/// The app, running.
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

  /// Buys the cheapest thing in the demo shop; the order's id.
  Future<String> buy() async {
    final placed = await run(
      () => read(checkoutRepositoryProvider).placeOrder(
        selection: const CheckoutSelection(
          addressId: 'addr-1',
          paymentMethodId: 'pm-cod',
          buyNow: BuyNowLine(productId: 'p-1'),
        ),
        idempotencyKey: 'rate-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await settle();
    return placed.unwrap().orderId;
  }

  /// Nova takes the newest order all the way to the door, then the shopper
  /// is back.
  Future<void> deliverIt({String store = 'merchant@saba.app'}) async {
    await signOut();
    await signIn(store);
    final rows = await run(
      () => read(merchantOrdersProvider(null).notifier).future,
    );
    final part = rows.items.first.id;
    for (final step in const [
      'CONFIRMED',
      'PROCESSING',
      'SHIPPED',
      'DELIVERED',
    ]) {
      await run(
        () => read(
          merchantRepositoryProvider,
        ).updateOrderStatus(orderId: part, status: step),
      );
    }
    await signOut();
    await signIn('shopper@saba.app');
  }

  /// The server asked afresh. The provider answers once per app opening,
  /// which is what the app wants and what a test has to step around.
  Future<OrderToRate?> askAgain() {
    container.invalidate(orderToRateProvider);
    return run(() => read(orderToRateProvider.future));
  }

  /// What a shopper sees on the store's own page.
  Future<double> storeRating(String storeId) async {
    final store = await run(() => read(merchantStoreProvider(storeId).future));
    container.invalidate(merchantStoreProvider(storeId));
    return store.rating;
  }
}
