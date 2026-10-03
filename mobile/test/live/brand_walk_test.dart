// The backend's brand walk (2026-10-01): the store's brand box against the
// real server, with the app's own code, on a waiting product the walk adds to
// the M2 test store and deletes at the end. Skipped unless asked for:
//
//   flutter test test/live/brand_walk_test.dart \
//     --dart-define=LIVE=true --dart-define=USE_MOCK_DATA=false \
//     --dart-define=API_BASE_URL=http://localhost:3000/api/v1
//
// Each write is made on the state the step before read, and the walk stops
// at the first answer it did not expect, with no more writes.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/errors/failure.dart';
import 'package:saba_marketplace/core/errors/result.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/catalog/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _live = bool.fromEnvironment('LIVE');
const _base = String.fromEnvironment('API_BASE_URL');
const _phone = '+9647732172587';
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

  Future<MerchantRepository> signedIn() async {
    store.clear();
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
    await c.read(authControllerProvider.future);
    (await c
            .read(authControllerProvider.notifier)
            .signIn(phone: _phone, password: 'walkpass123'))
        .unwrap();
    return c.read(merchantRepositoryProvider);
  }

  /// Saba's side, as the web panel asks it: the dev admin from SETUP.md.
  Future<Dio> sabaSignedIn() async {
    final dio = Dio(BaseOptions(baseUrl: _base, validateStatus: (_) => true));
    final r = await dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'email': 'admin@saba.app', 'password': 'saba12345'},
    );
    final token = (r.data!['data'] as Map)['accessToken'] as String;
    dio.options.headers['Authorization'] = 'Bearer $token';
    return dio;
  }

  /// The product's status and brand as Saba sees them; no status when Saba
  /// finds no product.
  Future<(String?, Map<dynamic, dynamic>?)> sabaSees(Dio saba, String id) async {
    final r = await saba.get<Map<String, dynamic>>('/admin/products/$id');
    final data = r.data?['data'] as Map?;
    return (data?['status'] as String?, data?['brand'] as Map?);
  }

  Future<List<Map<dynamic, dynamic>>> sabaBrands(
    Dio saba, {
    String? q,
    String? status,
  }) async {
    final r = await saba.get<Map<String, dynamic>>(
      '/admin/brands',
      queryParameters: {'q': ?q, 'status': ?status},
    );
    return [
      for (final b in (r.data!['data'] as Map)['items'] as List) b as Map,
    ];
  }

  String say(Result<Object?> result) => result.fold(
    ok: (_) => 'OK',
    err: (Failure f) => 'ERR ${f.statusCode} "${f.message}"',
  );

  /// Prints [line]; false, after STOP, when [ok] is not.
  bool step(String line, {required bool ok}) {
    print('${ok ? '' : 'STOP '}$line');
    return ok;
  }

  /// What the edit form sends for [p], its brand box as the step leaves it.
  ProductDraft draftOf(
    Product p, {
    String? brandId,
    String? brandName,
    bool clear = false,
  }) => ProductDraft(
    id: p.id,
    name: p.nameEn ?? (p.nameAr == null ? p.name : ''),
    nameAr: p.nameAr ?? '',
    description: p.description,
    categoryId: p.categoryId!,
    brandId: brandId,
    brandName: brandName,
    clearBrand: clear,
    price: p.price,
    originalPrice: p.originalPrice,
    stock: p.availableQuantity ?? 0,
    stockBefore: p.availableQuantity ?? 0,
    warranty: p.warranty,
    imageUrls: [for (final m in p.media) m.url],
  );

  test('the brand box against the real server', skip: !_live, () async {
    final shelf = await signedIn();
    final saba = await sabaSignedIn();

    Future<List<String>> ids() async => [
      for (final r in (await shelf.products()).unwrap().items) r.id,
    ];

    final before = await ids();
    if (!step(
      '0 before: products $before',
      ok: (await sabaBrands(saba, q: 'walk brand')).isEmpty,
    )) {
      return;
    }

    // 0. A waiting product, as the form adds one, in 57's category (read
    // only): no brand, no photo.
    final category = (await shelf.product('57')).unwrap().categoryId!;
    final added = await shelf.saveProduct(
      ProductDraft(
        name: 'Brand Walk Case',
        nameAr: 'حافظة جولة العلامة',
        description: 'A test product for the brand walk; deleted at the end.',
        categoryId: category,
        price: 10000,
        stock: 1,
      ),
    );
    final made = [
      for (final id in await ids())
        if (!before.contains(id)) id,
    ];
    if (!step(
      '0 added: ${say(added)}, new $made',
      ok: !added.isErr && made.length == 1,
    )) {
      return;
    }
    final id = made.single;
    var p = (await shelf.product(id)).unwrap();
    var (status, brand) = await sabaSees(saba, id);
    if (!step(
      '0 is: ${p.name}, brand ${p.brand?.name}, $status',
      ok: p.brand == null && brand == null && status == 'PENDING',
    )) {
      return;
    }

    // 1. A brand Saba checked, picked from the list: sent by its id.
    final checked = {
      for (final b in await sabaBrands(saba, status: 'APPROVED')) b['id'],
    };
    final picked = (await shelf.brands())
        .unwrap()
        .where((b) => checked.contains(b.id))
        .firstOrNull;
    if (!step('1 picks: ${picked?.id}:${picked?.name}', ok: picked != null)) {
      return;
    }
    final one = await shelf.saveProduct(draftOf(p, brandId: picked!.id));
    p = (await shelf.product(id)).unwrap();
    (status, brand) = await sabaSees(saba, id);
    if (!step(
      '1 picked: ${say(one)}, brand ${p.brand?.id}:${p.brand?.name}, $status',
      ok: !one.isErr && p.brand?.id == picked.id && status == 'PENDING',
    )) {
      return;
    }

    // 2. A name not on the list: sent as typed, and waits for Saba's check.
    final two = await shelf.saveProduct(
      draftOf(p, brandName: 'Walk Brand 01'),
    );
    p = (await shelf.product(id)).unwrap();
    (status, brand) = await sabaSees(saba, id);
    final waiting = [
      for (final b in await sabaBrands(saba, status: 'PENDING'))
        if (b['name'] == 'Walk Brand 01') b['id'] as String,
    ];
    if (!step(
      '2 typed: ${say(two)}, brand ${p.brand?.id}:${p.brand?.name}, $status, '
      'waiting $waiting, Saba sees $brand',
      ok:
          !two.isErr &&
          p.brand?.name == 'Walk Brand 01' &&
          status == 'PENDING' &&
          waiting.length == 1 &&
          p.brand?.id == waiting.single &&
          brand?['id'] == waiting.single &&
          brand?['isNew'] == true,
    )) {
      return;
    }
    final walkId = waiting.single;

    // 3. The same name in other letters: the same brand, not a second one.
    final three = await shelf.saveProduct(
      draftOf(p, brandName: 'walk brand 01'),
    );
    p = (await shelf.product(id)).unwrap();
    final named = await sabaBrands(saba, q: 'walk brand');
    if (!step(
      '3 other case: ${say(three)}, brand ${p.brand?.id}:${p.brand?.name}, '
      'walk brands ${[for (final b in named) '${b['id']}:${b['name']}']}',
      ok: !three.isErr && p.brand?.id == walkId && named.length == 1,
    )) {
      return;
    }

    // 4. The box emptied: the product has no brand.
    final four = await shelf.saveProduct(draftOf(p, clear: true));
    p = (await shelf.product(id)).unwrap();
    (status, brand) = await sabaSees(saba, id);
    if (!step(
      '4 emptied: ${say(four)}, brand ${p.brand?.name}, $status',
      ok: !four.isErr && p.brand == null && brand == null && status == 'PENDING',
    )) {
      return;
    }

    // 5. Saba deletes the walk brand; its products (none now) keep none.
    final gone = await saba.delete<Map<String, dynamic>>(
      '/admin/brands/$walkId',
      queryParameters: {'moveTo': 'none'},
    );
    final left = await sabaBrands(saba, q: 'walk brand');
    if (!step(
      '5 brand deleted: HTTP ${gone.statusCode}, walk brands left $left',
      ok: gone.statusCode == 200 && left.isEmpty,
    )) {
      return;
    }

    // 6. Still as it was added, then deleted by the store: M2 as the walk
    // found it.
    p = (await shelf.product(id)).unwrap();
    (status, brand) = await sabaSees(saba, id);
    if (!step(
      '6 is: brand ${p.brand?.name}, $status',
      ok: p.brand == null && brand == null && status == 'PENDING',
    )) {
      return;
    }
    final deleted = await shelf.deleteProduct(id);
    final after = await ids();
    (status, _) = await sabaSees(saba, id);
    step(
      '6 deleted: ${say(deleted)}, products $after, Saba sees ${status ?? 'none'}',
      ok: !deleted.isErr && '$after' == '$before' && status == null,
    );
  });
}
