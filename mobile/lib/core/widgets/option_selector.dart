import 'package:flutter/material.dart';

import '../theme/app_dimensions.dart';
import '../theme/saba_icons.dart';
import '../utils/context_extensions.dart';

/// One choice in an [OptionSelector].
@immutable
class OptionValue {
  const OptionValue({required this.value, this.isAvailable = true});

  final String value;

  /// An unavailable combination stays **visible and struck through**, and is
  /// still tappable. Hiding it makes the customer think the product changed.
  final bool isAvailable;
}

/// `size/option selector` — the row of boxes under a variant name.
///
/// Short values get a 48 square; word-length values size to their content, so
/// "S / M / L" and "128 GB / 256 GB" are the same component.
class OptionSelector extends StatelessWidget {
  const OptionSelector({
    super.key,
    required this.values,
    required this.selected,
    required this.onSelected,
  });

  final List<OptionValue> values;
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm + 1,
      runSpacing: AppSpacing.sm + 1,
      children: [
        for (final option in values)
          _OptionBox(
            option: option,
            isSelected: option.value == selected,
            onTap: () => onSelected(option.value),
          ),
      ],
    );
  }
}

class _OptionBox extends StatelessWidget {
  const _OptionBox({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  final OptionValue option;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    final available = option.isAvailable;

    final (background, foreground, border) = switch ((isSelected, available)) {
      (true, _) => (context.colors.primary, context.colors.onPrimary, null),
      (false, true) => (
        context.colors.surface,
        context.colors.onSurface,
        market.border,
      ),
      (false, false) => (
        market.surfaceMuted,
        market.textMuted,
        market.surfaceMuted,
      ),
    };

    return Semantics(
      button: true,
      selected: isSelected,
      enabled: available,
      label: option.value,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.action),
        child: Container(
          height: AppSizes.minTapTarget,
          constraints: const BoxConstraints(minWidth: AppSizes.minTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppRadius.action),
            border: border == null ? null : Border.all(color: border),
          ),
          child: Text(
            option.value,
            style: context.textStyles.labelLarge?.copyWith(
              color: foreground,
              decoration: available ? null : TextDecoration.lineThrough,
              decorationColor: foreground,
            ),
          ),
        ),
      ),
    );
  }
}

/// The colour swatches, stacked vertically beside the product image.
///
/// A selected swatch carries a **tick**, not just a ring, because a ring alone
/// is invisible on a light colour and to anyone who cannot separate the two
/// hues. The colour name is announced to screen readers and shown in the
/// label above the row.
class ColourSwatchColumn extends StatelessWidget {
  const ColourSwatchColumn({
    super.key,
    required this.values,
    required this.selected,
    required this.onSelected,
    this.colours = const <String, String>{},
    this.inRow = false,
  });

  final List<OptionValue> values;
  final String? selected;
  final ValueChanged<String> onSelected;

  /// Option value to `#RRGGBB`, straight from the catalogue.
  final Map<String, String> colours;

  /// Side by side under the option's label, rather than stacked.
  final bool inRow;

