import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../messaging/presentation/messaging_providers.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../../core/widgets/dark_header_card.dart';
import '../../../../core/widgets/saba_tile.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../auth/domain/entities.dart';
import '../../../auth/presentation/auth_providers.dart';
import '../../../legal/legal_screen.dart';
import '../widgets/merchant_widgets.dart';
import '../../../../core/widgets/saba_nav_bar.dart';
import '../../../../core/utils/iraqi_phone.dart';
import '../../../../core/widgets/saba_logo.dart';

/// The merchant's own account hub.
///
/// Built like the customer's account: who you are on a card, then the rows
/// grouped under a heading each, every row with its own colour. It used to be
/// one long list of grey icons split by dividers - eleven rows read top to
/// bottom to find one.
class MerchantAccountScreen extends ConsumerWidget {
  const MerchantAccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final market = context.market;
    final auth = ref.watch(authControllerProvider).value;
    final unreadMessages = ref.watch(unreadMessageCountProvider);
    final user = auth?.user;
    final store = user?.merchant;

    if (user == null) {
      return Scaffold(
        body: Column(
          children: [
            PageTitle(title: l10n.account),
            Expanded(
              child: EmptyStateView(
                title: l10n.guestTitle,
                message: l10n.guestMessage,
                icon: SabaIcons.user,
                actionLabel: l10n.signIn,
                onAction: () => context.push(AppRoutes.login),
              ),
            ),
          ],
        ),
      );
    }

    // Each row's colour is the theme's ink on its own soft fill, so both
    // hold in dark mode. Adjacent rows never share one.
    final blue = (market.info, market.infoSoft);
    final green = (market.success, market.successSoft);
    final purple = (market.accent, market.accentSoft);
    final amber = (market.warning, market.warningSoft);
    final ink = (context.colors.onSurface, market.surfaceMuted);

