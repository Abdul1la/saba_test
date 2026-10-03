// Report and block (the reviewer's item 3; backend 426336e), with the app's
// own code against the real server: Amina, and the M2 test store (store 15,
// its product 57). Skipped unless asked for:
//
//   flutter test test/live/report_block_walk_test.dart \
//     --dart-define=LIVE=true --dart-define=USE_MOCK_DATA=false \
//     --dart-define=API_BASE_URL=http://localhost:3000/api/v1
//
// It leaves their chat unblocked, with one more message in it, and Saba
// three reports marked "report walk".
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/config/api_endpoints.dart';
import 'package:saba_marketplace/core/errors/failure.dart';
import 'package:saba_marketplace/core/errors/result.dart';
import 'package:saba_marketplace/core/network/api_client.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/messaging/presentation/messaging_providers.dart';
import 'package:saba_marketplace/features/reviews/domain/entities.dart';
import 'package:saba_marketplace/features/reviews/presentation/widgets/report_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _live = bool.fromEnvironment('LIVE');
const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _why = ReportChoice(
  reason: ReportReason.misleading,
  description: 'report walk',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // One keystore per account: each container is its own phone.
  final phones = <String, Map<String, String>>{};
  var current = '';

  setUpAll(() {
    HttpOverrides.global = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_keystore, (call) async {
          final store = phones.putIfAbsent(current, () => {});
          final key = call.arguments is Map ? call.arguments['key'] : null;
          switch (call.method) {
            case 'write':
              store[key as String] = call.arguments['value'] as String? ?? '';
            case 'read':
              return store[key as String];
            case 'readAll':
              return Map<String, String>.from(store);
          }
          return null;
        });
  });

  Future<ProviderContainer> signedIn(
    String phone,
    String password, {
    String locale = 'en',
  }) async {
    current = '$phone/$locale';
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
    (await c
            .read(authControllerProvider.notifier)
            .signIn(phone: phone, password: password))
        .unwrap();
    return c;
  }

  String say(Result<Object?> result) => result.fold(
    ok: (value) => value is Conversation
        ? 'OK blocked=${value.blocked} byMe=${value.blockedByMe}'
        : 'OK',
    err: (Failure f) => 'ERR ${f.statusCode} "${f.message}"',
  );

  test('report and block', skip: !_live, timeout: Timeout.none, () async {
    final amina = await signedIn('+9647701234567', 'saba12345');
    final aminaAr = await signedIn('+9647701234567', 'saba12345', locale: 'ar');
    final seller = await signedIn('+9647732172587', 'walkpass123');
    // Each call runs as its own phone.
    Future<T> as<T>(ProviderContainer c, String who, Future<T> Function() f) {
      current = who;
      return f();
    }

    const a = '+9647701234567/en';
    const aAr = '+9647701234567/ar';
    const s = '+9647732172587/en';
    final aClient = amina.read(apiClientProvider);
    final sClient = seller.read(apiClientProvider);

    // 1. What a shopper sees: kept once, and a repeat is fine.
    Future<String> report(
      (ProviderContainer, String, ApiClient) phone,
      ReportTarget target,
      String id,
    ) async {
      final (c, who, client) = phone;
      return say(
        await as(
          c,
          who,
          () => sendReport(client, target: target, id: id, choice: _why),
        ),
      );
    }

    final shopper = (amina, a, aClient);
    final store = (seller, s, sClient);
    print('1 product 57: ${await report(shopper, ReportTarget.product, '57')}');
    print('1 again: ${await report(shopper, ReportTarget.product, '57')}');
    print('1 store 15: ${await report(shopper, ReportTarget.store, '15')}');
    print(
      '1 no such product: '
      '${await report(shopper, ReportTarget.product, '999999')}',
    );
    final badReason = await as(
      amina,
      a,
      () => aClient.command(
        ApiEndpoints.reports,
        data: const {'targetType': 'PRODUCT', 'targetId': '57', 'reason': 'NO'},
      ),
    );
    print('1 no such reason: ${say(badReason)}');

    // 2. Never one's own.
    print('2 own product: ${await report(store, ReportTarget.product, '57')}');
    print('2 own store: ${await report(store, ReportTarget.store, '15')}');

    // 3. The chat, reported.
    final aChats = amina.read(messagingRepositoryProvider);
    final sChats = seller.read(messagingRepositoryProvider);
    final started = await as(amina, a, () => aChats.startWithStore('15'));
    print('3 chat: ${say(started)} id=${started.valueOrNull?.id}');
    final chat = started.valueOrNull?.id;
    if (chat == null) return;
    final hello = await as(
      amina,
      a,
      () => aChats.send(conversationId: chat, body: 'report walk: hello'),
    );
    print('3 hello: ${say(hello)}');
    print(
      '3 report: ${await report(shopper, ReportTarget.conversation, chat)}',
    );

    try {
      // 4. Amina blocks: nobody writes; the store's view is not its block.
      final blocked = await as(
        amina,
        a,
        () => aChats.setBlocked(chat, blocked: true),
      );
      print('4 Amina blocks: ${say(blocked)}');
      if (blocked.isErr) return;
      print(
        '4 store sees: ${say(await as(seller, s, () => sChats.conversation(chat)))}',
      );
      print(
        '4 store writes: '
        '${say(await as(seller, s, () => sChats.send(conversationId: chat, body: 'report walk: blocked?')))}',
      );
      final aminaArChats = aminaAr.read(messagingRepositoryProvider);
      print(
        '4 Amina writes (ar): '
        '${say(await as(aminaAr, aAr, () => aminaArChats.send(conversationId: chat, body: 'report walk: blocked?')))}',
      );

      // 5. Each side lifts only its own.
      print(
        '5 store unblocks (not its block): '
        '${say(await as(seller, s, () => sChats.setBlocked(chat, blocked: false)))}',
      );
      print(
        '5 store blocks too: '
        '${say(await as(seller, s, () => sChats.setBlocked(chat, blocked: true)))}',
      );
      print(
        '5 Amina unblocks: '
        '${say(await as(amina, a, () => aChats.setBlocked(chat, blocked: false)))}',
      );
      print(
        '5 store unblocks: '
        '${say(await as(seller, s, () => sChats.setBlocked(chat, blocked: false)))}',
      );
      print(
        '5 Amina writes: '
        '${say(await as(amina, a, () => aChats.send(conversationId: chat, body: 'report walk: open again')))}',
      );
    } finally {
      // Never left blocked, whatever happened above.
      await as(amina, a, () => aChats.setBlocked(chat, blocked: false));
      await as(seller, s, () => sChats.setBlocked(chat, blocked: false));
      print('end: ${say(await as(amina, a, () => aChats.conversation(chat)))}');
    }
  });
}
