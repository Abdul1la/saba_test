import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../auth/domain/entities.dart';
import '../../../auth/presentation/auth_providers.dart';
import '../merchant_providers.dart';
import '../screens/merchant_store_settings_screen.dart';

/// The three things a new store has to do before anyone can buy from it.
///
/// A new owner landed on a dashboard reading "Store closed" with no switch to
/// open it and nothing saying why, while the one setting that decides whether
/// a sale is even possible - the delivery fee - sat in a screen nothing
/// pointed at. This says what is left, in order, and each row opens it.
///
/// It disappears once all three are done.
class StoreSetupChecklist extends ConsumerWidget {
  const StoreSetupChecklist({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final market = context.market;
    final store = ref.watch(currentUserProvider)?.merchant;
    final dashboard = ref.watch(merchantDashboardProvider).value;
    final settings = ref.watch(storeSettingsProvider).value;

    if (store == null) return const SizedBox.shrink();

    final hasProduct = (dashboard?.productCount ?? 0) > 0;
    final hasDelivery = (settings?.delivery?.governorates.isNotEmpty) ?? false;
    final approved = store.status == MerchantStatus.approved;

    // Done is done: an established store does not need telling how to open.
    if (hasProduct && hasDelivery && approved) return const SizedBox.shrink();
    // A store Saba turned down is told that by its own banner, not by a
    // checklist whose last line it can never tick.
    if (store.status == MerchantStatus.rejected) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: market.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.setUpYourStore, style: context.textStyles.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          _Step(
            label: l10n.stepAddFirstProduct,
            done: hasProduct,
            onTap: () => context.push(AppRoutes.merchantProductForm),
          ),
          _Step(
            label: l10n.stepSetDelivery,
            done: hasDelivery,
            onTap: () => context.push(AppRoutes.merchantStoreSettings),
          ),
          // Nothing to tap: it is Saba's turn, and saying so is the point.
          _Step(label: l10n.stepWaitForApproval, done: approved),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.label, required this.done, this.onTap});

  final String label;
  final bool done;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    final chevron = context.isRtl
        ? SabaIcons.chevronLeft
        : SabaIcons.chevronRight;

    return InkWell(
      onTap: done ? null : onTap,
      borderRadius: BorderRadius.circular(AppRadius.action),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            SabaIcon(
              done ? SabaIcons.check : SabaIcons.clock,
              size: AppSizes.iconMd,
              color: done ? market.success : market.borderStrong,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                style: context.textStyles.bodyMedium?.copyWith(
                  color: done ? market.textMuted : null,
                  decoration: done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (!done && onTap != null)
              SabaIcon(chevron, size: AppSizes.iconSm, color: market.textMuted),
          ],
        ),
      ),
    );
  }
}
