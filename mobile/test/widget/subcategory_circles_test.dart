import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/theme/app_theme.dart';
import 'package:saba_marketplace/features/catalog/domain/entities.dart';
import 'package:saba_marketplace/features/catalog/presentation/widgets/subcategory_circles.dart';

/// A category's sub-categories above its products (the user's call,
/// 2026-10-05): "All" first, then each one; a tap picks it.
void main() {
  Future<void> show(
    WidgetTester tester,
    Category parent, {
    String? selectedId,
    ValueChanged<String?>? onSelected,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: SubcategoryCircles(
            parent: parent,
            selectedId: selectedId,
            onSelected: onSelected ?? (_) {},
          ),
        ),
      ),
    );
  }

  const laptops = Category(
    id: '2',
    name: 'Laptops',
    children: [
      Category(id: '10', name: 'Ultrabooks', parentId: '2'),
      Category(id: '11', name: 'Gaming laptops', parentId: '2'),
    ],
  );

  testWidgets('"All" first, then each sub-category; a tap picks it', (
    tester,
  ) async {
    String? picked = 'unset';
    await show(tester, laptops, onSelected: (id) => picked = id);

    expect(find.text('All'), findsOneWidget);
    expect(find.text('Ultrabooks'), findsOneWidget);
    expect(find.text('Gaming laptops'), findsOneWidget);

    await tester.tap(find.text('Gaming laptops'));
    expect(picked, '11');
    await tester.tap(find.text('All'));
    expect(picked, isNull);
  });

  testWidgets('a category with no sub-categories shows nothing', (
    tester,
  ) async {
    await show(tester, const Category(id: '3', name: 'Headphones'));
    expect(find.text('All'), findsNothing);
  });
}
