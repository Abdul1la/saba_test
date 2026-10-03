import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/live_updates.dart';

import '../../../core/errors/result.dart';
import '../../../core/network/api_response.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/providers/paged_state.dart';
import '../data/catalog_repository_impl.dart';
import '../domain/catalog_repository.dart';
import '../domain/entities.dart';
import '../domain/product_query.dart';
import '../../auth/presentation/auth_providers.dart';

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  ref.watch(accountIdProvider);
  return CatalogRepositoryImpl(ref.watch(apiClientProvider));
});

/// The full category tree, as Saba's admin keeps it: a category it adds,
/// hides or renames shows on the next load. The store's product form reads
/// it again when it opens, and Browse when it is pulled or the app reopened.
/// It was kept for the whole session, although this said a pull refreshed
/// it.
final categoryTreeProvider = FutureProvider<List<Category>>((ref) async {
  return (await ref.watch(catalogRepositoryProvider).fetchCategoryTree())
      .unwrap();
});

final categoryProvider = FutureProvider.family<Category, String>((
  ref,
  id,
) async {
  return (await ref.watch(catalogRepositoryProvider).fetchCategory(id))
      .unwrap();
});

/// Attribute definitions for a category, which drive the dynamic filter sheet.
final categoryAttributesProvider =
    FutureProvider.family<List<AttributeDefinition>, String>((ref, id) async {
      return (await ref
              .watch(catalogRepositoryProvider)
              .fetchCategoryAttributes(id))
          .unwrap();
    });

/// The filter's brands. The filter reads them again when it opens: Saba
/// checks new ones on its brands page, and they were kept for the session.
final brandsProvider = FutureProvider.family<List<Brand>, String?>((
  ref,
  categoryId,
) async {
  return (await ref
          .watch(catalogRepositoryProvider)
          .fetchBrands(categoryId: categoryId))
      .unwrap();
});

/// Fetched each time the page opens: kept for the session, it showed the
/// stock of the first visit, and let a shopper pick more than was left
/// until they pulled to refresh (BUGS.md 92).
final productProvider = FutureProvider.autoDispose.family<Product, String>((
  ref,
  id,
) async {
  final repository = ref.watch(catalogRepositoryProvider);
  return (await repository.fetchProduct(id)).unwrap();
});

final relatedProductsProvider =
    FutureProvider.family<List<ProductSummary>, String>((ref, productId) async {
      return (await ref
              .watch(catalogRepositoryProvider)
              .fetchRelatedProducts(productId))
          .unwrap();
    });

/// Paginated product list for a given query.
///
/// The query is the family argument and has value equality, so navigating back
/// to the same filtered list reuses the pages already loaded.
class ProductListNotifier extends PagedNotifier<ProductSummary> {
  ProductListNotifier(this.query);

  final ProductQuery query;

  @override
  Future<PagedState<ProductSummary>> build() {
    ref.watch(accountIdProvider);
    // An order takes stock: the last one bought left Home's card saying
    // "available" until the app was restarted (the tester).
    ref.watch(liveTopicProvider(LiveTopic.orders));
    return super.build();
  }

  @override
  Future<Result<PaginatedList<ProductSummary>>> fetchPage(int page) {
    return ref
        .read(catalogRepositoryProvider)
        .fetchProducts(query: query, page: page);
  }
}

final productListProvider =
    AsyncNotifierProvider.family<
      ProductListNotifier,
      PagedState<ProductSummary>,
      ProductQuery
    >(ProductListNotifier.new);
