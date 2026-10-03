import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/dark_header_card.dart';
import '../../../../core/widgets/filter_chip_row.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../core/widgets/status_timeline.dart';
import '../../../orders/presentation/widgets/order_notes.dart';
import '../../domain/entities.dart';
import '../returns_providers.dart';
import '../widgets/return_status_chip.dart';

/// G5 — one return request, including refund tracking.
///
/// Built to the same shape as the order detail: a dark hero that answers "what
/// is happening to my money", then the trail, then the detail. A customer
/// moving between the two screens should not have to relearn either.
class ReturnDetailScreen extends ConsumerWidget {
  const ReturnDetailScreen({super.key, required this.returnId});

  final String returnId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final request = ref.watch(returnDetailProvider(returnId));

    return Scaffold(
      body: AsyncStateView<ReturnDetail>(
        value: request,
        onRetry: () => ref.invalidate(returnDetailProvider(returnId)),
        builder: (detail) => RefreshIndicator(
          onRefresh: () => ref.refresh(returnDetailProvider(returnId).future),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              WhiteHeader(child: _Hero(detail: detail)),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenGutter,
                  AppSpacing.lg + 2,
                  AppSpacing.screenGutter,
                  AppSpacing.xxl,
                ),
                child: ContentContainer(
                  maxWidth: 720,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (detail.status == ReturnStatus.rejected)
                        _RejectedCard(detail: detail)
                      else
                        _ProgressCard(detail: detail),
                      // A declined return hands nothing back: it still said
                      // "Refund amount 145,000" (the tester).
                      if (detail.status != ReturnStatus.rejected) ...[
                        const SizedBox(height: AppSpacing.md + 2),
                        _RefundCard(detail: detail),
                      ],
                      const SizedBox(height: AppSpacing.md + 2),
                      _ItemsCard(detail: detail),
                      if (detail.photoUrls.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md + 2),
                        _PhotosCard(urls: detail.photoUrls),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                      AppButton(
                        label: l10n.viewOrder,
                        variant: AppButtonVariant.secondary,
                        icon: SabaIcons.receipt,
                        onPressed: () => context.push(
                          AppRoutes.orderDetailPath(detail.orderId),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.detail});

  final ReturnDetail detail;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = l10n.locale.toLanguageTag();
    final market = context.market;

    return DarkHeaderCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DarkIconButton(
                icon: context.isRtl
                    ? SabaIcons.chevronRight
                    : SabaIcons.chevronLeft,
                tooltip: l10n.back,
                onPressed: () => context.popOrGo(AppRoutes.orders),
              ),
              const Spacer(),
              ReturnStatusChip(status: detail.status),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            detail.orderNumber,
            style: context.textStyles.displaySmall?.copyWith(
              fontSize: 26,
              color: market.onDark,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${l10n.returnRequestedOn} '
            '${Formatters.date(detail.requestedAt, locale: locale)}',
            style: context.textStyles.bodySmall?.copyWith(
              color: market.onDarkMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.lg + 2),
          OnDarkRaisedCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.returnReason,
                  style: context.textStyles.labelSmall?.copyWith(
                    color: market.onDarkMuted,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  reasonLabel(l10n, detail.reason) ?? detail.reason,
                  style: context.textStyles.bodyMedium?.copyWith(
                    fontSize: 13.5,
                    color: market.onDark,
                  ),
                ),
                if (detail.description != null &&
                    detail.description!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    detail.description!,
                    style: context.textStyles.bodySmall?.copyWith(
                      height: 1.45,
                      color: market.onDarkMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The ladder from request to refund, with everything still to come drawn
/// hollow so "where am I" needs no reading.
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.detail});

  final ReturnDetail detail;

  @override
  Widget build(BuildContext context) {
    final steps = ReturnStatus.progression;
    // `closed` is not a rung on this ladder, it is the end of it, so indexOf
    // returned -1 and lit nothing: a finished return drew as one that had
    // never been requested, directly under a green "Closed" badge.
    final reached = detail.status == ReturnStatus.closed
        ? steps.length - 1
        : steps.indexOf(detail.status);

    return SectionCard(
      title: context.l10n.returnProgress,
      child: StatusTimeline(
        entries: [
          for (var i = 0; i < steps.length; i++)
            TimelineEntry(
              label: ReturnStatusChip.labelFor(context, steps[i]),
              isDone: i <= reached,
              color: context.market.success,
            ),
        ],
      ),
    );
  }
}

/// A rejected request has no ladder left to climb, so it says why instead of
/// showing a bar that can never fill.
class _RejectedCard extends StatelessWidget {
  const _RejectedCard({required this.detail});

  final ReturnDetail detail;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (ink, fill) = StatusBadge.colorsFor(context, StatusTone.negative);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SabaIcon(SabaIcons.alertCircle, size: AppSizes.iconLg, color: ink),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.rejectionReason,
                  style: context.textStyles.titleSmall?.copyWith(
                    fontSize: 14,
                    color: ink,
                  ),
                ),
                if (detail.rejectionReason != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    reasonLabel(l10n, detail.rejectionReason!) ??
                        detail.rejectionReason!,
                    style: context.textStyles.bodySmall?.copyWith(height: 1.45),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemsCard extends StatelessWidget {
  const _ItemsCard({required this.detail});

  final ReturnDetail detail;

  @override
  Widget build(BuildContext context) {
    final locale = context.l10n.locale.toLanguageTag();

    return SectionCard(
      title: context.l10n.returnedItems,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in detail.items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppNetworkImage(
                    url: item.imageUrl,
                    width: 48,
                    height: 48,
                    radius: AppRadius.md,
                    fallbackIcon: iconForName(item.name, 0),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.bodyMedium?.copyWith(
                            fontSize: 13.5,
                            height: 1.35,
                          ),
                        ),
                        if (item.variantLabel != null)
                          Text(
                            item.variantLabel!,
                            style: context.textStyles.labelSmall,
                          ),
                        Text(
                          '× ${item.quantity}',
                          style: context.textStyles.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  // Nothing comes back on a declined return.
                  if (item.refundAmount != null &&
                      detail.status != ReturnStatus.rejected) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      Formatters.money(
                        item.refundAmount!,
                        locale: locale,
                        currencyCode: detail.currencyCode,
                      ),
                      style: context.textStyles.titleSmall?.copyWith(
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RefundCard extends StatelessWidget {
  const _RefundCard({required this.detail});

  final ReturnDetail detail;

  String _statusLabel(BuildContext context, RefundStatus status) {
    final l10n = context.l10n;
    return switch (status) {
      RefundStatus.pending => l10n.refundStatusPending,
      RefundStatus.processing => l10n.refundStatusProcessing,
      RefundStatus.completed => l10n.refundStatusCompleted,
      RefundStatus.failed => l10n.refundStatusFailed,
      RefundStatus.unknown => l10n.status,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = l10n.locale.toLanguageTag();
    final refund = detail.refund;

    if (refund == null) {
      return SectionCard(
        title: l10n.refund,
        child: Text(
          l10n.noRefundYet,
          style: context.textStyles.bodySmall?.copyWith(height: 1.45),
        ),
      );
    }

    return SectionCard(
      title: l10n.refund,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The amount leads. It is the single number the customer opened this
          // screen to see, so it is not buried in a list of equal rows.
          Text(
            Formatters.money(
              refund.amount,
              locale: locale,
              currencyCode: refund.currencyCode,
            ),
            style: context.textStyles.displaySmall?.copyWith(
              fontSize: 26,
              color: context.market.success,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          CardLine(
            label: l10n.refundStatus,
            value: _statusLabel(context, refund.status),
          ),
          if (refund.method != null)
            CardLine(label: l10n.refundMethod, value: refund.method!),
          if (refund.reference != null)
            CardLine(label: l10n.refundReference, value: refund.reference!),
          if (refund.processedAt != null)
            CardLine(
              label: l10n.refundProcessedOn,
              value: Formatters.date(refund.processedAt!, locale: locale),
            )
          else if (refund.expectedAt != null)
            CardLine(
              label: l10n.refundExpectedBy,
              value: Formatters.date(refund.expectedAt!, locale: locale),
            ),
        ],
      ),
    );
  }
}

class _PhotosCard extends StatelessWidget {
  const _PhotosCard({required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: context.l10n.returnPhotos,
      child: SizedBox(
        height: 96,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: urls.length,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
          itemBuilder: (context, index) => AppNetworkImage(
            url: urls[index],
            width: 96,
            height: 96,
            radius: AppRadius.md,
            fallbackIcon: SabaIcons.image,
          ),
        ),
      ),
    );
  }
}
