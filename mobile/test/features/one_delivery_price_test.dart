// One delivery price, one delivery time.
//
// The product page said "Delivers to Baghdad · 6,000 IQD · 3-5 days" and
// checkout then charged 3,000 and promised 1-2 days: the page worked the
// terms out itself from the store's settings, and the server worked them out
// again when it priced the order. Two rules for one number is two answers.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/location/governorate.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/addresses/presentation/address_providers.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/cart/presentation/cart_providers.dart';
import 'package:saba_marketplace/features/catalog/presentation/catalog_providers.dart';
import 'package:saba_marketplace/features/checkout/presentation/checkout_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => DioFactory.mockBackend.resetForTesting());
  tearDown(() => DioFactory.mockBackend.resetForTesting());

  test(
    'the product page and checkout name the same fee and the same time',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'saba.pref.onboarding_seen': true,
        'saba.pref.locale': 'en',
      });
      final c = ProviderContainer(
        overrides: [
          appPreferencesProvider.overrideWithValue(
            await AppPreferences.create(),
          ),
        ],
        retry: (_, _) => null,
      );
      addTearDown(c.dispose);
      (await c
              .read(authControllerProvider.notifier)
              .signIn(email: 'shopper@saba.app', password: 'Password1'))
          .unwrap();

      // The case the tester hit: browsing as Erbil, with the saved address in
      // Baghdad. The page used to answer for Erbil - Nova's out-of-town price
      // - while checkout charged the Baghdad one.
      (await c
              .read(authControllerProvider.notifier)
              .updateProfile(governorate: Governorate.erbil.apiValue))
          .unwrap();
      await c.read(addressListProvider.notifier).refresh();
      expect(
        c.read(deliveryCityProvider),
        Governorate.baghdad,
        reason: 'the line is still answering for the city they browse from',
      );

      final product =
          (await c.read(catalogRepositoryProvider).fetchProduct('p-1'))
              .unwrap();
      final delivery = product.merchant!.delivery!;
      final onThePage = delivery.to(
        c.read(deliveryCityProvider)!,
        storeCity: product.merchant!.governorate,
      );
      expect(onThePage, isNotNull, reason: 'the page says it cannot deliver');

      await c.read(cartControllerProvider.notifier).addItem(productId: 'p-1');
      final checkout = c.read(checkoutControllerProvider.notifier);
      await checkout.selectAddress('addr-1');
      final group = c
          .read(checkoutControllerProvider)
          .summary!
          .groups
          .firstWhere((g) => g.merchantId == product.merchant!.id);

      expect(
        group.shippingFee,
        onThePage!.$1,
        reason: 'the page and checkout charge different delivery fees',
      );
      expect(
        group.estimatedDelivery,
        contains(RegExp(r'\d')),
        reason: 'checkout says nothing about when it comes',
      );
    },
  );
}
