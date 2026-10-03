import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/providers/paged_state.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/filter_chip_row.dart';
import '../../../../core/widgets/paged_list_view.dart';
import '../../../../core/widgets/price_text.dart' show StockBadge;
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/skeletons.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../home/presentation/home_providers.dart';
import '../../domain/entities.dart';
import '../merchant_providers.dart';
import '../../../../core/utils/western_digits_formatter.dart';
import '../../../../core/widgets/saba_nav_bar.dart';

/// The merchant's shelf.
///
/// It used to be five tabs of approval state — Draft, Pending, Approved,
/// Rejected — which is the catalogue team's question, not the seller's. A
/// merchant opening this screen wants to know what is running out, so the
/// shelf is sorted by what is sellable: everything, running low, out, hidden.
///
/// Approval has not disappeared; a rejected product still says so on its row,
/// and the dashboard's "Needs you today" is where it asks to be dealt with.
class MerchantProductsScreen extends ConsumerStatefulWidget {
  const MerchantProductsScreen({super.key, this.initialFilter});

  final String? initialFilter;

  @override
  ConsumerState<MerchantProductsScreen> createState() =>
      _MerchantProductsScreenState();
}

class _MerchantProductsScreenState
    extends ConsumerState<MerchantProductsScreen> {
  /// Null is everything. The rest match the shelf filters the API takes.
  static const List<String?> _filters = <String?>[
    null,
    'waiting',
    'low',
    'out',
    'hidden',
  ];

  late int _selected = () {
    final index = _filters.indexOf(widget.initialFilter);
    return index < 0 ? 0 : index;
  }();

  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _labelFor(String? filter, Map<String, int>? counts) {
    final l10n = context.l10n;
    final label = switch (filter) {
      'waiting' => l10n.waitingForApproval,
      'low' => l10n.lowStockFilter,
      'out' => l10n.outFilter,
      'hidden' => l10n.hiddenFilter,
      _ => l10n.all,
    };
    // A number only when the server sent one. "Hidden · 0" and "Hidden" mean
    // different things and must not be written the same way.
    final count = counts?[filter ?? 'all'];
    return count == null ? label : '$label · $count';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final counts = switch (ref.watch(merchantProductCountsProvider)) {
      AsyncData(:final value) => value,
      _ => null,
    };

    return Scaffold(
      body: Column(
        children: [
          PageTitle(
            title: l10n.myProducts,
            trailing: AppButton(
              label: l10n.addProduct,
              icon: SabaIcons.plus,
              size: AppButtonSize.small,
              expand: false,
              onPressed: () => context.push(AppRoutes.merchantProductForm),
            ),
          ),
          const SizedBox(height: AppSpacing.md + 2),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenGutter,
            ),
            // A search box, not a form field: the words go inside it as a
            // hint. As an AppTextField it wore a label above it, and a label
            // on a field nobody must fill says "(Optional)".
            child: TextField(
              controller: _searchController,
              inputFormatters: const [WesternDigitsFormatter()],
              textInputAction: TextInputAction.search,
              // A shelf of eighty-six is searched, not scrolled.
              onChanged: (value) => setState(() => _query = value.trim()),
              decoration: InputDecoration(
                hintText: l10n.searchYourProducts,
                prefixIcon: Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: AppSpacing.lg - 2,
                    end: AppSpacing.md,
                  ),
                  child: SabaIcon(
                    SabaIcons.search,
                    size: AppSizes.iconMd,
                    color: context.market.textMuted,
                  ),
                ),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: l10n.clear,
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: SabaIcon(
                          SabaIcons.close,
                          size: AppSizes.iconSm,
                          color: context.market.textMuted,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md + 2),
          TextFilterChips(
            labels: [for (final filter in _filters) _labelFor(filter, counts)],
            selectedIndex: _selected,
            onSelected: (index) => setState(() => _selected = index),
          ),
          const SizedBox(height: AppSpacing.md + 2),
          Expanded(
            child: _ProductList(
              shelf: (
                filter: _filters[_selected],
                query: _query.isEmpty ? null : _query,
              ),
              isSearching: _query.isNotEmpty || _filters[_selected] != null,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductList extends ConsumerStatefulWidget {
  const _ProductList({required this.shelf, required this.isSearching});

  final ProductShelf shelf;

  /// Whether the list is narrowed, which decides whether an empty result
  /// means "you have no products" or "nothing matched".
  final bool isSearching;

  @override
  ConsumerState<_ProductList> createState() => _ProductListState();
}

class _ProductListState extends ConsumerState<_ProductList> {
  /// Products with a request in flight. `_ProductRow` awaited nothing, so
  /// "Submit for approval" stayed idle-looking for the whole round trip and
  /// every extra tap posted again.
  final Set<String> _busy = <String>{};

  ProductShelf get shelf => widget.shelf;

  Future<void> _guard(String id, Future<void> Function() action) async {
    if (_busy.contains(id)) return;
    setState(() => _busy.add(id));
    await action();
    if (!mounted) return;
    setState(() => _busy.remove(id));
  }

  void _refresh() {
    ref.invalidate(merchantProductsProvider);
    ref.invalidate(merchantProductCountsProvider);
    ref.invalidate(merchantDashboardProvider);
    ref.invalidate(merchantInventoryProvider);
  }

  Future<void> _setStock(MerchantProductRow product, int stock) async {
    await _guard(product.id, () async {
      final result = await ref
          .read(merchantRepositoryProvider)
          .setProductStock(productId: product.id, stock: stock);
      if (!mounted) return;
      result.fold(
        ok: (_) => _refresh(),
        err: (failure) => AppSnackBar.failure(context, failure),
      );
    });
  }

  Future<void> _restock(MerchantProductRow product) async {
    final value = await AppDialogs.bottomSheet<int>(
      context,
      isScrollControlled: false,
      builder: (_) => _RestockSheet(product: product),
    );
    if (value == null || !mounted) return;
    await _setStock(product, value);
  }

  Future<void> _submit(MerchantProductRow product) async {
    await _guard(product.id, () async {
      final result = await ref
          .read(merchantRepositoryProvider)
          .submitForApproval(product.id);
      if (!mounted) return;
      result.fold(
        ok: (_) {
          _refresh();
          AppSnackBar.success(context, context.l10n.productPendingApproval);
        },
        err: (failure) => AppSnackBar.failure(context, failure),
      );
    });
  }

  Future<void> _setShown(MerchantProductRow product) async {
    final shown = !product.isActive;
    await _guard(product.id, () async {
      final result = await ref
          .read(merchantRepositoryProvider)
          .setProductShown(product.id, shown: shown);
      if (!mounted) return;
      result.fold(
        ok: (_) {
          _refresh();
          AppSnackBar.success(
            context,
            shown ? context.l10n.productShown : context.l10n.productHidden,
          );
        },
        err: (failure) => AppSnackBar.failure(context, failure),
      );
    });
  }

  Future<void> _flashSale(MerchantProductRow product) async {
    // The sheet sends the request itself, so what the server refuses lands
    // on its field; it comes back with what to tell the store.
    final said = await AppDialogs.bottomSheet<String>(
      context,
      builder: (_) => _FlashSaleSheet(product: product),
    );
    if (said == null || !mounted) return;
    _refresh();
    // Home's rail is the stores' flash sales.
    ref.invalidate(homeFeedProvider);
    AppSnackBar.success(context, said);
  }

  Future<void> _delete(MerchantProductRow product) async {
    if (_busy.contains(product.id)) return;
    final l10n = context.l10n;
    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.deleteProductTitle,
      message: l10n.deleteProductMessage,
      confirmLabel: l10n.delete,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    await _guard(product.id, () async {
      final result = await ref
          .read(merchantRepositoryProvider)
          .deleteProduct(product.id);
      if (!mounted) return;
      result.fold(
        ok: (_) => _refresh(),
        err: (failure) => AppSnackBar.failure(context, failure),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(merchantProductsProvider(shelf));
    final notifier = ref.read(merchantProductsProvider(shelf).notifier);

    return AsyncStateView<PagedState<MerchantProductRow>>(
      value: state,
      onRetry: () => ref.invalidate(merchantProductsProvider(shelf)),
      loadingBuilder: (_) => const ListSkeleton(itemHeight: 88),
      builder: (paged) => PagedListView<MerchantProductRow>(
        state: paged,
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          0,
          AppSpacing.screenGutter,
          SabaNavBar.clearance(context),
        ),
        separatorHeight: AppSpacing.md,
        onLoadMore: notifier.loadMore,
        onRefresh: notifier.refresh,
        onRetryLoadMore: notifier.retryLoadMore,
        // A filtered list that finds nothing is not an empty store. Offering
        // "Add your first product" to a merchant with eighty-six of them is
        // the app not knowing what it just did.
        emptyState: widget.isSearching
            ? EmptyStateView(
                title: l10n.noProductsMatch,
                icon: SabaIcons.search,
              )
            : EmptyStateView(
                title: l10n.noProductsYet,
                message: l10n.addFirstProduct,
                icon: SabaIcons.box,
                actionLabel: l10n.addProduct,
                onAction: () => context.push(AppRoutes.merchantProductForm),
              ),
        itemBuilder: (context, product, _) => _ProductRow(
          product: product,
          isBusy: _busy.contains(product.id),
          onEdit: () =>
              context.push(AppRoutes.merchantProductForm, extra: product),
          onSubmit: () => _submit(product),
          onToggleShown: () => _setShown(product),
          onDelete: () => _delete(product),
          onFlashSale: () => _flashSale(product),
          onRestock: () => _restock(product),
          onStockChanged: (value) => _setStock(product, value),
        ),
      ),
    );
  }
}

/// One product on the shelf.
class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.product,
    required this.onEdit,
    required this.onSubmit,
    required this.onToggleShown,
    required this.onDelete,
    required this.onFlashSale,
    required this.onRestock,
    required this.onStockChanged,
    this.isBusy = false,
  });

  final MerchantProductRow product;
  final VoidCallback onEdit;
  final VoidCallback onSubmit;
  final VoidCallback onToggleShown;
  final VoidCallback onDelete;
  final VoidCallback onFlashSale;
  final VoidCallback onRestock;
  final ValueChanged<int> onStockChanged;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final market = context.market;
    final locale = l10n.locale.toLanguageTag();
    final isHidden = !product.isActive;

    return Opacity(
      // A hidden product is still yours and still editable, so it stays on
      // the shelf — dimmed, and labelled, because dimming alone is a style a
      // colour-blind reader may not see at all.
      opacity: isHidden ? 0.55 : 1,
      // The row looks like a card, so a tap on it does something: it opens
      // the product to edit, as the pencil does (BUGS 98).
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md + 2),
            decoration: BoxDecoration(
              border: Border.all(color: market.border),
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    AppNetworkImage(
                      url: product.imageUrl,
                      width: 56,
                      height: 56,
                      radius: AppRadius.action,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.textStyles.bodyMedium?.copyWith(
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            Formatters.money(
                              product.price,
                              locale: locale,
                              currencyCode: product.currencyCode,
                            ),
                            // A price, so the price's navy and weight, not a
                            // grey caption.
                            style: context.theme
                                .extension<MarketplaceTextStyles>()
                                ?.price
                                .copyWith(fontSize: 15, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _StockBadge(product: product, isHidden: isHidden),
                  ],
                ),
                // Saba took it down: said first, with why.
                if (product.takenDown) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: market.errorSoft,
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                    child: Text(
                      [
                        l10n.takenDownBySaba,
                        ?product.takenDownReason,
                      ].join(': '),
                      style: context.textStyles.labelSmall?.copyWith(
                        color: context.colors.error,
                      ),
                    ),
                  ),
                ],
                if (product.isRejected && product.rejectionReason != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: market.errorSoft,
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                    child: Text(
                      product.rejectionReason!,
                      style: context.textStyles.labelSmall?.copyWith(
                        color: context.colors.error,
                      ),
                    ),
                  ),
                ],
                // Only a product in front of shoppers - approved, not hidden -
                // goes on a flash sale; a hidden one keeps a running sale's chip
                // so the sale can be ended. Its own line: the action row below
                // has no room for a fifth control at 320 wide.
                if (product.isApproved &&
                    (!isHidden || product.isOnFlashSale)) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: _FlashSaleControl(
                      product: product,
                      onPressed: isBusy ? null : onFlashSale,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                // The stock control on one side, the actions on the other, and
                // the control flexible between them. A Spacer cannot give way, so
                // the worst row on the shelf - out of stock and still a draft, so
                // a Restock button beside all three icons - overflowed in Arabic
                // and would do the same in English at a raised font scale.
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Sold in options: each option's stock is set on its own,
                    // in the form or Inventory, and the server refuses one
                    // number for the whole. The empty box keeps the actions at
                    // the end.
                    if (product.hasVariants)
                      const SizedBox.shrink()
                    // Out of stock is the one state with a single obvious next
                    // move, so it gets a button rather than a stepper starting
                    // from nothing.
                    else
                      Flexible(
                        child: product.isOutOfStock
                            ? AppButton(
                                label: l10n.restock,
                                // One per sold-out row, so not the screen's
                                // main action: that is "Add product".
                                variant: AppButtonVariant.secondary,
                                size: AppButtonSize.small,
                                isLoading: isBusy,
                                // Sits beside the stepper it replaces, so it
                                // takes the width its label needs; expanding
                                // here asks a Row for infinite width and
                                // throws the row away.
                                expand: false,
                                onPressed: onRestock,
                              )
                            : _StockStepper(
                                value: product.stock,
                                enabled: !isBusy,
                                onChanged: onStockChanged,
                              ),
                      ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (product.isDraft || product.isRejected)
                          IconButton(
                            onPressed: isBusy ? null : onSubmit,
                            tooltip: l10n.submitForApproval,
                            icon: SabaIcon(
                              SabaIcons.send,
                              size: AppSizes.iconMd,
                            ),
                          ),
                        // Only an approved product is in front of shoppers to
                        // take away, or to put back.
                        if (!product.isPending &&
                            !product.isDraft &&
                            !product.isRejected)
                          IconButton(
                            // Locked while Saba has it down.
                            onPressed: isBusy || product.takenDown
                                ? null
                                : onToggleShown,
                            tooltip: isHidden
                                ? l10n.showToShoppers
                                : l10n.hideFromShoppers,
                            icon: SabaIcon(
                              isHidden ? SabaIcons.eye : SabaIcons.eyeOff,
                              size: AppSizes.iconMd,
                            ),
                          ),
                        IconButton(
                          onPressed: onEdit,
                          tooltip: l10n.edit,
                          icon: SabaIcon(
                            SabaIcons.pencil,
                            size: AppSizes.iconMd,
                          ),
                        ),
                        IconButton(
                          onPressed: isBusy ? null : onDelete,
                          tooltip: l10n.delete,
                          icon: SabaIcon(
                            SabaIcons.trash,
                            size: AppSizes.iconMd,
                            color: context.colors.error,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Flash sale" to start one; "Flash sale until 9:00 PM" while one runs,
/// which opens the same sheet to change it or end it.
class _FlashSaleControl extends StatelessWidget {
  const _FlashSaleControl({required this.product, required this.onPressed});

  final MerchantProductRow product;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ends = product.saleEndsAt;
    if (ends == null) {
      return AppButton(
        label: l10n.flashSale,
        icon: SabaIcons.flame,
        variant: AppButtonVariant.secondary,
        size: AppButtonSize.small,
        expand: false,
        onPressed: onPressed,
      );
    }

    final locale = l10n.locale.toLanguageTag();
    final local = ends.toLocal();
    final now = DateTime.now();
    final today =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSizes.minTapTarget),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: 1,
          // Shrinks whole rather than cut the time off.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: StockBadge(
              label: l10n.flashSaleUntil(
                today
                    ? Formatters.time(ends, locale: locale)
                    : Formatters.monthDayTime(ends, locale: locale),
              ),
              icon: SabaIcons.flame,
              // A sale is heat: amber, like the shopper's flash-sale card.
              background: context.market.heat,
              foreground: context.market.onHeat,
            ),
          ),
        ),
      ),
    );
  }
}

/// A flash sale on one product: a sale price in steps of 250 IQD, when it
/// ends, and "End sale now" while one runs.
class _FlashSaleSheet extends ConsumerStatefulWidget {
  const _FlashSaleSheet({required this.product});

  final MerchantProductRow product;

  @override
  ConsumerState<_FlashSaleSheet> createState() => _FlashSaleSheetState();
}

class _FlashSaleSheetState extends ConsumerState<_FlashSaleSheet> {
  late final _price = TextEditingController(
    text: widget.product.isOnFlashSale ? '${widget.product.price.round()}' : '',
  );

  /// Three hours from now, on the hour, until the store picks.
  late DateTime _endsAt = () {
    if (widget.product.saleEndsAt case final ends?) return ends.toLocal();
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, now.hour + 3);
  }();

  String? _priceError;
  String? _endError;
  bool _saving = false;
  bool _ending = false;

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  Future<void> _pickEnd() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _endsAt.isBefore(now) ? now : _endsAt,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 30)),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_endsAt),
    );
    if (time == null || !mounted) return;
    setState(() {
      _endsAt = DateTime(day.year, day.month, day.day, time.hour, time.minute);
      _endError = null;
    });
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final value = Formatters.typedNumber(_price.text);
    final priceError = value == null || value <= 0
        ? l10n.salePriceInvalid
        : value % 250 != 0
        ? l10n.iqdSteps
        : value >= widget.product.priceBeforeSale
        ? l10n.salePriceNotLower
        : null;
    final endError = _endsAt.isAfter(DateTime.now())
        ? null
        : l10n.saleEndPassed;
    setState(() {
      _priceError = priceError;
      _endError = endError;
    });
    if (priceError != null || endError != null) return;

    setState(() => _saving = true);
    final result = await ref
        .read(merchantRepositoryProvider)
        .startFlashSale(
          productId: widget.product.id,
          salePrice: value!,
          endsAt: _endsAt,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    result.fold(
      ok: (_) => Navigator.of(context).pop(l10n.flashSaleSaved),
      err: (failure) {
        final price = failure.messageForField('salePrice');
        final end = failure.messageForField('saleEndsAt');
        if (price == null && end == null) {
          AppSnackBar.failure(context, failure);
          return;
        }
        setState(() {
          _priceError = price;
          _endError = end;
        });
      },
    );
  }

  Future<void> _end() async {
    final l10n = context.l10n;
    // The price changes for every shopper at once: asked, not assumed.
    final sure = await AppDialogs.confirm(
      context,
      title: l10n.endSaleQuestion,
      message: l10n.endSaleWarning,
      confirmLabel: l10n.endSaleNow,
      isDestructive: true,
    );
    if (!sure || !mounted) return;
    setState(() => _ending = true);
    final result = await ref
        .read(merchantRepositoryProvider)
        .endFlashSale(widget.product.id);
    if (!mounted) return;
    setState(() => _ending = false);
    result.fold(
      ok: (_) => Navigator.of(context).pop(l10n.flashSaleEnded),
      err: (failure) => AppSnackBar.failure(context, failure),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = l10n.locale.toLanguageTag();
    final product = widget.product;
    final busy = _saving || _ending;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.flashSale, style: AppTypography.subsectionTitle(context)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              product.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.textStyles.bodySmall,
            ),
            // Hidden from shoppers: a running sale can be ended, not changed.
            if (product.isActive) ...[
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                label: l10n.salePrice,
                controller: _price,
                autofocus: !product.isOnFlashSale,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                isRequired: true,
                // A tenth off, to the 250 below: a price this sale could be.
                hint: context.exampleOf(
                  (product.priceBeforeSale * 0.9 / 250).floor() * 250,
                ),
                helper: l10n.normalPrice(
                  Formatters.money(
                    product.priceBeforeSale,
                    locale: locale,
                    currencyCode: product.currencyCode,
                  ),
                ),
                serverError: _priceError,
                onChanged: (_) {
                  if (_priceError != null) setState(() => _priceError = null);
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              InkWell(
                onTap: busy ? null : _pickEnd,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: l10n.endsOn,
                    errorText: _endError,
                    suffixIcon: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: SabaIcon(
                        SabaIcons.clock,
                        size: AppSizes.iconSm,
                        color: context.market.textMuted,
                      ),
                    ),
                  ),
                  child: Text(
                    Formatters.monthDayTime(_endsAt, locale: locale),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.bodyMedium,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: product.isOnFlashSale ? l10n.save : l10n.startSale,
                icon: SabaIcons.flame,
                isLoading: _saving,
                onPressed: busy ? null : _save,
              ),
            ],
            if (product.isOnFlashSale) ...[
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                label: l10n.endSaleNow,
                variant: AppButtonVariant.dangerText,
                isLoading: _ending,
                onPressed: busy ? null : _end,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "18 in stock" / "3 left" / "Out of stock" / "Hidden".
///
/// Always a word, never a colour on its own: a merchant who cannot see the
/// amber got no warning at all from the old row, and the number could not
/// tell them either, because "low" depends on a threshold nothing displayed.
class _StockBadge extends StatelessWidget {
  const _StockBadge({required this.product, required this.isHidden});

  final MerchantProductRow product;
  final bool isHidden;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    // Where a product stands with Saba comes first: a merchant who has
    // just added one wants to know it is waiting, not how many are left.
    if (product.isPending || product.isDraft) {
      return StatusBadge(
        label: l10n.waitingForApproval,
        tone: StatusTone.progress,
        compact: true,
      );
    }
    if (product.isRejected) {
      return StatusBadge(
        label: l10n.statusRejected,
        tone: StatusTone.negative,
        compact: true,
      );
    }
    if (product.takenDown) {
      return StatusBadge(
        label: l10n.takenDown,
        tone: StatusTone.negative,
        compact: true,
      );
    }
    if (isHidden) {
      return StatusBadge(
        label: l10n.hidden,
        tone: StatusTone.neutral,
        compact: true,
      );
    }
    if (product.isOutOfStock) {
      return StatusBadge(
        label: l10n.outOfStock,
        tone: StatusTone.negative,
        compact: true,
      );
    }
    if (product.isLowStock) {
      return StatusBadge(
        label: '${product.stock} ${l10n.leftCount}',
        tone: StatusTone.caution,
        compact: true,
      );
    }
    return StatusBadge(
      label: '${product.stock} ${l10n.inStockCount}',
      tone: StatusTone.positive,
      compact: true,
    );
  }
}

/// Stock, changed where it is read.
///
/// One unit at a time is what the design draws, because the common correction
/// on a shelf is "I found one more" or "one was damaged". Anything larger is
/// a Restock, which asks for the number outright.
class _StockStepper extends StatelessWidget {
  const _StockStepper({
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final market = context.market;

    Widget button(String icon, VoidCallback? onTap, String tooltip) {
      return Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: enabled ? onTap : null,
          customBorder: const CircleBorder(),
          child: Container(
            width: AppSizes.minTapTarget,
            height: AppSizes.minTapTarget,
            alignment: Alignment.center,
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: market.surfaceMuted,
                shape: BoxShape.circle,
              ),
              child: SabaIcon(
                icon,
                size: AppSizes.iconSm,
                color: onTap == null || !enabled
                    ? market.textMuted
                    : context.colors.onSurface,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(
          SabaIcons.minus,
          value > 0 ? () => onChanged(value - 1) : null,
          context.l10n.decrease,
        ),
        Text(
          '$value',
          style: context.textStyles.titleSmall?.copyWith(fontSize: 14),
        ),
        button(
          SabaIcons.plus,
          () => onChanged(value + 1),
          context.l10n.increase,
        ),
      ],
    );
  }
}

/// Asks for the new stock outright, because a product at zero is usually
/// coming back as a whole box, not one tap at a time.
class _RestockSheet extends StatefulWidget {
  const _RestockSheet({required this.product});

  final MerchantProductRow product;

  @override
  State<_RestockSheet> createState() => _RestockSheetState();
}

class _RestockSheetState extends State<_RestockSheet> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = Formatters.typedWholeNumber(_controller.text);
    if (value == null || value <= 0) {
      setState(() => _error = context.l10n.validationRequired);
      return;
    }
    Navigator.of(context).pop(value);
  }

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
            Text(l10n.setStock, style: AppTypography.subsectionTitle(context)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              widget.product.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.textStyles.bodySmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              label: l10n.stock,
              hint: context.exampleOf(24),
              controller: _controller,
              // One number, one sheet: the keyboard comes up with it.
              autofocus: true,
              keyboardType: TextInputType.number,
              isRequired: true,
              serverError: _error,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: AppSpacing.xl),
            AppButton(label: l10n.confirm, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}
