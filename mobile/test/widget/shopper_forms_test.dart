// The two forms a shopper meets after buying, and what they demanded.
//
// The stars on a delivered order open the review already answered, because
// most reviews are a rating and nothing else. Then the review form refused to
// submit without ten characters of prose, so the one-tap path ended at a wall.
// And the address form asked every customer in Iraq to type the name of their
// own country into a blank required field.
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
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/cart/presentation/cart_providers.dart';
import 'package:saba_marketplace/features/checkout/presentation/checkout_providers.dart';
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

  /// [route] is where the app lands; [pushed] is opened on top of it, the
  /// way the app opens it — a screen that ends by popping needs something
  /// underneath to pop back to.
  Future<ProviderContainer> openSignedIn(
    WidgetTester tester,
    String route, {
    String? pushed,
    Future<void> Function(ProviderContainer)? before,
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
      await container
          .read(authControllerProvider.notifier)
          .signIn(email: 'demo@saba.app', password: 'Password1');
      if (before != null) await before(container);
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
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    container.read(appRouterProvider).go(route);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    if (pushed != null) {
      container.read(appRouterProvider).push(pushed);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }
    return container;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('an invoice can be sent to someone', (tester) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    late String orderId;
    final container = await openSignedIn(
      tester,
      AppRoutes.orders,
      before: (c) async {
        await c
            .read(cartControllerProvider.notifier)
            .addItem(productId: 'p-1', quantity: 2);
        final checkout = c.read(checkoutControllerProvider.notifier);
        await checkout.priceOrder();
        orderId = (await checkout.placeOrder()).unwrap().orderId;
      },
    );

    container.read(appRouterProvider).push(AppRoutes.orderInvoicePath(orderId));
    await settle(tester);
    expect(find.text(_en.invoice), findsWidgets);
    // The screen's own comment says this is what a customer forwards on.
    await tester.tap(find.text(_en.copy));
    await settle(tester);

    expect(copied, isNotNull);
    expect(copied, contains(_en.grandTotal));
    expect(find.text(_en.copiedToClipboard), findsOneWidget);
  });

  testWidgets('a new address starts with her name, her number and her city', (
    tester,
  ) async {
    await openSignedIn(
      tester,
      AppRoutes.addresses,
      pushed: AppRoutes.addressForm,
    );

    // Iraq only, found by landmark: no country, no postal code.
    expect(find.text(_en.country), findsNothing);
    expect(find.text(_en.postalCode), findsNothing);
    expect(
      find.widgetWithText(TextField, 'Amina Saleh'),
      findsOneWidget,
      reason: 'her name is not filled in',
    );
    expect(
      find.widgetWithText(TextField, '7701234567'),
      findsOneWidget,
      reason: 'her number is not filled in',
    );
    expect(find.text('Baghdad'), findsOneWidget, reason: 'no city picked');

    Future<void> save() async {
      await tester.ensureVisible(find.text(_en.save));
      await tester.tap(find.text(_en.save));
      await tester.pump(const Duration(milliseconds: 300));
    }

    // Left blank, the area and the landmark are asked for.
    await save();
    expect(find.text(_en.validationRequired), findsNWidgets(2));

    // A number that is not an Iraqi mobile never reaches a driver.
    await tester.enterText(
      find.widgetWithText(TextField, '7701234567'),
      '0123 456',
    );
    await save();
    expect(find.text(_en.validationPhone), findsOneWidget);
  });
}
