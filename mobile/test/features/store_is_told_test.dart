// A store hears what Saba decided about it.
//
// An approved store was never told: the notice went to the owner's email
// while a store's inbox is keyed `store:<id>`, so it was written where
// nothing reads. And a store Saba turned down still read "waiting to be
// approved" on its own screens, under a red Rejected chip.
import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/mock/mock_data.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import '../support/saba_web.dart';
import 'package:saba_marketplace/features/auth/domain/entities.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:saba_marketplace/features/notifications/presentation/notifications_providers.dart';
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

  Future<String> openAStore(ProviderContainer c, String email) async {
    (await c
            .read(authControllerProvider.notifier)
            .registerMerchant(
              MerchantRegistration(
                fullName: 'Zagros Phones',
                email: email,
                password: 'Demo1234!',
                phone: '+964770555${email.hashCode.abs() % 10000}',
                storeName: 'Zagros Phones',
                businessType: 'INDIVIDUAL',
                country: 'Iraq',
                governorate: 'ERBIL',
              ),
            ))
        .unwrap();
    return c.read(currentUserProvider)!.merchant!.id;
  }

  Future<void> signIn(ProviderContainer c, String email) async {
    (await c
            .read(authControllerProvider.notifier)
            .signIn(email: email, password: 'Password1'))
        .unwrap();
  }

  // The backend's tester: Saba started a store's deletion from the admin
  // web. The owner's app hears the notice and reads the account again, but
  // the dashboard would keep "Open for orders" and the deletion its old
  // state. Both read again when the account's deletion date changes.
  test(
    'a deletion asked from elsewhere reaches the store\'s screens',
    () async {
      final c = await boot();
      await signIn(c, 'merchant@saba.app');
      final shelf = c.read(merchantRepositoryProvider);
      final account = c.read(authControllerProvider.notifier);
      expect((await c.read(merchantDashboardProvider.future)).isOpen, isTrue);
      expect((await c.read(storeDeletionProvider.future)).requestedAt, isNull);

      // Asked elsewhere: all the app does is read the account again.
      (await shelf.requestDeletion()).unwrap();
      (await account.refreshUser()).unwrap();
      expect((await c.read(merchantDashboardProvider.future)).isOpen, isFalse);
      expect(
        (await c.read(storeDeletionProvider.future)).requestedAt,
        isNotNull,
      );

      // Taken back elsewhere.
      (await shelf.cancelDeletion()).unwrap();
      (await account.refreshUser()).unwrap();
      expect((await c.read(storeDeletionProvider.future)).requestedAt, isNull);
    },
  );

  test('an approved store is told so, in its own inbox', () async {
    final c = await boot();
    final store = await openAStore(c, 'zagros@gmail.com');

    await c.read(authControllerProvider.notifier).signOut();
    await signIn(c, 'admin@saba.app');
    expect(
      await c.read(adminAnswersProvider).store(store, approve: true),
      isNull,
    );

    await c.read(authControllerProvider.notifier).signOut();
    await signIn(c, 'zagros@gmail.com');
    final inbox = (await c.read(notificationsRepositoryProvider).fetch())
        .unwrap();
    expect(
      inbox.items.map((n) => n.title),
      contains(contains('approved')),
      reason: 'Saba approved the store and never told it',
    );
  });

  // API_CONTRACT.md 6.2: a reject with no reason told the store nothing.
  test('a rejected store is told why, not that it is still waiting', () async {
    final c = await boot();
    final store = await openAStore(c, 'nothing@gmail.com');

    await c.read(authControllerProvider.notifier).signOut();
    await signIn(c, 'admin@saba.app');
    final answers = c.read(adminAnswersProvider);
    for (final blank in [null, '', '   ']) {
      expect(
        (await answers.store(
          store,
          approve: false,
          reason: blank,
        ))?.messageForField('reason'),
        isNotNull,
        reason: 'turned down with no reason: "$blank"',
      );
    }
    expect(
      await answers.store(
        store,
        approve: false,
        reason: '  The store name is a brand it does not sell.  ',
      ),
      isNull,
    );
    // Answered once.
    expect(
      (await answers.store(store, approve: true))?.statusCode,
      409,
      reason: 'a store turned down was approved after the answer',
    );

    await c.read(authControllerProvider.notifier).signOut();
    await signIn(c, 'nothing@gmail.com');
    final merchant = c.read(currentUserProvider)!.merchant!;
    expect(merchant.status, MerchantStatus.rejected);
    expect(
      merchant.rejectionReason,
      'The store name is a brand it does not sell.',
    );

    final inbox = (await c.read(notificationsRepositoryProvider).fetch())
        .unwrap();
    final told = inbox.items.firstWhere(
      (n) => n.title.contains('not approved'),
      orElse: () => throw StateError('the store was never told'),
    );
    expect(
      told.body,
      contains('The store name is a brand it does not sell.'),
      reason: 'turned down, and not told why',
    );
  });

  // API_CONTRACT.md 6.1 and 6.2: the queue sent one name, already in the
  // admin's language; a rejected product was told nothing.
  test(
    'the admin sees a product in both languages; a rejection says why',
    () async {
      final c = await boot();
      await signIn(c, 'merchant@saba.app');
      final draft = (await c.read(merchantRepositoryProvider).products())
          .unwrap()
          .items
          .firstWhere((row) => row.isDraft);
      (await c.read(merchantRepositoryProvider).submitForApproval(draft.id))
          .unwrap();
      final product = MockData.productById(draft.id)!;

      await signIn(c, 'admin@saba.app');
      // Asked in Arabic, answered in both.
      await c
          .read(localeControllerProvider.notifier)
          .setLocale(const Locale('ar'));
      final queue =
          (await c
                  .read(apiClientProvider)
                  .get<Map<String, dynamic>>(
                    adminQueuePath,
                    decoder: (envelope) => envelope.dataAsMap,
                  ))
              .unwrap();
      final record = (queue['products'] as List)
          .cast<Map<dynamic, dynamic>>()
          .firstWhere((p) => p['id'] == draft.id);
      expect(record['nameEn'], product['nameEn']);
      expect(record['nameAr'], product['nameAr']);
      expect(record['categoryName'], isNot(record['categoryNameAr']));
      expect((record['merchant'] as Map)['storeName'], 'Nova Electronics');
      expect(record['status'], 'PENDING');
      final waiting = (await c.read(
        adminQueueProvider.future,
      )).products.firstWhere((p) => p.id == draft.id);
      expect(waiting.title, product['nameEn']);
      expect(waiting.titleAr, product['nameAr']);

      final answers = c.read(adminAnswersProvider);
      expect(
        (await answers.product(
          draft.id,
          approve: false,
        ))?.messageForField('reason'),
        isNotNull,
        reason: 'turned down with no reason',
      );
      const why = 'The photos are of another model.';
      expect(
        await answers.product(draft.id, approve: false, reason: why),
        isNull,
      );
      expect(
        (await answers.product(draft.id, approve: true))?.statusCode,
        409,
        reason: 'answered twice',
      );

      await c
          .read(localeControllerProvider.notifier)
          .setLocale(const Locale('en'));
      await signIn(c, 'merchant@saba.app');
      final row =
          (await c
                  .read(merchantRepositoryProvider)
                  .products(query: product['name'] as String))
              .unwrap()
              .items
              .firstWhere((row) => row.id == draft.id);
      expect(row.isRejected, isTrue);
      expect(
        row.rejectionReason,
        why,
        reason: 'the shelf shows a made-up reason',
      );
      final inbox = (await c.read(notificationsRepositoryProvider).fetch())
          .unwrap();
      expect(
        inbox.items.map((n) => n.body),
        contains(contains(why)),
        reason: 'the store was not told why',
      );
    },
  );
}
