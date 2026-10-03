// The buttons that reported success and changed nothing, and the two stock
// numbers that disagreed.
//
// Submit for approval, deleting a demo product, editing one, adjusting an
// option's stock and deleting an account all answered 200 and left the app
// exactly as it was. And a product said it had 12 while its colours said 5,
// 4 and 3 - two numbers for one shelf, only one of which ever moved.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/catalog/domain/product_query.dart';
import 'package:saba_marketplace/features/catalog/presentation/catalog_providers.dart';
import 'package:saba_marketplace/features/cart/presentation/cart_providers.dart';
import 'package:saba_marketplace/features/checkout/presentation/checkout_providers.dart';
import 'package:saba_marketplace/features/merchant/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => DioFactory.mockBackend.resetForTesting());
  tearDown(() => DioFactory.mockBackend.resetForTesting());

  Future<ProviderContainer> open(String email) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'saba.pref.onboarding_seen': true,
      'saba.pref.locale': 'en',
    });
    final container = ProviderContainer(
      overrides: [
        appPreferencesProvider.overrideWithValue(await AppPreferences.create()),
      ],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    (await container
            .read(authControllerProvider.notifier)
            .signIn(email: email, password: 'Password1'))
        .unwrap();
    return container;
  }

  Future<List<MerchantProductRow>> shelf(ProviderContainer c) async =>
      (await c.read(merchantRepositoryProvider).products(page: 1))
          .unwrap()
          .items;

  test('submit for approval really moves the product', () async {
    final c = await open('merchant@saba.app');
    final draft = (await shelf(c)).firstWhere((row) => row.isDraft);

    (await c.read(merchantRepositoryProvider).submitForApproval(draft.id))
        .unwrap();

    final after = (await shelf(c)).firstWhere((row) => row.id == draft.id);
    expect(
      after.status,
      'PENDING',
      reason: 'the paper plane said "sent" and the row kept its old status',
    );
  });

  test(
    'deleting a demo product takes it off the shelf and out of the shop',
    () async {
      final c = await open('merchant@saba.app');
      final row = (await shelf(c)).first;

      (await c.read(merchantRepositoryProvider).deleteProduct(row.id)).unwrap();

      expect(
        (await shelf(c)).map((r) => r.id),
        isNot(contains(row.id)),
        reason: 'the store deleted it and it stayed on the shelf',
      );

      final page = await c
          .read(catalogRepositoryProvider)
          .fetchProducts(query: const ProductQuery());
      expect(
        page.unwrap().items.map((p) => p.id),
        isNot(contains(row.id)),
        reason: 'a deleted product was still for sale',
      );
    },
  );

  test('editing a demo product keeps its category', () async {
    final c = await open('merchant@saba.app');
    final row = (await shelf(c)).first;
    final before =
        (await c.read(catalogRepositoryProvider).fetchProduct(row.id)).unwrap();
    final moved = before.categoryId == 'c-smartphones'
        ? 'c-laptops'
        : 'c-smartphones';

    (await c
            .read(merchantRepositoryProvider)
            .saveProduct(
              ProductDraft(
                id: row.id,
                name: before.name,
                nameAr: before.nameAr ?? 'منتج',
                categoryId: moved,
                price: before.price,
                stock: 5,
              ),
            ))
        .unwrap();

    final after = (await c.read(catalogRepositoryProvider).fetchProduct(row.id))
        .unwrap();
    expect(
      after.categoryId,
      moved,
      reason: 'the form said saved and the category did not move',
    );
  });

  test('deleting an account really empties it', () async {
    final c = await open('shopper@saba.app');
    await c.read(cartControllerProvider.notifier).addItem(productId: 'p-1');
    expect(c.read(cartItemCountProvider), greaterThan(0));

    (await c.read(authRepositoryProvider).deleteAccount()).unwrap();
    // Emptied at once, before anything else happens.
    final cart = (await c.read(cartRepositoryProvider).fetchCart()).unwrap();
    expect(cart.groups, isEmpty, reason: 'a deleted account kept its cart');

    // And it does not come back: signing in with it is refused.
    await c.read(authControllerProvider.notifier).signOut();
    final again = await c
        .read(authControllerProvider.notifier)
        .signIn(email: 'shopper@saba.app', password: 'Password1');
    expect(again.isOk, isFalse, reason: 'a deleted account signed back in');
  });

  test("an option's stock saves, and the product is their sum", () async {
    final c = await open('merchant@saba.app');
    final rows = (await c.read(merchantRepositoryProvider).inventory(page: 1))
        .unwrap()
        .items;
    final option = rows.firstWhere((row) => row.variantLabel != null);

    final product =
        (await c.read(catalogRepositoryProvider).fetchProduct(option.productId))
            .unwrap();
    final wholeBefore = product.availableQuantity;

    (await c
            .read(merchantRepositoryProvider)
            .adjustStock(
              inventoryId: option.id,
              quantity: 3,
              reason: 'MANUAL_ADJUSTMENT',
            ))
        .unwrap();

    final again = (await c.read(merchantRepositoryProvider).inventory(page: 1))
        .unwrap()
        .items
        .firstWhere((row) => row.id == option.id);
    expect(
      again.available,
      option.available + 3,
      reason: 'the sheet saved and the row came back as it was',
    );

    final whole =
        (await c.read(catalogRepositoryProvider).fetchProduct(option.productId))
            .unwrap();
    expect(
      whole.availableQuantity,
      (wholeBefore ?? 0) + 3,
      reason: 'the product kept a stock number of its own',
    );
    expect(
      whole.variants
          .firstWhere((variant) => variant.id == option.id.substring(4))
          .availableQuantity,
      option.available + 3,
      reason: "the shopper's page does not show the option's real stock",
    );
  });

  Future<InventoryRow> plainRow(ProviderContainer c) async =>
      (await c.read(merchantRepositoryProvider).inventory(page: 1))
          .unwrap()
          .items
          .firstWhere((r) => r.variantLabel == null && r.available > 0);

  Future<void> empty(ProviderContainer c, InventoryRow row) async =>
      (await c
              .read(merchantRepositoryProvider)
              .adjustStock(
                inventoryId: row.id,
                quantity: -row.available,
                reason: 'MANUAL_ADJUSTMENT',
              ))
          .unwrap();

  Future<void> signIn(ProviderContainer c, String email) async {
    await c.read(authControllerProvider.notifier).signOut();
    (await c
            .read(authControllerProvider.notifier)
            .signIn(email: email, password: 'Password1'))
        .unwrap();
  }

  test('checkout refuses what has run out', () async {
    final c = await open('merchant@saba.app');
    final row = await plainRow(c);
    await signIn(c, 'shopper@saba.app');
    (await c
            .read(cartControllerProvider.notifier)
            .addItem(productId: row.productId))
        .unwrap();

    // Emptied by its own store, while a shopper has it in the cart.
    await signIn(c, 'merchant@saba.app');
    await empty(c, row);
    await signIn(c, 'shopper@saba.app');

    final checkout = c.read(checkoutControllerProvider.notifier);
    await checkout.priceOrder();
    final placed = await checkout.placeOrder();
    expect(
      placed.isErr,
      isTrue,
      reason: 'an order was taken for something the shop has run out of',
    );
  });

  // As the real server (M4): what has run out does not go in the cart.
  test('what has run out cannot go in the cart', () async {
    final c = await open('merchant@saba.app');
    final row = await plainRow(c);
    await empty(c, row);
    await signIn(c, 'shopper@saba.app');

    final added = await c
        .read(cartRepositoryProvider)
        .addItem(productId: row.productId);
    expect(
      added.failureOrNull?.message,
      "This has run out, so it can't go in the cart.",
    );
  });
}
