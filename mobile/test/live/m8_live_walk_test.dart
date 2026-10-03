// M8 (BACKEND_PLAN.md 8.1): live updates from the real server. Skipped
// unless asked for:
//
//   flutter test test/live/m8_live_walk_test.dart \
//     --dart-define=LIVE=true --dart-define=USE_MOCK_DATA=false \
//     --dart-define=API_BASE_URL=http://localhost:3000/api/v1 \
//     --dart-define=PHASE=orders|web|long|restart
//
// Each account watched is its own app with the channel open, and does
// nothing itself; what it does is done by another app signed in as the
// same account. So all a watcher hears came from the server.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/config/app_config.dart';
import 'package:saba_marketplace/core/errors/failure.dart';
import 'package:saba_marketplace/core/errors/result.dart';
import 'package:saba_marketplace/core/network/live_updates.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/addresses/presentation/address_providers.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/cart/presentation/cart_providers.dart';
import 'package:saba_marketplace/features/checkout/presentation/checkout_providers.dart';
import 'package:saba_marketplace/features/merchant/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:saba_marketplace/features/messaging/presentation/messaging_providers.dart';
import 'package:saba_marketplace/features/notifications/presentation/live_channel_provider.dart';
import 'package:saba_marketplace/features/orders/domain/orders_repository.dart';
import 'package:saba_marketplace/features/orders/presentation/orders_providers.dart';
import 'package:saba_marketplace/features/support/presentation/support_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _live = bool.fromEnvironment('LIVE');
const _phase = String.fromEnvironment('PHASE', defaultValue: 'orders');
const _go = String.fromEnvironment('GO_DIR');
const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// One app: its own keys, its own announcements.
class _App {
  _App(this.name);
  final String name;
  final keys = <String, String>{};
  late ProviderContainer c;
  final heard = <String>[];
  DateTime? since;

  void mark() {
    heard.clear();
    since = DateTime.now();
  }

  int count(LiveTopic topic) => heard.where((h) => h == topic.name).length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The keys belong to the app whose call it is; the harness has one
  // keychain, so each app swaps its own in around its calls.
  _App? current;

