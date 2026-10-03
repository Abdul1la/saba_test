// Chat photos against the real server (backend bdfea4f), with the app's own
// code: the shopper Amina sends a real photo to her chat with the M2 store,
// and the signed photoUrl is read back and fetched. Skipped unless asked for:
//
//   flutter test test/live/photo_walk_test.dart \
//     --dart-define=LIVE=true --dart-define=USE_MOCK_DATA=false \
//     --dart-define=API_BASE_URL=http://localhost:3000/api/v1
//
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/errors/failure.dart';
import 'package:saba_marketplace/core/errors/result.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/media/domain/entities.dart';
import 'package:saba_marketplace/features/messaging/presentation/messaging_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _live = bool.fromEnvironment('LIVE');
const _m2Store = '15';
const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

// A real 1x1 PNG, so the server's "is it an image?" check passes.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNk'
  '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

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
            case 'readAll':
              return Map<String, String>.from(store);
          }
          return null;
        });
  });

  String say(Result<Object?> result) => result.fold(
    ok: (_) => 'OK',
    err: (Failure f) => 'ERR ${f.statusCode} "${f.message}" ${f.fieldErrors}',
  );

  Future<MessagingRepository> signedIn() async {
    store.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'saba.pref.onboarding_seen': true,
      'saba.pref.locale': 'en',
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
            .signIn(phone: '+9647701234567', password: 'saba12345'))
        .unwrap();
    return c.read(messagingRepositoryProvider);
  }

  PickedMedia photo(Uint8List bytes, String mime, String name) => PickedMedia(
    fileName: name,
    sizeBytes: bytes.length,
    mimeType: mime,
    bytes: bytes,
  );

  /// Fetches [url] with no auth header, as the app loads a photo: the status
  /// and the content type.
  Future<(int, String?)> fetch(String url) async {
    final client = HttpClient();
    try {
      final response = await (await client.getUrl(Uri.parse(url))).close();
      await response.drain<void>();
      return (response.statusCode, response.headers.contentType?.mimeType);
    } finally {
      client.close();
    }
  }

  test('a photo sent to a chat comes back as a signed link', skip: !_live, () async {
    final shelf = await signedIn();

    // The chat with the M2 store: the one already there, or a new one.
    final chat = (await shelf.startWithStore(_m2Store)).unwrap();
    print('0 chat: ${chat.id} "${chat.title}"');

    // 1. A real photo: saved, body empty, a photoUrl handed back.
    final sent = await shelf.sendPhoto(
      conversationId: chat.id,
      photo: photo(_png, 'image/png', 'walk.png'),
    );
    print('1 sent: ${say(sent)}');
    if (sent case Ok<Message>(:final value)) {
      print(
        '1 message: isPhoto=${value.isPhoto} body="${value.body}" '
        'photoUrl=${value.photoUrl}',
      );
      final url = value.photoUrl;
      if (url != null) {
        print('1 url is https: ${url.startsWith('https://')}');
        final (status, type) = await fetch(url);
        print('1 fetch: HTTP $status, $type');
      }
    }

    // 2. Read the thread back: the newest message is the photo, and the
    // conversation card says so.
    final page = (await shelf.messages(chat.id)).unwrap();
    final newest = page.items.first;
    print(
      '2 thread newest: isPhoto=${newest.isPhoto} photoUrl=${newest.photoUrl}',
    );
    final card = (await shelf.conversation(chat.id)).unwrap();
    print(
      '2 card: lastMessageIsPhoto=${card.lastMessageIsPhoto} '
      'lastMessage=${card.lastMessage}',
    );

    // 3. Not an image: refused on the file, nothing saved.
    final bad = await shelf.sendPhoto(
      conversationId: chat.id,
      photo: photo(
        Uint8List.fromList(utf8.encode('this is not an image')),
        'text/plain',
        'notes.txt',
      ),
    );
    print('3 not an image: ${say(bad)}');
  });
}
