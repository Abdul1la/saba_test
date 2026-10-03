import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/location/governorate.dart';
import '../../../../core/location/governorate_picker.dart';
import '../../../../core/location/store_delivery.dart';

import '../../../messaging/presentation/widgets/message_store_button.dart';
import '../../../reviews/presentation/widgets/report_dialog.dart';
import '../../../../core/config/api_endpoints.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/core_providers.dart';
import '../../../../core/providers/paged_state.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/json_reader.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/paged_list_view.dart';
import '../../../../core/widgets/rating_stars.dart';
import '../../../../core/widgets/results_chrome.dart';
import '../../../../core/widgets/saba_tile.dart';
import '../../../../core/widgets/search_pill.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/skeletons.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../addresses/presentation/address_providers.dart';
import '../../../merchant/presentation/merchant_providers.dart';
import '../../../merchant/presentation/widgets/store_preview_bar.dart';
import '../../../cart/domain/entities.dart' show CouponOffer;
import '../../../cart/presentation/cart_providers.dart';
import '../../../cart/presentation/widgets/coupon_offers.dart';
import '../../domain/entities.dart';
import '../../domain/product_query.dart';
import '../catalog_providers.dart';
import '../widgets/connected_product_card.dart';
import '../widgets/product_card.dart';
import '../../../../core/utils/western_digits_formatter.dart';
import '../../../../core/widgets/saba_logo.dart';

/// A merchant's public storefront (specification section 22).
class MerchantStore {
  const MerchantStore({
    required this.id,
    required this.storeName,
    this.description,
    this.logoUrl,
    this.bannerUrl,
    this.rating = 0,
    this.reviewCount = 0,
    this.productCount = 0,
    this.isOpen = true,
    this.returnPolicy,
    this.governorate,
    this.address,
    this.delivery,
  });

  final String id;
  final String storeName;
  final String? description;
  final String? logoUrl;
  final String? bannerUrl;
  final double rating;
  final int reviewCount;
  final int productCount;
  final bool isOpen;
  final String? returnPolicy;

  /// Where the store is; every store has one.
  final Governorate? governorate;

  /// Its street address, when the store gave one.
  final String? address;

  /// Where it delivers and what it asks.
  final StoreDelivery? delivery;
}

final merchantStoreProvider = FutureProvider.family<MerchantStore, String>((
  ref,
  id,
) async {
  final client = ref.watch(apiClientProvider);
  final result = await client.get<MerchantStore>(
    ApiEndpoints.merchantStore(id),
    decoder: (envelope) {
      final json = envelope.dataAsMap;
      return MerchantStore(
        id: Json.str(json, const ['id', 'merchantId'], fallback: id),
        storeName: Json.str(json, const ['storeName', 'name', 'businessName']),
        description: Json.strOrNull(json, const ['description', 'about']),
        logoUrl: Json.strOrNull(json, const ['logoUrl', 'logo']),
        bannerUrl: Json.strOrNull(json, const ['bannerUrl', 'banner']),
        rating: Json.decimal(json, const ['rating', 'averageRating']),
        reviewCount: Json.integer(json, const ['reviewCount', 'reviewsCount']),
        productCount: Json.integer(json, const ['productCount']),
        returnPolicy: Json.strOrNull(json, const ['returnPolicy']),
        governorate: Governorate.fromApi(json['governorate'] ?? json['city']),
        address: Json.strOrNull(json, const ['businessAddress', 'address']),
        delivery: StoreDelivery.fromJson(json['delivery']),
        isOpen: Json.boolean(json, const ['isOpen'], fallback: true),
      );
    },
  );
  return result.unwrap();
});

/// The shop as a customer sees it: the banner, who they are, then the shelves.
class StorefrontScreen extends ConsumerStatefulWidget {
  const StorefrontScreen({super.key, required this.merchantId});

  final String merchantId;

  @override
  ConsumerState<StorefrontScreen> createState() => _StorefrontScreenState();
}

class _StorefrontScreenState extends ConsumerState<StorefrontScreen> {
  /// Empty means the whole shop. Held here because it is part of the query
  /// the grid is built from.
  String _search = '';

