import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_typography.dart';
import '../../orders/presentation/widgets/order_notes.dart';

import '../../../core/theme/app_dimensions.dart';
import '../../../core/utils/context_extensions.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/iraqi_phone.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/call_button.dart';
import '../../../core/widgets/saba_tile.dart';
import '../../auth/presentation/widgets/iraqi_phone_field.dart';
import '../domain/entities.dart';
import 'merchant_providers.dart';
import 'widgets/merchant_widgets.dart';

/// Moves one order to its next fulfilment state.
///
/// Shared by the order list and the order detail screen: both advance the
/// same order through the same table, and a second copy of this flow is how
/// the card and its own detail screen end up disagreeing about what happens
/// next — or asking for a tracking number in only one of the two places.
///
/// Returns the state the order reached, or null when nothing changed.
Future<String?> advanceMerchantOrder(
  BuildContext context,
  WidgetRef ref,
  MerchantOrderRow order,
) async {
  final next = MerchantOrderStatus.next(order.status);
  if (next == null) return null;

  // Confirming follows a call: most cash orders that go wrong are ones
  // nobody checked by voice - a wrong number, a joke, a changed mind.
  if (next == 'CONFIRMED') {
    final called = await AppDialogs.bottomSheet<bool>(
      context,
      isScrollControlled: false,
      builder: (_) => _CallFirstSheet(phone: order.customerPhone),
    );
    if (called != true || !context.mounted) return null;
  }

  // Shipping says who is bringing it, so the shopper can call them.
  Courier? courier;
  if (next == 'SHIPPED') {
    courier = await AppDialogs.bottomSheet<Courier>(
      context,
      builder: (_) => const _CourierSheet(),
    );
    if (courier == null || !context.mounted) return null;
  }

  final result = await ref
      .read(merchantRepositoryProvider)
      .updateOrderStatus(orderId: order.id, status: next, courier: courier);
  if (!context.mounted) return null;

  return result.fold(
    ok: (_) {
      _refresh(ref, order.id);
      AppSnackBar.success(context, MerchantOrderStatus.label(context, next));
      return next;
    },
    err: (failure) {
      AppSnackBar.failure(context, failure);
      return null;
    },
  );
}

/// Refuses one order, with a reason, and refunds the customer.
///
/// The reason is asked for because the customer is about to be told one, and
/// because a merchant who has to name the cause declines fewer orders out of
/// habit. Nothing is sent until they pick.
///
/// Returns true when the order was declined.
Future<bool> declineMerchantOrder(
  BuildContext context,
  WidgetRef ref,
  MerchantOrderRow order,
) async {
  final reason = await AppDialogs.bottomSheet<String>(
    context,
    isScrollControlled: false,
    builder: (_) => const _DeclineSheet(),
  );
  if (reason == null || !context.mounted) return false;

  final result = await ref
      .read(merchantRepositoryProvider)
      .updateOrderStatus(
        orderId: order.id,
        status: 'CANCELLED',
        reason: reason,
      );
  if (!context.mounted) return false;

  return result.fold(
    ok: (_) {
      _refresh(ref, order.id);
      AppSnackBar.success(context, context.l10n.orderDeclined);
      return true;
    },
    err: (failure) {
      AppSnackBar.failure(context, failure);
      return false;
    },
  );
}

/// The shopper refused the parcel at the door: nothing is paid, and the
/// things come back to the shelf.
Future<bool> refuseMerchantOrder(
  BuildContext context,
  WidgetRef ref,
  MerchantOrderRow order,
) async {
  final l10n = context.l10n;
  final sure = await AppDialogs.confirm(
    context,
    title: l10n.refusedAtDoor,
    message: l10n.refusedConfirm,
    confirmLabel: l10n.refusedAtDoor,
    isDestructive: true,
  );
  if (!sure || !context.mounted) return false;
  final result = await ref
      .read(merchantRepositoryProvider)
      .updateOrderStatus(orderId: order.id, status: 'REFUSED');
  if (!context.mounted) return false;
  return result.fold(
    ok: (_) {
      _refresh(ref, order.id);
      AppSnackBar.success(context, l10n.orderStatusRefused);
      return true;
    },
    err: (failure) {
      AppSnackBar.failure(context, failure);
      return false;
    },
  );
}

