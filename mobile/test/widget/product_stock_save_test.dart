// The reviewer: saving a product set its stock again, so units sold while
// the edit form was open came back. Each stock now goes with the number the
// form showed (stockBefore): unchanged, it stays; changed while it moved,
// the save is refused and the form shows what is there now. And any edit
// in the options table saved every option as new (no id), deleting the old
// ones and their stock history.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/app.dart';
import 'package:saba_marketplace/core/errors/result.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/merchant/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// The demo server, noting what each save sent.
class _Recording extends MerchantRepositoryImpl {
  _Recording(super.client);

  final sent = <ProductDraft>[];

  @override
  Future<Result<void>> saveProduct(ProductDraft draft) {
    sent.add(draft);
    return super.saveProduct(draft);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = <String, String>{};

  setUp(() {
    store.clear();
    DioFactory.mockBackend.resetForTesting();
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
  tearDown(() => DioFactory.mockBackend.resetForTesting());

  /// The store signed in, its product [pick] open in the edit form.
  Future<(ProviderContainer, _Recording, MerchantProductRow)> openForm(
    WidgetTester tester,
    bool Function(MerchantProductRow) pick,
  ) async {
    tester.view.physicalSize = const Size(411 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'saba.pref.onboarding_seen': true,
      'saba.pref.locale': 'en',
    });
    final preferences = await AppPreferences.create();
    late _Recording shelf;
    final c = ProviderContainer(
      overrides: [
        appPreferencesProvider.overrideWithValue(preferences),
        merchantRepositoryProvider.overrideWith(
          (ref) => shelf = _Recording(ref.watch(apiClientProvider)),
        ),
      ],
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);
    late MerchantProductRow row;
    await tester.runAsync(() async {
      (await c
              .read(authControllerProvider.notifier)
              .signIn(email: 'merchant@saba.app', password: 'Password1'))
          .unwrap();
      row = (await c.read(merchantRepositoryProvider).products())
          .unwrap()
          .items
          .firstWhere(pick);
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: const SabaApp()),
    );
    await settle(tester);
    c.read(appRouterProvider).push(AppRoutes.merchantProductForm, extra: row);
    await settle(tester);
    return (c, shelf, row);
  }

  Future<void> save(WidgetTester tester) async {
    final button = find.text('Save changes');
    await tester.ensureVisible(button.last);
    await tester.pump();
    await tester.tap(button.last);
    await settle(tester);
  }

  Future<int?> stockNow(ProviderContainer c, String id) async =>
      (await c.read(merchantRepositoryProvider).product(id))
          .unwrap()
          .availableQuantity;

  testWidgets('one option\'s stock changes; every option keeps its id', (
    tester,
  ) async {
    final (c, shelf, row) = await openForm(tester, (r) => r.id == 'p-1');
    late List<({String id, int? stock})> before;
    await tester.runAsync(() async {
      before = [
        for (final v
            in (await c.read(merchantRepositoryProvider).product(row.id))
                .unwrap()
                .variants)
          (id: v.id, stock: v.availableQuantity),
      ];
    });
    expect(before, hasLength(6));
    // Not what it holds: the same number typed again changes nothing.
    final typed = before.first.stock! + 4;

    final card = find.ancestor(
      of: find.text('Black / 128GB'),
      matching: find.byType(Card),
    );
    final stockBox = find
        .descendant(of: card, matching: find.byType(TextField))
        .at(1);
    await tester.ensureVisible(stockBox);
    await tester.enterText(stockBox, '$typed');
    await tester.pump();
    await save(tester);

    final sent = shelf.sent.single.variants;
    expect(
      [for (final v in sent) v.id],
      [for (final v in before) v.id],
      reason: 'an option saved as new: its old one deleted',
    );
    expect(
      [for (final v in sent) v.stockBefore],
      [for (final v in before) v.stock],
    );
    late List<({String id, int? stock})> after;
    await tester.runAsync(() async {
      after = [
        for (final v
            in (await c.read(merchantRepositoryProvider).product(row.id))
                .unwrap()
                .variants)
          (id: v.id, stock: v.availableQuantity),
      ];
    });
    expect(after.first, (id: before.first.id, stock: typed));
    expect(after.skip(1), before.skip(1), reason: 'only Black / 128GB moved');
  });

  // Backend 2af9579: changing what shoppers read on an approved product
  // takes it off the shop until Saba looks again. The form says so first.
  for (final approved in [true, false]) {
    testWidgets('the form says what sends it back to review ($approved)', (
      tester,
    ) async {
      await openForm(tester, (r) => r.isApproved == approved);
      expect(
        find.text(const AppLocalizations(Locale('en')).editApprovedNote),
        approved ? findsOneWidget : findsNothing,
      );
    });
  }

  testWidgets('an untouched save keeps what sold while the form was open', (
    tester,
  ) async {
    final (c, _, row) = await openForm(
      tester,
      (r) => !r.hasVariants && r.stock > 2,
    );
    // Sold meanwhile, as the stock page would say.
    await tester.runAsync(() async {
      (await c
              .read(merchantRepositoryProvider)
              .setProductStock(productId: row.id, stock: row.stock - 1))
          .unwrap();
    });
    await save(tester);
    late int? now;
    await tester.runAsync(() async => now = await stockNow(c, row.id));
    expect(now, row.stock - 1, reason: 'the stock was put back');
  });

  testWidgets('a stock changed while it moved is refused and shown again', (
    tester,
  ) async {
    final (c, _, row) = await openForm(
      tester,
      (r) => !r.hasVariants && r.stock > 2,
    );
    await tester.runAsync(() async {
      (await c
              .read(merchantRepositoryProvider)
              .setProductStock(productId: row.id, stock: row.stock - 1))
          .unwrap();
    });
    final stockBox = find.widgetWithText(TextField, '${row.stock}');
    await tester.ensureVisible(stockBox);
    await tester.enterText(stockBox, '${row.stock + 5}');
    await tester.pump();
    await save(tester);

    expect(
      find.text(
        'Stock changed while you were editing: ${row.stock - 1} left now. '
        'Check it and save again.',
      ),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(TextField, '${row.stock - 1}'),
      findsOneWidget,
      reason: 'the form still shows the number that was refused',
    );
    late int? now;
    await tester.runAsync(() async => now = await stockNow(c, row.id));
    expect(now, row.stock - 1, reason: 'nothing saved');
  });
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}
