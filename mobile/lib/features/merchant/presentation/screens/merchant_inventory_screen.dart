import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/providers/paged_state.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/paged_list_view.dart';
import '../../../../core/widgets/search_pill.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/skeletons.dart';
import '../../../../core/widgets/state_views.dart';
import '../../domain/entities.dart';
import '../merchant_providers.dart';

/// Stock levels per product or variant (specification section 25).
///
/// Adjustments are sent as an intent; the server applies them inside a
/// transaction and writes an inventory record. The app never computes the new
/// total itself.
class MerchantInventoryScreen extends ConsumerWidget {
  const MerchantInventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(merchantInventoryProvider);
    final notifier = ref.read(merchantInventoryProvider.notifier);

    return Scaffold(
      appBar: SabaAppBar(
        title: l10n.inventory,
        backFallback: AppRoutes.merchantDashboard,
      ),
      body: AsyncStateView<PagedState<InventoryRow>>(
        value: state,
        onRetry: () => ref.invalidate(merchantInventoryProvider),
        loadingBuilder: (_) => const ListSkeleton(itemHeight: 76),
        builder: (paged) => PagedListView<InventoryRow>(
          state: paged,
          onLoadMore: notifier.loadMore,
          onRefresh: notifier.refresh,
          onRetryLoadMore: notifier.retryLoadMore,
          emptyState: EmptyStateView(
            title: l10n.emptyProducts,
            icon: SabaIcons.box,
          ),
          itemBuilder: (context, row, _) => _InventoryRowCard(
            row: row,
            onAdjust: () => _adjust(context, ref, row),
          ),
        ),
      ),
    );
  }

  Future<void> _adjust(
    BuildContext context,
    WidgetRef ref,
    InventoryRow row,
  ) async {
    final quantity = await AppDialogs.bottomSheet<int>(
      context,
      isScrollControlled: false,
      builder: (_) => _AdjustStockSheet(row: row),
    );
    if (quantity == null || !context.mounted) return;

    // The sheet asks for the new quantity, and the server takes a change:
    // so the change is the difference. Sending the typed number as it was
    // added it - 3 on the shelf, "2" typed, 5 saved - and correcting stock
    // down was impossible.
    // ponytail: worked out from the row on screen; a sale landing between
    // opening the sheet and saving is not seen. A server "set" call (or an
    // expected-current check) closes that when the backend is real.
    final result = await ref
        .read(merchantRepositoryProvider)
        .adjustStock(
          inventoryId: row.id,
          quantity: quantity - row.available,
          reason: 'MANUAL_ADJUSTMENT',
        );
    if (!context.mounted) return;

    result.fold(
      // The shelf too: it shows each product's total, which an option's
      // change moves, and it said 15 until a reload made it 18.
      ok: (_) => ref
        ..invalidate(merchantInventoryProvider)
        ..invalidate(merchantDashboardProvider)
        ..invalidate(merchantProductsProvider)
        ..invalidate(merchantProductCountsProvider),
      err: (failure) => AppSnackBar.failure(context, failure),
    );
  }
}

class _InventoryRowCard extends StatelessWidget {
  const _InventoryRowCard({required this.row, required this.onAdjust});

  final InventoryRow row;
  final VoidCallback onAdjust;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final market = context.market;
    final statusColor = row.isOutOfStock
        ? context.colors.error
        : row.isLowStock
        ? market.warning
        : market.success;
    final radius = BorderRadius.circular(AppRadius.card);
    final details = row.variantLabel ?? '';

    return Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: market.border),
      ),
      clipBehavior: Clip.antiAlias,
      // The whole card adjusts: the row exists to change one number.
      child: InkWell(
        onTap: onAdjust,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md + 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppNetworkImage(
                    url: row.imageUrl,
                    width: 52,
                    height: 52,
                    radius: AppRadius.action,
                    fallbackIcon: SabaIcons.box,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.titleSmall?.copyWith(
                            fontSize: 14.5,
                          ),
                        ),
                        if (details.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            details,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.textStyles.labelSmall,
                          ),
                        ],
                        // Low stock was carried by hue alone, and the number
                        // cannot say it either: "low" depends on a per-row
                        // threshold this screen never shows. A merchant who
                        // cannot separate amber from green got no warning.
                        if (row.isOutOfStock || row.isLowStock) ...[
                          const SizedBox(height: AppSpacing.sm),
                          StatusBadge(
                            label: row.isOutOfStock
                                ? l10n.outOfStock
                                : l10n.lowStock,
                            tone: row.isOutOfStock
                                ? StatusTone.negative
                                : StatusTone.caution,
                            compact: true,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  CircleIconButton(
                    icon: SabaIcons.pencil,
                    tooltip: l10n.adjustStock,
                    size: 36,
                    onPressed: onAdjust,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm + 2,
                ),
                decoration: BoxDecoration(
                  color: market.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppRadius.action),
                ),
                child: Row(
                  children: [
                    _Stat(
                      label: l10n.availableStock,
                      value: '${row.available}',
                      color: statusColor,
                    ),
                    _Stat(label: l10n.reservedStock, value: '${row.reserved}'),
                    _Stat(label: l10n.soldStock, value: '${row.sold}'),
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

/// One of the three figures, each a third of the strip.
class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: context.textStyles.titleMedium?.copyWith(
              fontSize: 17,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textStyles.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _AdjustStockSheet extends StatefulWidget {
  const _AdjustStockSheet({required this.row});

  final InventoryRow row;

  @override
  State<_AdjustStockSheet> createState() => _AdjustStockSheetState();
}

class _AdjustStockSheetState extends State<_AdjustStockSheet> {
  final _formKey = GlobalKey<FormState>();

  /// Opens with the current figure selected, not just shown.
  ///
  /// The field is prefilled so the merchant can see what the stock is now,
  /// but tapping a filled number field only moves the caret — so typing 5
  /// over 18 saved 185 or 518, and the merchant found out when the product
  /// oversold. Selected, the first keystroke replaces it, which is what
  /// "new quantity" means. It also saves clearing the field by hand.
  late final _controller =
      TextEditingController(text: widget.row.available.toString())
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.row.available.toString().length,
        );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.stockAdjustment,
                style: AppTypography.subsectionTitle(context),
              ),
              const SizedBox(height: AppSpacing.xs),
              // Which one: a product with four colours gave four rows that
              // all said "Nova X5 Smartphone", so the sheet could not say
              // what was about to change.
              Text(
                [widget.row.name, ?widget.row.variantLabel].join('  ·  '),
                style: context.textStyles.bodySmall,
              ),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                label: l10n.newQuantity,
                hint: context.exampleOf(18),
                controller: _controller,
                isRequired: true,
                // The sheet exists to type one number into. Making the
                // merchant tap the field first is a step that buys nothing.
                autofocus: true,
                keyboardType: TextInputType.number,
                validator: (value) => Validators.number(value, l10n),
              ),
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: l10n.save,
                onPressed: () {
                  if (!(_formKey.currentState?.validateAndReveal() ?? false)) {
                    return;
                  }
                  Navigator.of(
                    context,
                  ).pop(Formatters.typedWholeNumber(_controller.text));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
