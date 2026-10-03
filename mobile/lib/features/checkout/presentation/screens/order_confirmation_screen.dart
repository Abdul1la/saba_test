import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../orders/domain/entities.dart';
import '../../../orders/presentation/orders_providers.dart';

/// Shown after the server has committed the order.
///
/// The order is read back from the API rather than echoed from local state, so
/// what the customer sees is exactly what was persisted.
class OrderConfirmationScreen extends ConsumerWidget {
  const OrderConfirmationScreen({super.key, required this.orderId});

  final String orderId;

  /// The order exists either way; only the payment may still be unsettled, so
  /// the headline reflects the payment rather than assuming success.
  ///
  /// It did not. Only the mark changed: a failed payment drew a red alert
  /// above the words "Order placed", and the explanation sat further down in
  /// a box of its own. The biggest thing on the screen said one thing and the
  /// picture above it said another. Mark, headline and sentence are one
  /// statement now, and the box below is just the button to re-check.
  static String _headlineIcon(Order order) => switch (order.paymentStatus) {
    PaymentStatus.paid => SabaIcons.check,
    PaymentStatus.pending when order.isCashOnDelivery => SabaIcons.check,
    PaymentStatus.failed || PaymentStatus.cancelled => SabaIcons.alertCircle,
    _ => SabaIcons.clock,
  };

  static (String, String) _headline(AppLocalizations l10n, Order order) =>
      switch (order.paymentStatus) {
        // Cash is paid to the driver, so nothing is "waiting on the payment
        // provider": the order is placed and the customer has cash to ready.
        PaymentStatus.pending when order.isCashOnDelivery => (
          l10n.orderPlaced,
          l10n.codPlacedMessage,
        ),
        PaymentStatus.failed || PaymentStatus.cancelled => (
          l10n.paymentFailedTitle,
          l10n.paymentFailedMessage,
        ),
        PaymentStatus.refunded || PaymentStatus.partiallyRefunded => (
          l10n.orderStatusRefunded,
          l10n.orderPlacedMessage,
        ),
        PaymentStatus.paid => (l10n.orderPlaced, l10n.orderPlacedMessage),
        _ => (l10n.orderPlaced, l10n.paymentPendingMessage),
      };

  static Color _headlineColor(BuildContext context, Order order) =>
      switch (order.paymentStatus) {
        PaymentStatus.paid => context.market.success,
        PaymentStatus.pending when order.isCashOnDelivery =>
          context.market.success,
        PaymentStatus.failed || PaymentStatus.cancelled => context.colors.error,
        _ => context.market.warning,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final order = ref.watch(orderDetailProvider(orderId));

    return PopScope(
      // Going "back" into the checkout flow would be meaningless now, so the
      // system back gesture is taken over rather than swallowed: it used to
      // do nothing at all, which on Android reads as an app that has frozen.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go(AppRoutes.home);
      },
      child: Scaffold(
        body: SafeArea(
          child: AsyncStateView<Order>(
            value: order,
            onRetry: () => ref.invalidate(orderDetailProvider(orderId)),
            // Scrollable: the payment card plus two buttons overflow a short
            // screen when the keyboard-free height is small.
            builder: (value) => SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    decoration: BoxDecoration(
                      color: _headlineColor(
                        context,
                        value,
                      ).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: SabaIcon(
                      _headlineIcon(value),
                      size: 64,
                      color: _headlineColor(context, value),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  Text(
                    _headline(l10n, value).$1,
                    style: AppTypography.screenTitle(context),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _headline(l10n, value).$2,
                    style: context.textStyles.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: context.market.surfaceMuted,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Column(
                      children: [
                        Text(
                          l10n.orderNumber,
                          style: context.textStyles.labelSmall,
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        SelectableText(
                          value.orderNumber,
                          style: context.textStyles.titleMedium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _PaymentStatusCard(order: value),
                  const SizedBox(height: AppSpacing.xxl),
                  AppButton(
                    label: l10n.viewOrder,
                    onPressed: () =>
                        context.go(AppRoutes.orderDetailPath(value.id)),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    label: l10n.continueShopping,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => context.go(AppRoutes.home),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Reports what the backend recorded for this order's payment, and lets the
/// customer re-check.
///
/// Nothing here is inferred from the provider's redirect: the screen re-reads
/// the order and trusts only `paymentStatus` (specification section 14).
class _PaymentStatusCard extends ConsumerStatefulWidget {
  const _PaymentStatusCard({required this.order});

  final Order order;

  @override
  ConsumerState<_PaymentStatusCard> createState() => _PaymentStatusCardState();
}

class _PaymentStatusCardState extends ConsumerState<_PaymentStatusCard> {
  bool _isChecking = false;

  /// Re-reads the order and waits for the answer.
  ///
  /// This used to be a bare `ref.invalidate`, and the view it refreshes keeps
  /// its current content during a refresh — so on the one screen where the
  /// customer is anxiously waiting for a payment to settle, tapping Check
  /// produced no spinner, no disable and, when nothing had changed, no
  /// visible response at all. So they tapped it again, and again.
  Future<void> _check() async {
    setState(() => _isChecking = true);
    try {
      ref.invalidate(orderDetailProvider(widget.order.id));
      await ref.read(orderDetailProvider(widget.order.id).future);
    } catch (_) {
      // The rebuilt view reports the failure; this only has to stop spinning.
    }
    if (!mounted) return;
    setState(() => _isChecking = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final order = widget.order;

    // Cash is settled at the door, so there is nothing to re-check.
    final isUnsettled =
        !order.isCashOnDelivery &&
        (order.paymentStatus == PaymentStatus.pending ||
            order.paymentStatus == PaymentStatus.processing);

    // "Order placed" is not the same fact as "we took the money" — a cash
    // order says the first and not the second — so the payment keeps its own
    // line. What it lost is the bordered box it used to sit in, and its
    // duplicate sentence: the headline above says that part now.
    //
    // A failed payment is the exception. There the headline *is* the payment,
    // so saying it again here would be the same sentence twice.
    final (label, colour) = switch (order.paymentStatus) {
      PaymentStatus.paid => (l10n.paymentConfirmed, context.market.success),
      PaymentStatus.refunded || PaymentStatus.partiallyRefunded => (
        l10n.orderStatusRefunded,
        context.market.warning,
      ),
      PaymentStatus.failed || PaymentStatus.cancelled => (null, null),
      PaymentStatus.pending when order.isCashOnDelivery => (
        l10n.payOnDelivery,
        context.market.info,
      ),
      _ => (l10n.paymentPending, context.market.warning),
    };

    if (label == null) return const SizedBox.shrink();

    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SabaIcon(
              order.isCashOnDelivery
                  ? SabaIcons.truck
                  : _statusMark(order.paymentStatus),
              size: AppSizes.iconSm,
              color: colour,
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: context.textStyles.titleSmall?.copyWith(color: colour),
              ),
            ),
          ],
        ),
        if (isUnsettled) ...[
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: l10n.checkPaymentStatus,
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.small,
            icon: SabaIcons.refresh,
            isLoading: _isChecking,
            onPressed: _check,
          ),
        ],
      ],
    );
  }

  static String _statusMark(PaymentStatus status) => switch (status) {
    PaymentStatus.paid => SabaIcons.check,
    _ => SabaIcons.clock,
  };
}
