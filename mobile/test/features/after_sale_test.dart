import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/features/orders/data/orders_repository_impl.dart';
import 'package:saba_marketplace/features/orders/domain/entities.dart';
import 'package:saba_marketplace/features/returns/data/returns_repository_impl.dart';
import 'package:saba_marketplace/features/returns/domain/entities.dart';

/// Phase 4 — G5 returns list, G6 invoice, G7 cancel reason.

void main() {
  group('ReturnStatus', () {
    test('parses every state in specification section 19', () {
      expect(ReturnStatus.fromApi('REQUESTED'), ReturnStatus.requested);
      expect(ReturnStatus.fromApi('APPROVED'), ReturnStatus.approved);
      expect(ReturnStatus.fromApi('REJECTED'), ReturnStatus.rejected);
      expect(ReturnStatus.fromApi('PICKUP'), ReturnStatus.pickup);
      expect(ReturnStatus.fromApi('RECEIVED'), ReturnStatus.received);
      expect(
        ReturnStatus.fromApi('REFUND_PENDING'),
        ReturnStatus.refundPending,
      );
      expect(ReturnStatus.fromApi('REFUNDED'), ReturnStatus.refunded);
      expect(ReturnStatus.fromApi('CLOSED'), ReturnStatus.closed);
    });

    test('accepts a hyphenated or lowercase spelling', () {
      expect(
        ReturnStatus.fromApi('refund-pending'),
        ReturnStatus.refundPending,
      );
      expect(ReturnStatus.fromApi('pickup_scheduled'), ReturnStatus.pickup);
    });

    test('an unrecognised state does not crash a screen', () {
      expect(ReturnStatus.fromApi('SOMETHING_NEW'), ReturnStatus.unknown);
      expect(ReturnStatus.fromApi(null), ReturnStatus.unknown);
    });

    test('apiValue round-trips, including the underscored one', () {
      for (final status in ReturnStatus.values) {
        if (status == ReturnStatus.unknown) continue;
        expect(ReturnStatus.fromApi(status.apiValue), status);
      }
    });

    test('rejected leaves the progress trail', () {
      expect(ReturnStatus.progression, isNot(contains(ReturnStatus.rejected)));
      expect(ReturnStatus.rejected.isFinal, isTrue);
      expect(ReturnStatus.requested.isFinal, isFalse);
    });
  });

  group('RefundStatus', () {
    test('treats the server spellings of "done" as completed', () {
      for (final value in <String>['COMPLETED', 'REFUNDED', 'SUCCEEDED']) {
        expect(RefundStatus.fromApi(value), RefundStatus.completed);
      }
    });

    test('an unknown value is not silently reported as completed', () {
      expect(RefundStatus.fromApi('WEIRD'), RefundStatus.unknown);
    });
  });

  group('ReturnMappers', () {
    final json = <String, dynamic>{
      'id': 'ret-1',
      'orderId': 'ord-1',
      'orderNumber': 'SB-100001',
      'status': 'REFUND_PENDING',
      'requestedAt': '2026-09-01T10:00:00.000Z',
      'reason': 'DAMAGED',
      'description': 'Screen cracked',
      'currencyCode': 'JOD',
      'items': [
        <String, dynamic>{
          'orderItemId': 'oi-1',
          'name': 'Phone',
          'quantity': 2,
          'refundAmount': 300,
        },
      ],
      'refund': <String, dynamic>{
        'amount': 300,
        'currency': 'JOD',
        'status': 'PENDING',
        'method': 'Visa ending 4242',
        'expectedAt': '2026-09-08T10:00:00.000Z',
      },
      'timeline': [
        <String, dynamic>{
          'status': 'REQUESTED',
          'occurredAt': '2026-09-01T10:00:00.000Z',
        },
      ],
      'photos': <String>['a.jpg'],
    };

    test('maps a full detail payload', () {
      final detail = ReturnMappers.detail(json);
      expect(detail.id, 'ret-1');
      expect(detail.status, ReturnStatus.refundPending);
      expect(detail.items.single.quantity, 2);
      expect(detail.totalQuantity, 2);
      expect(detail.refund?.amount, 300);
      expect(detail.refund?.status, RefundStatus.pending);
      expect(detail.refund?.currencyCode, 'JOD');
      expect(detail.timeline, hasLength(1));
      expect(detail.photoUrls, <String>['a.jpg']);
    });

    test('a return with no refund yet maps to a null refund', () {
      final withoutRefund = Map<String, dynamic>.from(json)..remove('refund');
      expect(ReturnMappers.detail(withoutRefund).refund, isNull);
    });

    test('a sparse payload does not throw', () {
      final detail = ReturnMappers.detail(<String, dynamic>{'id': 'r'});
      expect(detail.id, 'r');
      expect(detail.items, isEmpty);
      expect(detail.status, ReturnStatus.unknown);
    });

    test('summary reads the refund amount and item count', () {
      final summary = ReturnMappers.summary(<String, dynamic>{
        'id': 'ret-2',
        'orderNumber': 'SB-2',
        'status': 'REFUNDED',
        'itemCount': 3,
        'refundAmount': 50,
      });
      expect(summary.status, ReturnStatus.refunded);
      expect(summary.itemCount, 3);
      expect(summary.refundAmount, 50);
    });
  });

  group('Invoice', () {
    final json = <String, dynamic>{
      'orderId': 'ord-1',
      'orderNumber': 'SB-100001',
      'invoiceNumber': 'INV-SB-100001',
      'issuedAt': '2026-09-01T10:00:00.000Z',
      'lines': [
        <String, dynamic>{
          'description': 'Phone',
          'quantity': 2,
          'unitPrice': 100,
          'total': 200,
        },
      ],
      'subtotal': 200,
      'shipping': 5,
      'tax': 10,
      'discount': 15,
      'total': 200,
      'currencyCode': 'JOD',
      'paymentStatus': 'PAID',
    };

    test('maps the server figures', () {
      final invoice = OrderMappers.invoice(json);
      expect(invoice.reference, 'INV-SB-100001');
      expect(invoice.lines.single.total, 200);
      expect(invoice.subtotal, 200);
      expect(invoice.shipping, 5);
      expect(invoice.paymentStatus, PaymentStatus.paid);
    });

    test('never recomputes the total from its lines (section 16)', () {
      // Deliberately inconsistent: a historical invoice must still report what
      // was charged, not what the current figures would add up to.
      final odd = Map<String, dynamic>.from(json)..['total'] = 999;
      expect(OrderMappers.invoice(odd).total, 999);
    });

    test('falls back to the order number when there is no invoice number', () {
      final noNumber = Map<String, dynamic>.from(json)..remove('invoiceNumber');
      expect(OrderMappers.invoice(noNumber).reference, 'SB-100001');
    });

    test('a sparse payload does not throw', () {
      final invoice = OrderMappers.invoice(<String, dynamic>{'orderId': 'o'});
      expect(invoice.lines, isEmpty);
      expect(invoice.total, 0);
    });
  });

  group('CancelReason', () {
    test('every reason carries a stable code, not a translated sentence', () {
      expect(CancelReason.changedMind.apiValue, 'CHANGED_MIND');
      expect(CancelReason.other.apiValue, 'OTHER');
      for (final reason in CancelReason.values) {
        expect(reason.apiValue, matches(RegExp(r'^[A-Z_]+$')));
      }
    });

    test('codes are unique', () {
      final codes = CancelReason.values.map((r) => r.apiValue).toSet();
      expect(codes, hasLength(CancelReason.values.length));
    });
  });
}
