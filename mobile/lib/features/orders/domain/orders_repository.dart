import 'package:flutter/foundation.dart';

import '../../../core/errors/result.dart';
import '../../../core/network/api_response.dart';
import 'entities.dart';

/// One line of a return request.
@immutable
class ReturnLine {
  const ReturnLine({required this.orderItemId, required this.quantity});

  final String orderItemId;
  final int quantity;
}

/// Customer-facing order access.
///
/// Every call is scoped to the signed-in customer by the backend; the client
/// never passes a customer id and could not widen the scope if it tried
/// (specification section 51).
abstract interface class OrdersRepository {
  Future<Result<PaginatedList<OrderSummary>>> fetchOrders({
    OrderStatus? status,
    int page = 1,
  });

  Future<Result<Order>> fetchOrder(String id);

  /// The invoice for an order (specification section 15).
  Future<Result<Invoice>> fetchInvoice(String orderId);

  /// [reason] is a stable code (see `CancelReason`); [note] is the customer's
  /// own words, which the backend stores but never parses.
  Future<Result<Order>> cancelOrder({
    required String orderId,
    required String reason,
    String? note,
  });

  /// "Did you receive it?" for one store's part. A no goes to the store,
  /// who calls the shopper about it.
  Future<Result<Order>> confirmReceived({
    required String orderId,
    required String merchantId,
    required bool received,
  });

  /// Opens a return request. Approval, pickup and refund are driven by the
  /// merchant and admin from their own surfaces (specification section 19).
  Future<Result<void>> requestReturn({
    required String orderId,
    required List<ReturnLine> lines,
    required String reason,
    String? description,
  });
}
