// A shop page has to show something for sale, and its buttons have to work
// for the person who has not signed in yet.
//
// Both were broken here. The header ran 670 points down a 914-point phone
// before the first product, because Follow was a full-width block under the
// description; and Follow itself returned in silence for a visitor with no
// account, so the one obviously pressable thing on the page did nothing.
//
// And the owner looking at their own shop: no "Only a few left" pushed at
// them, and a new store's empty preview says its product is waiting for
// Saba, not "No products found".
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/domain/entities.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/catalog/presentation/widgets/product_card.dart';
import 'package:saba_marketplace/features/merchant/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:saba_marketplace/features/merchant/presentation/screens/merchant_store_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _secureStorage = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

const _en = AppLocalizations(Locale('en'));

/// A Pixel 8 in logical pixels — the surface the header has to fit inside.
const double _screenHeight = 914;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    DioFactory.mockBackend.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          _secureStorage,
          (call) async => call.method == 'readAll' ? <String, String>{} : null,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, null);
  });

  /// The app, signed out — which is how most first visits arrive.
  Future<ProviderContainer> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(411 * 3, _screenHeight * 3);
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

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp.router(
            routerConfig: ref.watch(appRouterProvider),
            locale: const Locale('en'),
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
    return container;
  }

  Future<void> openStore(
    WidgetTester tester,
    ProviderContainer container,
    String store,
  ) async {
    container.read(appRouterProvider).go(AppRoutes.storefrontPath(store));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// Opens a demo shop, signed out.
  Future<void> pumpStorefront(WidgetTester tester) async =>
      openStore(tester, await pumpApp(tester), 'm-1');

  testWidgets('a shop shows something for sale without scrolling', (
    tester,
  ) async {
    await pumpStorefront(tester);

    final cards = find.byType(ProductCard);
    expect(cards, findsWidgets);

    // Not just the top edge peeking in: the whole first card, price and all.
    // A card cut off by the bottom of the screen is a shelf you have to
    // believe in before you can see it.
    final first = tester.getRect(cards.first);
    expect(
      first.bottom,
      lessThanOrEqualTo(_screenHeight),
      reason:
          'the first product ends at ${first.bottom} on a $_screenHeight '
          'point screen — the header above it has grown back',
    );
  });

  testWidgets('searching inside a shop narrows its shelves', (tester) async {
    await pumpStorefront(tester);
    final all = find.byType(ProductCard).evaluate().length;
    expect(all, greaterThan(1));

    await tester.enterText(find.byType(TextField).first, 'zzzznothing');
    // Past the debounce, then past the demo backend's latency.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(find.byType(ProductCard), findsNothing);
    // It blames the search, not the shop — and the field is still there to
    // clear, because the empty state replaces the grid, never the header.
    expect(find.text(_en.noResultsInStore), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.byTooltip(_en.clear));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(find.byType(ProductCard), findsWidgets);
  });

  testWidgets('the owner is not told "Only a few left" about their own shop', (
    tester,
  ) async {
    final container = await pumpApp(tester);
    await tester.runAsync(
      () => container
          .read(authControllerProvider.notifier)
          .signIn(email: 'merchant@saba.app', password: 'Password1'),
    );
    await openStore(tester, container, 'm-1');

    expect(find.byType(ProductCard), findsWidgets);
    expect(
      find.text(_en.lowStock),
      findsNothing,
      reason: "the owner's preview pushes urgency at the owner",
    );
  });

  testWidgets(
    "a new store: its preview says the product is waiting, and it has "
    'chosen no delivery fee',
    (tester) async {
      final container = await pumpApp(tester);
      await tester.runAsync(
        () => container
            .read(authControllerProvider.notifier)
            .registerMerchant(
              const MerchantRegistration(
                fullName: 'Zagros Phones',
                email: 'zagros@gmail.com',
                password: 'Demo1234!',
                phone: '+9647705551234',
                storeName: 'Zagros Phones',
                businessType: 'INDIVIDUAL',
                country: 'Iraq',
                governorate: 'ERBIL',
              ),
            ),
      );
      final store = container.read(currentUserProvider)!.merchant!.id;

      // Nothing chosen, nothing ticked: 5,000 IQD to its own city was
      // handed to every new store, and the checklist believed it.
      final settings = await tester.runAsync(
        () => container.read(storeSettingsProvider.future),
      );
      expect(
        settings!.delivery,
        isNull,
        reason: 'a new store has a delivery fee its owner never set',
      );

      await tester.runAsync(
        () => container
            .read(merchantRepositoryProvider)
            .saveProduct(
              const ProductDraft(
                name: 'Phone case',
                nameAr: 'غطاء هاتف',
                categoryId: 'c-smartphones',
                price: 12500,
                stock: 4,
              ),
            ),
      );
      container.invalidate(merchantProductCountsProvider);
      await openStore(tester, container, store);

      expect(find.byType(ProductCard), findsNothing);
      expect(
        find.text(_en.previewWaitingMessage),
        findsOneWidget,
        reason: 'the preview does not say the product is waiting',
      );
      expect(find.text(_en.emptyProducts), findsNothing);
    },
  );
}
