import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/filter_chip_row.dart';
import '../../../../core/widgets/quantity_selector.dart';
import '../../../../core/widgets/results_chrome.dart';
import '../../../../core/utils/formatters.dart';
import '../returns_providers.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/sticky_bar.dart';
import '../../../orders/domain/entities.dart';
import '../../../orders/domain/orders_repository.dart';
import '../../../orders/presentation/orders_providers.dart';
import '../../domain/entities.dart';

/// Opens a return request for selected lines of an order (section 19).
///
/// One scroll with the commitment pinned to the bottom, like checkout: pick
/// the lines, say why, send. The submit button counts what is selected, so it
/// is never a mystery what is about to be sent back.
class RequestReturnScreen extends ConsumerStatefulWidget {
  const RequestReturnScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<RequestReturnScreen> createState() =>
      _RequestReturnScreenState();
}

class _RequestReturnScreenState extends ConsumerState<RequestReturnScreen> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();

  /// Order item id to the quantity being returned.
  final Map<String, int> _selected = <String, int>{};

  ReturnReason _reason = ReturnReason.damaged;
  bool _isSubmitting = false;
  Failure? _failure;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  String _reasonLabel(ReturnReason reason) {
    final l10n = context.l10n;
    return switch (reason) {
      ReturnReason.damaged => l10n.returnReasonDamaged,
      ReturnReason.wrongItem => l10n.returnReasonWrongItem,
      ReturnReason.notAsDescribed => l10n.returnReasonNotAsDescribed,
      ReturnReason.missingParts => l10n.returnReasonMissingParts,
      ReturnReason.changedMind => l10n.returnReasonChangedMind,
      ReturnReason.other => l10n.returnReasonOther,
    };
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _failure = null);

    if (_selected.isEmpty) {
      // This used to borrow the product page's variant-picker message and
      // tell the customer to "choose the product options first" - on a screen
      // that has no options. It names the control that is actually blocking.
      AppSnackBar.info(context, context.l10n.selectItemsToReturn);
      return;
    }
    if (!(_formKey.currentState?.validateAndReveal() ?? false)) return;

    setState(() => _isSubmitting = true);

    final result = await ref
        .read(ordersRepositoryProvider)
        .requestReturn(
          orderId: widget.orderId,
          reason: _reason.apiValue,
          description: _description.text.trim().isEmpty
              ? null
              : _description.text.trim(),
          lines: [
            for (final entry in _selected.entries)
              ReturnLine(orderItemId: entry.key, quantity: entry.value),
          ],
        );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    result.fold(
      ok: (_) {
        ref.invalidate(orderDetailProvider(widget.orderId));
        // The order page's "Return details" reads the returns list: it
        // came only after a reload (the tester).
        ref.invalidate(returnListProvider);
        AppSnackBar.success(context, context.l10n.done);
        Navigator.of(context).maybePop();
      },
      err: (failure) {
        setState(() => _failure = failure);
        AppSnackBar.failure(context, failure);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final order = ref.watch(orderDetailProvider(widget.orderId));

    return Scaffold(
      appBar: SabaAppBar(title: l10n.requestReturn),
      body: AsyncStateView<Order>(
        value: order,
        onRetry: () => ref.invalidate(orderDetailProvider(widget.orderId)),
        builder: (value) {
          final returnable = value.items
              .where((item) => item.canReturn)
              .toList();
          // The rest, each with why: an order of two offered one, and the
          // other was simply left out (the tester).
          final left = value.items.where((item) => !item.canReturn).toList();

          if (returnable.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.screenGutter),
              children: [
                NoResultsView(
                  icon: SabaIcons.refresh,
                  title: l10n.emptyTitle,
                  message: l10n.nothingToReturnNow,
                ),
                if (left.isNotEmpty) _NotReturnable(items: left),
              ],
            );
          }

          final lineCount = _selected.values.fold(0, (sum, qty) => sum + qty);
          // What the store hands back, before it is sent (the tester): what
          // each unit really cost, after the store's coupon.
          final refund = [
            for (final item in returnable)
              if (_selected[item.id] case final qty?) item.paidUnitPrice * qty,
          ].fold<num>(0, (sum, amount) => sum + amount);

          return Form(
            key: _formKey,
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenGutter,
                      AppSpacing.sm,
                      AppSpacing.screenGutter,
                      AppSpacing.xxl,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // v1: seven days from delivery, cash back from the
                        // store when it collects the item.
                        Text(
                          '${l10n.returnWindowNote} ${l10n.returnCashNote}',
                          style: context.textStyles.bodySmall,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        SectionCard(
                          title: l10n.orderItems,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final item in returnable)
                                _ItemRow(
                                  item: item,
                                  quantity: _selected[item.id],
                                  onToggle: (isSelected) => setState(() {
                                    if (isSelected) {
                                      _selected[item.id] = 1;
                                    } else {
                                      _selected.remove(item.id);
                                    }
                                  }),
                                  onQuantityChanged: (value) => setState(
                                    () => _selected[item.id] = value,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (left.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.md + 2),
                          _NotReturnable(items: left),
                        ],
                        const SizedBox(height: AppSpacing.md + 2),
                        SectionCard(
                          title: l10n.returnReason,
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            AppSpacing.lg,
                            AppSpacing.lg,
                            AppSpacing.lg,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // A row of pills rather than a dropdown: six short
                              // reasons are faster to compare side by side than
                              // behind a menu, and the choice stays visible.
                              for (final reason in ReturnReason.values)
                                _ReasonOption(
                                  label: _reasonLabel(reason),
                                  isSelected: _reason == reason,
                                  onTap: () => setState(() => _reason = reason),
                                ),
                              const SizedBox(height: AppSpacing.md),
                              AppTextField(
                                label: l10n.description,
                                hint: context.exampleOf(context.l10n.exReturn),
                                controller: _description,
                                maxLines: 4,
                                maxLength: 1000,
                                serverError: _failure?.messageForField(
                                  'description',
                                ),
                                // Only "another reason" genuinely needs words:
                                // demanding ten characters to explain "it arrived
                                // damaged" is friction for nothing.
                                validator: _reason == ReturnReason.other
                                    ? (value) =>
                                          Validators.minLength(value, 10, l10n)
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                StickyBar(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (lineCount > 0) ...[
                        CardLine(
                          label: l10n.refundAmount,
                          value: Formatters.money(
                            refund,
                            locale: l10n.locale.toLanguageTag(),
                            currencyCode: value.currencyCode,
                          ),
                          emphasise: true,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      AppButton(
                        label: lineCount == 0
                            ? l10n.submit
                            : '${l10n.submit}  ·  ${l10n.counted(lineCount, CountNoun.item)}',
                        isLoading: _isSubmitting,
                        onPressed: _submit,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One reason, as a selectable row.
class _ReasonOption extends StatelessWidget {
  const _ReasonOption({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final market = context.market;

    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: isSelected,
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.action),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: [
              // A filled disc with a tick, not a radio: the same mark the rest
              // of the app uses for "this one is chosen".
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected
                      ? context.colors.primary
                      : Colors.transparent,
                  border: isSelected
                      ? null
                      : Border.all(color: market.border, width: 2),
                ),
                child: isSelected
                    ? SabaIcon(
                        SabaIcons.check,
                        size: 13,
                        color: context.colors.onPrimary,
                      )
                    : null,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  label,
                  style: context.textStyles.bodyMedium?.copyWith(
                    fontSize: 13.5,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
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

/// The order's items that are not on this return, each with why: not
/// delivered yet, cancelled, or returned already or past its seven days.
class _NotReturnable extends StatelessWidget {
  const _NotReturnable({required this.items});

  final List<OrderItem> items;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return SectionCard(
      title: l10n.notOnThisReturn,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.productName, style: context.textStyles.bodyMedium),
                  Text(
                    switch (item.status) {
                      OrderStatus.delivered => l10n.returnedOrLate,
                      OrderStatus.cancelled => l10n.cancelledNothingToReturn,
                      _ => l10n.notDeliveredYetReturn,
                    },
                    style: context.textStyles.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.quantity,
    required this.onToggle,
    required this.onQuantityChanged,
  });

  final OrderItem item;

  /// Null when this line is not part of the return.
  final int? quantity;

  final ValueChanged<bool> onToggle;
  final ValueChanged<int> onQuantityChanged;

  @override
  Widget build(BuildContext context) {
    final isSelected = quantity != null;
    final market = context.market;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        children: [
          InkWell(
            onTap: () => onToggle(!isSelected),
            borderRadius: BorderRadius.circular(AppRadius.action),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    color: isSelected
                        ? context.colors.primary
                        : Colors.transparent,
                    border: isSelected
                        ? null
                        : Border.all(color: market.border, width: 2),
                  ),
                  child: isSelected
                      ? SabaIcon(
                          SabaIcons.check,
                          size: 13,
                          color: context.colors.onPrimary,
                        )
                      : null,
                ),
                const SizedBox(width: AppSpacing.md),
                AppNetworkImage(
                  url: item.imageUrl,
                  width: 48,
                  height: 48,
                  radius: AppRadius.md,
                  fallbackIcon: iconForName(item.productName, 0),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.productName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.textStyles.bodyMedium?.copyWith(
                          fontSize: 13.5,
                          height: 1.35,
                        ),
                      ),
                      if (item.variantLabel != null) ...[
                        const SizedBox(height: AppSpacing.xxs - 1),
                        Text(
                          item.variantLabel!,
                          style: context.textStyles.labelSmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (isSelected) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Text(
                  context.l10n.quantity,
                  style: context.textStyles.labelMedium,
                ),
                const Spacer(),
                QuantitySelector(
                  quantity: quantity!,
                  maxQuantity: item.quantity,
                  onChanged: onQuantityChanged,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
