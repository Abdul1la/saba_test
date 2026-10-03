import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/features/reviews/data/reviews_repository_impl.dart';
import 'package:saba_marketplace/features/reviews/domain/entities.dart';

/// G9 — reviews of a store. Products are not reviewed in version 1.

void main() {
  group('ReviewMappers.review', () {
    test('maps a full review including the seller reply', () {
      final review = ReviewMappers.review(<String, dynamic>{
        'id': 'r1',
        'rating': 4,
        'createdAt': '2026-09-01T10:00:00.000Z',
        'body': 'Good',
        'authorName': 'Amina',
        'verified': true,
        'photos': <String>['a.jpg'],
        'merchantResponse': <String, dynamic>{
          'body': 'Thanks',
          'merchantName': 'Nova',
          'respondedAt': '2026-09-02T10:00:00.000Z',
        },
      });

      expect(review.rating, 4);
      expect(review.isVerifiedPurchase, isTrue);
      expect(review.photoUrls, <String>['a.jpg']);
      expect(review.merchantResponse?.merchantName, 'Nova');
    });

    test('clamps a rating outside 1-5 so the star row cannot break', () {
      expect(ReviewMappers.review(<String, dynamic>{'rating': 99}).rating, 5);
      expect(ReviewMappers.review(<String, dynamic>{'rating': -4}).rating, 0);
    });

    test('a sparse payload does not throw', () {
      final review = ReviewMappers.review(<String, dynamic>{'id': 'r'});
      expect(review.photoUrls, isEmpty);
      expect(review.merchantResponse, isNull);
      expect(review.isVerifiedPurchase, isFalse);
    });
  });

  group('report codes', () {
    test('report reasons are stable codes, not translated text', () {
      for (final reason in ReportReason.values) {
        expect(reason.apiValue, matches(RegExp(r'^[A-Z_]+$')));
      }
      expect(
        ReportReason.values.map((r) => r.apiValue).toSet(),
        hasLength(ReportReason.values.length),
      );
    });
  });
}
