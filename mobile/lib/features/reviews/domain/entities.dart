import 'package:flutter/foundation.dart';

/// The merchant's public reply to a review (specification section 20).
///
/// A merchant may answer a review but never alter its rating, so this is a
/// separate body of text and carries no score of its own.
@immutable
class MerchantResponse {
  const MerchantResponse({
    required this.body,
    required this.respondedAt,
    this.merchantName,
  });

  final String body;
  final DateTime respondedAt;
  final String? merchantName;
}

/// One customer review (specification section 20).
@immutable
class Review {
  const Review({
    required this.id,
    required this.rating,
    required this.createdAt,
    this.title,
    this.body,
    this.authorName,
    this.authorAvatarUrl,
    this.isVerifiedPurchase = false,
    this.photoUrls = const <String>[],
    this.variantLabel,
    this.merchantResponse,
  });

  final String id;

  /// 1 to 5. The server is the authority; the client only renders it.
  final int rating;
  final DateTime createdAt;
  final String? title;
  final String? body;
  final String? authorName;
  final String? authorAvatarUrl;

  /// Set by the backend from the order history, never by the client.
  final bool isVerifiedPurchase;
  final List<String> photoUrls;
  final String? variantLabel;
  final MerchantResponse? merchantResponse;
}

/// Why something is being reported (specification sections 8 and 20).
///
/// Sent as a stable code so moderation and reporting never parse a translated
/// sentence — the same rule as [CancelReason].
enum ReportReason {
  counterfeit('COUNTERFEIT'),
  prohibited('PROHIBITED'),
  misleading('MISLEADING'),
  offensive('OFFENSIVE'),
  spam('SPAM'),
  other('OTHER');

  const ReportReason(this.apiValue);

  final String apiValue;
}
