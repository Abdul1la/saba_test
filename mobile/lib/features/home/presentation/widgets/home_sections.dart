import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../../core/widgets/dark_header_card.dart';
import '../../../../core/widgets/filter_chip_row.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/store_card.dart';
import '../../../cart/presentation/cart_providers.dart';
import '../../../cart/presentation/widgets/coupon_offers.dart';
import '../../../catalog/domain/entities.dart';
import '../../../catalog/presentation/widgets/connected_product_card.dart';
import '../../../catalog/presentation/widgets/product_card.dart';
import '../../domain/entities.dart';
import '../home_providers.dart';

/// Renders one configured home section, choosing the layout from its type.
class HomeSectionView extends StatelessWidget {
  const HomeSectionView({super.key, required this.section});

  final HomeSection section;

  @override
  Widget build(BuildContext context) {
    return switch (section.type) {
      HomeSectionType.bannerCarousel => _BannerStrip(section: section),
      HomeSectionType.categoryGrid => _CategoryCircles(section: section),
      HomeSectionType.flashSale => _FlashSaleSection(section: section),
      HomeSectionType.productCarousel => _ProductCarousel(section: section),
      HomeSectionType.productGrid => _ProductGrid(section: section),
      HomeSectionType.merchantCarousel => _MerchantCarousel(section: section),
      HomeSectionType.brandCarousel => _BrandCarousel(section: section),
      HomeSectionType.couponOffers => _CouponSection(section: section),
      HomeSectionType.unknown => const SizedBox.shrink(),
    };
  }
}

/// The customer's coupons, where the admin placed them on Home. Signed out,
/// or with nothing to offer, the section is not drawn at all.
class _CouponSection extends ConsumerWidget {
  const _CouponSection({required this.section});

  final HomeSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offers = ref.watch(availableCouponsProvider).value ?? const [];
    if (offers.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: section.title ?? context.l10n.couponsForYou,
          subtitle: section.subtitle,
        ),
        CouponOfferStrip(offers: offers),
      ],
    );
  }
}

/// Where a banner leads, or null when it leads nowhere.
///
/// One function answers both questions — whether to offer a tap at all, and
/// where to go on press — so the two can never disagree. They did: a banner
/// of type URL passed the old "is it navigable" check and so was given a tap,
/// but the switch that ran on press had no case for it and returned in
/// silence. The banner rippled under a finger and nothing happened.
String? _destinationOf(HomeBanner banner) {
  final action = banner.action;
  if (action == null || !action.isNavigable) return null;

  final value = action.value!;
  return switch (action.type.toUpperCase()) {
    'PRODUCT' => AppRoutes.productDetailPath(value),
    'CATEGORY' => AppRoutes.categoryProductsPath(value),
    'MERCHANT' || 'STORE' => AppRoutes.storefrontPath(value),
    'SEARCH' => '${AppRoutes.search}?q=$value',
    // External URLs are deliberately not opened from here: leaving the app
    // needs url_launcher and a product decision nobody has made yet. Until
    // then such a banner is a picture, and is drawn as one.
    _ => null,
  };
}

/// The tap for a banner, or null when it has no destination.
VoidCallback? _bannerTap(BuildContext context, HomeBanner banner) {
  final destination = _destinationOf(banner);
  return destination == null ? null : () => context.push(destination);
}

/// The banners at the top of Home, inside the dark header: photographs the
/// admin uploads, the offer printed in the picture itself (specification
/// section 6), sliding with page dots underneath.
///
/// A banner opens what Saba's admin linked it to: a product, a store or a
/// category (the admin's banners page, 2026-10-01). One with no link is a
/// picture, and tapping it does nothing. The words the admin gives it are
/// read out to a screen reader, and drawn only while there is no photograph
/// yet.
class HomePromoCarousel extends StatefulWidget {
  const HomePromoCarousel({super.key, required this.section});

  final HomeSection section;

  /// Wide, as a shop-front poster is: 2.4 times as wide as it is tall.
  static const double aspectRatio = 2.4;

  @override
  State<HomePromoCarousel> createState() => _HomePromoCarouselState();
}

