import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

/// Sort orders offered by the product list and search results (section 11).
enum ProductSort {
  relevance('relevance'),
  newest('newest'),
  priceAsc('price_asc'),
  priceDesc('price_desc'),
  bestSelling('best_selling');

  const ProductSort(this.apiValue);

  final String apiValue;
}

/// An immutable description of "which products to show".
///
/// Used as the argument to the product-list provider family, so it implements
/// value equality: two identical queries share one cached list instead of
/// refetching.
@immutable
class ProductQuery {
  const ProductQuery({
    this.search,
    this.categoryId,
    this.merchantId,
    this.governorate,
    this.deliverTo,
    this.brandIds = const <String>[],
    this.minPrice,
    this.maxPrice,
    this.inStockOnly = false,
    this.onSaleOnly = false,
    this.sort = ProductSort.relevance,
    this.attributes = const <String, List<String>>{},
  });

  final String? search;
  final String? categoryId;
  final String? merchantId;

  /// Products from stores in this governorate (its API code), or anywhere.
  /// A scope like [merchantId], not a filter: Home's city chips set it.
  final String? governorate;

  /// The shopper's own governorate, so each product can say whether its store
  /// delivers there. Changes what comes back, so it is part of the query.
  final String? deliverTo;
  final List<String> brandIds;
  final num? minPrice;
  final num? maxPrice;
  final bool inStockOnly;
  final bool onSaleOnly;
  final ProductSort sort;

  /// Dynamic, category-driven attribute filters: `{'Color': ['Black']}`.
  final Map<String, List<String>> attributes;

  /// Flattened into query parameters the backend validates and applies. The
  /// server decides what is actually returned; this is only a request.
  Map<String, dynamic> toQueryParameters() => <String, dynamic>{
    'q': ?search,
    'categoryId': ?categoryId,
    'merchantId': ?merchantId,
    'governorate': ?governorate,
    'deliverTo': ?deliverTo,
    if (brandIds.isNotEmpty) 'brandIds': brandIds.join(','),
    'minPrice': ?minPrice,
    'maxPrice': ?maxPrice,
    if (inStockOnly) 'inStock': true,
    if (onSaleOnly) 'onSale': true,
    'sort': sort.apiValue,
    for (final entry in attributes.entries)
      if (entry.value.isNotEmpty) 'attr_${entry.key}': entry.value.join(','),
  };

  /// Filters only — sorting is not a filter, and search is its own field.
  int get activeFilterCount {
    var count = 0;
    if (brandIds.isNotEmpty) count++;
    if (minPrice != null || maxPrice != null) count++;
    if (inStockOnly) count++;
    if (onSaleOnly) count++;
    count += attributes.values.where((values) => values.isNotEmpty).length;
    return count;
  }

  bool get hasActiveFilters => activeFilterCount > 0;

  /// Every active filter, each able to remove itself.
  ///
  /// The design's rule: "Active filters are chips at the top, not a number on
  /// a button. Each one is removable where it is visible." A count on a button
  /// tells the customer that something is filtering their results but not
  /// what, and makes them open a sheet to find out — which is how people end
  /// up believing a shop has no stock.
  ///
  /// [describe] formats a price, so this stays free of localisation.
  List<ActiveFilter> activeFilters({
    required String Function(num amount) money,
    required String priceUpTo,
    required String priceFrom,
    required String priceBetween,
    required String inStock,
    required String onSale,
    required String brandsLabel,
    String comma = ', ',
  }) {
    final filters = <ActiveFilter>[];

    if (minPrice != null || maxPrice != null) {
      final label = switch ((minPrice, maxPrice)) {
        (null, final max?) => '$priceUpTo ${money(max)}',
        (final min?, null) => '$priceFrom ${money(min)}',
        (final min?, final max?) =>
          '$priceBetween ${money(min)} – ${money(max)}',
        _ => priceUpTo,
      };
      filters.add(
        ActiveFilter(
          label: label,
          remove: () => copyWith(clearPriceRange: true),
        ),
      );
    }

    if (inStockOnly) {
      filters.add(
        ActiveFilter(
          label: inStock,
          remove: () => copyWith(inStockOnly: false),
        ),
      );
    }

    if (onSaleOnly) {
      filters.add(
        ActiveFilter(label: onSale, remove: () => copyWith(onSaleOnly: false)),
      );
    }

    if (brandIds.isNotEmpty) {
      filters.add(
        ActiveFilter(
          label: '$brandsLabel · ${brandIds.length}',
          remove: () => copyWith(brandIds: const <String>[]),
        ),
      );
    }

    for (final entry in attributes.entries) {
      if (entry.value.isEmpty) continue;
      filters.add(
        ActiveFilter(
          label: entry.value.join(comma),
          remove: () {
            final next = Map<String, List<String>>.from(attributes)
              ..remove(entry.key);
            return copyWith(attributes: next);
          },
        ),
      );
    }

    return filters;
  }

  ProductQuery copyWith({
    String? search,
    String? categoryId,
    String? merchantId,
    String? governorate,
    String? deliverTo,
    List<String>? brandIds,
    num? minPrice,
    num? maxPrice,
    bool? inStockOnly,
    bool? onSaleOnly,
    ProductSort? sort,
    Map<String, List<String>>? attributes,
    bool clearSearch = false,
    bool clearPriceRange = false,
    bool clearGovernorate = false,
  }) {
    return ProductQuery(
      search: clearSearch ? null : (search ?? this.search),
      categoryId: categoryId ?? this.categoryId,
      merchantId: merchantId ?? this.merchantId,
      governorate: clearGovernorate ? null : (governorate ?? this.governorate),
      deliverTo: deliverTo ?? this.deliverTo,
      brandIds: brandIds ?? this.brandIds,
      minPrice: clearPriceRange ? null : (minPrice ?? this.minPrice),
      maxPrice: clearPriceRange ? null : (maxPrice ?? this.maxPrice),
      inStockOnly: inStockOnly ?? this.inStockOnly,
      onSaleOnly: onSaleOnly ?? this.onSaleOnly,
      sort: sort ?? this.sort,
      attributes: attributes ?? this.attributes,
    );
  }

  /// Drops every filter but keeps the scope (category, merchant, search term).
  ProductQuery clearedFilters() => ProductQuery(
    search: search,
    categoryId: categoryId,
    merchantId: merchantId,
    governorate: governorate,
    deliverTo: deliverTo,
    sort: sort,
  );

  static const DeepCollectionEquality _equality = DeepCollectionEquality();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ProductQuery &&
        other.search == search &&
        other.categoryId == categoryId &&
        other.merchantId == merchantId &&
        other.governorate == governorate &&
        other.deliverTo == deliverTo &&
        other.minPrice == minPrice &&
        other.maxPrice == maxPrice &&
        other.inStockOnly == inStockOnly &&
        other.onSaleOnly == onSaleOnly &&
        other.sort == sort &&
        _equality.equals(other.brandIds, brandIds) &&
        _equality.equals(other.attributes, attributes);
  }

  @override
  int get hashCode => Object.hash(
    search,
    categoryId,
    merchantId,
    governorate,
    deliverTo,
    minPrice,
    maxPrice,
    inStockOnly,
    onSaleOnly,
    sort,
    _equality.hash(brandIds),
    _equality.hash(attributes),
  );

  @override
  String toString() => 'ProductQuery(${toQueryParameters()})';
}

/// One filter the customer can see and switch off where they see it.
@immutable
class ActiveFilter {
  const ActiveFilter({required this.label, required this.remove});

  final String label;

  /// The query with this one filter taken out, everything else kept.
  final ProductQuery Function() remove;
}