  setUpAll(() {
    HttpOverrides.global = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_keystore, (call) async {
          final keys = current?.keys ?? <String, String>{};
          final key = call.arguments is Map ? call.arguments['key'] : null;
          switch (call.method) {
            case 'write':
              keys[key as String] = call.arguments['value'] as String? ?? '';
            case 'read':
              return keys[key as String];
            case 'delete':
              keys.remove(key as String);
            case 'readAll':
              return Map<String, String>.from(keys);
            case 'deleteAll':
              keys.clear();
          }
          return null;
        });
  });

  String say(Result<Object?> result) => result.fold(
    ok: (value) => 'OK',
    err: (Failure f) => 'ERR ${f.statusCode} "${f.message}"',
  );

  Future<_App> open(
    String name,
    String? phone,
    String? email,
    String password, {
    bool watch = false,
  }) async {
    final app = _App(name);
    current = app;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'saba.pref.onboarding_seen': true,
      'saba.pref.locale': 'en',
    });
    app.c = ProviderContainer(
      overrides: [
        appPreferencesProvider.overrideWithValue(await AppPreferences.create()),
      ],
      retry: (_, _) => null,
    );
    addTearDown(app.c.dispose);
    await app.c.read(authControllerProvider.future);
    final r = await app.c
        .read(authControllerProvider.notifier)
        .signIn(phone: phone, email: email, password: password);
    print('sign-in $name: ${say(r)}');
    if (watch) {
      app.c.read(liveUpdatesProvider).changes.listen((t) {
        app.heard.add(t.name);
        print(
          '   ${DateTime.now().toIso8601String().substring(11, 19)} $name heard ${t.name}',
        );
      });
      app.c.listen(liveChannelProvider, (_, _) {});
      await Future<void>.delayed(const Duration(seconds: 2));
      print(
        '$name channel open: ${app.c.read(liveChannelProvider)?.opened} time(s)',
      );
    }
    return app;
  }

  /// Runs [action] as [app], its keys in place.
  Future<T> as<T>(_App app, Future<T> Function(ProviderContainer c) action) {
    current = app;
    return action(app.c);
  }

  Future<void> settle([int seconds = 2]) =>
      Future<void>.delayed(Duration(seconds: seconds));

  String utc() => DateTime.now().toUtc().toIso8601String().substring(11, 19);

  void report(String step, _App app) {
    print(
      '$step [${utc()} UTC] ${app.name}: orders ${app.count(LiveTopic.orders)}, notifications ${app.count(LiveTopic.notifications)}',
    );
    app.mark();
  }

  Future<void> waitFor(String name) async {
    final file = File('$_go/$name');
    print('waiting for "$name" ...');
    while (!file.existsSync()) {
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    print('"$name" arrived');
  }

  test('M8 phase $_phase', skip: !_live, timeout: Timeout.none, () async {
    print('API ${AppConfig.apiBaseUrl} mock=${AppConfig.useMockData}');

    if (_phase == 'orders') {
      final amina = await open(
        'Amina (watching)',
        '+9647701234567',
        null,
        'saba12345',
        watch: true,
      );
      final store = await open(
        'M2 store (watching)',
        '+9647732172587',
        null,
        'walkpass123',
        watch: true,
      );
      // Amina acts from her own app: the server allows 10 sign-ins per phone
      // in 15 minutes. Her own writes are counted out with mark().
      final shopper = amina;
      final seller = await open(
        'M2 store (acting)',
        '+9647732172587',
        null,
        'walkpass123',
      );
      amina.mark();
      store.mark();

      Future<(String, String)> place(String step) => as(shopper, (c) async {
        await c
            .read(cartControllerProvider.notifier)
            .addItem(productId: '57', variantId: '66');
        final address =
            (await c.read(addressRepositoryProvider).fetchAddresses())
                .unwrap()
                .firstWhere((a) => a.isDefault);
        final flow = c.read(checkoutControllerProvider.notifier);
        await flow.selectAddress(address.id);
        final placed = (await flow.placeOrder()).unwrap();
        print('$step placed ${placed.orderNumber} [${utc()} UTC]');
        final part = await as(
          seller,
          (s) async =>
              (await s
                      .read(merchantRepositoryProvider)
                      .orders(status: 'PENDING'))
                  .unwrap()
                  .items
                  .firstWhere((r) => r.orderNumber == placed.orderNumber)
                  .id,
        );
        return (placed.orderId, part);
      });

      // 2. A new order: the store hears it by itself.
      final (orderId, part) = await place('2');
      await settle();
      report('2 new order', store);
      report('2 new order', amina);

      // 1. The store's steps: Amina hears each.
      amina.mark();
      for (final step in ['CONFIRMED', 'PROCESSING', 'SHIPPED', 'DELIVERED']) {
        final r = await as(
          seller,
          (s) => s
              .read(merchantRepositoryProvider)
              .updateOrderStatus(
                orderId: part,
                status: step,
                courier: step == 'SHIPPED'
                    ? const Courier(name: 'Ali Hassan', phone: '+9647701112222')
                    : null,
              ),
        );
        await settle();
        print('1 store $step: ${say(r)}');
        report('1 $step', amina);
        report('1 $step', store);
      }
      final seen = await as(
        amina,
        (c) async => (await c.read(orderDetailProvider(orderId).future)).status,
      );
      print('1 Amina\'s order now: ${seen.name}');

      // 2. Another, cancelled by her: the store hears it.
      final (second, _) = await place('2b');
      await settle();
      store.mark();
      amina.mark();
      final cancelled = await as(
        shopper,
        (c) => c
            .read(ordersRepositoryProvider)
            .cancelOrder(orderId: second, reason: 'CHANGED_MIND'),
      );
      await settle();
      print('2 cancel: ${say(cancelled)}');
      report('2 cancelled', store);
      amina.mark();

      // 3. A return: asked (the store hears), approved and refunded (Amina).
      final line = await as(
        shopper,
        (c) async =>
            (await c.read(ordersRepositoryProvider).fetchOrder(orderId))
                .unwrap()
                .items
                .first,
      );
      final asked = await as(
        shopper,
        (c) => c
            .read(ordersRepositoryProvider)
            .requestReturn(
              orderId: orderId,
              lines: [ReturnLine(orderItemId: line.id, quantity: 1)],
              reason: 'CHANGED_MIND',
            ),
      );
      await settle();
      print('3 return asked: ${say(asked)}');
      report('3 asked', store);
      amina.mark();
      final returnId = await as(
        seller,
        (s) async => (await s.read(merchantRepositoryProvider).order(part))
            .unwrap()
            .returns
            .single
            .id,
      );
      for (final answer in ['APPROVED', 'REFUNDED']) {
        final r = await as(
          seller,
          (s) =>
              s.read(merchantRepositoryProvider).answerReturn(returnId, answer),
        );
        await settle();
        print('3 store $answer: ${say(r)}');
        report('3 $answer', amina);
        report('3 $answer', store);
      }

      // 4. A chat message from Nova: Amina's bell.
      final nova = await open(
        'Nova (acting)',
        null,
        'merchant@saba.app',
        'saba12345',
      );
      final sent = await as(
        nova,
        (c) => c
            .read(messagingRepositoryProvider)
            .send(conversationId: '1', body: 'M8: a live message from Nova.'),
      );
      await settle();
      print('4 Nova writes: ${say(sent)}');
      report('4 chat', amina);
      report('4 chat', store);

      // For the web's W8: a ticket, and a second message in it.
      final ticket = await as(
        shopper,
        (c) => c
            .read(supportRepositoryProvider)
            .create(
              subject: 'M8 live: is my return refunded?',
              category: 'RETURN',
              description: 'The store refunded my return today. Is it done?',
            ),
      );
      print(
        'W8 ticket [${utc()} UTC]: ${say(ticket)} ${ticket.valueOrNull?.reference}',
      );
      await settle(3);
      final more = await as(
        shopper,
        (c) => c
            .read(supportRepositoryProvider)
            .reply(
              ticketId: ticket.valueOrNull!.id,
              body: 'A second message: the cash was handed back at the door.',
            ),
      );
      print('W8 second message [${utc()} UTC]: ${say(more)}');

      // 8. Another account in the same app: only its own changes.
      await as(amina, (c) => c.read(authControllerProvider.notifier).signOut());
      await settle(1);
      print('8 signed out: channel=${amina.c.read(liveChannelProvider)}');
      final walk = await as(
        amina,
        (c) => c
            .read(authControllerProvider.notifier)
            .signIn(phone: '+9647731006565', password: 'walkpass123'),
      );
      await settle();
      print(
        '8 Walk Shopper in the same app: ${say(walk)} channel opened ${amina.c.read(liveChannelProvider)?.opened}',
      );
      amina.mark();
      final again = await as(
        nova,
        (c) => c
            .read(messagingRepositoryProvider)
            .send(conversationId: '1', body: 'M8: this one is for Amina only.'),
      );
      await settle();
      print('8 Nova writes to Amina: ${say(again)}');
      report('8 Walk Shopper after a message to Amina', amina);
    }

    // 4, 5 and 9 with the web, one go-file at a time.
    if (_phase == 'web') {
      final amina = await open(
        'Amina (watching)',
        '+9647701234567',
        null,
        'saba12345',
        watch: true,
      );
      final store = await open(
        'M2 store (watching)',
        '+9647732172587',
        null,
        'walkpass123',
        watch: true,
      );
      final walk = await open(
        'Walk Shopper (watching)',
        '+9647731006565',
        null,
        'walkpass123',
        watch: true,
      );
      String status() =>
          '${store.c.read(currentUserProvider)?.merchant?.status.name}';
      print('5 store status at start: ${status()}');
      for (final a in [amina, store, walk]) {
        a.mark();
      }

      await waitFor('ticket');
      await settle(3);
      report('4 ticket answer', amina);

      await waitFor('suspended');
      await settle(4);
      report('5 suspended', store);
      print('5 store status: ${status()}');

      await waitFor('active');
      await settle(4);
      report('5 active again', store);
      print('5 store status: ${status()}');

      await waitFor('walk-suspended');
      await settle(4);
      final channel = walk.c.read(liveChannelProvider);
      print(
        '9 Walk Shopper: signed in=${walk.c.read(currentUserProvider) != null} '
        'channel=${channel == null ? 'closed' : 'open, ${channel.opened} time(s)'}',
      );
      report('9 suspended', walk);
    }

    // For the web: one more order from the M2 store, delivered.
    if (_phase == 'deliver1') {
      final amina = await open('Amina', '+9647701234567', null, 'saba12345');
      final seller = await open(
        'M2 store',
        '+9647732172587',
        null,
        'walkpass123',
      );
      final placed = await as(amina, (c) async {
        await c
            .read(cartControllerProvider.notifier)
            .addItem(productId: '57', variantId: '66');
        final address =
            (await c.read(addressRepositoryProvider).fetchAddresses())
                .unwrap()
                .firstWhere((a) => a.isDefault);
        final flow = c.read(checkoutControllerProvider.notifier);
        await flow.selectAddress(address.id);
        return (await flow.placeOrder()).unwrap();
      });
      print('placed ${placed.orderNumber} [${utc()} UTC]');
      final repo = seller.c.read(merchantRepositoryProvider);
      final part = (await as(seller, (_) => repo.orders(status: 'PENDING')))
          .unwrap()
          .items
          .firstWhere((r) => r.orderNumber == placed.orderNumber)
          .id;
      for (final step in ['CONFIRMED', 'PROCESSING', 'SHIPPED', 'DELIVERED']) {
        await settle(2);
        final r = await as(
          seller,
          (_) => repo.updateOrderStatus(
            orderId: part,
            status: step,
            courier: step == 'SHIPPED'
                ? const Courier(name: 'Ali Hassan', phone: '+9647701112222')
                : null,
          ),
        );
        print('$step: ${say(r)} [${utc()} UTC]');
      }
    }

    // 6. Past the access token's 15 minutes.
    if (_phase == 'long') {
      final amina = await open(
        'Amina (watching)',
        '+9647701234567',
        null,
        'saba12345',
        watch: true,
      );
      final nova = await open(
        'Nova (acting)',
        null,
        'merchant@saba.app',
        'saba12345',
      );
      print('6 waiting 16 minutes ...');
      await Future<void>.delayed(const Duration(minutes: 16));
      print(
        '6 channel opened ${amina.c.read(liveChannelProvider)?.opened} time(s)',
      );
      amina.mark();
      final sent = await as(
        nova,
        (c) => c
            .read(messagingRepositoryProvider)
            .send(conversationId: '1', body: 'M8: after the token ran out.'),
      );
      await settle();
      print('6 Nova writes: ${say(sent)}');
      report('6 after 16 minutes', amina);
    }

    // 7. The connection lost for 30 seconds and back (the server on :3001
    // stopped and started by the walk's runner).
    if (_phase == 'restart') {
      final amina = await open(
        'Amina (watching)',
        '+9647701234567',
        null,
        'saba12345',
        watch: true,
      );
      amina.mark();
      await waitFor('down');
      print('7 server down');
      await waitFor('up');
      await Future<void>.delayed(const Duration(seconds: 40));
      print(
        '7 channel opened ${amina.c.read(liveChannelProvider)?.opened} time(s)',
      );
      report('7 after the drop', amina);
    }
  });
}
