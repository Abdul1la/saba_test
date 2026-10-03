// Promises Home makes.
//
// It drew a wishlist heart twice — once in the dark header, once in the search
// row a few pixels below it: two identical controls, same screen, same
// destination. It wrapped every promo banner in a tap, including banners
// carrying no destination, so a finger got a ripple and nothing else. The
// banners at the top are now the admin's photographs and never a link, by the
// product owner's decision; a banner strip further down keeps the rule that a
// tap is offered only where there is somewhere to go.
//
// The demo feed has no banner without an action, which is exactly why these
// tests hand Home a feed of their own instead of waiting for one to turn up in
// the data. A guard that can only fire on data nobody ships is not a guard.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/core/widgets/app_network_image.dart';
import 'package:saba_marketplace/core/widgets/dark_header_card.dart';
import 'package:saba_marketplace/features/catalog/domain/entities.dart';
import 'package:saba_marketplace/features/catalog/presentation/screens/product_list_screen.dart';
import 'package:saba_marketplace/features/catalog/presentation/widgets/product_card.dart';
import 'package:saba_marketplace/features/home/domain/entities.dart';
import 'package:saba_marketplace/features/home/presentation/home_providers.dart';
import 'package:saba_marketplace/features/home/presentation/widgets/home_sections.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _secureStorage = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

const _en = AppLocalizations(Locale('en'));

