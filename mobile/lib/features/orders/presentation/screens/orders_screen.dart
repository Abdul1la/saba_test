import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/paged_state.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/filter_chip_row.dart';
import '../../../../core/widgets/paged_list_view.dart';
import '../../../../core/widgets/results_chrome.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/skeletons.dart';
import '../../../returns/presentation/widgets/return_list.dart';
import '../../domain/entities.dart';
import '../orders_providers.dart';
import '../widgets/order_card.dart';
import '../widgets/order_status_chip.dart';
import '../../../../core/widgets/saba_nav_bar.dart';

/// Everything the customer has bought, narrowed by state - and their returns.
///
/// The tab bar is gone. Nine tabs meant nine live lists and a strip of labels
/// scrolling under a line; the design filters one list with a row of pills,
/// which is both its own language and eight fewer provider subscriptions.
///
/// Returns are the last pill. They had a screen of their own behind a text
/// link in this header, which customers did not notice, and the pill row
/// already had "Returned" and "Refunded" - two order states that said a
/// return had happened but not where its refund had got to. One Returns pill
/// shows the requests themselves, each with its status and refund.
class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  /// Null is "all". The rest are the states the specification lists for
  /// customers, in the order an order actually passes through them.
  static const List<OrderStatus?> _filters = <OrderStatus?>[
    null,
    OrderStatus.pending,
    OrderStatus.confirmed,
    OrderStatus.processing,
    OrderStatus.shipped,
    OrderStatus.delivered,
    OrderStatus.cancelled,
  ];

  /// The pill after the order states.
  static final int _returnsIndex = _filters.length;

  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      body: Column(
        children: [
          PageTitle(title: l10n.myOrders),
          const SizedBox(height: AppSpacing.lg),
          TextFilterChips(
            labels: [
              for (final status in _filters)
                status == null
                    ? l10n.orderStatusAll
                    : OrderStatusChip.labelFor(context, status),
              l10n.returns,
            ],
            selectedIndex: _selected,
            onSelected: (index) => setState(() => _selected = index),
          ),
          const SizedBox(height: AppSpacing.md + 2),
          Expanded(
            child: _selected == _returnsIndex
                ? ReturnList(
                    onShowAll: () => setState(() => _selected = _returnsIndex),
                    onShowOrders: () => setState(() => _selected = 0),
                  )
                : _OrderList(
                    status: _filters[_selected],
                    onShowAll: () => setState(() => _selected = 0),
                  ),
          ),
        ],
      ),
    );
  }
}

class _OrderList extends ConsumerWidget {
  const _OrderList({required this.status, required this.onShowAll});

  final OrderStatus? status;

  /// Clears the filter from inside the empty state, so a customer who lands on
  /// an empty "Refunded" is one tap from what they do have.
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(orderListProvider(status));
    final notifier = ref.read(orderListProvider(status).notifier);

    return AsyncStateView<PagedState<OrderSummary>>(
      value: state,
      onRetry: () => ref.invalidate(orderListProvider(status)),
      loadingBuilder: (_) => const ListSkeleton(itemHeight: 104),
      builder: (paged) => PagedListView<OrderSummary>(
        state: paged,
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          0,
          AppSpacing.screenGutter,
          SabaNavBar.clearance(context),
        ),
        onLoadMore: notifier.loadMore,
        onRefresh: notifier.refresh,
        onRetryLoadMore: notifier.retryLoadMore,
        // An empty "Cancelled" is not an empty account. Telling someone with
        // twelve orders that they have none is simply false, so a filtered
        // dead end names the filter and offers to drop it.
        emptyState: status == null
            ? NoResultsView(
                icon: SabaIcons.receipt,
                title: l10n.emptyOrders,
                message: l10n.emptyOrdersMessage,
                actions: [
                  FilledButton(
                    onPressed: () => context.go(AppRoutes.home),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: Text(l10n.startShopping),
                  ),
                ],
              )
            : NoResultsView(
                icon: SabaIcons.receipt,
                title: l10n.emptyFilteredList,
                message: l10n.emptyFilteredListMessage,
                actions: [
                  FilledButton(
                    onPressed: onShowAll,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: Text(l10n.showAll),
                  ),
                ],
              ),
        itemBuilder: (context, order, _) => OrderCard(
          orderNumber: order.orderNumber,
          badge: OrderStatusChip(status: order.status, compact: true),
          facts: [
            // Date and count on one muted line: two facts that are only ever
            // read together.
            '${Formatters.date(order.placedAt, locale: context.l10n.locale.toLanguageTag())}'
                '  ·  ${context.l10n.counted(order.itemCount, CountNoun.item)}',
            // On a multi-vendor marketplace, who is shipping this is part of
            // knowing what the order is.
            if (order.merchantNames.isNotEmpty) order.merchantNames.join(' · '),
          ],
          showPhoto: true,
          imageUrl: order.previewImageUrl,
          footnote: PaymentStatusLabel(
            status: order.paymentStatus,
            isCashOnDelivery: order.isCashOnDelivery,
          ),
          total: order.total,
          currencyCode: order.currencyCode,
          onTap: () => context.push(AppRoutes.orderDetailPath(order.id)),
        ),
      ),
    );
  }
}
