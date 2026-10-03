import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The demo data has to come out in one piece.
///
/// When the backend is real, deleting the fake data must be deleting a folder
/// — not hunting through fifty screens for a hard-coded name. This test is the
/// promise that it stays that way: if demo data starts leaking into feature
/// code, it fails here rather than being discovered on the day of the switch.
///
/// The whole seam:
///   * `lib/core/mock/` — every fake product, order, store and user.
///   * `AppConfig.useMockData` — one compile-time flag.
///   * `lib/core/network/dio_factory.dart` — the only file that reads it.
void main() {
  late final List<({String path, String source})> libFiles;

  setUpAll(() {
    libFiles = [
      for (final entity in Directory('lib').listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          (
            path: entity.path.replaceAll(r'\', '/'),
            source: entity.readAsStringSync(),
          ),
    ];
  });

  test('all demo data lives in lib/core/mock', () {
    const allowed = <String>{
      'lib/core/mock/mock_api_interceptor.dart',
      'lib/core/mock/mock_data.dart',
      // Keeps the demo server on the phone; part of mock_api_interceptor.
      'lib/core/mock/mock_state_saving.dart',
      // Wires the interceptor in when the flag is on, and nothing else.
      'lib/core/network/dio_factory.dart',
      'lib/core/config/app_config.dart',
    };

    final leaks = libFiles
        .where((f) => !allowed.contains(f.path))
        .where(
          // `MockData.`, with the dot: the class being *used*. Matching the
          // bare word also caught every file that reads the flag, which is
          // called `useMockData` and carries no data at all.
          (f) =>
              f.source.contains('MockData.') ||
              f.source.contains('MockApiInterceptor') ||
              f.source.contains("core/mock/"),
        )
        .map((f) => f.path)
        .toList();

    expect(
      leaks,
      isEmpty,
      reason:
          'Demo data reached outside lib/core/mock: ${leaks.join(', ')}. '
          'Move it back, or deleting the fake data later means editing these '
          'files too.',
    );
  });

  test('demo mode is one flag, read in one place', () {
    final readers = libFiles
        .where((f) => f.source.contains('AppConfig.isDemoMode'))
        .map((f) => f.path)
        .toList();

    // The screens may ask whether this is a demo build — the sign-in screen
    // shows its demo accounts that way — but only the network layer may act
    // on it by installing a fake backend.
    expect(
      readers.where((p) => p.startsWith('lib/core/network/')).length,
      1,
      reason: 'Expected exactly one network-layer reader, found: $readers',
    );

    final config = File('lib/core/config/app_config.dart').readAsStringSync();
    expect(
      config.contains('bool.fromEnvironment'),
      isTrue,
      reason:
          'The flag must stay compile-time, so a release build cannot ship '
          'the fake backend by accident.',
    );
  });

  test('no screen hard-codes a demo email or phone', () {
    // The two demo accounts are named on the sign-in screen on purpose. Any
    // other screen naming them means fake data has grown a second home.
    const allowed = <String>{
      'lib/features/auth/presentation/screens/login_screen.dart',
    };

    final pattern = RegExp(r'(shopper@saba\.app|merchant@saba\.app)');
    final leaks = libFiles
        .where((f) => !allowed.contains(f.path) && !f.path.contains('/mock/'))
        .where((f) => pattern.hasMatch(f.source))
        .map((f) => f.path)
        .toList();

    expect(
      leaks,
      isEmpty,
      reason: 'Demo accounts named in: ${leaks.join(', ')}',
    );
  });

  // Saba sells in Iraq. The demo data was written against an earlier market
  // and the merchants were moved, but the customer's own saved address was
  // not — so the checkout a client is shown delivered to Amman, and the
  // signed-in sessions claimed to be in Jordan. Names, not a country field:
  // a stray city is how it came back the first time.
  test('the demo data is set in the market the app sells in', () {
    const foreign = <String>['Jordan', 'Amman', 'Irbid', '+962'];

    for (final file in libFiles) {
      if (!file.path.startsWith('lib/core/mock/')) continue;
      for (final word in foreign) {
        expect(
          file.source.contains(word),
          isFalse,
          reason: '${file.path} still mentions $word; Saba sells in Iraq',
        );
      }
    }
  });
}
