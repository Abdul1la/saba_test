import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/result.dart';
import '../../../core/network/api_response.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/providers/paged_state.dart';
import '../data/reviews_repository_impl.dart';
import '../domain/entities.dart';
import '../domain/reviews_repository.dart';
import '../../auth/presentation/auth_providers.dart';

final reviewsRepositoryProvider = Provider<ReviewsRepository>((ref) {
  ref.watch(accountIdProvider);
  return ReviewsRepositoryImpl(ref.watch(apiClientProvider));
});

/// What shoppers have said about one store.
class MerchantReviewsNotifier extends PagedNotifier<Review> {
  MerchantReviewsNotifier(this.merchantId);

  final String merchantId;

  @override
  Future<PagedState<Review>> build() {
    ref.watch(accountIdProvider);
    return super.build();
  }

  @override
  Future<Result<PaginatedList<Review>>> fetchPage(int page) {
    return ref
        .read(reviewsRepositoryProvider)
        .fetchMerchantReviews(merchantId, page: page);
  }
}

final merchantReviewsProvider =
    AsyncNotifierProvider.family<
      MerchantReviewsNotifier,
      PagedState<Review>,
      String
    >(MerchantReviewsNotifier.new);
