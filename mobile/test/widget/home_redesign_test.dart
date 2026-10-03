// Home after the redesign, drawn with the fonts the phone will use: the
// globe switches everything on it, the heading fonts are there, and nothing
// overflows on a small phone, a big one, or with large text.
//
// Run with --dart-define=SABA_SHOTS=true to also save pictures of Home in
// both languages to build/home_shots/, for a look without a phone.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/mock/mock_data.dart';
import 'package:saba_marketplace/app.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/core/theme/app_typography.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/catalog/presentation/widgets/product_card.dart';
import 'package:saba_marketplace/features/home/presentation/widgets/home_products.dart';
import 'package:saba_marketplace/features/home/presentation/widgets/home_sections.dart';
import 'package:saba_marketplace/features/messaging/presentation/screens/messaging_screens.dart';
import 'package:saba_marketplace/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _paths = MethodChannel('plugins.flutter.io/path_provider');

const _en = AppLocalizations(Locale('en'));
const _ar = AppLocalizations(Locale('ar'));

const _shots = bool.fromEnvironment('SABA_SHOTS');

/// Every font the app bundles, as pubspec.yaml declares them.
const _fonts = <String, List<String>>{
  AppTypography.family: [
    'IBMPlexSansArabic-Light.ttf',
    'IBMPlexSansArabic-Regular.ttf',
    'IBMPlexSansArabic-Medium.ttf',
    'IBMPlexSansArabic-SemiBold.ttf',
    'IBMPlexSansArabic-Bold.ttf',
  ],
  AppTypography.headingFamily: ['DMSerifDisplay-Regular.ttf'],
  AppTypography.headingFamilyArabic: ['Amiri-Bold.ttf'],
};

