// M9, against the real server: a coupon refused on its usage limit ("at
// least 1", "not below its uses") saved nothing and said nothing - the
// limit box showed no server words, and a refusal on a field skips the
// message. Now the limit and minimum boxes show them, and a refusal on a
// field the form draws no box for is said in a message.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/app.dart';
import 'package:saba_marketplace/core/errors/failure.dart';
import 'package:saba_marketplace/core/errors/result.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/merchant/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _en = AppLocalizations(Locale('en'));

/// The demo server, except that saving a coupon is refused on [field].
class _Refusing extends MerchantRepositoryImpl {
  const _Refusing(super.client, this.field, this.message);

  final String field;
  final String message;

  @override
  Future<Result<void>> saveCoupon(MerchantCoupon coupon) async => Result.err(
    ValidationFailure(
      message: 'Check the highlighted fields.',
      fieldErrors: [FieldError(field: field, message: message)],
    ),
  );
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
            case 'readAll':
              return Map<String, String>.from(store);
          }
          return null;
        });
  });
  tearDown(() => DioFactory.mockBackend.resetForTesting());

  for (final (field, message) in [
    ('usageLimit', 'It has been used 3 times: the limit cannot be lower.'),
    ('discountType', 'Choose an amount or a percentage.'),
  ]) {
    testWidgets('a refusal on $field is said', (tester) async {
      tester.view.physicalSize = const Size(411 * 3, 1400 * 3);
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
          merchantRepositoryProvider.overrideWith(
            (ref) => _Refusing(ref.watch(apiClientProvider), field, message),
          ),
        ],
        retry: (_, _) => null,
      );
      addTearDown(c.dispose);
      late MerchantCoupon coupon;
      await tester.runAsync(() async {
        (await c
                .read(authControllerProvider.notifier)
                .signIn(email: 'merchant@saba.app', password: 'Password1'))
            .unwrap();
        coupon = (await c.read(merchantRepositoryProvider).coupons())
            .unwrap()
            .first;
      });

      Future<void> settle() async {
        for (var i = 0; i < 16; i++) {
          await tester.pump(const Duration(milliseconds: 120));
        }
      }

      await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const SabaApp()),
      );
      await settle();
      c
          .read(appRouterProvider)
          .push(AppRoutes.merchantCouponForm, extra: coupon);
      await settle();

      final save = find.text(_en.save);
      await tester.ensureVisible(save.last);
      await tester.pump();
      await tester.tap(save.last);
      await settle();

      expect(find.text(message), findsOneWidget, reason: 'refused in silence');
    });
  }
}