  @override
  Widget build(BuildContext context) {
    if (inRow) {
      // Each colour named under its circle: a circle alone left the shopper
      // guessing "navy or black?" (the tester).
      return Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        children: [
          for (final option in values)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Swatch(
                  option: option,
                  hex: colours[option.value],
                  isSelected: option.value == selected,
                  onTap: () => onSelected(option.value),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 72),
                  child: Text(
                    option.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: context.textStyles.labelSmall?.copyWith(
                      fontWeight: option.value == selected
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final option in values)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _Swatch(
              option: option,
              hex: colours[option.value],
              isSelected: option.value == selected,
              onTap: () => onSelected(option.value),
            ),
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.option,
    required this.hex,
    required this.isSelected,
    required this.onTap,
  });

  final OptionValue option;
  final String? hex;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    final fill = colourFor(option.value, hex: hex) ?? market.surfaceMuted;
    // A tick on a pale swatch has to be dark to be seen at all.
    final tick = fill.computeLuminance() > 0.55
        ? market.surfaceDark
        : market.onDark;

    return Semantics(
      button: true,
      selected: isSelected,
      enabled: option.isAvailable,
      label: option.value,
      child: InkResponse(
        onTap: onTap,
        radius: AppSizes.minTapTarget / 2,
        child: SizedBox(
          width: AppSizes.minTapTarget,
          height: 38,
          child: Center(
            child: Opacity(
              opacity: option.isAvailable ? 1 : 0.5,
              child: Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: fill,
                  shape: BoxShape.circle,
                  border: Border.all(color: context.colors.surface, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: isSelected
                          ? context.colors.onSurface
                          : market.borderStrong,
                      spreadRadius: isSelected ? 2 : 1,
                    ),
                  ],
                ),
                child: isSelected
                    ? SabaIcon(SabaIcons.check, size: 14, color: tick)
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Resolves a colour option value to an actual colour.
///
/// [hex] is what the catalogue supplied for this value and always wins. The
/// name table below is the fallback for a seller who gave a name and no
/// value, and it is deliberately short: a name nobody recognises returns null
/// and the caller falls back to [OptionSelector], which shows the word in a
/// box. An unusual colour still works, it just does not get a dot.
Color? colourFor(String name, {String? hex}) {
  final parsed = _parseHex(hex);
  if (parsed != null) return parsed;

  final key = name.trim().toLowerCase();
  return const <String, Color>{
    'black': Color(0xFF14181D),
    'white': Color(0xFFF7F8FA),
    'grey': Color(0xFF8A99AB),
    'gray': Color(0xFF8A99AB),
    'silver': Color(0xFFC3CAD3),
    'navy': Color(0xFF1B2440),
    'blue': Color(0xFF1A56C4),
    'sky': Color(0xFF6BA9E8),
    'green': Color(0xFF127346),
    'olive': Color(0xFF6B7A3A),
    'red': Color(0xFFB32D1C),
    'maroon': Color(0xFF6E1F16),
    'pink': Color(0xFFE58FA8),
    'purple': Color(0xFF6B4BA8),
    'orange': Color(0xFFD9600B),
    'yellow': Color(0xFFE8B23D),
    'gold': Color(0xFFC9A227),
    'beige': Color(0xFFD9CFBA),
    'cream': Color(0xFFEFE7D6),
    'brown': Color(0xFF6B4A2E),
    'tan': Color(0xFF8A7B63),
    'khaki': Color(0xFF9A8C6A),
    'teal': Color(0xFF127A7A),
    'أسود': Color(0xFF14181D),
    'أبيض': Color(0xFFF7F8FA),
    'رمادي': Color(0xFF8A99AB),
    'كحلي': Color(0xFF1B2440),
    'أزرق': Color(0xFF1A56C4),
    'أخضر': Color(0xFF127346),
    'أحمر': Color(0xFFB32D1C),
    'بني': Color(0xFF6B4A2E),
    'بيج': Color(0xFFD9CFBA),
    'ذهبي': Color(0xFFC9A227),
  }[key];
}

/// `#RRGGBB` or `#AARRGGBB`, with or without the hash. Null for anything
/// else, including an empty string and a malformed value.
Color? _parseHex(String? hex) {
  if (hex == null) return null;
  final digits = hex.trim().replaceFirst('#', '');
  if (digits.length != 6 && digits.length != 8) return null;
  final value = int.tryParse(digits, radix: 16);
  if (value == null) return null;
  return Color(digits.length == 6 ? 0xFF000000 | value : value);
}

/// True when every value in an option is a colour we can draw.
///
/// One unrecognised value sends the whole option back to boxes, because a row
/// that is half dots and half words reads as broken.
bool isColourOption(
  String name,
  List<String> values, {
  Map<String, String> colours = const <String, String>{},
}) {
  final lower = name.trim().toLowerCase();
  const names = {'colour', 'color', 'اللون', 'لون'};
  if (!names.contains(lower)) return false;
  return values.every((value) => colourFor(value, hex: colours[value]) != null);
}