/// What Home can sell: the demo's products less the few its stores keep
/// off sale.
final int _onSale = MockData.products
    .where((p) => MockData.startsOnSale(p['id']))
    .length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = <String, String>{};
  final shotKey = GlobalKey();

  // The real fonts, from the app's own bundle: a test normally draws every
  // letter as a box, which would hide a font that is missing or too tall.
  setUpAll(() async {
    for (final entry in _fonts.entries) {
      final loader = FontLoader(entry.key);
      for (final file in entry.value) {
        loader.addFont(rootBundle.load('assets/fonts/$file'));
      }
      await loader.load();
    }
  });

  setUp(() {
    store.clear();
    DioFactory.mockBackend.resetForTesting();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_keystore, (call) async {
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
    messenger.setMockMethodCallHandler(
      _paths,
      (_) async => Directory.systemTemp.path,
    );
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_paths, null);
    messenger.setMockMethodCallHandler(_keystore, null);
    DioFactory.mockBackend.resetForTesting();
  });

  /// Home, signed in as the demo shopper, on a phone [width] x [height].
  Future<(ProviderContainer, Future<void> Function())> pumpHome(
    WidgetTester tester, {
    String language = 'en',
    double width = 411,
    double height = 914,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = Size(width * 3, height * 3);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

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
    await tester.runAsync(
      () => container
          .read(authControllerProvider.notifier)
          .signIn(email: 'shopper@saba.app', password: 'Password1'),
    );

    await tester.pumpWidget(
      RepaintBoundary(
        key: shotKey,
        child: UncontrolledProviderScope(
          container: container,
          child: const SabaApp(),
        ),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 18; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    await settle();
    container.read(appRouterProvider).go(AppRoutes.home);
    await settle();
    return (container, settle);
  }

  Finder home() => find
      .byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      )
      .first;

  Future<void> shoot(WidgetTester tester, String name) async {
    if (!_shots) return;
    await tester.runAsync(() async {
      final boundary =
          shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/home_shots/$name.png')
        ..createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  test('the heading fonts are declared, bundled and chosen in one place', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final entry in _fonts.entries) {
      // The whole line: "family: AmiriX" must not pass for Amiri.
      expect(
        RegExp(
          '^ *- family: ${entry.key}\$',
          multiLine: true,
        ).hasMatch(pubspec),
        isTrue,
        reason: '${entry.key} is not declared: its text would fall back',
      );
      for (final file in entry.value) {
        expect(
          File('assets/fonts/$file').existsSync(),
          isTrue,
          reason: '$file is not in the app',
        );
      }
    }
  });

  testWidgets('a heading on Home uses the font for its language', (
    tester,
  ) async {
    late TextStyle english;
    late TextStyle arabic;
    Widget probe(Locale locale, void Function(TextStyle) keep) => Localizations(
      locale: locale,
      delegates: const [DefaultWidgetsLocalizations.delegate],
      child: Builder(
        builder: (context) {
          keep(AppTypography.heading(context, size: 21, color: Colors.black));
          return const SizedBox();
        },
      ),
    );
    await tester.pumpWidget(probe(const Locale('en'), (s) => english = s));
    await tester.pumpWidget(probe(const Locale('ar'), (s) => arabic = s));

    expect(english.fontFamily, AppTypography.headingFamily);
    expect(
      english.fontFamilyFallback,
      contains(AppTypography.headingFamilyArabic),
    );
    expect(arabic.fontFamily, AppTypography.headingFamilyArabic);
    expect(arabic.fontFamilyFallback, contains(AppTypography.headingFamily));
    // The body font stands last behind both, never a system font.
    expect(english.fontFamilyFallback!.last, AppTypography.family);
    expect(arabic.fontFamilyFallback!.last, AppTypography.family);
  });

  testWidgets('the globe switches the language, and all of Home follows', (
    tester,
  ) async {
    final (container, settle) = await pumpHome(tester);
    TextDirection direction() =>
        Directionality.of(tester.element(find.byType(Scaffold).first));

    TextStyle styleOf(String text) =>
        tester.widget<Text>(find.text(text).first).style!;

    expect(direction(), TextDirection.ltr);
    expect(find.text('Shop by category'), findsOneWidget);
    // The headings are in the heading font; the chips stay in the body font.
    expect(styleOf('Shop by category').fontFamily, AppTypography.headingFamily);
    expect(styleOf('Amina Saleh').fontFamily, AppTypography.headingFamily);
    await shoot(tester, 'home_en_top');

    await tester.tap(find.byTooltip(_en.changeLanguage));
    await settle();

    expect(container.read(localeControllerProvider)?.languageCode, 'ar');
    expect(direction(), TextDirection.rtl);
    // Read again from the server, in Arabic: not the English left on screen.
    expect(find.text('تسوّق حسب القسم'), findsOneWidget);
    expect(find.text('Shop by category'), findsNothing);
    expect(
      styleOf('تسوّق حسب القسم').fontFamily,
      AppTypography.headingFamilyArabic,
    );
    expect(
      styleOf('Amina Saleh').fontFamily,
      AppTypography.headingFamilyArabic,
    );
    await shoot(tester, 'home_ar_top');

    // The grid too: its first product, by its Arabic name.
    await tester.scrollUntilVisible(
      find.text(_ar.filters),
      400,
      scrollable: home(),
    );
    await settle();
    expect(find.text(_ar.productsFound(_onSale)), findsOneWidget);
    // The city chips, right above the grid they filter (just scrolled past).
    expect(find.text(_ar.allCities, skipOffstage: false), findsOneWidget);
    final firstName = tester
        .widget<ProductCard>(
          find
              .descendant(
                of: find.byType(HomeAllProducts),
                matching: find.byType(ProductCard),
              )
              .first,
        )
        .product
        .name;
    expect(firstName, 'هاتف نوفا X5 الذكي');
    await shoot(tester, 'home_ar_grid');

    // And back.
    await tester.scrollUntilVisible(
      find.byTooltip(_ar.changeLanguage),
      -400,
      scrollable: home(),
    );
    await tester.tap(find.byTooltip(_ar.changeLanguage));
    await settle();
    expect(direction(), TextDirection.ltr);
    expect(find.text('Shop by category'), findsOneWidget);
  });

  testWidgets('messages and notifications still open from the top bar', (
    tester,
  ) async {
    final (container, settle) = await pumpHome(tester);
    await tester.tap(find.byTooltip(_en.messages));
    await settle();
    expect(find.byType(ConversationsScreen), findsOneWidget);

    container.read(appRouterProvider).go(AppRoutes.home);
    await settle();
    await tester.tap(find.byTooltip(_en.notifications));
    await settle();
    expect(find.byType(NotificationsScreen), findsOneWidget);
  });

  testWidgets('the greeting can be read, and is whole on a small phone', (
    tester,
  ) async {
    await pumpHome(tester, width: 320, height: 568);
    final name = find.text('Amina Saleh');
    // Dark on the white header: a style made outside the header once drew
    // it white on white.
    final color = tester.widget<Text>(name).style!.color!;
    expect(
      color.computeLuminance(),
      lessThan(0.3),
      reason: 'the name is too light to read on the white header',
    );
    // Whole, not "Ami...": three icons leave little room on a small phone.
    expect(
      tester.renderObject<RenderParagraph>(name).didExceedMaxLines,
      isFalse,
      reason: 'the name is cut off',
    );
  });

  // The tester, at 320 px and the largest text: "Headph / ones" under its
  // circle, and the greeting's name shrunk to a whisper.
  testWidgets(
    'no word is broken, and the name keeps its size, on a small phone',
    (tester) async {
      await pumpHome(tester, width: 320, height: 568, textScale: 1.4);
      final name = find.text('Amina Saleh');
      expect(
        find.ancestor(of: name, matching: find.byType(FittedBox)),
        findsNothing,
        reason: 'the name is shrunk to fit',
      );
      expect(
        tester.renderObject<RenderParagraph>(name).didExceedMaxLines,
        isFalse,
      );

      final label = find.text('Headphones');
      await tester.scrollUntilVisible(label, 200, scrollable: home());
      final paragraph = tester.renderObject<RenderParagraph>(label);
      final lines =
          (TextPainter(
                text: paragraph.text,
                textScaler: paragraph.textScaler,
                textDirection: TextDirection.ltr,
              )..layout(maxWidth: paragraph.constraints.maxWidth))
              .computeLineMetrics()
              .length;
      expect(lines, 1, reason: 'the word is broken across lines');
    },
  );

  testWidgets('section titles are whole at the largest text size', (
    tester,
  ) async {
    await pumpHome(tester, width: 320, height: 568, textScale: 1.4);
    final title = find.text('Shop by category');
    await tester.scrollUntilVisible(title, 200, scrollable: home());
    expect(
      tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
      isFalse,
      reason: 'the title is cut off',
    );
  });

  for (final language in const ['en', 'ar']) {
    testWidgets('the banner words are whole at the largest text size in '
        '$language', (tester) async {
      await pumpHome(
        tester,
        language: language,
        width: 320,
        height: 568,
        textScale: 1.4,
      );
      final words = find.descendant(
        of: find.byType(HomePromoCarousel),
        matching: find.byType(Text),
      );
      expect(words, findsWidgets);
      for (final text in words.evaluate()) {
        final paragraph = text.findRenderObject()! as RenderParagraph;
        final shown = (text.widget as Text).data;
        expect(paragraph.didExceedMaxLines, isFalse, reason: '"$shown" is cut');
        // Its box as tall as its lines: the second line was cut in half.
        expect(
          paragraph.size.height,
          greaterThanOrEqualTo(paragraph.textSize.height - 0.01),
          reason: '"$shown" is clipped',
        );
      }
    });
  }

  // A small phone, a large one, and large text on the small one - in both
  // languages, with the real fonts, scrolled from the top to the last card.
  const phones = <(String, double, double, double)>[
    ('small', 320, 568, 1),
    // 1.4 is the largest text size the app allows (app.dart).
    ('small-large-text', 320, 568, 1.4),
    ('large', 430, 932, 1),
  ];
  for (final language in const ['en', 'ar']) {
    for (final (name, width, height, scale) in phones) {
      testWidgets('Home fits a $name phone in $language', (tester) async {
        final (_, settle) = await pumpHome(
          tester,
          language: language,
          width: width,
          height: height,
          textScale: scale,
        );
        await shoot(tester, 'home_${language}_$name');
        // Down to the last product, through every section and page.
        await tester.scrollUntilVisible(
          find.text(
            language == 'ar'
                ? 'مايكروويف الحدباء 30 لتر'
                : 'Hadba Microwave 30L',
          ),
          500,
          scrollable: home(),
          maxScrolls: 200,
        );
        await settle();
        await shoot(tester, 'home_${language}_${name}_end');
      });
    }
  }

  testWidgets('a page other than Home follows a language switch at once', (
    tester,
  ) async {
    final (container, settle) = await pumpHome(tester);
    container
        .read(appRouterProvider)
        .go(AppRoutes.categoryProductsPath('c-phones'));
    await settle();
    expect(find.text('Nova X5 Smartphone'), findsOneWidget);

    await tester.runAsync(
      () => container
          .read(localeControllerProvider.notifier)
          .setLocale(const Locale('ar')),
    );
    await settle();

    // Read again in Arabic, without leaving the page. Only Home used to.
    expect(find.text('هاتف نوفا X5 الذكي'), findsOneWidget);
    expect(find.text('Nova X5 Smartphone'), findsNothing);
  });
}
