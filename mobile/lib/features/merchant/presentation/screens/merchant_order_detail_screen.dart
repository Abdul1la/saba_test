import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/call_button.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/skeletons.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../core/widgets/sticky_bar.dart';
import '../../../returns/domain/entities.dart';
import '../../../returns/presentation/widgets/return_status_chip.dart';
import '../../domain/entities.dart';
import '../merchant_order_actions.dart';
import '../merchant_providers.dart';
import '../widgets/merchant_widgets.dart';
import '../../../../core/utils/iraqi_phone.dart';

/// One order, as the merchant packing it needs to see it.
///
/// The list card carries a number, a count and a total — enough to recognise
/// an order, and nothing at all to fulfil one. A merchant cannot pack what
/// they cannot see and cannot post to an address that was never shown, so
/// this screen is where the items, the customer and the destination live.
class MerchantOrderDetailScreen extends ConsumerWidget {
  const MerchantOrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(merchantOrderDetailProvider(orderId));

    return Scaffold(
      appBar: SabaAppBar(
        // The order number is the title once it is known; until then the
        // bar says what the screen is rather than flashing a placeholder
        // number that then changes under the reader.
        title: switch (detail) {
          AsyncData(:final value) => value.row.orderNumber,
          _ => context.l10n.orderDetails,
        },
        backFallback: AppRoutes.merchantOrders,
      ),
      body: SafeArea(
        top: false,
        child: AsyncStateView<MerchantOrderDetail>(
          value: detail,
          onRetry: () => ref.invalidate(merchantOrderDetailProvider(orderId)),
          loadingBuilder: (_) => const ListSkeleton(itemHeight: 96),
          builder: (order) => _Body(order: order),
        ),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.order});

  final MerchantOrderDetail order;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  /// Guards the one button on the screen while its request is in flight. A
  /// second tap would re-send the *same* transition, because `row.status` is
  /// still the stale pre-request value until the refetch lands.
  bool _advancing = false;

