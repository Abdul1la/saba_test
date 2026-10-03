import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/saba_icons.dart';

import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../auth/domain/entities.dart';
import '../../../auth/presentation/auth_providers.dart';
import '../../../orders/domain/entities.dart' show OrderStatus;
import '../../../orders/presentation/widgets/order_status_chip.dart';
import '../../domain/entities.dart';

/// The merchant fulfilment workflow, and how to say it.
///
/// This lives here rather than inside the list screen because the order
/// detail screen advances the same order through the same states: two copies
/// of the transition table is how a card and its own detail screen end up
/// offering different next steps for the same order (specification 26).
class MerchantOrderStatus {
  const MerchantOrderStatus._();

  /// PENDING -> CONFIRMED -> PROCESSING -> SHIPPED -> DELIVERED: confirm (after
  /// a call), prepare, send with a driver, delivered.
  static const List<String> workflow = <String>[
    'PENDING',
    'CONFIRMED',
    'PROCESSING',
    'SHIPPED',
    'DELIVERED',
  ];

  /// The state after [current], or null when there is nowhere left to go —
  /// delivered, refused, cancelled, returned and refunded are all ends.
  static String? next(String current) {
    final index = workflow.indexOf(current.toUpperCase());
    if (index < 0 || index >= workflow.length - 1) return null;
    return workflow[index + 1];
  }

  static String label(BuildContext context, String status) {
    final l10n = context.l10n;
    return switch (status.toUpperCase()) {
      // The value is PENDING, as the server says it; the words stay "New".
      'PENDING' => l10n.orderStatusNew,
      'CONFIRMED' => l10n.orderStatusConfirmed,
      'PROCESSING' => l10n.orderStatusProcessing,
      'SHIPPED' => l10n.orderStatusShipped,
      'DELIVERED' => l10n.orderStatusDelivered,
      'CANCELLED' => l10n.orderStatusCancelled,
      'REFUSED' => l10n.orderStatusRefused,
      'RETURNED' => l10n.orderStatusReturned,
      'REFUNDED' => l10n.orderStatusRefunded,
      _ => status,
    };
  }

  /// PENDING ("New") is the merchant's to-do, not a neutral fact, so it is drawn as
  /// something waiting rather than as one more colourless pill.
  /// The shopper's colour for the same status, so both sides agree.
  static StatusTone tone(String status) =>
      OrderStatusChip.toneFor(OrderStatus.fromApi(status));
}

