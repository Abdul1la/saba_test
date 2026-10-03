import 'package:flutter/material.dart';

import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../domain/entities.dart';

/// The state of an order, drawn as the design's `card/badge`.
///
/// Shared by the order list, the order detail and the timeline, so an order
/// that is "Shipped" is the same word and the same blue wherever it is seen.
class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip({
    super.key,
    required this.status,
    this.compact = false,
  });

  final OrderStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) => StatusBadge(
    label: labelFor(context, status),
    tone: toneFor(status),
    compact: compact,
  );

  static String labelFor(BuildContext context, OrderStatus status) {
    final l10n = context.l10n;
    return switch (status) {
      OrderStatus.pending => l10n.orderStatusPending,
      OrderStatus.confirmed => l10n.orderStatusConfirmed,
      OrderStatus.processing => l10n.orderStatusProcessing,
      OrderStatus.shipped => l10n.orderStatusShipped,
      OrderStatus.delivered => l10n.orderStatusDelivered,
      OrderStatus.cancelled => l10n.orderStatusCancelled,
      OrderStatus.refused => l10n.orderStatusRefused,
      OrderStatus.returned => l10n.orderStatusReturned,
      OrderStatus.refunded => l10n.orderStatusRefunded,
      OrderStatus.unknown => '',
    };
  }

  /// The shopper's list and the store's queue both colour a status from
  /// here: waiting on the store is amber on both sides, not amber on one and
  /// blue on the other.
  static StatusTone toneFor(OrderStatus status) => switch (status) {
    OrderStatus.pending => StatusTone.caution,
    OrderStatus.delivered => StatusTone.positive,
    OrderStatus.shipped => StatusTone.progress,
    OrderStatus.cancelled ||
    OrderStatus.refused ||
    OrderStatus.returned => StatusTone.negative,
    OrderStatus.refunded => StatusTone.caution,
    OrderStatus.unknown => StatusTone.neutral,
    _ => StatusTone.progress,
  };

  /// The ink of the badge, for a dot or a line that has to match it.
  static Color colorFor(BuildContext context, OrderStatus status) =>
      StatusBadge.colorsFor(context, toneFor(status)).$1;
}

/// Whether the money has actually arrived, shown under the delivery state.
///
/// Quieter than the status badge on purpose: for most orders payment is
/// settled and unremarkable, and only becomes worth a glance when it is not.
class PaymentStatusLabel extends StatelessWidget {
  const PaymentStatusLabel({
    super.key,
    required this.status,
    this.isCashOnDelivery = false,
  });

  final PaymentStatus status;
  final bool isCashOnDelivery;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final (label, tone) = switch (status) {
      // "Payment: Approved" was office language; a customer says "Paid".
      PaymentStatus.paid => (l10n.paymentPaid, StatusTone.positive),
      PaymentStatus.pending when isCashOnDelivery => (
        l10n.payOnDelivery,
        StatusTone.progress,
      ),
      PaymentStatus.pending => (l10n.awaitingPayment, StatusTone.caution),
      PaymentStatus.processing => (
        l10n.orderStatusProcessing,
        StatusTone.progress,
      ),
      PaymentStatus.failed => (l10n.paymentFailedShort, StatusTone.negative),
      PaymentStatus.cancelled => (
        l10n.orderStatusCancelled,
        StatusTone.negative,
      ),
      PaymentStatus.refunded || PaymentStatus.partiallyRefunded => (
        l10n.orderStatusRefunded,
        StatusTone.caution,
      ),
      PaymentStatus.unknown => ('', StatusTone.neutral),
    };

    if (label.isEmpty) return const SizedBox.shrink();
    final color = StatusBadge.colorsFor(context, tone).$1;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: SabaIcon(SabaIcons.creditCard, size: 13, color: color),
        ),
        const SizedBox(width: AppSpacing.xs + 1),
        Flexible(
          // Wraps rather than ending in "Pay on d…".
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.textStyles.labelSmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// The paid / unpaid stamp on an invoice.
class PaymentStatusBadge extends StatelessWidget {
  const PaymentStatusBadge({super.key, required this.status});

  final PaymentStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final (label, tone) = switch (status) {
      PaymentStatus.paid => (l10n.amountPaid, StatusTone.positive),
      PaymentStatus.pending => (l10n.orderStatusPending, StatusTone.caution),
      PaymentStatus.processing => (
        l10n.orderStatusProcessing,
        StatusTone.progress,
      ),
      PaymentStatus.failed => (l10n.paymentFailedShort, StatusTone.negative),
      PaymentStatus.cancelled => (
        l10n.orderStatusCancelled,
        StatusTone.negative,
      ),
      PaymentStatus.refunded || PaymentStatus.partiallyRefunded => (
        l10n.orderStatusRefunded,
        StatusTone.caution,
      ),
      PaymentStatus.unknown => ('', StatusTone.neutral),
    };

    return StatusBadge(label: label, tone: tone);
  }
}
