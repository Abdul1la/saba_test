import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/api_endpoints.dart';
import '../../../core/errors/result.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/utils/json_reader.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../catalog/data/catalog_mappers.dart';
import '../../catalog/domain/entities.dart';

/// Read and write the customer's default wishlist.
///
/// The backend supports multiple named lists; the app uses the default one and
/// can grow into the others without a contract change (section 18).
abstract interface class WishlistRepository {
  Future<Result<List<ProductSummary>>> fetchItems();

  Future<Result<void>> add(String productId);

  Future<Result<void>> remove(String productId);
}

class WishlistRepositoryImpl implements WishlistRepository {
  const WishlistRepositoryImpl(this.client);

  final ApiClient client;

  @override
  Future<Result<List<ProductSummary>>> fetchItems() {
    return client.get<List<ProductSummary>>(
      ApiEndpoints.wishlistDefaultItems,
      decoder: (envelope) =>
          Json.mapList(envelope.dataAsList, CatalogMappers.productSummary),
    );
  }

  @override
  Future<Result<void>> add(String productId) => client.command(
    ApiEndpoints.wishlistDefaultItems,
    data: <String, dynamic>{'productId': productId},
  );

  @override
  Future<Result<void>> remove(String productId) => client.command(
    ApiEndpoints.wishlistDefaultItem(productId),
    method: 'DELETE',
  );
}

final wishlistRepositoryProvider = Provider<WishlistRepository>((ref) {
  ref.watch(accountIdProvider);
  return WishlistRepositoryImpl(ref.watch(apiClientProvider));
});

/// Holds the wishlist and exposes an optimistic toggle.
///
/// The heart icon flips immediately and rolls back if the server rejects the
/// change, which keeps the grid feeling instant without inventing state.
class WishlistController extends AsyncNotifier<List<ProductSummary>> {
  WishlistRepository get _repository => ref.read(wishlistRepositoryProvider);

  @override
  Future<List<ProductSummary>> build() async {
    final isAuthenticated = ref.watch(accountIdProvider) != null;
    final isCustomer = ref.watch(currentRoleProvider).isCustomer;
    // Product names come back in the reader's language.
    ref.watch(acceptLanguageProvider);
    if (!isAuthenticated || !isCustomer) return const <ProductSummary>[];
    return (await _repository.fetchItems()).unwrap();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () async => (await _repository.fetchItems()).unwrap(),
    );
  }

  bool contains(String productId) => (state.value ?? const <ProductSummary>[])
      .any((item) => item.id == productId);

  /// Adds or removes, returning the failure when the server refused.
  Future<Result<void>> toggle(ProductSummary product) async {
    final current = state.value ?? const <ProductSummary>[];
    final isSaved = current.any((item) => item.id == product.id);

    // Optimistic update.
    state = AsyncValue<List<ProductSummary>>.data(
      isSaved
          ? current.where((item) => item.id != product.id).toList()
          : <ProductSummary>[product.copyWith(isWishlisted: true), ...current],
    );

    final result = isSaved
        ? await _repository.remove(product.id)
        : await _repository.add(product.id);

    if (result.isErr) {
      // Roll back to exactly what we had before.
      state = AsyncValue<List<ProductSummary>>.data(current);
    }

    return result;
  }
}

final wishlistControllerProvider =
    AsyncNotifierProvider<WishlistController, List<ProductSummary>>(
      WishlistController.new,
    );

/// Fast membership lookup for product cards.
final wishlistIdsProvider = Provider<Set<String>>((ref) {
  final items = ref.watch(wishlistControllerProvider).value;
  if (items == null) return const <String>{};
  return items.map((item) => item.id).toSet();
});
