// Every form leaves room to type with the keyboard up, on the smallest phone.
//
// The store's sign-up pinned its step header above the fields and its button
// below them: on a 320x568 phone the fields scrolled in a window 64 px tall,
// and with the keyboard up in no window at all. A store owner on a small
// phone could not fill the form.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/widgets/app_text_field.dart';
import 'package:saba_marketplace/app.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// A small phone's keyboard, in logical pixels.
const double _keyboard = 260;

/// Room for a field and the error under it.
const double _room = 120;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final keys = <String, String>{};
  setUp(() {
    keys.clear();
    DioFactory.mockBackend.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          switch (call.method) {
            case 'write':
              keys[call.arguments['key'] as String] =
                  call.arguments['value'] as String? ?? '';
              return null;
            case 'read':
              return keys[call.arguments['key'] as String];
            case 'delete':
              keys.remove(call.arguments['key'] as String);
              return null;
            case 'readAll':
              return Map<String, String>.from(keys);
            case 'deleteAll':
              keys.clear();
              return null;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  /// Each form, and who opens it; null is signed out.
  // The sign-up forms open only with a verified number.
  final forms = <(String, String?)>[
    (
      AppRoutes.registerPath(
        merchant: false,
        phone: '+9647512223344',
        token: 'test-token',
      ),
      null,
    ),
    (
      AppRoutes.registerPath(
        merchant: true,
        phone: '+9647512223344',
        token: 'test-token',
      ),
      null,
    ),
    (AppRoutes.forgotPassword, null),
    (AppRoutes.login, null),
    (AppRoutes.addressForm, 'shopper@saba.app'),
    (AppRoutes.profile, 'shopper@saba.app'),
    (AppRoutes.newSupportTicket, 'shopper@saba.app'),
    (AppRoutes.merchantStoreSettings, 'merchant@saba.app'),
    (AppRoutes.merchantProductForm, 'merchant@saba.app'),
    (AppRoutes.merchantCouponForm, 'merchant@saba.app'),
  ];

  /// [route], opened by [account] on a 320 x 568 phone.
  Future<void> open(
    WidgetTester tester,
    String route,
    String? account, {
    String locale = 'en',
  }) async {
    tester.view.physicalSize = const Size(320 * 3, 568 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues(<String, Object>{
      'saba.pref.onboarding_seen': true,
      'saba.pref.locale': locale,
    });
    final preferences = await AppPreferences.create();
    final container = ProviderContainer(
      overrides: [appPreferencesProvider.overrideWithValue(preferences)],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    if (account != null) {
      await tester.runAsync(() async {
        (await container
                .read(authControllerProvider.notifier)
                .signIn(email: account, password: 'Password1'))
            .unwrap();
      });
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SabaApp()),
    );
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    container.read(appRouterProvider).go(route);
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  // The user: empty fields gave no idea what to type or in what form. Each
  // one now shows an example until something is typed, on both sides.
  for (final locale in ['en', 'ar']) {
    for (final (route, account) in forms) {
      testWidgets('$route shows an example in every empty field, $locale', (
        tester,
      ) async {
        await open(tester, route, account, locale: locale);
        final fields = tester.widgetList<TextField>(find.byType(TextField));
        expect(fields, isNotEmpty);
        for (final field in fields) {
          if (field.readOnly || (field.controller?.text ?? '').isNotEmpty) {
            continue;
          }
          expect(
            field.decoration?.hintText,
            isNotNull,
            reason: '$route: a field with no example',
          );
          expect(field.decoration!.hintText!.trim(), isNotEmpty);
        }
      });
    }
  }

  for (final (route, account) in forms) {
    testWidgets('$route leaves room to type with the keyboard up', (
      tester,
    ) async {
      await open(tester, route, account);

      tester.view.viewInsets = const FakeViewPadding(bottom: _keyboard * 3);
      addTearDown(tester.view.resetViewInsets);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }

      // The tallest window that scrolls up and down, less what the keyboard
      // covers.
      final above = Rect.fromLTRB(0, 0, 320, 568 - _keyboard);
      var window = 0.0;
      for (final element in find.byType(Scrollable).evaluate()) {
        final scrollable = element.widget as Scrollable;
        if (axisDirectionToAxis(scrollable.axisDirection) != Axis.vertical) {
          continue;
        }
        final seen = tester.getRect(find.byWidget(scrollable)).intersect(above);
        if (seen.height > window) window = seen.height;
      }
      expect(
        window,
        greaterThanOrEqualTo(_room),
        reason: '$route scrolls its fields in $window px with the keyboard up',
      );
    });
  }

  // The tester: the store's Stock box held a real "0", so 1,200 typed into
  // it read "01,200". Empty now, with its example.
  testWidgets('a new product starts with an empty stock box', (tester) async {
    await open(tester, AppRoutes.merchantProductForm, 'merchant@saba.app');
    final stock = tester.widget<TextField>(
      find.descendant(
        of: find.widgetWithText(AppTextField, 'Stock'),
        matching: find.byType(TextField),
      ),
    );
    expect(stock.controller?.text, isEmpty);
    expect(stock.decoration?.hintText, 'e.g. 12');
  });
}
