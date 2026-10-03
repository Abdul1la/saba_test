import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/features/merchant/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:saba_marketplace/features/merchant/presentation/screens/merchant_payouts_screen.dart';

const _en = AppLocalizations(Locale('en'));

void main() {
  // A month with nothing owed read "Due": the demo sends DUE for every past
  // month, and a backend may send NONE. The amount decides, not the status.
  testWidgets('a past month with nothing owed says so, not "Due"', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(411 * 3, 914 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sabaBillsProvider.overrideWith(
            (ref) async => SabaBills(
              currencyCode: 'IQD',
              ratePercent: 8,
              current: SabaBill(month: DateTime(2026, 9)),
              past: [
                SabaBill(month: DateTime(2026, 8), isDue: true),
                SabaBill(month: DateTime(2026, 7), owed: 12000, isDue: true),
                SabaBill(month: DateTime(2026, 6), owed: 8000),
              ],
            ),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: MerchantPayoutsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(_en.billNothingOwed), findsOneWidget);
    expect(find.text(_en.billDue), findsOneWidget, reason: 'only July is due');
    expect(find.text(_en.billPaid), findsOneWidget);
  });
}
