import 'package:flutter/material.dart';

import '../theme/app_dimensions.dart';
import '../theme/saba_icons.dart';
import '../utils/context_extensions.dart';
import 'section_header.dart';

/// One row in a settings or account list.
///
/// Account, Settings and the notification preferences each had their own
/// `ListTile` before, which meant three different icon sizes and three
/// different row heights for the same job. This is the one row.
///
/// A row that navigates gets a chevron pointing the way the language reads; a
/// row that toggles gets its control instead. It never gets both — an arrow
/// beside a switch promises a screen that does not exist.
class SabaTile extends StatelessWidget {
  const SabaTile({
    super.key,
    required this.label,
    this.icon,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.isDestructive = false,
    this.tint,
  });

  final String label;

  /// A [SabaIcons] path. Omitted for a row that reads better without one.
  final String? icon;

  /// Sets [icon] on a soft coloured tile, as `(ink, fill)`. The account hub
  /// uses it: a colour per row lets the eye find a row without reading every
  /// label. Null keeps the plain muted icon the other lists use.
  final (Color, Color)? tint;

  final String? subtitle;

  /// A switch, a value, a badge. When null and [onTap] is set, a chevron.
  final Widget? trailing;

  final VoidCallback? onTap;

  /// Paints the row in the error colour, for "delete" and "sign out".
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    final ink = isDestructive ? context.colors.error : context.colors.onSurface;

    final tint = this.tint;

    final row = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        // The tile is taller than a bare icon; the row stays the same height.
        vertical: tint == null ? AppSpacing.md + 1 : AppSpacing.sm + 2,
      ),
      child: Row(
        children: [
          if (icon != null && tint != null) ...[
            Container(
              width: AppSizes.tileIcon,
              height: AppSizes.tileIcon,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint.$2,
                borderRadius: BorderRadius.circular(AppRadius.action),
              ),
              child: SabaIcon(icon!, size: AppSizes.iconMd, color: tint.$1),
            ),
            const SizedBox(width: AppSpacing.md),
          ] else if (icon != null) ...[
            SabaIcon(
              icon!,
              size: AppSizes.iconMd,
              color: isDestructive ? context.colors.error : market.textMuted,
            ),
            const SizedBox(width: AppSpacing.md + 2),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.bodyLarge?.copyWith(
                    fontSize: 14.5,
                    fontWeight: tint == null ? null : FontWeight.w500,
                    color: ink,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.xxs - 1),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.labelSmall?.copyWith(
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          if (trailing != null)
            trailing!
          else if (onTap != null)
            SabaIcon(
              context.isRtl ? SabaIcons.chevronLeft : SabaIcons.chevronRight,
              size: AppSizes.iconSm,
              color: market.textMuted,
            ),
        ],
      ),
    );

    if (onTap == null) return row;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.action),
      child: row,
    );
  }
}

/// A card of [SabaTile]s, hairlined between rows.
///
/// The hairline is inset past the icon so it separates the labels rather than
/// cutting the card in half, which is what keeps a ten-row account screen
/// readable without ten separate cards.
///
/// The title sits above the card, not inside it. Inside, it shared the card's
/// zero padding - the rows need that to run edge to edge - and so was jammed
/// into the card's corner on Account, Settings and the notification
/// preferences alike.
class TileGroup extends StatelessWidget {
  const TileGroup({super.key, required this.tiles, this.title, this.subtitle});

  final String? title;

  /// A line under the title explaining the group, above the card.
  final String? subtitle;

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    final card = SectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < tiles.length; index++) ...[
            if (index > 0)
              Padding(
                padding: EdgeInsetsDirectional.only(
                  start: _labelInset(tiles[index]),
                ),
                child: Divider(height: 1, color: context.market.border),
              ),
            tiles[index],
          ],
        ],
      ),
    );

    if (title == null && subtitle == null) return card;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.xs,
            0,
            AppSpacing.xs,
            AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null)
                Text(
                  title!,
                  style: context.textStyles.titleMedium?.copyWith(
                    fontSize: 14,
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  subtitle!,
                  style: context.textStyles.bodySmall?.copyWith(height: 1.5),
                ),
              ],
            ],
          ),
        ),
        card,
      ],
    );
  }

  /// Where a row's label starts, so the hairline above it lines up with it.
  static double _labelInset(Widget tile) {
    // A choice has no icon: its line starts where its words do.
    if (tile is ChoiceRow) return tile.padding.left;
    final tinted = tile is SabaTile && tile.tint != null;
    return tinted
        ? AppSpacing.lg + AppSizes.tileIcon + AppSpacing.md
        : AppSpacing.lg + AppSizes.iconMd + AppSpacing.md + 2;
  }
}

/// A row that is one of a set: the chosen one carries a tick.
///
/// The design marks a choice with a tick at the end of the row rather than a
/// radio dial at the start — the row is the target, and the eye finds one
/// ticked line faster than one filled circle. Shared by the sort sheets and
/// the settings screen so a choice looks the same wherever it is made.
class ChoiceRow extends StatelessWidget {
  const ChoiceRow({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.subtitle,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.xl,
      vertical: AppSpacing.lg - 1,
    ),
  });

  final String label;
  final String? subtitle;
  final bool isSelected;
  final VoidCallback onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: isSelected,
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: padding,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      // Every option in the text colour, not the hint's
                      // grey: the grey rows read as empty.
                      style: context.textStyles.bodyLarge?.copyWith(
                        fontSize: 14.5,
                        color: context.colors.onSurface,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppSpacing.xxs - 1),
                      Text(subtitle!, style: context.textStyles.labelSmall),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              if (isSelected)
                SabaIcon(
                  SabaIcons.check,
                  size: AppSizes.iconMd,
                  color: context.colors.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
