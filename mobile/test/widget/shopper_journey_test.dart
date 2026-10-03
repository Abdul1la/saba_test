// One customer, one shopping trip, done by tapping.
//
// Every other test here drives a provider or jumps to a route. This one only
// presses what is on the screen — a product, Add to cart, the Cart tab, the
// quantity, Checkout, Place order, View order — because a screen that renders
// and a screen that can be used are different claims, and only the second one
// is what the app is for.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/app.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/core/widgets/option_selector.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/cart/presentation/cart_providers.dart';
import 'package:saba_marketplace/features/catalog/presentation/screens/product_detail_screen.dart';
import 'package:saba_marketplace/features/catalog/presentation/widgets/product_card.dart';
import 'package:saba_marketplace/features/checkout/presentation/screens/checkout_screen.dart';
import 'package:saba_marketplace/features/orders/presentation/screens/order_detail_screen.dart';
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

  testWidgets('a customer buys something without ever leaving the screen', (
    tester,
  ) async {
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

    // Signing in has its own end-to-end test through the form; this trip
    // starts from a customer who is already in.
    await tester.runAsync(() async {
      await container
          .read(authControllerProvider.notifier)
          .signIn(email: 'demo@saba.app', password: 'Password1');
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SabaApp()),
    );

    Future<void> settle() async {
      for (var i = 0; i < 18; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    Future<void> press(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pump();
      await tester.tap(finder);
      await settle();
    }

    await settle();
    container.read(appRouterProvider).go(AppRoutes.home);
    await settle();

    // --- a product on the home feed -------------------------------------
    // The feed is built lazily and the grid of every product sits below the
    // flash sale, the coupons and the stores, so it is scrolled to, as a
    // person would.
    final feed = find
        .byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        )
        .first;
    for (
      var step = 0;
      step < 10 && find.byType(ProductCard).evaluate().isEmpty;
      step++
    ) {
      await tester.drag(feed, const Offset(0, -300));
      await settle();
    }
    final card = find.byType(ProductCard).first;
    expect(card, findsOneWidget, reason: 'home has nothing to sell');
    await press(card);
    expect(
      find.byType(ProductDetailScreen),
      findsOneWidget,
      reason: 'a product card on Home did not open the product',
    );

    // --- pick the options, the way a person has to ------------------------
    //
    // The first product on the demo feed has variants, and a product with
    // options cannot be added until they are all chosen — the server would
    // reject an ambiguous line anyway. So the trip picks one of each, which
    // is what a customer does before the button will work.
    // Colour is drawn as swatches and the rest as boxes, each under its
    // own name in the options block below the price, so both have to be
    // answered — "all of them chosen" is what the button waits for.
    await tester.scrollUntilVisible(
      find.byType(OptionSelector),
      200,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pump();
    for (final group in <Finder>[
      find.byType(ColourSwatchColumn),
      find.byType(OptionSelector),
    ]) {
      for (var index = 0; index < group.evaluate().length; index++) {
        // A predicate, not byType: the swatches are InkResponse and the
        // boxes are InkWell, and byType matches the exact class. InkWell is
        // an InkResponse, so this catches both.
        final options = find.descendant(
          of: group.at(index),
          matching: find.byWidgetPredicate((widget) => widget is InkResponse),
        );
        if (options.evaluate().isEmpty) continue;
        await press(options.first);
      }
    }

    // --- into the cart ---------------------------------------------------
    await press(find.text(_en.addToCart).last);
    expect(
      container.read(cartControllerProvider).requireValue.allItems,
      hasLength(1),
      reason: 'Add to cart did not put anything in the cart',
    );

    // The snackbar offers the cart; a real customer takes it.
    await press(find.text(_en.cart).last);
    expect(find.text(_en.myCart), findsOneWidget);

    // --- change your mind about how many --------------------------------
    final before = container
        .read(cartControllerProvider)
        .requireValue
        .itemCount;
    await press(find.byTooltip(_en.increase).first);
    expect(
      container.read(cartControllerProvider).requireValue.itemCount,
      before + 1,
      reason: 'the quantity control did not change the cart',
    );

    // --- pay -------------------------------------------------------------
    await press(find.text(_en.proceedToCheckout));
    expect(find.byType(CheckoutScreen), findsOneWidget);

    // The screen that takes the money says what it is for.
    final bought = container
        .read(cartControllerProvider)
        .requireValue
        .allItems
        .single;
    expect(
      find.textContaining(bought.name),
      findsOneWidget,
      reason: 'checkout does not say what is being bought',
    );

    // The pay button carries the amount, and is live on arrival.
    final pay = find.textContaining(_en.placeOrder);
    expect(pay, findsOneWidget);
    await press(pay);

    expect(
      find.text(_en.orderPlaced),
      findsOneWidget,
      reason: 'Place order did not produce a confirmed order',
    );
    // Cash on delivery is chosen first. It is paid at the door, so nothing
    // is "waiting on the payment provider" and there is nothing to re-check.
    expect(
      find.text(_en.codPlacedMessage),
      findsOneWidget,
      reason: 'a cash order reads like a payment stuck with a provider',
    );
    expect(find.text(_en.checkPaymentStatus), findsNothing);

    // --- and look at what was bought -------------------------------------
    await press(find.text(_en.viewOrder));
    expect(find.byType(OrderDetailScreen), findsOneWidget);
    expect(
      container.read(cartControllerProvider).requireValue.isEmpty,
      isTrue,
      reason: 'the cart still holds what was already bought',
    );
  });
}
