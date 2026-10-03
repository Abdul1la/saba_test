// S10 and M10 (BACKEND_PLAN.md §7), the app's side, before Firebase is in:
// the phone's push address goes to the server for whoever is signed in, in
// the app's language; a tapped push opens what its notification opens; and
// sign-out takes the address back, so the next person on the phone does not
// get the last one's pushes.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/app.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/push/push_service.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

class _Push implements PushService {
  String current = 'tok-1';
  int asked = 0;
  final changes = StreamController<String>.broadcast();
  final tapped = StreamController<PushTap>.broadcast();

  @override
  Future<String?> token() async => current;

  @override
  Stream<String> get tokenChanges => changes.stream;

  @override
  Stream<PushTap> get taps => tapped.stream;

  @override
  Future<void> askPermission() async => asked++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = <String, String>{};

  setUp(() {
    store.clear();
    DioFactory.mockBackend.resetForTesting();
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
  tearDown(() => DioFactory.mockBackend.resetForTesting());

  Future<ProviderContainer> start(
    WidgetTester tester, {
    PushService? push,
  }) async {
    tester.view.physicalSize = const Size(411 * 3, 914 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'saba.pref.onboarding_seen': true,
      'saba.pref.locale': 'en',
    });
    final preferences = await AppPreferences.create();
    final c = ProviderContainer(
      overrides: [
        appPreferencesProvider.overrideWithValue(preferences),
        if (push != null) pushServiceProvider.overrideWithValue(push),
      ],
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: const SabaApp()),
    );
    return c;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Map<String, Map<String, dynamic>> addresses() =>
      DioFactory.mockBackend.pushAddresses;

  testWidgets('the phone is registered, follows the language, opens a tapped '
      'push, and is taken back at sign-out', (tester) async {
    final push = _Push();
    final c = await start(tester, push: push);
    await settle(tester);
    expect(addresses(), isEmpty, reason: 'registered before anyone signed in');

    await tester.runAsync(
      () => c
          .read(authControllerProvider.notifier)
          .signIn(email: 'shopper@saba.app', password: 'Password1'),
    );
    await settle(tester);
    final account = c.read(accountIdProvider);
    expect(push.asked, greaterThan(0), reason: 'never asked to show pushes');
    expect(addresses()['tok-1'], {
      'account': account,
      'platform': 'ANDROID',
      'language': 'en',
    });

    // The language changes: the pushes follow it.
    await tester.runAsync(
      () => c
          .read(localeControllerProvider.notifier)
          .setLocale(const Locale('ar')),
    );
    await settle(tester);
    expect(addresses()['tok-1']?['language'], 'ar');

    // The push service hands the phone a new address.
    push.current = 'tok-2';
    push.changes.add('tok-2');
    await settle(tester);
    expect(addresses()['tok-2']?['account'], account);

    // A tapped push opens what its notification opens.
    push.tapped.add(
      const PushTap(
        notificationId: 'n-1',
        targetType: 'TICKET',
        targetId: 't-1',
      ),
    );
    await settle(tester);
    expect(
      c.read(appRouterProvider).state.uri.path,
      '/support/t-1',
      reason: 'the tap opened nothing',
    );

    await tester.runAsync(
      () => c.read(authControllerProvider.notifier).signOut(),
    );
    await settle(tester);
    expect(
      addresses().containsKey('tok-2'),
      isFalse,
      reason: 'still pushing to the phone after sign-out',
    );
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets('without a push service nothing is sent', (tester) async {
    final c = await start(tester);
    await tester.runAsync(
      () => c
          .read(authControllerProvider.notifier)
          .signIn(email: 'shopper@saba.app', password: 'Password1'),
    );
    await settle(tester);
    expect(addresses(), isEmpty);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
}
