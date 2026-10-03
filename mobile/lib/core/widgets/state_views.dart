import 'package:flutter/material.dart';

import '../theme/app_typography.dart';
import '../errors/failure.dart';
import '../localization/failure_messages.dart';
import '../theme/app_dimensions.dart';
import '../theme/saba_icons.dart';
import '../utils/context_extensions.dart';

/// Centered progress indicator for a whole page or panel.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(message!, style: context.textStyles.bodyMedium),
          ],
        ],
      ),
    );
  }
}

/// The standard error state: an icon, a readable message and a retry action
/// when retrying could plausibly help.
class AppErrorView extends StatelessWidget {
  const AppErrorView({
    super.key,
    required this.failure,
    this.onRetry,
    this.compact = false,
  });

  final Failure failure;
  final VoidCallback? onRetry;

  /// Tighter layout for use inside a list section rather than a full page.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final showRetry = onRetry != null && failure.isRetryable;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SabaIcon(
              _iconFor(failure.code),
              size: compact ? 32 : 48,
              color: context.colors.error,
            ),
            SizedBox(height: compact ? AppSpacing.sm : AppSpacing.lg),
            Text(
              failure.localizedMessage(l10n),
              textAlign: TextAlign.center,
              style: compact
                  ? context.textStyles.bodySmall
                  : context.textStyles.bodyMedium,
            ),
            if (showRetry) ...[
              SizedBox(height: compact ? AppSpacing.md : AppSpacing.xl),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: SabaIcon(SabaIcons.refresh, size: AppSizes.iconMd),
                label: Text(l10n.retry),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, AppSizes.buttonHeightSmall),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _iconFor(FailureCode code) => switch (code) {
    FailureCode.network => SabaIcons.wifiOff,
    FailureCode.timeout => SabaIcons.clock,
    FailureCode.notFound => SabaIcons.search,
    FailureCode.authorization => SabaIcons.lock,
    FailureCode.authentication => SabaIcons.user,
    FailureCode.inventory => SabaIcons.box,
    FailureCode.payment => SabaIcons.creditCard,
    _ => SabaIcons.alertCircle,
  };
}

/// The standard empty state: not an error, just nothing to show yet.
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.title,
    this.message,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final String title;
  final String? message;

  /// A [SabaIcons] path. This was typed `IconData` with a Material default,
  /// which is how stock icons kept arriving on screens that had otherwise
  /// been redrawn: the type itself asked every caller for Material's family.
  /// The same change was already needed on `AppButton.icon` and
  /// `AppTextField.prefixIcon` — a parameter's type is what generates the
  /// leak, so the type is what has to change.
  final String? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                color: context.market.surfaceMuted,
                shape: BoxShape.circle,
              ),
              child: SabaIcon(
                icon ?? SabaIcons.archive,
                size: compact ? 28 : 40,
                color: context.colors.onSurfaceVariant,
              ),
            ),
            SizedBox(height: compact ? AppSpacing.md : AppSpacing.xl),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.sectionTitle(context),
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: context.textStyles.bodySmall,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, AppSizes.buttonHeightSmall),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xxl,
                  ),
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
