// Fewer surprises between seeing a product and owning it.
//
// A card's bag button put a product in the cart with no colour or size
// chosen, a line the store cannot pack. Signing in from a product dropped the
// customer on Home with the product gone. And checkout priced delivery at
// 9.99 beside a cart that had charged 5,000 IQD, with Express changing
// nothing at all.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/app.dart';
import 'package:saba_marketplace/core/config/api_endpoints.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/mock/mock_data.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/core/widgets/app_button.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/auth/presentation/screens/login_screen.dart';
import 'package:saba_marketplace/features/cart/presentation/cart_providers.dart';
import 'package:saba_marketplace/features/catalog/presentation/screens/product_detail_screen.dart';
import 'package:saba_marketplace/features/checkout/presentation/screens/checkout_screen.dart';
import 'package:saba_marketplace/features/catalog/presentation/widgets/product_card.dart';
import 'package:saba_marketplace/features/orders/presentation/screens/orders_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// Where the image cache keeps its files. A test has no phone to ask, and
/// Home's pictures would otherwise fail the test before it checks anything.
const _paths = MethodChannel('plugins.flutter.io/path_provider');

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

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          _paths,
          (_) async => Directory.systemTemp.path,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_paths, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_keystore, null);
    DioFactory.mockBackend.resetForTesting();
  });

  /// The app on a phone; signed in as [email], or signed out when null.
  Future<(ProviderContainer, Future<void> Function())> pumpApp(
    WidgetTester tester, {
    String? email,
  }) async {
    tester.view.physicalSize = const Size(411 * 3, 914 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues(<String, Object>{
      'saba.pref.onboarding_seen': true,
      'saba.pref.locale': 'en',
    });
    final preferences = await AppPreferences.create();
    final container = ProviderContainer(
      overrides: [appPreferencesProvider.overrideWithValue(preferences)],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);

    if (email != null) {
      await tester.runAsync(() async {
        await container
            .read(authControllerProvider.notifier)
            .signIn(email: email, password: 'Password1');
      });
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SabaApp()),
    );

    Future<void> settle() async {
      for (var i = 0; i < 18; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    await settle();
    return (container, settle);
  }

  testWidgets('a card for a product with options opens it, not adds it bare', (
    tester,
  ) async {
    final (container, settle) = await pumpApp(tester, email: 'demo@saba.app');
    container.read(appRouterProvider).go(AppRoutes.home);
    await settle();

    bool withOptions(Widget widget) =>
        widget is FlashSaleCard && widget.product.hasOptions;
    final card = find.byWidgetPredicate(withOptions);
    final feed = find
        .byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        )
        .first;
    // Down to the flash sale, then along it: the soonest to end comes
    // first, so the one sold in options may be further along.
    final flash = find.byType(FlashSaleCard);
    for (var step = 0; step < 10 && flash.evaluate().isEmpty; step++) {
      await tester.drag(feed, const Offset(0, -300));
      await settle();
    }
    await tester.ensureVisible(flash.first);
    await settle();
    await tester.scrollUntilVisible(
      card,
      250,
      scrollable: find.ancestor(
        of: flash.first,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              axisDirectionToAxis(widget.axisDirection) == Axis.horizontal,
        ),
      ),
    );
    expect(card, findsWidgets, reason: 'no card with options on Home');

    final add = find.descendant(
      of: card.first,
      matching: find.byType(CornerActionButton),
    );
    await tester.ensureVisible(add);
    await tester.pump();
    await tester.tap(add);
    await settle();

    expect(
      container.read(cartControllerProvider).requireValue.isEmpty,
      isTrue,
      reason: 'the product went in with no options chosen',
    );
    expect(
      find.byType(ProductDetailScreen),
      findsOneWidget,
      reason: 'the button did not lead to where the options are chosen',
    );
  });

  /// Signs in through the form, as a person does.
  Future<void> signInWithForm(
    WidgetTester tester,
    Future<void> Function() settle,
  ) async {
    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(2), reason: 'the sign-in form is not up');
    // By phone, the way people sign in: Amina, the demo shopper.
    await tester.enterText(fields.at(0), '07701234567');
    await tester.enterText(fields.at(1), 'Password1');
    await tester.pump();
    final button = find.widgetWithText(FilledButton, _en.signIn);
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button);
    await settle();
  }

  testWidgets('signing in goes back to the product it was opened from', (
    tester,
  ) async {
    final (container, settle) = await pumpApp(tester);
    container.read(appRouterProvider).go(AppRoutes.productDetailPath('p-1'));
    await settle();

    // Anything on the product that needs an account opens sign-in; the
    // bar at the bottom is on screen without scrolling.
    await tester.tap(find.text(_en.addToCart).last);
    await settle();
    expect(find.byType(LoginScreen), findsOneWidget);

    await signInWithForm(tester, settle);

    expect(
      find.byType(LoginScreen),
      findsNothing,
      reason: 'sign-in stayed on screen after signing in',
    );
    expect(find.byType(ProductDetailScreen), findsOneWidget);
  });

  testWidgets('a page that asked for sign-in opens once signed in', (
    tester,
  ) async {
    final (container, settle) = await pumpApp(tester);
    container.read(appRouterProvider).go(AppRoutes.orders);
    await settle();
    expect(find.byType(LoginScreen), findsOneWidget);

    await signInWithForm(tester, settle);

    expect(
      find.byType(OrdersScreen),
      findsOneWidget,
      reason: 'signing in forgot where the customer was going',
    );
  });

  testWidgets('Buy now buys the one product and leaves the cart as it was', (
    tester,
  ) async {
    final (container, settle) = await pumpApp(tester, email: 'demo@saba.app');
    final client = container.read(apiClientProvider);
    final inCart = MockData.productById('p-5')!['name'] as String;
    final bought = MockData.productById('p-7')!['name'] as String;

    // Something already waiting in the cart.
    await tester.runAsync(() async {
      (await client.command(
        ApiEndpoints.cartItems,
        data: <String, dynamic>{'productId': 'p-5', 'quantity': 1},
      )).unwrap();
    });

    container.read(appRouterProvider).go(AppRoutes.productDetailPath('p-7'));
    await settle();
    await tester.tap(find.text(_en.buyNow).last);
    await settle();

    expect(find.byType(CheckoutScreen), findsOneWidget);
    expect(find.textContaining(bought), findsOneWidget);
    expect(
      find.textContaining(inCart),
      findsNothing,
      reason: 'Buy now checked out the whole cart',
    );

    await tester.tap(find.textContaining(_en.placeOrder));
    await settle();
    expect(find.text(_en.orderPlaced), findsOneWidget);

    late Map<String, dynamic> cart;
    await tester.runAsync(() async {
      cart = (await client.get<Map<String, dynamic>>(
        ApiEndpoints.cart,
        decoder: (envelope) => envelope.dataAsMap,
      )).unwrap();
    });
    final names = [
      for (final group in cart['groups'] as List)
        for (final item in (group as Map)['items'] as List)
          (item as Map)['name'],
    ];
    expect(names, [
      inCart,
    ], reason: 'Buy now emptied the cart, or left its product in it');
  });

  testWidgets("delivery is the store's own fee, the same the cart charged", (
    tester,
  ) async {
    final (container, _) = await pumpApp(tester, email: 'demo@saba.app');
    final client = container.read(apiClientProvider);

    late Map<String, dynamic> cart;
    late Map<String, dynamic> review;
    await tester.runAsync(() async {
      // One item from Nova, in Baghdad, going to the Baghdad address.
      (await client.command(
        ApiEndpoints.cartItems,
        data: <String, dynamic>{'productId': 'p-5', 'quantity': 1},
      )).unwrap();
      cart = (await client.get<Map<String, dynamic>>(
        ApiEndpoints.cart,
        decoder: (envelope) => envelope.dataAsMap,
      )).unwrap();
      review = (await client.post<Map<String, dynamic>>(
        ApiEndpoints.checkoutReview,
        data: <String, dynamic>{'addressId': 'addr-1'},
        decoder: (envelope) => envelope.dataAsMap,
      )).unwrap();
    });

    // One way to deliver: the store's own, at its in-city fee, in dinars -
    // not a Standard and an Express invented for every store alike.
    final group = (review['groups'] as List).single as Map;
    final options = group['shippingOptions'] as List;
    expect(options, hasLength(1));
    final option = options.single as Map;
    expect(option['fee'], 3000, reason: "not Nova's fee in its own city");
    expect(option['currencyCode'], 'IQD', reason: 'delivery in another money');
    expect(
      (cart['totals'] as Map)['shipping'],
      option['fee'],
      reason: 'the cart and checkout charged different delivery',
    );
  });
}
