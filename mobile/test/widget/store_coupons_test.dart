// A store's own coupons: made from the Store tab, seen on the store's page.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/app.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/merchant/presentation/screens/merchant_coupons_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// Where the image cache keeps its files; a test has no phone to ask.
const _paths = MethodChannel('plugins.flutter.io/path_provider');

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

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          _paths,
          (_) async => Directory.systemTemp.path,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_paths, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_keystore, null);
    DioFactory.mockBackend.resetForTesting();
  });

  /// The app on a phone; signed in as [email], or signed out when null.
  Future<(ProviderContainer, Future<void> Function())> pumpApp(
    WidgetTester tester, {
    String? email,
  }) async {
    tester.view.physicalSize = const Size(411 * 3, 914 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues(<String, Object>{
      'saba.pref.onboarding_seen': true,
      'saba.pref.locale': 'en',
    });
    final preferences = await AppPreferences.create();
    final container = ProviderContainer(
      overrides: [appPreferencesProvider.overrideWithValue(preferences)],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);

    if (email != null) {
      await tester.runAsync(() async {
        await container
            .read(authControllerProvider.notifier)
            .signIn(email: email, password: 'Password1');
      });
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SabaApp()),
    );

    Future<void> settle() async {
      for (var i = 0; i < 18; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    await settle();
    return (container, settle);
  }

  testWidgets('a merchant makes a coupon from the Store tab', (tester) async {
    final (container, settle) = await pumpApp(
      tester,
      email: 'merchant@saba.app',
    );
    container.read(appRouterProvider).go(AppRoutes.merchantAccount);
    await settle();

    final door = find.text(_en.coupons);
    expect(door, findsOneWidget, reason: 'the Store tab has no way in');
    await tester.ensureVisible(door);
    await tester.pump();
    await tester.tap(door);
    await settle();
    expect(find.byType(MerchantCouponsScreen), findsOneWidget);
    // The demo store's own: one running, one that starts later.
    expect(find.text('NOVA10'), findsOneWidget);
    expect(find.text(_en.couponScheduled), findsOneWidget);

    await tester.tap(find.text(_en.newCoupon));
    await settle();
    expect(find.byType(MerchantCouponFormScreen), findsOneWidget);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'eid20');
    await tester.enterText(fields.at(1), '20');
    await tester.pump();
    // The ticket a customer will see, drawn as it is typed.
    expect(find.text(_en.amountOff('20%')), findsOneWidget);
    expect(find.text('EID20'), findsWidgets);

    await tester.tap(find.text(_en.save));
    await settle();

    expect(find.byType(MerchantCouponsScreen), findsOneWidget);
    expect(
      find.text('EID20'),
      findsOneWidget,
      reason: 'the new coupon is not on the list',
    );
  });

  testWidgets('a store page shows the coupons it is running', (tester) async {
    final (container, settle) = await pumpApp(
      tester,
      email: 'shopper@saba.app',
    );
    container.read(appRouterProvider).go(AppRoutes.storefrontPath('m-1'));
    await settle();

    // A sticker on the store's sign, which opens every code it is running.
    final sticker = find.byTooltip(_en.couponsFrom('Nova Electronics'));
    expect(
      sticker,
      findsOneWidget,
      reason: "the store's coupons are not on its page",
    );
    expect(find.textContaining('NOVA10'), findsOneWidget);
    await tester.tap(sticker);
    await settle();
    expect(find.text(_en.copy), findsWidgets);
    expect(
      find.textContaining('WEEKEND15'),
      findsNothing,
      reason: 'a coupon that starts later was shown as usable',
    );
  });
}
