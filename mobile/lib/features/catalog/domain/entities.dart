import 'package:flutter/foundation.dart';

import '../../../core/location/governorate.dart';
import '../../../core/location/store_delivery.dart';

/// A catalog category.
///
/// Categories are created by administrators at runtime and are never hard-coded
/// in the app (specification section 7). The app renders whatever tree the API
/// returns, to any depth.
@immutable
class Category {
  const Category({
    required this.id,
    required this.name,
    this.slug,
    this.imageUrl,
    this.bannerUrl,
    this.parentId,
    this.productCount = 0,
    this.children = const <Category>[],
  });

  final String id;
  final String name;
  final String? slug;
  final String? imageUrl;
  final String? bannerUrl;
  final String? parentId;
  final int productCount;
  final List<Category> children;

  bool get hasChildren => children.isNotEmpty;
  bool get isRoot => parentId == null || parentId!.isEmpty;
}

@immutable
class Brand {
  const Brand({
    required this.id,
    required this.name,
    this.nameAr,
    this.logoUrl,
    this.productCount = 0,
  });

  final String id;
  final String name;

  /// The Arabic name Saba set, when it set one; only the store's product
  /// form is sent it (the shop's lists come in the reader's language).
  final String? nameAr;
  final String? logoUrl;
  final int productCount;

  /// The name to show a reader of [languageCode].
  String nameIn(String languageCode) =>
      languageCode == 'ar' ? (nameAr ?? name) : name;
}

/// A category-scoped attribute definition, used to build dynamic filters and
/// the merchant's product form (specification section 9).
@immutable
class AttributeDefinition {
  const AttributeDefinition({
    required this.id,
    required this.name,
    required this.type,
    this.unit,
    this.isRequired = false,
    this.isFilterable = false,
    this.isVariantOption = false,
    this.values = const <AttributeOption>[],
  });

  final String id;
  final String name;
  final String type; // TEXT | NUMBER | BOOLEAN | SELECT | MULTI_SELECT
  final String? unit;
  final bool isRequired;
  final bool isFilterable;

  /// True when this attribute distinguishes variants, such as Color or Storage.
  final bool isVariantOption;

  final List<AttributeOption> values;
}

@immutable
class AttributeOption {
  const AttributeOption({required this.id, required this.value, this.label});

  final String id;
  final String value;
  final String? label;

  String get display => label ?? value;
}

@immutable
class ProductMedia {
  const ProductMedia({
    required this.id,
    required this.url,
    this.thumbnailUrl,
    this.isPrimary = false,
  });

  final String id;
  final String url;
  final String? thumbnailUrl;
  final bool isPrimary;
}

enum StockStatus {
  inStock,
  lowStock,
  outOfStock,
  unknown;

  static StockStatus fromApi(Object? value, {int? quantity, int? threshold}) {
    final token = value?.toString().toUpperCase();
    return switch (token) {
      'IN_STOCK' => StockStatus.inStock,
      'LOW_STOCK' => StockStatus.lowStock,
      'OUT_OF_STOCK' => StockStatus.outOfStock,
      _ when quantity != null => switch (quantity) {
        <= 0 => StockStatus.outOfStock,
        _ when threshold != null && quantity <= threshold =>
          StockStatus.lowStock,
        _ => StockStatus.inStock,
      },
      _ => StockStatus.unknown,
    };
  }

  bool get isPurchasable =>
      this == StockStatus.inStock || this == StockStatus.lowStock;
}

/// A purchasable configuration of a product: a specific colour, size, storage
/// and so on (specification section 10).
@immutable
class ProductVariant {
  const ProductVariant({
    required this.id,
    required this.price,
    required this.stockStatus,
    this.sku,
    this.barcode,
    this.originalPrice,
    this.discountPercentage,
    this.availableQuantity,
    this.imageUrl,
    this.weight,
    this.dimensions,
    this.options = const <String, String>{},
  });

  final String id;
  final num price;
  final StockStatus stockStatus;
  final String? sku;
  final String? barcode;
  final num? originalPrice;
  final num? discountPercentage;

  /// What the server says is available right now. Advisory only — the real
  /// check happens inside the checkout transaction (section 17).
  final int? availableQuantity;

  final String? imageUrl;
  final num? weight;
  final String? dimensions;

  /// Option name to value, for example `{'Color': 'Black', 'Storage': '256GB'}`.
  final Map<String, String> options;

  bool get isAvailable => stockStatus.isPurchasable;
  bool get isDiscounted => originalPrice != null && originalPrice! > price;
}

/// The store that sells a product.
@immutable
class ProductMerchant {
  const ProductMerchant({
    required this.id,
    required this.storeName,
    this.logoUrl,
    this.rating,
    this.reviewCount = 0,
    this.governorate,
    this.delivery,
    this.isOpen = true,
  });

  final String id;
  final String storeName;
  final String? logoUrl;
  final double? rating;
  final int reviewCount;

  /// False while its owner has it closed: nothing can be bought from it.
  final bool isOpen;

  /// Where the store is.
  final Governorate? governorate;

