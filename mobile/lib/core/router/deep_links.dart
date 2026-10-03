import '../config/app_config.dart';
import 'app_routes.dart';

/// Turns an incoming `saba://…` link into an in-app location.
///
/// The OS hands the app the whole URI, and a custom scheme parses in a way the
/// router cannot match: `saba://search?q=x` has an **empty path** and puts
/// `search` in the host. Left alone it would resolve to `/`, and the query
/// would be silently dropped.
///
/// Returns null for anything that is already an in-app path, so the router can
/// ignore it.
String? normalizeDeepLink(Uri uri) {
  if (uri.scheme != AppConfig.deepLinkScheme) return null;

  final segments = <String>[
    if (uri.host.isNotEmpty) uri.host,
    ...uri.pathSegments,
  ];

  // A bare `saba://` is just "open the app".
  if (segments.isEmpty) return AppRoutes.home;

  final location = '/${segments.join('/')}';
  return uri.hasQuery ? '$location?${uri.query}' : location;
}

/// Where the app was asked to go before the session was known.
///
/// A link opens the app cold: the router is asked for
/// `/search?q=…` while `AuthController` is still restoring the
/// session, so the redirect parks on the splash screen. Without somewhere to
/// put the destination it is lost, and the customer lands on the home screen
/// wondering why the link did nothing.
///
/// Deliberately a tiny mutable holder behind a provider rather than a global:
/// every test gets a fresh one with its `ProviderContainer`.
class PendingDeepLink {
  String? _location;

  /// Ignores the splash screen itself, which would redirect to itself forever.
  void remember(String location) {
    if (location == AppRoutes.splash) return;
    _location = location;
  }

  /// Returns the stored destination once, then forgets it. Consuming it is the
  /// point: a stale link must not hijack a later navigation.
  String? take() {
    final location = _location;
    _location = null;
    return location;
  }
}
