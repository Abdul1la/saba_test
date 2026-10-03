import 'package:flutter/material.dart';

import '../../../../core/utils/context_extensions.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../domain/entities.dart';

/// The state of one return request, drawn as the design's `card/badge`.
///
/// Colour carries meaning, so the label is always present too — a chip that
/// only differs by hue is unreadable to a colour-blind customer.
class ReturnStatusChip extends StatelessWidget {
  const ReturnStatusChip({
    super.key,
    required this.status,
    this.compact = false,
  });

  final ReturnStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) => StatusBadge(
    label: labelFor(context, status),
    tone: toneFor(status),
    compact: compact,
  );

  static String labelFor(BuildContext context, ReturnStatus status) {
    final l10n = context.l10n;
    return switch (status) {
      ReturnStatus.requested => l10n.returnStatusRequested,
      ReturnStatus.approved => l10n.returnStatusApproved,
      ReturnStatus.rejected => l10n.returnStatusRejected,
      ReturnStatus.pickup => l10n.returnStatusPickup,
      ReturnStatus.received => l10n.returnStatusReceived,
      ReturnStatus.refundPending => l10n.returnStatusRefundPending,
      ReturnStatus.refunded => l10n.returnStatusRefunded,
      ReturnStatus.closed => l10n.returnStatusClosed,
      ReturnStatus.unknown => l10n.status,
    };
  }

  static StatusTone toneFor(ReturnStatus status) => switch (status) {
    ReturnStatus.refunded || ReturnStatus.closed => StatusTone.positive,
    ReturnStatus.rejected => StatusTone.negative,
    ReturnStatus.refundPending || ReturnStatus.received => StatusTone.caution,
    ReturnStatus.unknown => StatusTone.neutral,
    _ => StatusTone.progress,
  };

  /// The ink of the badge, for a dot that has to match it.
  static Color colorFor(BuildContext context, ReturnStatus status) =>
      StatusBadge.colorsFor(context, toneFor(status)).$1;
}
