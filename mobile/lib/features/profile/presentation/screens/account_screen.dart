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
import '../../../../core/widgets/results_chrome.dart';
import '../../../../core/widgets/saba_tile.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../auth/domain/entities.dart';
import '../../../auth/presentation/auth_providers.dart';
import '../../../legal/legal_screen.dart';
import '../../../../core/widgets/saba_nav_bar.dart';
import '../../../../core/utils/iraqi_phone.dart';

/// The customer account hub.
///
/// Signed-out visitors can still reach this tab; they see a sign-in prompt
/// rather than a broken page, because browsing is public but account data is
/// not.
///
/// The rows are grouped into cards by what they are for — who you are, what
/// you follow, how you get in — instead of one long list split by dividers.
/// Eleven undifferentiated rows is a list nobody reads.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final market = context.market;
    final user = ref.watch(currentUserProvider);
    final unreadMessages = ref.watch(unreadMessageCountProvider);

    // A colour per row, so a row is found by its colour before its label is
    // read. Adjacent rows never share one. Each is the theme's ink on its own
    // soft fill, so both hold in dark mode.
    final blue = (market.info, market.infoSoft);
    final green = (market.success, market.successSoft);
    final purple = (market.accent, market.accentSoft);
    final ink = (context.colors.onSurface, market.surfaceMuted);

    if (user == null) {
      return Scaffold(
        body: Column(
          children: [
            PageTitle(title: l10n.account),
            Expanded(
              child: NoResultsView(
                icon: SabaIcons.user,
                title: l10n.guestTitle,
                message: l10n.guestMessage,
                actions: [
                  FilledButton(
                    onPressed: () => context.push(AppRoutes.login),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: Text(l10n.signIn),
                  ),
                  const LegalLinks(pages: LegalPage.values),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          WhiteHeader(child: _AccountHeader(user: user)),
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
                // No "Verify your email" card: v1 sends no email, so it led to
                // a screen that cannot work (the user, 2026-09-30).
                // Wishlist and Compare are here as well as beside the search
                // bar. Only there, they were an unlabelled heart and a button
                // that appears once two products are being compared - and
                // shoppers looking for "my wishlist" look in their account.
                TileGroup(
                  title: l10n.accountYou,
                  tiles: [
                    // No "My profile" row: the name at the top opens it,
                    // and two doors to one room on one screen is one too
                    // many.
                    SabaTile(
                      icon: SabaIcons.mapPin,
                      label: l10n.addresses,
                      tint: green,
                      onTap: () => context.push(AppRoutes.addresses),
                    ),
                    SabaTile(
                      icon: SabaIcons.heart,
                      label: l10n.wishlist,
                      tint: purple,
                      onTap: () => context.push(AppRoutes.wishlist),
                    ),
                    // Here, not under a heading of its own: "Security and
                    // settings" had come down to this one row (BUGS.md 86).
                    SabaTile(
                      icon: SabaIcons.globe,
                      label: l10n.settings,
                      tint: ink,
                      onTap: () => context.push(AppRoutes.settings),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                // Headed, because four unlabelled cards of identical rows
                // means reading all eleven to find one.
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
                    SabaTile(
                      icon: SabaIcons.refresh,
                      label: l10n.returnPolicy,
                      tint: purple,
                      onTap: () => context.push(
                        AppRoutes.legalPath(LegalPage.returns.slug),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                AppButton(
                  label: l10n.signOut,
                  variant: AppButtonVariant.secondary,
                  icon: SabaIcons.signOut,
                  onPressed: () => _signOut(context, ref),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.signOutConfirmTitle,
      message: l10n.signOutConfirmMessage,
      confirmLabel: l10n.signOut,
      isDestructive: true,
    );
    if (!confirmed) return;

    await ref.read(authControllerProvider.notifier).signOut();
  }
}

/// The dark card at the top, as on Home: the page title and who is signed in.
///
/// A shopper does not open a store from here. The specification has merchant
/// registration as its own sign-up (sections 5 and 21), not a customer
/// account turning into a store.
class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final market = context.market;
    final chevron = context.isRtl
        ? SabaIcons.chevronLeft
        : SabaIcons.chevronRight;
    final hasAvatar = user.avatarUrl != null && user.avatarUrl!.isNotEmpty;

    return DarkHeaderCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.account,
            style: AppTypography.screenTitle(context, color: market.onDark),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Who is signed in. Tappable, because a name and a face are where
          // a customer expects to start editing their details.
          InkWell(
            onTap: () => context.push(AppRoutes.profile),
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  if (hasAvatar)
                    AppCircleImage(
                      url: user.avatarUrl,
                      size: 58,
                      fallbackIcon: SabaIcons.user,
                    )
                  else
                    // Initials on the accent: a generic silhouette tells the
                    // customer nothing they do not already know.
                    Container(
                      width: 58,
                      height: 58,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: market.accent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: market.onDarkFill,
                          width: 3,
                          strokeAlign: BorderSide.strokeAlignOutside,
                        ),
                      ),
                      child: Text(
                        user.initials,
                        style: context.textStyles.titleLarge?.copyWith(
                          fontSize: 20,
                          color: market.onAccent,
                        ),
                      ),
                    ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.titleMedium?.copyWith(
                            fontSize: 17,
                            color: market.onDark,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        // No email in v1: the phone is the account. The demo
                        // accounts' sign-in emails showed here (the tester).
                        // Isolated left to right: in Arabic the leading plus
                        // is a neutral character and was carried to the far
                        // end, "9647701234567+".
                        if (user.phone != null)
                          Text(
                            Formatters.ltrIsolate(
                              IraqiPhone.display(user.phone!),
                            ),
                            style: context.textStyles.bodySmall?.copyWith(
                              color: market.onDarkMuted,
                            ),
                          ),
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
        ],
      ),
    );
  }
}
