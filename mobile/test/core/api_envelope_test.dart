import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/network/api_response.dart';

void main() {
  group('ApiEnvelope', () {
    test('parses the documented success envelope', () {
      final envelope = ApiEnvelope.fromResponse(<String, dynamic>{
        'success': true,
        'message': 'Request successful',
        'data': <String, dynamic>{'id': '1'},
        'meta': <String, dynamic>{'page': 2, 'perPage': 20, 'total': 45},
      });

      expect(envelope.success, isTrue);
      expect(envelope.message, 'Request successful');
      expect(envelope.dataAsMap['id'], '1');
      expect(envelope.pagination.page, 2);
      expect(envelope.pagination.total, 45);
      expect(envelope.pagination.totalPages, 3);
      expect(envelope.pagination.hasNextPage, isTrue);
    });

    test('reports a 2xx body with success:false as a failure', () {
      final envelope = ApiEnvelope.fromResponse(<String, dynamic>{
        'success': false,
        'message': 'Coupon expired',
      });

      expect(envelope.success, isFalse);
      expect(envelope.message, 'Coupon expired');
    });

    test('accepts a bare object as the payload', () {
      final envelope = ApiEnvelope.fromResponse(<String, dynamic>{
        'id': '42',
        'name': 'Phone',
      });

      expect(envelope.success, isTrue);
      expect(envelope.dataAsMap['name'], 'Phone');
    });

    test('reads a list from data, or from data.items', () {
      final flat = ApiEnvelope.fromResponse(<String, dynamic>{
        'data': [
          {'id': '1'},
          {'id': '2'},
        ],
      });
      expect(flat.dataAsList, hasLength(2));

      final nested = ApiEnvelope.fromResponse(<String, dynamic>{
        'data': {
          'items': [
            {'id': '1'},
          ],
        },
      });
      expect(nested.dataAsList, hasLength(1));
    });

    test('falls back to empty pagination when meta is absent', () {
      final envelope = ApiEnvelope.fromResponse(<String, dynamic>{
        'data': <Map<String, dynamic>>[],
      });

      expect(envelope.pagination.page, 1);
      expect(envelope.pagination.hasNextPage, isFalse);
    });

    test('derives totalPages when the server omits it', () {
      final meta = PaginationMeta.fromJson(<String, dynamic>{
        'page': 1,
        'perPage': 10,
        'total': 25,
      });

      expect(meta.totalPages, 3);
    });

    test('tolerates numbers sent as strings', () {
      final meta = PaginationMeta.fromJson(<String, dynamic>{
        'page': '3',
        'per_page': '20',
        'total': '100',
      });

      expect(meta.page, 3);
      expect(meta.perPage, 20);
      expect(meta.total, 100);
    });
  });

  group('PaginatedList', () {
    test('append keeps earlier pages and adopts the newest meta', () {
      const first = PaginatedList<String>(
        items: ['a', 'b'],
        meta: PaginationMeta(page: 1, perPage: 2, total: 4, totalPages: 2),
      );
      const second = PaginatedList<String>(
        items: ['c', 'd'],
        meta: PaginationMeta(page: 2, perPage: 2, total: 4, totalPages: 2),
      );

      final combined = first.append(second);

      expect(combined.items, ['a', 'b', 'c', 'd']);
      expect(combined.meta.page, 2);
      expect(combined.hasNextPage, isFalse);
    });
  });
}