/// A banner section, either the first one (drawn in the dark header as the
/// promo carousel) or a later one (drawn as the strip further down).
List<HomeSection> _feed({required bool lead, BannerAction? action}) {
  const banner = 'banners';
  final section = HomeSection(
    id: banner,
    type: HomeSectionType.bannerCarousel,
    banners: [
      HomeBanner(
        id: 'b1',
        // Empty on purpose: the widget draws its neutral fallback tile and no
        // test ever waits on the network.
        imageUrl: '',
        title: 'Eid offer',
        subtitle: 'This week',
        action: action,
      ),
    ],
  );

  if (lead) return [section];

  // A banner section only becomes the strip when something else is first.
  return [
    const HomeSection(
      id: 'filler',
      type: HomeSectionType.productCarousel,
      title: 'For you',
    ),
    section,
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
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

  /// Home, on a phone, with the feed the test chose.
  Future<ProviderContainer> pumpHome(
    WidgetTester tester,
    List<HomeSection> sections, {
    VoidCallback? onFetch,
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
      overrides: [
        appPreferencesProvider.overrideWithValue(preferences),
        homeFeedProvider.overrideWith((ref) async {
          onFetch?.call();
          return sections;
        }),
      ],
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

    container.read(appRouterProvider).go(AppRoutes.home);
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    return container;
  }

  /// The tap on a banner in the strip below the header.
  VoidCallback? stripTap(WidgetTester tester) {
    return tester
        .widget<InkWell>(
          find
              .ancestor(
                of: find.byType(AppNetworkImage),
                matching: find.byType(InkWell),
              )
              .first,
        )
        .onTap;
  }

  testWidgets('Home has no wishlist shortcut: it is in Account', (
    tester,
  ) async {
    await pumpHome(tester, _feed(lead: true));

    // The dark header and the search row both draw a Tooltip with this
    // label, so a heart returning to either place fails here. The hearts on
    // the products say "Add to wishlist", not this.
    expect(find.byTooltip(_en.wishlist), findsNothing);
  });

  testWidgets('the header on Home is white, with dark status-bar icons', (
    tester,
  ) async {
    await pumpHome(tester, _feed(lead: true));

    final header = find.byType(DarkHeaderCard);
    final card = tester.widget<Container>(
      find.descendant(of: header, matching: find.byType(Container)).first,
    );
    expect(
      (card.decoration! as BoxDecoration).color,
      Theme.of(tester.element(header)).colorScheme.surface,
      reason: 'the Home header went back to black',
    );
    // White icons on a white card would vanish.
    final statusBar = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.descendant(
        of: header,
        matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
      ),
    );
    expect(statusBar.value.statusBarIconBrightness, Brightness.dark);
  });

  testWidgets('a banner at the top opens what Saba linked it to, and is a '
      'picture otherwise', (tester) async {
    // Saba's banners page links a banner to a product, a store or a
    // category, or to nothing (the user's decisions, 2026-09-30). A link the
    // app does not open, a web address, leaves it a picture too.
    for (final (action, opens) in const <(BannerAction?, bool)>[
      (null, false),
      (BannerAction(type: 'URL', value: 'https://saba.iq/eid'), false),
      (BannerAction(type: 'CATEGORY', value: 'cat-1'), true),
    ]) {
      await pumpHome(tester, _feed(lead: true, action: action));

      final carousel = find.byType(HomePromoCarousel);
      expect(carousel, findsOneWidget);
      final taps = tester
          .widgetList<InkWell>(
            find.descendant(of: carousel, matching: find.byType(InkWell)),
          )
          .where((inkWell) => inkWell.onTap != null);
      expect(
        taps.isNotEmpty,
        opens,
        reason: 'the banner linked to ${action?.type} has the wrong tap',
      );
    }
  });

  testWidgets('categories are round pictures in two rows that open', (
    tester,
  ) async {
    await pumpHome(tester, [
      HomeSection(
        id: 'categories',
        type: HomeSectionType.categoryGrid,
        title: 'Shop by category',
        categories: [
          for (var i = 1; i <= 6; i++) Category(id: 'c-$i', name: 'Cat $i'),
        ],
      ),
    ]);

    // Six make two rows of three: the first half on top, the rest below.
    final top = tester.getTopLeft(find.text('Cat 1')).dy;
    expect(tester.getTopLeft(find.text('Cat 3')).dy, top);
    expect(tester.getTopLeft(find.text('Cat 4')).dy, greaterThan(top));

    await tester.tap(find.text('Cat 5'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    // A pushed screen, so the screen is what is checked, not the address.
    final list = tester.widget<ProductListScreen>(
      find.byType(ProductListScreen),
    );
    expect(list.initialQuery.categoryId, 'c-5');
  });

  testWidgets('a strip banner follows the same rule', (tester) async {
    await pumpHome(tester, _feed(lead: false));
    expect(stripTap(tester), isNull);

    await pumpHome(
      tester,
      _feed(
        lead: false,
        action: const BannerAction(type: 'PRODUCT', value: 'p-1'),
      ),
    );
    expect(stripTap(tester), isNotNull);
  });

  testWidgets('only the flash sale draws the flash-sale card', (tester) async {
    // A limited offer has a card of its own so it stands apart from the
    // feed; every other rail keeps the ordinary card.
    const item = ProductSummary(
      id: 'p-1',
      name: 'Nova X5 Smartphone',
      price: 49000,
      originalPrice: 61250,
      currencyCode: 'IQD',
      stockStatus: StockStatus.inStock,
    );
    await pumpHome(tester, const [
      HomeSection(
        id: 'flash',
        type: HomeSectionType.flashSale,
        title: 'Flash sale',
        products: [item],
      ),
      HomeSection(
        id: 'rail',
        type: HomeSectionType.productCarousel,
        title: 'For you',
        products: [item],
      ),
    ]);

    expect(find.byType(FlashSaleCard), findsOneWidget);
    expect(find.byType(ProductCard), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(FlashSaleCard),
        matching: find.text(_en.addToCart),
      ),
      findsOneWidget,
      reason: 'the flash-sale card carries a full "Add to cart" button',
    );
  });

  // The rail counts down to the soonest sale's end. At zero it asked for
  // nothing, so the ended sale stayed on Home at its sale price.
  testWidgets('the countdown at zero asks for Home again, once', (
    tester,
  ) async {
    var fetches = 0;
    final ends = DateTime.now().add(const Duration(seconds: 3));
    await pumpHome(tester, [
      HomeSection(
        id: 'flash',
        type: HomeSectionType.flashSale,
        endsAt: ends,
        products: const [
          ProductSummary(
            id: 'p-7',
            name: 'Atlas Smartwatch Series 4',
            price: 871000,
            originalPrice: 1089000,
            currencyCode: 'IQD',
            stockStatus: StockStatus.inStock,
          ),
        ],
      ),
    ], onFetch: () => fetches++);
    expect(fetches, 1);

    await tester.runAsync(
      () => Future<void>.delayed(
        ends.difference(DateTime.now()) + const Duration(milliseconds: 100),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(fetches, 2, reason: 'the sale ended and Home was not asked again');
    await tester.pump(const Duration(seconds: 3));
    expect(fetches, 2, reason: 'asked again every second');
  });
}
