import 'package:flutter/material.dart';

import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../../core/widgets/filter_chip_row.dart';
import '../../domain/entities.dart';

/// A category's sub-categories as round pictures with their names, above its
/// products (the user's call, 2026-10-05): "All" first, then each one, with
/// the picture Saba's admin gave it, or an icon. It scrolls away with the
/// products, which stay what the screen is for; a category with no
/// sub-categories shows nothing.
class SubcategoryCircles extends StatelessWidget {
  const SubcategoryCircles({
    super.key,
    required this.parent,
    required this.selectedId,
    required this.onSelected,
  });

  /// The main category; its [Category.children] are drawn.
  final Category parent;

  /// The chosen sub-category, null for all of [parent].
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  static const double _circle = 60;

  @override
  Widget build(BuildContext context) {
    final children = parent.children;
    if (children.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: _circle + 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: children.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _Circle(
              label: context.l10n.all,
              icon: SabaIcons.grid,
              isSelected: selectedId == null,
              onTap: () => onSelected(null),
            );
          }
          final child = children[index - 1];
          return _Circle(
            label: child.name,
            icon: iconForName(child.name, index),
            imageUrl: child.imageUrl,
            isSelected: child.id == selectedId,
            onTap: () => onSelected(child.id),
          );
        },
      ),
    );
  }
}

class _Circle extends StatelessWidget {
  const _Circle({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    this.imageUrl,
  });

  final String label;

  /// Drawn when there is no picture, or it has not loaded.
  final String icon;
  final String? imageUrl;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    final brand = context.colors.primary;
    const size = SubcategoryCircles._circle;

    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: SizedBox(
          width: size + 14,
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.xs),
              // The chosen one wears a ring in the brand colour.
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: size + 6,
                height: size + 6,
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? brand : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: ClipOval(
                  child: AppNetworkImage(
                    url: imageUrl,
                    width: size,
                    height: size,
                    radius: 0,
                    fallback: Container(
                      color: isSelected
                          ? brand.withValues(alpha: 0.12)
                          : market.surfaceMuted,
                      alignment: Alignment.center,
                      child: SabaIcon(
                        icon,
                        size: 24,
                        color: isSelected ? brand : market.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs + 2),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: context.textStyles.labelSmall?.copyWith(
                  fontSize: 12,
                  height: 1.2,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? context.colors.onSurface
                      : market.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
