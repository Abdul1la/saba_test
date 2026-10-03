import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_dimensions.dart';
import '../theme/saba_icons.dart';
import '../utils/context_extensions.dart';

/// Three levels, so the main action reads as the main action:
///
/// * `primary` — solid purple, white words. One per screen: the thing the
///   person came to do.
/// * `secondary` — outlined, purple words on the surface.
/// * `text` — tertiary: words only.
///
/// And red for removing or cancelling, never for anything else: `danger` is
/// the filled red bar; `dangerText` is the quiet variant for a destructive
/// action that is real but rare — cancelling an order, deleting an address —
/// where a full red bar beside the ordinary actions invites exactly the
/// mis-tap it matters most to avoid.
enum AppButtonVariant { primary, secondary, text, danger, dangerText }

/// `large` is for the one action a screen exists for, such as Continue on the
/// role choice.
enum AppButtonSize { large, regular, small }

/// The app's button.
///
/// Handles the busy state itself so no screen has to reimplement "disable the
/// button and show a spinner while the request is in flight".
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.regular,
    this.icon,
    this.isLoading = false,
    this.iconTrailing = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;

  /// A [SabaIcons] path. The design ships its own icon set; a button that
  /// took an [IconData] could only ever draw Material's, which is what made
  /// the first pass still read as the old app.
  final String? icon;

  /// While true the button is disabled and shows a spinner in place of its
  /// label, which also prevents double submission.
  final bool isLoading;

  /// Puts [icon] after the label. See [_content].
  final bool iconTrailing;

  final bool expand;

  @override
  Widget build(BuildContext context) {
    final height = switch (size) {
      AppButtonSize.large => AppSizes.buttonHeightLarge,
      AppButtonSize.regular => AppSizes.buttonHeight,
      AppButtonSize.small => AppSizes.buttonHeightSmall,
    };
    // Null keeps the theme's label style.
    final textStyle = size == AppButtonSize.large
        ? context.textStyles.labelLarge?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          )
        : null;
    final minimumSize = expand ? Size.fromHeight(height) : Size(0, height);
    final padding = EdgeInsets.symmetric(
      horizontal: expand ? AppSpacing.lg : AppSpacing.xl,
    );

    final effectiveOnPressed = isLoading ? null : onPressed;
    final child = _content(context);

    final button = switch (variant) {
      AppButtonVariant.primary => FilledButton(
        onPressed: effectiveOnPressed,
        style: FilledButton.styleFrom(
          minimumSize: minimumSize,
          padding: padding,
          textStyle: textStyle,
        ),
        child: child,
      ),
      AppButtonVariant.secondary => OutlinedButton(
        onPressed: effectiveOnPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: minimumSize,
          padding: padding,
          textStyle: textStyle,
        ),
        child: child,
      ),
      AppButtonVariant.text => TextButton(
        onPressed: effectiveOnPressed,
        style: TextButton.styleFrom(
          minimumSize: minimumSize,
          padding: padding,
          textStyle: textStyle,
        ),
        child: child,
      ),
      AppButtonVariant.dangerText => TextButton(
        onPressed: effectiveOnPressed,
        style: TextButton.styleFrom(
          minimumSize: minimumSize,
          padding: padding,
          textStyle: textStyle,
          foregroundColor: Theme.of(context).colorScheme.error,
        ),
        child: child,
      ),
      AppButtonVariant.danger => FilledButton(
        onPressed: effectiveOnPressed,
        style: FilledButton.styleFrom(
          minimumSize: minimumSize,
          padding: padding,
          textStyle: textStyle,
          backgroundColor: Theme.of(context).colorScheme.error,
          foregroundColor: Theme.of(context).colorScheme.onError,
        ),
        child: child,
      ),
    };

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }

  Widget _content(BuildContext context) {
    if (isLoading) {
      return SizedBox(
        height: AppSizes.iconMd,
        width: AppSizes.iconMd,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(_foregroundFor(context)),
        ),
      );
    }

    // One line, always: the button's height is pinned by minimumSize, so a
    // second line would overflow it. A label too long for the width shrinks
    // to fit rather than ending in "…" - "Start the de…" read as broken.
    // Arabic and a raised system font scale both reach it.
    if (icon == null) {
      return FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1));
    }

    final glyph = SabaIcon(
      icon!,
      size: size == AppButtonSize.large ? AppSizes.iconLg : AppSizes.iconMd,
      color: _foregroundFor(context),
    );
    final text = Text(label, maxLines: 1);

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // An icon that labels the action leads; one that points at where the
          // action goes follows. "Add to cart" wants its bag in front of the
          // words, "Continue ›" wants its chevron after them - a chevron on the
          // left is pointing back at the text it is supposed to lead away from.
          if (!iconTrailing) ...[glyph, const SizedBox(width: AppSpacing.sm)],
          text,
          if (iconTrailing) ...[const SizedBox(width: AppSpacing.sm), glyph],
        ],
      ),
    );
  }

  Color _foregroundFor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (variant) {
      AppButtonVariant.primary => scheme.onPrimary,
      AppButtonVariant.danger => scheme.onError,
      AppButtonVariant.dangerText => scheme.error,
      _ => scheme.primary,
    };
  }
}

