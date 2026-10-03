// `Category` is also an annotation class in Flutter's foundation library; the
// catalog entity is the one meant here.
import 'package:flutter/foundation.dart' hide Category;

import '../../../core/location/governorate.dart';
import '../../catalog/domain/entities.dart';

/// What a home-page section renders.
///
/// The home page is assembled by administrators from the web panel, so the app
/// renders whatever sections the API sends, in the order it sends them
/// (specification sections 6 and 38). Adding a new section type is a backend
/// change plus one case here.
enum HomeSectionType {
  bannerCarousel,
  categoryGrid,
  productCarousel,
  productGrid,
  flashSale,
  merchantCarousel,
  brandCarousel,

  /// "Coupon promotions" (specification section 6): where on Home the
  /// customer's own coupons go. The section places them; the coupons
  /// endpoint fills it, because offers belong to an account and the home
  /// feed is the same for everybody.
  couponOffers,
  unknown;

  static HomeSectionType fromApi(Object? value) =>
      switch (value?.toString().toUpperCase()) {
        'BANNER' ||
        'BANNERS' ||
        'BANNER_CAROUSEL' => HomeSectionType.bannerCarousel,
        'CATEGORY' ||
        'CATEGORIES' ||
        'CATEGORY_GRID' => HomeSectionType.categoryGrid,
        'PRODUCT_CAROUSEL' || 'PRODUCTS' => HomeSectionType.productCarousel,
        'PRODUCT_GRID' => HomeSectionType.productGrid,
        'FLASH_SALE' || 'FLASH_SALES' => HomeSectionType.flashSale,
        'MERCHANT' ||
        'MERCHANTS' ||
        'FEATURED_MERCHANTS' => HomeSectionType.merchantCarousel,
        'BRAND' || 'BRANDS' => HomeSectionType.brandCarousel,
        'COUPON' ||
        'COUPONS' ||
        'COUPON_PROMOTIONS' => HomeSectionType.couponOffers,
        _ => HomeSectionType.unknown,
      };
}

/// Where tapping a banner should go.
@immutable
class BannerAction {
  const BannerAction({required this.type, this.value});

  final String type; // PRODUCT | CATEGORY | MERCHANT | SEARCH | URL | NONE
  final String? value;

  bool get isNavigable =>
      value != null && value!.isNotEmpty && type.toUpperCase() != 'NONE';
}

@immutable
class HomeBanner {
  const HomeBanner({
    required this.id,
    required this.imageUrl,
    this.title,
    this.subtitle,
    this.action,
  });

  final String id;
  final String imageUrl;
  final String? title;
  final String? subtitle;
  final BannerAction? action;
}

@immutable
class FeaturedMerchant {
  const FeaturedMerchant({
    required this.id,
    required this.storeName,
    this.logoUrl,
    this.bannerUrl,
    this.rating,
    this.productCount = 0,
    this.governorate,
  });

  final String id;
  final String storeName;
  final String? logoUrl;
  final String? bannerUrl;
  final double? rating;
  final int productCount;

  /// Where the store is, on its card.
  final Governorate? governorate;
}

/// One configured block of the home page.
@immutable
class HomeSection {
  const HomeSection({
    required this.id,
    required this.type,
    this.title,
    this.subtitle,
    this.products = const <ProductSummary>[],
    this.banners = const <HomeBanner>[],
    this.categories = const <Category>[],
    this.merchants = const <FeaturedMerchant>[],
    this.brands = const <Brand>[],
    this.endsAt,
    this.categoryId,
  });

  final String id;
  final HomeSectionType type;
  final String? title;
  final String? subtitle;
  final List<ProductSummary> products;
  final List<HomeBanner> banners;
  final List<Category> categories;
  final List<FeaturedMerchant> merchants;
  final List<Brand> brands;

  /// Countdown deadline for a flash-sale section.
  final DateTime? endsAt;

  /// Set when "see all" should open a filtered product list.
  final String? categoryId;

  /// A section with nothing in it is skipped rather than rendered empty.
  /// The coupon section never arrives with items - it is filled per account
  /// on the device, and hides itself when there is nothing to offer.
  bool get isEmpty =>
      type != HomeSectionType.couponOffers &&
      products.isEmpty &&
      banners.isEmpty &&
      categories.isEmpty &&
      merchants.isEmpty &&
      brands.isEmpty;
}
