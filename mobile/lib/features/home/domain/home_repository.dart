import '../../../core/errors/result.dart';
import 'entities.dart';

/// The home page is data, not layout.
///
/// Administrators compose banners, flash sales and featured rails from the web
/// panel; this returns whatever they configured (specification section 6).
abstract interface class HomeRepository {
  Future<Result<List<HomeSection>>> fetchHomeFeed();
}