/// `button/corner-action` — the small dark rounded square in the bottom
/// trailing corner of a product card.
///
/// One tap adds to cart. It confirms **in place** — a tick for 1.2 seconds —
/// instead of firing a snackbar for every add, because a customer adding four
/// things in a row should not be interrupted four times. A failure turns into
/// an error state the customer can tap again, and that one does announce
/// itself, because a silent failure is the thing worth interrupting for.
class CornerActionButton extends StatefulWidget {
  const CornerActionButton({
    super.key,
    required this.onPressed,
    required this.tooltip,
    this.icon,
    this.label,
    this.color,
    this.onColor,
  });

  /// Returns `true` when the item was added. `null` disables the button, which
  /// is what out of stock looks like.
  final Future<bool> Function()? onPressed;
  final String tooltip;

  /// Defaults to the design's bag icon.
  final String? icon;

  /// When set, the button is a pill that fills its width and carries this
  /// word beside the icon — the flash-sale card's "Add to cart". Same states,
  /// same confirm in place; the tick comes with "Added to cart" in words.
  final String? label;

  /// The fill at rest and the ink on it; the primary purple when null. The
  /// flash-sale card's is amber, with navy ink.
  final Color? color;
  final Color? onColor;

  @override
  State<CornerActionButton> createState() => _CornerActionButtonState();
}

enum _CornerState { idle, loading, added, failed }

class _CornerActionButtonState extends State<CornerActionButton> {
  _CornerState _state = _CornerState.idle;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    if (_state == _CornerState.loading) return;
    _reset?.cancel();
    setState(() => _state = _CornerState.loading);

    final ok = await widget.onPressed!();
    if (!mounted) return;

    setState(() => _state = ok ? _CornerState.added : _CornerState.failed);
    _reset = Timer(AppMotion.confirmInPlace, () {
      if (mounted) setState(() => _state = _CornerState.idle);
    });
  }

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    final enabled = widget.onPressed != null;

    final (background, foreground) = switch (_state) {
      _CornerState.added => (market.success, market.onAccent),
      _CornerState.failed => (context.colors.error, context.colors.onError),
      _ when !enabled => (market.surfaceMuted, market.outOfStock),
      _ => (
        widget.color ?? context.colors.primary,
        widget.onColor ?? context.colors.onPrimary,
      ),
    };

    final label = switch (_state) {
      _CornerState.added => context.l10n.addedToCart,
      _CornerState.failed => context.l10n.retry,
      _ => widget.tooltip,
    };

    if (widget.label != null) {
      return _pill(enabled, background, foreground);
    }

    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: InkResponse(
          onTap: enabled && _state != _CornerState.loading ? _run : null,
          radius: AppSizes.minTapTarget / 2,
          child: SizedBox(
            width: AppSizes.minTapTarget,
            height: AppSizes.minTapTarget,
            // Bottom-aligned inside its tap box so the visible square sits on
            // the same baseline as the price beside it.
            child: Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedContainer(
                duration: AppMotion.press,
                width: AppSizes.cornerAction,
                height: AppSizes.cornerAction,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(AppRadius.action),
                ),
                child: switch (_state) {
                  _CornerState.loading => SizedBox(
                    width: AppSizes.iconSm,
                    height: AppSizes.iconSm,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: foreground,
                    ),
                  ),
                  _CornerState.added => SabaIcon(
                    SabaIcons.check,
                    color: foreground,
                  ),
                  _CornerState.failed => SabaIcon(
                    SabaIcons.refresh,
                    color: foreground,
                  ),
                  _CornerState.idle => SabaIcon(
                    widget.icon ?? SabaIcons.bag,
                    color: foreground,
                  ),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The [label] form. Its words are its accessible name, so it needs no
  /// tooltip; it looks 40 tall and answers a full 48.
  Widget _pill(bool enabled, Color background, Color foreground) {
    final (String? icon, String text) = switch (_state) {
      _CornerState.loading => (null, widget.label!),
      _CornerState.added => (SabaIcons.check, context.l10n.addedToCart),
      _CornerState.failed => (SabaIcons.refresh, context.l10n.retry),
      _CornerState.idle => (widget.icon ?? SabaIcons.bag, widget.label!),
    };

    return FilledButton(
      onPressed: enabled && _state != _CornerState.loading ? _run : null,
      style: FilledButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        // Busy keeps the pill's own colours; only out of stock looks off.
        disabledBackgroundColor: background,
        disabledForegroundColor: foreground,
        minimumSize: const Size(0, AppSizes.cornerAction),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        tapTargetSize: MaterialTapTargetSize.padded,
        visualDensity: VisualDensity.standard,
      ),
      child: icon == null
          ? Semantics(
              label: text,
              child: SizedBox(
                width: AppSizes.iconSm,
                height: AppSizes.iconSm,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foreground,
                ),
              ),
            )
          // Shrinks a touch rather than trailing off: "Added to your cart"
          // is a few points wider than the pill, and a confirmation that
          // ends in "…" reads as broken.
          : FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SabaIcon(icon, size: AppSizes.iconSm, color: foreground),
                  const SizedBox(width: AppSpacing.sm - 2),
                  Text(text, maxLines: 1),
                ],
              ),
            ),
    );
  }
}
