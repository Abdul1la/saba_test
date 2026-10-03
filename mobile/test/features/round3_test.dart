// Round 3 of BUGS.md, where a check below the screens can hold it.
//
// 92: the product page kept the stock of its first visit for the session,
// and let a shopper pick more than was left.
// 22: the "set as default" switch looked switched off and disabled at once.
// 34: PACKED, a status nothing could reach, is gone.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/core/theme/app_colors.dart';
import 'package:saba_marketplace/core/theme/app_theme.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/catalog/presentation/catalog_providers.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:saba_marketplace/features/merchant/presentation/widgets/merchant_widgets.dart';
import 'package:saba_marketplace/features/orders/domain/entities.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => DioFactory.mockBackend.resetForTesting());
  tearDown(() => DioFactory.mockBackend.resetForTesting());

  Future<ProviderContainer> as(String email) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'saba.pref.onboarding_seen': true,
      'saba.pref.locale': 'en',
    });
    final c = ProviderContainer(
      overrides: [
        appPreferencesProvider.overrideWithValue(await AppPreferences.create()),
      ],
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);
    (await c
            .read(authControllerProvider.notifier)
            .signIn(email: email, password: 'Password1'))
        .unwrap();
    return c;
  }

  test('92: a product opened again has the stock there is now', () async {
    final shopper = await as('shopper@saba.app');
    // The page open, then closed.
    final visit = shopper.listen(productProvider('p-11'), (_, _) {});
    final first = await shopper.read(productProvider('p-11').future);
    expect(first.availableQuantity, greaterThan(2));
    visit.close();
    await Future<void>.delayed(Duration.zero);

    // The store sells all but two elsewhere.
    final store = await as('merchant@saba.app');
    (await store
            .read(merchantRepositoryProvider)
            .setProductStock(productId: 'p-11', stock: 2))
        .unwrap();

    final again = await shopper.read(productProvider('p-11').future);
    expect(
      again.availableQuantity,
      2,
      reason: 'the page still offers the stock of the first visit',
    );
  });

  test('22: a switch that is off looks off, not greyed out', () {
    final theme = AppTheme.light().switchTheme;
    expect(theme.trackColor?.resolve(<WidgetState>{}), AppPalette.borderStrong);
    expect(
      theme.trackOutlineColor?.resolve(<WidgetState>{}),
      Colors.transparent,
    );
    expect(theme.thumbColor?.resolve(<WidgetState>{}), Colors.white);
  });

  test('34: no PACKED anywhere in the order statuses', () {
    expect(
      OrderStatus.values.map((s) => s.apiValue),
      isNot(contains('PACKED')),
    );
    expect(OrderStatus.fromApi('PACKED'), OrderStatus.unknown);
    expect(MerchantOrderStatus.workflow, isNot(contains('PACKED')));
  });
}
