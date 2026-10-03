import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/api_endpoints.dart';
import '../../../core/location/governorate.dart';
import '../../../core/providers/core_providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../catalog/domain/product_query.dart';
import '../data/home_repository_impl.dart';
import '../domain/entities.dart';
import '../domain/home_repository.dart';

final homeRepositoryProvider = Provider<HomeRepository>((ref) {
  ref.watch(accountIdProvider);
  return HomeRepositoryImpl(ref.watch(apiClientProvider));
});

/// The configured home page.
///
/// Refetched on pull-to-refresh and whenever the signed-in user changes, since
/// recommendations and "recently viewed" are personalized server-side.
final homeFeedProvider = FutureProvider<List<HomeSection>>((ref) async {
  return (await ref.watch(homeRepositoryProvider).fetchHomeFeed()).unwrap();
});

/// Home's city chips: every city with an open, approved store. Their own
/// list, not the stores rail's, which shows only the featured stores and
/// can be left out altogether (API_CONTRACT.md 6.11).
final storeCitiesProvider = FutureProvider<List<Governorate>>((ref) async {
  final result = await ref
      .watch(apiClientProvider)
      .get<List<Governorate>>(
        ApiEndpoints.storeCities,
        decoder: (envelope) => [
          for (final value in envelope.data as List<dynamic>? ?? const [])
            ?Governorate.fromApi(value),
        ],
      );
  return result.unwrap();
});

/// What Home's grid of every product shows: the city chip picked, and what
/// its Filters sheet set. Every city and no filters to begin with.
class HomeProductsController extends Notifier<ProductQuery> {
  @override
  ProductQuery build() {
    // A city or filter one account picked is not the next one's.
    ref.watch(accountIdProvider);
    return const ProductQuery();
  }

  /// Null is "All cities".
  void selectCity(Governorate? city) => state = city == null
      ? state.copyWith(clearGovernorate: true)
      : state.copyWith(governorate: city.apiValue);

  void applyFilters(ProductQuery filtered) => state = filtered;
}

final homeProductsControllerProvider =
    NotifierProvider<HomeProductsController, ProductQuery>(
      HomeProductsController.new,
    );

/// The query the grid asks with: the controller's, plus the shopper's own
/// city, so each card can say whether it can be delivered to them.
final homeProductsQueryProvider = Provider<ProductQuery>(
  (ref) => ref
      .watch(homeProductsControllerProvider)
      .copyWith(deliverTo: ref.watch(shopperCityProvider)?.apiValue),
);
