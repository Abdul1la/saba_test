import '../../../core/config/api_endpoints.dart';
import '../../../core/errors/result.dart';
import '../../../core/location/governorate.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json_reader.dart';
import '../../catalog/data/catalog_mappers.dart';
import '../../catalog/domain/entities.dart' show ProductSummary;
import '../domain/entities.dart';
import '../domain/home_repository.dart';

class HomeMappers {
  const HomeMappers._();

  static HomeSection section(Map<String, dynamic> json) {
    final type = HomeSectionType.fromApi(
      json['type'] ?? json['sectionType'] ?? json['kind'],
    );

    // Items may arrive under a generic `items` key or a type-specific one.
    final items = Json.objects(json, const ['items', 'data', 'products']);

    return HomeSection(
      id: Json.str(json, const ['id', 'sectionId']),
      type: type,
      title: Json.strOrNull(json, const ['title', 'name', 'label']),
      subtitle: Json.strOrNull(json, const ['subtitle', 'description']),
      products: switch (type) {
        HomeSectionType.productCarousel ||
        HomeSectionType.productGrid ||
        HomeSectionType.flashSale => Json.mapList(
          items,
          CatalogMappers.productSummary,
        ),
        _ => const <ProductSummary>[],
      },
      banners: type == HomeSectionType.bannerCarousel
          ? Json.mapList(
              items.isNotEmpty ? items : Json.objects(json, const ['banners']),
              banner,
            )
          : const <HomeBanner>[],
      categories: type == HomeSectionType.categoryGrid
          ? Json.mapList(
              items.isNotEmpty
                  ? items
                  : Json.objects(json, const ['categories']),
              CatalogMappers.category,
            )
          : const [],
      merchants: type == HomeSectionType.merchantCarousel
          ? Json.mapList(
              items.isNotEmpty
                  ? items
                  : Json.objects(json, const ['merchants']),
              merchant,
            )
          : const <FeaturedMerchant>[],
      brands: type == HomeSectionType.brandCarousel
          ? Json.mapList(
              items.isNotEmpty ? items : Json.objects(json, const ['brands']),
              CatalogMappers.brand,
            )
          : const [],
      endsAt: Json.date(json, const ['endsAt', 'endTime', 'expiresAt']),
      categoryId: Json.strOrNull(json, const ['categoryId']),
    );
  }

  static HomeBanner banner(Map<String, dynamic> json) {
    // What Saba's admin linked it to: {type: PRODUCT|STORE|CATEGORY, id},
    // or null for a banner that is only a picture. The flat keys read
    // before were never sent, so no banner could lead anywhere.
    final link = Json.objectOrNull(json, const ['link']);
    return HomeBanner(
      id: Json.str(json, const ['id', 'bannerId']),
      imageUrl: Json.str(json, const ['imageUrl', 'image', 'url']),
      title: Json.strOrNull(json, const ['title']),
      subtitle: Json.strOrNull(json, const ['subtitle', 'description']),
      action: link == null
          ? null
          : BannerAction(
              type: Json.str(link, const ['type'], fallback: 'NONE'),
              value: Json.strOrNull(link, const ['id']),
            ),
    );
  }

  static FeaturedMerchant merchant(Map<String, dynamic> json) =>
      FeaturedMerchant(
        id: Json.str(json, const ['id', 'merchantId']),
        storeName: Json.str(json, const ['storeName', 'name', 'businessName']),
        logoUrl: Json.strOrNull(json, const ['logoUrl', 'logo']),
        bannerUrl: Json.strOrNull(json, const ['bannerUrl', 'banner']),
        rating: Json.decimalOrNull(json, const ['rating', 'averageRating']),
        productCount: Json.integer(json, const ['productCount']),
        governorate: Governorate.fromApi(json['governorate'] ?? json['city']),
      );
}

class HomeRepositoryImpl implements HomeRepository {
  const HomeRepositoryImpl(this.client);

  final ApiClient client;

  @override
  Future<Result<List<HomeSection>>> fetchHomeFeed() {
    return client.get<List<HomeSection>>(
      ApiEndpoints.homeSections,
      decoder: (envelope) {
        final sections = Json.mapList(envelope.dataAsList, HomeMappers.section);
        // Drop sections the backend sent but that have nothing to show, and
        // types this build does not understand yet.
        return sections
            .where(
              (section) =>
                  !section.isEmpty && section.type != HomeSectionType.unknown,
            )
            .toList(growable: false);
      },
    );
  }
}
