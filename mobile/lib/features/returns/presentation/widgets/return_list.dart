import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/paged_state.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/paged_list_view.dart';
import '../../../../core/widgets/results_chrome.dart';
import '../../../../core/widgets/skeletons.dart';
import '../../domain/entities.dart';
import '../returns_providers.dart';
import 'return_status_chip.dart';
import '../../../../core/widgets/saba_nav_bar.dart';

/// The customer's return requests and where each refund has got to.
///
/// Read-only: approval, pickup and the refund itself are the merchant's and
/// admin's to drive (specification section 19). Shown under the Returns chip
/// on My orders - a return is part of an order's life, and it had its own
/// screen behind a text link in the header that customers did not find.
class ReturnList extends ConsumerWidget {
  const ReturnList({
    super.key,
    this.status,
    required this.onShowAll,
    required this.onShowOrders,
  });

  /// Null for every return.
  final ReturnStatus? status;

  /// Clears a status filter from inside its empty state.
  final VoidCallback onShowAll;

  /// "No returns yet" offers the orders, where a return is started from.
  final VoidCallback onShowOrders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(returnListProvider(status));
    final notifier = ref.read(returnListProvider(status).notifier);

    return AsyncStateView<PagedState<ReturnSummary>>(
      value: state,
      onRetry: () => ref.invalidate(returnListProvider(status)),
      loadingBuilder: (_) => const ListSkeleton(itemHeight: 104),
      builder: (paged) => PagedListView<ReturnSummary>(
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
        emptyState: status == null
            ? NoResultsView(
                icon: SabaIcons.refresh,
                title: l10n.noReturns,
                message: l10n.noReturnsMessage,
                actions: [
                  FilledButton(
                    onPressed: onShowOrders,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: Text(l10n.myOrders),
                  ),
                ],
              )
            : NoResultsView(
                icon: SabaIcons.refresh,
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
        itemBuilder: (context, request, _) => _ReturnCard(request: request),
      ),
    );
  }
}

/// One return request: which order, how far along, and how much comes back.
class _ReturnCard extends StatelessWidget {
  const _ReturnCard({required this.request});

  final ReturnSummary request;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = l10n.locale.toLanguageTag();
    final radius = BorderRadius.circular(AppRadius.card);

    return Material(
      color: context.colors.surface,
      borderRadius: radius,
      child: InkWell(
        onTap: () => context.push(AppRoutes.returnDetailPath(request.id)),
        borderRadius: radius,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md + 2),
          decoration: BoxDecoration(
            border: Border.all(color: context.market.border),
            borderRadius: radius,
          ),
          child: Row(
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
                            style: context.textStyles.titleMedium?.copyWith(
                              fontSize: 14.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        ReturnStatusChip(status: request.status, compact: true),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      '${Formatters.date(request.requestedAt, locale: locale)}'
                      '  ·  ${l10n.counted(request.itemCount, CountNoun.item)}',
                      style: context.textStyles.labelSmall,
                    ),
                    const SizedBox(height: AppSpacing.sm + 2),
                    // The refund is the whole point of the screen, so it is
                    // labelled rather than left as a bare number that could be
                    // mistaken for what the order cost.
                    // A declined return refunds nothing: the server still
                    // sends what it was for, and it read as money coming back.
                    if (request.status == ReturnStatus.rejected)
                      const SizedBox.shrink()
                    else if (request.refundAmount != null)
                      Row(
                        children: [
                          // Gives way to the amount, which must be read whole.
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
                            style: context.textStyles.titleMedium?.copyWith(
                              fontSize: 15,
                              color: context.market.success,
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        l10n.noRefundYet,
                        style: context.textStyles.labelSmall,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
