import 'package:flutter/material.dart';

import '../theme/app_dimensions.dart';
import '../theme/saba_icons.dart';
import '../utils/context_extensions.dart';

/// Read-only star rating with an optional review count.
///
/// Filled stars are the warm accent, empty stars are a neutral: a 4-of-5 row
/// has to read as a rating, not as damage. A product with no reviews yet shows
/// five empty stars and says so in words, because an empty row on its own
/// looks like a zero score.
class RatingStars extends StatelessWidget {
  const RatingStars({
    super.key,
    required this.rating,
    this.reviewCount,
    this.size = AppSizes.iconSm,
    this.showValue = true,
    this.compact = false,
  });

  /// The version drawn inside a product card: 10px stars and a single
  /// `4.6 (128)` in muted 11px beside them.
  const RatingStars.card({
    super.key,
    required this.rating,
    required this.reviewCount,
  }) : size = 12,
       showValue = true,
       compact = true;

  final double rating;
  final int? reviewCount;
  final double size;
  final bool showValue;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    final l10n = context.l10n;
    final hasReviews = (reviewCount ?? 0) > 0;

    // A star that is not there is still a whole star, just muted: an outline
    // among filled ones reads as a different shape rather than a lower score.
    //
    // The rating alone decides the stars. This used to be gated on
    // `hasReviews` too, so any caller that did not hand over a count drew five
    // grey stars beside a perfectly good score — a review card, which has a
    // rating and nothing else, and the product page, which passes
    // `reviewCount: null` precisely because it prints the count itself. A
    // product with no reviews still lands on five empty stars, because its
    // rating is 0; `hasReviews` decides the words, never the score.
    final stars = [
      for (var index = 1; index <= 5; index++)
        SabaIcon(
          switch (rating - index) {
            >= 0 => SabaIcons.starFilled,
            >= -0.5 => SabaIcons.starHalf,
            _ => SabaIcons.starFilled,
          },
          size: size,
          color: rating - index < -0.5 ? market.starEmpty : market.star,
        ),
    ];

    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...stars,
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              hasReviews
                  ? '${rating.toStringAsFixed(1)} ($reviewCount)'
                  : l10n.noReviews,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textStyles.labelSmall?.copyWith(
                color: market.textMuted,
                fontSize: 11,
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...stars,
        if (showValue && hasReviews) ...[
          const SizedBox(width: AppSpacing.xs),
          Text(
            rating.toStringAsFixed(1),
            style: context.textStyles.labelSmall?.copyWith(
              color: context.colors.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (reviewCount != null) ...[
          const SizedBox(width: AppSpacing.xxs),
          Text(
            hasReviews ? '($reviewCount)' : l10n.noReviews,
            style: context.textStyles.labelSmall,
          ),
        ],
      ],
    );
  }
}

/// Tappable stars, used when writing a review.
class RatingInput extends StatelessWidget {
  const RatingInput({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 36,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    // This is the only rating control in the app, and it announced five
    // unlabelled buttons: SabaIcon is a bare SvgPicture with no
    // semanticsLabel, and the IconButtons carried no tooltip. Naming the row
    // once and each star by its number reads as "Rating, 3, selected", which
    // is what the pattern already used by _HelpfulPill and _StepButton gives.
    return Semantics(
      label: context.l10n.rating,
      container: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var star = 1; star <= 5; star++)
            Semantics(
              button: true,
              inMutuallyExclusiveGroup: true,
              selected: star <= value,
              label: '$star',
              child: IconButton(
                onPressed: () => onChanged(star),
                visualDensity: VisualDensity.compact,
                icon: SabaIcon(
                  star <= value ? SabaIcons.starFilled : SabaIcons.star,
                  size: size,
                  color: star <= value
                      ? context.market.star
                      : context.colors.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
