// M5 (BACKEND_PLAN.md 8.1): returns, and a suspended shopper, with the app's
// own code against the real server. Skipped unless asked for:
//
//   flutter test test/live/m5_returns_walk_test.dart \
//     --dart-define=LIVE=true --dart-define=USE_MOCK_DATA=false \
//     --dart-define=API_BASE_URL=http://localhost:3000/api/v1 \
//     --dart-define=PHASE=returns|before|suspended|unsuspended
//
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/config/app_config.dart';
import 'package:saba_marketplace/core/errors/failure.dart';
import 'package:saba_marketplace/core/errors/result.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:saba_marketplace/features/notifications/presentation/notifications_providers.dart';
import 'package:saba_marketplace/features/orders/domain/entities.dart';
import 'package:saba_marketplace/features/orders/domain/orders_repository.dart';
import 'package:saba_marketplace/features/orders/presentation/orders_providers.dart';
import 'package:saba_marketplace/features/returns/presentation/returns_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _live = bool.fromEnvironment('LIVE');
const _phase = String.fromEnvironment('PHASE', defaultValue: 'returns');
const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _walkShopper = '+9647731006565';
const _walkPassword = 'walkpass123';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = <String, String>{};
  final saved = File('${Directory.systemTemp.path}/saba_m5_session.json');

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

  Future<ProviderContainer> app({
    String locale = 'en',
    Map<String, String> keys = const {},
  }) async {
    store
      ..clear()
      ..addAll(keys);
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
    return c;
  }

  Future<ProviderContainer> as(
    String? phone,
    String? email,
    String password, {
    String locale = 'en',
  }) async {
    final c = await app(locale: locale);
    final r = await c
        .read(authControllerProvider.notifier)
        .signIn(phone: phone, email: email, password: password);
    print('sign-in ${phone ?? email} ($locale): ${say(r)}');
    return c;
  }

  Future<ProviderContainer> asAmina({String locale = 'en'}) =>
      as('+9647701234567', null, 'saba12345', locale: locale);
  Future<ProviderContainer> asStoreA({String locale = 'en'}) =>
      as('+9647732172587', null, 'walkpass123', locale: locale);
  Future<ProviderContainer> asNova({String locale = 'en'}) =>
      as(null, 'merchant@saba.app', 'saba12345', locale: locale);

  Future<void> inbox(ProviderContainer c, String label, {int count = 1}) async {
    final list = await c.read(notificationsRepositoryProvider).fetch();
    for (final n in (list.valueOrNull?.items ?? const []).take(count)) {
      print(
        '$label: "${n.title}" / "${n.body}" -> ${n.targetType}:${n.targetId}',
      );
    }
  }

  /// A product's stock as its store's Inventory shows it, every row.
  Future<String> stockOf(ProviderContainer c, String productId) async {
    final repo = c.read(merchantRepositoryProvider);
    final found = <String>[];
    for (var page = 1; page < 20; page++) {
      final list = (await repo.inventory(page: page)).valueOrNull;
      if (list == null) break;
      for (final r in list.items.where((r) => r.productId == productId)) {
        found.add('${r.variantLabel ?? r.name}:${r.available}');
      }
      if (!list.hasNextPage) break;
    }
    return '$found';
  }

  test('M5 phase $_phase', skip: !_live, timeout: Timeout.none, () async {
    print('API ${AppConfig.apiBaseUrl} mock=${AppConfig.useMockData}');

    if (_phase == 'returns') {
      final amina = await asAmina();
      final orders = amina.read(ordersRepositoryProvider);
      final all = (await orders.fetchOrders()).unwrap().items;
      String idOf(String number) =>
          all.firstWhere((o) => o.orderNumber == number).id;
      Future<Order> order(String number) async =>
          (await orders.fetchOrder(idOf(number))).unwrap();

      // 1. SB-100166's lines, each returnable, at what was paid for it.
      final delivered = await order('SB-100166');
      print(
        '1 SB-100166 ${delivered.status.name}: ${[for (final i in delivered.items) '${i.id} ${i.merchantName}: ${i.productName} list=${i.unitPrice} paid=${i.paidUnitPrice} canReturn=${i.canReturn}']}',
      );
      final headphones = delivered.items.firstWhere(
        (i) => i.productName.contains('Headphones'),
      );
      final charger = delivered.items.firstWhere(
        (i) => i.productName.contains('Charger'),
      );
      final phone = delivered.items.firstWhere(
        (i) => i.productName.contains('M3 Phone'),
      );
      final nova = await asNova();
      final storeA = await asStoreA();
      print('1 headphones stock before: ${await stockOf(nova, '5')}');
      print('1 M3 Phone stock before: ${await stockOf(storeA, '57')}');

      Future<Result<void>> ask(
        List<OrderItem> items,
        String reason, {
        String number = 'SB-100166',
        int quantity = 1,
        String? words,
        OrdersRepository? repo,
      }) => (repo ?? orders).requestReturn(
        orderId: idOf(number),
        lines: [
          for (final i in items)
            ReturnLine(orderItemId: i.id, quantity: quantity),
        ],
        reason: reason,
        description: words,
      );

      // 2's refusals that must not open anything.
      print(
        '2 two stores in one: ${say(await ask([phone, charger], 'DAMAGED'))}',
      );
      print(
        '2 two chargers (1 bought): ${say(await ask([charger], 'DAMAGED', quantity: 2))}',
      );
      print(
        '2 words over 1,000: ${say(await ask([charger], 'DAMAGED', words: 'x' * 1001))}',
      );
      print('2 an unknown reason: ${say(await ask([charger], 'BROKEN'))}');

      print(
        '1 return headphones: ${say(await ask([headphones], 'DAMAGED', words: 'The left side makes no sound.'))}',
      );
      final returns = amina.read(returnsRepositoryProvider);
      final first = (await returns.fetchReturns()).unwrap().items.first;
      final firstPage = (await returns.fetchReturn(first.id)).unwrap();
      print(
        '1 return ${first.id}: ${firstPage.status.name} ${firstPage.merchantName} reason=${firstPage.reason} '
        'refund=${first.refundAmount} items=${[for (final i in firstPage.items) '${i.name} x${i.quantity} ${i.refundAmount}']}',
      );
      await inbox(await asNova(), '1 Nova');

      // 2. Once per line; nothing to return on what never arrived.
      print('2 headphones again: ${say(await ask([headphones], 'DAMAGED'))}');
      for (final number in ['SB-100168', 'SB-100169', 'SB-100170']) {
        final o = await order(number);
        print(
          '2 $number ${o.status.name}: canReturn=${[for (final i in o.items) i.canReturn]} '
          'ask: ${say(await ask(o.items, 'CHANGED_MIND', number: number))}',
        );
      }

      // 3. Nova answers; the stock comes back only when the cash does.
      final novaRepo = (await asNova()).read(merchantRepositoryProvider);
      print(
        '3 refunded before approving: ${say(await novaRepo.answerReturn(first.id, 'REFUNDED'))}',
      );
      print(
        '3 approve: ${say(await novaRepo.answerReturn(first.id, 'APPROVED'))}',
      );
      await inbox(await asAmina(), '3 Amina');
      print(
        '3 headphones stock approved: ${await stockOf(await asNova(), '5')}',
      );
      final novaAgain = (await asNova()).read(merchantRepositoryProvider);
      print(
        '3 reject after approving: ${say(await novaAgain.answerReturn(first.id, 'REJECTED', reason: 'USED'))}',
      );
      print(
        '3 cash handed back: ${say(await novaAgain.answerReturn(first.id, 'REFUNDED'))}',
      );
      print(
        '3 refunded twice: ${say(await novaAgain.answerReturn(first.id, 'REFUNDED'))}',
      );
      print(
        '3 headphones stock refunded: ${await stockOf(await asNova(), '5')}',
      );
      final aminaNow = await asAmina();
      await inbox(aminaNow, '3 Amina');
      final done =
          (await aminaNow.read(returnsRepositoryProvider).fetchReturn(first.id))
              .unwrap();
      print(
        '3 return page: ${done.status.name} refund=${done.refund?.amount} ${done.refund?.status.name}',
      );

      // 4. Declined by store A, with a reason from the list.
      final amina4 = await asAmina();
      final orders4 = amina4.read(ordersRepositoryProvider);
      print(
        '4 return M3 Phone: ${say(await ask([phone], 'NOT_AS_DESCRIBED', words: 'The colour is not the white shown.', repo: orders4))}',
      );
      final second =
          (await amina4.read(returnsRepositoryProvider).fetchReturns())
              .unwrap()
              .items
              .first;
      final a = (await asStoreA()).read(merchantRepositoryProvider);
      print(
        '4 decline with no reason: ${say(await a.answerReturn(second.id, 'REJECTED'))}',
      );
      print(
        '4 decline USED: ${say(await a.answerReturn(second.id, 'REJECTED', reason: 'USED'))}',
      );
      print(
        '4 refund after declining: ${say(await a.answerReturn(second.id, 'REFUNDED'))}',
      );
      print('4 M3 Phone stock after: ${await stockOf(await asStoreA(), '57')}');
      final amina5 = await asAmina();
      await inbox(amina5, '4 Amina');
      print(
        '4 M3 Phone again: ${say(await ask([phone], 'DAMAGED', repo: amina5.read(ordersRepositoryProvider)))}',
      );
      final after =
          (await amina5
                  .read(ordersRepositoryProvider)
                  .fetchOrder(idOf('SB-100166')))
              .unwrap();
      print(
        '4 SB-100166 canReturn now: ${[for (final i in after.items) '${i.productName}:${i.canReturn}']}',
      );

      // 5. Amina's returns, newest first, each with its steps and refund.
      final list = (await amina5.read(returnsRepositoryProvider).fetchReturns())
          .unwrap()
          .items;
      for (final r in list) {
        final page =
            (await amina5.read(returnsRepositoryProvider).fetchReturn(r.id))
                .unwrap();
        print(
          '5 ${r.id} ${r.orderNumber} ${r.status.name} at ${r.requestedAt.toLocal()} refund=${r.refundAmount} '
          'steps=${[for (final t in page.timeline) t.status.name]} why=${page.rejectionReason}',
        );
      }

      // 7. Ahmed: every delivery more than 7 days old.
      final ahmed = await as('+9647705550211', null, 'saba12345');
      final his = ahmed.read(ordersRepositoryProvider);
      for (final o in (await his.fetchOrders()).unwrap().items) {
        final full = (await his.fetchOrder(o.id)).unwrap();
        print(
          '7 ${o.orderNumber} ${o.status.name} ${o.placedAt.toLocal()}: canReturn=${[for (final i in full.items) i.canReturn]}',
        );
        if (o.status == OrderStatus.delivered) {
          print(
            '7 ask ${o.orderNumber}: ${say(await his.requestReturn(
              orderId: o.id,
              lines: [ReturnLine(orderItemId: full.items.first.id, quantity: 1)],
              reason: 'CHANGED_MIND',
            ))}',
          );
        }
      }

      // 8. In Arabic.
      final ar = await asAmina(locale: 'ar');
      await inbox(ar, '8 ar Amina', count: 4);
      print(
        '8 ar headphones again: ${say(await ar.read(ordersRepositoryProvider).requestReturn(
          orderId: idOf('SB-100166'),
          lines: [ReturnLine(orderItemId: headphones.id, quantity: 1)],
          reason: 'DAMAGED',
        ))}',
      );
      final arPage =
          (await ar.read(returnsRepositoryProvider).fetchReturn(second.id))
              .unwrap();
      print(
        '8 ar declined page: ${arPage.status.name} why=${arPage.rejectionReason} store=${arPage.merchantName}',
      );
      await inbox(await asNova(locale: 'ar'), '8 ar Nova');
      final arStore = (await asStoreA(
        locale: 'ar',
      )).read(merchantRepositoryProvider);
      print(
        '8 ar refund after declining: ${say(await arStore.answerReturn(second.id, 'REFUNDED'))}',
      );
    }

    // 6. Suspension, in two halves: a session saved before the web
    // suspends the shopper, and what it and a new sign-in meet after.
    if (_phase == 'before') {
      final c = await as(_walkShopper, null, _walkPassword);
      print('6 signed in: ${c.read(currentUserProvider)?.fullName}');
      saved.writeAsStringSync(jsonEncode(store));
      print('6 session kept: ${store.keys.toList()}');
    }
    if (_phase == 'suspended' || _phase == 'unsuspended') {
      final keys = saved.existsSync()
          ? Map<String, String>.from(
              jsonDecode(saved.readAsStringSync()) as Map,
            )
          : <String, String>{};
      final kept = await app(keys: keys);
      print(
        '6 $_phase kept session: user=${kept.read(currentUserProvider)?.fullName}',
      );
      final r = await kept.read(ordersRepositoryProvider).fetchOrders();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      print(
        '6 $_phase its next request: ${say(r)} -> signed in=${kept.read(currentUserProvider) != null}',
      );
      for (final locale in ['en', 'ar']) {
        final c = await app(locale: locale);
        final signIn = await c
            .read(authControllerProvider.notifier)
            .signIn(phone: _walkShopper, password: _walkPassword);
        print('6 $_phase sign-in ($locale): ${say(signIn)}');
      }
    }
  });
}
