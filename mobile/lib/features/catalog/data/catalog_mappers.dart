import '../../../core/config/app_config.dart';
import '../../../core/location/governorate.dart';
import '../../../core/location/store_delivery.dart';
import '../../../core/utils/json_reader.dart';
import '../domain/entities.dart';

/// JSON to domain conversion for the catalog.
class CatalogMappers {
  const CatalogMappers._();

  static Category category(Map<String, dynamic> json) => Category(
    id: Json.str(json, const ['id', 'categoryId']),
    name: Json.str(json, const ['name', 'title']),
    slug: Json.strOrNull(json, const ['slug']),
    imageUrl: Json.strOrNull(json, const ['imageUrl', 'image']),
    bannerUrl: Json.strOrNull(json, const ['bannerUrl', 'banner']),
    parentId: Json.strOrNull(json, const ['parentId', 'parent_id']),
    productCount: Json.integer(json, const ['productCount', 'productsCount']),
    children: Json.mapList(
      Json.objects(json, const ['children', 'subcategories']),
      category,
    ),
  );

  static Brand brand(Map<String, dynamic> json) => Brand(
    id: Json.str(json, const ['id', 'brandId']),
    name: Json.str(json, const ['name']),
    nameAr: Json.strOrNull(json, const ['nameAr']),
    logoUrl: Json.strOrNull(json, const ['logoUrl', 'logo', 'imageUrl']),
    productCount: Json.integer(json, const ['productCount']),
  );

  static AttributeDefinition attributeDefinition(Map<String, dynamic> json) =>
      AttributeDefinition(
        id: Json.str(json, const ['id', 'attributeId']),
        name: Json.str(json, const ['name', 'label']),
        type: Json.str(json, const [
          'type',
          'dataType',
        ], fallback: 'TEXT').toUpperCase(),
        unit: Json.strOrNull(json, const ['unit']),
        isRequired: Json.boolean(json, const ['isRequired', 'required']),
        isFilterable: Json.boolean(json, const ['isFilterable', 'filterable']),
        isVariantOption: Json.boolean(json, const [
          'isVariantOption',
          'isVariant',
        ]),
        values: Json.mapList(
          Json.objects(json, const ['values', 'options', 'attributeValues']),
          attributeOption,
        ),
      );

  static AttributeOption attributeOption(Map<String, dynamic> json) =>
      AttributeOption(
        id: Json.str(json, const ['id', 'valueId']),
        value: Json.str(json, const ['value', 'name']),
        label: Json.strOrNull(json, const ['label', 'displayName']),
      );

  static ProductMedia media(Map<String, dynamic> json) => ProductMedia(
    id: Json.str(json, const ['id']),
    url: Json.str(json, const ['url', 'imageUrl', 'src']),
    thumbnailUrl: Json.strOrNull(json, const ['thumbnailUrl', 'thumbnail']),
    isPrimary: Json.boolean(json, const ['isPrimary', 'primary']),
  );

  static ProductVariant variant(Map<String, dynamic> json) {
    final quantity = Json.integerOrNull(json, const [
      'availableQuantity',
      'stock',
      'quantity',
    ]);
    return ProductVariant(
      id: Json.str(json, const ['id', 'variantId']),
      price: Json.number(json, const ['price', 'salePrice']),
      stockStatus: StockStatus.fromApi(
        json['stockStatus'] ?? json['stock_status'],
        quantity: quantity,
        threshold: Json.integerOrNull(json, const ['lowStockThreshold']),
      ),
      sku: Json.strOrNull(json, const ['sku']),
      barcode: Json.strOrNull(json, const ['barcode']),
      originalPrice: Json.numberOrNull(json, const [
        'originalPrice',
        'compareAtPrice',
      ]),
      discountPercentage: Json.numberOrNull(json, const [
        'discountPercentage',
        'discountPercent',
      ]),
      availableQuantity: quantity,
      imageUrl: Json.strOrNull(json, const ['imageUrl', 'image']),
      weight: Json.numberOrNull(json, const ['weight']),
      dimensions: Json.strOrNull(json, const ['dimensions']),
      options: _variantOptions(json),
    );
  }

  /// Accepts either `options: {Color: Black}` or
  /// `attributes: [{name: Color, value: Black}]`.
  static Map<String, String> _variantOptions(Map<String, dynamic> json) {
    final flat = Json.stringMap(json, const ['options', 'variantOptions']);
    if (flat.isNotEmpty) return flat;

    final list = Json.objects(json, const ['attributes', 'variantAttributes']);
    if (list.isEmpty) return const <String, String>{};

    return <String, String>{
      for (final entry in list)
        Json.str(entry, const ['name', 'attributeName']): Json.str(
          entry,
          const ['value', 'attributeValue'],
        ),
    };
  }

  static ProductMerchant merchant(Map<String, dynamic> json) => ProductMerchant(
    id: Json.str(json, const ['id', 'merchantId']),
    storeName: Json.str(json, const ['storeName', 'name', 'businessName']),
    logoUrl: Json.strOrNull(json, const ['logoUrl', 'logo']),
    rating: Json.decimalOrNull(json, const ['rating', 'averageRating']),
    reviewCount: Json.integer(json, const ['reviewCount', 'reviewsCount']),
    governorate: Governorate.fromApi(json['governorate'] ?? json['city']),
    delivery: StoreDelivery.fromJson(json['delivery']),
    isOpen: Json.boolean(json, const ['isOpen'], fallback: true),
  );

