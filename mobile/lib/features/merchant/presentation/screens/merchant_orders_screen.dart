import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/location/governorate_picker.dart';
import '../../../../core/providers/paged_state.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/filter_chip_row.dart';
import '../../../../core/widgets/paged_list_view.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/skeletons.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../orders/presentation/widgets/order_card.dart';
import '../../../returns/domain/entities.dart';
import '../../../returns/presentation/widgets/return_status_chip.dart';
import '../../domain/entities.dart';
import '../merchant_order_actions.dart';
import '../merchant_providers.dart';
import '../widgets/merchant_widgets.dart';
import '../../../../core/widgets/saba_nav_bar.dart';

/// One tab of the fulfilment queue.
///
/// Four buckets, not a tab per status. A merchant does not think "is this
/// CONFIRMED or PROCESSING" — they think "what do I have to do today". So the six-state
/// workflow is grouped by the action it waits on: something to answer,
/// something to pack, something on its way, something done.
///
/// The workflow itself is untouched. This is only how it is shown.
class _Bucket {
  const _Bucket(this.label, this.statuses);

  final String Function(BuildContext) label;
  final List<String> statuses;
}

final List<_Bucket> _buckets = <_Bucket>[
  _Bucket((context) => context.l10n.toConfirm, const <String>['PENDING']),
  _Bucket((context) => context.l10n.preparing, const <String>[
    'CONFIRMED',
    'PROCESSING',
  ]),
  // On the way, and done, apart: a delivered order stayed under "Shipped"
  // and its number never dropped (BUGS.md 56).
  _Bucket((context) => context.l10n.orderStatusShipped, const <String>[
    'SHIPPED',
  ]),
  _Bucket((context) => context.l10n.orderStatusDelivered, const <String>[
    'DELIVERED',
  ]),
  // Declined, cancelled by the shopper, or refused at the door: in no tab,
  // a store could not find them again (M4). Each card says which.
  _Bucket((context) => context.l10n.orderStatusCancelled, const <String>[
    'CANCELLED',
    'REFUSED',
  ]),
  // What shoppers sent back. A return lived only inside its order's screen,
  // and nothing in this list said one was waiting, so stores never answered
  // them. Its number counts the ones waiting for the store.
  _Bucket((context) => context.l10n.returns, const <String>[_returnsBucket]),
];

/// The returns tab's key, and the server's count of returns waiting for the store.
const String _returnsBucket = 'RETURNS';

class MerchantOrdersScreen extends ConsumerStatefulWidget {
  const MerchantOrdersScreen({super.key, this.initialStatus});

  /// Opens on one bucket, so a dashboard row lands on the orders it named.
  final String? initialStatus;

  @override
  ConsumerState<MerchantOrdersScreen> createState() =>
      _MerchantOrdersScreenState();
}

class _MerchantOrdersScreenState extends ConsumerState<MerchantOrdersScreen> {
  late int _selected = () {
    final wanted = widget.initialStatus?.toUpperCase();
    if (wanted == null) return 0;
    final index = _buckets.indexWhere((b) => b.statuses.contains(wanted));
    // A status no bucket holds used to fall through to "To confirm" without
    // a word, which is how a row promising returns showed new orders. The
    // fallback stays for release builds; in debug and in tests it is loud,
    // so the next caller that links to a queue that does not exist finds out
    // before a merchant does.
    assert(
      index >= 0,
      'No order bucket holds status $wanted, so this link would silently '
      'open "To confirm". Add a bucket or do not link here.',
    );
    return index < 0 ? 0 : index;
  }();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final counts = ref.watch(merchantOrderCountsProvider);

    // A pill carries its number only when the server actually sent one. A
    // silent "0" on a bucket that was never counted is worse than no number.
    String labelFor(_Bucket bucket) {
      final label = bucket.label(context);
      final total = counts.whenOrNull(
        data: (values) => bucket.statuses.fold<int>(
          0,
          (sum, status) => sum + (values[status] ?? 0),
        ),
      );
      return total == null ? label : '$label · $total';
    }

