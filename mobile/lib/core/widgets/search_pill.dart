import 'package:flutter/material.dart';

import '../theme/app_dimensions.dart';
import '../theme/saba_icons.dart';
import '../utils/context_extensions.dart';

/// `input/search` — a tappable pill, not a live field.
///
/// Typing happens on the search screen, which owns suggestions and history, so
/// this never takes focus and never shows a keyboard. It reads as a button to
/// a screen reader for exactly that reason.
class SearchPill extends StatelessWidget {
  const SearchPill({super.key, required this.hint, required this.onTap});

  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final market = context.market;

    return Semantics(
      button: true,
      label: hint,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          height: AppSizes.buttonHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl - 4),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: market.border),
          ),
          child: Row(
            children: [
              SabaIcon(
                SabaIcons.search,
                color: context.colors.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.bodyMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `button/icon-circle` — back, share, favourite, filter, notifications.
///
/// Visible size is [size], the tap target is always at least
/// [AppSizes.minTapTarget]. Every one of these carries an accessibility
/// label, because the icon alone is not the name of the action.
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.size = AppSizes.iconCircle,
    this.filled = false,
  });

  final String icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final double size;

  /// Purple circle with an inverted icon, for the one action beside a
  /// search bar. Otherwise a neutral circle with a hairline.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    final enabled = onPressed != null;

    final background = filled ? context.colors.primary : context.colors.surface;
    final foreground = filled
        ? context.colors.onPrimary
        : context.colors.onSurface;

    final tap = size < AppSizes.minTapTarget ? AppSizes.minTapTarget : size;

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: InkResponse(
          onTap: onPressed,
          radius: tap / 2,
          child: SizedBox(
            width: tap,
            height: tap,
            child: Center(
              child: Opacity(
                opacity: enabled ? 1 : 0.4,
                child: Container(
                  width: size,
                  height: size,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: background,
                    shape: BoxShape.circle,
                    border: filled ? null : Border.all(color: market.border),
                  ),
                  child: SabaIcon(icon, color: foreground),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
