import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../messaging/presentation/widgets/message_store_button.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/call_button.dart';
import '../../../../core/widgets/dark_header_card.dart';
import '../../../../core/widgets/filter_chip_row.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/location/store_delivery.dart';
import '../../../returns/domain/entities.dart';
import '../../../returns/presentation/returns_providers.dart';
import '../../../returns/presentation/widgets/cancel_reason_dialog.dart';
import '../../../returns/presentation/widgets/return_status_chip.dart';
import '../../../reviews/presentation/rate_order_providers.dart';
import '../../domain/entities.dart';
import '../orders_providers.dart';
import '../widgets/order_notes.dart';
import '../widgets/order_status_chip.dart';
import '../../../../core/utils/iraqi_phone.dart';

/// One order in full.
///
/// The screen opens on what the customer came to find out — where the parcel
/// is — so the status and the trail come first, and the
/// receipt follows. The old version led with a grey summary block and put the
/// timeline last, which is the opposite of why anyone opens this screen.
class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(orderDetailProvider(orderId));

    return Scaffold(
      body: AsyncStateView<Order>(
        value: order,
        onRetry: () => ref.invalidate(orderDetailProvider(orderId)),
        builder: (value) => RefreshIndicator(
          onRefresh: () => ref.refresh(orderDetailProvider(orderId).future),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              WhiteHeader(child: _Hero(order: value)),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenGutter,
                  AppSpacing.lg + 2,
                  AppSpacing.screenGutter,
                  AppSpacing.xxl,
                ),
                child: Column(
                  children: [
                    // One box per store, each with its own steps: one
                    // timeline for the whole order could not say whose
                    // parcel was where (the user).
                    _StoreBoxes(order: value),
                    const SizedBox(height: AppSpacing.md + 2),
                    _TotalsCard(order: value),
                    if (value.shippingAddress != null) ...[
                      const SizedBox(height: AppSpacing.md + 2),
                      _AddressCard(
                        address: value.shippingAddress!,
                        paymentMethodLabel: value.paymentMethodLabel,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    _Actions(order: value),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `card/header-dark` carrying the answer to "where is my order".
///
/// It owns the back button and the status bar, so there is no separate app bar
/// above it — a white strip over a dark block would read as two headers.
class _Hero extends StatelessWidget {
  const _Hero({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = l10n.locale.toLanguageTag();
    final market = context.market;

    return DarkHeaderCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DarkIconButton(
                icon: context.isRtl
                    ? SabaIcons.chevronRight
                    : SabaIcons.chevronLeft,
                tooltip: l10n.back,
                onPressed: () => context.popOrGo(AppRoutes.orders),
              ),
              const Spacer(),
              OrderStatusChip(status: order.status),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            order.orderNumber,
            style: context.textStyles.displaySmall?.copyWith(
              fontSize: 26,
              color: market.onDark,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${l10n.orderDate}: '
            '${Formatters.dateTime(order.placedAt, locale: locale)}',
            style: context.textStyles.bodySmall?.copyWith(
              color: market.onDarkMuted,
            ),
          ),
          // The badge follows the store furthest behind, as My orders does;
          // with two stores or more, said so.
          if (order.itemsByMerchant.length > 1 &&
              !const [
                OrderStatus.delivered,
                OrderStatus.cancelled,
                OrderStatus.refused,
                OrderStatus.unknown,
              ].contains(order.status)) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.orderFollowsSlowest(
                OrderStatusChip.labelFor(context, order.status),
              ),
              style: context.textStyles.bodySmall?.copyWith(
                color: market.onDarkMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Every store's part of the order, a box each.
class _StoreBoxes extends StatelessWidget {
  const _StoreBoxes({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, entry) in order.itemsByMerchant.entries.indexed) ...[
          if (index > 0) const SizedBox(height: AppSpacing.md + 2),
          _StoreBox(order: order, storeName: entry.key, items: entry.value),
        ],
      ],
    );
  }
}

/// One store's part: its name and its step, a bar of the four steps, what
/// to hand its driver, its driver or when it should come, and its items.
/// Compact, so five stores are five short boxes, not five timelines.
class _StoreBox extends StatelessWidget {
  const _StoreBox({
    required this.order,
    required this.storeName,
    required this.items,
  });

  final Order order;
  final String storeName;
  final List<OrderItem> items;

  @override
  Widget build(BuildContext context) {
    final first = items.first;
    final status = first.status;
    final stopped =
        status == OrderStatus.cancelled || status == OrderStatus.refused;
    final part = order.parts[first.merchantId];
    final stopNote = stopped ? _stopNote(context) : null;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (storeName.isNotEmpty)
            Row(
              children: [
                SabaIcon(
                  SabaIcons.store,
                  size: AppSizes.iconSm,
                  color: context.market.textMuted,
                ),
                const SizedBox(width: AppSpacing.sm - 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        storeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textStyles.titleSmall,
                      ),
                      if (status != OrderStatus.unknown) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        OrderStatusChip(status: status, compact: true),
                      ],
                    ],
                  ),
                ),
                // "Where is it", "it came broken": asked of the store that
                // sent these lines, from the order itself.
                if (first.merchantId case final merchantId?)
                  MessageStoreButton(
                    merchantId: merchantId,
                    about: context.l10n.aboutOrder(order.orderNumber),
                  ),
              ],
            ),
          if (!stopped && status != OrderStatus.unknown) ...[
            const SizedBox(height: AppSpacing.md),
            _StepBar(status: status),
          ],
          if (stopNote != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              stopNote,
              style: context.textStyles.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
          // What to hand this store's driver - or what was.
          if (_cashLine(context, first) case final line?) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              line,
              style: context.textStyles.labelMedium?.copyWith(
                color: context.market.success,
              ),
            ),
          ],
          if (part != null && first.merchantId != null)
            _PartDelivery(
              order: order,
              merchantId: first.merchantId!,
              part: part,
              status: status,
            ),
          const SizedBox(height: AppSpacing.md),
          for (final item in items) _OrderItemRow(item: item),
        ],
      ),
    );
  }

  /// Why this store's part stopped: its step in the order's history, with
  /// the reason given.
  String? _stopNote(BuildContext context) {
    for (final entry in order.timeline.reversed) {
      if ((entry.status == OrderStatus.cancelled ||
              entry.status == OrderStatus.refused) &&
          (entry.storeName == null || entry.storeName == storeName)) {
        return timelineNote(context.l10n, entry);
      }
    }
    return null;
  }

  /// "Cash to the driver: 120,000 IQD" for one store's part, "Paid to the
  /// driver" once it has come, nothing for a part that was called off or
  /// refused at the door: the server keeps its amount, but nobody pays it.
  String? _cashLine(BuildContext context, OrderItem first) {
    final due = order.dueByStore[first.merchantId];
    if (!order.isCashOnDelivery ||
        due == null ||
        first.status == OrderStatus.cancelled ||
        first.status == OrderStatus.refused) {
      return null;
    }
    final l10n = context.l10n;
    final amount = Formatters.money(
      due,
      locale: l10n.locale.toLanguageTag(),
      currencyCode: order.currencyCode,
    );
    final label = first.status == OrderStatus.delivered
        ? l10n.paidToDriver
        : l10n.cashToDriver;
    return '$label: $amount';
  }
}

