// Signing up with a number that already had an account took the account
// over: "Omar Second" signed up on Ali First's number, sign-in opened Omar,
// and Ali's account could not be reached again. No step said a word.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/errors/failure.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/domain/entities.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = <String, String>{};

  setUp(() {
    DioFactory.mockBackend.resetForTesting();
    store.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
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

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    DioFactory.mockBackend.resetForTesting();
  });

  const number = '+9647509990001';

  test('a number with an account is refused, and the account stays', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final c = ProviderContainer(
      overrides: [
        appPreferencesProvider.overrideWithValue(await AppPreferences.create()),
      ],
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);
    await c.read(authControllerProvider.future);
    final auth = c.read(authControllerProvider.notifier);
    final repo = c.read(authRepositoryProvider);

    (await auth.registerCustomer(
      const CustomerRegistration(
        fullName: 'Ali First',
        password: 'Demo1234!',
        phone: number,
      ),
    )).unwrap();
    await auth.signOut();

    // The number step says so, before any code is sent.
    final code = await repo.sendOtp(number, purpose: OtpPurpose.signUp);
    expect(code.isErr, isTrue, reason: 'a code was sent to sign up again');
    code.fold(ok: (_) {}, err: (f) => expect(f, isA<ConflictFailure>()));
    // Signing in is still a code away: only sign-up is refused.
    expect((await repo.sendOtp(number)).isOk, isTrue);

    // Past the number step, the account is still not overwritten.
    final second = await auth.registerCustomer(
      const CustomerRegistration(
        fullName: 'Omar Second',
        password: 'Demo1234!',
        phone: number,
      ),
    );
    expect(second.isErr, isTrue, reason: 'the account was taken over');

    final back = (await auth.signIn(
      phone: number,
      password: 'Demo1234!',
    )).unwrap();
    expect(back.fullName, 'Ali First');

    // A demo account's number is taken too; a new number is not.
    expect(
      (await repo.sendOtp('+9647701234567', purpose: OtpPurpose.signUp)).isErr,
      isTrue,
    );
    expect(
      (await repo.sendOtp('+9647509990002', purpose: OtpPurpose.signUp)).isOk,
      isTrue,
    );
  });

  // BUGS.md 122: a forgotten password, by the code sent to the number.
  test('a password is reset only with the code, for an account', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final c = ProviderContainer(
      overrides: [
        appPreferencesProvider.overrideWithValue(await AppPreferences.create()),
      ],
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);
    await c.read(authControllerProvider.future);
    final repo = c.read(authRepositoryProvider);

    // No account on this number: nothing to reset, and no code sent.
    expect(
      (await repo.sendOtp(
        '+9647509990099',
        purpose: OtpPurpose.passwordReset,
      )).isErr,
      isTrue,
    );

    const phone = '+9647701234567';
    final code = (await repo.sendOtp(
      phone,
      purpose: OtpPurpose.passwordReset,
    )).unwrap().demoCode!;
    final wrong = code == '000000' ? '111111' : '000000';
    expect(
      (await repo.resetPassword(
        phone: phone,
        code: wrong,
        password: 'long enough',
      )).isErr,
      isTrue,
      reason: 'a reset without the code',
    );
    expect(
      (await repo.resetPassword(
        phone: phone,
        code: code,
        password: 'short',
      )).isErr,
      isTrue,
    );
    expect(
      (await repo.resetPassword(
        phone: phone,
        code: code,
        password: 'long enough',
      )).isOk,
      isTrue,
    );
  });

  // BUGS.md 108: a hand-edited link with the number written 0751... or
  // "+964 751 ..." made a second account where +964751... was refused. One
  // number, however it is written.
  test('one number, however it is written, is one account', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final c = ProviderContainer(
      overrides: [
        appPreferencesProvider.overrideWithValue(await AppPreferences.create()),
      ],
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);
    await c.read(authControllerProvider.future);
    final auth = c.read(authControllerProvider.notifier);
    final repo = c.read(authRepositoryProvider);

    (await auth.registerCustomer(
      const CustomerRegistration(
        fullName: 'Ali First',
        password: 'Demo1234!',
        phone: number,
      ),
    )).unwrap();
    await auth.signOut();

    const ways = [
      '07509990001',
      '0750 999 0001',
      '+964 750 999 0001',
      '9647509990001',
      '009647509990001',
      '٠٧٥٠٩٩٩٠٠٠١',
    ];
    for (final way in ways) {
      expect(
        (await repo.sendOtp(way, purpose: OtpPurpose.signUp)).isErr,
        isTrue,
        reason: '$way got a sign-up code',
      );
      expect(
        (await auth.registerCustomer(
          CustomerRegistration(
            fullName: 'Omar Second',
            password: 'Demo1234!',
            phone: way,
          ),
        )).isErr,
        isTrue,
        reason: '$way made a second account',
      );
      final back = (await auth.signIn(
        phone: way,
        password: 'Demo1234!',
      )).unwrap();
      expect(back.fullName, 'Ali First', reason: 'signed in by $way');
      await auth.signOut();
    }

    // A forgotten password, asked for with the number's 0.
    final code = (await repo.sendOtp(
      '07509990001',
      purpose: OtpPurpose.passwordReset,
    )).unwrap().demoCode!;
    expect(
      (await repo.resetPassword(
        phone: '+964 750 999 0001',
        code: code,
        password: 'long enough',
      )).isOk,
      isTrue,
    );
  });
}
