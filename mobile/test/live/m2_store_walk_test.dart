// M2 (BACKEND_PLAN.md 8.1): a store's own settings and its approval, with
// the app's own code against the real server. Skipped unless asked for; run
// in phases, the web answering the store between them:
//
//   flutter test test/live/m2_store_walk_test.dart \
//     --dart-define=LIVE=true --dart-define=USE_MOCK_DATA=false \
//     --dart-define=API_BASE_URL=http://localhost:3001/api/v1 \
//     --dart-define=SMS_LOG=<the server's log file> \
//     --dart-define=PHASE=waiting|approved|suspended \
//     [--dart-define=STORE_PHONE=+9647732xxxxxxx]
//
// "waiting" signs a new test store up (it prints its number) unless
// STORE_PHONE names one; the others need STORE_PHONE.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:dio/dio.dart' as dio;
import 'package:flutter/material.dart';
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
import 'package:saba_marketplace/features/home/presentation/home_providers.dart';
import 'package:saba_marketplace/features/media/data/media_repository_impl.dart';
import 'package:saba_marketplace/features/media/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:saba_marketplace/features/merchant/presentation/screens/merchant_store_settings_screen.dart';
import 'package:saba_marketplace/features/notifications/presentation/notifications_providers.dart';
import 'package:saba_marketplace/app.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _live = bool.fromEnvironment('LIVE');
const _smsLog = String.fromEnvironment('SMS_LOG');
const _phase = String.fromEnvironment('PHASE', defaultValue: 'waiting');
const _storePhone = String.fromEnvironment('STORE_PHONE');
const _password = 'walkpass123';
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

  Future<String> codeFor(String phone) async {
    for (var i = 0; i < 20; i++) {
      for (final line in File(_smsLog).readAsLinesSync().reversed) {
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

  Future<ProviderContainer> signedIn(
    String phone, {
    String locale = 'en',
  }) async {
    final c = await app(locale: locale);
    final result = await c
        .read(authControllerProvider.notifier)
        .signIn(phone: phone, password: _password);
    print('sign-in ($locale): ${say(result)}');
    return c;
  }

  void describe(ProviderContainer c, String label) {
    final user = c.read(currentUserProvider);
    print(
      '$label: ${user?.role} "${user?.merchant?.storeName}" '
      'status=${user?.merchant?.status} id=${user?.merchant?.id}',
    );
  }

  Future<Result<void>> saveSettings(
    ProviderContainer c,
    Map<String, dynamic> changes,
  ) async {
    final now = await c.read(storeSettingsProvider.future);
    return c
        .read(apiClientProvider)
        .command(
          ApiEndpoints.merchantStoreSettings,
          method: 'PUT',
          data: <String, dynamic>{
            'storeName': now.storeName,
            'description': ?now.description,
            'businessAddress': ?now.businessAddress,
            'logoUrl': now.logoUrl,
            'governorate': now.governorate?.apiValue,
            'delivery': ?now.delivery?.toJson(),
            ...changes,
          },
        );
  }

  Future<void> readBack(ProviderContainer c, String label) async {
    c.invalidate(storeSettingsProvider);
    final s = await c.read(storeSettingsProvider.future);
    print(
      '$label: name="${s.storeName}" desc="${s.description}" '
      'address="${s.businessAddress}" city=${s.governorate?.apiValue} '
      'logo=${s.logoUrl} delivery=${s.delivery?.toJson()}',
    );
  }

  Future<void> notifications(ProviderContainer c, String label) async {
    final inbox = await c.read(notificationsRepositoryProvider).fetch();
    for (final n in inbox.valueOrNull?.items ?? const []) {
      print(
        '$label notification: "${n.title}" / "${n.body}" '
        '-> ${n.targetType}:${n.targetId} read=${n.isRead}',
      );
    }
    if (inbox.isErr) print('$label notifications: ${say(inbox)}');
  }

  test('M2 phase $_phase', skip: !_live, timeout: Timeout.none, () async {
    print('API ${AppConfig.apiBaseUrl} mock=${AppConfig.useMockData}');
    var phone = _storePhone;

    if (_phase == 'waiting') {
      if (phone.isEmpty) {
        final stamp = DateTime.now().millisecondsSinceEpoch % 100000;
        phone = '+96477321${stamp.toString().padLeft(5, '0')}';
        final c = await app();
        final auth = c.read(authRepositoryProvider);
        print(
          'sendOtp: ${say(await auth.sendOtp(phone, purpose: OtpPurpose.signUp))}',
        );
        final token = await auth.verifyOtp(
          phone: phone,
          code: await codeFor(phone),
        );
        final opened = await c
            .read(authControllerProvider.notifier)
            .registerMerchant(
              MerchantRegistration(
                fullName: 'M2 Owner',
                password: _password,
                phone: phone,
                storeName: 'M2 Store $stamp',
                businessType: 'INDIVIDUAL',
                phoneVerificationToken: token.valueOrNull,
                governorate: 'BAGHDAD',
              ),
            );
        print('registerMerchant: ${say(opened)}');
      }
      print('STORE_PHONE=$phone');

      // 1. Signed in, waiting.
      var c = await signedIn(phone);
      describe(c, '1 store');
      final dashboard = await c.read(merchantRepositoryProvider).dashboard();
      print('1 dashboard: ${say(dashboard)}');

      // 2. Settings: saved, and still there after signing out and in.
      await readBack(c, '2 before');
      print(
        '2 save: ${say(await saveSettings(c, {
          'description': 'Phones and accessories, M2 walk.',
          'businessAddress': 'Karrada Inner St., near Babel Hotel',
          'governorate': 'BAGHDAD',
          'delivery': {
            'governorates': ['BAGHDAD', 'BASRA'],
            'feeInside': 3000,
            'timeInside': '1_2_DAYS',
            'feeOutside': 6000,
            'timeOutside': '3_5_DAYS',
          },
        }))}',
      );
      await c.read(authControllerProvider.notifier).signOut();
      c = await signedIn(phone);
      await readBack(c, '2 after sign-in');

      // Delivery terms.
      print(
        '2 fee 3,100: ${say(await saveSettings(c, {
          'delivery': {
            'governorates': ['BAGHDAD'],
            'feeInside': 3100,
            'timeInside': '1_2_DAYS',
          },
        }))}',
      );
      print(
        '2 own city left out: ${say(await saveSettings(c, {
          'delivery': {
            'governorates': ['BASRA'],
            'feeInside': 3000,
            'timeInside': '1_2_DAYS',
            'feeOutside': 6000,
            'timeOutside': '3_5_DAYS',
          },
        }))}',
      );
      await readBack(c, '2 after own city left out');
      print(
        '2 outside, no fee or time: ${say(await saveSettings(c, {
          'delivery': {
            'governorates': ['BAGHDAD', 'BASRA'],
            'feeInside': 3000,
            'timeInside': '1_2_DAYS',
          },
        }))}',
      );

      // Logo: uploaded, saved, seen, removed.
      final bytes = File(
        'assets/images/stores/atlas-banner.jpg',
      ).readAsBytesSync();
      final uploaded = await MediaRepositoryImpl(c.read(apiClientProvider))
          .upload(
            PickedMedia(
              fileName: 'logo.jpg',
              sizeBytes: bytes.length,
              mimeType: 'image/jpeg',
              bytes: bytes,
            ),
          );
      print('2 logo upload: ${say(uploaded)} url=${uploaded.valueOrNull?.url}');
      if (uploaded.valueOrNull case final logo?) {
        print(
          '2 logo save: ${say(await saveSettings(c, {'logoUrl': logo.url}))}',
        );
        await readBack(c, '2 with logo');
        try {
          final got = await dio.Dio().get<List<int>>(
            logo.url,
            options: dio.Options(responseType: dio.ResponseType.bytes),
          );
          print('2 logo served: ${got.statusCode} ${got.data?.length} bytes');
        } on Object catch (e) {
          print('2 logo served: FAILED $e');
        }
        print(
          '2 logo removed: ${say(await saveSettings(c, {'logoUrl': null}))}',
        );
        await readBack(c, '2 without logo');
      }
      final big = List<int>.filled(6 * 1024 * 1024, 0);
      final tooBig = await MediaRepositoryImpl(c.read(apiClientProvider))
          .upload(
            PickedMedia(
              fileName: 'big.jpg',
              sizeBytes: big.length,
              mimeType: 'image/jpeg',
              bytes: Uint8List.fromList(big),
            ),
          );
      print('2 logo over 5 MB: ${say(tooBig)}');

      // Store name.
      print(
        '2 name of 41: ${say(await saveSettings(c, {'storeName': 'S' * 41}))}',
      );
      print(
        '2 name taken in the city: '
        '${say(await saveSettings(c, {'storeName': 'Nova Electronics'}))}',
      );

      // 3. Closed and open again.
      final shelf = c.read(merchantRepositoryProvider);
      print('3 close: ${say(await shelf.setOpen(false))}');
      print('3 open again: ${say(await shelf.setOpen(true))}');
      print(
        '3 dashboard open: ${(await shelf.dashboard()).valueOrNull?.isOpen}',
      );

      // 8. In Arabic.
      final ar = await signedIn(phone, locale: 'ar');
      print(
        '8 ar fee 3,100: ${say(await saveSettings(ar, {
          'delivery': {
            'governorates': ['BAGHDAD'],
            'feeInside': 3100,
            'timeInside': '1_2_DAYS',
          },
        }))}',
      );
      print(
        '8 ar name taken: '
        '${say(await saveSettings(ar, {'storeName': 'Nova Electronics'}))}',
      );
      return;
    }

    expect(phone, isNotEmpty, reason: 'STORE_PHONE is needed after waiting');
    final c = await signedIn(phone);
    describe(c, '$_phase store');
    await notifications(c, _phase);
    final ar = await signedIn(phone, locale: 'ar');
    await notifications(ar, '$_phase ar');

    if (_phase == 'approved') {
      // 5. As a shopper: the store's page and its city among the chips.
      final id = c.read(currentUserProvider)?.merchant?.id ?? '';
      final shopper = await app();
      print(
        '5 shopper sign-in: ${say(await shopper.read(authControllerProvider.notifier).signIn(phone: '+9647701234567', password: 'saba12345'))}',
      );
      final page = await shopper
          .read(apiClientProvider)
          .get<Map<String, dynamic>>(
            ApiEndpoints.merchantStore(id),
            decoder: (e) => e.dataAsMap,
          );
      print('5 public page: ${say(page)} ${page.valueOrNull}');
      final cities = await shopper.read(storeCitiesProvider.future);
      print('5 city chips: ${[for (final city in cities) city.apiValue]}');
    }
  });

  // What a suspended store's owner sees: the dashboard and the account.
  testWidgets(
    'M2 suspended: the owner sees it on the dashboard and the account',
    skip: !_live || _phase != 'suspended',
    (tester) async {
      tester.view.physicalSize = const Size(411 * 3, 914 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => Directory.systemTemp.path,
          );
      final c = (await tester.runAsync(() => signedIn(_storePhone)))!;
      Future<void> settle() async {
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 150)),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const SabaApp()),
      );
      await settle();
      for (final route in [
        AppRoutes.merchantDashboard,
        AppRoutes.merchantAccount,
      ]) {
        c.read(appRouterProvider).go(route);
        await settle();
        print(
          '$route: "Suspended" shown ${find.text('Suspended').evaluate().length}x, '
          'open switch ${find.byType(Switch).evaluate().length}, '
          'error ${tester.takeException()}',
        );
      }
      await tester.runAsync(
        () => c.read(authControllerProvider.notifier).signOut(),
      );
      await tester.pumpWidget(const SizedBox());
      await settle();
    },
  );
}
