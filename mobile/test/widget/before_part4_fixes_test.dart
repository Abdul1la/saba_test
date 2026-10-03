// The fixes asked for before the product page's rebuild.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/location/governorate.dart';
import 'package:saba_marketplace/core/location/governorate_picker.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/core/theme/app_theme.dart';
import 'package:saba_marketplace/core/theme/app_typography.dart';
import 'package:saba_marketplace/core/widgets/saba_tile.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/auth/presentation/widgets/auth_scaffold.dart';
import 'package:saba_marketplace/features/catalog/domain/entities.dart';
import 'package:saba_marketplace/features/catalog/presentation/widgets/product_card.dart';
import 'package:saba_marketplace/features/legal/legal_screen.dart';
import 'package:saba_marketplace/core/widgets/app_network_image.dart';
import 'package:saba_marketplace/features/merchant/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/presentation/widgets/merchant_widgets.dart';
import 'package:saba_marketplace/features/merchant/presentation/screens/merchant_product_form_screen.dart';
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
          final key = call.arguments is Map ? call.arguments['key'] : null;
          switch (call.method) {
            case 'write':
              store[key as String] = call.arguments['value'] as String? ?? '';
              return null;
            case 'read':
              return store[key as String];
            case 'delete':
              store.remove(key as String);
              return null;
            case 'readAll':
              return Map<String, String>.from(store);
            case 'deleteAll':
              store.clear();
              return null;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_keystore, null);
    DioFactory.mockBackend.resetForTesting();
  });

  Widget host(Widget child, {String language = 'en'}) => MaterialApp(
    theme: AppTheme.light(),
    locale: Locale(language),
    localizationsDelegates: const <LocalizationsDelegate<Object>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  /// The whole app, signed in as [who], opened at [route].
  Future<ProviderContainer> app(
    WidgetTester tester, {
    required String route,
    String? who,
    Object? extra,
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
    await tester.runAsync(() async {
      if (who != null) {
        await container
            .read(authControllerProvider.notifier)
            .signIn(email: who, password: 'Password1');
      }
    });
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
    Future<void> settle() async {
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    await settle();
    final router = container.read(appRouterProvider);
    extra == null ? router.go(route) : router.push(route, extra: extra);
    await settle();
    return container;
  }

  testWidgets('Settings: every option in the text colour, lines at the words', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        TileGroup(
          tiles: [
            ChoiceRow(label: 'One', isSelected: true, onTap: () {}),
            ChoiceRow(label: 'Two', isSelected: false, onTap: () {}),
          ],
        ),
      ),
    );
    final colors = AppTheme.light().colorScheme;
    for (final label in ['One', 'Two']) {
      expect(
        tester.widget<Text>(find.text(label)).style?.color,
        colors.onSurface,
        reason: label,
      );
    }
    // The nearest padding around the line is its inset.
    final divider = tester
        .widgetList<Padding>(
          find.ancestor(
            of: find.byType(Divider),
            matching: find.byType(Padding),
          ),
        )
        .first;
    final row = tester.widget<ChoiceRow>(find.byType(ChoiceRow).first);
    expect((divider.padding as EdgeInsetsDirectional).start, row.padding.left);
  });

  testWidgets('a product card names its store\'s city; a sale card does not', (
    tester,
  ) async {
    const product = ProductSummary(
      id: 'x',
      name: 'Kettle',
      price: 25000,
      currencyCode: 'IQD',
      stockStatus: StockStatus.inStock,
      merchantName: 'Atlas Home',
      merchantCity: Governorate.basra,
    );
    await tester.pumpWidget(
      host(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 180,
              child: ProductCard(product: product, onTap: () {}),
            ),
            const SizedBox(width: 8),
            FlashSaleCard(product: product, onTap: () {}),
          ],
        ),
      ),
    );
    expect(find.byType(CityLabel), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ProductCard),
        matching: find.text('Basra'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('sign-in greets a first visit and a return alike', (
    tester,
  ) async {
    await app(tester, route: AppRoutes.login);
    expect(find.text('Welcome to Saba'), findsOneWidget);
    expect(find.text('Welcome back'), findsNothing);
  });

  testWidgets('the policy pages set their headings in the heading font', (
    tester,
  ) async {
    await tester.pumpWidget(host(const LegalScreen(page: LegalPage.privacy)));
    final heading = tester.widget<Text>(find.text('What Saba keeps'));
    expect(heading.style?.fontFamily, AppTypography.headingFamily);
  });

  // BUGS 183: the Terms and Privacy said to ask Support to close or delete
  // an account. Apple does not accept that, and the app deletes from its
  // own button. Both pages now name it, in both languages.
  for (final language in ['en', 'ar']) {
    testWidgets('the Terms and Privacy send deletion to the app ($language)', (
      tester,
    ) async {
      final button = AppLocalizations(Locale(language)).deleteAccount;
      for (final page in [LegalPage.terms, LegalPage.privacy]) {
        await tester.pumpWidget(
          host(LegalScreen(page: page), language: language),
        );
        expect(find.textContaining(button), findsOneWidget, reason: '$page');
      }
    });
  }

  testWidgets('the store is told a product was not approved, and why', (
    tester,
  ) async {
    await app(
      tester,
      route: AppRoutes.merchantDashboard,
      who: 'merchant@saba.app',
    );
    expect(find.text('1 product ${_en.notApprovedSuffix}'), findsOneWidget);
    expect(find.text(_en.rejectedNeedsEdit), findsOneWidget);

    // Opened to be fixed, the form shows Saba's reason.
    const row = MerchantProductRow(
      id: 'p-41',
      name: 'Orbit Action Camera 4K',
      price: 215000,
      currencyCode: 'IQD',
      status: 'REJECTED',
      stock: 0,
      rejectionReason: 'Images do not meet the catalogue guidelines.',
    );
    await app(
      tester,
      route: AppRoutes.merchantProductForm,
      who: 'merchant@saba.app',
      extra: row,
    );
    expect(find.text(_en.sabaSaidNo), findsOneWidget);
    expect(find.textContaining(row.rejectionReason!), findsOneWidget);
  });

  // BUGS 98: the bar said "This is how buyers see your store" over a
  // product buyers cannot see, and a tap on a shelf row did nothing.
  testWidgets('a product buyers cannot see says so; a shelf row opens it', (
    tester,
  ) async {
    await app(
      tester,
      route: AppRoutes.productDetailPath('p-51'), // Nova's hidden one
      who: 'merchant@saba.app',
    );
    expect(find.text(_en.previewNotListed), findsOneWidget);
    expect(find.text(_en.storePreview), findsNothing);

    await app(
      tester,
      route: AppRoutes.productDetailPath('p-1'),
      who: 'merchant@saba.app',
    );
    expect(find.text(_en.storePreview), findsOneWidget);
    expect(find.text(_en.previewNotListed), findsNothing);

    await app(
      tester,
      route: AppRoutes.merchantProducts,
      who: 'merchant@saba.app',
    );
    await tester.tap(find.byType(AppNetworkImage).first);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(find.byType(MerchantProductFormScreen), findsOneWidget);
  });

  // The tester: "D-0" and "W1" under the charts in Arabic.
  testWidgets('a chart names its ends in the language it is read in', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        SalesBarChart(
          points: [
            SalesPoint(
              label: 'M-1',
              value: 10,
              from: DateTime(2026, 8),
              unit: 'MONTH',
            ),
            SalesPoint(
              label: 'M-0',
              value: 20,
              from: DateTime(2026, 9),
              unit: 'MONTH',
            ),
          ],
        ),
        language: 'ar',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('M-1'), findsNothing);
    expect(find.text('أغسطس'), findsOneWidget);
    expect(find.text('سبتمبر'), findsOneWidget);
  });

  // The user: the language screen is centred, all of it; "start edge" was
  // for the sign-in screens.
  testWidgets('the language screen is centred', (tester) async {
    await app(tester, route: AppRoutes.language);
    final middle = tester.getCenter(find.byType(Scaffold).first).dx;
    for (final text in [
      find.textContaining(_en.chooseYourLanguage),
      find.text(_en.changeLanguageLater),
      find.text(_en.sabaTagline),
    ]) {
      expect(tester.widget<Text>(text).textAlign, TextAlign.center);
      expect(tester.getCenter(text).dx, closeTo(middle, 2));
    }
  });

  // The user: "Already have an account? Sign in" was small grey text at the
  // start edge. Centred, apart from the form, big enough to read and tap.
  testWidgets('the sign-in and sign-up links are centred and easy to tap', (
    tester,
  ) async {
    for (final (route, count) in [
      (AppRoutes.registerPhonePath(merchant: false), 2),
      (AppRoutes.login, 1),
    ]) {
      await app(tester, route: route);
      final middle = tester.getCenter(find.byType(Scaffold).first).dx;
      final links = find.byType(AuthSwitchLink);
      expect(links, findsNWidgets(count), reason: route);
      for (final link in links.evaluate()) {
        final button = find.descendant(
          of: find.byWidget(link.widget),
          matching: find.byType(TextButton),
        );
        expect(tester.getCenter(button).dx, closeTo(middle, 2), reason: route);
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
        final label = find.descendant(of: button, matching: find.byType(Text));
        expect(
          tester.renderObject<RenderParagraph>(label).text.style?.fontSize ?? 0,
          greaterThanOrEqualTo(16),
          reason: route,
        );
      }
    }
  });
}
