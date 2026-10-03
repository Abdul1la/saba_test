import 'package:flutter/material.dart';

import '../theme/app_typography.dart';
import '../constants/app_constants.dart';
import '../errors/failure.dart';
import '../localization/failure_messages.dart';
import '../theme/app_dimensions.dart';
import '../theme/saba_icons.dart';
import '../utils/context_extensions.dart';
import 'app_button.dart';

/// Confirmation dialogs and snack bars.
///
/// Every destructive action routes through [AppDialogs.confirm] so the
/// wording, the button order and the RTL behaviour stay consistent
/// (specification section 59).
class AppDialogs {
  const AppDialogs._();

  /// Returns true only when the user explicitly confirms.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    String? message,
    String? confirmLabel,
    String? cancelLabel,
    bool isDestructive = false,
  }) async {
    final l10n = context.l10n;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        titleTextStyle: AppTypography.subsectionTitle(dialogContext),
        title: Text(title),
        content: message == null ? null : Text(message),
        actions: [
          DialogActions(
            cancelLabel: cancelLabel,
            onCancel: () => Navigator.of(dialogContext).pop(false),
            confirmLabel: confirmLabel ?? l10n.confirm,
            onConfirm: () => Navigator.of(dialogContext).pop(true),
            isDestructive: isDestructive,
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// A modal bottom sheet sized to its content, scrollable when tall.
  static Future<T?> bottomSheet<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    bool isScrollControlled = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      useSafeArea: true,
      // Above the whole app, not inside the current tab. Opened from a tab,
      // the sheet went into that tab's navigator - underneath the floating
      // navigation bar, which covered its field and its button.
      useRootNavigator: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: builder(sheetContext),
      ),
    );
  }
}

/// The foot of every dialog: the way out and the action, equal width, side by
/// side. In Arabic they mirror with the rest of the dialog.
///
/// The theme makes a filled button full width, so a dialog's own action row
/// could never hold two: it stacked a small bare "Cancel" above a wide bar,
/// and the way out read as a footnote under the one real button.
class DialogActions extends StatelessWidget {
  const DialogActions({
    super.key,
    required this.confirmLabel,
    required this.onConfirm,
    this.cancelLabel,
    this.onCancel,
    this.isDestructive = false,
  });

  final String confirmLabel;
  final VoidCallback? onConfirm;

  /// "Cancel" unless the dialog names what backing out keeps.
  final String? cancelLabel;

  /// Closes the dialog unless given.
  final VoidCallback? onCancel;

  /// Paints the action in the error colour.
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: AppButton(
            label: cancelLabel ?? context.l10n.cancel,
            variant: AppButtonVariant.secondary,
            onPressed: onCancel ?? () => Navigator.of(context).pop(),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: AppButton(
            label: confirmLabel,
            variant: isDestructive
                ? AppButtonVariant.danger
                : AppButtonVariant.primary,
            onPressed: onConfirm,
          ),
        ),
      ],
    );
  }
}

/// Transient feedback messages.
class AppSnackBar {
  const AppSnackBar._();

  /// [actionLabel] puts the obvious next step inside the message itself.
  /// "Added to cart" with nothing to press leaves someone hunting for the
  /// cart tab to check what just happened.
  static void success(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) => _show(
    context,
    message: message,
    icon: SabaIcons.check,
    background: context.market.success,
    actionLabel: actionLabel,
    onAction: onAction,
  );

  static void info(BuildContext context, String message) => _show(
    context,
    message: message,
    icon: SabaIcons.info,
    background: context.market.info,
  );

  /// Shows a localized message for a typed failure.
  static void failure(BuildContext context, Failure failure) => _show(
    context,
    message: failure.localizedMessage(context.l10n),
    icon: SabaIcons.alertCircle,
    background: context.colors.error,
  );

  static void error(BuildContext context, String message) => _show(
    context,
    message: message,
    icon: SabaIcons.alertCircle,
    background: context.colors.error,
  );

  static void _show(
    BuildContext context, {
    required String message,
    required String icon,
    required Color background,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    // White on the light-mode fills, dark on the dark-mode ones: white on
    // dark mode's green was 2:1.
    final ink = context.market.onAccent;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: AppConstants.snackBarDuration,
          // Flutter keeps a snack bar that has an action on screen until it
          // is dismissed by hand, so "Added to your cart - Cart" and "Item
          // removed - Undo" never went away. These are passing notes; the
          // action is a shortcut, not a question that must be answered.
          persist: false,
          backgroundColor: background,
          action: actionLabel == null || onAction == null
              ? null
              : SnackBarAction(
                  label: actionLabel,
                  textColor: ink,
                  onPressed: onAction,
                ),
          content: Row(
            children: [
              SabaIcon(icon, color: ink, size: AppSizes.iconMd),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(message, style: TextStyle(color: ink)),
              ),
            ],
          ),
        ),
      );
  }
}
