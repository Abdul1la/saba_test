// Pictures of every screen, for a design review without a phone.
//
// Skipped unless asked for:
//   flutter test test/widget/design_shots_test.dart --dart-define=SABA_SHOTS=true
// Optional: --dart-define=SABA_SHOTS_WIDTH=320 and SABA_SHOTS_SCALE=1.4 for a
// small phone at the largest text size; SABA_SHOTS_ONLY=login,/cart for only
// the routes containing one of those words. The pictures land in
// build/design_shots/<side>_<language>_<mode>/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/app.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/core/theme/app_colors.dart';
import 'package:saba_marketplace/core/theme/app_theme.dart';
import 'package:saba_marketplace/core/theme/app_typography.dart';
import 'package:saba_marketplace/core/widgets/saba_logo.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/cart/presentation/cart_providers.dart';
import 'package:saba_marketplace/features/checkout/presentation/checkout_providers.dart';
import 'package:saba_marketplace/features/messaging/presentation/messaging_providers.dart';
import 'package:saba_marketplace/features/support/presentation/support_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _paths = MethodChannel('plugins.flutter.io/path_provider');

const _shots = bool.fromEnvironment('SABA_SHOTS');
const _width = int.fromEnvironment('SABA_SHOTS_WIDTH', defaultValue: 411);
const _scale = String.fromEnvironment('SABA_SHOTS_SCALE', defaultValue: '1');
const _only = String.fromEnvironment('SABA_SHOTS_ONLY');

