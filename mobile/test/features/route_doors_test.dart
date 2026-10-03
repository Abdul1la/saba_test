import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every route must have a door.
///
/// A route can be declared, given a screen, given an access rule, and still be
/// unreachable because nothing in the app ever navigates to it. That has
/// happened here more than once — the merchant order detail had a screen and
/// no `GoRoute`, and the whole merchant area had routes and no link from
/// Account, so a signed-in seller could not reach their own store.
///
/// Reading the source rather than the widget tree is deliberate: the failure
/// is "nobody links here", which is a fact about the code, not about a frame.
void main() {
  /// Reached by redirect, by a link from outside the app, or by the navigation
  /// bar — so no `context.go` to them exists, and none should.
  ///
  /// Every entry needs a reason. A route parked here to silence the test is
  /// exactly the bug the test is for.
  const entryPoints = <String, String>{
    'splash': 'the first route the app boots into',
    'language': 'the redirect sends a first launch here',
    'home': 'the redirect target once a customer is signed in',
    'merchantDashboard': 'the redirect target once a merchant is signed in',
    'merchantAnalytics': 'a tab in the merchant shell, opened by the nav bar',
    'account': 'a tab in the customer shell, opened by the nav bar',
  };

  late final String routesSource;
  late final Map<String, String> routePaths;
  late final String appSource;

  /// `/orders/:id/invoice` and `'/orders/$orderId/invoice'` are the same door.
  /// Both collapse to `/orders/*/invoice` so they can be compared.
  String normalise(String path) => path
      .replaceAll(RegExp(r'\$\{[^}]*\}'), '*')
      .replaceAll(RegExp(r'\$\w+'), '*')
      .replaceAll(RegExp(r':\w+'), '*');

  setUpAll(() {
    routesSource = File('lib/core/router/app_routes.dart').readAsStringSync();

    routePaths = <String, String>{
      for (final m in RegExp(
        r"static const String (\w+) = '(/[^']*)'",
      ).allMatches(routesSource))
        m.group(1)!: m.group(2)!,
    };

    // Everything except the two files that exist to declare routes. A route
    // mentioned only there is declared, not reachable.
    final buffer = StringBuffer();
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final name = entity.path.replaceAll(r'\', '/');
      if (name.endsWith('core/router/app_routes.dart')) continue;
      if (name.endsWith('core/router/app_router.dart')) continue;
      buffer.writeln(entity.readAsStringSync());
    }
    appSource = buffer.toString();
  });

  test('the route table is not empty', () {
    // Guards the regex above: a rename that stopped it matching would turn
    // every assertion below into a silent pass over zero routes.
    expect(routePaths.length, greaterThan(40));
  });

  test('every route can be reached from somewhere in the app', () {
    // Most screens navigate through a builder — `conversationPath(id)` rather
    // than `conversationDetail` — and the builder writes the path out as a
    // literal. So a builder counts as a door for the route whose path it
    // writes, or whose constant it names, provided the builder itself is used.
    final builderDoors = <String>{};
    for (final m in RegExp(
      r'static String (\w+)\([^)]*\)\s*(?:=>|\{)([\s\S]*?);',
    ).allMatches(routesSource)) {
      final builder = m.group(1)!;
      final body = m.group(2)!;
      if (!RegExp('AppRoutes\\.$builder\\b').hasMatch(appSource)) continue;

      for (final entry in routePaths.entries) {
        // Matched against the whole normalised body rather than against
        // string literals picked out of it: a builder that appends an optional
        // query holds nested quotes - `? '' : '?rating=\$rating'` - and
        // literal-by-literal extraction tears those in half. The trailing
        // `\*|'` keeps `/orders/*` from matching `/orders/*/invoice`.
        final target = normalise(entry.value);
        final writesThePath = RegExp(
          '${RegExp.escape(target)}'
          r"(\*|')",
        ).hasMatch(normalise(body));
        final namesTheRoute = RegExp('\\b${entry.key}\\b').hasMatch(body);
        if (writesThePath || namesTheRoute) builderDoors.add(entry.key);
      }
    }

    final orphans = <String>[];
    for (final name in routePaths.keys) {
      if (entryPoints.containsKey(name)) continue;
      if (builderDoors.contains(name)) continue;
      if (RegExp('AppRoutes\\.$name\\b').hasMatch(appSource)) continue;
      orphans.add(name);
    }

    expect(
      orphans,
      isEmpty,
      reason:
          'These routes exist but nothing navigates to them, so no user can '
          'get there: ${orphans.join(', ')}. Either add the link that opens '
          'each one, or delete the route.',
    );
  });

  test('every route declares an access rule', () {
    // A route missing from the access map falls to whatever the default is,
    // which is how a merchant-only screen ends up open to a customer.
    final missing = routePaths.keys
        .where((name) => !routesSource.contains('AppRoutes.$name: RouteAccess'))
        .toList();

    expect(
      missing,
      isEmpty,
      reason:
          'These routes have no entry in the access map: ${missing.join(', ')}',
    );
  });

  // There was a fourth check here - "every route has a GoRoute behind it" -
  // and it was deleted rather than kept. A child route is registered under
  // its parent with a relative path (`':id'` under `AppRoutes.supportTickets`),
  // which is correct go_router and which reading the source cannot see, so the
  // check called three healthy routes broken. A test that cries wolf gets
  // muted, and a muted test protects nothing.

  test('every exception in this file still names a real route', () {
    // Stops the allow-list rotting: a renamed or deleted route would leave an
    // entry here quietly excusing nothing.
    final stale = entryPoints.keys
        .where((name) => !routePaths.containsKey(name))
        .toList();

    expect(
      stale,
      isEmpty,
      reason: 'No longer real routes: ${stale.join(', ')}',
    );
  });
}