  static ProductSummary productSummary(Map<String, dynamic> json) {
    final merchantJson = Json.objectOrNull(json, const ['merchant', 'store']);
    final brandJson = Json.objectOrNull(json, const ['brand']);
    final quantity = Json.integerOrNull(json, const [
      'availableQuantity',
      'stock',
    ]);

    return ProductSummary(
      id: Json.str(json, const ['id', 'productId']),
      name: Json.str(json, const ['name', 'title']),
      price: Json.number(json, const ['price', 'salePrice']),
      currencyCode: Json.str(json, const [
        'currencyCode',
        'currency',
      ], fallback: AppConfig.fallbackCurrencyCode),
      stockStatus: StockStatus.fromApi(
        json['stockStatus'] ?? json['stock_status'],
        quantity: quantity,
      ),
      imageUrl: Json.strOrNull(json, const [
        'imageUrl',
        'primaryImage',
        'thumbnail',
        'image',
      ]),
      originalPrice: Json.numberOrNull(json, const [
        'originalPrice',
        'compareAtPrice',
      ]),
      discountPercentage: Json.numberOrNull(json, const [
        'discountPercentage',
        'discountPercent',
      ]),
      merchantId: merchantJson == null
          ? Json.strOrNull(json, const ['merchantId'])
          : Json.str(merchantJson, const ['id', 'merchantId']),
      merchantName: merchantJson == null
          ? Json.strOrNull(json, const ['merchantName'])
          : Json.str(merchantJson, const ['storeName', 'name']),
      merchantCity: merchantJson == null
          ? null
          : Governorate.fromApi(
              merchantJson['governorate'] ?? merchantJson['city'],
            ),
      brandName: brandJson == null
          ? Json.strOrNull(json, const ['brandName'])
          : Json.str(brandJson, const ['name']),
      isWishlisted: Json.boolean(json, const ['isWishlisted', 'inWishlist']),
      isFlashSale: Json.boolean(json, const ['isFlashSale', 'flashSale']),
      flashSaleEndsAt: Json.date(json, const ['flashSaleEndsAt', 'saleEndsAt']),
      hasOptions:
          Json.boolean(json, const ['hasVariants', 'hasOptions']) ||
          (json['variants'] is List && (json['variants'] as List).isNotEmpty),
      deliveryAvailable: Json.boolean(json, const ['deliveryAvailable']),
    );
  }

  static Product product(Map<String, dynamic> json) {
    final merchantJson = Json.objectOrNull(json, const ['merchant', 'store']);
    final brandJson = Json.objectOrNull(json, const ['brand']);
    final categoryJson = Json.objectOrNull(json, const ['category']);
    final quantity = Json.integerOrNull(json, const [
      'availableQuantity',
      'stock',
    ]);

    final variants = Json.mapList(
      Json.objects(json, const ['variants', 'productVariants']),
      variant,
    );

    final images = Json.mapList(
      Json.objects(json, const ['images', 'productImages']),
      media,
    );
    return Product(
      id: Json.str(json, const ['id', 'productId']),
      name: Json.str(json, const ['name', 'title']),
      nameEn: Json.strOrNull(json, const ['nameEn']),
      nameAr: Json.strOrNull(json, const ['nameAr']),
      price: Json.number(json, const ['price', 'salePrice']),
      currencyCode: Json.str(json, const [
        'currencyCode',
        'currency',
      ], fallback: AppConfig.fallbackCurrencyCode),
      stockStatus: StockStatus.fromApi(
        json['stockStatus'] ?? json['stock_status'],
        quantity: quantity,
      ),
      description: Json.strOrNull(json, const ['description', 'details']),
      media: images,
      originalPrice: Json.numberOrNull(json, const [
        'originalPrice',
        'compareAtPrice',
      ]),
      discountPercentage: Json.numberOrNull(json, const [
        'discountPercentage',
        'discountPercent',
      ]),
      sku: Json.strOrNull(json, const ['sku']),
      barcode: Json.strOrNull(json, const ['barcode']),
      brand: brandJson == null ? null : brand(brandJson),
      categoryId: categoryJson == null
          ? Json.strOrNull(json, const ['categoryId'])
          : Json.str(categoryJson, const ['id']),
      categoryName: categoryJson == null
          ? Json.strOrNull(json, const ['categoryName'])
          : Json.str(categoryJson, const ['name']),
      merchant: merchantJson == null ? null : merchant(merchantJson),
      variantOptions: _variantOptionsFrom(json, variants),
      optionColours: Json.stringMap(json, const [
        'optionColours',
        'optionColors',
      ]),
      variants: variants,
      sizeGuide: Json.strOrNull(json, const ['sizeGuide', 'sizeChart']),
      warranty: Json.strOrNull(json, const ['warranty', 'warrantyInfo']),
      returnPolicy: Json.strOrNull(json, const ['returnPolicy']),
      availableQuantity: quantity,
      isWishlisted: Json.boolean(json, const ['isWishlisted', 'inWishlist']),
      isListed: Json.boolean(json, const ['isListed'], fallback: true),
    );
  }

  /// Prefers the explicit option list from the API, and otherwise derives the
  /// option axes from the variants themselves so the selector still works.
  static Map<String, List<String>> _variantOptionsFrom(
    Map<String, dynamic> json,
    List<ProductVariant> variants,
  ) {
    final declared = Json.objects(json, const ['variantOptions', 'options']);
    if (declared.isNotEmpty) {
      return <String, List<String>>{
        for (final option in declared)
          Json.str(option, const ['name', 'label']): Json.strings(
            option,
            const ['values', 'options'],
          ),
      };
    }

    final derived = <String, List<String>>{};
    for (final variant in variants) {
      variant.options.forEach((name, value) {
        final values = derived.putIfAbsent(name, () => <String>[]);
        if (!values.contains(value)) values.add(value);
      });
    }
    return derived;
  }
}