  /// Where it delivers and what it asks; on the product page only.
  final StoreDelivery? delivery;
}

/// The lightweight shape used by grids, carousels and search results.
@immutable
class ProductSummary {
  const ProductSummary({
    required this.id,
    required this.name,
    required this.price,
    required this.currencyCode,
    required this.stockStatus,
    this.imageUrl,
    this.originalPrice,
    this.discountPercentage,
    this.merchantId,
    this.merchantName,
    this.merchantCity,
    this.brandName,
    this.isWishlisted = false,
    this.isFlashSale = false,
    this.flashSaleEndsAt,
    this.hasOptions = false,
    this.deliveryAvailable = false,
  });

  final String id;
  final String name;
  final num price;
  final String currencyCode;
  final StockStatus stockStatus;
  final String? imageUrl;
  final num? originalPrice;
  final num? discountPercentage;
  final String? merchantId;
  final String? merchantName;

  /// Where its store is; every product is where its store is.
  final Governorate? merchantCity;
  final String? brandName;
  final bool isWishlisted;
  final bool isFlashSale;
  final DateTime? flashSaleEndsAt;

  /// Sold in options - colour, size - that have to be chosen before it can
  /// go in the cart, which a card cannot do.
  final bool hasOptions;

  /// Its store delivers to the shopper's governorate. False when that is not
  /// known - signed out, or no city chosen - rather than a guess.
  final bool deliveryAvailable;

  bool get isDiscounted => originalPrice != null && originalPrice! > price;
  bool get isAvailable => stockStatus.isPurchasable;

  ProductSummary copyWith({bool? isWishlisted}) => ProductSummary(
    id: id,
    name: name,
    price: price,
    currencyCode: currencyCode,
    stockStatus: stockStatus,
    imageUrl: imageUrl,
    originalPrice: originalPrice,
    discountPercentage: discountPercentage,
    merchantId: merchantId,
    merchantName: merchantName,
    merchantCity: merchantCity,
    brandName: brandName,
    isWishlisted: isWishlisted ?? this.isWishlisted,
    isFlashSale: isFlashSale,
    flashSaleEndsAt: flashSaleEndsAt,
    hasOptions: hasOptions,
    deliveryAvailable: deliveryAvailable,
  );
}

/// Everything the product detail screen needs.
@immutable
class Product {
  const Product({
    required this.id,
    required this.name,
    this.nameEn,
    this.nameAr,
    required this.price,
    required this.currencyCode,
    required this.stockStatus,
    this.description,
    this.media = const <ProductMedia>[],
    this.originalPrice,
    this.discountPercentage,
    this.sku,
    this.barcode,
    this.brand,
    this.categoryId,
    this.categoryName,
    this.merchant,
    this.variantOptions = const <String, List<String>>{},
    this.optionColours = const <String, String>{},
    this.variants = const <ProductVariant>[],
    this.sizeGuide,
    this.warranty,
    this.returnPolicy,
    this.availableQuantity,
    this.isWishlisted = false,
    this.isListed = true,
  });

  final String id;
  final String name;

  /// The names its store typed, for the edit form; [name] is the one to
  /// show, in the shopper's language.
  final String? nameEn;
  final String? nameAr;

  final num price;
  final String currencyCode;
  final StockStatus stockStatus;
  final String? description;
  final List<ProductMedia> media;
  final num? originalPrice;
  final num? discountPercentage;
  final String? sku;
  final String? barcode;
  final Brand? brand;
  final String? categoryId;
  final String? categoryName;
  final ProductMerchant? merchant;

  /// Option name to the values offered, in display order.
  final Map<String, List<String>> variantOptions;

  /// Option value to a colour, as `#RRGGBB`, for options that are colours.
  ///
  /// The design draws colour options as swatches rather than as words, which
  /// needs an actual colour and not just the name of one. A value missing
  /// here falls back to a table of common colour names, and an option whose
  /// values cannot all be resolved is drawn as boxes instead — half dots and
  /// half words reads as broken.
  final Map<String, String> optionColours;

  final List<ProductVariant> variants;

  /// The seller's sizing chart, shown from the "Size guide" link. Absent when
  /// the seller has not supplied one, and then the link is not shown either.
  final String? sizeGuide;

  final String? warranty;
  final String? returnPolicy;
  final int? availableQuantity;
  final bool isWishlisted;

  /// Buyers can see it: approved, not hidden, not taken down. Only its own
  /// store is ever sent one that is not (BUGS 98).
  final bool isListed;

  bool get hasVariants => variants.isNotEmpty;
  bool get isDiscounted => originalPrice != null && originalPrice! > price;
  bool get isAvailable => stockStatus.isPurchasable;

  List<String> get imageUrls => media.map((item) => item.url).toList();

  /// Finds the variant matching a full set of selected options.
  ProductVariant? variantFor(Map<String, String> selection) {
    if (variants.isEmpty) return null;
    for (final variant in variants) {
      final matches = selection.entries.every(
        (entry) => variant.options[entry.key] == entry.value,
      );
      if (matches && variant.options.length == selection.length) return variant;
    }
    return null;
  }
}
