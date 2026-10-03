import '../../../core/config/api_endpoints.dart';
import '../../../core/errors/result.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_response.dart';
import '../../../core/utils/json_reader.dart';
import '../domain/catalog_repository.dart';
import '../domain/entities.dart';
import '../domain/product_query.dart';
import 'catalog_mappers.dart';

/// Talks to the public catalog endpoints.
///
/// Combines the data source and repository roles for this read-only feature:
/// there is no local persistence to coordinate, so a separate data-source class
/// would only forward calls.
class CatalogRepositoryImpl implements CatalogRepository {
  const CatalogRepositoryImpl(this.client);

  final ApiClient client;

  @override
  Future<Result<List<Category>>> fetchCategoryTree() {
    return client.get<List<Category>>(
      ApiEndpoints.categories,
      queryParameters: const <String, dynamic>{'tree': true},
      decoder: (envelope) =>
          Json.mapList(envelope.dataAsList, CatalogMappers.category),
    );
  }

  @override
  Future<Result<Category>> fetchCategory(String id) {
    return client.get<Category>(
      ApiEndpoints.category(id),
      decoder: (envelope) => CatalogMappers.category(envelope.dataAsMap),
    );
  }

  @override
  Future<Result<List<AttributeDefinition>>> fetchCategoryAttributes(
    String categoryId,
  ) {
    return client.get<List<AttributeDefinition>>(
      ApiEndpoints.categoryAttributes(categoryId),
      decoder: (envelope) =>
          Json.mapList(envelope.dataAsList, CatalogMappers.attributeDefinition),
    );
  }

  @override
  Future<Result<List<Brand>>> fetchBrands({String? categoryId}) {
    return client.get<List<Brand>>(
      ApiEndpoints.brands,
      queryParameters: <String, dynamic>{'categoryId': ?categoryId},
      decoder: (envelope) =>
          Json.mapList(envelope.dataAsList, CatalogMappers.brand),
    );
  }

  @override
  Future<Result<PaginatedList<ProductSummary>>> fetchProducts({
    required ProductQuery query,
    int page = 1,
  }) {
    // A search term routes to the search endpoint, which the backend can back
    // with a dedicated search engine later without the app changing
    // (specification section 11).
    final hasSearch = (query.search ?? '').trim().isNotEmpty;
    return client.getPage<ProductSummary>(
      hasSearch ? ApiEndpoints.search : ApiEndpoints.products,
      page: page,
      queryParameters: query.toQueryParameters(),
      itemDecoder: CatalogMappers.productSummary,
    );
  }

  @override
  Future<Result<Product>> fetchProduct(String id) {
    return client.get<Product>(
      ApiEndpoints.product(id),
      decoder: (envelope) => CatalogMappers.product(envelope.dataAsMap),
    );
  }

  @override
  Future<Result<List<ProductSummary>>> fetchRelatedProducts(String productId) =>
      _summaryList(ApiEndpoints.relatedProducts(productId));

  Future<Result<List<ProductSummary>>> _summaryList(String path) {
    return client.get<List<ProductSummary>>(
      path,
      decoder: (envelope) =>
          Json.mapList(envelope.dataAsList, CatalogMappers.productSummary),
    );
  }
}
