import 'package:flutter/material.dart';

import '../theme/app_typography.dart';
import '../theme/app_dimensions.dart';
import '../theme/saba_icons.dart';
import '../utils/context_extensions.dart';
import 'saba_tile.dart';

/// A bottom sheet that asks for one choice out of a short list.
///
/// The design marks a chosen option with a tick at the end of its row, not
/// with a radio dial at the start: the row itself is the target, and the eye
/// finds the one ticked line faster than it finds the one filled circle.
///
/// Both sort sheets in the app are this widget, so "Newest first" cannot be a
/// radio on one screen and a tick on another.
class OptionSheet<T> extends StatelessWidget {
  const OptionSheet({
    super.key,
    required this.title,
    required this.options,
    required this.labelOf,
    required this.current,
    this.subtitleOf,
  });

  final String title;
  final List<T> options;
  final String Function(T) labelOf;

  /// Null when nothing has been chosen yet.
  final T? current;

  /// A second, quieter line under an option - a subcategory's parent.
  final String? Function(T)? subtitleOf;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.lg + 2,
              AppSpacing.xl,
              AppSpacing.md,
            ),
            child: Text(title, style: AppTypography.subsectionTitle(context)),
          ),
          // Scrolls when the list is longer than the sheet may be tall. As a
          // plain column, ten categories ran off the bottom of the sheet.
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              children: [
                for (final option in options)
                  ChoiceRow(
                    label: labelOf(option),
                    subtitle: subtitleOf?.call(option),
                    isSelected: option == current,
                    onTap: () => Navigator.of(context).pop(option),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A form field that opens an [OptionSheet] instead of a drop-down menu.
///
/// Drawn like the text fields around it - the same label, fill and radius -
/// holding the chosen value, or a hint in the muted colour until there is
/// one. A drop-down opened a floating Material menu over the form, a
/// different look from every other choice in the app.
class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.label,
    required this.onTap,
    this.value,
    this.hint,
    this.errorText,
  });

  final String label;
  final VoidCallback? onTap;

  /// The chosen option's words, or null for none yet.
  final String? value;
  final String? hint;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    final radius = BorderRadius.circular(AppRadius.input);
    final hasError = errorText != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.textStyles.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        Material(
          color: market.surfaceMuted,
          borderRadius: radius,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Container(
              height: AppSizes.inputHeight,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: hasError ? context.colors.error : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value ?? hint ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.bodyMedium?.copyWith(
                        color: value == null
                            ? market.textMuted
                            : context.colors.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  SabaIcon(
                    SabaIcons.chevronDown,
                    size: AppSizes.iconMd,
                    color: market.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            errorText!,
            style: context.textStyles.bodySmall?.copyWith(
              color: context.colors.error,
            ),
          ),
        ],
      ],
    );
  }
}