    return Scaffold(
      body: Column(
        children: [
          PageTitle(title: l10n.merchantOrders),
          const SizedBox(height: AppSpacing.lg),
          TextFilterChips(
            labels: [for (final bucket in _buckets) labelFor(bucket)],
            selectedIndex: _selected,
            onSelected: (index) => setState(() => _selected = index),
          ),
          const SizedBox(height: AppSpacing.md + 2),
          Expanded(
            child: _buckets[_selected].statuses.contains(_returnsBucket)
                ? const _ReturnList()
                : _OrderList(bucket: _buckets[_selected]),
          ),
          // Only under the bucket that can decline. What a Decline costs -
          // an immediate refund and a mark against the store - is said
          // before it is pressed, not discovered afterwards.
          if (_selected == 0)
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.screenGutter,
                0,
                AppSpacing.screenGutter,
                SabaNavBar.clearance(context) - AppSpacing.xxl,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SabaIcon(
                    SabaIcons.info,
                    size: AppSizes.iconSm,
                    color: context.market.textMuted,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      l10n.declineNote,
                      style: context.textStyles.labelSmall,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _OrderList extends ConsumerStatefulWidget {
  const _OrderList({required this.bucket});

  final _Bucket bucket;

  @override
  ConsumerState<_OrderList> createState() => _OrderListState();
}

class _OrderListState extends ConsumerState<_OrderList> {
  /// Orders with a change in flight, so the buttons that started it stop
  /// taking taps. Without it a second tap re-ran the *same* transition —
  /// `order.status` is still the stale pre-request value — and at the
  /// shipping step that put a second tracking sheet over the first.
  final Set<String> _busy = <String>{};

  String get _query => widget.bucket.statuses.join(',');

  Future<void> _run(
    MerchantOrderRow order,
    Future<void> Function() action,
  ) async {
    if (_busy.contains(order.id)) return;
    setState(() => _busy.add(order.id));
    await action();
    if (!mounted) return;
    setState(() => _busy.remove(order.id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(merchantOrdersProvider(_query));
    final notifier = ref.read(merchantOrdersProvider(_query).notifier);

    return AsyncStateView<PagedState<MerchantOrderRow>>(
      value: state,
      onRetry: () => ref.invalidate(merchantOrdersProvider(_query)),
      loadingBuilder: (_) => const ListSkeleton(itemHeight: 180),
      builder: (paged) => PagedListView<MerchantOrderRow>(
        state: paged,
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          0,
          AppSpacing.screenGutter,
          SabaNavBar.clearance(context),
        ),
        separatorHeight: AppSpacing.md,
        onLoadMore: notifier.loadMore,
        onRefresh: notifier.refresh,
        onRetryLoadMore: notifier.retryLoadMore,
        emptyState: EmptyStateView(
          title: l10n.emptyOrders,
          icon: SabaIcons.receipt,
        ),
        itemBuilder: (context, order, _) => _QueuedOrder(
          order: order,
          isBusy: _busy.contains(order.id),
          onOpen: () =>
              context.push(AppRoutes.merchantOrderDetailPath(order.id)),
          onAdvance: () =>
              _run(order, () => advanceMerchantOrder(context, ref, order)),
          onDecline: () =>
              _run(order, () => declineMerchantOrder(context, ref, order)),
        ),
      ),
    );
  }
}

/// One order in the queue, on the same [OrderCard] as the shopper's.
///
/// The card carries what the decision needs: who it is for, where it goes,
/// what is in it, and how it was paid. An item count and a total is enough to
/// recognise an order and not enough to answer one.
class _QueuedOrder extends StatelessWidget {
  const _QueuedOrder({
    required this.order,
    required this.onOpen,
    required this.onAdvance,
    required this.onDecline,
    this.isBusy = false,
  });

  final MerchantOrderRow order;
  final VoidCallback onOpen;
  final VoidCallback onAdvance;
  final VoidCallback onDecline;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isNew = order.status.toUpperCase() == 'PENDING';
    final next = MerchantOrderStatus.next(order.status);

    final who = [
      if (order.customerName != null) order.customerName!,
      // "Karrada, Baghdad": the area, and the city it is in.
      if ([
            order.customerArea,
            order.customerGovernorate?.label(context),
          ].nonNulls.join(l10n.comma)
          case final place when place.isNotEmpty)
        place,
      l10n.counted(order.itemCount, CountNoun.item),
    ].join('  ·  ');

    return OrderCard(
      orderNumber: order.orderNumber,
      // An unanswered order says how long it has waited, because "7 orders"
      // and "one of them since Tuesday" are different problems. Everything
      // else shows its state.
      badge: isNew
          ? _WaitingBadge(since: order.placedAt)
          : StatusBadge(
              label: MerchantOrderStatus.label(context, order.status),
              tone: MerchantOrderStatus.tone(order.status),
              compact: true,
            ),
      facts: [who],
      items: [for (final item in order.items) (item.name, item.quantity)],
      // Nothing to collect for an order called off or refused (BUGS 205).
      footnote:
          const {'CANCELLED', 'REFUSED'}.contains(order.status.toUpperCase())
          ? null
          : Text(
              l10n.collectInCash,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textStyles.labelSmall,
            ),
      total: order.total,
      currencyCode: order.currencyCode,
      onTap: onOpen,
      actions: next == null
          ? null
          : Row(
              children: [
                Expanded(
                  flex: 2,
                  child: AppButton(
                    label: isNew
                        ? l10n.confirm
                        : '${l10n.nextStatus}: '
                              '${MerchantOrderStatus.label(context, next)}',
                    size: AppButtonSize.small,
                    isLoading: isBusy,
                    onPressed: onAdvance,
                  ),
                ),
                // Decline exists only where there is still something to
                // refuse. Offering it after the parcel has shipped would be
                // a button that cannot do what it says.
                if (isNew) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: AppButton(
                      label: l10n.decline,
                      // It cancels the order: red, and quiet beside Confirm.
                      variant: AppButtonVariant.dangerText,
                      size: AppButtonSize.small,
                      onPressed: isBusy ? null : onDecline,
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

/// "Waiting 3h" - how long an unanswered order has sat there, on the same
/// badge as every other status.
class _WaitingBadge extends StatelessWidget {
  const _WaitingBadge({required this.since});

  final DateTime since;

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(since);

    return StatusBadge(
      // Whole words: it read "19m" in English and "1ي" in Arabic.
      label: context.l10n.waitingFor(elapsed),
      // Past a day unanswered, it stops being a note and becomes a problem.
      tone: elapsed.inHours >= 24 ? StatusTone.negative : StatusTone.caution,
      compact: true,
    );
  }
}

/// The store's returns, newest first. Each opens its order, where the
/// answer buttons are: approve or decline, then "cash handed back".
class _ReturnList extends ConsumerWidget {
  const _ReturnList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(merchantReturnsProvider);
    final notifier = ref.read(merchantReturnsProvider.notifier);

    return AsyncStateView<PagedState<MerchantReturnRow>>(
      value: state,
      onRetry: () => ref.invalidate(merchantReturnsProvider),
      loadingBuilder: (_) => const ListSkeleton(itemHeight: 120),
      builder: (paged) => PagedListView<MerchantReturnRow>(
        state: paged,
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          0,
          AppSpacing.screenGutter,
          SabaNavBar.clearance(context),
        ),
        separatorHeight: AppSpacing.md,
        onLoadMore: notifier.loadMore,
        onRefresh: notifier.refresh,
        onRetryLoadMore: notifier.retryLoadMore,
        emptyState: EmptyStateView(
          title: l10n.emptyStoreReturns,
          message: l10n.emptyStoreReturnsMessage,
          icon: SabaIcons.refresh,
        ),
        itemBuilder: (context, row, _) => _StoreReturnCard(
          row: row,
          onOpen: () =>
              context.push(AppRoutes.merchantOrderDetailPath(row.storeOrderId)),
        ),
      ),
    );
  }
}

/// One return, as the shopper's list shows it, plus who sent it and, while
/// it waits on the store, what the store has to do next.
class _StoreReturnCard extends StatelessWidget {
  const _StoreReturnCard({required this.row, required this.onOpen});

  final MerchantReturnRow row;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final market = context.market;
    final locale = l10n.locale.toLanguageTag();
    final request = row.request;
    final radius = BorderRadius.circular(AppRadius.card);
    final next = switch (request.status) {
      ReturnStatus.requested => l10n.returnNeedsAnswer,
      ReturnStatus.approved => l10n.returnNeedsCash,
      _ => null,
    };

    return Material(
      color: context.colors.surface,
      borderRadius: radius,
      child: InkWell(
        onTap: onOpen,
        borderRadius: radius,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md + 2),
          decoration: BoxDecoration(
            // A return waiting on the store stands out from the answered ones.
            border: Border.all(
              color: next == null ? market.border : market.warning,
            ),
            borderRadius: radius,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppNetworkImage(
                    url: request.previewImageUrl,
                    width: 64,
                    height: 64,
                    radius: AppRadius.md,
                    fallbackIcon: SabaIcons.box,
                  ),
                  const SizedBox(width: AppSpacing.md + 2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                request.orderNumber,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.textStyles.titleMedium
                                    ?.copyWith(fontSize: 14.5),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            ReturnStatusChip(
                              status: request.status,
                              compact: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          [
                            if (row.customerName case final name?
                                when name.isNotEmpty)
                              name,
                            Formatters.date(request.requestedAt, locale: locale),
                            l10n.counted(request.itemCount, CountNoun.item),
                          ].join('  ·  '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.labelSmall,
                        ),
                        // What the store hands back in cash. A declined return
                        // hands back nothing, so it shows no amount.
                        if (request.status != ReturnStatus.rejected &&
                            request.refundAmount != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l10n.refundAmount,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.textStyles.labelSmall,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Text(
                                Formatters.money(
                                  request.refundAmount!,
                                  locale: locale,
                                  currencyCode: request.currencyCode,
                                ),
                                style: context.textStyles.titleMedium
                                    ?.copyWith(fontSize: 15),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (next != null) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm + 2,
                  ),
                  decoration: BoxDecoration(
                    color: market.warningSoft,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    children: [
                      SabaIcon(
                        SabaIcons.info,
                        size: AppSizes.iconSm,
                        color: market.warning,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          next,
                          style: context.textStyles.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      SabaIcon(
                        context.isRtl
                            ? SabaIcons.chevronLeft
                            : SabaIcons.chevronRight,
                        size: AppSizes.iconSm,
                        color: market.textMuted,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