class _HomePromoCarouselState extends State<HomePromoCarousel> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final banners = widget.section.banners;

    return Column(
      children: [
        AspectRatio(
          aspectRatio: HomePromoCarousel.aspectRatio,
          child: PageView.builder(
            controller: _controller,
            itemCount: banners.length,
            onPageChanged: (index) => setState(() => _page = index),
            itemBuilder: (context, index) =>
                _BannerPicture(banner: banners[index], index: index),
          ),
        ),
        if (banners.length > 1) ...[
          const SizedBox(height: AppSpacing.md),
          OnDarkPageDots(count: banners.length, index: _page),
        ],
      ],
    );
  }
}

class _BannerPicture extends StatelessWidget {
  const _BannerPicture({required this.banner, required this.index});

  final HomeBanner banner;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: banner.title,
      child: InkWell(
        onTap: _bannerTap(context, banner),
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: AppNetworkImage(
          url: banner.imageUrl,
          radius: AppRadius.card,
          fallback: _BannerFallback(banner: banner, index: index),
        ),
      ),
    );
  }
}

/// A banner with no photograph yet: its own colour and the admin's words,
/// so the demo - and a slow connection - shows an offer, not a grey box.
class _BannerFallback extends StatelessWidget {
  const _BannerFallback({required this.banner, required this.index});