    // A nav tab has nothing behind it, so it opens with a title rather than
    // a bar with a back arrow that would have nowhere to go.
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          WhiteHeader(
            child: _StoreHeader(user: user, store: store),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.xl,
              AppSpacing.screenGutter,
              SabaNavBar.clearance(context),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (auth != null && !auth.canSell)
                  const PendingApprovalBanner(
                    margin: EdgeInsets.only(bottom: AppSpacing.xl),
                  ),
                TileGroup(
                  title: l10n.myStore,
                  tiles: [
                    SabaTile(
                      icon: SabaIcons.store,
                      label: l10n.storeSettings,
                      tint: purple,
                      onTap: () =>
                          context.push(AppRoutes.merchantStoreSettings),
                    ),
                    // Discount codes: the store's own promotions (spec §27).
                    SabaTile(
                      icon: SabaIcons.ticket,
                      label: l10n.coupons,
                      subtitle: l10n.couponsTileHint,
                      tint: blue,
                      onTap: () => context.push(AppRoutes.merchantCoupons),
                    ),
                    SabaTile(
                      icon: SabaIcons.box,
                      label: l10n.inventory,
                      tint: amber,
                      onTap: () => context.push(AppRoutes.merchantInventory),
                    ),
                    SabaTile(
                      icon: SabaIcons.coin,
                      label: l10n.oweSaba,
                      tint: green,
                      onTap: () => context.push(AppRoutes.merchantPayouts),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                TileGroup(
                  title: l10n.accountGetHelp,
                  tiles: [
                    SabaTile(
                      icon: SabaIcons.bell,
                      label: l10n.notifications,
                      tint: purple,
                      onTap: () => context.push(AppRoutes.notifications),
                    ),
                    SabaTile(
                      icon: SabaIcons.message,
                      label: l10n.messages,
                      tint: blue,
                      trailing: unreadMessages > 0
                          ? Badge(label: Text('$unreadMessages'))
                          : null,
                      onTap: () => context.push(AppRoutes.conversations),
                    ),
                    SabaTile(
                      icon: SabaIcons.headset,
                      label: l10n.support,
                      tint: green,
                      onTap: () => context.push(AppRoutes.supportTickets),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                TileGroup(
                  title: l10n.accountSecurity,
                  tiles: [
                    SabaTile(
                      icon: SabaIcons.user,
                      label: l10n.myProfile,
                      tint: blue,
                      onTap: () => context.push(AppRoutes.profile),
                    ),
                    SabaTile(
                      icon: SabaIcons.globe,
                      label: l10n.settings,
                      tint: ink,
                      onTap: () => context.push(AppRoutes.settings),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                TileGroup(
                  title: l10n.aboutSaba,
                  tiles: [
                    SabaTile(
                      icon: SabaIcons.clipboard,
                      label: l10n.termsOfUse,
                      tint: blue,
                      onTap: () => context.push(
                        AppRoutes.legalPath(LegalPage.terms.slug),
                      ),
                    ),
                    SabaTile(
                      icon: SabaIcons.lock,
                      label: l10n.privacyPolicy,
                      tint: green,
                      onTap: () => context.push(
                        AppRoutes.legalPath(LegalPage.privacy.slug),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                AppButton(
                  label: l10n.signOut,
                  variant: AppButtonVariant.secondary,
                  icon: SabaIcons.signOut,
                  onPressed: () async {
                    final confirmed = await AppDialogs.confirm(
                      context,
                      title: l10n.signOutConfirmTitle,
                      message: l10n.signOutConfirmMessage,
                      confirmLabel: l10n.signOut,
                      isDestructive: true,
                    );
                    if (!confirmed) return;
                    await ref.read(authControllerProvider.notifier).signOut();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The dark card at the top, as on the dashboard: the page title, the store
/// - its logo, name, who is signed in and whether it is selling, tapping
/// through to its settings - and the storefront its customers see.
class _StoreHeader extends StatelessWidget {
  const _StoreHeader({required this.user, required this.store});

  final User user;
  final MerchantSummary? store;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final market = context.market;
    final store = this.store;
    final chevron = context.isRtl
        ? SabaIcons.chevronLeft
        : SabaIcons.chevronRight;

    return DarkHeaderCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.account,
            style: AppTypography.screenTitle(context, color: market.onDark),
          ),
          const SizedBox(height: AppSpacing.lg),
          InkWell(
            onTap: () => context.push(AppRoutes.merchantStoreSettings),
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  // Square, like the store tile on the dashboard: a store is
                  // not a person, so it does not get the round avatar.
                  Container(
                    width: 58,
                    height: 58,
                    alignment: Alignment.center,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: market.accent,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                    // Its own logo, or Saba's mark until it has one.
                    child: AppNetworkImage(
                      url: store?.logoUrl,
                      width: 58,
                      height: 58,
                      radius: AppRadius.card,
                      fallback: const SabaMark(size: 58),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          store?.storeName ?? user.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.titleMedium?.copyWith(
                            fontSize: 17,
                            color: market.onDark,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        // The phone, never the demo's sign-in email: v1 has
                        // no email (the tester).
                        Text(
                          Formatters.ltrIsolate(
                            IraqiPhone.display(user.phone ?? ''),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.bodySmall?.copyWith(
                            color: market.onDarkMuted,
                          ),
                        ),
                        if (store != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          _StoreStatusBadge(status: store.status),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: market.onDarkFill,
                      shape: BoxShape.circle,
                    ),
                    child: SabaIcon(
                      chevron,
                      size: AppSizes.iconSm,
                      color: market.onDark,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // The merchant could edit their shop from here and never look at
          // it. The storefront is the page their customers see, one tap from
          // the settings that change it.
          if (store != null) ...[
            const SizedBox(height: AppSpacing.lg),
            OnDarkRaisedCard(
              onTap: () => context.push(AppRoutes.storefrontPath(store.id)),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: market.info,
                      borderRadius: BorderRadius.circular(AppRadius.action),
                    ),
                    child: SabaIcon(
                      SabaIcons.eye,
                      size: AppSizes.iconMd,
                      color: market.onAccent,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.visitStore,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.titleSmall?.copyWith(
                            fontSize: 14.5,
                            color: market.onDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.visitStoreHint,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.labelSmall?.copyWith(
                            color: market.onDarkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  SabaIcon(
                    chevron,
                    size: AppSizes.iconSm,
                    color: market.onDarkMuted,
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

/// Whether the store is selling, in the app's status badge.
class _StoreStatusBadge extends StatelessWidget {
  const _StoreStatusBadge({required this.status});

  final MerchantStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final (label, tone) = switch (status) {
      MerchantStatus.approved => (l10n.statusApproved, StatusTone.positive),
      MerchantStatus.pending => (l10n.waitingForApproval, StatusTone.caution),
      MerchantStatus.rejected => (l10n.statusRejected, StatusTone.negative),
      MerchantStatus.suspended => (l10n.statusSuspended, StatusTone.negative),
      MerchantStatus.unknown => ('', StatusTone.neutral),
    };

    return StatusBadge(label: label, tone: tone, compact: true);
  }
}
