import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/features/catalog/domain/product_query.dart';

/// "Active filters are chips at the top, not a number on a button. Each one is
/// removable where it is visible."
///
/// The part worth pinning is that removing one chip removes **only** that
/// filter. A customer who takes off "under 150,000" and silently loses
/// "in stock" as well is being lied to by the interface.
void main() {
  List<ActiveFilter> filtersOf(ProductQuery query) => query.activeFilters(
    money: (amount) => '$amount',
    priceUpTo: 'Up to',
    priceFrom: 'From',
    priceBetween: 'Between',
    inStock: 'In stock',
    onSale: 'On sale',
    brandsLabel: 'Brands',
  );

  test('no filters, no chips', () {
    expect(filtersOf(const ProductQuery()), isEmpty);
    expect(
      filtersOf(const ProductQuery(search: 'hoodie', sort: ProductSort.newest)),
      isEmpty,
      reason: 'a search term and a sort order are not filters',
    );
  });

  test('one chip per active filter, matching the count on the button', () {
    const query = ProductQuery(
      maxPrice: 150000,
      inStockOnly: true,
      onSaleOnly: true,
    );

    expect(filtersOf(query), hasLength(query.activeFilterCount));
  });

  test('a price range is one chip, not two', () {
    const query = ProductQuery(minPrice: 50000, maxPrice: 150000);
    expect(filtersOf(query), hasLength(1));
    expect(filtersOf(query).single.label, contains('Between'));
  });

  test('removing a chip takes out that filter and nothing else', () {
    const query = ProductQuery(
      search: 'hoodie',
      categoryId: 'c-1',
      maxPrice: 150000,
      inStockOnly: true,
      sort: ProductSort.priceAsc,
    );

    final price = filtersOf(
      query,
    ).firstWhere((filter) => filter.label.contains('Up to'));
    final next = price.remove();

    expect(next.maxPrice, isNull);
    expect(next.inStockOnly, isTrue, reason: 'the other filter must survive');
    expect(next.search, 'hoodie', reason: 'the search term is not a filter');
    expect(next.categoryId, 'c-1', reason: 'the category is not a filter');
    expect(next.sort, ProductSort.priceAsc, reason: 'the sort is not a filter');
  });

  test('removing an attribute leaves the other attributes alone', () {
    const query = ProductQuery(
      attributes: {
        'Colour': ['Black'],
        'Size': ['M', 'L'],
      },
    );

    final colour = filtersOf(
      query,
    ).firstWhere((filter) => filter.label == 'Black');
    final next = colour.remove();

    expect(next.attributes.containsKey('Colour'), isFalse);
    expect(next.attributes['Size'], ['M', 'L']);
  });
}
