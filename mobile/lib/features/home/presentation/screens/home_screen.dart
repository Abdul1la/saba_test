import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/providers/core_providers.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/widgets/saba_logo.dart';
import '../../../../core/widgets/shop_header.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/widgets/dark_header_card.dart';
import '../../../../core/widgets/skeletons.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../auth/presentation/auth_providers.dart';
import '../../../messaging/presentation/messaging_providers.dart';
import '../../../notifications/presentation/notifications_providers.dart';
import '../../domain/entities.dart';
import '../home_providers.dart';
import '../../../catalog/presentation/catalog_providers.dart';
import '../widgets/home_products.dart';
import '../widgets/home_sections.dart';
import '../../../../core/widgets/saba_nav_bar.dart';

/// The customer home page.
///
/// Holds no catalog knowledge of its own: it renders the sections an
/// administrator configured, in the order the API returns them.
///
/// The one arrangement decision it makes is that a banner section arriving
/// first is drawn *inside* the dark header card rather than below it, which is
/// how the design composes the top of the screen. Everything else is still a
/// plain stack of independent blocks, so any section can be absent and any
/// order works.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(homeFeedProvider);
    final user = ref.watch(currentUserProvider);

    final sections = feed.value ?? const <HomeSection>[];
    final leadBanner =
        sections.isNotEmpty &&
            sections.first.type == HomeSectionType.bannerCarousel
        ? sections.first
        : null;
    final rest = leadBanner == null ? sections : sections.skip(1).toList();

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            ref.refresh(homeFeedProvider.future),
            ref
                .read(
                  productListProvider(
                    ref.read(homeProductsQueryProvider),
                  ).notifier,
                )
                .refresh(),
          ]);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _HomeHeader(
                greetingName: _greetingName(user?.fullName),
                banner: leadBanner,
              ),
            ),
            SliverToBoxAdapter(
              child: ShopHeader(
                // The heart is not here: the wishlist is in Account and on
                // every product.
                showWishlist: false,
              ),
            ),
            ...feed.when(
              skipLoadingOnRefresh: true,
              // A language switch reads the feed again: keep what is on
              // screen until the new words arrive, instead of a skeleton.
              skipLoadingOnReload: true,
              data: (_) => _dataSlivers(context, rest),
              loading: () => const [SliverToBoxAdapter(child: _HomeSkeleton())],
              error: (error, _) => [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: AppErrorView(
                    failure: ErrorMapper.fromObject(error),
                    onRetry: () => ref.invalidate(homeFeedProvider),
                  ),
                ),
              ],
            ),
            // Clears the floating navigation bar, which is not part of the
            // layout and would otherwise cover the last row of content.
            SliverToBoxAdapter(
              child: SizedBox(height: SabaNavBar.clearance(context)),
            ),
          ],
        ),
      ),
    );
  }

  /// The sections, then every product: the grid says so itself when there
  /// is nothing to show.
  List<Widget> _dataSlivers(BuildContext context, List<HomeSection> sections) {
    return [
      SliverList.builder(
        itemCount: sections.length,
        itemBuilder: (context, index) =>
            HomeSectionView(section: sections[index]),
      ),
      const HomeAllProducts(),
    ];
  }
}

/// The card at the top, white on Home: who you are, then what is on offer.
class _HomeHeader extends ConsumerWidget {
  const _HomeHeader({this.greetingName, this.banner});

  final String? greetingName;
  final HomeSection? banner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final signedIn = greetingName != null && greetingName!.trim().isNotEmpty;

    return WhiteHeader(child: _card(context, ref, l10n, signedIn));
  }

  Widget _card(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    bool signedIn,
  ) {
    return DarkHeaderCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DarkHeaderGreeting(
            // "Hello", not "Welcome back": a brand-new account was greeted
            // as though it had been here before.
            label: signedIn ? l10n.hello : l10n.homeGreeting,
            name: signedIn ? greetingName! : l10n.appName,
            // The app's top bar carries its mark, and "Saba" signed out is
            // set as the logo sets it; a person's name, in Home's heading.
            leading: const SabaMark(size: AppSizes.iconCircle),
            nameStyle: signedIn
                ? AppTypography.heading(
                    context,
                    size: 22,
                    color: context.market.onDark,
                  )
                : SabaLogo.nameStyle(
                    context,
                    size: 24,
                    color: context.market.onDark,
                  ),
            shrinkToFit: true,
            // The heart used to sit here too, a few pixels above the one in
            // the search row - two identical controls going to the same place
            // on the same screen. The bell stays: notifications are not a
            // shopping tool, and this is where the app talks to you.
            actions: [
              // One tap between Arabic and English. Home's own content is
              // read again in the new language: see homeFeedProvider.
              DarkIconButton(
                icon: SabaIcons.globe,
                tooltip: l10n.changeLanguage,
                onPressed: () {
                  final isArabic =
                      Localizations.localeOf(context).languageCode == 'ar';
                  ref
                      .read(localeControllerProvider.notifier)
                      .setLocale(Locale(isArabic ? 'en' : 'ar'));
                },
              ),
              // The way to the stores the customer has written to, and the
              // dot when one has answered. It was four taps deep in Account.
              DarkIconButton(
                icon: SabaIcons.message,
                tooltip: l10n.messages,
                showDot: ref.watch(unreadMessageCountProvider) > 0,
                onPressed: () => context.push(AppRoutes.conversations),
              ),
              DarkIconButton(
                icon: SabaIcons.bell,
                tooltip: l10n.notifications,
                // Was hardcoded true, so the dot was lit for everyone for
                // ever — a badge that always says "there is something" says
                // nothing. The count provider already existed.
                showDot:
                    (ref.watch(unreadNotificationCountProvider).value ?? 0) > 0,
                onPressed: () => context.push(AppRoutes.notifications),
              ),
            ],
          ),
          if (banner != null && banner!.banners.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            HomePromoCarousel(section: banner!),
          ],
        ],
      ),
    );
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        SizedBox(height: AppSpacing.sectionGap),
        HorizontalSectionSkeleton(),
        SizedBox(height: AppSpacing.sectionGap),
        HorizontalSectionSkeleton(),
      ],
    );
  }
}

/// The name in the greeting: whole up to 24 letters, then cut with "…"
/// rather than shrunk. A 140-letter name was squeezed onto one line until it
/// could not be read; shorter ones still shrink a little to fit whole.
String? _greetingName(String? fullName) {
  final name = fullName?.trim() ?? '';
  if (name.isEmpty) return null;
  return name.length <= 24 ? name : '${name.substring(0, 23).trimRight()}…';
}
