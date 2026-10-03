// A store owner deletes their account (BUGS 212; BACKEND_READY.md,
// "Deleting a store's account"), with the app's own code against the real
// server. Skipped unless asked for; run in two phases, the backend session
// running the hourly step (npm run housekeeping) between them:
//
//   flutter test test/live/store_deletion_walk_test.dart \
//     --dart-define=LIVE=true --dart-define=USE_MOCK_DATA=false \
//     --dart-define=API_BASE_URL=http://localhost:3000/api/v1 \
//     --dart-define=PHASE=ask|deleted \
//     [--dart-define=STORE_PHONE=+9647732xxxxxxx] \
//     [--dart-define=SMS_LOG=<a server's log> --dart-define=OTP_URL=<its API>]
//
// "ask" signs a new test store up unless STORE_PHONE names one: the code is
// asked for through OTP_URL, whose server writes it to SMS_LOG. A store with
// something left to finish stops it before any write. It leaves the deletion
// asked for, and the number and the phone's saved session in the system temp
// folder for "deleted".
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' as dio;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/config/api_endpoints.dart';
import 'package:saba_marketplace/core/config/app_config.dart';
import 'package:saba_marketplace/core/errors/failure.dart';
import 'package:saba_marketplace/core/errors/result.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/domain/entities.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/merchant/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _live = bool.fromEnvironment('LIVE');
const _phase = String.fromEnvironment('PHASE', defaultValue: 'ask');
const _storePhone = String.fromEnvironment('STORE_PHONE');
const _smsLog = String.fromEnvironment('SMS_LOG');
const _otpUrl = String.fromEnvironment('OTP_URL');
const _password = 'walkpass123';
const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = <String, String>{};
  var phone = _storePhone;
  final saved = File(
    '${Directory.systemTemp.path}/saba_store_deletion_walk.json',
  );

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

  /// The app opening, with whatever session the phone holds in [store].
  Future<ProviderContainer> app({String locale = 'en'}) async {
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

  String say(Result<Object?> result) => result.fold(
    ok: (value) => 'OK',
    err: (Failure f) =>
        'ERR ${f.runtimeType} ${f.statusCode} "${f.message}" ${f.fieldErrors}',
  );

  Future<(ProviderContainer, Result<Object?>)> signedIn({
    String locale = 'en',
  }) async {
    store.clear();
    final c = await app(locale: locale);
    final result = await c
        .read(authControllerProvider.notifier)
        .signIn(phone: phone, password: _password);
    return (c, result);
  }

  Future<String> codeFor(String phone) async {
    final pattern = RegExp('SMS code for ${RegExp.escape(phone)}: ([0-9]+)');
    for (var i = 0; i < 30; i++) {
      for (final line in File(_smsLog).readAsLinesSync().reversed) {
        if (pattern.firstMatch(line) case final match?) return match.group(1)!;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    fail('no code in the server log for $phone');
  }

  /// A new test store: waiting for approval, and it has never sold.
  Future<void> signUp() async {
    final stamp = DateTime.now().millisecondsSinceEpoch % 100000;
    phone = '+96477321${stamp.toString().padLeft(5, '0')}';
    final sent = await dio.Dio().post<dynamic>(
      '$_otpUrl${ApiEndpoints.sendOtp}',
      data: {'phone': phone, 'purpose': 'SIGN_UP'},
    );
    print('0 code asked: ${sent.statusCode}');
    store.clear();
    final c = await app();
    final token = await c
        .read(authRepositoryProvider)
        .verifyOtp(phone: phone, code: await codeFor(phone));
    print('0 code: ${say(token)}');
    final opened = await c
        .read(authControllerProvider.notifier)
        .registerMerchant(
          MerchantRegistration(
            fullName: 'Deletion Walk Owner',
            password: _password,
            phone: phone,
            storeName: 'Deletion Walk $stamp',
            businessType: 'INDIVIDUAL',
            phoneVerificationToken: token.valueOrNull,
            governorate: 'BAGHDAD',
          ),
        );
    print('0 sign-up: ${say(opened)} STORE_PHONE=$phone');
  }

  String state(StoreDeletion? d) => d == null
      ? '-'
      : 'requestedAt=${d.requestedAt?.toIso8601String()} '
            'openOrders=${d.openOrders} openReturns=${d.openReturns} '
            'returnsOpenUntil=${d.returnsOpenUntil} owed=${d.owed} '
            '${d.currencyCode}';

  bool nothingLeft(StoreDeletion d) =>
      d.openOrders == 0 &&
      d.openReturns == 0 &&
      d.returnsOpenUntil == null &&
      d.owed <= 0;

  Future<String> account(ProviderContainer c) async {
    final user = (await c.read(authControllerProvider.notifier).refreshUser())
        .valueOrNull;
    return '${user?.merchant?.storeName} ${user?.merchant?.status} '
        'deletionRequestedAt=${user?.merchant?.deletionRequestedAt}';
  }

  Future<String> isOpen(ProviderContainer c) async =>
      '${(await c.read(merchantRepositoryProvider).dashboard()).valueOrNull?.isOpen}';

  test(
    'store deletion, phase $_phase',
    skip: !_live,
    timeout: Timeout.none,
    () async {
      print('API ${AppConfig.apiBaseUrl} demo=${AppConfig.isDemoMode}');

      if (_phase == 'ask') {
        if (phone.isEmpty) await signUp();

        // 1. What is left, read before anything is written.
        final (c, signIn) = await signedIn();
        print('1 sign-in: ${say(signIn)}');
        if (signIn.isErr) return;
        final id = c.read(currentUserProvider)?.merchant?.id;
        print('1 account: ${await account(c)} id=$id');
        final shelf = c.read(merchantRepositoryProvider);
        final before = await shelf.deletion();
        print('1 state: ${say(before)} ${state(before.valueOrNull)}');
        final b = before.valueOrNull;
        if (b == null || b.requestedAt != null || !nothingLeft(b)) {
          print('1 STOP: asked already, or something is left to finish');
          return;
        }
        print('1 open: ${await isOpen(c)}');

        // 2. Asked: the store closes at once. Asked twice, the first day.
        final asked = await shelf.requestDeletion();
        print('2 ask: ${say(asked)} ${state(asked.valueOrNull)}');
        if (asked.isErr) return;
        final again = await shelf.requestDeletion();
        print(
          '2 ask again: ${say(again)} same day='
          '${again.valueOrNull?.requestedAt == asked.valueOrNull?.requestedAt}',
        );
        print('2 account: ${await account(c)}');
        print('2 open: ${await isOpen(c)}');

        // 3. The switch cannot open it, in either language.
        print('3 open (en): ${say(await shelf.setOpen(true))}');
        final (ar, arSignIn) = await signedIn(locale: 'ar');
        print('3 sign-in (ar): ${say(arSignIn)}');
        final shelfAr = ar.read(merchantRepositoryProvider);
        print('3 open (ar): ${say(await shelfAr.setOpen(true))}');
        print('3 open now: ${await isOpen(ar)}');

        // 4. Taken back: nothing asked, and still closed.
        print('4 keep: ${say(await shelfAr.cancelDeletion())}');
        print('4 state: ${state((await shelfAr.deletion()).valueOrNull)}');
        print('4 account: ${await account(ar)}');
        print('4 open: ${await isOpen(ar)}');

        // 5. The switch works again, and asking again closes it.
        final reopened = await shelfAr.setOpen(true);
        print('5 open: ${say(reopened)} now=${await isOpen(ar)}');
        if (reopened.isErr) return;
        final last = await shelfAr.requestDeletion();
        print('5 ask again: ${say(last)} ${state(last.valueOrNull)}');
        print('5 account: ${await account(ar)}');
        print('5 open: ${await isOpen(ar)}');

        saved.writeAsStringSync(
          jsonEncode({'phone': phone, 'store': id, 'keystore': store}),
        );
        print('ASKED: run the hourly step, then PHASE=deleted');
        return;
      }

      // 6. The phone still signed in opens the app: its session is over.
      final kept = jsonDecode(saved.readAsStringSync()) as Map<String, dynamic>;
      phone = kept['phone'] as String;
      store
        ..clear()
        ..addAll((kept['keystore'] as Map<String, dynamic>).cast());
      final c = await app();
      print(
        '6 opened: signedIn=${c.read(isAuthenticatedProvider)} '
        'user=${c.read(currentUserProvider)?.id}',
      );

      // 7. The number has no account now.
      final (_, signIn) = await signedIn();
      print('7 sign-in: ${say(signIn)}');

      // 8. The store's page is not there.
      final page = await c
          .read(apiClientProvider)
          .get<void>(
            ApiEndpoints.merchantStore('${kept['store']}'),
            decoder: (_) {},
          );
      print('8 store page: ${say(page)}');
    },
  );
}
