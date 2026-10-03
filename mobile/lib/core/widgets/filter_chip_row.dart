import 'package:flutter/material.dart';

import '../theme/app_dimensions.dart';
import '../theme/saba_icons.dart';
import '../utils/context_extensions.dart';

/// One chip in a [FilterChipRow].
@immutable
class FilterChipItem {
  const FilterChipItem({
    required this.id,
    required this.label,
    required this.icon,
  });

  final String id;
  final String label;

  /// A [SabaIcons] asset path.
  final String icon;
}

/// `chip/filter` — the expanding chip row.
///
/// Unselected chips are icon-only 44 circles; the selected one expands into a
/// dark pill and reveals its label. That is what keeps the row short enough to
/// fit on a phone while making the current choice unmistakable — a row of
/// full-width labels would either wrap or scroll past the edge.
///
/// The expansion animates over [AppMotion.chipExpand]. In Arabic the row
/// scrolls from the right and the chip expands leftward, which
/// [Directionality] handles for free.
class FilterChipRow extends StatelessWidget {
  const FilterChipRow({
    super.key,
    required this.items,
    required this.selectedId,
    required this.onSelected,
  });

  final List<FilterChipItem> items;

  /// The expanded chip. Null expands none of them.
  final String? selectedId;

  final ValueChanged<FilterChipItem> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSizes.filterChipHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenGutter,
        ),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm + 1),
        itemBuilder: (context, index) {
          final item = items[index];
          return _Chip(
            item: item,
            isSelected: item.id == selectedId,
            onTap: () => onSelected(item),
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final FilterChipItem item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final market = context.market;

    final background = isSelected
        ? context.colors.primary
        : context.colors.surface;
    final foreground = isSelected
        ? context.colors.onPrimary
        : context.colors.onSurface;

    return Semantics(
      button: true,
      selected: isSelected,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: AnimatedContainer(
          duration: AppMotion.chipExpand,
          curve: Curves.easeOut,
          height: AppSizes.filterChipHeight,
          // An icon-only chip is a circle, so its padding has to leave it
          // exactly as wide as it is tall.
          padding: isSelected
              ? const EdgeInsetsDirectional.fromSTEB(13, 0, AppSpacing.lg, 0)
              : const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: isSelected ? null : Border.all(color: market.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SabaIcon(item.icon, color: foreground),
              if (isSelected) ...[
                const SizedBox(width: AppSpacing.sm - 1),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.labelLarge?.copyWith(
                    color: foreground,
                    fontSize: 12.5,
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

/// Picks the line-art icon that stands in for a category or a product.
///
/// The design draws a product without a photograph as a large outline of the
/// thing itself on a neutral tile — never a stretched stock photo. The API has
/// no icon field yet, so this reads the name. Anything it does not recognise
/// still gets a stable icon rather than a blank tile, chosen by position so a
/// row or a grid never repeats itself.
String iconForName(String name, int index) {
  final lower = name.toLowerCase();

  bool has(List<String> words) => words.any(lower.contains);

  // A plain chain, so the first match wins and the order is visible. Each
  // line knows the Arabic words too: names come in the reader's language,
  // and an Arabic name matched nothing, so سماعات got a sofa.
  if (has(['headphone', 'earbud', 'audio', 'speaker', 'sound', 'سماع'])) {
    return SabaIcons.video;
  }
  if (has(['phone', 'smartphone', 'mobile', 'هاتف', 'هواتف', 'موبايل'])) {
    return SabaIcons.phone;
  }
  if (has([
    'laptop',
    'notebook',
    'computer',
    'tablet',
    ' tab ',
    'ipad',
    'book ',
    'حاسوب',
    'حواسيب',
    'تابلت',
    'لوحي',
    'لابتوب',
  ])) {
    return SabaIcons.tablet;
  }
  if (has(['watch', 'clock', 'timer', 'ساعة', 'ساعات'])) return SabaIcons.clock;
  if (has(['camera', 'photo', 'lens', 'كاميرا'])) return SabaIcons.camera;
  if (has(['tv', 'monitor', 'screen', 'display', 'شاشة', 'تلفاز'])) {
    return SabaIcons.video;
  }
  if (has([
    'sofa',
    'chair',
    'table',
    'furnit',
    'home',
    'kitchen',
    'cook',
    'pan',
    'pot',
    'appliance',
    'منزل',
    'مطبخ',
    'أثاث',
    'كنبة',
  ])) {
    return SabaIcons.sofa;
  }
  if (has([
    'hoodie',
    'shirt',
    'dress',
    'jacket',
    'cloth',
    'wear',
    'fashion',
    'shoe',
    'bag',
    'cotton',
  ])) {
    return SabaIcons.handbag;
  }
  if (has(['jewel', 'gold', 'ring', 'diamond'])) return SabaIcons.gem;
  if (has(['grocer', 'food', 'snack', 'drink'])) return SabaIcons.shoppingBag;
  if (has(['car', 'auto', 'tyre', 'tire'])) return SabaIcons.truck;
  if (has(['book', 'station', 'pen', 'paper'])) return SabaIcons.clipboard;
  if (has(['sport', 'fit', 'gym'])) return SabaIcons.trendingUp;
  if (has(['charger', 'cable', 'power', 'battery', 'شاحن', 'كابل', 'بطارية'])) {
    return SabaIcons.card;
  }

  final fallbacks = SabaIcons.categoryFallbacks;
  return fallbacks[index.abs() % fallbacks.length];
}

/// The word-labelled variant of `chip/filter`.
///
/// [FilterChipRow] hides the label until a chip is chosen, which works for
/// categories because the icon already says "phones". A status cannot be
/// drawn: "Shipped" and "Delivered" would be the same parcel glyph, so these
/// chips always carry their words and only the fill changes.
///
/// This is what replaced the tab bars on Orders and Returns. A tab bar with
/// nine tabs builds nine lists and scrolls its own labels under a line; one
/// row of pills filters a single list, which is both the design's language and
/// eight fewer live provider subscriptions.
class TextFilterChips extends StatelessWidget {
  const TextFilterChips({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.screenGutter,
    ),
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final market = context.market;

    return SizedBox(
      height: AppSizes.filterChipHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: labels.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm + 1),
        itemBuilder: (context, index) {
          final isSelected = index == selectedIndex;

          return Semantics(
            button: true,
            selected: isSelected,
            child: InkWell(
              onTap: () => onSelected(index),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: AnimatedContainer(
                duration: AppMotion.chipExpand,
                curve: Curves.easeOut,
                height: AppSizes.filterChipHeight,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg + 2,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? context.colors.primary
                      : context.colors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: isSelected ? null : Border.all(color: market.border),
                ),
                child: Text(
                  labels[index],
                  maxLines: 1,
                  style: context.textStyles.labelLarge?.copyWith(
                    fontSize: 12.5,
                    color: isSelected
                        ? context.colors.onPrimary
                        : context.colors.onSurface,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
