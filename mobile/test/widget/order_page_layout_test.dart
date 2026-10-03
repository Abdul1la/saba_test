// The order page before "Did you receive it?" is answered, drawn with the
// fonts the phone uses on a small phone. The tester found the driver's number
// broken in two, "+964 770 555 / 9988", and "Yes, I got it" shrunk to a tiny
// font beside a full-size "No": both were squeezed into a narrow column
// beside the store's Message button.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/theme/app_theme.dart';
import 'package:saba_marketplace/core/theme/app_typography.dart';
import 'package:saba_marketplace/features/orders/domain/entities.dart';
import 'package:saba_marketplace/features/orders/presentation/orders_providers.dart';
import 'package:saba_marketplace/features/orders/presentation/screens/order_detail_screen.dart';

const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// The body font, as pubspec.yaml declares it.
const _fonts = [
  'IBMPlexSansArabic-Light.ttf',
  'IBMPlexSansArabic-Regular.ttf',
  'IBMPlexSansArabic-Medium.ttf',
  'IBMPlexSansArabic-SemiBold.ttf',
  'IBMPlexSansArabic-Bold.ttf',
];

/// Nova's part, delivered and not yet answered, with its driver.
final _order = Order(
  id: 'o-arrived',
  orderNumber: 'SB-1002',
  placedAt: DateTime(2026, 9, 20),
  status: OrderStatus.delivered,
  paymentStatus: PaymentStatus.pending,
  items: const <OrderItem>[
    OrderItem(
      id: 'i-1',
      productName: 'Nova X5 Smartphone',
      quantity: 1,
      unitPrice: 100000,
      lineTotal: 100000,
      currencyCode: 'IQD',
      merchantId: 'm-1',
      merchantName: 'Nova Electronics',
      status: OrderStatus.delivered,
    ),
  ],
  subtotal: 100000,
  total: 100000,
  currencyCode: 'IQD',
  parts: const <String, OrderStorePart>{
    'm-1': OrderStorePart(
      amountDue: 100000,
      courierName: 'Haider Salim',
      courierPhone: '+9647705559988',
    ),
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The real fonts, from the app's own bundle: a test normally draws every
  // letter as a 1em box, twice as wide as the phone's letters.
  setUpAll(() async {
    final loader = FontLoader(AppTypography.family);
    for (final file in _fonts) {
      loader.addFont(rootBundle.load('assets/fonts/$file'));
    }
    await loader.load();
  });

  setUp(() {
    DioFactory.mockBackend.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_keystore, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_keystore, null);
    DioFactory.mockBackend.resetForTesting();
  });

  for (final language in ['en', 'ar']) {
    testWidgets('the driver\'s number is whole and both answers full size, '
        '$language', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final l10n = AppLocalizations(Locale(language));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            orderDetailProvider(_order.id).overrideWith((ref) async => _order),
          ],
          retry: (_, _) => null,
          child: MaterialApp(
            theme: AppTheme.light(),
            locale: Locale(language),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const <LocalizationsDelegate<Object>>[
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: OrderDetailScreen(orderId: _order.id),
          ),
        ),
      );
      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }

      // Every glyph of the number on one line.
      const number = '+964 770 555 9988';
      final paragraph = tester.renderObject<RenderParagraph>(
        find.textContaining(number),
      );
      final start = paragraph.text.toPlainText().indexOf(number);
      final lines = {
        for (final box in paragraph.getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: start + number.length),
        ))
          box.top.round(),
      };
      expect(lines, hasLength(1), reason: 'the number broke across lines');

      // Drawn at the size it was laid out at: a label shrunk to fit is
      // painted smaller than itself.
      expect(find.text(l10n.didYouReceive), findsOneWidget);
      for (final label in [l10n.yesReceived, l10n.noNotReceived]) {
        final text = find.text(label);
        expect(text, findsOneWidget);
        expect(
          tester.getRect(text).height,
          closeTo(tester.getSize(text).height, 0.5),
          reason: '"$label" shrunk to fit',
        );
      }
    });
  }

  // The user: a two-store order had one timeline, so with one store
  // delivered and the other not, nothing said whose parcel was where. A box
  // per store now, each with a bar of four steps across it - compact with
  // five stores, on the smallest phone at the largest text.
  for (final language in ['en', 'ar']) {
    for (final dark in [false, true]) {
      testWidgets('five stores, a box and a step bar each, $language'
          '${dark ? ', dark' : ''}', (tester) async {
        tester.view.physicalSize = const Size(320 * 3, 640 * 3);
        tester.view.devicePixelRatio = 3;
        tester.platformDispatcher.textScaleFactorTestValue = 1.4;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final l10n = AppLocalizations(Locale(language));

        const steps = [
          ('m-1', 'Nova Electronics', OrderStatus.delivered),
          ('m-2', 'Atlas Home', OrderStatus.shipped),
          ('m-3', 'Zakho Mobile', OrderStatus.processing),
          ('m-4', 'Basra Gadgets', OrderStatus.confirmed),
          ('m-5', 'Erbil Tech', OrderStatus.pending),
        ];
        final order = Order(
          id: 'o-five',
          orderNumber: 'SB-1005',
          placedAt: DateTime(2026, 9, 20),
          status: OrderStatus.confirmed,
          paymentStatus: PaymentStatus.pending,
          items: [
            for (final (id, name, status) in steps)
              OrderItem(
                id: 'i-$id',
                productName: 'Item from $name',
                quantity: 1,
                unitPrice: 10000,
                lineTotal: 10000,
                currencyCode: 'IQD',
                merchantId: id,
                merchantName: name,
                status: status,
              ),
          ],
          subtotal: 50000,
          total: 50000,
          currencyCode: 'IQD',
          parts: {
            for (final (id, _, status) in steps)
              id: OrderStorePart(
                amountDue: 10000,
                deliveryTime: '1_2_DAYS',
                courierName: status == OrderStatus.shipped ? 'Ali' : null,
                courierPhone: status == OrderStatus.shipped
                    ? '+9647701112222'
                    : null,
              ),
          },
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              orderDetailProvider(order.id).overrideWith((ref) async => order),
            ],
            retry: (_, _) => null,
            child: MaterialApp(
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              themeMode: dark ? ThemeMode.dark : ThemeMode.light,
              locale: Locale(language),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const <LocalizationsDelegate<Object>>[
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: OrderDetailScreen(orderId: order.id),
            ),
          ),
        );
        for (var i = 0; i < 14; i++) {
          await tester.pump(const Duration(milliseconds: 120));
        }
        expect(tester.takeException(), isNull, reason: 'overflowed');

        // A bar per store, each at its own step.
        final bars = find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == '_StepBar',
        );
        expect(bars, findsNWidgets(5));
        for (final (_, name, _) in steps) {
          expect(find.text(name), findsOneWidget, reason: name);
        }
        // Where each one is: the driver once shipped, when it should come
        // before that.
        expect(find.textContaining('${l10n.driverLabel}: Ali'), findsOneWidget);
        expect(
          find.text(l10n.expectedArrival(l10n.delivery1to2Days)),
          findsNWidgets(3),
        );
        // The badge at the top follows the slowest store, and says so.
        expect(
          find.text(l10n.orderFollowsSlowest(l10n.orderStatusConfirmed)),
          findsOneWidget,
        );
        // Compact: a box is its store, its bar and its line, not a timeline.
        final boxes = find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == '_StoreBox',
        );
        for (final box in tester.widgetList(boxes)) {
          final height = tester.getSize(find.byWidget(box)).height;
          expect(height, lessThan(420), reason: 'a box $height tall');
        }
      });
    }
  }
}
