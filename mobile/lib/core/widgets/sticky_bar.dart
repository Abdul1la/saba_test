import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../theme/app_dimensions.dart';
import '../utils/context_extensions.dart';

/// The bar pinned to the bottom of a buying screen — product detail, cart,
/// checkout.
///
/// One of the three things in the whole design allowed a shadow, because it
/// has to read as sitting *above* the page rather than as the end of it. Its
/// top corners take the sheet radius for the same reason.
class StickyBar extends StatelessWidget {
  const StickyBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final market = context.market;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: market.border)),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
        boxShadow: [
          BoxShadow(
            color: (context.isDarkMode ? Colors.black : AppPalette.textPrimary)
                .withValues(
                  alpha: context.isDarkMode ? 0.5 : AppElevation.floatOpacity,
                ),
            blurRadius: AppElevation.floatBlur,
            offset: const Offset(0, -AppElevation.floatOffsetY),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.md + 2,
            AppSpacing.screenGutter,
            AppSpacing.md + 2,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The "Total / 135,000" block at the leading end of a [StickyBar].
class StickyBarTotal extends StatelessWidget {
  const StickyBarTotal({super.key, required this.label, required this.amount});

  final String label;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: context.textStyles.labelSmall?.copyWith(fontSize: 11.5),
        ),
        Text(
          amount,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.theme
              .extension<MarketplaceTextStyles>()
              ?.price
              .copyWith(fontSize: 19, height: 1.1),
        ),
      ],
    );
  }
}
