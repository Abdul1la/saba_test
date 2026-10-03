// M7 (BACKEND_PLAN.md 8.1): chats and support tickets, with the app's own
// code against the real server. Skipped unless asked for:
//
//   flutter test test/live/m7_chats_walk_test.dart \
//     --dart-define=LIVE=true --dart-define=USE_MOCK_DATA=false \
//     --dart-define=API_BASE_URL=http://localhost:3000/api/v1 \
//     --dart-define=PHASE=chats|tickets|answered|waiting|closed|reopened
//
// ignore_for_file: avoid_print
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
import 'package:saba_marketplace/features/messaging/presentation/messaging_providers.dart';
import 'package:saba_marketplace/features/notifications/presentation/notifications_providers.dart';
import 'package:saba_marketplace/features/support/presentation/support_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _live = bool.fromEnvironment('LIVE');
const _phase = String.fromEnvironment('PHASE', defaultValue: 'chats');
const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _m2Store = '15';

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

  // One sign-in per account and language for a whole run: the server takes
  // 10 sign-ins per phone in 15 minutes, and a walk that signed in at every
  // step met "Too many tries" half way.
  final signedIn = <String, ProviderContainer>{};

  Future<ProviderContainer> as(
    String? phone,
    String? email,
    String password, {
    String locale = 'en',
  }) async {
    final key = '${phone ?? email}|$locale';
    if (signedIn[key] case final c?) return c;
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
    print('sign-in ${phone ?? email} ($locale): ${say(r)}');
    if (r.isOk) signedIn[key] = c;
    return c;
  }

  Future<ProviderContainer> asAmina({String locale = 'en'}) =>
      as('+9647701234567', null, 'saba12345', locale: locale);
  Future<ProviderContainer> asNova({String locale = 'en'}) =>
      as(null, 'merchant@saba.app', 'saba12345', locale: locale);
  Future<ProviderContainer> asStoreA({String locale = 'en'}) =>
      as('+9647732172587', null, 'walkpass123', locale: locale);

  Future<void> inbox(ProviderContainer c, String label, {int count = 1}) async {
    final list = await c.read(notificationsRepositoryProvider).fetch();
    for (final n in (list.valueOrNull?.items ?? const []).take(count)) {
      print(
        '$label: "${n.title}" / "${n.body}" (${n.body.length}) -> ${n.targetType}:${n.targetId}',
      );
    }
  }

  Future<List<Conversation>> chats(ProviderContainer c, String label) async {
    final list = (await c.read(messagingRepositoryProvider).conversations())
        .unwrap();
    print(
      '$label chats: ${[for (final x in list) '${x.id} "${x.title}" unread=${x.unreadCount} at ${x.updatedAt.toLocal()} last="${x.lastMessage}"']}',
    );
    return list;
  }

  Future<String> thread(ProviderContainer c, String id) async {
    final page = (await c.read(messagingRepositoryProvider).messages(id))
        .unwrap();
    return '${[for (final m in page.items.take(4)) '${m.isMine ? 'me' : 'them'}: ${m.body.length > 40 ? '${m.body.substring(0, 40)}...' : m.body}']}';
  }

  /// The newest ticket whose subject has [words], with its messages.
  Future<SupportTicket?> ticketOf(
    ProviderContainer c,
    String label,
    String words,
  ) async {
    final repo = c.read(supportRepositoryProvider);
    final mine = (await repo.tickets()).unwrap();
    final t = mine.where((x) => x.subject.contains(words)).firstOrNull;
    if (t == null) {
      print(
        '$label: no ticket "$words" in ${[for (final x in mine) x.subject]}',
      );
      return null;
    }
    final full = (await repo.ticket(t.id)).unwrap();
    final messages = (await repo.messages(t.id)).unwrap();
    print(
      '$label ticket ${full.reference} (${full.id}) ${full.status.name} "${full.subject}" '
      '${full.category}: ${[for (final m in messages) '${m.isFromCustomer ? 'me' : 'Saba(${m.authorName})'}: ${m.body}']}',
    );
    return full;
  }

  test('M7 phase $_phase', skip: !_live, timeout: Timeout.none, () async {
    print('API ${AppConfig.apiBaseUrl} mock=${AppConfig.useMockData}');

    if (_phase == 'chats') {
      // 1. Amina's chats, newest first; opening Nova's clears only hers.
      final amina = await asAmina();
      final mine = await chats(amina, '1 Amina');
      final withNova = mine.firstWhere((x) => x.title.contains('Nova'));
      final nova = await asNova();
      final novaSide = await chats(nova, '1 Nova before');
      print('1 Nova thread: ${await thread(amina, withNova.id)}');
      final a2 = await asAmina();
      print(
        '1 Amina opens it: ${say(await a2.read(messagingRepositoryProvider).markRead(withNova.id))}',
      );
      await chats(a2, '1 Amina after');
      final novaAfter = await chats(await asNova(), '1 Nova after');
      print(
        '1 Nova side unchanged: ${novaSide.firstWhere((x) => x.id == withNova.id).unreadCount} -> '
        '${novaAfter.firstWhere((x) => x.id == withNova.id).unreadCount}',
      );
      final send = a2.read(messagingRepositoryProvider);
      print(
        '1 empty: ${say(await send.send(conversationId: withNova.id, body: '   '))}',
      );
      print(
        '1 2,001 characters: ${say(await send.send(conversationId: withNova.id, body: 'x' * 2001))}',
      );
      const long =
          'Hello Nova, is the Kite Audio Studio Headphones black one back in '
          'stock, and can it come to Karrada by Thursday?';
      print(
        '1 write (${long.length} characters): ${say(await send.send(conversationId: withNova.id, body: long))}',
      );
      await chats(await asAmina(), '1 Amina after writing');

      // 2. Nova sees it, is told, and replies.
      final n2 = await asNova();
      await chats(n2, '2 Nova');
      await inbox(n2, '2 Nova');
      print(
        '2 Nova replies: ${say(await n2.read(messagingRepositoryProvider).send(conversationId: withNova.id, body: 'Yes, the black one is back. We deliver in Karrada within 1 to 2 days.'))}',
      );
      final a3 = await asAmina();
      await inbox(a3, '2 Amina');
      await chats(a3, '2 Amina');
      print('2 Amina thread: ${await thread(a3, withNova.id)}');

      // Only its two sides open it.
      final other = (await asStoreA()).read(messagingRepositoryProvider);
      print(
        '2 M2 store opens Amina-Nova: ${say(await other.messages(withNova.id))} / ${say(await other.send(conversationId: withNova.id, body: 'hi'))}',
      );

      // 3. "Message the store" on M2 Store's page.
      final a4 = await asAmina();
      final repo = a4.read(messagingRepositoryProvider);
      print(
        '3 a store that is not there: ${say(await repo.startWithStore('99999'))}',
      );
      final started = await repo.startWithStore(_m2Store);
      final chat = started.unwrap();
      print('3 start: ${say(started)} ${chat.id} "${chat.title}"');
      final again = await repo.startWithStore(_m2Store);
      print(
        '3 again: ${again.valueOrNull?.id == chat.id ? 'the same chat' : 'ANOTHER ${again.valueOrNull?.id}'}',
      );
      final listed = await chats(a4, '3 Amina before writing');
      print(
        '3 listed before writing: ${listed.any((x) => x.id == chat.id) ? 'LISTED' : 'not listed'}',
      );
      print(
        '3 write: ${say(await repo.send(conversationId: chat.id, body: 'Hello, does the M3 Phone come in black again soon?'))}',
      );
      final m2 = await asStoreA();
      await chats(m2, '3 M2 store');
      await inbox(m2, '3 M2 store');
      print(
        '3 M2 replies: ${say(await m2.read(messagingRepositoryProvider).send(conversationId: chat.id, body: 'Black is coming next week. We will let you know.'))}',
      );
      final a5 = await asAmina();
      await inbox(a5, '3 Amina');
      print('3 Amina thread: ${await thread(a5, chat.id)}');

      // 9. In Arabic.
      await inbox(await asNova(locale: 'ar'), '9 ar Nova');
      await inbox(await asAmina(locale: 'ar'), '9 ar Amina', count: 2);
      final ar = (await asAmina(
        locale: 'ar',
      )).read(messagingRepositoryProvider);
      print(
        '9 ar 2,001 characters: ${say(await ar.send(conversationId: chat.id, body: 'x' * 2001))}',
      );
    }

    if (_phase == 'tickets') {
      // 4. Amina's ticket, after its refusals; the M2 store's own.
      final amina = await asAmina();
      final repo = amina.read(supportRepositoryProvider);
      print(
        '4 subject of 3: ${say(await repo.create(subject: 'M7x', category: 'ORDER', description: 'My parcel came with a scratch on it.'))}',
      );
      print(
        '4 description of 9: ${say(await repo.create(subject: 'M7 Scratched phone', category: 'ORDER', description: 'Scratched'))}',
      );
      print(
        '4 unknown category: ${say(await repo.create(subject: 'M7 Scratched phone', category: 'BILLING', description: 'My parcel came with a scratch on it.'))}',
      );
      final ar = (await asAmina(locale: 'ar')).read(supportRepositoryProvider);
      print(
        '9 ar subject of 3: ${say(await ar.create(subject: 'M7x', category: 'ORDER', description: 'My parcel came with a scratch on it.'))}',
      );
      final had = (await repo.tickets()).unwrap().where(
        (t) => t.subject.contains('M7 Amina'),
      );
      final made = had.isNotEmpty
          ? Result<SupportTicket>.ok(had.first)
          : await repo.create(
              subject: 'M7 Amina: the headphones box was open',
              category: 'DELIVERY',
              description:
                  'Order SB-100166 arrived with the headphones box already open. Is that normal?',
            );
      print(
        '4 Amina opens: ${say(made)} ${made.valueOrNull?.reference} ${made.valueOrNull?.id}',
      );
      await ticketOf(await asAmina(), '4 Amina', 'M7 Amina');
      final m2 = (await asStoreA()).read(supportRepositoryProvider);
      final storeMade = await m2.create(
        subject: 'M7 M2 Store: when is my bill due?',
        category: 'PAYMENT',
        description:
            'When do I pay Saba for September, and how do I hand the cash over?',
      );
      print(
        '4 M2 store opens: ${say(storeMade)} ${storeMade.valueOrNull?.reference} ${storeMade.valueOrNull?.id}',
      );
      await ticketOf(await asStoreA(), '4 M2 store', 'M7 M2 Store');
      print(
        '4 Amina sees the store\'s: ${(await repo.tickets()).unwrap().any((t) => t.subject.contains('M7 M2 Store')) ? 'YES' : 'no'}',
      );
    }

    // 5 and 8. Saba's answers.
    if (_phase == 'answered') {
      final amina = await asAmina();
      await inbox(amina, '5 Amina', count: 2);
      await ticketOf(amina, '5 Amina', 'M7 Amina');
      final m2 = await asStoreA();
      await inbox(m2, '8 M2 store', count: 2);
      await ticketOf(m2, '8 M2 store', 'M7 M2 Store');
      await inbox(await asAmina(locale: 'ar'), '9 ar Amina', count: 2);
    }

    // 6. Waiting for her: told in words; her answer opens it again.
    if (_phase == 'waiting') {
      final amina = await asAmina();
      await inbox(amina, '6 Amina', count: 2);
      final t = await ticketOf(amina, '6 Amina', 'M7 Amina');
      print(
        '6 reply over 2,000: ${say(await amina.read(supportRepositoryProvider).reply(ticketId: t!.id, body: 'x' * 2001))}',
      );
      print(
        '6 answer: ${say(await amina.read(supportRepositoryProvider).reply(ticketId: t.id, body: 'Nothing was missing, it was only open. Thank you.'))}',
      );
      await ticketOf(await asAmina(), '6 Amina after', 'M7 Amina');
      await inbox(await asAmina(locale: 'ar'), '9 ar Amina', count: 1);
    }

    // 7. Closed: told, and her reply refused; opened again: it goes.
    if (_phase == 'closed' || _phase == 'reopened') {
      final amina = await asAmina();
      await inbox(amina, '7 $_phase Amina', count: 2);
      final t = await ticketOf(amina, '7 $_phase Amina', 'M7 Amina');
      print(
        '7 $_phase reply: ${say(await amina.read(supportRepositoryProvider).reply(ticketId: t!.id, body: 'One more question about the box.'))}',
      );
      if (_phase == 'closed') {
        final ar = (await asAmina(
          locale: 'ar',
        )).read(supportRepositoryProvider);
        print(
          '9 ar closed reply: ${say(await ar.reply(ticketId: t.id, body: 'One more question about the box.'))}',
        );
        await inbox(await asAmina(locale: 'ar'), '9 ar Amina', count: 1);
      }
      await ticketOf(await asAmina(), '7 $_phase Amina after', 'M7 Amina');
    }
  });
}
