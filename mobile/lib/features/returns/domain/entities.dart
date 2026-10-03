import 'package:flutter/foundation.dart';

/// Return lifecycle, exactly the states in specification section 19.
enum ReturnStatus {
  requested,
  approved,
  rejected,
  pickup,
  received,
  refundPending,
  refunded,
  closed,
  unknown;

  static ReturnStatus fromApi(Object? value) =>
      switch (value?.toString().toUpperCase().replaceAll('-', '_')) {
        'REQUESTED' => ReturnStatus.requested,
        'APPROVED' => ReturnStatus.approved,
        'REJECTED' => ReturnStatus.rejected,
        'PICKUP' || 'PICKUP_SCHEDULED' => ReturnStatus.pickup,
        'RECEIVED' => ReturnStatus.received,
        'REFUND_PENDING' => ReturnStatus.refundPending,
        'REFUNDED' => ReturnStatus.refunded,
        'CLOSED' => ReturnStatus.closed,
        _ => ReturnStatus.unknown,
      };

  String get apiValue => switch (this) {
    ReturnStatus.refundPending => 'REFUND_PENDING',
    _ => name.toUpperCase(),
  };

  /// A rejected or closed request is finished; nothing more will happen.
  bool get isFinal =>
      this == ReturnStatus.rejected ||
      this == ReturnStatus.refunded ||
      this == ReturnStatus.closed;

  /// The order the customer sees on the progress trail. Rejected requests
  /// leave the trail, so they are deliberately absent.
  /// v1's steps (API_CONTRACT D18): the store collects the item and hands
  /// the cash back in one visit. Pickup, received and refund pending were
  /// drawn and never happened (the tester).
  static const List<ReturnStatus> progression = <ReturnStatus>[
    ReturnStatus.requested,
    ReturnStatus.approved,
    ReturnStatus.refunded,
  ];
}

/// Where the money is, once a return is approved (specification section 19).
enum RefundStatus {
  pending,
  processing,
  completed,
  failed,
  unknown;

  static RefundStatus fromApi(Object? value) =>
      switch (value?.toString().toUpperCase()) {
        'PENDING' => RefundStatus.pending,
        'PROCESSING' => RefundStatus.processing,
        'COMPLETED' || 'REFUNDED' || 'SUCCEEDED' => RefundStatus.completed,
        'FAILED' => RefundStatus.failed,
        _ => RefundStatus.unknown,
      };
}

@immutable
class ReturnItem {
  const ReturnItem({
    required this.orderItemId,
    required this.name,
    required this.quantity,
    this.imageUrl,
    this.variantLabel,
    this.refundAmount,
  });

  final String orderItemId;
  final String name;
  final int quantity;
  final String? imageUrl;
  final String? variantLabel;
  final num? refundAmount;
}

/// The refund attached to a return, when one has been raised.
@immutable
class RefundRecord {
  const RefundRecord({
    required this.amount,
    required this.currencyCode,
    required this.status,
    this.id,
    this.method,
    this.reference,
    this.processedAt,
    this.expectedAt,
  });

  final num amount;
  final String currencyCode;
  final RefundStatus status;
  final String? id;

  /// How the money goes back: the original card, a wallet, store credit.
  final String? method;
  final String? reference;
  final DateTime? processedAt;

  /// When the customer should expect to see it, if the backend estimates one.
  final DateTime? expectedAt;
}

@immutable
class ReturnTimelineEntry {
  const ReturnTimelineEntry({
    required this.status,
    required this.occurredAt,
    this.note,
  });

  final ReturnStatus status;
  final DateTime occurredAt;
  final String? note;
}

/// One row in the returns list.
@immutable
class ReturnSummary {
  const ReturnSummary({
    required this.id,
    required this.orderId,
    required this.orderNumber,
    required this.status,
    required this.requestedAt,
    required this.itemCount,
    required this.currencyCode,
    this.refundAmount,
    this.previewImageUrl,
  });

  final String id;
  final String orderId;
  final String orderNumber;
  final ReturnStatus status;
  final DateTime requestedAt;
  final int itemCount;
  final String currencyCode;
  final num? refundAmount;
  final String? previewImageUrl;
}

/// A return request in full, including where its refund has got to.
@immutable
class ReturnDetail {
  const ReturnDetail({
    required this.id,
    required this.orderId,
    required this.orderNumber,
    required this.status,
    required this.requestedAt,
    required this.reason,
    required this.items,
    required this.currencyCode,
    this.description,
    this.merchantName,
    this.rejectionReason,
    this.refund,
    this.timeline = const <ReturnTimelineEntry>[],
    this.photoUrls = const <String>[],
  });

  final String id;
  final String orderId;
  final String orderNumber;
  final ReturnStatus status;
  final DateTime requestedAt;
  final String reason;
  final List<ReturnItem> items;
  final String currencyCode;
  final String? description;
  final String? merchantName;

  /// Why the merchant said no. Only meaningful when [status] is rejected.
  final String? rejectionReason;
  final RefundRecord? refund;
  final List<ReturnTimelineEntry> timeline;
  final List<String> photoUrls;

  int get totalQuantity => items.fold(0, (sum, item) => sum + item.quantity);
}

/// Why a customer is cancelling (specification section 19).
///
/// Sent as a stable code so the backend and the admin panel are not parsing a
/// translated sentence; the free-text note travels separately.
/// Why the customer is sending it back.
///
/// The screen used to hold these as bare strings and print them by replacing
/// underscores with spaces, so an Arabic customer chose between "DAMAGED" and
/// "WRONG ITEM". The code the backend stores and the words the customer reads
/// are two different things, exactly as [CancelReason] already had it.
enum ReturnReason {
  damaged('DAMAGED'),
  wrongItem('WRONG_ITEM'),
  notAsDescribed('NOT_AS_DESCRIBED'),
  missingParts('MISSING_PARTS'),
  changedMind('CHANGED_MIND'),
  other('OTHER');

  const ReturnReason(this.apiValue);

  final String apiValue;
}

enum CancelReason {
  changedMind('CHANGED_MIND'),
  foundCheaper('FOUND_CHEAPER'),
  deliveryTooSlow('DELIVERY_TOO_SLOW'),
  orderedByMistake('ORDERED_BY_MISTAKE'),
  other('OTHER');

  const CancelReason(this.apiValue);

  final String apiValue;
}
