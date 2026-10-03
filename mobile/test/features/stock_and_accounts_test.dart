// The tester's three from Part A.
//
// The inventory sheet asked for the new quantity and added it instead; a
// purchase of an option never came off that option's shelf; and a deleted
// account's number still signed in.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import '../support/saba_web.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/checkout/domain/entities.dart';
import 'package:saba_marketplace/features/checkout/presentation/checkout_providers.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => DioFactory.mockBackend.resetForTesting());
  tearDown(() => DioFactory.mockBackend.resetForTesting());

  Future<ProviderContainer> boot() async {
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
    return c;
  }

  Future<void> signIn(ProviderContainer c, String email) async {
    await c.read(authControllerProvider.notifier).signOut();
    (await c
            .read(authControllerProvider.notifier)
            .signIn(email: email, password: 'Password1'))
        .unwrap();
  }

  test(
    'an option bought comes off that option, and the shelf can run out',
    () async {
      final c = await boot();
      await signIn(c, 'merchant@saba.app');
      final rows = (await c.read(merchantRepositoryProvider).inventory(page: 1))
          .unwrap()
          .items;
      final option = rows.firstWhere((row) => row.variantLabel != null);
      // Down to exactly two, the way the sheet now does it.
      (await c
              .read(merchantRepositoryProvider)
              .adjustStock(
                inventoryId: option.id,
                quantity: 2 - option.available,
              ))
          .unwrap();

      Future<bool> buyOne(String key) async =>
          (await c
                  .read(checkoutRepositoryProvider)
                  .placeOrder(
                    selection: CheckoutSelection(
                      addressId: 'addr-1',
                      paymentMethodId: 'pm-cod',
                      buyNow: BuyNowLine(
                        productId: option.productId,
                        variantId: option.id.substring(4),
                      ),
                    ),
                    idempotencyKey: key,
                  ))
              .isOk;

      await signIn(c, 'shopper@saba.app');
      expect(await buyOne('one'), isTrue);
      expect(await buyOne('two'), isTrue);
      expect(
        await buyOne('three'),
        isFalse,
        reason: 'a third was sold from a shelf of two',
      );

      await signIn(c, 'merchant@saba.app');
      final after =
          (await c.read(merchantRepositoryProvider).inventory(page: 1))
              .unwrap()
              .items
              .firstWhere((row) => row.id == option.id);
      expect(
        after.available,
        0,
        reason: 'two were sold and the shelf kept them',
      );
    },
  );

  test('the new quantity is the new quantity, down as well as up', () async {
    final c = await boot();
    await signIn(c, 'merchant@saba.app');
    final repo = c.read(merchantRepositoryProvider);
    final row = (await repo.inventory(page: 1)).unwrap().items.first;

    // What the sheet sends for "make it 1".
    (await repo.adjustStock(
      inventoryId: row.id,
      quantity: 1 - row.available,
    )).unwrap();
    final after = (await repo.inventory(
      page: 1,
    )).unwrap().items.firstWhere((r) => r.id == row.id);
    expect(after.available, 1, reason: 'the stock could not be brought down');
  });

  test('a deleted account is gone, by email and by number', () async {
    final c = await boot();
    await signIn(c, 'shopper@saba.app');
    (await c.read(authRepositoryProvider).deleteAccount()).unwrap();
    await c.read(authControllerProvider.notifier).signOut();

    final byEmail = await c
        .read(authControllerProvider.notifier)
        .signIn(email: 'shopper@saba.app', password: 'Password1');
    expect(byEmail.isOk, isFalse, reason: 'a deleted account signed back in');
  });

  test('a demo product sent for approval reaches the admin queue', () async {
    final c = await boot();
    await signIn(c, 'merchant@saba.app');
    final repo = c.read(merchantRepositoryProvider);
    final draft = (await repo.products(
      page: 1,
    )).unwrap().items.firstWhere((row) => row.isDraft || row.isRejected);
    (await repo.submitForApproval(draft.id)).unwrap();

    await signIn(c, 'admin@saba.app');
    final queue = await c.read(adminQueueProvider.future);
    expect(
      queue.products.map((p) => p.id),
      contains(draft.id),
      reason: 'sent for approval, and Saba never saw it',
    );
    expect(
      await c.read(adminAnswersProvider).product(draft.id, approve: true),
      isNull,
    );
  });
}