  Future<void> _advance() async {
    if (_advancing) return;
    setState(() => _advancing = true);
    await advanceMerchantOrder(context, ref, widget.order.row);
    if (!mounted) return;
    setState(() => _advancing = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = l10n.locale.toLanguageTag();
    final order = widget.order;
    final address = order.shippingAddress;
    final row = order.row;
    final next = MerchantOrderStatus.next(row.status);

    String money(num value) =>
        Formatters.money(value, locale: locale, currencyCode: row.currencyCode);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.sm,
              AppSpacing.screenGutter,
              AppSpacing.xxl,
            ),
            children: [
              Row(
                children: [
                  StatusBadge(
                    label: MerchantOrderStatus.label(context, row.status),
                    tone: MerchantOrderStatus.tone(row.status),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      Formatters.dateTime(row.placedAt, locale: locale),
                      textAlign: TextAlign.end,
                      style: context.textStyles.labelSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // Where it goes and who receives it. Two facts a packing slip
              // cannot be written without, and neither was anywhere in the
              // app before this screen existed.
              SectionCard(
                title: l10n.shippingAddress,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Line(
                      icon: SabaIcons.user,
                      label: l10n.customer,
                      // Unknown is said, not left as a gap: an empty slot
                      // reads as a layout bug, not as missing data.
                      value: row.customerName ?? l10n.notAvailable,
                    ),
                    if (order.customerPhone != null)
                      _Line(
                        icon: SabaIcons.phone,
                        label: l10n.phone,
                        value: IraqiPhone.display(order.customerPhone!),
                        copyable: true,
                        leftToRight: true,
                      ),
                    _Line(
                      icon: SabaIcons.mapPin,
                      label: l10n.shippingAddress,
                      value:
                          address?.formattedIn(l10n.locale.languageCode) ??
                          l10n.notAvailable,
                      copyable: address != null,
                    ),
                    if (address?.landmark != null)
                      _Line(
                        icon: SabaIcons.flag,
                        label: l10n.nearestLandmark,
                        value: address!.landmark!,
                      ),
                    if (address?.instructions != null)
                      _Line(
                        icon: SabaIcons.message,
                        label: l10n.deliveryInstructions,
                        value: address!.instructions!,
                      ),
                  ],
                ),
              ),

              if (order.courier case final courier?) ...[
                const SizedBox(height: AppSpacing.md),
                SectionCard(
                  title: l10n.whoDelivers,
                  trailing: CallButton(number: courier.phone),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Line(
                        icon: SabaIcons.truck,
                        label: l10n.driverName,
                        value: courier.name,
                      ),
                      _Line(
                        icon: SabaIcons.phone,
                        label: l10n.phone,
                        value: IraqiPhone.display(courier.phone),
                        copyable: true,
                        leftToRight: true,
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: AppSpacing.md),
              SectionCard(
                title: l10n.orderItems,
                child: Column(
                  children: [
                    for (final item in order.items)
                      _ItemRow(item: item, money: money),
                    if (order.items.isEmpty)
                      Text(
                        l10n.notAvailable,
                        style: context.textStyles.bodySmall,
                      ),
                  ],
                ),
              ),

              for (final request in order.returns) ...[
                const SizedBox(height: AppSpacing.md),
                _ReturnCard(orderId: row.id, request: request, money: money),
              ],

              const SizedBox(height: AppSpacing.md),
              SectionCard(
                child: Column(
                  children: [
                    CardLine(
                      label: l10n.subtotal,
                      value: money(order.subtotal),
                    ),
                    if (order.discount > 0)
                      CardLine(
                        label: l10n.discount,
                        value: Formatters.deduction(
                          order.discount,
                          locale: locale,
                          currencyCode: row.currencyCode,
                        ),
                      ),
                    CardLine(
                      label: l10n.shipping,
                      value: money(order.shipping),
                    ),
                    Divider(
                      height: AppSpacing.lg,
                      color: context.market.border,
                    ),
                    // The one figure the driver needs: what to take at the
                    // door. Cash is the only way to pay in v1. Called off
                    // or refused at the door, there is nothing to take.
                    if (const {
                      'CANCELLED',
                      'REFUSED',
                    }.contains(row.status.toUpperCase()))
                      CardLine(label: l10n.total, value: money(row.total))
                    else
                      CardLine(
                        label: l10n.collectInCash,
                        value: money(row.total),
                        emphasise: true,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // A finished order has no next step, so no bar is drawn rather than a
        // disabled button asking to be pressed.
        if (next != null)
          StickyBar(
            child: Row(
              children: [
                if (row.status.toUpperCase() == 'SHIPPED') ...[
                  Expanded(
                    child: AppButton(
                      label: l10n.refusedAtDoor,
                      variant: AppButtonVariant.secondary,
                      onPressed: _advancing
                          ? null
                          : () => refuseMerchantOrder(context, ref, row),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  child: AppButton(
                    label: row.status.toUpperCase() == 'SHIPPED'
                        ? MerchantOrderStatus.label(context, next)
                        : '${l10n.nextStatus}: '
                              '${MerchantOrderStatus.label(context, next)}',
                    isLoading: _advancing,
                    onPressed: _advance,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One return the shopper asked for: what, how much, where it has got to,
/// and the store's next step - approve and collect it, or decline it; then,
/// once collected, say the cash was handed back.
class _ReturnCard extends ConsumerWidget {
  const _ReturnCard({
    required this.orderId,
    required this.request,
    required this.money,
  });

  final String orderId;
  final ReturnDetail request;
  final String Function(num) money;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    Future<void> answer(String status) => answerMerchantReturn(
      context,
      ref,
      orderId: orderId,
      returnId: request.id,
      status: status,
    );

    return SectionCard(
      title: l10n.returnRequests,
      trailing: ReturnStatusChip(status: request.status, compact: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in request.items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(
                '${item.quantity} × ${item.name}',
                style: context.textStyles.bodyMedium,
              ),
            ),
          if (request.refund case final refund?
              when request.status != ReturnStatus.rejected)
            CardLine(label: l10n.refundAmount, value: money(refund.amount)),
          if (request.status == ReturnStatus.requested) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: l10n.declineReturn,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => answer('REJECTED'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: AppButton(
                    label: l10n.approveReturn,
                    onPressed: () => answer('APPROVED'),
                  ),
                ),
              ],
            ),
          ] else if (request.status == ReturnStatus.approved) ...[
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              label: l10n.cashHandedBack,
              onPressed: () => answer('REFUNDED'),
            ),
          ],
        ],
      ),
    );
  }
}

/// An icon-and-text line: a name, a phone, an address.
class _Line extends StatefulWidget {
  const _Line({
    required this.icon,
    required this.value,
    required this.label,
    this.copyable = false,
    this.leftToRight = false,
  });

  final String icon;
  final String value;

  /// A phone number: kept in one piece in Arabic, plus sign in front.
  final bool leftToRight;

  /// What this line holds, for a screen reader.
  final String label;

  /// A phone number and an address exist to leave the app: the merchant
  /// rings the customer about the delivery and pastes the address onto the
  /// parcel. This was SelectableText, so doing either meant long-pressing,
  /// dragging a handle over the whole value and hitting Copy — three fiddly
  /// actions on the screen someone is using while packing a box.
  final bool copyable;

  @override
  State<_Line> createState() => _LineState();
}

class _LineState extends State<_Line> {
  /// Confirmed in place, not with a snackbar: a tick on the row itself says
  /// it next to the thing it is about, and interrupts nothing. It is the
  /// same confirmation the product card's add button already uses.
  bool _copied = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.value));
    if (!mounted) return;
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(AppMotion.confirmInPlace, () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = context.textStyles.bodyMedium?.copyWith(fontSize: 13.5);
    final market = context.market;

    final line = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SabaIcon(widget.icon, size: AppSizes.iconMd, color: market.textMuted),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              // Shown isolated, copied raw: the marks must not reach a dialer.
              widget.leftToRight
                  ? Formatters.ltrIsolate(widget.value)
                  : widget.value,
              style: style,
            ),
          ),
          if (widget.copyable) ...[
            const SizedBox(width: AppSpacing.sm),
            SabaIcon(
              _copied ? SabaIcons.check : SabaIcons.clipboard,
              size: AppSizes.iconMd,
              color: _copied ? market.success : market.textMuted,
            ),
          ],
        ],
      ),
    );

    if (!widget.copyable) return line;

    return Semantics(
      button: true,
      label: _copied
          ? context.l10n.copiedToClipboard
          : '${context.l10n.copy} ${widget.label}',
      child: InkWell(
        onTap: _copy,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        child: line,
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.money});

  final MerchantOrderItem item;
  final String Function(num) money;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 1),
      child: Row(
        children: [
          AppNetworkImage(
            url: item.imageUrl,
            width: 48,
            height: 48,
            radius: AppRadius.action,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.bodyMedium?.copyWith(
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 2),
                // No SKU: it read "SKU SKU-p-1" and means nothing to a
                // small shop, which knows its stock by name.
                Text(
                  '× ${item.quantity}',
                  style: context.textStyles.labelSmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            money(item.price * item.quantity),
            style: context.textStyles.titleSmall?.copyWith(fontSize: 14),
          ),
        ],
      ),
    );
  }
}
