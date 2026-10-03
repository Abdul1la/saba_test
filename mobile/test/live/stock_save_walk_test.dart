// The reviewer: saving a product reset its stock. With the app's own code
// against the real server (backend cd6228c), on the M2 test store's product
// with options. Skipped unless asked for:
//
//   flutter test test/live/stock_save_walk_test.dart \
//     --dart-define=LIVE=true --dart-define=USE_MOCK_DATA=false \
//     --dart-define=API_BASE_URL=http://localhost:3000/api/v1
//
// It leaves every stock as it found it.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/errors/failure.dart';
import 'package:saba_marketplace/core/errors/result.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/catalog/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _live = bool.fromEnvironment('LIVE');
const _phone = '+9647732172587';
const _productId = '57';
const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = <String, String>{};

  setUpAll(() {
    HttpOverrides.global = null;
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

  Future<MerchantRepository> signedIn(String locale) async {
    store.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'saba.pref.onboarding_seen': true,
      'saba.pref.locale': locale,
    });
    final c = ProviderContainer(
      overrides: [
        appPreferencesProvider.overrideWithValue(await AppPreferences.create()),
      ],
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);
    await c.read(authControllerProvider.future);
    (await c
            .read(authControllerProvider.notifier)
            .signIn(phone: _phone, password: 'walkpass123'))
        .unwrap();
    return c.read(merchantRepositoryProvider);
  }

  String say(Result<Object?> result) => result.fold(
    ok: (_) => 'OK',
    err: (Failure f) => 'ERR ${f.statusCode} "${f.message}"',
  );

  /// What the edit form sends for [p], with [stocks] typed over it and
  /// [shown] as the numbers the form had loaded, by option id.
  ProductDraft draftOf(
    Product p, {
    Map<String, int> stocks = const {},
    Map<String, int> shown = const {},
  }) => ProductDraft(
    id: p.id,
    name: p.nameEn ?? (p.nameAr == null ? p.name : ''),
    nameAr: p.nameAr ?? '',
    description: p.description,
    categoryId: p.categoryId!,
    price: p.price,
    originalPrice: p.originalPrice,
    stock: p.availableQuantity ?? 0,
    stockBefore: p.availableQuantity ?? 0,
    warranty: p.warranty,
    imageUrls: [for (final m in p.media) m.url],
    variants: [
      for (final v in p.variants)
        ProductVariantDraft(
          id: v.id,
          options: v.options,
          sku: v.sku,
          price: v.price,
          stock: stocks[v.id] ?? v.availableQuantity ?? 0,
          stockBefore: shown[v.id] ?? v.availableQuantity ?? 0,
        ),
    ],
  );

  String options(Product p) =>
      [for (final v in p.variants) '${v.id}:${v.availableQuantity}'].join(' ');

  test('saving a product keeps its stock', skip: !_live, () async {
    final shelf = await signedIn('en');
    final start = (await shelf.product(_productId)).unwrap();
    print('0 start: ${start.name} ${options(start)}');
    final a = start.variants.first;
    final aStock = a.availableQuantity ?? 0;

    // 1. Saved untouched: nothing moves, every option keeps its id.
    final untouched = await shelf.saveProduct(draftOf(start));
    final one = (await shelf.product(_productId)).unwrap();
    print('1 untouched: ${say(untouched)} ${options(one)}');
    if (untouched.isErr) return;

    // 2. Sold meanwhile, as far as the form knows: the stock page adds 2.
    final row = (await shelf.inventory()).unwrap().items.firstWhere(
      (r) => r.id == a.id,
    );
    final moved = await shelf.adjustStock(
      inventoryId: row.id,
      quantity: 2,
      reason: 'stock save walk',
    );
    final two = (await shelf.product(_productId)).unwrap();
    print('2 moved +2: ${say(moved)} ${options(two)}');
    if (moved.isErr) return;

    // 3. The form still showed the old number and changed it: refused, in
    // both languages, and nothing saved.
    final stale = draftOf(
      two,
      stocks: {a.id: aStock + 5},
      shown: {a.id: aStock},
    );
    print('3 stale (en): ${say(await shelf.saveProduct(stale))}');
    final arabic = await signedIn('ar');
    print('3 stale (ar): ${say(await arabic.saveProduct(stale))}');
    final three = (await shelf.product(_productId)).unwrap();
    print('3 after: ${options(three)}');

    // 4. Changed from what is there now: saved. Back to where it started.
    final back = await shelf.saveProduct(
      draftOf(three, stocks: {a.id: aStock}),
    );
    final four = (await shelf.product(_productId)).unwrap();
    print('4 back: ${say(back)} ${options(four)}');
    print(
      'ids kept: ${options(four).split(' ').map((s) => s.split(':').first).join(',') == options(start).split(' ').map((s) => s.split(':').first).join(',')}',
    );
  });
}
