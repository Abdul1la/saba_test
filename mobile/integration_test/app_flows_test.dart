// The real app, on a real device, walked the way people use it.
//
// Widget tests draw screens in a test harness: a fake clock, a stand-in font
// where every glyph is a square, no system insets. This runs SabaApp itself on
// the phone — real engine, real fonts, real safe areas, real time — and walks
// the two jobs the app exists for, in both languages:
//
//   shopper   Home -> product -> options -> add to cart -> cart -> quantity
//             -> checkout -> place order -> the order
//   merchant  dashboard -> waiting orders -> an order -> copy the address
//             -> advance it -> edit a product
//
// and then opens every screen of both halves. Each step prints a STEP line, so
// a failure reads as "this step, this reason" instead of a stack trace.
//
// Run: flutter test integration_test/app_flows_test.dart -d <device>
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:saba_marketplace/app.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/core/theme/saba_icons.dart';
import 'package:saba_marketplace/core/widgets/option_selector.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/cart/presentation/cart_providers.dart';
import 'package:saba_marketplace/features/catalog/presentation/screens/product_detail_screen.dart';
import 'package:saba_marketplace/features/catalog/presentation/widgets/product_card.dart';
import 'package:saba_marketplace/features/checkout/presentation/checkout_providers.dart';
import 'package:saba_marketplace/features/checkout/presentation/screens/checkout_screen.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:saba_marketplace/features/merchant/presentation/screens/merchant_order_detail_screen.dart';
import 'package:saba_marketplace/features/merchant/presentation/screens/merchant_product_form_screen.dart';
import 'package:saba_marketplace/features/orders/presentation/screens/order_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void step(String what) => debugPrint('STEP  $what');

/// Real time, not a fake clock: the demo backend answers after 350ms of
/// wall-clock time, and the flash-sale countdown never stops ticking, so
/// pumpAndSettle would wait forever.
Future<void> settle(WidgetTester tester, {int ms = 1600}) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 50));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// Pumps until [finder] matches, up to [seconds]. The first test of a run
/// meets a debug VM that is still compiling every screen on first use, so a
/// fixed wait that suits the tenth test is too short for the first.
Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  int seconds = 20,
}) async {
  // A `.first` or `.last` finder throws when nothing matches yet instead of
  // answering "none", so "not there yet" has to be caught, not assumed.
  bool present() {
    try {
      return finder.evaluate().isNotEmpty;
    } on StateError {
      return false;
    }
  }

  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!present() && DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

/// Pumps until [condition] holds, up to [seconds]: an action's result is
/// checked when it has happened, not after a guess at how long it takes.
Future<void> waitUntil(
  WidgetTester tester,
  bool Function() condition, {
  int seconds = 15,
}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!condition() && DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<void> press(WidgetTester tester, Finder finder, {int ms = 1600}) async {
  await waitFor(tester, finder);
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester, ms: ms);
}

Future<ProviderContainer> launch(
  WidgetTester tester, {
  required String language,
  required String email,
}) async {
  DioFactory.mockBackend.resetForTesting();
  SharedPreferences.setMockInitialValues(<String, Object>{
    'saba.pref.onboarding_seen': true,
    'saba.pref.locale': language,
  });
  final preferences = await AppPreferences.create();
  final container = ProviderContainer(
    overrides: [appPreferencesProvider.overrideWithValue(preferences)],
    retry: (_, _) => null,
  );
  addTearDown(container.dispose);

  await container
      .read(authControllerProvider.notifier)
      .signIn(email: email, password: 'Password1');
  expect(
    container.read(authControllerProvider).value?.user,
    isNotNull,
    reason: 'could not sign in as $email',
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SabaApp()),
  );
  await settle(tester, ms: 3000);
  return container;
}

