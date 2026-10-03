import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/constants/app_constants.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/theme/app_dimensions.dart';
import 'package:saba_marketplace/core/theme/app_theme.dart';
import 'package:saba_marketplace/core/theme/saba_icons.dart';
import 'package:saba_marketplace/core/widgets/app_dialogs.dart';
import 'package:saba_marketplace/core/widgets/filter_chip_row.dart';
import 'package:saba_marketplace/core/widgets/option_selector.dart';
import 'package:saba_marketplace/core/utils/formatters.dart';
import 'package:saba_marketplace/core/widgets/saba_nav_bar.dart';
import 'package:saba_marketplace/features/cart/domain/entities.dart';
import 'package:saba_marketplace/features/cart/presentation/widgets/coupon_offers.dart';
import 'package:saba_marketplace/features/catalog/domain/entities.dart';
import 'package:saba_marketplace/features/catalog/presentation/widgets/product_card.dart';

/// The components the design system introduces, and the rules they carry.
void main() {
  Widget host(Widget child, {Locale locale = const Locale('en')}) {
    return MaterialApp(
      theme: AppTheme.light(),
      locale: locale,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );
  }

  ProductSummary product({
    String name = 'Cotton hoodie, heavy weight',
    num price = 135000,
    num? originalPrice,
    StockStatus stock = StockStatus.inStock,
  }) {
    return ProductSummary(
      id: 'p-1',
      name: name,
      price: price,
      originalPrice: originalPrice,
      currencyCode: 'IQD',
      stockStatus: stock,
    );
  }

  group('product card fits the height it reports', () {
    // The bug this pins: heightFor once used the corner button's *visible*
    // 40px instead of its 48px tap target, so every card overflowed by a
    // sliver. A card that does not fit the box a grid gives it is a yellow
    // stripe on every screen in the app, so the two must agree exactly.
    Future<void> expectNoOverflow(
      WidgetTester tester, {
      required double width,
      required ProductSummary item,
      double textScale = 1,
      Locale locale = const Locale('en'),
    }) async {
      await tester.pumpWidget(
        host(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: Builder(
              builder: (context) => Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  height: ProductCard.heightFor(context, width),
                  child: ProductCard(
                    product: item,
                    onTap: () {},
                    onWishlistToggle: () {},
                  ),
                ),
              ),
            ),
          ),
          locale: locale,
        ),
      );

      expect(
        tester.takeException(),
        isNull,
        reason: 'the card must fit the height heightFor promises',
      );
    }

    testWidgets('at rail width', (tester) async {
      await expectNoOverflow(
        tester,
        width: AppSizes.productCardRailWidth,
        item: product(),
      );
    });

    testWidgets('at grid width, with a struck-through original price', (
      tester,
    ) async {
      await expectNoOverflow(
        tester,
        width: 173,
        item: product(originalPrice: 180000),
      );
    });

    testWidgets('with a one-line name, which still reserves two', (
      tester,
    ) async {
      await expectNoOverflow(tester, width: 173, item: product(name: 'Sofa'));
    });

    testWidgets('in Arabic, whose lines are taller', (tester) async {
      await expectNoOverflow(
        tester,
        width: 173,
        item: product(name: 'طقم أواني طبخ ستانلس ستيل 12 قطعة'),
        locale: const Locale('ar'),
      );
    });

    testWidgets('at 1.5x text size', (tester) async {
      await expectNoOverflow(
        tester,
        width: 173,
        item: product(originalPrice: 180000),
        textScale: 1.5,
      );
    });

    testWidgets('a short name and a long one give the same card height', (
      tester,
    ) async {
      // "Name clamps at two lines and the card height is fixed, so a grid
      // never goes ragged." Measured with no height imposed on the card, so
      // this is the card's own doing rather than the box it was put in.
      Future<double> measure(String name) async {
        await tester.pumpWidget(
          host(
            Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 173,
                child: ProductCard(
                  product: product(name: name),
                  onTap: () {},
                ),
              ),
            ),
          ),
        );
        return tester.getSize(find.byType(ProductCard)).height;
      }

      final short = await measure('Sofa');
      final long = await measure(
        'Stainless steel cookware set, 12 heavy pieces',
      );

      expect(short, long);
    });
  });

  group('flash-sale card', () {
    const width = AppSizes.flashSaleCardWidth;

    Future<void> pumpCard(
      WidgetTester tester, {
      required ProductSummary item,
      double textScale = 1,
      Locale locale = const Locale('en'),
      Future<bool> Function()? onAddToCart,
    }) async {
      await tester.pumpWidget(
        host(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: Builder(
              builder: (context) => Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  height: FlashSaleCard.heightFor(context, width),
                  child: FlashSaleCard(
                    product: item,
                    onTap: () {},
                    onWishlistToggle: () {},
                    onAddToCart: onAddToCart ?? () async => true,
                  ),
                ),
              ),
            ),
          ),
          locale: locale,
        ),
      );
    }

    // Seven figures and the largest text size the app allows: the widest a
    // price gets, beside the name, in a card of fixed width.
    final cases = <String, (ProductSummary, double, Locale)>{
      'a seven-figure sale price at the 1.4x cap': (
        product(price: 1250000, originalPrice: 1562500),
        1.4,
        const Locale('en'),
      ),
      'Arabic, low stock, at the 1.4x cap': (
        product(
          name: 'طقم أواني طبخ ستانلس ستيل 12 قطعة',
          price: 1250000,
          originalPrice: 1562500,
          stock: StockStatus.lowStock,
        ),
        1.4,
        const Locale('ar'),
      ),
    };

    for (final MapEntry(key: name, value: (item, scale, locale))
        in cases.entries) {
      testWidgets('fits the height it reports: $name', (tester) async {
        await pumpCard(tester, item: item, textScale: scale, locale: locale);

        expect(tester.takeException(), isNull);
        final price = tester.renderObject<RenderParagraph>(
          find.textContaining('1,250,000', findRichText: true),
        );
        expect(
          price.didExceedMaxLines,
          isFalse,
          reason: 'a price is never cut short',
        );
      });
    }

    testWidgets('fits the height it reports: plain', (tester) async {
      await pumpCard(tester, item: product());
      expect(tester.takeException(), isNull);
    });

    testWidgets('the add button confirms in place, in words', (tester) async {
      var adds = 0;
      await pumpCard(
        tester,
        item: product(),
        onAddToCart: () async {
          adds++;
          return true;
        },
      );

      await tester.tap(find.text('Add to cart'));
      await tester.pump();

      expect(adds, 1);
      expect(find.text('Added to your cart'), findsOneWidget);

      await tester.pump(AppMotion.confirmInPlace);
      expect(find.text('Add to cart'), findsOneWidget);
    });

    testWidgets('out of stock says so and cannot be pressed', (tester) async {
      await pumpCard(tester, item: product(stock: StockStatus.outOfStock));

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
      expect(
        find.descendant(
          of: find.byType(FilledButton),
          matching: find.text('Out of stock'),
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('a note with an action still goes away on its own', (
    tester,
  ) async {
    // Flutter keeps a snack bar that has an action until it is dismissed by
    // hand, so "Added to your cart - Cart" sat over the product page for good.
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => AppSnackBar.success(
              context,
              'Added to your cart',
              actionLabel: 'Cart',
              onAction: () {},
            ),
            child: const Text('add'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('add'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    expect(find.text('Added to your cart'), findsOneWidget);

    await tester.pump(AppConstants.snackBarDuration);
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pump(const Duration(milliseconds: 750));
    expect(find.text('Added to your cart'), findsNothing);
  });

  group('a product without a photo is drawn, not blanked', () {
    // The design: "No image -> a neutral tile with the words 'no image',
    // never a stretched placeholder photo." The tile carries line art of the
    // thing itself, picked from the name, so a grid of them still reads as a
    // grid of products rather than a grid of broken images.
    Future<String?> iconOn(WidgetTester tester, String name) async {
      await tester.pumpWidget(
        host(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 173,
              child: ProductCard(
                product: product(name: name),
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      final icons = tester
          .widgetList<SabaIcon>(find.byType(SabaIcon))
          .map((w) => w.icon)
          .toList();
      return icons.isEmpty ? null : icons.first;
    }

    testWidgets('a hoodie gets the clothing icon', (tester) async {
      expect(
        await iconOn(tester, 'Cotton hoodie, heavy weight'),
        SabaIcons.handbag,
      );
    });

    testWidgets('a phone gets the phone icon', (tester) async {
      expect(
        await iconOn(tester, 'Smartphone 128 GB, dual SIM'),
        SabaIcons.phone,
      );
    });

    testWidgets('a camera gets the camera icon', (tester) async {
      // Deliberately an icon that is NOT in the positional fallback list, so
      // this can only pass if the name was actually read.
      expect(await iconOn(tester, 'Mirrorless camera, 24MP'), SabaIcons.camera);
    });

    test('an unrecognised name still gets a stable icon, never nothing', () {
      final first = iconForName('Widget 3000', 7);
      expect(first, isNotEmpty);
      expect(
        iconForName('Widget 3000', 7),
        first,
        reason: 'the same product must not change icon between builds',
      );
    });
  });

  group('floating pill navigation', () {
    const destinations = [
      SabaNavDestination(icon: 'assets/icons/home.svg', label: 'Home'),
      SabaNavDestination(
        icon: 'assets/icons/bag.svg',
        label: 'Cart',
        badgeCount: 3,
      ),
    ];

    testWidgets('only the active tab shows its label', (tester) async {
      await tester.pumpWidget(
        host(
          const SabaNavBar(
            destinations: destinations,
            selectedIndex: 0,
            onSelected: _ignore,
          ),
        ),
      );

      expect(find.text('Home'), findsOneWidget);
      expect(
        find.text('Cart'),
        findsNothing,
        reason: 'an inactive tab is an icon alone — the pill is the signature',
      );
    });

    testWidgets('the badge count is rendered', (tester) async {
      await tester.pumpWidget(
        host(
          const SabaNavBar(
            destinations: destinations,
            selectedIndex: 0,
            onSelected: _ignore,
          ),
        ),
      );

      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('tapping a tab reports its index', (tester) async {
      var tapped = -1;
      await tester.pumpWidget(
        host(
          SabaNavBar(
            destinations: destinations,
            selectedIndex: 0,
            onSelected: (index) => tapped = index,
          ),
        ),
      );

      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is SabaIcon && w.icon.endsWith('bag.svg'),
        ),
      );
      expect(tapped, 1);
    });
  });

  group('colour options', () {
    test('a value the catalogue coloured wins over the name table', () {
      // "Black" is in the name table as #14181D. A seller who says their
      // black is actually #223344 must get their colour, not ours.
      expect(
        colourFor('Black', hex: '#223344'),
        const Color(0xFF223344),
        reason: 'the catalogue is the authority on its own colours',
      );
    });

    test('a name still resolves when the catalogue gave no value', () {
      expect(colourFor('Navy'), isNotNull);
    });

    test('a malformed value falls through to the name', () {
      expect(colourFor('Navy', hex: 'not-a-colour'), colourFor('Navy'));
      expect(colourFor('Sparkling teal', hex: '#12'), isNull);
    });

    test('an option becomes swatches only when every value resolves', () {
      expect(isColourOption('Colour', ['Black', 'Navy']), isTrue);
      expect(
        isColourOption('Colour', ['Black', 'Sparkling teal']),
        isFalse,
        reason: 'half dots and half words reads as broken',
      );
      expect(
        isColourOption(
          'Colour',
          ['Black', 'Sparkling teal'],
          colours: {'Sparkling teal': '#0E7C86'},
        ),
        isTrue,
        reason: 'the catalogue can supply what the name table cannot',
      );
      expect(
        isColourOption('Storage', ['128GB', '256GB']),
        isFalse,
        reason: 'only an option actually named colour becomes swatches',
      );
    });
  });

  group('money is written the way the design writes it', () {
    test('IQD has no decimals and the mark follows the number', () {
      expect(
        Formatters.money(250000, locale: 'en', currencyCode: 'IQD'),
        '250,000 IQD',
      );
    });

    test('only the mark localises — the digits stay Western', () {
      expect(
        Formatters.money(250000, locale: 'ar', currencyCode: 'IQD'),
        '250,000 د.ع',
        reason: 'an Iraqi customer reads 250,000 faster than ٢٥٠٬٠٠٠',
      );
    });

    test('a glyph currency still leads its number', () {
      expect(Formatters.money(5, locale: 'en', currencyCode: 'USD'), r'$5.00');
    });

    test('moneyParts splits the figure for the card', () {
      final (number, mark) = Formatters.moneyParts(
        135000,
        locale: 'en',
        currencyCode: 'IQD',
      );
      expect(number, '135,000');
      expect(mark, 'IQD');
    });
  });

  // The cart's code field never said where a code comes from. The customer's
  // coupons are offered under it and on Home, worded on the device.
  group('coupon offers', () {
    const offers = <CouponOffer>[
      CouponOffer(code: 'SABA10', isPercentage: true, value: 10),
      CouponOffer(
        code: 'WELCOME',
        isPercentage: false,
        value: 5000,
        currencyCode: 'IQD',
        firstOrderOnly: true,
      ),
    ];

    testWidgets('a chip puts its own code on in one tap', (tester) async {
      final applied = <String>[];
      await tester.pumpWidget(
        host(CouponOfferChips(offers: offers, onApply: applied.add)),
      );

      expect(find.text('10% off'), findsOneWidget);
      expect(find.text('5,000 IQD off'), findsOneWidget);
      await tester.tap(find.text('WELCOME'));
      expect(applied, ['WELCOME']);
    });

    testWidgets('it reads in Arabic, amount where Arabic puts it', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          CouponOfferChips(offers: offers, onApply: (_) {}),
          locale: const Locale('ar'),
        ),
      );
      await tester.pump();
      expect(find.text('خصم 5,000 د.ع'), findsOneWidget);
    });

    testWidgets('Home copies the code and says where else it is', (
      tester,
    ) async {
      String? copied;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await tester.pumpWidget(host(const CouponOfferStrip(offers: offers)));
      expect(find.text('Your first order only'), findsOneWidget);

      await tester.tap(find.text('Copy').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(copied, 'SABA10');
      expect(
        find.text(const AppLocalizations(Locale('en')).couponCopied),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      // Let the note go, so no timer outlives the test.
      await tester.pump(AppConstants.snackBarDuration);
      await tester.pumpAndSettle();
    });
  });
}

void _ignore(int _) {}
