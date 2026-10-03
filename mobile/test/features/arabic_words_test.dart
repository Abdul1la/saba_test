// In Arabic, the demo server answers in Arabic.
//
// It swapped a product's name and nothing else, so a product page said
// "12 months manufacturer warranty" and a developer's note for its
// description, options read "Black · 128GB" in the cart and on orders, a
// store's description and address, the support chat's title and the demo
// address stayed English, and an order placed in English kept English names
// for an Arabic reader.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/addresses/presentation/address_providers.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/catalog/presentation/catalog_providers.dart';
import 'package:saba_marketplace/features/catalog/presentation/screens/storefront_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _arabic = RegExp('[؀-ۿ]');
final _latinWord = RegExp('[A-Za-z]{3,}');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => DioFactory.mockBackend.resetForTesting());
  tearDown(() => DioFactory.mockBackend.resetForTesting());

  Future<ProviderContainer> inArabic() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'saba.pref.onboarding_seen': true,
      'saba.pref.locale': 'ar',
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
            .signIn(email: 'shopper@saba.app', password: 'Password1'))
        .unwrap();
    return c;
  }

  test('a product page: its description, warranty and options', () async {
    final c = await inArabic();
    final product =
        (await c.read(catalogRepositoryProvider).fetchProduct('p-1')).unwrap();

    for (final (what, text) in [
      ('description', product.description ?? ''),
      ('warranty', product.warranty ?? ''),
    ]) {
      expect(_arabic.hasMatch(text), isTrue, reason: '$what: "$text"');
      expect(_latinWord.hasMatch(text), isFalse, reason: '$what: "$text"');
    }
    final words = {
      for (final variant in product.variants) ...variant.options.keys,
      for (final variant in product.variants) ...variant.options.values,
    };
    expect(words, containsAll(<String>['اللون', 'أسود']));
    expect(words, isNot(contains('Black')));
    // The swatches are keyed by the same words, or they lose their colour.
    expect(product.optionColours.keys, contains('أسود'));
  });

  test("a store's description and address, and the demo address", () async {
    final c = await inArabic();
    final store = await c.read(merchantStoreProvider('m-2').future);
    expect(store.description, 'أجهزة منزلية ولوازم المطبخ.');
    expect(store.address, 'شارع الكورنيش، العشار');

    final address = (await c.read(addressListProvider.future)).first;
    expect(address.label, 'المنزل');
  });
}
