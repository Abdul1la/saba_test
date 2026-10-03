// M6, against the real server: "What you owe Saba" said "Paid" without the
// day Saba marked it, and a past month hid the cash handed back on returns,
// so Atlas's August read 1,005,000 in sales and 68,750 owed - not 8% of it.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/app.dart';
import 'package:saba_marketplace/core/errors/result.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/core/utils/formatters.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/merchant/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// Atlas's months as the real server sent them on 28 September.
final _bills = SabaBills(
  currencyCode: 'IQD',
  ratePercent: 8,
  current: SabaBill(
    month: DateTime(2026, 9),
    orderCount: 4,
    sales: 1270000,
    owed: 101500,
  ),
  past: [
    SabaBill(
      month: DateTime(2026, 8),
      orderCount: 4,
      sales: 1005000,
      returned: 145000,
      owed: 68750,
      isDue: true,
    ),
    SabaBill(
      month: DateTime(2026, 7),
      orderCount: 2,
      sales: 280000,
      owed: 22500,
      paidAt: DateTime.utc(2026, 8, 4, 9),
    ),
  ],
);

class _Atlas extends MerchantRepositoryImpl {
  const _Atlas(super.client);

  @override
  Future<Result<SabaBills>> bills() async => Result.ok(_bills);
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

  for (final locale in ['en', 'ar']) {
    testWidgets('a past month says when it was paid, and what came off '
        '($locale)', (tester) async {
      tester.view.physicalSize = const Size(411 * 3, 1400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'saba.pref.onboarding_seen': true,
        'saba.pref.locale': locale,
      });
      final preferences = await AppPreferences.create();
      final c = ProviderContainer(
        overrides: [
          appPreferencesProvider.overrideWithValue(preferences),
          merchantRepositoryProvider.overrideWith(
            (ref) => _Atlas(ref.watch(apiClientProvider)),
          ),
        ],
        retry: (_, _) => null,
      );
      addTearDown(c.dispose);
      await tester.runAsync(
        () => c
            .read(authControllerProvider.notifier)
            .signIn(email: 'merchant@saba.app', password: 'Password1'),
      );

      Future<void> settle() async {
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 120));
        }
      }

      await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const SabaApp()),
      );
      await settle();
      c.read(appRouterProvider).push(AppRoutes.merchantPayouts);
      await settle();

      final l10n = AppLocalizations(Locale(locale));
      final paidDay = Formatters.monthDay(
        DateTime.utc(2026, 8, 4, 9),
        locale: locale,
      );
      expect(find.text(l10n.billPaidOn(paidDay)), findsOneWidget);
      expect(find.text(l10n.billDue), findsOneWidget);
      expect(
        find.textContaining(
          Formatters.deduction(145000, locale: locale, currencyCode: 'IQD'),
        ),
        findsOneWidget,
        reason: "August's returned cash is not on its line",
      );
      expect(
        find.text(Formatters.monthYear(DateTime(2026, 8), locale: locale)),
        findsOneWidget,
      );
    });
  }
}
