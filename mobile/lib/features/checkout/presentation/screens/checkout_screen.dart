import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/failure_messages.dart';
import '../../../../core/location/governorate_picker.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/results_chrome.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/sticky_bar.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../addresses/domain/entities.dart';
import '../../../addresses/presentation/address_providers.dart';
import '../../../auth/presentation/auth_providers.dart';
import '../../domain/entities.dart';
import '../checkout_providers.dart';
import '../../../../core/utils/iraqi_phone.dart';

/// Cart → Address → Shipping → Payment → Review → Confirmation.
///
/// Every total shown here comes from a server pricing call; the client only
/// sends the identifiers of what the customer chose (specification section 13).
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key, this.buyNow});

  /// Set for Buy now: this product alone, not the cart.
  final BuyNowLine? buyNow;

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  @override
  void initState() {
    super.initState();
    // Price the order as soon as the screen opens, using the default address.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(checkoutControllerProvider.notifier)
          .begin(buyNow: widget.buyNow);
    });
  }

  Future<void> _placeOrder() async {
    final controller = ref.read(checkoutControllerProvider.notifier);
    final result = await controller.placeOrder();

    if (!mounted) return;

    switch (result) {
      case Ok<PlacedOrder>(:final value):
        context.go(AppRoutes.orderConfirmationPath(value.orderId));
      case Err<PlacedOrder>(:final failure):
        AppSnackBar.failure(context, failure);
    }
  }

  /// What to draw when the server has not priced the order yet.
  ///
  /// "No totals" has three causes and used to have one drawing: a generic
  /// error whose Retry never rendered, because the invented
  /// [BusinessRuleFailure] it was given is not retryable. So a customer who
  /// had simply never saved an address was told the app had broken, and the
  /// screen could not heal - [CheckoutController.priceOrder] returns early
  /// without an address, and nothing called it again. Three causes, three
  /// screens.
  Widget _buildUnpriced(BuildContext context, CheckoutState state) {
    final l10n = context.l10n;

    if (!state.selection.hasAddress) {
      // The controller takes its address from the address list, so until that
      // list resolves "no address" and "still loading" are the same state.
      if (ref.watch(addressListProvider).isLoading) return const LoadingView();

      // Reaching checkout with nothing saved is an ordinary first order, not
      // a fault - so it gets the one control that moves it forward.
      return NoResultsView(
        icon: SabaIcons.mapPin,
        title: l10n.emptyAddresses,
        message: l10n.emptyAddressesMessage,
        actions: [
          FilledButton(
            onPressed: () => context.push(AppRoutes.addressForm),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(AppSizes.buttonHeight),
            ),
            child: Text(l10n.addAddress),
          ),
        ],
      );
    }

    final failure = state.failure;
    if (failure != null) {
      return AppErrorView(
        failure: failure,
        onRetry: ref.read(checkoutControllerProvider.notifier).priceOrder,
      );
    }

    return const LoadingView();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(checkoutControllerProvider);
    final summary = state.summary;

    // The address list can resolve a frame after this screen opens, which
    // rebuilds the controller with an address but still no totals. The
    // one-shot in initState has already fired by then, so without this the
    // screen would sit on an empty state nothing ever refreshes.
    ref.listen<CheckoutState>(checkoutControllerProvider, (previous, next) {
      if (next.selection.hasAddress &&
          next.summary == null &&
          !next.isPricing &&
          next.failure == null) {
        ref.read(checkoutControllerProvider.notifier).priceOrder();
      }
    });

    return Scaffold(
      appBar: SabaAppBar(title: l10n.checkout),
      body: summary == null
          ? _buildUnpriced(context, state)
          : _Body(state: state, summary: summary),
      bottomNavigationBar: summary == null
          ? null
          : _PlaceOrderBar(
              state: state,
              summary: summary,
              onPlaceOrder: _placeOrder,
            ),
    );
  }
}

/// The whole commitment on one scroll.
///
/// The design is explicit that checkout is **numbered, not paged**: three
/// cards the customer can see all of before the button, which is what stops
/// abandonment on a high-value cart. Address and delivery show what is
/// chosen and open a sheet to change it, so the scroll stays short.
class _Body extends ConsumerWidget {
  const _Body({required this.state, required this.summary});

