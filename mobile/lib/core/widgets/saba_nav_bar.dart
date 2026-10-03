import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/saba_icons.dart';
import '../utils/context_extensions.dart';

/// One tab in a [SabaNavBar].
@immutable
class SabaNavDestination {
  const SabaNavDestination({
    required this.icon,
    required this.label,
    this.badgeCount = 0,
  });

  /// One icon per tab. The active tab takes the navy ink inside the lavender
  /// pill rather than swapping to a filled variant — the pill is the signal.
  final String icon;
  final String label;

  /// Shown as a badge on the icon's trailing-top corner when above zero.
  final int badgeCount;
}

/// `nav/pill` — the floating navigation bar.
///
/// The signature of the whole app is the pill, not the bar: the active tab is
/// a lavender capsule carrying icon *and* label, every other tab is an icon alone
/// in a 48 tap circle. That is also what makes it accessible — only one label
/// is on screen, and it is the one that answers "where am I".
///
/// It floats over the content rather than reserving space, so every scroll
/// view underneath pads its bottom by [clearance].
class SabaNavBar extends StatelessWidget {
  const SabaNavBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<SabaNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// How much of the bottom of the screen the bar covers, the phone's own
  /// gesture area included. Anything pinned above the bar measures from
  /// this; the cart's checkout button measured without the gesture area and
  /// sat on top of the bar.
  static double coveredHeight(BuildContext context) =>
      AppSizes.navPillHeight +
      AppSizes.navPillInsetBottom +
      MediaQuery.paddingOf(context).bottom;

  /// What a scroll view under the bar pads its bottom by, so its last row
  /// can be scrolled clear of it. A fixed 104 left out the phone's own
  /// gesture area, and on most phones the last row of products stayed under
  /// the bar (BUGS.md 31).
  static double clearance(BuildContext context) =>
      AppSpacing.navSafe + MediaQuery.paddingOf(context).bottom;

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    final isDark = context.isDarkMode;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSizes.navPillInsetX,
        0,
        AppSizes.navPillInsetX,
        AppSizes.navPillInsetBottom + MediaQuery.paddingOf(context).bottom,
      ),
      // Opaque so a tap on the bar's own background never reaches, and
      // scrolls, the content it is floating over.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Container(
          height: AppSizes.navPillHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            color: market.surfaceDark,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: market.onDarkBorder),
            boxShadow: [
              BoxShadow(
                // The bar can no longer separate itself by being darker than
                // the page in dark mode, so the shadow does more of the work.
                color: (isDark ? Colors.black : AppPalette.textPrimary)
                    .withValues(
                      alpha: isDark ? 0.6 : AppElevation.floatOpacity,
                    ),
                blurRadius: AppElevation.floatBlur,
                offset: const Offset(0, AppElevation.floatOffsetY),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Only the selected pill flexes; the icon-only tabs keep their
              // own width. When all five flexed, each was handed an equal
              // fifth, so the pill - which needs icon, label and padding -
              // got the same room as a bare icon and overflowed a narrow
              // phone, while the icons left theirs unused. Now the pill gets
              // every point the icons do not need, and its label shortens
              // before anything runs off the bar.
              for (var index = 0; index < destinations.length; index++)
                if (index == selectedIndex)
                  Flexible(
                    child: _NavItem(
                      destination: destinations[index],
                      isSelected: true,
                      onTap: () => onSelected(index),
                    ),
                  )
                else
                  _NavItem(
                    destination: destinations[index],
                    isSelected: false,
                    onTap: () => onSelected(index),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.isSelected,
    required this.onTap,
  });

  final SabaNavDestination destination;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final market = context.market;

    // Inside the lavender pill the ink is the bar's navy, badge included.
    final foreground = isSelected ? market.surfaceDark : market.onDark;

    // The selected tab's icon is drawn solid, its outline everywhere else.
    final icon = SabaIcon(
      isSelected ? SabaIcons.filled(destination.icon) : destination.icon,
      size: AppSizes.iconLg,
      color: foreground,
    );

    final badged = destination.badgeCount > 0
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              icon,
              PositionedDirectional(
                top: -5,
                end: -7,
                child: _NavBadge(
                  count: destination.badgeCount,
                  isOnActivePill: isSelected,
                ),
              ),
            ],
          )
        : icon;

    return Semantics(
      button: true,
      selected: isSelected,
      label: destination.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: AnimatedContainer(
          duration: AppMotion.chipExpand,
          curve: Curves.easeOut,
          height: AppSizes.navPillActiveHeight,
          padding: EdgeInsets.symmetric(horizontal: isSelected ? 18 : 12),
          decoration: BoxDecoration(
            color: isSelected ? market.onDarkAccent : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              badged,
              if (isSelected) ...[
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    destination.label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.labelLarge?.copyWith(
                      color: foreground,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The count on a navigation icon.
///
/// It carries a 2px ring in whatever it is sitting on, so it reads as a
/// separate object rather than as part of the glyph.
class _NavBadge extends StatelessWidget {
  const _NavBadge({required this.count, required this.isOnActivePill});

  final int count;
  final bool isOnActivePill;

  @override
  Widget build(BuildContext context) {
    final market = context.market;

    return Container(
      constraints: const BoxConstraints(minWidth: AppSizes.navBadge),
      height: AppSizes.navBadge,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isOnActivePill ? market.surfaceDark : market.onDarkAccent,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(
          color: isOnActivePill ? market.onDarkAccent : market.surfaceDark,
          width: 2,
        ),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: context.textStyles.labelSmall?.copyWith(
          color: isOnActivePill ? market.onDark : market.surfaceDark,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}