  /// The shelves already on screen.
  ///
  /// Every search term makes a different provider, and a provider that has
  /// never run has no value — so without this the body fell back to its
  /// skeleton on the first keystroke, taking the search field down with it
  /// and closing the keyboard. Holding the last good page keeps the screen
  /// standing while the next one is fetched, which is also what a shopper
  /// expects: the old results stay until the new ones are ready.
  PagedState<ProductSummary>? _shelves;

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(merchantStoreProvider(widget.merchantId));
    final isPreview = ref.watch(isMyStoreProvider(widget.merchantId));
    // The owner's products Saba has not approved yet: on their shelf, not
    // in their shop. Only the owner asks.
    final waiting = isPreview
        ? (ref.watch(merchantProductCountsProvider).value?['waiting'] ?? 0)
        : 0;
    final query = ProductQuery(
      merchantId: widget.merchantId,
      search: _search.isEmpty ? null : _search,
    );
    final products = ref.watch(productListProvider(query));
    final notifier = ref.read(productListProvider(query).notifier);
    final columns = context.productGridColumns;

    if (products.hasValue) _shelves = products.value;
    final shelves = _shelves;

    return Scaffold(
      // The owner's own shop opens with a band saying so, above everything.
      appBar: isPreview
          ? const PreferredSize(
              preferredSize: Size.fromHeight(56),
              child: StorePreviewBar(),
            )
          : null,
      body: AsyncStateView<MerchantStore>(
        value: store,
        onRetry: () => ref.invalidate(merchantStoreProvider(widget.merchantId)),
        builder: (value) => AsyncStateView<PagedState<ProductSummary>>(
          // Only ever "loading" before the first page of all: after that the
          // previous one is handed straight back, so the header is never
          // torn down mid-search.
          value: shelves == null
              ? products
              : AsyncValue<PagedState<ProductSummary>>.data(shelves),
          onRetry: () => ref.invalidate(productListProvider(query)),
          loadingBuilder: (_) => const ProductGridSkeleton(),
          builder: (paged) => LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth =
                  (constraints.maxWidth -
                      AppSpacing.screenGutter * 2 -
                      AppSpacing.md * (columns - 1)) /
                  columns;

              return PagedListView<ProductSummary>(
                state: paged,
                // A product grid keeps its place when a product is closed.
                reloadOnReturn: false,
                onLoadMore: notifier.loadMore,
                onRefresh: notifier.refresh,
                onRetryLoadMore: notifier.retryLoadMore,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenGutter,
                  0,
                  AppSpacing.screenGutter,
                  AppSpacing.xxl,
                ),
                header: _StoreHeader(
                  store: value,
                  isPreview: isPreview,
                  onReviews: () => context.push(
                    AppRoutes.merchantReviewsPath(widget.merchantId),
                  ),
                  onSearch: (term) => setState(() => _search = term),
                  onReport: () => reportToSaba(
                    context,
                    ref,
                    target: ReportTarget.store,
                    id: widget.merchantId,
                  ),
                ),
                // The card reports the height it needs; this grid used to
                // guess with childAspectRatio: 0.6, which cannot know the
                // text scale the reader has set.
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: AppSpacing.md,
                  mainAxisSpacing: AppSpacing.md,
                  mainAxisExtent: ProductCard.heightFor(context, cardWidth),
                ),
                // A shop with nothing listed and a search that matched
                // nothing are different facts, and saying the first when the
                // second is true blames the shop for the customer's word.
                emptyState: _search.isEmpty && waiting > 0
                    // The owner's shop is empty because Saba has not said
                    // yes yet, not because nothing is on its shelf.
                    ? NoResultsView(
                        icon: SabaIcons.clock,
                        title: context.l10n.waitingForApproval,
                        message: context.l10n.previewWaitingMessage,
                      )
                    : _search.isEmpty
                    ? NoResultsView(
                        icon: SabaIcons.store,
                        title: context.l10n.emptyProducts,
                        message: context.l10n.emptyProductsMessage,
                      )
                    : NoResultsView(
                        icon: SabaIcons.search,
                        title: context.l10n.noResultsInStore,
                        message: context.l10n.noResultsInStoreMessage,
                      ),
                itemBuilder: (context, product, _) =>
                    ConnectedProductCard(product: product),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Banner, identity, policies — everything above the shelves.
class _StoreHeader extends StatelessWidget {
  const _StoreHeader({
    required this.store,
    required this.isPreview,
    required this.onReviews,
    required this.onSearch,
    required this.onReport,
  });

  final MerchantStore store;

  /// Reports the store to Saba (Apple 1.2).
  final VoidCallback onReport;

  /// The owner looking at their own shop: no coupons to claim, nobody to
  /// message.
  final bool isPreview;
  final VoidCallback onReviews;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final market = context.market;
    // "Basra · Corniche Street, Al-Ashar": the city always, the street when
    // the store gave one.
    final place = [
      store.governorate?.label(context),
      store.address,
    ].where((part) => part != null && part.isNotEmpty).join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The shop sign, inside the gutter like every other card. The back
        // circle rides on top of it, because the banner is the whole top of
        // the screen and an app bar above it would be a second header.
        Stack(
          children: [
            AppNetworkImage(
              url: store.bannerUrl,
              width: double.infinity,
              height: 150,
              radius: AppRadius.card,
              // A store with no picture of its own: Saba's mark.
              fallback: Container(
                height: 150,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.market.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: const SabaMark(size: 56),
              ),
            ),
            PositionedDirectional(
              top: MediaQuery.paddingOf(context).top + AppSpacing.sm,
              start: AppSpacing.sm,
              child: CircleIconButton(
                icon: context.isRtl
                    ? SabaIcons.chevronRight
                    : SabaIcons.chevronLeft,
                tooltip: l10n.back,
                filled: true,
                onPressed: () => context.popOrGo(),
              ),
            ),
            // The store's coupons as a sticker on its sign: the first product
            // has to show without scrolling, and a strip of coupon cards
            // pushed it off the bottom of the screen.
            if (!isPreview)
              PositionedDirectional(
                start: AppSpacing.sm,
                bottom: AppSpacing.sm,
                end: AppSpacing.sm,
                child: Align(
                  alignment: AlignmentDirectional.bottomStart,
                  child: _StoreCoupons(store: store),
                ),
              ),
            // Message sits up here rather than beside the store's name,
            // where it squeezed the rating off the card.
            if (!isPreview)
              PositionedDirectional(
                top: MediaQuery.paddingOf(context).top + AppSpacing.sm,
                end: AppSpacing.sm,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleIconButton(
                      icon: SabaIcons.flag,
                      tooltip: l10n.reportStore,
                      filled: true,
                      onPressed: onReport,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    MessageStoreButton(
                      merchantId: store.id,
                      variant: AppButtonVariant.secondary,
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md + 2),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppCircleImage(
                    url: store.logoUrl,
                    size: 56,
                    fallback: const SabaMark(size: 56),
                  ),
                  const SizedBox(width: AppSpacing.md + 2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          store.storeName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.nameTitle(context),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        if (store.reviewCount > 0)
                          RatingStars(
                            rating: store.rating,
                            reviewCount: store.reviewCount,
                            size: 13,
                          ),
                        if (place.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xxs - 1),
                          Row(
                            children: [
                              SabaIcon(
                                SabaIcons.mapPin,
                                size: 12,
                                color: market.textMuted,
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Flexible(
                                child: Text(
                                  place,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.textStyles.labelSmall,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (!store.isOpen)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: StatusBadge(
                    label: context.l10n.storeClosedNow,
                    tone: StatusTone.negative,
                  ),
                ),
              if (store.delivery case final delivery?)
                Consumer(
                  builder: (context, ref, _) =>
                      switch (ref.watch(deliveryCityProvider)) {
                        null => const SizedBox.shrink(),
                        final city => Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.md),
                          child: StoreDeliveryLine(
                            delivery: delivery,
                            storeCity: store.governorate,
                            shopperCity: city,
                          ),
                        ),
                      },
                ),
              if (store.description != null &&
                  store.description!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md + 2),
                Text(
                  store.description!,
                  // A chatty shop should not be able to push its own shelves
                  // off the bottom of the screen.
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.bodySmall?.copyWith(height: 1.5),
                ),
              ],
            ],
          ),
        ),
        // What to know before buying here, in one card instead of two.
        // Reviews used to sit in a second bordered box directly underneath,
        // holding a single row.
        const SizedBox(height: AppSpacing.md + 2),
        SectionCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Saba's rule, the same at every store.
                    _Policy(
                      icon: SabaIcons.refresh,
                      label: l10n.returnPolicy,
                      value: l10n.returnRuleShort,
                    ),
                  ],
                ),
              ),
              // A full row rather than the rating beside the shop name made
              // tappable: a rating is eighteen points tall, and a control has
              // to be reachable by a thumb.
              SabaTile(
                icon: SabaIcons.star,
                label: l10n.storeReviews,
                subtitle: store.reviewCount > 0
                    ? '${store.rating.toStringAsFixed(1)} '
                          '(${store.reviewCount})'
                    : null,
                onTap: onReviews,
              ),
            ],
          ),
        ),
        // In place of a "Products" heading, which named what was
        // obviously underneath it and cost the same height. A shop with two
        // hundred things needed a way in that was not scrolling.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            0,
            AppSpacing.xl,
            0,
            AppSpacing.md,
          ),
          child: _StoreSearch(onChanged: onSearch),
        ),
      ],
    );
  }
}

