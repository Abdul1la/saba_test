// Every main screen, signed in, against the real server: what the server
// refuses shows up in its log. Skipped unless asked for (see
// m1_accounts_walk_test.dart for the flags).
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/app.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _live = bool.fromEnvironment('LIVE');
const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = <String, String>{};

  setUpAll(() {
    HttpOverrides.global = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => Directory.systemTemp.path,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_keystore, (call) async {
          final key = call.arguments is Map ? call.arguments['key'] : null;
          switch (call.method) {
            case 'write':
              store[key as String] = call.arguments['value'] as String? ?? '';
            case 'read':
              return store[key as String];
            case 'delete':
              store.remove(key as String);
            case 'readAll':
              return Map<String, String>.from(store);
            case 'deleteAll':
              store.clear();
          }
          return null;
        });
  });

  for (final (who, phone, email, routes) in [
    (
      'shopper',
      '+9647701234567',
      null,
      [
        AppRoutes.home,
        AppRoutes.categories,
        AppRoutes.cart,
        AppRoutes.orders,
        AppRoutes.account,
        AppRoutes.notifications,
        AppRoutes.conversations,
        AppRoutes.profile,
        AppRoutes.addresses,
        AppRoutes.wishlist,
        AppRoutes.supportTickets,
      ],
    ),
    (
      'store',
      null,
      'merchant@saba.app',
      [
        AppRoutes.merchantDashboard,
        AppRoutes.merchantProducts,
        AppRoutes.merchantOrders,
        AppRoutes.merchantInventory,
        AppRoutes.merchantAnalytics,
        AppRoutes.merchantPayouts,
        AppRoutes.merchantStoreSettings,
        AppRoutes.merchantCoupons,
        AppRoutes.merchantAccount,
        AppRoutes.notifications,
        AppRoutes.conversations,
      ],
    ),
  ]) {
    testWidgets(
      'every $who screen opens against the real server',
      skip: !_live,
      (tester) async {
        tester.view.physicalSize = const Size(411 * 3, 914 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        store.clear();
        SharedPreferences.setMockInitialValues(<String, Object>{
          'saba.pref.onboarding_seen': true,
          'saba.pref.locale': 'en',
        });
        final prefs = await tester.runAsync(AppPreferences.create);
        final container = ProviderContainer(
          overrides: [appPreferencesProvider.overrideWithValue(prefs!)],
          retry: (_, _) => null,
        );
        addTearDown(container.dispose);
        final signed = await tester.runAsync(
          () => container
              .read(authControllerProvider.notifier)
              .signIn(phone: phone, email: email, password: 'saba12345'),
        );
        print('[$who] sign-in: ${signed!.isOk ? 'OK' : signed.failureOrNull}');

        Future<void> settle() async {
          for (var i = 0; i < 10; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 150)),
            );
            await tester.pump(const Duration(milliseconds: 50));
          }
        }

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const SabaApp(),
          ),
        );
        await settle();
        for (final route in routes) {
          container.read(appRouterProvider).go(route);
          await settle();
          final problem = tester.takeException();
          final at = container
              .read(appRouterProvider)
              .routerDelegate
              .currentConfiguration
              .uri
              .path;
          print('[$who] $route -> $at${problem == null ? '' : ' ! $problem'}');
        }
        await tester.pumpWidget(const SizedBox());
        await settle();
      },
    );
  }
}
