import 'package:flutter/material.dart';

import '../location/governorate.dart';
import '../location/governorate_picker.dart';
import '../theme/app_dimensions.dart';
import '../theme/saba_icons.dart';
import '../utils/context_extensions.dart';
import 'app_network_image.dart';
import 'saba_logo.dart';

/// `card/store` — the one card for a store, wherever one appears: Home's
/// store rail and the seller card on a product page.
///
/// Its logo, its name, its rating and its city, on the same soft-shadowed
/// card as a product. A screen that knows more adds it: [label] above the
/// name ("Sold by"), [extra] under it (whether it delivers to you) and
/// [trailing] before the chevron (a Message button).
class StoreCard extends StatelessWidget {
  const StoreCard({
    super.key,
    required this.name,
    required this.onTap,
    this.logoUrl,
    this.city,
    this.rating,
    this.label,
    this.extra,
    this.trailing,
    this.width,
  });

  final String name;
  final VoidCallback onTap;
  final String? logoUrl;
  final Governorate? city;
  final double? rating;
  final String? label;
  final Widget? extra;
  final Widget? trailing;

  /// Set when the card sits in a horizontal rail.
  final double? width;

  static const double _padding = AppSpacing.md + 2;
  static const double _logo = 48;

  /// Width of a store card in a rail.
  static const double railWidth = 250;

  static TextStyle? _nameStyle(BuildContext context) =>
      context.textStyles.titleLarge?.copyWith(fontSize: 14);

  /// The height of a card with no [label] or [extra], for sizing a rail.
  static double heightFor(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final name = _nameStyle(context);
    final nameLine = scaler.scale(name?.fontSize ?? 14) * (name?.height ?? 1.3);
    // The rating and the city, from the theme's own line heights, which are
    // taller in Arabic. The star and the pin are 12.
    final rating =
        scaler.scale(11.5) * (context.textStyles.labelMedium?.height ?? 1.4);
    final city =
        scaler.scale(11) * (context.textStyles.labelSmall?.height ?? 1.4);
    final metaLine = [rating, city, 12.0].reduce((a, b) => a > b ? a : b);
    // Two more for the way a line's box is rounded when it is drawn: half a
    // pixel short cut the city off in Arabic at a large text size. The card
    // centres what it holds, so the spare two never show.
    final text = nameLine + AppSpacing.xs + metaLine + 2;
    return _padding * 2 + (text > _logo ? text : _logo);
  }

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    final radius = BorderRadius.circular(AppRadius.card);

    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: AppElevation.card,
        ),
        child: Material(
          color: context.colors.surface,
          clipBehavior: Clip.antiAlias,
          borderRadius: radius,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(_padding),
              child: Row(
                children: [
                  SizedBox(
                    width: _logo,
                    height: _logo,
                    child: AppNetworkImage(
                      url: logoUrl,
                      radius: AppRadius.action,
                      // No logo of its own: Saba's mark.
                      fallback: const SabaMark(size: _logo),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (label != null) ...[
                          Text(
                            label!,
                            style: context.textStyles.bodySmall?.copyWith(
                              fontSize: 11.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                        ],
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _nameStyle(context),
                        ),
                        if (rating != null || city != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Row(
                            children: [
                              if (rating != null) ...[
                                SabaIcon(
                                  SabaIcons.starFilled,
                                  size: 12,
                                  color: market.star,
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Text(
                                  rating!.toStringAsFixed(1),
                                  style: context.textStyles.labelMedium
                                      ?.copyWith(
                                        fontSize: 11.5,
                                        color: context.colors.onSurfaceVariant,
                                      ),
                                ),
                                if (city != null)
                                  const SizedBox(width: AppSpacing.sm),
                              ],
                              if (city != null)
                                Flexible(child: StoreCity(city: city!)),
                            ],
                          ),
                        ],
                        if (extra != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          extra!,
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    trailing!,
                  ],
                  const SizedBox(width: AppSpacing.sm),
                  SabaIcon(
                    context.isRtl
                        ? SabaIcons.chevronLeft
                        : SabaIcons.chevronRight,
                    size: AppSizes.iconSm,
                    color: context.colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
