import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/errors/failure.dart';
import 'package:saba_marketplace/core/errors/result.dart';
import 'package:saba_marketplace/features/catalog/domain/product_query.dart';

void main() {
  group('Result', () {
    test('Ok carries the value', () {
      const result = Result<int>.ok(7);
      expect(result.isOk, isTrue);
      expect(result.isErr, isFalse);
      expect(result.valueOrNull, 7);
      expect(result.failureOrNull, isNull);
    });

    test('Err carries the failure', () {
      const failure = NotFoundFailure(message: 'missing');
      const result = Result<int>.err(failure);
      expect(result.isErr, isTrue);
      expect(result.valueOrNull, isNull);
      expect(result.failureOrNull, failure);
    });

    test('fold collapses both branches', () {
      const ok = Result<int>.ok(2);
      const err = Result<int>.err(NetworkFailure());

      expect(ok.fold(ok: (v) => v * 10, err: (_) => -1), 20);
      expect(err.fold(ok: (v) => v * 10, err: (_) => -1), -1);
    });

    test('map transforms success and preserves failure', () {
      expect(const Result<int>.ok(3).map((v) => v + 1).valueOrNull, 4);

      const failure = ServerFailure();
      final mapped = const Result<int>.err(failure).map((v) => v + 1);
      expect(mapped.failureOrNull, failure);
    });

    test('unwrap throws the failure so AsyncValue can capture it', () {
      expect(
        () => const Result<int>.err(InventoryFailure()).unwrap(),
        throwsA(isA<InventoryFailure>()),
      );
      expect(const Result<int>.ok(1).unwrap(), 1);
    });
  });

  group('ProductQuery', () {
    test('two identical queries are equal, so the cache is shared', () {
      const a = ProductQuery(
        categoryId: 'c1',
        brandIds: ['b1', 'b2'],
        minPrice: 10,
        sort: ProductSort.priceAsc,
        attributes: {
          'Color': ['Black'],
        },
      );
      const b = ProductQuery(
        categoryId: 'c1',
        brandIds: ['b1', 'b2'],
        minPrice: 10,
        sort: ProductSort.priceAsc,
        attributes: {
          'Color': ['Black'],
        },
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('a different filter produces a different query', () {
      const a = ProductQuery(categoryId: 'c1');
      const b = ProductQuery(categoryId: 'c1', inStockOnly: true);
      expect(a, isNot(equals(b)));
    });

    test('query parameters omit absent filters', () {
      const query = ProductQuery(categoryId: 'c1');
      final params = query.toQueryParameters();

      expect(params['categoryId'], 'c1');
      expect(params.containsKey('minPrice'), isFalse);
      expect(params.containsKey('inStock'), isFalse);
      expect(params['sort'], 'relevance');
    });

    test('query parameters flatten lists and attributes', () {
      const query = ProductQuery(
        brandIds: ['b1', 'b2'],
        inStockOnly: true,
        onSaleOnly: true,
        attributes: {
          'Color': ['Black', 'Blue'],
          'Empty': <String>[],
        },
      );
      final params = query.toQueryParameters();

      expect(params['brandIds'], 'b1,b2');
      expect(params['inStock'], true);
      expect(params['onSale'], true);
      expect(params['attr_Color'], 'Black,Blue');
      expect(params.containsKey('attr_Empty'), isFalse);
    });

    test('counts active filters but not sorting or search', () {
      const query = ProductQuery(
        search: 'phone',
        sort: ProductSort.priceDesc,
        brandIds: ['b1'],
        minPrice: 5,
        inStockOnly: true,
        attributes: {
          'Color': ['Black'],
        },
      );

      // brands + price range + inStock + one attribute
      expect(query.activeFilterCount, 4);
      expect(query.hasActiveFilters, isTrue);
    });

    test('clearedFilters keeps the scope and drops the filters', () {
      const query = ProductQuery(
        search: 'phone',
        categoryId: 'c1',
        merchantId: 'm1',
        sort: ProductSort.newest,
        brandIds: ['b1'],
        inStockOnly: true,
      );

      final cleared = query.clearedFilters();

      expect(cleared.search, 'phone');
      expect(cleared.categoryId, 'c1');
      expect(cleared.merchantId, 'm1');
      expect(cleared.sort, ProductSort.newest);
      expect(cleared.hasActiveFilters, isFalse);
    });
  });
}