String location(ProviderContainer container) => container
    .read(appRouterProvider)
    .routerDelegate
    .currentConfiguration
    .uri
    .path;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final language in const ['en', 'ar']) {
    final l10n = AppLocalizations(Locale(language));

    testWidgets('[$language] a customer buys something by tapping', (
      tester,
    ) async {
      final container = await launch(
        tester,
        language: language,
        email: 'demo@saba.app',
      );
      container.read(appRouterProvider).go(AppRoutes.home);
      await settle(tester, ms: 2500);

      step('[$language] shopper: open a product from Home');
      final card = find.byType(ProductCard).first;
      expect(card, findsOneWidget, reason: 'Home shows nothing to buy');
      await press(tester, card, ms: 2500);
      expect(
        find.byType(ProductDetailScreen),
        findsOneWidget,
        reason: 'a product card did not open the product',
      );

      step('[$language] shopper: choose every option');
      for (final group in <Finder>[
        find.byType(ColourSwatchColumn),
        find.byType(OptionSelector),
      ]) {
        for (var index = 0; index < group.evaluate().length; index++) {
          final options = find.descendant(
            of: group.at(index),
            matching: find.byWidgetPredicate((w) => w is InkResponse),
          );
          if (options.evaluate().isEmpty) continue;
          await press(tester, options.first, ms: 800);
        }
      }

      step('[$language] shopper: add to cart');
      await press(tester, find.text(l10n.addToCart).last);
      await waitUntil(
        tester,
        () =>
            container.read(cartControllerProvider).value?.allItems.length == 1,
      );
      expect(
        container.read(cartControllerProvider).requireValue.allItems,
        hasLength(1),
        reason: 'Add to cart put nothing in the cart',
      );

      step('[$language] shopper: follow the snackbar to the cart');
      await press(tester, find.text(l10n.cart).last, ms: 2500);
      expect(
        find.text(l10n.myCart),
        findsOneWidget,
        reason: 'the Cart action did not open the cart',
      );

      step('[$language] shopper: add one more');
      final before = container
          .read(cartControllerProvider)
          .requireValue
          .itemCount;
      await press(tester, find.byTooltip(l10n.increase).first);
      expect(
        container.read(cartControllerProvider).requireValue.itemCount,
        before + 1,
        reason: 'the quantity control did nothing',
      );

      step('[$language] shopper: checkout');
      await press(tester, find.text(l10n.proceedToCheckout), ms: 3000);
      expect(
        find.byType(CheckoutScreen),
        findsOneWidget,
        reason: 'Proceed to checkout did not open checkout',
      );

      step('[$language] shopper: place the order');
      await press(tester, find.textContaining(l10n.placeOrder), ms: 3500);
      expect(
        find.text(l10n.orderPlaced),
        findsOneWidget,
        reason: 'Place order did not confirm an order',
      );

      step('[$language] shopper: look at the order');
      await press(tester, find.text(l10n.viewOrder), ms: 2500);
      expect(
        find.byType(OrderDetailScreen),
        findsOneWidget,
        reason: 'View order did not open the order',
      );
      expect(
        container.read(cartControllerProvider).requireValue.isEmpty,
        isTrue,
        reason: 'the cart still holds what was bought',
      );
      step('[$language] shopper: PASSED');
    });

    testWidgets('[$language] a merchant fulfils an order by tapping', (
      tester,
    ) async {
      final container = await launch(
        tester,
        language: language,
        email: 'merchant@saba.app',
      );
      container.read(appRouterProvider).go(AppRoutes.merchantDashboard);
      await settle(tester, ms: 2500);

      step('[$language] merchant: the dashboard says orders are waiting');
      final waiting = find.textContaining(l10n.toConfirmSuffix);
      expect(
        waiting,
        findsOneWidget,
        reason: 'no waiting orders on the dashboard',
      );
      await press(tester, waiting, ms: 2500);
      expect(location(container), AppRoutes.merchantOrders);

      step('[$language] merchant: open the first order');
      await press(tester, find.textContaining('SB-').first, ms: 2500);
      expect(
        find.byType(MerchantOrderDetailScreen),
        findsOneWidget,
        reason: 'an order in the queue did not open',
      );

      step('[$language] merchant: copy the address in one tap');
      await press(tester, find.textContaining('Baghdad').first, ms: 400);
      // The evidence is the tick that replaces the clipboard icon. Reading
      // the clipboard back is not: Android refuses clipboard reads here and
      // answers null for a copy that worked — measured, tick=true every time.
      // The icon inside the address row itself: it swaps from clipboard to
      // a tick. Not the semantics label, which merges the address text into
      // the same node and so never equals "Copied" exactly.
      final row = find
          .ancestor(
            of: find.textContaining('Baghdad').first,
            matching: find.byType(InkWell),
          )
          .first;
      final ticked = find.descendant(
        of: row,
        matching: find.byWidgetPredicate(
          (w) => w is SabaIcon && w.icon == SabaIcons.check,
        ),
      );
      expect(
        ticked,
        findsOneWidget,
        reason: 'tapping the address did not copy it',
      );

      step('[$language] merchant: move the order on');
      await press(tester, find.textContaining(l10n.nextStatus), ms: 2500);
      final order =
          (await container.read(merchantRepositoryProvider).order('mo-1'))
              .unwrap();
      expect(
        order.row.status,
        isNot('NEW'),
        reason: 'Advance status reported success and the order did not move',
      );

      step('[$language] merchant: edit a product');
      container.read(appRouterProvider).go(AppRoutes.merchantProducts);
      await settle(tester, ms: 2500);
      await press(tester, find.byTooltip(l10n.edit).first, ms: 3000);
      expect(
        find.byType(MerchantProductFormScreen),
        findsOneWidget,
        reason: 'Edit did not open the product form',
      );
      final filled = tester
          .widgetList<TextField>(find.byType(TextField))
          .map((field) => field.controller?.text ?? '')
          .where((text) => text.length > 40);
      expect(
        filled,
        isNotEmpty,
        reason: 'the edit form opened without the product description',
      );
      step('[$language] merchant: PASSED');
    });

    testWidgets('[$language] every screen opens on the phone', (tester) async {
      final container = await launch(
        tester,
        language: language,
        email: 'demo@saba.app',
      );

      // A customer with history, so screens draw with data rather than
      // their empty states.
      await container
          .read(cartControllerProvider.notifier)
          .addItem(productId: 'p-1', quantity: 2);
      final checkout = container.read(checkoutControllerProvider.notifier);
      await checkout.priceOrder();
      final orderId = (await checkout.placeOrder()).unwrap().orderId;
      await container
          .read(cartControllerProvider.notifier)
          .addItem(productId: 'p-2', quantity: 1);

      final routes = <String>[
        AppRoutes.home,
        AppRoutes.categories,
        AppRoutes.cart,
        AppRoutes.orders,
        AppRoutes.account,
        AppRoutes.search,
        AppRoutes.wishlist,
        AppRoutes.addresses,
        AppRoutes.addressForm,
        AppRoutes.notifications,
        AppRoutes.conversations,
        AppRoutes.supportTickets,
        AppRoutes.newSupportTicket,
        AppRoutes.profile,
        AppRoutes.settings,
        AppRoutes.checkout,
        AppRoutes.productDetailPath('p-1'),
        AppRoutes.storefrontPath('m-1'),
        AppRoutes.categoryProductsPath('c-1'),
        AppRoutes.merchantReviewsPath('m-1'),
        AppRoutes.orderDetailPath(orderId),
        AppRoutes.orderInvoicePath(orderId),
        AppRoutes.requestReturnPath(orderId),
        AppRoutes.orderConfirmationPath(orderId),
      ];

      for (final route in routes) {
        step('[$language] open $route');
        container.read(appRouterProvider).go(route);
        await settle(tester);
        expect(
          location(container),
          Uri.parse(route).path,
          reason: '$route was redirected away',
        );
        expect(
          tester.takeException(),
          isNull,
          reason: '$route threw or overflowed on the phone',
        );
      }
      step('[$language] every shopper screen: PASSED');
    });

    testWidgets('[$language] every merchant screen opens on the phone', (
      tester,
    ) async {
      final container = await launch(
        tester,
        language: language,
        email: 'merchant@saba.app',
      );

      final routes = <String>[
        AppRoutes.merchantDashboard,
        AppRoutes.merchantProducts,
        AppRoutes.merchantOrders,
        AppRoutes.merchantOrdersPath(status: 'NEW'),
        AppRoutes.merchantAnalytics,
        AppRoutes.merchantAccount,
        AppRoutes.merchantProductForm,
        AppRoutes.merchantInventory,
        AppRoutes.merchantPayouts,
        AppRoutes.merchantStoreSettings,
        AppRoutes.merchantOrderDetailPath('mo-1'),
      ];

      for (final route in routes) {
        step('[$language] open $route');
        container.read(appRouterProvider).go(route);
        await settle(tester);
        expect(
          location(container),
          Uri.parse(route).path,
          reason: '$route was redirected away',
        );
        expect(
          tester.takeException(),
          isNull,
          reason: '$route threw or overflowed on the phone',
        );
      }
      step('[$language] every merchant screen: PASSED');
    });
  }
}
