import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/features/merchant/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/presentation/widgets/variant_matrix_editor.dart';

/// G19 — the merchant variant matrix (specification section 10).

Widget _harness(Widget child) => MaterialApp(
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const <LocalizationsDelegate<Object>>[
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

/// Fields inside the open dialog only.
///
/// A plain `find.byType(TextFormField)` also matches the SKU, price and stock
/// boxes on every matrix row, so it types into the wrong widget as soon as one
/// option exists.
Finder dialogFields() => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.byType(TextFormField),
);

/// Adds one option type through the dialog, as a merchant would.
Future<void> addOption(WidgetTester tester, String name, String values) async {
  await tester.tap(find.widgetWithText(ActionChip, 'Add option'));
  await tester.pumpAndSettle();

  await tester.enterText(dialogFields().at(0), name);
  await tester.enterText(dialogFields().at(1), values);
  await tester.tap(find.widgetWithText(FilledButton, 'Save'));
  await tester.pumpAndSettle();
}

void main() {
  group('ProductVariantDraft', () {
    test('signature ignores map ordering', () {
      const a = ProductVariantDraft(
        options: <String, String>{'Color': 'Red', 'Size': 'M'},
      );
      const b = ProductVariantDraft(
        options: <String, String>{'Size': 'M', 'Color': 'Red'},
      );
      expect(a.signature, b.signature);
    });

    test('distinct combinations do not collide', () {
      const a = ProductVariantDraft(
        options: <String, String>{'Color': 'Red', 'Size': 'M'},
      );
      const b = ProductVariantDraft(
        options: <String, String>{'Color': 'Red', 'Size': 'L'},
      );
      expect(a.signature, isNot(b.signature));
    });

    test('serialises options as name/value pairs', () {
      const draft = ProductVariantDraft(
        options: <String, String>{'Color': 'Red'},
        sku: 'RED-1',
        price: 99,
        stock: 4,
      );
      final json = draft.toJson();
      expect(json['sku'], 'RED-1');
      expect(json['price'], 99);
      expect(json['stock'], 4);
      expect(json['options'], [
        <String, dynamic>{'name': 'Color', 'value': 'Red'},
      ]);
    });

    test('an inherited price is omitted rather than sent as zero', () {
      const draft = ProductVariantDraft(
        options: <String, String>{'Color': 'Red'},
      );
      expect(draft.toJson().containsKey('price'), isFalse);
    });
  });

  group('ProductDraft', () {
    ProductDraft base({
      List<String> images = const <String>[],
      List<ProductVariantDraft> variants = const <ProductVariantDraft>[],
    }) => ProductDraft(
      name: 'Phone',
      nameAr: 'هاتف',
      description: 'A phone',
      categoryId: 'c1',
      price: 100,
      imageUrls: images,
      variants: variants,
    );

    test('omits media and variants when there are none', () {
      final json = base().toJson();
      expect(json.containsKey('images'), isFalse);
      expect(json.containsKey('variants'), isFalse);
    });

    test('sends images in order — the first is the main image', () {
      final json = base(images: <String>['a.jpg', 'b.jpg']).toJson();
      expect(json['images'], <String>['a.jpg', 'b.jpg']);
    });

    test('sends variants', () {
      final json = base(
        variants: const <ProductVariantDraft>[
          ProductVariantDraft(options: <String, String>{'Color': 'Red'}),
        ],
      ).toJson();
      expect((json['variants'] as List).length, 1);
    });
  });

  group('VariantMatrixEditor', () {
    testWidgets('one option produces one row per value', (tester) async {
      var latest = <ProductVariantDraft>[];
      await tester.pumpWidget(
        _harness(VariantMatrixEditor(onChanged: (v) => latest = v)),
      );
      await tester.pumpAndSettle();

      await addOption(tester, 'Color', 'Red, Blue');

      expect(latest.length, 2);
      expect(latest.map((v) => v.label), containsAll(<String>['Red', 'Blue']));
    });

    testWidgets('two options produce the cartesian product', (tester) async {
      var latest = <ProductVariantDraft>[];
      await tester.pumpWidget(
        _harness(VariantMatrixEditor(onChanged: (v) => latest = v)),
      );
      await tester.pumpAndSettle();

      await addOption(tester, 'Color', 'Red, Blue');
      await addOption(tester, 'Size', 'S, M, L');

      expect(latest.length, 6, reason: '2 colours x 3 sizes');
    });

    testWidgets('duplicate values are collapsed', (tester) async {
      var latest = <ProductVariantDraft>[];
      await tester.pumpWidget(
        _harness(VariantMatrixEditor(onChanged: (v) => latest = v)),
      );
      await tester.pumpAndSettle();

      await addOption(tester, 'Color', 'Red, Red, Blue');

      expect(latest.length, 2);
    });

    testWidgets('editing an option keeps the stock already typed in', (
      tester,
    ) async {
      var latest = <ProductVariantDraft>[];
      await tester.pumpWidget(
        _harness(VariantMatrixEditor(onChanged: (v) => latest = v)),
      );
      await tester.pumpAndSettle();

      await addOption(tester, 'Color', 'Red');

      // Type stock against the only row (price, stock). SKU is gone: it
      // meant nothing to a small shop.
      final rowFields = find.descendant(
        of: find.byType(Card),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(rowFields.at(1), '7');
      await tester.pumpAndSettle();
      expect(latest.single.stock, 7);

      // Adding a colour must not discard the figure already entered for Red.
      await tester.tap(find.byType(InputChip).first);
      await tester.pumpAndSettle();
      await tester.enterText(dialogFields().at(1), 'Red, Blue');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(latest.length, 2);
      final red = latest.firstWhere((v) => v.label == 'Red');
      expect(red.stock, 7, reason: 'the surviving row keeps its stock');
    });

    testWidgets('removing an option clears the matrix', (tester) async {
      var latest = <ProductVariantDraft>[];
      await tester.pumpWidget(
        _harness(VariantMatrixEditor(onChanged: (v) => latest = v)),
      );
      await tester.pumpAndSettle();

      await addOption(tester, 'Color', 'Red, Blue');
      expect(latest.length, 2);

      tester.widget<InputChip>(find.byType(InputChip).first).onDeleted!();
      await tester.pumpAndSettle();

      expect(latest, isEmpty);
    });

    testWidgets('an existing product opens with its matrix already built', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          VariantMatrixEditor(
            onChanged: (_) {},
            initial: const <ProductVariantDraft>[
              ProductVariantDraft(
                options: <String, String>{'Color': 'Red'},
                stock: 3,
              ),
              ProductVariantDraft(
                options: <String, String>{'Color': 'Blue'},
                stock: 5,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Red'), findsOneWidget);
      expect(find.text('Blue'), findsOneWidget);
    });
  });
}
