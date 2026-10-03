import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/router/deep_links.dart';

/// Phase 6 — G15. The parsing half of deep linking, kept pure so it can be
/// tested without a router, a platform channel or a device.
void main() {
  group('normalizeDeepLink', () {
    test('moves the host into the path and keeps the query', () {
      // This is the case that matters: a custom scheme puts the first segment
      // in `host` and leaves `path` empty, so the raw URI resolves to `/`.
      final uri = Uri.parse('saba://search?q=abc123');
      expect(uri.path, isEmpty, reason: 'precondition: the trap being avoided');

      expect(normalizeDeepLink(uri), '/search?q=abc123');
    });

    test('keeps deeper paths intact', () {
      expect(
        normalizeDeepLink(Uri.parse('saba://orders/o-1/invoice')),
        '/orders/o-1/invoice',
      );
    });

    test('carries every query parameter, not just the first', () {
      final result = normalizeDeepLink(
        Uri.parse('saba://reset-password?token=t1&email=a%40b.com'),
      );
      expect(result, contains('token=t1'));
      expect(result, contains('email=a%40b.com'));
    });

    test('a bare link just opens the app', () {
      expect(normalizeDeepLink(Uri.parse('saba://')), AppRoutes.home);
    });

    test('ignores in-app paths, so the redirect does not loop', () {
      expect(normalizeDeepLink(Uri.parse('/search?q=x')), isNull);
      expect(normalizeDeepLink(Uri.parse('/home')), isNull);
    });

    test('ignores other schemes', () {
      expect(
        normalizeDeepLink(Uri.parse('https://saba.app/search?q=x')),
        isNull,
      );
    });
  });

  group('PendingDeepLink', () {
    test('hands the destination back exactly once', () {
      final pending = PendingDeepLink();
      pending.remember('/search?q=abc');

      expect(pending.take(), '/search?q=abc');
      expect(
        pending.take(),
        isNull,
        reason: 'a consumed link must not hijack a later navigation',
      );
    });

    test('is empty until something is remembered', () {
      expect(PendingDeepLink().take(), isNull);
    });

    test('refuses to remember the splash screen', () {
      // Remembering it would make the splash redirect to itself forever.
      final pending = PendingDeepLink()..remember(AppRoutes.splash);
      expect(pending.take(), isNull);
    });

    test('the newest link wins', () {
      final pending = PendingDeepLink()
        ..remember('/a')
        ..remember('/b');
      expect(pending.take(), '/b');
    });
  });
}
