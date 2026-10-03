import '../../../core/errors/result.dart';
import '../../../core/network/api_response.dart';
import 'entities.dart';
import 'product_query.dart';

/// Read access to the public catalog.
///
/// Everything here is served by the backend from MySQL. The app holds no
/// category list, brand list or product data of its own (specification
/// sections 7 and 70).
abstract interface class CatalogRepository {
  /// Root categories, each with its children populated one level deep.
  Future<Result<List<Category>>> fetchCategoryTree();

  Future<Result<Category>> fetchCategory(String id);

  /// Attribute definitions for a category, used to build dynamic filters.
  Future<Result<List<AttributeDefinition>>> fetchCategoryAttributes(
    String categoryId,
  );

  Future<Result<List<Brand>>> fetchBrands({String? categoryId});

  Future<Result<PaginatedList<ProductSummary>>> fetchProducts({
    required ProductQuery query,
    int page = 1,
  });

  Future<Result<Product>> fetchProduct(String id);

  /// The one rail under a product. There were three - related, similar and
  /// frequently bought together - and the demo shop answered all three with
  /// the same handful of products.
  Future<Result<List<ProductSummary>>> fetchRelatedProducts(String productId);
}