/// One headline figure: a coloured icon tile, the number, what it counts.
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.accent,
    this.onTap,
  });

  final String label;
  final String value;
  final String icon;
  final Color? accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? context.colors.primary;
    final radius = BorderRadius.circular(AppRadius.card);

    return Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: context.market.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md + 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: AppSizes.tileIcon,
                height: AppSizes.tileIcon,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.action),
                ),
                child: SabaIcon(icon, size: AppSizes.iconMd, color: color),
              ),
              const SizedBox(height: AppSpacing.md),
              // A long figure shrinks rather than losing its last digits.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  value,
                  maxLines: 1,
                  style: context.textStyles.titleLarge?.copyWith(
                    fontSize: 19,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.textStyles.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "+12%" against the previous period, green up and red down, with an
/// arrow so the direction is not carried by colour alone.
class DeltaPill extends StatelessWidget {
  const DeltaPill({super.key, required this.percent});

  final double percent;

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    final isUp = percent >= 0;
    final color = isUp ? market.success : context.colors.error;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SabaIcon(
            isUp ? SabaIcons.trendingUp : SabaIcons.trendingDown,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 3),
          Text(
            '${isUp ? '+' : ''}${percent.toStringAsFixed(0)}%',
            style: context.textStyles.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A lightweight bar chart.
///
/// Drawn with layout widgets rather than a charting dependency: the series is
/// small, and this keeps the app's dependency surface minimal.
///
/// Two things it used to get wrong, both of which made it lie:
///
/// A day with no sales was drawn at 2% height, because the height factor was
/// clamped off the floor. A merchant looking for their quiet days could not
/// find them — nothing ever touched zero. Now zero is zero, and a baseline
/// rule runs under the whole series so an empty column still reads as a day
/// rather than as a gap.
///
/// An empty series returned `SizedBox.shrink()`, so the chart vanished and
/// took its heading with it. The merchant with no sales at all — the one who
/// most needs to be told something — was told nothing.
class SalesBarChart extends StatelessWidget {
  const SalesBarChart({
    super.key,
    required this.points,
    this.height = 180,
    this.onDark = false,
  });

  final List<SalesPoint> points;
  final double height;

  /// Drawn inside the dashboard's dark header, where the ink inverts.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    final muted = onDark ? market.onDarkMuted : market.textMuted;

    if (points.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            context.l10n.noSalesYet,
            style: context.textStyles.bodySmall?.copyWith(color: muted),
          ),
        ),
      );
    }

    final maxValue = points
        .map((point) => point.value)
        .reduce((a, b) => a > b ? a : b);
    final safeMax = maxValue <= 0 ? 1 : maxValue;
    final barColor = onDark ? market.onDarkMuted : context.colors.primary;
    final lastColor = onDark ? market.onDark : context.colors.primary;
    final locale = context.l10n.locale.toLanguageTag();
    // Named here, in the reader's language: the server's "D-0" and "W1"
    // stayed Latin in Arabic (the tester).
    String name(SalesPoint point) => switch (point.from) {
      null => point.label,
      final from when point.unit == 'MONTH' => Formatters.month(
        from,
        locale: locale,
      ),
      final from => Formatters.monthDay(from, locale: locale),
    };

    return SizedBox(
      height: height,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                // The floor. Without it a run of zero days is a blank strip
                // with no way to tell it from a chart that failed to draw.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    height: 1,
                    color: muted.withValues(alpha: 0.35),
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var index = 0; index < points.length; index++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xxs,
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.bottomCenter,
                            heightFactor: (points[index].value / safeMax)
                                .clamp(0.0, 1.0)
                                .toDouble(),
                            child: Container(
                              decoration: BoxDecoration(
                                // The newest column is the one being asked
                                // about, so it is the one that is lit.
                                color: index == points.length - 1
                                    ? lastColor
                                    : barColor,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(AppRadius.xs),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Nine labels do not fit under nine columns on a phone, and the
          // design does not try: it names the ends and lets the shape speak.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                name(points.first),
                style: context.textStyles.labelSmall?.copyWith(color: muted),
              ),
              Text(
                name(points.last),
                style: context.textStyles.labelSmall?.copyWith(color: muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Status pill for a merchant product's approval state.
class ProductStatusChip extends StatelessWidget {
  const ProductStatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final (label, color) = switch (status.toUpperCase()) {
      'DRAFT' => (l10n.productDraft, context.colors.onSurfaceVariant),
      'PENDING' => (l10n.productPendingApproval, context.market.warning),
      'APPROVED' => (l10n.productApproved, context.market.success),
      'REJECTED' => (l10n.productRejected, context.colors.error),
      _ => (status, context.colors.onSurfaceVariant),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: context.textStyles.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Banner shown to a merchant whose store is not approved yet.
///
/// The selling surfaces stay visible but the server rejects the writes, so this
/// explains why rather than silently hiding everything.
class PendingApprovalBanner extends ConsumerWidget {
  const PendingApprovalBanner({
    super.key,
    this.margin = const EdgeInsets.all(AppSpacing.screenGutter),
  });

  /// None inside a layout that already pads its children.
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final market = context.market;
    final merchant = ref.watch(authControllerProvider).value?.user?.merchant;
    final status = merchant?.status;
    final reason = merchant?.rejectionReason;

    // A store Saba turned down used to read "waiting to be approved", with a
    // red Rejected chip directly above it on the same screen: two answers to
    // one question, and neither said what to do next.
    final rejected = status == MerchantStatus.rejected;
    final (tint, icon, words) = rejected
        ? (
            context.colors.error,
            SabaIcons.alertCircle,
            l10n.merchantRejectedBanner,
          )
        : (market.warning, SabaIcons.clock, l10n.merchantPendingApproval);

    return Container(
      margin: margin,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: tint.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SabaIcon(icon, size: AppSizes.iconMd, color: tint),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(words, style: context.textStyles.bodySmall),
                // Saba's own words: what to change before asking again.
                if (rejected && reason != null && reason.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l10n.rejectionReason,
                    style: context.textStyles.labelSmall?.copyWith(
                      color: market.textMuted,
                    ),
                  ),
                  Text(reason, style: context.textStyles.bodyMedium),
                ],
                if (rejected) ...[
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    label: l10n.support,
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.small,
                    expand: false,
                    onPressed: () => context.push(AppRoutes.supportTickets),
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
