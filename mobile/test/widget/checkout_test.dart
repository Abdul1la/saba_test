// Checkout, arrived at the way a customer arrives at it.
//
// Two things were wrong. Nothing chose a payment method on arrival, so the
// customer met "Place order · 2,605,200 IQD" greyed out with nothing on
// screen saying why — shipping had always adopted the server's default, and
// payment simply had not. And the screen could say what the order cost and
// when it would arrive without ever saying how much of it there was.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/config/api_endpoints.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/core/utils/formatters.dart';
import 'package:saba_marketplace/features/addresses/presentation/address_providers.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/cart/presentation/cart_providers.dart';
import 'package:saba_marketplace/features/checkout/presentation/checkout_providers.dart';
import 'package:saba_marketplace/features/merchant/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

const _en = AppLocalizations(Locale('en'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = <String, String>{};

  setUp(() {
    store.clear();
    DioFactory.mockBackend.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_keystore, (call) async {
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
        .setMockMethodCallHandler(_keystore, null);
    DioFactory.mockBackend.resetForTesting();
  });

  /// Signs in, fills the cart with [cart] (product id to how many), and
  /// opens checkout.
  Future<ProviderContainer> pumpCheckout(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    Map<String, int> cart = const {'p-1': 2},
  }) async {
    tester.view.physicalSize = const Size(411 * 3, 914 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues(<String, Object>{
      'saba.pref.onboarding_seen': true,
    });
    final preferences = await AppPreferences.create();
    final container = ProviderContainer(
      overrides: [appPreferencesProvider.overrideWithValue(preferences)],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);

    // In `runAsync`: the demo backend answers after 350ms of real time, and a
    // widget test's clock is fake, so these would never complete out here.
    await tester.runAsync(() async {
      await container
          .read(authControllerProvider.notifier)
          .signIn(email: 'demo@saba.app', password: 'Password1');
      for (final MapEntry(key: productId, value: quantity) in cart.entries) {
        await container
            .read(cartControllerProvider.notifier)
            .addItem(productId: productId, quantity: quantity);
      }
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp.router(
            routerConfig: ref.watch(appRouterProvider),
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
          ),
        ),
      ),
    );
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    container.read(appRouterProvider).go(AppRoutes.checkout);
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    return container;
  }

  testWidgets('the pay button is live on arrival, not waiting on a tap', (
    tester,
  ) async {
    final container = await pumpCheckout(tester);
    final state = container.read(checkoutControllerProvider);

    expect(
      state.summary,
      isNotNull,
      reason: 'the order has to be priced for this test to mean anything',
    );
    expect(state.selection.paymentMethodId, isNotNull);
    expect(state.canPlaceOrder, isTrue);

    // And the customer can see which method is in force before committing.
    final chosen = state.summary!.paymentMethods.firstWhere(
      (method) => method.id == state.selection.paymentMethodId,
    );
    expect(chosen.isEnabled, isTrue);
    expect(find.text(chosen.label), findsOneWidget);
  });

  testWidgets('the delivery step says how much is in the box', (tester) async {
    final container = await pumpCheckout(tester);
    final summary = container.read(checkoutControllerProvider).summary!;
    final group = summary.groups.first;

    expect(group.itemCount, greaterThan(0));
    expect(
      find.textContaining(_en.counted(group.itemCount, CountNoun.item)),
      findsWidgets,
      reason: 'the delivery row leads with the count of what is being shipped',
    );
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  String iqd(num amount) =>
      Formatters.money(amount, locale: 'en', currencyCode: 'IQD');

  // p-1 is Nova Electronics', p-8 Atlas Home's: two stores, two drivers.
  const twoStores = {'p-1': 2, 'p-8': 1};

  testWidgets('cash only, and what to hand each store\'s driver', (
    tester,
  ) async {
    final container = await pumpCheckout(tester, cart: twoStores);
    final summary = container.read(checkoutControllerProvider).summary!;
    expect(summary.groups, hasLength(2));

    // Cash, and nothing greyed out beside it promising a card.
    expect(find.text('Coming soon'), findsNothing);
    expect(find.text(_en.codNote), findsOneWidget);

    // Under the total: each store's name beside what its driver takes.
    final block = find.text(_en.cashToEachDriver);
    await tester.scrollUntilVisible(
      block,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final drivers = find
        .ancestor(of: block, matching: find.byType(Column))
        .first;
    for (final group in summary.groups) {
      for (final text in [group.merchantName, iqd(group.amountDue!)]) {
        expect(
          find.descendant(of: drivers, matching: find.text(text)),
          findsOneWidget,
          reason: '$text is not in what to pay each driver',
        );
      }
    }

    // Placed, the order says it again, store by store.
    late String orderId;
    await tester.runAsync(() async {
      orderId =
          (await container
                  .read(checkoutControllerProvider.notifier)
                  .placeOrder())
              .unwrap()
              .orderId;
    });
    container.read(appRouterProvider).go(AppRoutes.orderDetailPath(orderId));
    await settle(tester);
    for (final group in summary.groups) {
      final line = '${_en.cashToDriver}: ${iqd(group.amountDue!)}';
      await tester.scrollUntilVisible(
        find.text(line),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(line), findsOneWidget, reason: 'no $line on the order');
    }

    // And Nova's order card says what its driver collects.
    await tester.runAsync(
      () => container
          .read(authControllerProvider.notifier)
          .signIn(email: 'merchant@saba.app', password: 'Password1'),
    );
    container.read(appRouterProvider).go(AppRoutes.merchantOrders);
    await settle(tester);
    final nova = summary.groups.singleWhere((g) => g.merchantId == 'm-1');
    final card = find.ancestor(
      of: find.text(iqd(nova.amountDue!)),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: card.first, matching: find.text(_en.collectInCash)),
      findsOneWidget,
      reason: "Nova's card does not say what to collect",
    );
  });

  // M4 step 10: a part refused at the door still read "Cash to the driver"
  // with the whole amount; there is nothing to pay for it.
  testWidgets('a part refused at the door asks for no cash', (tester) async {
    final container = await pumpCheckout(tester);
    final due = container
        .read(checkoutControllerProvider)
        .summary!
        .groups
        .single
        .amountDue!;
    late String orderId;
    late String part;
    final auth = container.read(authControllerProvider.notifier);
    await tester.runAsync(() async {
      orderId =
          (await container
                  .read(checkoutControllerProvider.notifier)
                  .placeOrder())
              .unwrap()
              .orderId;
      await auth.signIn(email: 'merchant@saba.app', password: 'Password1');
      final nova = container.read(merchantRepositoryProvider);
      part = (await nova.orders()).unwrap().items.first.id;
      for (final status in ['CONFIRMED', 'PROCESSING', 'SHIPPED', 'REFUSED']) {
        (await nova.updateOrderStatus(
          orderId: part,
          status: status,
          courier: status == 'SHIPPED'
              ? const Courier(name: 'Ali', phone: '+9647701112222')
              : null,
        )).unwrap();
      }
    });

    // The store's page: no cash to collect either.
    container
        .read(appRouterProvider)
        .go(AppRoutes.merchantOrderDetailPath(part));
    await settle(tester);
    expect(find.text(iqd(due), skipOffstage: false), findsWidgets);
    expect(
      find.text(_en.collectInCash, skipOffstage: false),
      findsNothing,
      reason: 'the store is told to collect for a refused parcel',
    );

    // And it can be found again: under Cancelled, with no cash to collect.
    container
        .read(appRouterProvider)
        .go(AppRoutes.merchantOrdersPath(status: 'REFUSED'));
    await settle(tester);
    expect(
      find.text(_en.orderStatusRefused),
      findsWidgets,
      reason: 'the refused order is in no tab',
    );
    expect(find.text(_en.collectInCash), findsNothing);

    await tester.runAsync(
      () => auth.signIn(email: 'demo@saba.app', password: 'Password1'),
    );
    container.read(appRouterProvider).go(AppRoutes.orderDetailPath(orderId));
    await settle(tester);

    // Its store's box is there, and says why it stopped.
    expect(
      find.textContaining(_en.refusedAtDoor, skipOffstage: false),
      findsWidgets,
    );
    expect(
      find.textContaining(_en.cashToDriver, skipOffstage: false),
      findsNothing,
      reason: 'a refused parcel still asks for its ${iqd(due)}',
    );
  });

  testWidgets("a new shopper's first order stops at 1,000,000 IQD", (
    tester,
  ) async {
    // p-9 is Nova's camera at 950,000 IQD: two are over the limit.
    final container = await pumpCheckout(tester, cart: {'p-9': 2});
    final state = container.read(checkoutControllerProvider);
    expect(state.summary!.total, greaterThan(1000000));

    // Once in its own box, and again under the grey button (BUGS.md 18).
    expect(
      find.textContaining('1,000,000 IQD'),
      findsNWidgets(2),
      reason: 'the shopper is not told why',
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
      reason: 'the pay button is live over the limit',
    );
  });

  testWidgets("a store that doesn't come to the address stops the order", (
    tester,
  ) async {
    // p-8 is Atlas Home's, which delivers around the south and to Baghdad.
    final container = await pumpCheckout(tester, cart: {'p-8': 1});

    // She sends it to Erbil instead.
    await tester.runAsync(() async {
      final erbil =
          (await container
                      .read(apiClientProvider)
                      .post<Map<String, dynamic>>(
                        ApiEndpoints.addresses,
                        data: <String, dynamic>{
                          'fullName': 'Amina Saleh',
                          'phone': '+9647701234567',
                          'governorate': 'ERBIL',
                          'area': 'Ainkawa',
                          'landmark': 'Next to Ainkawa Mall',
                        },
                        decoder: (envelope) => envelope.dataAsMap,
                      ))
                  .unwrap()['id']
              as String;
      container.invalidate(addressListProvider);
      await container.read(addressListProvider.future);
      await container
          .read(checkoutControllerProvider.notifier)
          .selectAddress(erbil);
    });
    await settle(tester);

    expect(
      find.text("Doesn't deliver to Erbil. ${_en.removeOrChangeAddress}"),
      findsOneWidget,
      reason: "Atlas's part does not say it cannot come",
    );
    // No "—" for its price (19), and not in the cash-limit box (17): it is
    // said on its own row, and under the grey button (18).
    expect(find.text('—'), findsNothing);
    expect(find.text(_en.noDelivery), findsOneWidget);
    expect(
      container.read(checkoutControllerProvider).summary!.warnings,
      isEmpty,
    );
    expect(
      find.text(
        "Atlas Home: Doesn't deliver to Erbil. ${_en.removeOrChangeAddress}",
      ),
      findsOneWidget,
      reason: 'the grey button does not say why',
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
      reason: 'the order can be placed to a city its store does not reach',
    );
    // Her Home city is Baghdad; the order goes where the address is.
    expect(
      find.text(_en.addressCityNote(home: 'Baghdad', city: 'Erbil')),
      findsOneWidget,
    );
  });

  testWidgets('checkout fits a phone in Arabic', (tester) async {
    // Asserts nothing beyond arriving: Flutter fails a test on any overflow,
    // and the route sweep has never seen this screen with a priced order on
    // it, because it needs a signed-in cart to get past the empty state.
    await pumpCheckout(tester, locale: const Locale('ar'));
    expect(find.byType(FilledButton), findsWidgets);
  });
}
