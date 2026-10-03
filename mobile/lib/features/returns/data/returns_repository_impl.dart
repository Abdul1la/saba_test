import '../../../core/config/api_endpoints.dart';
import '../../../core/config/app_config.dart';
import '../../../core/errors/result.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_response.dart';
import '../../../core/utils/json_reader.dart';
import '../domain/entities.dart';
import '../domain/returns_repository.dart';

class ReturnMappers {
  const ReturnMappers._();

  static ReturnSummary summary(Map<String, dynamic> json) => ReturnSummary(
    id: Json.str(json, const ['id', 'returnId']),
    orderId: Json.str(json, const ['orderId', 'order']),
    orderNumber: Json.str(json, const ['orderNumber', 'number', 'reference']),
    status: ReturnStatus.fromApi(json['status'] ?? json['returnStatus']),
    requestedAt:
        Json.date(json, const ['requestedAt', 'createdAt', 'date']) ??
        DateTime.fromMillisecondsSinceEpoch(0),
    itemCount: Json.integer(json, const ['itemCount', 'itemsCount']),
    currencyCode: Json.str(json, const [
      'currencyCode',
      'currency',
    ], fallback: AppConfig.fallbackCurrencyCode),
    refundAmount: Json.numberOrNull(json, const [
      'refundAmount',
      'refundTotal',
      'amount',
    ]),
    previewImageUrl: Json.strOrNull(json, const [
      'previewImageUrl',
      'imageUrl',
      'thumbnail',
    ]),
  );

  static ReturnItem item(Map<String, dynamic> json) => ReturnItem(
    orderItemId: Json.str(json, const ['orderItemId', 'itemId', 'id']),
    name: Json.str(json, const ['name', 'productName', 'title']),
    quantity: Json.integer(json, const ['quantity', 'qty']),
    imageUrl: Json.strOrNull(json, const ['imageUrl', 'image', 'thumbnail']),
    variantLabel: Json.strOrNull(json, const ['variantLabel', 'variant']),
    refundAmount: Json.numberOrNull(json, const [
      'refundAmount',
      'amount',
      'total',
    ]),
  );

  static RefundRecord refund(Map<String, dynamic> json) => RefundRecord(
    id: Json.strOrNull(json, const ['id', 'refundId']),
    amount: Json.number(json, const ['amount', 'total', 'refundAmount']),
    currencyCode: Json.str(json, const [
      'currencyCode',
      'currency',
    ], fallback: AppConfig.fallbackCurrencyCode),
    status: RefundStatus.fromApi(json['status'] ?? json['refundStatus']),
    method: Json.strOrNull(json, const ['method', 'refundMethod', 'target']),
    reference: Json.strOrNull(json, const ['reference', 'transactionId']),
    processedAt: Json.date(json, const [
      'processedAt',
      'completedAt',
      'refundedAt',
    ]),
    expectedAt: Json.date(json, const ['expectedAt', 'estimatedAt', 'eta']),
  );

  static ReturnTimelineEntry timelineEntry(Map<String, dynamic> json) =>
      ReturnTimelineEntry(
        status: ReturnStatus.fromApi(json['status']),
        occurredAt:
            Json.date(json, const ['occurredAt', 'createdAt', 'at']) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        note: Json.strOrNull(json, const ['note', 'comment', 'description']),
      );

  static ReturnDetail detail(Map<String, dynamic> json) {
    final refundJson = Json.objectOrNull(json, const ['refund', 'refundInfo']);

    return ReturnDetail(
      id: Json.str(json, const ['id', 'returnId']),
      orderId: Json.str(json, const ['orderId', 'order']),
      orderNumber: Json.str(json, const ['orderNumber', 'number', 'reference']),
      status: ReturnStatus.fromApi(json['status'] ?? json['returnStatus']),
      requestedAt:
          Json.date(json, const ['requestedAt', 'createdAt', 'date']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      reason: Json.str(json, const ['reason', 'returnReason']),
      description: Json.strOrNull(json, const ['description', 'note']),
      merchantName: Json.strOrNull(json, const ['merchantName', 'storeName']),
      rejectionReason: Json.strOrNull(json, const [
        'rejectionReason',
        'rejectedReason',
        'merchantNote',
      ]),
      items: Json.mapList(
        Json.objects(json, const ['items', 'returnItems', 'lines']),
        item,
      ),
      currencyCode: Json.str(json, const [
        'currencyCode',
        'currency',
      ], fallback: AppConfig.fallbackCurrencyCode),
      refund: refundJson == null ? null : refund(refundJson),
      timeline: Json.mapList(
        Json.objects(json, const ['timeline', 'history', 'events']),
        timelineEntry,
      ),
      photoUrls: Json.strings(json, const ['photos', 'images', 'photoUrls']),
    );
  }
}

class ReturnsRepositoryImpl implements ReturnsRepository {
  const ReturnsRepositoryImpl(this.client);

  final ApiClient client;

  @override
  Future<Result<PaginatedList<ReturnSummary>>> fetchReturns({
    ReturnStatus? status,
    int page = 1,
  }) {
    return client.getPage<ReturnSummary>(
      ApiEndpoints.returns,
      page: page,
      queryParameters: <String, dynamic>{
        if (status != null && status != ReturnStatus.unknown)
          'status': status.apiValue,
      },
      itemDecoder: ReturnMappers.summary,
    );
  }

  @override
  Future<Result<ReturnDetail>> fetchReturn(String id) {
    return client.get<ReturnDetail>(
      ApiEndpoints.returnRequest(id),
      decoder: (envelope) => ReturnMappers.detail(envelope.dataAsMap),
    );
  }
}
