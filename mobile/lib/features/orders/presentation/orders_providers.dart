import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/result.dart';
import '../../../core/network/api_response.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/providers/paged_state.dart';
import '../data/orders_repository_impl.dart';
import '../domain/entities.dart';
import '../domain/orders_repository.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../../core/network/live_updates.dart';

final ordersRepositoryProvider = Provider<OrdersRepository>((ref) {
  ref.watch(accountIdProvider);
  return OrdersRepositoryImpl(ref.watch(apiClientProvider));
});

/// Paginated orders for one status tab. `null` means "all".
class OrderListNotifier extends PagedNotifier<OrderSummary> {
  OrderListNotifier(this.status);

  final OrderStatus? status;

  @override
  Future<PagedState<OrderSummary>> build() {
    ref.watch(accountIdProvider);
    ref.watch(liveTopicProvider(LiveTopic.orders));
    return super.build();
  }

  @override
  Future<Result<PaginatedList<OrderSummary>>> fetchPage(int page) {
    return ref
        .read(ordersRepositoryProvider)
        .fetchOrders(status: status, page: page);
  }
}

final orderListProvider =
    AsyncNotifierProvider.family<
      OrderListNotifier,
      PagedState<OrderSummary>,
      OrderStatus?
    >(OrderListNotifier.new);

final orderDetailProvider = FutureProvider.family<Order, String>((
  ref,
  id,
) async {
  ref.watch(liveTopicProvider(LiveTopic.orders));
  return (await ref.watch(ordersRepositoryProvider).fetchOrder(id)).unwrap();
});
