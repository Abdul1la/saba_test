import '../../../core/errors/result.dart';
import '../../../core/network/api_response.dart';
import 'entities.dart';

/// What shoppers have said about a store.
///
/// Products are not reviewed in version 1: a shopper rates the store that
/// delivered their order. Moderation and verified-purchase status belong to
/// the backend; the client renders them and reports intent (section 20).
abstract interface class ReviewsRepository {
  Future<Result<PaginatedList<Review>>> fetchMerchantReviews(
    String merchantId, {
    int page = 1,
  });

  Future<Result<void>> reportReview({
    required String reviewId,
    required String reason,
    String? description,
  });
}
