import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/api_endpoints.dart';
import '../../../core/errors/failure.dart';
import '../../../core/providers/core_providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../orders/presentation/orders_providers.dart';

/// One store in an order that has arrived and is waiting to be rated.
@immutable
class StoreToRate {
  const StoreToRate({required this.id, required this.storeName});

  final String id;
  final String storeName;
}

/// A delivered order the shopper has not answered for yet.
///
/// One order, one sheet, however many stores were in it: a separate popup per
/// store is how a shopper learns to dismiss popups without reading them.
@immutable
class OrderToRate {
  const OrderToRate({
    required this.orderId,
    required this.orderNumber,
    required this.stores,
  });

  final String orderId;
  final String orderNumber;
  final List<StoreToRate> stores;
}

/// The order to ask about when the app opens, or null when there is none.
///
/// The server decides: the oldest delivered order that has not been rated and
/// has not already been put off three times. Asking is not the app's memory
/// to keep - it has to survive the app closing, and it belongs to the
/// account, not the phone.
final orderToRateProvider = FutureProvider<OrderToRate?>((ref) async {
  if (!ref.watch(isAuthenticatedProvider)) return null;
  ref.watch(accountIdProvider);

  final result = await ref
      .watch(apiClientProvider)
      .get<OrderToRate?>(
        ApiEndpoints.ratingDue,
        decoder: (envelope) {
          final json = envelope.dataAsMap;
          final id = json['orderId'];
          if (id == null) return null;
          return OrderToRate(
            orderId: '$id',
            orderNumber: '${json['orderNumber'] ?? ''}',
            stores: [
              for (final store in (json['stores'] as List? ?? const []))
                StoreToRate(
                  id: '${(store as Map)['id']}',
                  storeName: '${store['storeName'] ?? ''}',
                ),
            ],
          );
        },
      );
  return result.valueOrNull;
});

/// The shopper's answers to the rating sheet.
class RateOrder {
  const RateOrder(this._ref);

  final Ref _ref;

  /// Stars for each store, and one comment for the whole order.
  Future<Failure?> rate({
    required String orderId,
    required Map<String, int> stars,
    String? comment,
  }) => _send(orderId, ApiEndpoints.rateOrder(orderId), <String, dynamic>{
    'received': true,
    'ratings': stars,
    'comment': ?comment,
  });

  /// "Yes, it arrived", saved at once: the sheet only moved on to the
  /// stars and kept nothing, so closing it there left the order unanswered
  /// and it was asked again at every opening (the tester). The stars, when
  /// given, follow with [rate].
  Future<Failure?> arrived(String orderId) => _send(
    orderId,
    ApiEndpoints.rateOrder(orderId),
    const <String, dynamic>{'received': true},
  );

  /// "Not yet": nothing to rate, and the stores are told so they can call.
  Future<Failure?> notArrived(String orderId) => _send(
    orderId,
    ApiEndpoints.rateOrder(orderId),
    <String, dynamic>{'received': false},
  );

  /// Put off. The sheet comes back next time, up to three times in all.
  Future<Failure?> notNow(String orderId) => _send(
    orderId,
    ApiEndpoints.skipRating(orderId),
    const <String, dynamic>{},
  );

  Future<Failure?> _send(
    String orderId,
    String path,
    Map<String, dynamic> body,
  ) async {
    final result = await _ref.read(apiClientProvider).command(path, data: body);
    _ref
      ..invalidate(orderToRateProvider)
      // An order page already open asks no more once this is answered.
      ..invalidate(orderDetailProvider(orderId));
    return result.failureOrNull;
  }
}

final rateOrderProvider = Provider<RateOrder>(RateOrder.new);