/// Every picture this run wrote, as `folder/file`, for the index page.
final _written = <String>[];

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = <String, String>{};
  final shotKey = GlobalKey();

  // One page to look through them all: a row per screen, a column per
  // language and mode, a long page's scrolled pictures under each other.
  tearDownAll(() {
    if (!_shots || _written.isEmpty) return;
    // side -> screen -> column -> pictures. From this run's pictures only,
    // so one left in the folder by an older run is never shown.
    final table = <String, Map<String, Map<String, List<String>>>>{};
    for (final path in _written) {
      final [folderName, fileName] = path.split('/');
      final cut = folderName.indexOf('_');
      final side = folderName.substring(0, cut);
      final column = folderName.substring(cut + 1);
      final screen = fileName.replaceFirst(RegExp(r'_\d+\.png$'), '');
      ((table[side] ??= {})[screen] ??= {})[column] ??= [];
      table[side]![screen]![column]!.add(path);
    }
    const order = ['en_light', 'en_dark', 'ar_light', 'ar_dark'];
    int rank(String column) {
      final index = order.indexOf(column);
      return index < 0 ? order.length : index;
    }

    final html = StringBuffer()
      ..writeln('<!doctype html><html><head><meta charset="utf-8">')
      ..writeln('<title>Saba screens</title><style>')
      ..writeln(
        'body{margin:0;padding:16px;background:#e9e6e1;color:#1c2536;'
        'font:14px system-ui,sans-serif}h1{margin:0 0 4px}'
        'h2{margin:32px 0 8px;text-transform:capitalize}'
        'nav a{margin-right:12px;color:#7b3fd4}'
        '.row{display:flex;gap:12px;overflow-x:auto;padding-bottom:8px;'
        'border-bottom:1px solid #cfc8bf}h3{margin:20px 0 8px}'
        '.col{flex:0 0 auto}.col b{display:block;margin:0 0 4px}'
        '.col img{display:block;width:260px;margin-bottom:6px;'
        'border-radius:8px;box-shadow:0 1px 4px #0003}',
      )
      ..writeln('</style></head><body><h1>Saba, every screen</h1>')
      ..writeln(
        '<p>English and Arabic, light and dark, at 411 px. '
        'A long screen continues downward in its column.</p><nav>',
      );
    final sides = table.keys.toList()..sort();
    for (final side in sides) {
      html.write('<a href="#$side">$side</a>');
    }
    html.writeln('</nav>');
    for (final side in sides) {
      html.writeln('<h2 id="$side">$side</h2>');
      final screens = table[side]!.keys.toList()..sort();
      for (final screen in screens) {
        html.writeln('<h3>$screen</h3><div class="row">');
        final columns = table[side]![screen]!.keys.toList()
          ..sort((a, b) => rank(a).compareTo(rank(b)));
        for (final column in columns) {
          final shots = table[side]![screen]![column]!..sort();
          html.write('<div class="col"><b>${column.replaceAll('_', ' ')}</b>');
          for (final shot in shots) {
            html.write('<img loading="lazy" src="$shot">');
          }
          html.writeln('</div>');
        }
        html.writeln('</div>');
      }
    }
    html.writeln('</body></html>');
    // A partial run gets its own page, so it never replaces the full one.
    final suffix = [
      if (_width != 411) '$_width',
      if (_scale != '1') 'x$_scale',
      if (_only.isNotEmpty) 'only',
    ].join('_');
    File(
      'build/design_shots/index${suffix.isEmpty ? '' : '_$suffix'}.html',
    ).writeAsStringSync(html.toString());
  });

  setUpAll(() async {
    if (!_shots) return;
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

  /// Draws each of [routes] as [who] and saves a picture of it.
  Future<void> shootAll(
    WidgetTester tester, {
    required String side,
    required String language,
    required String mode,
    required String? who,
    required Future<List<String>> Function(ProviderContainer) routes,
  }) async {
    // A real phone's screen: a taller canvas pushed fill-the-screen layouts
    // apart. A longer page gets more pictures, scrolled, instead.
    tester.view.physicalSize = Size(_width * 2.0, 914 * 2.0);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = double.parse(_scale);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    SharedPreferences.setMockInitialValues(<String, Object>{
      'saba.pref.onboarding_seen': true,
      'saba.pref.locale': language,
      'saba.pref.theme_mode': mode,
    });
    final preferences = await AppPreferences.create();
    final container = ProviderContainer(
      overrides: [appPreferencesProvider.overrideWithValue(preferences)],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);

    late List<String> paths;
    await tester.runAsync(() async {
      if (who != null) {
        await container
            .read(authControllerProvider.notifier)
            .signIn(email: who, password: 'Password1');
      }
      paths = await routes(container);
    });

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
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    await settle();
    final folder =
        '${side}_${language}_$mode'
        '${_width == 411 ? '' : '_$_width'}'
        '${_scale == '1' ? '' : '_x$_scale'}';
    for (final route in paths) {
      if (_only.isNotEmpty && !_only.split(',').any(route.contains)) continue;
      container.read(appRouterProvider).go(route);
      await settle();
      // Photos decode off the test clock.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await settle();
      // A redirected route would be a picture of some other screen.
      expect(
        container
            .read(appRouterProvider)
            .routerDelegate
            .currentConfiguration
            .uri
            .path,
        Uri.parse(route).path,
        reason: '$route was redirected',
      );
      // The order placed for the pictures has a new number in each run;
      // named without it, one screen is one row on the index page.
      final name = route
          .replaceAll(RegExp(r'order-\d+'), 'order')
          .replaceAll(RegExp(r'[/?=&]+'), '_')
          .replaceAll(RegExp(r'^_|_$'), '');
      Future<void> shoot(int part) => tester.runAsync(() async {
        final boundary =
            shotKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final path = '$folder/${name.isEmpty ? 'root' : name}_$part.png';
        File('build/design_shots/$path')
          ..createSync(recursive: true)
          ..writeAsBytesSync(bytes!.buffer.asUint8List());
        _written.add(path);
      });

      await shoot(1);
      // The page's own scroll: the vertical one that goes furthest.
      final pages =
          tester
              .stateList<ScrollableState>(find.byType(Scrollable))
              .where(
                (state) =>
                    state.position.axis == Axis.vertical &&
                    state.position.maxScrollExtent > 0,
              )
              .toList()
            ..sort(
              (a, b) => b.position.maxScrollExtent.compareTo(
                a.position.maxScrollExtent,
              ),
            );
      if (pages.isEmpty) continue;
      final page = pages.first.position;
      for (var part = 2; part <= 4; part++) {
        if (page.pixels >= page.maxScrollExtent) break;
        page.jumpTo(
          (page.pixels + page.viewportDimension * 0.8).clamp(
            0,
            page.maxScrollExtent,
          ),
        );
        await settle();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await settle();
        await shoot(part);
      }
    }
  }

  for (final language in const ['en', 'ar']) {
    for (final mode in const ['light', 'dark']) {
      testWidgets('shopper screens, $language, $mode', skip: !_shots, (
        tester,
      ) async {
        await shootAll(
          tester,
          side: 'shopper',
          language: language,
          mode: mode,
          who: 'demo@saba.app',
          routes: (container) async {
            await container
                .read(cartControllerProvider.notifier)
                .addItem(productId: 'p-1', quantity: 2);
            final checkout = container.read(
              checkoutControllerProvider.notifier,
            );
            await checkout.priceOrder();
            final orderId = (await checkout.placeOrder()).unwrap().orderId;
            await container
                .read(cartControllerProvider.notifier)
                .addItem(productId: 'p-2', quantity: 1);
            final chat =
                (await container
                        .read(messagingRepositoryProvider)
                        .startWithStore('m-1'))
                    .unwrap();
            final tickets =
                (await container.read(supportRepositoryProvider).tickets())
                    .unwrap();
            return [
              AppRoutes.home,
              AppRoutes.categories,
              AppRoutes.cart,
              AppRoutes.checkout,
              AppRoutes.orders,
              AppRoutes.orderDetailPath(orderId),
              AppRoutes.orderInvoicePath(orderId),
              AppRoutes.orderConfirmationPath(orderId),
              AppRoutes.account,
              AppRoutes.settings,
              AppRoutes.profile,
              AppRoutes.addresses,
              AppRoutes.addressForm,
              AppRoutes.search,
              AppRoutes.wishlist,
              AppRoutes.notifications,
              AppRoutes.conversations,
              AppRoutes.productDetailPath('p-1'),
              AppRoutes.productDetailPath('p-2'),
              AppRoutes.storefrontPath('m-1'),
              AppRoutes.merchantReviewsPath('m-1'),
              AppRoutes.categoryProductsPath('c-1'),
              AppRoutes.conversationPath(chat.id),
              AppRoutes.supportTickets,
              AppRoutes.newSupportTicket,
              if (tickets.isNotEmpty)
                AppRoutes.supportTicketPath(tickets.first.id),
              AppRoutes.requestReturnPath(orderId),
              AppRoutes.legalPath('privacy'),
            ];
          },
        );
      });

      testWidgets('store screens, $language, $mode', skip: !_shots, (
        tester,
      ) async {
        await shootAll(
          tester,
          side: 'store',
          language: language,
          mode: mode,
          who: 'merchant@saba.app',
          routes: (_) async => [
            AppRoutes.merchantDashboard,
            AppRoutes.merchantProducts,
            AppRoutes.merchantOrders,
            AppRoutes.merchantOrderDetailPath('mo-1'),
            AppRoutes.merchantAnalytics,
            AppRoutes.merchantAccount,
            AppRoutes.merchantProductForm,
            AppRoutes.merchantInventory,
            AppRoutes.merchantPayouts,
            AppRoutes.merchantStoreSettings,
            AppRoutes.merchantCoupons,
            AppRoutes.merchantCouponForm,
            AppRoutes.conversations,
            AppRoutes.notifications,
          ],
        );
      });

      testWidgets('sign-in screens, $language, $mode', skip: !_shots, (
        tester,
      ) async {
        await shootAll(
          tester,
          side: 'auth',
          language: language,
          mode: mode,
          who: null,
          routes: (_) async => [
            AppRoutes.language,
            AppRoutes.login,
            AppRoutes.forgotPassword,
            AppRoutes.registerPhonePath(merchant: false),
            AppRoutes.registerPhonePath(merchant: true),
          ],
        );
      });

      // Every version of the logo on one page: as the page draws it, on the
      // splash's purple, on a white document, and the mark alone.
      testWidgets('logo, $language, $mode', skip: !_shots, (tester) async {
        tester.view.physicalSize = Size(_width * 2.0, 700 * 2.0);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          RepaintBoundary(
            key: shotKey,
            child: MaterialApp(
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              themeMode: mode == 'dark' ? ThemeMode.dark : ThemeMode.light,
              locale: Locale(language),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: const Scaffold(
                body: Column(
                  children: [
                    SizedBox(height: 32),
                    SabaLogo(size: 56),
                    SizedBox(height: 24),
                    ColoredBox(
                      color: AppPalette.brand,
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(
                          child: SabaLogo(size: 56, tone: SabaMarkTone.white),
                        ),
                      ),
                    ),
                    SizedBox(height: 24),
                    ColoredBox(
                      color: AppPalette.surface,
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(
                          child: SabaLogo(size: 40, tone: SabaMarkTone.navy),
                        ),
                      ),
                    ),
                    SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SabaMark(size: 96),
                        SizedBox(width: 16),
                        SabaMark(size: 48),
                        SizedBox(width: 16),
                        SabaMark(size: 24),
                        SizedBox(width: 16),
                        SabaMark(size: 16),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final boundary =
              shotKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final path = 'logo_${language}_$mode/logo_1.png';
          File('build/design_shots/$path')
            ..createSync(recursive: true)
            ..writeAsBytesSync(bytes!.buffer.asUint8List());
          _written.add(path);
        });
      });
    }
  }
}
