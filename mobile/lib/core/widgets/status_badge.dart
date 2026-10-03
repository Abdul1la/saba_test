import 'package:flutter/material.dart';

import '../theme/app_dimensions.dart';
import '../utils/context_extensions.dart';

/// The tone a status carries, independent of which feature it came from.
enum StatusTone { neutral, progress, positive, caution, negative }

/// The design's `card/badge`: a soft-filled pill, 24 high, that states a
/// status in words.
///
/// Colour alone is never the message — a customer who cannot separate green
/// from red still reads "Delivered". The fill comes from the recovered
/// `semantic/*/soft` tokens rather than an alpha blend, so it stays correct on
/// both themes instead of washing out on the dark one.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.tone,
    this.compact = false,
  });

  final String label;
  final StatusTone tone;

  /// Smaller type for a badge riding inside a list card.
  final bool compact;

  /// The pair the tone resolves to: the ink, then the fill behind it.
  static (Color, Color) colorsFor(BuildContext context, StatusTone tone) {
    final market = context.market;
    return switch (tone) {
      StatusTone.positive => (market.success, market.successSoft),
      StatusTone.caution => (market.warning, market.warningSoft),
      StatusTone.negative => (context.colors.error, market.errorSoft),
      StatusTone.progress => (market.info, market.infoSoft),
      StatusTone.neutral => (market.textMuted, market.surfaceMuted),
    };
  }

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();

    final (ink, fill) = colorsFor(context, tone);

    return Container(
      height: AppSizes.cardBadgeHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md - 2),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      // As wide as its words. `Container.alignment` grows to all the width
      // it is offered, so in a column the badge stretched edge to edge.
      child: Center(
        widthFactor: 1,
        child: Text(
          label,
          style: context.textStyles.labelMedium?.copyWith(
            fontSize: compact ? 11 : 12,
            fontWeight: FontWeight.w600,
            color: ink,
            height: 1,
          ),
        ),
      ),
    );
  }
}