/// Confirmed · Preparing · Shipped · Delivered, across the box, the step a
/// store has reached marked. Across, not down: five stores with a timeline
/// each ran far too long.
class _StepBar extends StatelessWidget {
  const _StepBar({required this.status});

  final OrderStatus status;

  /// The step reached; -1 while the store has not confirmed.
  int get _reached => switch (status) {
    OrderStatus.confirmed => 0,
    OrderStatus.processing => 1,
    OrderStatus.shipped => 2,
    OrderStatus.delivered || OrderStatus.returned || OrderStatus.refunded => 3,
    _ => -1,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final market = context.market;
    final reached = _reached;
    final labels = [
      l10n.orderStatusConfirmed,
      l10n.stepPreparing,
      l10n.orderStatusShipped,
      l10n.orderStatusDelivered,
    ];
    Color line(bool done) => done ? market.accent : market.border;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Semantics(
              label: labels[i],
              selected: i == reached,
              child: Column(
                children: [
                  SizedBox(
                    height: 16,
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 2,
                            color: i == 0
                                ? Colors.transparent
                                : line(i <= reached),
                          ),
                        ),
                        Container(
                          width: i == reached ? 16 : 10,
                          height: i == reached ? 16 : 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i <= reached
                                ? market.accent
                                : context.colors.surface,
                            border: Border.all(
                              color: i <= reached
                                  ? market.accent
                                  : market.border,
                              width: 2,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Container(
                            height: 2,
                            color: i == labels.length - 1
                                ? Colors.transparent
                                : line(i < reached),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  // A word each, shrunk a little only at the largest text
                  // on the smallest phone rather than cut.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      labels[i],
                      maxLines: 1,
                      style: context.textStyles.labelSmall?.copyWith(
                        fontWeight: i == reached
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: i <= reached
                            ? context.colors.onSurface
                            : market.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// One store's delivery, for the shopper: who is bringing it and a way to
/// call them; once the store says it came, "did you receive it?".
class _PartDelivery extends ConsumerStatefulWidget {
  const _PartDelivery({
    required this.order,
    required this.merchantId,
    required this.part,
    required this.status,
  });

  final Order order;
  final String merchantId;
  final OrderStorePart part;
  final OrderStatus status;

  @override
  ConsumerState<_PartDelivery> createState() => _PartDeliveryState();
}

class _PartDeliveryState extends ConsumerState<_PartDelivery> {
  bool _answering = false;

  Future<void> _answer({required bool received}) async {
    setState(() => _answering = true);
    final result = await ref
        .read(ordersRepositoryProvider)
        .confirmReceived(
          orderId: widget.order.id,
          merchantId: widget.merchantId,
          received: received,
        );
    if (!mounted) return;
    setState(() => _answering = false);
    result.fold(
      ok: (_) {
        ref
          ..invalidate(orderDetailProvider(widget.order.id))
          // Answered here, the sheet does not ask it again.
          ..invalidate(orderToRateProvider);
        if (!received) {
          AppSnackBar.info(context, context.l10n.receiptProblemNote);
        }
      },
      err: (failure) => AppSnackBar.failure(context, failure),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final part = widget.part;
    final onTheWay =
        widget.status == OrderStatus.shipped ||
        widget.status == OrderStatus.delivered;

    final expected = DeliveryTime.fromApi(part.deliveryTime);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Before it ships, when it should come; its driver once it does.
        if (expected != null &&
            const [
              OrderStatus.pending,
              OrderStatus.confirmed,
              OrderStatus.processing,
            ].contains(widget.status))
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              l10n.expectedArrival(expected.label(context)),
              style: context.textStyles.bodySmall,
            ),
          ),
        if (onTheWay && part.courierName != null && part.courierPhone != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Row(
              children: [
                // The number on a line of its own: after the name it broke
                // in two, "+964 770 555 / 9988".
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${l10n.driverLabel}: ${part.courierName}',
                        style: context.textStyles.bodySmall,
                      ),
                      Text(
                        Formatters.ltrIsolate(
                          IraqiPhone.display(part.courierPhone!),
                        ),
                        style: context.textStyles.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                CallButton(number: part.courierPhone!),
              ],
            ),
          ),
        // The question on its own line, the answers side by side: the
        // app's buttons are full width, and in a row with the words they
        // ran off the screen.
        if (widget.status == OrderStatus.delivered &&
            part.received == null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(l10n.didYouReceive, style: context.textStyles.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              // Even halves, each label on one line and full size, as the
              // arrival sheet asks it: at a third of the row "No" broke into
              // "N / o" (the tester).
              Expanded(
                child: AppButton(
                  label: l10n.noNotReceived,
                  variant: AppButtonVariant.secondary,
                  onPressed: _answering ? null : () => _answer(received: false),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppButton(
                  label: l10n.yesReceived,
                  onPressed: _answering ? null : () => _answer(received: true),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _OrderItemRow extends StatelessWidget {
  const _OrderItemRow({required this.item});

  final OrderItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = l10n.locale.toLanguageTag();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The picture opens the product, as it does in the cart and on
              // every shelf in the app. Here it was the one place a product was
              // drawn and could not be reached, so seeing it again meant
              // remembering its name and searching for it.
              _ProductLink(
                productId: item.productId,
                child: AppNetworkImage(
                  url: item.imageUrl,
                  width: 56,
                  height: 56,
                  radius: AppRadius.md,
                  fallbackIcon: iconForName(item.productName, 0),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The stored snapshot, not the live product record.
                    _ProductLink(
                      productId: item.productId,
                      child: Text(
                        item.productName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.textStyles.bodyMedium?.copyWith(
                          fontSize: 13.5,
                          height: 1.35,
                        ),
                      ),
                    ),
                    if (item.variantLabel != null) ...[
                      const SizedBox(height: AppSpacing.xxs - 1),
                      Text(
                        item.variantLabel!,
                        style: context.textStyles.labelSmall,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xs + 1),
                    Text(
                      '${item.quantity} × '
                      '${Formatters.money(item.unitPrice, locale: locale, currencyCode: item.currencyCode)}',
                      style: context.textStyles.labelSmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                Formatters.money(
                  item.lineTotal,
                  locale: locale,
                  currencyCode: item.currencyCode,
                ),
                style: context.textStyles.titleSmall?.copyWith(fontSize: 13.5),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = l10n.locale.toLanguageTag();

    String money(num value) => Formatters.money(
      value,
      locale: locale,
      currencyCode: order.currencyCode,
    );

    return SectionCard(
      title: l10n.orderSummary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardLine(label: l10n.subtotal, value: money(order.subtotal)),
          if (order.discount > 0)
            CardLine(
              label: l10n.discount,
              value: Formatters.deduction(
                order.discount,
                locale: locale,
                currencyCode: order.currencyCode,
              ),
              valueColor: context.market.success,
            ),
          CardLine(label: l10n.shipping, value: money(order.shipping)),
          if (order.tax > 0) CardLine(label: l10n.tax, value: money(order.tax)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Divider(height: 1, color: context.market.border),
          ),
          CardLine(
            label: l10n.grandTotal,
            value: money(order.total),
            emphasise: true,
          ),
          // A cancelled order still showed its total, and nothing said that
          // none of it would be taken.
          if (order.status == OrderStatus.cancelled ||
              order.status == OrderStatus.refused) ...[
            const SizedBox(height: AppSpacing.sm),
            CardNote(
              order.status == OrderStatus.refused
                  ? l10n.refusedNothingPaid
                  : l10n.cancelledNothingCharged,
            ),
          ],
        ],
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.address, this.paymentMethodLabel});

  final OrderAddress address;

  /// Shown here rather than in the hero: how it was paid matters when
  /// checking the delivery details, not when checking where the parcel is.
  final String? paymentMethodLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return SectionCard(
      title: l10n.shippingAddress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SabaIcon(
                SabaIcons.mapPin,
                size: AppSizes.iconSm,
                color: context.market.textMuted,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      address.fullName,
                      style: context.textStyles.bodyMedium?.copyWith(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs - 1),
                    Text(
                      address.formattedIn(l10n.locale.languageCode),
                      style: context.textStyles.bodySmall?.copyWith(
                        height: 1.45,
                      ),
                    ),
                    if (address.landmark != null)
                      Text(
                        '${l10n.nearestLandmark}: ${address.landmark}',
                        style: context.textStyles.bodySmall,
                      ),
                    if (address.phone != null)
                      Text(
                        Formatters.ltrIsolate(
                          IraqiPhone.display(address.phone!),
                        ),
                        style: context.textStyles.bodySmall,
                      ),
                    if (address.instructions != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        address.instructions!,
                        style: context.textStyles.labelSmall,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (paymentMethodLabel != null) ...[
            const SizedBox(height: AppSpacing.md + 2),
            Row(
              children: [
                SabaIcon(
                  SabaIcons.creditCard,
                  size: AppSizes.iconSm,
                  color: context.market.textMuted,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '${l10n.paymentMethod}: $paymentMethodLabel',
                    style: context.textStyles.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Actions extends ConsumerStatefulWidget {
  const _Actions({required this.order});

  final Order order;

  @override
  ConsumerState<_Actions> createState() => _ActionsState();
}

class _ActionsState extends ConsumerState<_Actions> {
  bool _isCancelling = false;

  Future<void> _cancel() async {
    final l10n = context.l10n;

    // G7: the reason is the customer's, not a hardcoded 'CUSTOMER_REQUEST'.
    // The dialog doubles as the confirmation, so there is no second prompt.
    final choice = await CancelReasonDialog.show(context);
    if (choice == null || !mounted) return;

    setState(() => _isCancelling = true);

    final result = await ref
        .read(ordersRepositoryProvider)
        .cancelOrder(
          orderId: widget.order.id,
          reason: choice.apiValue,
          note: choice.note,
        );

    if (!mounted) return;
    setState(() => _isCancelling = false);

    result.fold(
      ok: (_) {
        ref.invalidate(orderDetailProvider(widget.order.id));
        ref.invalidate(orderListProvider);
        AppSnackBar.success(context, l10n.orderStatusCancelled);
      },
      err: (failure) => AppSnackBar.failure(context, failure),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final order = widget.order;
    // A return started on this order, shown on it. Finding it used to mean
    // leaving the order for a separate list and matching order numbers.
    final returns =
        ref
            .watch(returnListProvider(null))
            .value
            ?.items
            .where((request) => request.orderId == order.id)
            .toList() ??
        const <ReturnSummary>[];

    return Column(
      children: [
        for (final request in returns) ...[
          _ReturnLink(request: request),
          const SizedBox(height: AppSpacing.md),
        ],
        AppButton(
          label: l10n.viewInvoice,
          variant: AppButtonVariant.secondary,
          icon: SabaIcons.receipt,
          onPressed: () => context.push(AppRoutes.orderInvoicePath(order.id)),
        ),
        if (order.canReturn) ...[
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: l10n.requestReturn,
            variant: AppButtonVariant.secondary,
            icon: SabaIcons.refresh,
            onPressed: () =>
                context.push(AppRoutes.requestReturnPath(order.id)),
          ),
        ],
        if (order.canCancel) ...[
          const SizedBox(height: AppSpacing.sm),
          // Quiet, not a full red bar. Cancelling is irreversible and rare;
          // a danger-filled button of the same weight as "View invoice"
          // invites the mis-tap it is most important to avoid.
          AppButton(
            label: l10n.cancelOrder,
            variant: AppButtonVariant.dangerText,
            isLoading: _isCancelling,
            onPressed: _cancel,
          ),
        ],
      ],
    );
  }
}

/// A return on this order: its status, one tap from its details.
class _ReturnLink extends StatelessWidget {
  const _ReturnLink({required this.request});

  final ReturnSummary request;

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    final radius = BorderRadius.circular(AppRadius.card);

    return Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: market.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(AppRoutes.returnDetailPath(request.id)),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md + 2),
          child: Row(
            children: [
              Container(
                width: AppSizes.tileIcon,
                height: AppSizes.tileIcon,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: market.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadius.action),
                ),
                child: SabaIcon(
                  SabaIcons.refresh,
                  size: AppSizes.iconMd,
                  color: market.accent,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  context.l10n.returnDetails,
                  style: context.textStyles.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              ReturnStatusChip(status: request.status, compact: true),
              const SizedBox(width: AppSpacing.sm),
              SabaIcon(
                context.isRtl ? SabaIcons.chevronLeft : SabaIcons.chevronRight,
                size: AppSizes.iconSm,
                color: market.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens a product, when the order still knows which one it was.
///
/// An order stores a snapshot of what was bought, so `productId` can be null
/// for a line whose product has since been deleted. That line is drawn without
/// a tap rather than with one that leads to a missing page.
class _ProductLink extends StatelessWidget {
  const _ProductLink({required this.productId, required this.child});

  final String? productId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final id = productId;
    if (id == null) return child;

    return InkWell(
      onTap: () => context.push(AppRoutes.productDetailPath(id)),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: child,
    );
  }
}