/// The store's answer to a return: approve it and go and collect the item,
/// decline it, or - once collected - say the cash was handed back.
Future<void> answerMerchantReturn(
  BuildContext context,
  WidgetRef ref, {
  required String orderId,
  required String returnId,
  required String status,
}) async {
  // Each answer asked first, and a decline says why: one tap approved,
  // refunded or declined, with no reason for the shopper (the tester).
  final l10n = context.l10n;
  String? reason;
  switch (status) {
    case 'REJECTED':
      reason = await AppDialogs.bottomSheet<String>(
        context,
        builder: (_) =>
            const _DeclineSheet(codes: returnDeclineCodes, returns: true),
      );
      if (reason == null) return;
    case 'APPROVED':
      if (!await AppDialogs.confirm(
        context,
        title: l10n.approveReturn,
        message: l10n.confirmApproveReturn,
      )) {
        return;
      }
    case 'REFUNDED':
      if (!await AppDialogs.confirm(
        context,
        title: l10n.cashHandedBack,
        message: l10n.confirmCashBack,
      )) {
        return;
      }
  }
  if (!context.mounted) return;
  final result = await ref
      .read(merchantRepositoryProvider)
      .answerReturn(returnId, status, reason: reason);
  if (!context.mounted) return;
  result.fold(
    ok: (_) => _refresh(ref, orderId),
    err: (failure) => AppSnackBar.failure(context, failure),
  );
}

/// Everything an order change can move: the queue, this order, the pill
/// counts and the dashboard's to-do list. Missing one of these is how a
/// merchant confirms an order and watches the dashboard keep asking.
void _refresh(WidgetRef ref, String orderId) {
  ref.invalidate(merchantOrdersProvider);
  ref.invalidate(merchantOrderDetailProvider(orderId));
  ref.invalidate(merchantOrderCountsProvider);
  ref.invalidate(merchantDashboardProvider);
  // A delivery is a sale: "What you owe Saba" and Analytics kept the old
  // numbers until the app was reloaded (the tester).
  ref.invalidate(sabaBillsProvider);
  ref.invalidate(merchantAnalyticsProvider);
  // A refund puts the item back on the shelf: "My products" kept the old
  // stock until a reload (the tester).
  ref.invalidate(merchantProductsProvider);
  ref.invalidate(merchantInventoryProvider);
}

/// The reasons a merchant actually declines, as choices rather than a blank
/// box: a free-text field at this moment gets "sorry" and tells the customer
/// nothing.
class _DeclineSheet extends StatelessWidget {
  const _DeclineSheet({this.codes = declineReasonCodes, this.returns = false});

  final List<String> codes;

  /// A return, not an order: asked in those words, with no order note.
  final bool returns;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              returns ? l10n.whyDecliningReturn : l10n.whyDeclining,
              style: AppTypography.subsectionTitle(context),
            ),
            if (!returns) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(l10n.declineNote, style: context.textStyles.bodySmall),
            ],
            const SizedBox(height: AppSpacing.lg),
            // The code is what is kept, so the shopper reads the reason in
            // their language, not the store's.
            for (final code in codes)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: SabaTile(
                  label: reasonLabel(l10n, code)!,
                  onTap: () => Navigator.of(context).pop(code),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Call the shopper first", with the call a tap away and the confirm
/// under it. Pops true when the store says it called.
class _CallFirstSheet extends StatelessWidget {
  const _CallFirstSheet({required this.phone});

  final String? phone;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.callShopperFirst,
              style: AppTypography.subsectionTitle(context),
            ),
            if (phone case final number?) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      Formatters.ltrIsolate(IraqiPhone.display(number)),
                      style: context.textStyles.titleSmall,
                    ),
                  ),
                  CallButton(number: number),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: l10n.iCalledConfirm,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    );
  }
}

/// Who delivers it: the store's own driver, a name and a phone. v1 has no
/// delivery companies and no tracking numbers.
class _CourierSheet extends StatefulWidget {
  const _CourierSheet();

  @override
  State<_CourierSheet> createState() => _CourierSheetState();
}

class _CourierSheetState extends State<_CourierSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _send() {
    if (!(_formKey.currentState?.validateAndReveal() ?? false)) return;
    Navigator.of(context).pop(
      Courier(
        name: _name.text.trim(),
        phone: IraqiPhone.normalize(_phone.text)!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.whoDelivers,
                  style: AppTypography.subsectionTitle(context),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppTextField(
                  label: l10n.driverName,
                  hint: context.exampleOf(context.l10n.exDriverName),
                  controller: _name,
                  isRequired: true,
                  textInputAction: TextInputAction.next,
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? l10n.validationRequired
                      : null,
                ),
                const SizedBox(height: AppSpacing.lg),
                IraqiPhoneField(controller: _phone),
                const SizedBox(height: AppSpacing.xl),
                AppButton(label: l10n.markAsShipped, onPressed: _send),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
