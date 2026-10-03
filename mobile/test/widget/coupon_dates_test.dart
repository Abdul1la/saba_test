// From the backend session: the server sends a coupon's days in UTC, and
// Baghdad's midnight is 21:00 the day before. The edit form read the UTC
// date, so it showed the day before, and saving moved the coupon a day
// earlier. It goes red only where the phone is east of UTC - Iraq is, and
// so is the machine these tests are run on.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:saba_marketplace/core/errors/result.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/utils/formatters.dart';
import 'package:saba_marketplace/features/merchant/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:saba_marketplace/features/merchant/presentation/screens/merchant_coupons_screen.dart';

/// Keeps the coupon the form saves; nothing else is asked of it.
class _Shelf implements MerchantRepository {
  MerchantCoupon? saved;

  @override
  Future<Result<void>> saveCoupon(MerchantCoupon coupon) async {
    saved = coupon;
    return const Result.ok(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('a coupon opens on its own days and saves them unmoved', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(411 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // As the server sends them: this phone's midnights, in UTC.
    final starts = DateTime(2026, 10, 2);
    final ends = DateTime(2026, 10, 9);
    final coupon = MerchantCoupon(
      id: 'cp-1',
      code: 'SAVE10',
      isPercentage: true,
      value: 10,
      startsAt: starts.toUtc(),
      endsAt: ends.toUtc(),
    );
    final shelf = _Shelf();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => MerchantCouponFormScreen(coupon: coupon),
        ),
        GoRoute(
          path: AppRoutes.merchantCoupons,
          builder: (_, _) => const Placeholder(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [merchantRepositoryProvider.overrideWithValue(shelf)],
        retry: (_, _) => null,
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final day in [starts, ends]) {
      expect(
        find.text(Formatters.date(day, locale: 'en')),
        findsOneWidget,
        reason: 'the form shows another day than the coupon has',
      );
    }

    const en = AppLocalizations(Locale('en'));
    final save = find.text(en.save);
    await tester.ensureVisible(save);
    await tester.pump();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(shelf.saved?.startsAt, starts, reason: 'saved a day earlier');
    // The end is kept to the last second of its day.
    final saved = shelf.saved!.endsAt!.toLocal();
    expect(
      DateTime(saved.year, saved.month, saved.day),
      ends,
      reason: 'saved a day earlier',
    );
  });
}
