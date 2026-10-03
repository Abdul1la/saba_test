// Part 4: the product page in blocks, the facts as pills.
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
import 'package:saba_marketplace/core/theme/saba_icons.dart';
import 'package:saba_marketplace/core/widgets/app_button.dart';
import 'package:saba_marketplace/core/widgets/option_selector.dart';
import 'package:saba_marketplace/core/widgets/search_pill.dart';
import 'package:saba_marketplace/core/widgets/price_text.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
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

  testWidgets('the facts are pills, and only the true ones', (tester) async {
    // p-1: Nova's phone, in Baghdad; the demo shopper is in Baghdad too.
    await app(
      tester,
      route: AppRoutes.productDetailPath('p-1'),
      who: 'demo@saba.app',
    );
    Finder pill(String text) => find.descendant(
      of: find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_FactPill',
      ),
      matching: find.textContaining(text),
    );
    expect(pill(_en.inStock), findsOneWidget);
    // The category, whatever it is called.
    expect(
      tester
          .widgetList(
            find.byWidgetPredicate(
              (widget) => widget.runtimeType.toString() == '_FactPill',
            ),
          )
          .where((widget) => (widget as dynamic).icon == SabaIcons.grid),
      hasLength(1),
    );
    expect(pill('Baghdad'), findsOneWidget);
    expect(pill(_en.deliveryFee), findsOneWidget);
    expect(pill('12 months'), findsOneWidget);
    expect(
      tester
          .widgetList<Text>(
            find.descendant(
              of: find.byWidgetPredicate(
                (widget) => widget.runtimeType.toString() == '_FactPill',
              ),
              matching: find.byType(Text),
            ),
          )
          .where((text) => (text.data ?? '').trim().isEmpty),
      isEmpty,
      reason: 'an empty pill',
    );
  });

  testWidgets('the photo is square and fills the width', (tester) async {
    await app(
      tester,
      route: AppRoutes.productDetailPath('p-1'),
      who: 'demo@saba.app',
    );
    final size = tester.getSize(find.byType(PageView));
    expect(size.width, 411);
    expect(size.height, size.width);
  });

  testWidgets('the discount is a small pill, not a bar', (tester) async {
    await app(
      tester,
      route: AppRoutes.productDetailPath('p-1'),
      who: 'demo@saba.app',
    );
    expect(tester.getSize(find.byType(DiscountBadge)).width, lessThan(80));
  });

  testWidgets('an option is named above its choices', (tester) async {
    await app(
      tester,
      route: AppRoutes.productDetailPath('p-1'),
      who: 'demo@saba.app',
    );
    // Below the price and the facts: scrolled to.
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
    final label = tester.getTopLeft(find.text('Storage', findRichText: true));
    final choices = tester.getTopLeft(find.byType(OptionSelector));
    expect(label.dy, lessThan(choices.dy));
    // And the colour swatches are under their name, not on the photo.
    final swatches = tester.getTopLeft(find.byType(ColourSwatchColumn));
    expect(swatches.dy, lessThan(choices.dy));
    // Each circle named (the tester: unlabelled circles).
    expect(
      find.descendant(
        of: find.byType(ColourSwatchColumn),
        matching: find.text('Black'),
      ),
      findsOneWidget,
    );
    expect(find.byType(PageView), findsNothing, reason: 'scrolled past it');
    expect(find.text(_en.selectVariantFirst), findsOneWidget);
  });

  testWidgets('sold out says so in red', (tester) async {
    // p-6: the demo sells out every seventh product.
    await app(
      tester,
      route: AppRoutes.productDetailPath('p-6'),
      who: 'demo@saba.app',
    );
    expect(find.text(_en.outOfStock), findsWidgets);
  });

  // The tester: a store that does not come to the shopper said so only far
  // down the page, and Buy now still worked; and a 9,000 IQD phone case
  // claimed a 12-month warranty. p-14 is Zakho Mobile's case, and Zakho
  // does not deliver to Amina's Baghdad.
  testWidgets(
    'a store that cannot deliver says so at the top, and nothing sells',
    (tester) async {
      await app(
        tester,
        route: AppRoutes.productDetailPath('p-14'),
        who: 'shopper@saba.app',
      );
      final pill = find.descendant(
        of: find.byType(Wrap),
        matching: find.text(_en.noDeliveryTo('Baghdad')),
      );
      expect(pill, findsOneWidget, reason: 'not said among the facts');
      for (final label in [_en.buyNow, _en.addToCart]) {
        final button = tester.widget<AppButton>(
          find.widgetWithText(AppButton, label),
        );
        expect(button.onPressed, isNull, reason: '$label still works');
      }
      expect(find.textContaining('months'), findsNothing, reason: 'a warranty');
    },
  );

  // The user: no share button until Saba has a domain, a public product
  // page and the deep link files. It copied a link to a domain this project
  // never set up, which opens nothing (BUGS.md 180).
  testWidgets('a product page has no share button, only back and favourite', (
    tester,
  ) async {
    await app(
      tester,
      route: AppRoutes.productDetailPath('p-1'),
      who: 'shopper@saba.app',
    );
    final icons = [
      for (final button in tester.widgetList<CircleIconButton>(
        find.byType(CircleIconButton),
      ))
        button.icon,
    ];
    expect(icons, isNot(contains(SabaIcons.share)), reason: 'a share button');
    expect(icons, contains(SabaIcons.heart), reason: 'the favourite went too');
  });
}