/// The store's running coupons, as one sticker on its banner: the first
/// code and what it takes off, and how many more. A tap opens them all, each
/// with its Copy button.
class _StoreCoupons extends ConsumerWidget {
  const _StoreCoupons({required this.store});

  final MerchantStore store;

  void _showAll(BuildContext context, List<CouponOffer> offers) {
    AppDialogs.bottomSheet<void>(
      context,
      isScrollControlled: false,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            0,
            AppSpacing.sm,
            0,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenGutter,
                ),
                child: Text(
                  sheetContext.l10n.couponsFrom(store.storeName),
                  style: AppTypography.subsectionTitle(sheetContext),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              CouponOfferStrip(offers: offers, withStore: false),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offers =
        ref.watch(storeCouponsProvider(store.id)).value ??
        const <CouponOffer>[];
    if (offers.isEmpty) return const SizedBox.shrink();
    final first = offers.first;
    final more = offers.length - 1;

    final ink = context.market.onAccent;

    return Tooltip(
      message: context.l10n.couponsFrom(store.storeName),
      child: Material(
        color: context.market.accent,
        shape: const StadiumBorder(),
        elevation: 2,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => _showAll(context, offers),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm - 1,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SabaIcon(SabaIcons.ticket, size: 16, color: ink),
                const SizedBox(width: AppSpacing.sm - 2),
                Flexible(
                  child: Text(
                    '${first.code} · ${first.title(context)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.labelLarge?.copyWith(
                      color: ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (more > 0) ...[
                  const SizedBox(width: AppSpacing.sm - 2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm - 2,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: ink.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      '+$more',
                      style: context.textStyles.labelSmall?.copyWith(
                        color: ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Policy extends StatelessWidget {
  const _Policy({required this.icon, required this.label, required this.value});

  final String icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SabaIcon(icon, size: AppSizes.iconMd, color: context.market.textMuted),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: context.textStyles.labelMedium?.copyWith(fontSize: 12.5),
              ),
              const SizedBox(height: AppSpacing.xxs - 1),
              Text(
                value,
                style: context.textStyles.bodySmall?.copyWith(height: 1.45),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Search, scoped to one shop.
///
/// Its own widget because it owns a controller and a timer: the header around
/// it is rebuilt on every state change, and a field whose controller is
/// rebuilt with it loses what was typed.
class _StoreSearch extends StatefulWidget {
  const _StoreSearch({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  State<_StoreSearch> createState() => _StoreSearchState();
}

class _StoreSearchState extends State<_StoreSearch> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    // One request per pause rather than one per keystroke, at the delay the
    // search screen already uses.
    _debounce = Timer(
      AppConstants.searchDebounce,
      () => widget.onChanged(value.trim()),
    );
    setState(() {});
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    widget.onChanged('');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final market = context.market;

    return Container(
      height: AppSizes.buttonHeight,
      padding: const EdgeInsetsDirectional.only(
        start: AppSpacing.lg,
        end: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: market.border),
      ),
      child: Row(
        children: [
          SabaIcon(
            SabaIcons.search,
            size: AppSizes.iconSm,
            color: context.colors.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: TextField(
              controller: _controller,
              inputFormatters: const [WesternDigitsFormatter()],
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              style: context.textStyles.bodyMedium?.copyWith(fontSize: 13.5),
              decoration: InputDecoration(
                hintText: l10n.searchInStore,
                filled: false,
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          // Only once there is something to clear, so the row is not a
          // permanent offer to undo nothing.
          if (_controller.text.isNotEmpty)
            CircleIconButton(
              icon: SabaIcons.close,
              tooltip: l10n.clear,
              size: AppSizes.iconCircle - 8,
              onPressed: _clear,
            ),
        ],
      ),
    );
  }
}
