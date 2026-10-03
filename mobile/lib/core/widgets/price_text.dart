import 'package:flutter/material.dart';

import '../theme/app_dimensions.dart';
import '../theme/saba_icons.dart';
import '../utils/context_extensions.dart';
import '../utils/formatters.dart';

/// Renders a price, and when the item is discounted, the struck-through
/// original beside it.
///
/// Both figures come from the server. The app never computes a discount or a
/// total itself (specification sections 13 and 20).
class PriceText extends StatelessWidget {
  const PriceText({
    super.key,
    required this.amount,
    required this.currencyCode,
    this.originalAmount,
    this.size = PriceTextSize.regular,
    this.alignment = WrapAlignment.start,
  });

  final num amount;
  final String currencyCode;

  /// The pre-discount price, when the API reports one that is higher.
  final num? originalAmount;

  final PriceTextSize size;
  final WrapAlignment alignment;

  bool get _hasDiscount => originalAmount != null && originalAmount! > amount;

  @override
  Widget build(BuildContext context) {
    final locale = context.l10n.locale.toLanguageTag();

    final priceStyle = switch (size) {
      PriceTextSize.large => context.textStyles.headlineSmall,
      PriceTextSize.regular => context.textStyles.titleMedium,
      PriceTextSize.small => context.textStyles.titleSmall,
    };

    return Wrap(
      alignment: alignment,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.sm,
      children: [
        Text(
          Formatters.money(amount, locale: locale, currencyCode: currencyCode),
          style: priceStyle?.copyWith(
            color: context.market.price,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (_hasDiscount)
          Text(
            Formatters.money(
              originalAmount!,
              locale: locale,
              currencyCode: currencyCode,
            ),
            style: context.textStyles.bodySmall?.copyWith(
              color: context.market.originalPrice,
              decoration: TextDecoration.lineThrough,
            ),
          ),
      ],
    );
  }
}

enum PriceTextSize { small, regular, large }

/// The "−25%" chip on a discounted product.
///
/// Amber with navy ink: a discount is heat, not something to tap, so it is
/// never the purple.
class DiscountBadge extends StatelessWidget {
  const DiscountBadge({super.key, required this.percentage, this.pill = false});

  final num percentage;

  /// Fully rounded, beside a price; a card's corner keeps the small radius
  /// its stock badge has.
  final bool pill;

  @override
  Widget build(BuildContext context) {
    if (percentage <= 0) return const SizedBox.shrink();

    final rounded = percentage.round().toString();

    return Semantics(
      label: context.l10n.discountBadgeLabel(rounded),
      // "-25%" is a glyph, not a sentence; the label above says it in words.
      excludeSemantics: true,
      // Centred without `alignment`: a Container with an alignment grows to
      // the width it is offered, which on the product page was the screen.
      child: Container(
        height: pill ? 24 : AppSizes.cardBadgeHeight,
        padding: EdgeInsets.symmetric(
          horizontal: pill ? AppSpacing.sm + 2 : AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: context.market.heat,
          borderRadius: BorderRadius.circular(
            pill ? AppRadius.pill : AppRadius.xs,
          ),
        ),
        child: Center(
          widthFactor: 1,
          child: Text(
            context.l10n.discountBadge(rounded),
            style: context.textStyles.labelMedium?.copyWith(
              color: context.market.onHeat,
              fontSize: pill ? 12 : 11,
            ),
          ),
        ),
      ),
    );
  }
}

/// A stock badge on a product image — "Only 3 left", "Out of stock".
///
/// Always an icon *and* a word: a screenshot printed in black and white, or a
/// colour-blind customer, still reads the state.
class StockBadge extends StatelessWidget {
  const StockBadge({
    super.key,
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
    this.border,
  });

  final String label;
  final String icon;
  final Color background;
  final Color foreground;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppSizes.cardBadgeHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: border == null ? null : Border.all(color: border!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SabaIcon(icon, size: 13, color: foreground),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: context.textStyles.labelMedium?.copyWith(
              color: foreground,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
