// M1 (BACKEND_PLAN.md 8.1): the app's own account code against the real
// server. Skipped unless asked for:
//
//   flutter test test/live/m1_accounts_walk_test.dart \
//     --dart-define=LIVE=true --dart-define=USE_MOCK_DATA=false \
//     --dart-define=API_BASE_URL=http://localhost:3001/api/v1 \
//     --dart-define=SMS_LOG=<the server's log file>
//
// The server prints SMS codes to its log; SMS_LOG is where this reads them.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/config/app_config.dart';
import 'package:saba_marketplace/core/errors/failure.dart';
import 'package:saba_marketplace/core/errors/result.dart';
import 'package:saba_marketplace/core/location/governorate.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/addresses/domain/entities.dart';
import 'package:saba_marketplace/features/addresses/presentation/address_providers.dart';
import 'package:saba_marketplace/features/auth/domain/entities.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _live = bool.fromEnvironment('LIVE');
const _smsLog = String.fromEnvironment('SMS_LOG');
const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = <String, String>{};

  setUpAll(() {
    // A widget test answers every request with 400; this one talks to the
    // real server.
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

  Future<ProviderContainer> app({String locale = 'en'}) async {
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
    return c;
  }

  /// The newest code the server printed for [phone].
  Future<String> codeFor(String phone) async {
    for (var i = 0; i < 20; i++) {
      final lines = File(_smsLog).readAsLinesSync().reversed;
      for (final line in lines) {
        final match = RegExp(
          'SMS code for ${RegExp.escape(phone)}: (\\d+)',
        ).firstMatch(line);
        if (match != null) return match.group(1)!;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    fail('no code in the server log for $phone');
  }

  String say(Result<Object?> result) => result.fold(
    ok: (value) => 'OK',
    err: (Failure f) =>
        'ERR ${f.runtimeType} ${f.statusCode} "${f.message}" ${f.fieldErrors}',
  );

  // A number no demo account uses, new each run.
  final stamp = DateTime.now().millisecondsSinceEpoch % 100000;
  final shopperPhone = '+96477310${stamp.toString().padLeft(5, '0')}';
  final storePhone = '+96477320${stamp.toString().padLeft(5, '0')}';

  test('M1: accounts, against the real server', skip: !_live, timeout: Timeout.none, () async {
    print('API ${AppConfig.apiBaseUrl} mock=${AppConfig.useMockData}');

    // 1. Sign up as a shopper.
    var c = await app();
    final auth = c.read(authRepositoryProvider);
    final sent = await auth.sendOtp(shopperPhone, purpose: OtpPurpose.signUp);
    print('1 sendOtp: ${say(sent)}');
    final code = await codeFor(shopperPhone);
    final token = await auth.verifyOtp(phone: shopperPhone, code: code);
    print('1 verifyOtp: ${say(token)}');
    final signedUp = await c
        .read(authControllerProvider.notifier)
        .registerCustomer(
          CustomerRegistration(
            fullName: 'Walk Shopper',
            password: 'walkpass123',
            phone: shopperPhone,
            phoneVerificationToken: token.valueOrNull,
            governorate: 'BAGHDAD',
          ),
        );
    print('1 register: ${say(signedUp)}');
    print(
      '1 signed in: ${c.read(isAuthenticatedProvider)} '
      '${c.read(currentUserProvider)?.fullName} '
      '${c.read(currentUserProvider)?.role}',
    );

    // 2. That number again at sign-up.
    final again = await auth.sendOtp(shopperPhone, purpose: OtpPurpose.signUp);
    print('2 sendOtp again: ${say(again)}');

    // 3. Sign out, in; a wrong password; an unknown number.
    await c.read(authControllerProvider.notifier).signOut();
    print('3 signed out: ${!c.read(isAuthenticatedProvider)}');
    final notify = c.read(authControllerProvider.notifier);
    print(
      '3 wrong password: '
      '${say(await notify.signIn(phone: shopperPhone, password: 'wrongpass1'))}',
    );
    print(
      '3 unknown number: '
      '${say(await notify.signIn(phone: '+9647739999999', password: 'walkpass123'))}',
    );
    print(
      '3 right password: '
      '${say(await notify.signIn(phone: shopperPhone, password: 'walkpass123'))}',
    );

    // 4. Forgot password - a minute after the sign-up code, the server's
    // wait between two codes for one number.
    await notify.signOut();
    await Future<void>.delayed(const Duration(seconds: 61));
    final reset = await auth.sendOtp(
      shopperPhone,
      purpose: OtpPurpose.passwordReset,
    );
    print('4 reset sendOtp: ${say(reset)}');
    if (reset.isOk) {
      final resetCode = await codeFor(shopperPhone);
      print(
        '4 resetPassword: ${say(await auth.resetPassword(phone: shopperPhone, code: resetCode, password: 'newpass456'))}',
      );
      print(
        '4 old password: '
        '${say(await notify.signIn(phone: shopperPhone, password: 'walkpass123'))}',
      );
      print(
        '4 new password: '
        '${say(await notify.signIn(phone: shopperPhone, password: 'newpass456'))}',
      );
    }

    // 5. Edit profile, kept after signing out and in.
    final edited = await notify.updateProfile(
      fullName: 'Walk Shopper Edited',
      governorate: 'ERBIL',
    );
    print('5 updateProfile: ${say(edited)}');
    await notify.signOut();
    await notify.signIn(phone: shopperPhone, password: 'newpass456');
    final me = c.read(currentUserProvider);
    print('5 after sign-in: ${me?.fullName} ${me?.governorate}');

    // 6. Addresses.
    final addresses = c.read(addressRepositoryProvider);
    Address draft(String area, {String phone = '+9647701234567'}) => Address(
      id: '',
      fullName: 'Walk Shopper',
      phone: phone,
      governorate: Governorate.baghdad,
      area: area,
      landmark: 'Near the mosque',
    );
    final first = await addresses.create(draft('Karrada'));
    print('6 first: ${say(first)} default=${first.valueOrNull?.isDefault}');
    final second = await addresses.create(draft('Mansour'));
    print('6 second: ${say(second)} default=${second.valueOrNull?.isDefault}');
    if (second.valueOrNull case final two?) {
      print('6 setDefault: ${say(await addresses.setDefault(two.id))}');
      final list = (await addresses.fetchAddresses()).valueOrNull ?? const [];
      print(
        '6 list: ${[for (final a in list) '${a.area}${a.isDefault ? '*' : ''}']}',
      );
      final edit = await addresses.update(
        Address(
          id: two.id,
          fullName: two.fullName,
          phone: two.phone,
          governorate: two.governorate,
          area: 'Mansour Street 14',
          landmark: two.landmark,
          isDefault: two.isDefault,
        ),
      );
      print('6 edit: ${say(edit)} area=${edit.valueOrNull?.area}');
    }
    if (first.valueOrNull case final one?) {
      print('6 delete: ${say(await addresses.delete(one.id))}');
    }
    print('6 blank area: ${say(await addresses.create(draft('')))}');
    final blankLandmark = await addresses.create(
      Address(
        id: '',
        fullName: 'Walk Shopper',
        phone: '+9647701234567',
        governorate: Governorate.baghdad,
        area: 'Karrada',
        landmark: '',
      ),
    );
    print('6 blank landmark: ${say(blankLandmark)}');
    print(
      '6 not a mobile: ${say(await addresses.create(draft('Karrada', phone: '+9641234567')))}',
    );

    // 9 (here, on a signed-in account): the server's words in Arabic.
    final ar = await app(locale: 'ar');
    final arNotify = ar.read(authControllerProvider.notifier);
    print(
      '9 ar wrong password: '
      '${say(await arNotify.signIn(phone: shopperPhone, password: 'wrongpass1'))}',
    );
    print(
      '9 ar unknown number: '
      '${say(await arNotify.signIn(phone: '+9647739999999', password: 'walkpass123'))}',
    );
    print(
      '9 ar register refused field: ${say(await ar.read(authRepositoryProvider).registerCustomer(CustomerRegistration(fullName: '', password: 'x', phone: shopperPhone)))}',
    );

    // Too many tries, in Arabic: a number of its own, so no real one is
    // locked for 15 minutes.
    final locked = '+96477330${stamp.toString().padLeft(5, '0')}';
    Result<Object?> last = const Result.ok(null);
    for (var i = 0; i < 12; i++) {
      last = await arNotify.signIn(phone: locked, password: 'wrongpass1');
    }
    print('9 ar too many tries: ${say(last)}');

    // 7. Delete the account; the number signs up again.
    print('7 delete: ${say(await notify.deleteAccount())}');
    print('7 signed out: ${!c.read(isAuthenticatedProvider)}');
    c = await app();
    await Future<void>.delayed(const Duration(seconds: 61));
    print(
      '7 signUp code again: '
      '${say(await c.read(authRepositoryProvider).sendOtp(shopperPhone, purpose: OtpPurpose.signUp))}',
    );

    // 8. A store.
    final s = await app();
    final sAuth = s.read(authRepositoryProvider);
    print(
      '8 sendOtp: ${say(await sAuth.sendOtp(storePhone, purpose: OtpPurpose.signUp))}',
    );
    final sToken = await sAuth.verifyOtp(
      phone: storePhone,
      code: await codeFor(storePhone),
    );
    print('8 verifyOtp: ${say(sToken)}');
    final opened = await s
        .read(authControllerProvider.notifier)
        .registerMerchant(
          MerchantRegistration(
            fullName: 'Walk Owner',
            password: 'walkpass123',
            phone: storePhone,
            storeName: 'Walk Store $stamp',
            businessType: 'INDIVIDUAL',
            phoneVerificationToken: sToken.valueOrNull,
            governorate: 'BAGHDAD',
          ),
        );
    print('8 registerMerchant: ${say(opened)}');
    final owner = s.read(currentUserProvider);
    print(
      '8 store: ${owner?.role} ${owner?.merchant?.storeName} '
      '${owner?.merchant?.status}',
    );
  });
}