  final CheckoutState state;
  final CheckoutSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.xl - 4,
        AppSpacing.screenGutter,
        AppSpacing.xl,
      ),
      children: [
        if (summary.warnings.isNotEmpty) ...[
          _Warnings(warnings: summary.warnings),
          const SizedBox(height: AppSpacing.md + 2),
        ],
        _AddressCard(state: state),
        const SizedBox(height: AppSpacing.md + 2),
        _DeliveryCard(state: state, summary: summary),
        const SizedBox(height: AppSpacing.md + 2),
        _PaymentCard(state: state, summary: summary),
        const SizedBox(height: AppSpacing.md + 2),
        _TotalsCard(summary: summary),
        if (state.failure != null) ...[
          const SizedBox(height: AppSpacing.md + 2),
          Text(
            state.failure!.localizedMessage(l10n),
            textAlign: TextAlign.center,
            style: context.textStyles.bodySmall?.copyWith(
              color: context.colors.error,
            ),
          ),
        ],
      ],
    );
  }
}

/// A checkout card: white, bordered, a numbered header, then its content.
class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.number,
    required this.title,
    required this.child,
    this.action,
  });

  final int number;
  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border.all(color: context.market.border),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StepHeader(number: number, title: title, action: action),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

/// A block on the page colour inside a white card — the design's way of
/// showing a chosen value without another border.
class _SunkenBlock extends StatelessWidget {
  const _SunkenBlock({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.theme.scaffoldBackgroundColor,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md + 2,
            AppSpacing.md,
            AppSpacing.md + 2,
            AppSpacing.md,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _Warnings extends StatelessWidget {
  const _Warnings({required this.warnings});

  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    final market = context.market;

    // One box for each problem, never two unrelated ones in one.
    return Column(
      children: [
        for (final (index, warning) in warnings.indexed)
          Container(
            margin: EdgeInsets.only(top: index == 0 ? 0 : AppSpacing.sm),
            padding: const EdgeInsets.all(AppSpacing.md + 2),
            decoration: BoxDecoration(
              color: market.warningSoft,
              borderRadius: BorderRadius.circular(AppRadius.input),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SabaIcon(
                  SabaIcons.exclamation,
                  size: AppSizes.iconSm,
                  color: market.warning,
                ),
                const SizedBox(width: AppSpacing.sm + 2),
                Expanded(
                  child: Text(
                    warning,
                    style: context.textStyles.bodyMedium?.copyWith(
                      fontSize: 12.5,
                      color: market.warning,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Step 1 — where it is going.
class _AddressCard extends ConsumerWidget {
  const _AddressCard({required this.state});

  final CheckoutState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final addresses = ref.watch(addressListProvider);
    final chosen = addresses.value?.where(
      (address) => address.id == state.selection.addressId,
    );
    final address = (chosen == null || chosen.isEmpty) ? null : chosen.first;

    return _StepCard(
      number: 1,
      title: l10n.deliverTo,
      action: address == null
          ? null
          : _UnderlinedAction(
              label: l10n.change,
              onTap: () => _choose(context, ref),
            ),
      child: address == null
          ? OutlinedButton(
              onPressed: () => _choose(context, ref),
              child: Text(l10n.selectAddress),
            )
          : _SunkenBlock(
              onTap: () => _choose(context, ref),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SabaIcon(
                    SabaIcons.mapPin,
                    size: AppSizes.iconSm,
                    color: context.colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.sm + 3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          address.label == null
                              ? address.fullName
                              : '${address.label} · ${address.fullName}',
                          style: context.textStyles.titleLarge?.copyWith(
                            fontSize: 13.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${address.formattedIn(context.l10n.locale.languageCode)} · ${Formatters.ltrIsolate(IraqiPhone.display(address.phone))}',
                          style: context.textStyles.bodyMedium?.copyWith(
                            fontSize: 12.5,
                            height: 1.5,
                          ),
                        ),
                        // Home shops from one city; the order goes where
                        // the address is. Said when those differ.
                        if ((
                              ref.watch(shopperCityProvider),
                              address.governorate,
                            )
                            case (final home?, final city?)
                            when home != city) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            l10n.addressCityNote(
                              home: home.label(context),
                              city: city.label(context),
                            ),
                            style: context.textStyles.bodySmall?.copyWith(
                              fontSize: 12,
                              color: context.market.info,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _choose(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(checkoutControllerProvider.notifier);
    final picked = await AppDialogs.bottomSheet<String>(
      context,
      builder: (sheetContext) =>
          _AddressSheet(selectedId: state.selection.addressId),
    );
    if (picked == null) return;
    await controller.selectAddress(picked);
  }
}

/// The address list, in a sheet rather than inline, so the scroll stays short.
class _AddressSheet extends ConsumerWidget {
  const _AddressSheet({required this.selectedId});

  final String? selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final addresses = ref.watch(addressListProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          AppSpacing.sm,
          AppSpacing.screenGutter,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.deliveryAddress,
              style: AppTypography.subsectionTitle(context),
            ),
            const SizedBox(height: AppSpacing.md),
            AsyncStateView<List<Address>>(
              value: addresses,
              onRetry: () => ref.invalidate(addressListProvider),
              builder: (items) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final address in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm + 1),
                      child: _ChoiceRow(
                        isSelected: address.id == selectedId,
                        icon: SabaIcons.mapPin,
                        title: address.label ?? address.fullName,
                        subtitle: address.formattedIn(
                          context.l10n.locale.languageCode,
                        ),
                        onTap: () => Navigator.of(context).pop(address.id),
                      ),
                    ),
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: Text(
                        l10n.emptyAddresses,
                        style: context.textStyles.bodyMedium,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: () {
                Navigator.of(context).pop();
                context.push(AppRoutes.addressForm);
              },
              child: Text(l10n.addAddress),
            ),
          ],
        ),
      ),
    );
  }
}

/// Step 2 — one arrival per store, said before the payment step rather than
/// after the complaint.
class _DeliveryCard extends ConsumerWidget {
  const _DeliveryCard({required this.state, required this.summary});

  final CheckoutState state;
  final CheckoutSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locale = l10n.locale.toLanguageTag();
    final controller = ref.read(checkoutControllerProvider.notifier);

    return _StepCard(
      number: 2,
      title: summary.groups.length == 1
          ? l10n.delivery
          : l10n.deliveryFromStores(summary.groups.length),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final group in summary.groups) ...[
            Builder(
              builder: (context) {
                final selectedId =
                    state.selection.shippingOptionIds[group.merchantId] ??
                    group.selectedShippingOptionId;
                final options = group.shippingOptions;
                final matching = options.where((o) => o.id == selectedId);
                final option = matching.isEmpty
                    ? (options.isEmpty ? null : options.first)
                    : matching.first;

                return _SunkenBlock(
                  onTap: options.length < 2
                      ? null
                      : () async {
                          final picked = await AppDialogs.bottomSheet<String>(
                            context,
                            builder: (_) => _ShippingSheet(
                              group: group,
                              selectedId: selectedId,
                            ),
                          );
                          if (picked == null) return;
                          await controller.selectShipping(
                            merchantId: group.merchantId,
                            optionId: picked,
                          );
                        },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              group.merchantName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.textStyles.titleLarge?.copyWith(
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            option == null
                                ? l10n.noDelivery
                                : option.isFree
                                ? l10n.freeShipping
                                : Formatters.money(
                                    option.fee,
                                    locale: locale,
                                    currencyCode: option.currencyCode,
                                  ),
                            style: context.textStyles.labelLarge?.copyWith(
                              fontSize: 13,
                              color: option == null
                                  ? context.colors.error
                                  : option.isFree
                                  ? context.market.success
                                  : context.colors.onSurface,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                      // Always drawn, and it leads with how many things are
                      // in this box. The whole screen could say what the
                      // order cost and when it would arrive without ever
                      // saying how much of it there was.
                      const SizedBox(height: AppSpacing.xs + 1),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              [
                                l10n.counted(group.itemCount, CountNoun.item),
                                ?option?.estimatedDelivery,
                                ?option?.name,
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.textStyles.bodySmall?.copyWith(
                                fontSize: 12,
                              ),
                            ),
                          ),
                          if (options.length > 1)
                            SabaIcon(
                              context.isRtl
                                  ? SabaIcons.chevronLeft
                                  : SabaIcons.chevronRight,
                              size: 13,
                              color: context.colors.onSurfaceVariant,
                            ),
                        ],
                      ),
                      if (!group.deliversHere) ...[
                        const SizedBox(height: AppSpacing.xs + 1),
                        Text(
                          [
                            ?group.estimatedDelivery,
                            l10n.removeOrChangeAddress,
                          ].join('. '),
                          style: context.textStyles.bodySmall?.copyWith(
                            fontSize: 12,
                            color: context.colors.error,
                          ),
                        ),
                      ],
                      // What is being bought. The screen said how many
                      // things and what they cost, and never which things.
                      for (final item in group.lines)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: Text(
                            [
                              '${item.quantity} × ${item.name}',
                              ?item.variantLabel,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.textStyles.bodySmall?.copyWith(
                              fontSize: 12,
                              color: context.colors.onSurface,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: AppSpacing.sm + 1),
          ],
          if (summary.groups.length > 1)
            Text(
              l10n.twoDeliveriesNote,
              style: context.textStyles.bodySmall?.copyWith(
                fontSize: 12,
                height: 1.5,
              ),
            ),
        ],
      ),
    );
  }
}

class _ShippingSheet extends StatelessWidget {
  const _ShippingSheet({required this.group, required this.selectedId});

  final CheckoutGroup group;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = l10n.locale.toLanguageTag();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          AppSpacing.sm,
          AppSpacing.screenGutter,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              group.merchantName,
              style: AppTypography.subsectionTitle(context),
            ),
            const SizedBox(height: AppSpacing.md),
            for (final option in group.shippingOptions)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm + 1),
                child: _ChoiceRow(
                  isSelected: option.id == selectedId,
                  icon: SabaIcons.truck,
                  title: option.name,
                  subtitle: option.estimatedDelivery,
                  trailing: Text(
                    option.isFree
                        ? l10n.freeShipping
                        : Formatters.money(
                            option.fee,
                            locale: locale,
                            currencyCode: option.currencyCode,
                          ),
                    style: context.textStyles.labelLarge?.copyWith(
                      color: option.isFree
                          ? context.market.success
                          : context.colors.onSurface,
                    ),
                  ),
                  onTap: () => Navigator.of(context).pop(option.id),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Step 3 — how it is paid for.
class _PaymentCard extends ConsumerWidget {
  const _PaymentCard({required this.state, required this.summary});

  final CheckoutState state;
  final CheckoutSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final controller = ref.read(checkoutControllerProvider.notifier);
    final methods = summary.paymentMethods;

    String iconFor(PaymentMethodType type) => switch (type) {
      PaymentMethodType.card => SabaIcons.creditCard,
      PaymentMethodType.wallet => SabaIcons.coin,
      PaymentMethodType.cashOnDelivery => SabaIcons.truck,
      PaymentMethodType.bankTransfer => SabaIcons.card,
      PaymentMethodType.unknown => SabaIcons.creditCard,
    };

    return _StepCard(
      number: 3,
      title: l10n.paymentMethod,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (methods.isEmpty)
            Text(l10n.errorNotFound, style: context.textStyles.bodyMedium)
          else
            for (final method in methods)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm + 1),
                child: _ChoiceRow(
                  isSelected: method.id == state.selection.paymentMethodId,
                  isEnabled: method.isEnabled,
                  icon: iconFor(method.type),
                  title: method.label,
                  subtitle: method.isEnabled
                      ? method.description
                      : method.disabledReason,
                  onTap: method.isEnabled
                      ? () => controller.selectPaymentMethod(method.id)
                      : null,
                ),
              ),
          // How the money moves is said once, under the pay button.
        ],
      ),
    );
  }
}

/// A selectable row: the border carries the choice, and the radio confirms it.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.isSelected,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.isEnabled = true,
  });

  final bool isSelected;
  final String icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool isEnabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final market = context.market;

    return Semantics(
      button: true,
      selected: isSelected,
      enabled: isEnabled,
      label: title,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.input),
        child: Opacity(
          opacity: isEnabled ? 1 : 0.5,
          child: Container(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md + 2,
              AppSpacing.md + 1,
              AppSpacing.md + 2,
              AppSpacing.md + 1,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.input),
              border: Border.all(
                color: isSelected ? context.colors.primary : market.border,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                SabaIcon(
                  icon,
                  size: AppSizes.iconMd,
                  color: context.colors.onSurface,
                ),
                const SizedBox(width: AppSpacing.md - 1),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        // Two lines: "الدفع عند ا…" was cut at phone width.
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.textStyles.titleLarge?.copyWith(
                          fontSize: 13.5,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty)
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.bodySmall?.copyWith(
                            fontSize: 11.5,
                          ),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  trailing!,
                ],
                const SizedBox(width: AppSpacing.sm + 2),
                _Radio(isSelected: isSelected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.isSelected});

  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppMotion.press,
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: context.colors.surface,
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected
              ? context.colors.primary
              : context.market.borderStrong,
          width: isSelected ? 7 : 1.8,
        ),
      ),
    );
  }
}

