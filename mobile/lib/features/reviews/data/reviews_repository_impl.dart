import '../../../core/config/api_endpoints.dart';
import '../../../core/errors/result.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_response.dart';
import '../../../core/utils/json_reader.dart';
import '../domain/entities.dart';
import '../domain/reviews_repository.dart';

class ReviewMappers {
  const ReviewMappers._();

  static Review review(Map<String, dynamic> json) {
    final responseJson = Json.objectOrNull(json, const [
      'merchantResponse',
      'response',
      'reply',
    ]);

    return Review(
      id: Json.str(json, const ['id', 'reviewId']),
      // A rating outside 1-5 would break the star row, so it is clamped here
      // rather than trusted.
      rating: Json.integer(json, const [
        'rating',
        'stars',
        'score',
      ]).clamp(0, 5).toInt(),
      createdAt:
          Json.date(json, const ['createdAt', 'reviewedAt', 'date']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      title: Json.strOrNull(json, const ['title', 'headline']),
      body: Json.strOrNull(json, const ['body', 'comment', 'text']),
      authorName: Json.strOrNull(json, const [
        'authorName',
        'customerName',
        'userName',
        'author',
      ]),
      authorAvatarUrl: Json.strOrNull(json, const [
        'authorAvatarUrl',
        'avatarUrl',
      ]),
      isVerifiedPurchase: Json.boolean(json, const [
        'isVerifiedPurchase',
        'verifiedPurchase',
        'verified',
      ]),
      photoUrls: Json.strings(json, const ['photos', 'images', 'media']),
      variantLabel: Json.strOrNull(json, const ['variantLabel', 'variant']),
      merchantResponse: responseJson == null
          ? null
          : merchantResponse(responseJson),
    );
  }

  static MerchantResponse merchantResponse(Map<String, dynamic> json) =>
      MerchantResponse(
        body: Json.str(json, const ['body', 'comment', 'text']),
        respondedAt:
            Json.date(json, const ['respondedAt', 'createdAt', 'date']) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        merchantName: Json.strOrNull(json, const [
          'merchantName',
          'storeName',
          'author',
        ]),
      );
}

class ReviewsRepositoryImpl implements ReviewsRepository {
  const ReviewsRepositoryImpl(this.client);

  final ApiClient client;

  @override
  Future<Result<PaginatedList<Review>>> fetchMerchantReviews(
    String merchantId, {
    int page = 1,
  }) {
    return client.getPage<Review>(
      ApiEndpoints.merchantReviews(merchantId),
      page: page,
      itemDecoder: ReviewMappers.review,
    );
  }

  @override
  Future<Result<void>> reportReview({
    required String reviewId,
    required String reason,
    String? description,
  }) {
    return client.command(
      ApiEndpoints.reportReview(reviewId),
      data: <String, dynamic>{'reason': reason, 'description': ?description},
    );
  }
}
