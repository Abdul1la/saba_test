// M6 (BACKEND_PLAN.md 8.1): the store's money screens, with the app's own
// code against the real server. Skipped unless asked for:
//
//   flutter test test/live/m6_money_walk_test.dart \
//     --dart-define=LIVE=true --dart-define=USE_MOCK_DATA=false \
//     --dart-define=API_BASE_URL=http://localhost:3000/api/v1 \
//     --dart-define=PHASE=money|bills|close|screens
//
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/app.dart';
import 'package:saba_marketplace/core/config/app_config.dart';
import 'package:saba_marketplace/core/errors/failure.dart';
import 'package:saba_marketplace/core/errors/result.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/merchant/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _live = bool.fromEnvironment('LIVE');
const _phase = String.fromEnvironment('PHASE', defaultValue: 'money');
const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = <String, String>{};

  setUpAll(() {
    HttpOverrides.global = null;
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

  String say(Result<Object?> result) => result.fold(
    ok: (value) => 'OK',
    err: (Failure f) => 'ERR ${f.statusCode} "${f.message}" ${f.fieldErrors}',
  );

  Future<ProviderContainer> as(
    String? phone,
    String? email,
    String password, {
    String locale = 'en',
  }) async {
    store.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'saba.pref.onboarding_seen': true,
      'saba.pref.locale': locale,
    });
    final c = ProviderContainer(
      overrides: [
        appPreferencesProvider.overrideWithValue(await AppPreferences.create()),
      ],
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);
    await c.read(authControllerProvider.future);
    final r = await c
        .read(authControllerProvider.notifier)
        .signIn(phone: phone, email: email, password: password);
    print('sign-in ${phone ?? email}: ${say(r)}');
    return c;
  }

  final stores = <String, Future<ProviderContainer> Function()>{
    'Nova': () => as(null, 'merchant@saba.app', 'saba12345'),
    'Atlas': () => as(null, 'merchant2@saba.app', 'saba12345'),
    'M2 Store': () => as('+9647732172587', null, 'walkpass123'),
  };

  /// The rule, worked out here from the bill's own sales and returns.
  num owedBy(num sales, num returned) {
    final net = sales - returned;
    if (net <= 0) return 0;
    return (net * 8 / 100 / 250).round() * 250;
  }

  String bill(SabaBill b) {
    final expected = owedBy(b.sales, b.returned);
    return '${b.month.year}-${b.month.month.toString().padLeft(2, '0')} '
        'orders=${b.orderCount} sales=${b.sales} returned=${b.returned} '
        'owed=${b.owed} ${b.owed == expected ? '(rule OK)' : '(RULE SAYS $expected)'} '
        'due=${b.isDue} paid=${b.paidAt?.toLocal()}';
  }

  Future<void> bills(String name, MerchantRepository repo) async {
    final b = (await repo.bills()).unwrap();
    print('$name bills rate=${b.ratePercent}%: now ${bill(b.current)}');
    for (final m in b.past) {
      print('$name   past ${bill(m)}');
    }
  }

  test('M6 phase $_phase', skip: !_live, timeout: Timeout.none, () async {
    print('API ${AppConfig.apiBaseUrl} mock=${AppConfig.useMockData}');

    if (_phase == 'money') {
      for (final MapEntry(key: name, value: open) in stores.entries) {
        final repo = (await open()).read(merchantRepositoryProvider);
        await bills(name, repo);

        final d = (await repo.dashboard()).unwrap();
        print(
          '$name dashboard: revenue=${d.revenue} previous=${d.previousRevenue} '
          'days=${d.comparisonDays} today=${d.todaySales} total=${d.totalSales} '
          'orders=${d.orderCount} delta=${d.orderCountDelta} toConfirm=${d.pendingOrders} '
          'oldest=${d.oldestPendingHours}h low=${d.lowStockCount} out=${d.outOfStockCount} '
          'rejected=${d.rejectedCount} returns=${d.returnCount} refunds=${d.refundTotal} '
          'rating=${d.rating} (${d.ratingCount})',
        );
        print(
          '$name chart: ${[for (final p in d.salesSeries) '${p.label}(${p.from?.toLocal()}):${p.value}']}',
        );
        final counts = (await repo.orderCounts()).valueOrNull;
        final shelf = (await repo.productCounts()).valueOrNull;
        var rejected = 0;
        for (var page = 1; page < 30; page++) {
          final list = (await repo.products(page: page)).valueOrNull;
          if (list == null) break;
          rejected += list.items.where((r) => r.status == 'REJECTED').length;
          if (!list.hasNextPage) break;
        }
        print(
          '$name against: orders=$counts shelf=$shelf rejected rows=$rejected',
        );

        for (final period in ['week', 'month', 'year']) {
          final a = (await repo.analytics(period: period)).unwrap();
          print(
            '$name $period: revenue=${a.revenue} previous=${a.previousRevenue} orders=${a.orderCount} '
            'sold=${a.productsSold} average=${a.averageOrderValue} refunds=${a.refundTotal} '
            'cancelled=${a.cancellationCount}',
          );
          print(
            '$name $period series: ${[for (final p in a.series) '${p.label}(${p.from?.toLocal()}):${p.value}']}',
          );
          print(
            '$name $period top: ${[for (final t in a.topProducts) '${t.name}:${t.price}']}',
          );
        }
      }
    }

    if (_phase == 'bills') {
      final repo = (await stores['Atlas']!()).read(merchantRepositoryProvider);
      await bills('Atlas', repo);
    }

    // 3. Closed with August due, and open again at once.
    if (_phase == 'close') {
      final repo = (await stores['Atlas']!()).read(merchantRepositoryProvider);
      await bills('Atlas', repo);
      print('3 close: ${say(await repo.setOpen(false))}');
      print('3 open again: ${say(await repo.setOpen(true))}');
      print('3 open now: ${(await repo.dashboard()).valueOrNull?.isOpen}');
      final counts = (await repo.orderCounts()).valueOrNull;
      print('3 orders: $counts');
    }
  });

  // 7. The money screens themselves, in English and Arabic, on the real
  // server: the months, the statuses, the amounts and the paid day.
  for (final locale in ['en', 'ar']) {
    testWidgets(
      'M6 Atlas money screens ($locale)',
      skip: !_live || _phase != 'screens',
      (tester) async {
        tester.view.physicalSize = const Size(411 * 3, 2400 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              (_) async => Directory.systemTemp.path,
            );
        final c = (await tester.runAsync(
          () => as(null, 'merchant2@saba.app', 'saba12345', locale: locale),
        ))!;
        Future<void> settle() async {
          for (var i = 0; i < 12; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 150)),
            );
            await tester.pump(const Duration(milliseconds: 50));
          }
        }

        String texts() => [
          for (final w in tester.widgetList<Text>(
            find.byType(Text, skipOffstage: false),
          ))
            ?w.data,
        ].join(' | ');

        await tester.pumpWidget(
          UncontrolledProviderScope(container: c, child: const SabaApp()),
        );
        await settle();
        c.read(appRouterProvider).go(AppRoutes.merchantDashboard);
        await settle();
        print('7 $locale dashboard: ${texts()}');
        c.read(appRouterProvider).push(AppRoutes.merchantPayouts);
        await settle();
        print('7 $locale owe Saba: ${texts()}');
        await tester.runAsync(
          () => c.read(authControllerProvider.notifier).signOut(),
        );
        await tester.pumpWidget(const SizedBox());
        await settle();
      },
    );
  }
}