/// Items, delivery, discount, then the total.
class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.summary});

  final CheckoutSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final market = context.market;
    final locale = l10n.locale.toLanguageTag();

    String money(num amount) => Formatters.money(
      amount,
      locale: locale,
      currencyCode: summary.currencyCode,
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border.all(color: market.border),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        children: [
          _TotalRow(label: l10n.subtotal, value: money(summary.subtotal)),
          _TotalRow(label: l10n.delivery, value: money(summary.shipping)),
          if (summary.discount > 0)
            _TotalRow(
              label: summary.couponCode == null
                  ? l10n.discount
                  : '${l10n.discount}, ${summary.couponCode}',
              value: Formatters.deduction(
                summary.discount,
                locale: locale,
                currencyCode: summary.currencyCode,
              ),
              colour: market.success,
            ),
          if (summary.tax > 0)
            _TotalRow(label: l10n.tax, value: money(summary.tax)),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs - 2),
            color: market.surfaceMuted,
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.grandTotal,
                  style: context.textStyles.titleMedium?.copyWith(
                    fontSize: 14.5,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                money(summary.total),
                style: context.theme
                    .extension<MarketplaceTextStyles>()
                    ?.price
                    .copyWith(fontSize: 20, height: 1.1),
              ),
            ],
          ),
          // Each store sends its own driver, and each is paid at the door,
          // so the shopper has to know how much to hand to which. Only the
          // stores that are coming.
          if (summary.groups.where((g) => g.amountDue != null).length > 1) ...[
            const SizedBox(height: AppSpacing.md),
            _SunkenBlock(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      SabaIcon(
                        SabaIcons.coin,
                        size: AppSizes.iconSm,
                        color: market.success,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          l10n.cashToEachDriver,
                          style: context.textStyles.titleSmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (final group in summary.groups)
                    if (group.amountDue case final due?)
                      _TotalRow(label: group.merchantName, value: money(due)),
                  Text(
                    l10n.cashToEachDriverNote,
                    style: context.textStyles.bodySmall?.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value, this.colour});

  final String label;
  final String value;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textStyles.bodyMedium?.copyWith(fontSize: 13),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            value,
            style: context.textStyles.labelLarge?.copyWith(
              fontSize: 13,
              color: colour ?? context.colors.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// The pay button repeats the amount, and the line under it says when money
/// moves — the one sentence that answers "what happens if I tap this".
class _PlaceOrderBar extends StatelessWidget {
  const _PlaceOrderBar({
    required this.state,
    required this.summary,
    required this.onPlaceOrder,
  });

  final CheckoutState state;
  final CheckoutSummary summary;
  final Future<void> Function() onPlaceOrder;

  /// Why the order cannot be placed yet, or null when it can (or is only
  /// busy): the store that will not come first, then what the server said.
  String? _blockedBecause(AppLocalizations l10n) {
    if (state.isPricing || state.isPlacing) return null;
    if (state.selection.addressId == null) return l10n.selectAddress;
    if (summary.canPlaceOrder) return null;
    for (final group in summary.groups) {
      if (!group.deliversHere) {
        return [
          '${group.merchantName}: ${group.estimatedDelivery ?? l10n.noDelivery}',
          l10n.removeOrChangeAddress,
        ].join('. ');
      }
    }
    return summary.warnings.firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ready = state.canPlaceOrder;

    return StickyBar(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: ready ? onPlaceOrder : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
              ),
              child: state.isPlacing
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.colors.onPrimary,
                      ),
                    )
                  : Text(
                      l10n.placeOrderFor(
                        Formatters.money(
                          summary.total,
                          locale: l10n.locale.toLanguageTag(),
                          currencyCode: summary.currencyCode,
                        ),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.labelLarge?.copyWith(
                        fontSize: 14,
                        color: context.colors.onPrimary,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm + 1),
          // A grey button says why it is grey (BUGS.md 18); otherwise, cash
          // on delivery is the only way to pay in v1.
          if (_blockedBecause(l10n) case final reason?)
            Text(
              reason,
              textAlign: TextAlign.center,
              style: context.textStyles.bodySmall?.copyWith(
                fontSize: 12,
                height: 1.45,
                color: context.colors.error,
              ),
            )
          else
            Text(
              l10n.codNote,
              textAlign: TextAlign.center,
              style: context.textStyles.bodySmall?.copyWith(
                fontSize: 11.5,
                height: 1.45,
              ),
            ),
        ],
      ),
    );
  }
}

/// A quiet secondary action beside a step title.
class _UnderlinedAction extends StatelessWidget {
  const _UnderlinedAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // A link, so purple.
    final colour = context.colors.primary;

    // The underline is 1px under 12px text, which made the whole control
    // about 17dp high — a third of the 48 this codebase sets for anything
    // interactive. The rule stays visually tight; the target does not.
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(
          minHeight: AppSizes.minTapTarget,
          minWidth: AppSizes.minTapTarget,
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.only(bottom: 1),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colour, width: 1.5)),
        ),
        child: Text(
          label,
          style: context.textStyles.labelLarge?.copyWith(
            fontSize: 12,
            color: colour,
          ),
        ),
      ),
    );
  }
}
