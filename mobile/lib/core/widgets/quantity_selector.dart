import 'package:flutter/material.dart';

import '../theme/app_dimensions.dart';
import '../theme/saba_icons.dart';
import '../utils/context_extensions.dart';

/// Minus / value / plus, as the design draws it: a 44 pill with two 32
/// circles inside it.
///
/// At the minimum the decrement is **greyed, not hidden** — a control that
/// disappears leaves the customer looking for it. At the stock ceiling the
/// increment greys the same way.
///
/// [maxQuantity] comes from the server's available stock, so the control can
/// never ask for more than exists. The backend re-checks it anyway: this is a
/// convenience, not the enforcement point (specification section 12).
class QuantitySelector extends StatelessWidget {
  const QuantitySelector({
    super.key,
    required this.quantity,
    required this.onChanged,
    this.minQuantity = 1,
    this.maxQuantity,
    this.isBusy = false,
  });

  final int quantity;
  final ValueChanged<int> onChanged;
  final int minQuantity;
  final int? maxQuantity;

  /// True while an update request is in flight, which locks the control.
  final bool isBusy;

  bool get _canDecrease => !isBusy && quantity > minQuantity;
  bool get _canIncrease =>
      !isBusy && (maxQuantity == null || quantity < maxQuantity!);

  @override
  Widget build(BuildContext context) {
    final market = context.market;

    return Container(
      height: AppSizes.iconCircle,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs + 2),
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border.all(color: market.border),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepButton(
            icon: SabaIcons.minus,
            tooltip: context.l10n.decrease,
            onPressed: _canDecrease ? () => onChanged(quantity - 1) : null,
          ),
          SizedBox(
            width: 30,
            child: Center(
              child: isBusy
                  ? SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.colors.onSurface,
                      ),
                    )
                  : Text(
                      '$quantity',
                      style: context.textStyles.labelLarge?.copyWith(
                        fontSize: 13.5,
                        color: context.colors.onSurface,
                      ),
                    ),
            ),
          ),
          _StepButton(
            icon: SabaIcons.plus,
            tooltip: context.l10n.increase,
            // The design fills only the increment: it is the action the
            // customer is most likely to want, and one filled control in a
            // pair is what makes the pair readable at a glance.
            isPrimary: true,
            onPressed: _canIncrease ? () => onChanged(quantity + 1) : null,
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.isPrimary = false,
  });

  final String icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    final enabled = onPressed != null;

    final (background, foreground) = switch ((isPrimary, enabled)) {
      (true, true) => (context.colors.primary, context.colors.onPrimary),
      (true, false) => (market.surfaceMuted, market.textMuted),
      (false, true) => (market.surfaceMuted, context.colors.onSurface),
      (false, false) => (market.surfaceMuted, market.textMuted),
    };

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: InkResponse(
          onTap: onPressed,
          radius: AppSizes.minTapTarget / 2,
          child: SizedBox(
            width: 34,
            height: AppSizes.iconCircle,
            child: Center(
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: background,
                  shape: BoxShape.circle,
                ),
                child: SabaIcon(icon, size: AppSizes.iconSm, color: foreground),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
