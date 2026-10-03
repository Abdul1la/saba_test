// M10 (BACKEND_PLAN.md §7, S10): the app's push registration against the
// real server, with a stand-in for Firebase. Skipped unless asked for:
//
//   flutter test test/live/m10_push_walk_test.dart \
//     --dart-define=LIVE=true --dart-define=USE_MOCK_DATA=false \
//     --dart-define=API_BASE_URL=http://localhost:3000/api/v1
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/config/api_endpoints.dart';
import 'package:saba_marketplace/core/errors/failure.dart';
import 'package:saba_marketplace/core/errors/result.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/push/push_service.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _live = bool.fromEnvironment('LIVE');
const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

class _Push implements PushService {
  @override
  Future<String?> token() async => 'm10-walk-token-amina';
  @override
  Stream<String> get tokenChanges => const Stream<String>.empty();
  @override
  Stream<PushTap> get taps => const Stream<PushTap>.empty();
  @override
  Future<void> askPermission() async {}
}

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

  test('M10 registration against the real server', skip: !_live, () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'saba.pref.onboarding_seen': true,
      'saba.pref.locale': 'en',
    });
    final c = ProviderContainer(
      overrides: [
        appPreferencesProvider.overrideWithValue(await AppPreferences.create()),
        pushServiceProvider.overrideWithValue(_Push()),
      ],
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);
    await c.read(authControllerProvider.future);
    print(
      'sign-in: ${say(await c.read(authControllerProvider.notifier).signIn(phone: '+9647701234567', password: 'saba12345'))}',
    );
    final client = c.read(apiClientProvider);

    // What the app sends, as the app sends it.
    final device = c.read(pushDeviceProvider);
    await device.register();
    print('register (the app\'s PushDevice): done');
    print(
      'PUT again, same token: ${say(await client.command(ApiEndpoints.devices, method: 'PUT', data: {'token': 'm10-walk-token-amina', 'platform': 'ANDROID', 'language': 'ar'}))}',
    );
    print(
      'PUT a bad platform: ${say(await client.command(ApiEndpoints.devices, method: 'PUT', data: {'token': 'm10-walk-token-amina', 'platform': 'WEB', 'language': 'en'}))}',
    );
    print(
      'PUT a token with a space: ${say(await client.command(ApiEndpoints.devices, method: 'PUT', data: {'token': 'has space', 'platform': 'IOS', 'language': 'en'}))}',
    );
    await device.forget();
    print('forget (the app\'s PushDevice): done');
    print(
      'DELETE again: ${say(await client.command(ApiEndpoints.devices, method: 'DELETE', data: {'token': 'm10-walk-token-amina'}))}',
    );
    await c.read(authControllerProvider.notifier).signOut();
    print('signed out: ${c.read(currentUserProvider) == null}');
  });
}
