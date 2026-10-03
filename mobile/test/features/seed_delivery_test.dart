// A store's past orders went where it delivers, for what it charges.
//
// Every seeded order charged a flat 5,000 IQD, whatever the store's own
// terms - Nova asks 3,000 in Baghdad and 6,000 elsewhere - and Atlas, which
// does not deliver to Erbil, had orders delivered there.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/catalog/presentation/screens/storefront_screen.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => DioFactory.mockBackend.resetForTesting());
  tearDown(() => DioFactory.mockBackend.resetForTesting());

  for (final (email, store) in const [
    ('merchant@saba.app', 'm-1'),
    ('merchant2@saba.app', 'm-2'),
  ]) {
    test(
      '$store: each order goes where it delivers, for its own fee',
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
                .signIn(email: email, password: 'Password1'))
            .unwrap();

        final terms = await c.read(merchantStoreProvider(store).future);
        final orders = (await c.read(merchantRepositoryProvider).orders())
            .unwrap()
            .items;
        expect(orders, isNotEmpty);

        final fees = <num>{};
        for (final order in orders) {
          final city = order.customerGovernorate!;
          final asked = terms.delivery!.to(city, storeCity: terms.governorate);
          expect(
            asked,
            isNotNull,
            reason:
                '${order.orderNumber} went to $city, where $store '
                'does not deliver',
          );
          final goods = order.items.fold<num>(
            0,
            (sum, item) => sum + item.price * item.quantity,
          );
          expect(
            order.total - goods,
            asked!.$1,
            reason:
                '${order.orderNumber} charged its own fee, not the store\'s',
          );
          fees.add(asked.$1);
        }
        // Its own city and another: two fees, not one flat one.
        expect(fees, hasLength(2));
      },
    );

    // The admin web bills each store for the three months before this one;
    // the app had only today's orders and said "No past months yet".
    test('$store: owes Saba for the last three months', () async {
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
              .signIn(email: email, password: 'Password1'))
          .unwrap();

      final bills = (await c.read(merchantRepositoryProvider).bills()).unwrap();
      final now = DateTime.now();
      expect(
        [for (final bill in bills.past) bill.month],
        [
          for (var back = 1; back <= 3; back++)
            DateTime(now.year, now.month - back),
        ],
      );
      for (final bill in bills.past) {
        expect(bill.orderCount, greaterThan(0));
        // 8% of what was delivered less the cash given back, to 250 IQD.
        expect(
          bill.owed,
          ((bill.sales - bill.returned) * 8 / 100 / 250).round() * 250,
        );
      }
      // Atlas refunded a return in its history, as the admin web shows.
      if (store == 'm-2') {
        expect(
          bills.past.where((bill) => bill.returned > 0),
          isNotEmpty,
          reason: 'the refund the web takes off its bill is missing',
        );
      }
    });
  }
}
