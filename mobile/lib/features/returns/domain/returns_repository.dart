import '../../../core/errors/result.dart';
import '../../../core/network/api_response.dart';
import 'entities.dart';

/// Customer-facing access to return requests and their refunds.
///
/// Scoped to the signed-in customer by the backend; the client never passes a
/// customer id (specification section 51). Approval, pickup and the refund
/// itself are driven by the merchant and admin from their own surfaces —
/// everything here is read-only.
abstract interface class ReturnsRepository {
  Future<Result<PaginatedList<ReturnSummary>>> fetchReturns({
    ReturnStatus? status,
    int page = 1,
  });

  Future<Result<ReturnDetail>> fetchReturn(String id);
}
