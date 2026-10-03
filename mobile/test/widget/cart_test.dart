// The cart, driven the way a shopper drives it.
//
// Three things were wrong with it. Removing one line asked "Remove item?"
// first — two taps and a dialog to undo one tap. The total lived in a card in
// the list, so a cart longer than a screen let you press Checkout without ever
// seeing what you were about to pay. And a line the shop had sold out of froze
// the whole cart: the bar said there was a stock problem, the button went
// dead, and the only way forward was to hunt the line down by hand.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/mock/mock_data.dart';
import 'package:saba_marketplace/core/location/governorate_picker.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/core/utils/formatters.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/cart/domain/entities.dart';
import 'package:saba_marketplace/features/cart/presentation/cart_providers.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

const _en = AppLocalizations(Locale('en'));

/// A product that sells out once it is in the cart: what a real shop
/// produces when something sells out while you are deciding. One already
/// out cannot go in at all (BUGS 206).
final String _sellsOutProduct = MockData.products
    .firstWhere(
      (p) =>
          p['id'] != 'p-1' &&
          (p['variants'] as List? ?? const []).isEmpty &&
          (p['availableQuantity'] as num) > 0,
    )['id']
    .toString();
const String _inStockProduct = 'p-1';

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

  /// Signs in, fills the cart with [products], then opens it.
  Future<ProviderContainer> pumpCart(
    WidgetTester tester,
    List<String> products, {
    Locale locale = const Locale('en'),
    List<String> sellOut = const [],
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

    // Straight through the controllers rather than through the sign-in form:
    // this file is about the cart, and the form has tests of its own.
    //
    // Inside `runAsync`, because the demo backend answers after 350ms of real
    // time and a widget test's clock is fake: awaited out here, these futures
    // would simply never complete.
    await tester.runAsync(() async {
      await container
          .read(authControllerProvider.notifier)
          .signIn(email: 'demo@saba.app', password: 'Password1');
      for (final productId in products) {
        await container
            .read(cartControllerProvider.notifier)
            .addItem(productId: productId, quantity: 1);
      }
      if (sellOut.isEmpty) return;
      final auth = container.read(authControllerProvider.notifier);
      await auth.signIn(email: 'merchant@saba.app', password: 'Password1');
      for (final productId in sellOut) {
        (await container
                .read(merchantRepositoryProvider)
                .adjustStock(inventoryId: 'inv-$productId', quantity: -99999))
            .unwrap();
      }
      await auth.signIn(email: 'demo@saba.app', password: 'Password1');
      await container.read(cartControllerProvider.notifier).refresh();
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

    container.read(appRouterProvider).go(AppRoutes.cart);
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    return container;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Cart cartOf(ProviderContainer container) =>
      container.read(cartControllerProvider).requireValue;

  testWidgets('removing a line takes one tap and offers a way back', (
    tester,
  ) async {
    final container = await pumpCart(tester, [_inStockProduct]);
    expect(cartOf(container).allItems, hasLength(1));

    await tester.tap(find.text(_en.remove));
    await settle(tester);

    // Gone on the first tap — no dialog stood in the way.
    expect(cartOf(container).allItems, isEmpty);
    expect(find.text(_en.itemRemoved), findsOneWidget);

    await tester.tap(find.text(_en.undo));
    await settle(tester);

    expect(cartOf(container).allItems, hasLength(1));
  });

  // The design pass: one main action per screen. Every other button on the
  // cart is outlined, red, or sets its own quieter fill.
  testWidgets("checkout is the cart's one main button", (tester) async {
    await pumpCart(tester, [_inStockProduct]);

    expect(find.widgetWithText(OutlinedButton, _en.applyCoupon), findsOne);
    final main = tester
        .widgetList<FilledButton>(find.byType(FilledButton))
        .where((button) => button.style?.backgroundColor == null)
        .toList();
    expect(main, hasLength(1));
    expect(
      find.descendant(
        of: find.byWidget(main.single),
        matching: find.text(_en.proceedToCheckout),
      ),
      findsOne,
    );
  });

  testWidgets("each line names its store's city", (tester) async {
    // p-1 is Nova's, in Baghdad.
    await pumpCart(tester, [_inStockProduct]);
    expect(
      find.descendant(
        of: find.byType(CityLabel),
        matching: find.text('Baghdad'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the checkout bar says what you are about to pay', (
    tester,
  ) async {
    final container = await pumpCart(tester, [_inStockProduct]);

    // Not the card in the list — the bar pinned above the button, which is
    // on screen whatever the cart's length.
    final bar = find.ancestor(
      of: find.widgetWithText(FilledButton, _en.proceedToCheckout),
      matching: find.byType(Column),
    );
    expect(
      find.descendant(of: bar.last, matching: find.text(_en.grandTotal)),
      findsOneWidget,
    );

    // And it is the real figure, not a placeholder.
    final total = cartOf(container).totals.total;
    expect(total, greaterThan(0));
  });

  // BUGS.md 14 and 16. p-11 is Nova's, which comes to Baghdad; p-16 is
  // Zakho Mobile's, which does not.
  testWidgets('a store that cannot come says so on its card, with a way out', (
    tester,
  ) async {
    final container = await pumpCart(tester, ['p-11', 'p-16']);
    final zakho = cartOf(
      container,
    ).groups.singleWhere((group) => group.merchantId == 'm-3');
    expect(zakho.deliversHere, isFalse);

    expect(
      find.text(_en.notInTotal(zakho.estimatedDelivery!)),
      findsOneWidget,
      reason: 'the card does not say it',
    );
    expect(find.widgetWithText(TextButton, _en.changeAddress), findsOneWidget);

    // The total once, beside the button, not a second time in the list.
    final total = Formatters.money(
      cartOf(container).totals.total,
      locale: 'en',
      currencyCode: 'IQD',
    );
    expect(find.text(total), findsOneWidget, reason: 'the total twice');

    // Out of the way in one tap: saved for later, off the order.
    await tester.tap(find.widgetWithText(TextButton, _en.saveForLater));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 900)),
    );
    await settle(tester);
    final after = cartOf(container);
    expect(after.groups.map((group) => group.merchantId), ['m-1']);
    expect(after.savedForLater.map((item) => item.productId), ['p-16']);
  });

  testWidgets('a coupon goes on in one tap, and the totals show it', (
    tester,
  ) async {
    // Nova's NOVA10 needs 100,000 IQD of Nova's things; p-5 is Nova's.
    final container = await pumpCart(tester, ['p-5']);
    // The demo backend answers in real time; the test clock is fake.
    await tester.runAsync(
      () => container.read(availableCouponsProvider.future),
    );
    await settle(tester);

    await tester.ensureVisible(find.text('NOVA10'));
    await tester.pump();
    await tester.tap(find.text('NOVA10'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 600)),
    );
    await settle(tester);

    final cart = cartOf(container);
    expect(cart.coupon?.code, 'NOVA10', reason: 'the chip did not apply it');
    expect(cart.totals.couponDiscount, greaterThan(0));
    expect(
      find.text(_en.discount),
      findsOneWidget,
      reason: 'the coupon took money off and no line said so',
    );
  });

  testWidgets('a filled cart fits a phone in Arabic', (tester) async {
    // Asserts nothing: Flutter fails a test on any overflow, and the sweep in
    // no_overflow_test only ever saw this screen empty — which is how "Save
    // for later" and "Remove" sat side by side with no give for so long.
    await pumpCart(tester, [_inStockProduct], locale: const Locale('ar'));
    expect(find.byType(FilledButton), findsWidgets);
  });

  testWidgets('a sold-out line can be cleared from the bar in one tap', (
    tester,
  ) async {
    final container = await pumpCart(
      tester,
      [_inStockProduct, _sellsOutProduct],
      sellOut: [_sellsOutProduct],
    );
    expect(cartOf(container).hasUnavailableItems, isTrue);
    expect(cartOf(container).canCheckout, isFalse);

    // The button is not dead: it offers the one thing that unblocks the cart.
    expect(find.text(_en.proceedToCheckout), findsNothing);
    await tester.tap(find.text(_en.removeUnavailable));
    await settle(tester);

    expect(cartOf(container).hasUnavailableItems, isFalse);
    expect(cartOf(container).canCheckout, isTrue);
    // The line that was in stock is untouched.
    expect(cartOf(container).allItems, hasLength(1));
    expect(find.text(_en.proceedToCheckout), findsOneWidget);
  });

  // The tester: the only item saved for later, the cart said "Your cart is
  // empty" and the item looked lost. It was saved; the empty cart hid it.
  testWidgets('the only item saved for later shows, and moves back', (
    tester,
  ) async {
    final watch =
        MockData.products.firstWhere(
              (product) => product['name'] == 'Nova Watch Series 4',
            )['id']
            as String;
    final container = await pumpCart(tester, [watch]);

    await tester.tap(find.text(_en.saveForLater));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 900)),
    );
    await settle(tester);
    expect(cartOf(container).groups, isEmpty);
    expect(find.text(_en.emptyCartMessage), findsNothing, reason: 'hidden');
    expect(find.text(_en.savedForLater), findsOneWidget);
    expect(find.text('Nova Watch Series 4'), findsOneWidget);

    await tester.tap(find.text(_en.moveToCart));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 900)),
    );
    await settle(tester);
    expect(cartOf(container).savedForLater, isEmpty);
    expect(cartOf(container).allItems.single.productId, watch);
    expect(find.text(_en.savedForLater), findsNothing);
  });
}