  final HomeBanner banner;
  final int index;

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    final tones = [market.accent, market.info, market.success, market.warning];
    final tone = tones[index % tones.length];
    // Dark mode's tones are light, and white on them failed (3:1 on the
    // purple), so there the gradient starts a third darker: 4.7:1 or more.
    // White in both modes, like the words on a photo: the header this sits
    // in redefines "on dark" as navy.
    final shade = context.isDarkMode ? 0.35 : 0.0;
    const ink = AppPalette.textOnDark;

    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(AppSpacing.lg + 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            Color.lerp(tone, Colors.black, shade)!,
            Color.lerp(tone, Colors.black, shade + 0.35)!,
          ],
        ),
      ),
      child: Stack(
        children: [
          PositionedDirectional(
            end: -18,
            bottom: -22,
            child: SabaIcon(
              SabaIcons.bag,
              size: 120,
              color: ink.withValues(alpha: 0.16),
            ),
          ),
          // The words wrap across the full width as always, and shrink only
          // when they are taller than the banner: at the largest text size
          // on a small phone the title's second line was cut in half, and
          // the subtitle, held to one line, lost its end.
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) => FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: SizedBox(
                  width: constraints.maxWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (banner.subtitle case final subtitle?)
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.labelMedium?.copyWith(
                            color: ink.withValues(alpha: 0.85),
                          ),
                        ),
                      // Both are optional now (the admin's banners page).
                      if (banner.title case final title?) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.titleLarge?.copyWith(
                            fontSize: 22,
                            height: 1.15,
                            color: ink,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A banner section that is *not* first, and so did not go into the header.
class _BannerStrip extends StatelessWidget {
  const _BannerStrip({required this.section});

  final HomeSection section;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.sectionGap,
        AppSpacing.screenGutter,
        0,
      ),
      child: SizedBox(
        height: 150,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: section.banners.length,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
          itemBuilder: (context, index) {
            final banner = section.banners[index];
            return InkWell(
              onTap: _bannerTap(context, banner),
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: SizedBox(
                width: 280,
                child: AppNetworkImage(
                  url: banner.imageUrl,
                  radius: AppRadius.card,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Categories as round photographs with the name underneath, in two rows
/// that slide sideways together.
///
/// The admin chooses which categories are on Home and the photo each one
/// shows here. Until a photo is uploaded the category's icon stands in, on
/// a colour of its own. Tapping opens that category's products.
class _CategoryCircles extends StatelessWidget {
  const _CategoryCircles({required this.section});

  final HomeSection section;

  /// The circle, and the width a column is given when the rows scroll.
  static const double _circle = 72;
  static const double _scrollingColumn = 88;

  @override
  Widget build(BuildContext context) {
    final categories = section.categories;
    if (categories.isEmpty) return const SizedBox.shrink();

    // The first half across the top, the rest underneath.
    final columns = (categories.length + 1) ~/ 2;
    const gap = AppSpacing.sm;
    // Four columns or fewer spread over the width; more keep a fixed width
    // and scroll, with the next one showing at the edge.
    final available =
        MediaQuery.sizeOf(context).width - AppSpacing.screenGutter * 2;
    final width = columns <= 4
        ? (available - gap * (columns - 1)) / columns
        : _scrollingColumn;

    Widget row(int from, int to) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = from; index < to; index++) ...[
          if (index > from) const SizedBox(width: gap),
          SizedBox(
            width: width,
            child: _CategoryCircle(
              category: categories[index],
              index: index,
              size: _circle,
            ),
          ),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: section.title ?? context.l10n.categories,
          subtitle: section.subtitle,
          // Browse is a shell tab as well, and had the same push.
          onAction: () => context.go(AppRoutes.categories),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenGutter,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              row(0, columns),
              if (categories.length > columns) ...[
                const SizedBox(height: AppSpacing.md),
                row(columns, categories.length),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryCircle extends StatelessWidget {
  const _CategoryCircle({
    required this.category,
    required this.index,
    required this.size,
  });

  final Category category;
  final int index;
  final double size;

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    final tints = [
      (market.info, market.infoSoft),
      (market.success, market.successSoft),
      (market.accent, market.accentSoft),
      (market.warning, market.warningSoft),
    ];
    final (ink, fill) = tints[index % tints.length];

    return InkWell(
      onTap: () => context.push(AppRoutes.categoryProductsPath(category.id)),
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(
          children: [
            Container(
              width: size,
              height: size,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: market.surfaceMuted,
                border: Border.all(color: market.border),
              ),
              child: AppNetworkImage(
                url: category.imageUrl,
                radius: 0,
                fallback: ColoredBox(
                  color: fill,
                  child: Center(
                    child: SabaIcon(
                      iconForName(category.name, index),
                      size: size * 0.42,
                      color: ink,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            _WholeWords(
              category.name,
              style: context.textStyles.labelMedium!.copyWith(
                fontSize: 12.5,
                height: 1.25,
                fontWeight: FontWeight.w600,
                color: context.colors.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A horizontal rail of product cards, sized from the card itself so every
/// rail on every screen has the same rhythm.
class ProductRail extends StatelessWidget {
  const ProductRail({
    super.key,
    required this.products,
    this.flashSale = false,
  });

  final List<ProductSummary> products;

  /// A rail of [FlashSaleCard]s instead.
  final bool flashSale;

  @override
  Widget build(BuildContext context) {
    final width = flashSale
        ? AppSizes.flashSaleCardWidth
        : AppSizes.productCardRailWidth;

    return SizedBox(
      height: flashSale
          ? FlashSaleCard.heightFor(context, width)
          : ProductCard.heightFor(context, width),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // The product cards' shadows fall outside the rail; clipping them
        // left a hard edge under every card. The flash-sale card has none.
        clipBehavior: flashSale ? Clip.hardEdge : Clip.none,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenGutter,
        ),
        itemCount: products.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
        itemBuilder: (context, index) => ConnectedProductCard(
          product: products[index],
          width: width,
          flashSale: flashSale,
        ),
      ),
    );
  }
}

class _ProductCarousel extends StatelessWidget {
  const _ProductCarousel({required this.section});

  final HomeSection section;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: section.title ?? '',
          subtitle: section.subtitle,
          onAction: section.categoryId == null
              ? null
              : () => context.push(
                  AppRoutes.categoryProductsPath(section.categoryId!),
                ),
        ),
        ProductRail(products: section.products),
      ],
    );
  }
}

class _ProductGrid extends StatelessWidget {
  const _ProductGrid({required this.section});

  final HomeSection section;

  @override
  Widget build(BuildContext context) {
    final columns = context.productGridColumns;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: section.title ?? '', subtitle: section.subtitle),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenGutter,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth =
                  (constraints.maxWidth - AppSpacing.md * (columns - 1)) /
                  columns;

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: AppSpacing.md,
                  mainAxisSpacing: AppSpacing.md,
                  // Every card is the same height, so the rows stay level.
                  mainAxisExtent: ProductCard.heightFor(context, cardWidth),
                ),
                itemCount: section.products.length,
                itemBuilder: (context, index) =>
                    ConnectedProductCard(product: section.products[index]),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Flash sale rail with a live countdown to the soonest sale's end.
///
/// The deadline comes from the server; the timer re-renders the label, and
/// at zero asks for Home again, which comes back without the sale that
/// ended and counting down to the next. Whether a sale price still applies
/// is decided by the backend at checkout.
class _FlashSaleSection extends ConsumerStatefulWidget {
  const _FlashSaleSection({required this.section});

  final HomeSection section;

  @override
  ConsumerState<_FlashSaleSection> createState() => _FlashSaleSectionState();
}

class _FlashSaleSectionState extends ConsumerState<_FlashSaleSection> {
  Timer? _timer;
  Duration _remaining = Duration.zero;

  /// The end Home was last asked for again at, so it is asked once.
  DateTime? _renewedFor;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _tick();
      _renewAtZero();
    });
  }

  /// The soonest sale is over: Home again, once, without it. From the
  /// timer only, never while building.
  void _renewAtZero() {
    final endsAt = widget.section.endsAt;
    if (endsAt == null || _remaining > Duration.zero) return;
    if (_renewedFor == endsAt) return;
    _renewedFor = endsAt;
    ref.invalidate(homeFeedProvider);
  }

  void _tick() {
    final endsAt = widget.section.endsAt;
    if (endsAt == null) return;
    final remaining = endsAt.difference(DateTime.now());
    if (!mounted) return;
    setState(
      () => _remaining = remaining.isNegative ? Duration.zero : remaining,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    // Every city's sales: the city chips filter the grid of every product
    // only (the user), and sit above it.
    final products = section.products;
    if (products.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: section.title ?? context.l10n.flashSales,
          subtitle: section.subtitle,
          badge: section.endsAt == null
              ? null
              : _CountdownBadge(remaining: _remaining),
          onAction: section.categoryId == null
              ? null
              : () => context.push(
                  AppRoutes.categoryProductsPath(section.categoryId!),
                ),
        ),
        ProductRail(products: products, flashSale: true),
      ],
    );
  }
}

/// `02:14:09` — the time left, in the amber badge beside the section title.
class _CountdownBadge extends StatelessWidget {
  const _CountdownBadge({required this.remaining});

  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: context.market.heat,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SabaIcon(SabaIcons.clock, size: 13, color: context.market.onHeat),
          const SizedBox(width: AppSpacing.xs + 1),
          Text(
            Formatters.countdown(remaining),
            style: context.textStyles.labelMedium?.copyWith(
              color: context.market.onHeat,
              fontSize: 11.5,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _MerchantCarousel extends StatelessWidget {
  const _MerchantCarousel({required this.section});

  final HomeSection section;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: section.title ?? context.l10n.featuredMerchants,
          subtitle: section.subtitle,
        ),
        SizedBox(
          // The card's own height, which grows with the reader's text size.
          height: StoreCard.heightFor(context),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            // The cards' shadows fall outside the rail; clipping them left a
            // hard edge under every card.
            clipBehavior: Clip.none,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenGutter,
            ),
            itemCount: section.merchants.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, index) {
              final merchant = section.merchants[index];
              return StoreCard(
                width: StoreCard.railWidth,
                name: merchant.storeName,
                logoUrl: merchant.logoUrl,
                rating: merchant.rating,
                city: merchant.governorate,
                onTap: () =>
                    context.push(AppRoutes.storefrontPath(merchant.id)),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _BrandCarousel extends StatelessWidget {
  const _BrandCarousel({required this.section});

  final HomeSection section;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: section.title ?? context.l10n.popularBrands,
          subtitle: section.subtitle,
        ),
        SizedBox(
          height: 104,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenGutter,
            ),
            itemCount: section.brands.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, index) {
              final brand = section.brands[index];
              return SizedBox(
                width: 120,
                child: Material(
                  color: context.colors.surface,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    side: BorderSide(color: context.market.border),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: AppNetworkImage(
                            url: brand.logoUrl,
                            fit: BoxFit.contain,
                            fallbackIcon: SabaIcons.ticket,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          brand.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.labelMedium?.copyWith(
                            fontSize: 11.5,
                            color: context.colors.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Up to two centred lines that never break inside a word: when the longest
/// word is wider than the column, the words shrink until it fits. At 320 px
/// and the largest text, "Headphones" came out "Headph / ones" (the tester).
class _WholeWords extends StatelessWidget {
  const _WholeWords(this.text, {required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final scaler = MediaQuery.textScalerOf(context);
        var longest = 0.0;
        for (final word in text.split(' ')) {
          final painter = TextPainter(
            text: TextSpan(text: word, style: style),
            textScaler: scaler,
            textDirection: Directionality.of(context),
            maxLines: 1,
          )..layout();
          longest = math.max(longest, painter.width);
          painter.dispose();
        }
        // A little under the width: the scaler is not quite linear.
        final shrink = longest > box.maxWidth
            ? box.maxWidth / longest * 0.95
            : 1.0;
        return Text(
          text,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: style.copyWith(fontSize: style.fontSize! * shrink),
        );
      },
    );
  }
}
