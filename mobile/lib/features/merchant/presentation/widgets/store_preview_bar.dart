import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../auth/presentation/auth_providers.dart';

/// Is [merchantId] the store the signed-in merchant owns?
///
/// A merchant opening their own shop was handed the buyer's page: they could
/// put their own phone in a cart (it worked), wishlist it, share it, read
/// their own coupons and see "only a few left" about their own stock. Every
/// one of those controls asks this first.
final isMyStoreProvider = Provider.family<bool, String?>((ref, merchantId) {
  final mine = ref.watch(currentUserProvider)?.merchant?.id;
  return mine != null && merchantId != null && mine == merchantId;
});

/// The band across the top of a merchant's own shop or product: this is a
/// preview, not a shop you can buy from.
class StorePreviewBar extends StatelessWidget {
  const StorePreviewBar({super.key, this.onEdit, this.notListed = false});

  /// Where "Edit" goes, when there is somewhere sensible.
  final VoidCallback? onEdit;

  /// The product shown is one buyers cannot see (hidden, waiting, rejected
  /// or taken down), so the bar must not say this is what they see.
  final bool notListed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final market = context.market;

    return Material(
      color: market.info.withValues(alpha: 0.12),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              SabaIcon(
                notListed ? SabaIcons.eyeOff : SabaIcons.eye,
                size: AppSizes.iconSm,
                color: market.info,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  notListed ? l10n.previewNotListed : l10n.storePreview,
                  style: context.textStyles.labelMedium?.copyWith(
                    color: market.info,
                  ),
                ),
              ),
              if (onEdit != null)
                TextButton(onPressed: onEdit, child: Text(l10n.edit)),
              TextButton(
                onPressed: () => context.go(AppRoutes.merchantDashboard),
                child: Text(l10n.backToDashboard),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
