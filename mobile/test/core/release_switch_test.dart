// The tester: a release built from the README talked to the fake server.
// USE_MOCK_DATA was on unless a build turned it off, and the README's
// release commands never did. And two places read the raw switch instead of
// demo mode, so even a production build kept product photos on the phone
// (the server refused them) and switched live updates off.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/config/app_config.dart';

void main() {
  test(
    'the app talks to the real server unless a build asks for the demo',
    () {
      final before = AppConfig.demoForTests;
      addTearDown(() => AppConfig.demoForTests = before);
      AppConfig.demoForTests = false;
      expect(AppConfig.useMockData, isFalse, reason: 'the demo is the default');
      expect(AppConfig.isDemoMode, isFalse);
    },
    // A run that sets the switch itself says nothing about the default.
    skip: const bool.hasEnvironment('USE_MOCK_DATA'),
  );

  // The reviewer: a release built without the server's address fell back
  // to localhost, the phone itself. Only a debug run or the demo may.
  test('a release without the server address refuses to start', () {
    expect(
      AppConfig.needsServerAddress(debug: false, demo: false, address: ''),
      isTrue,
    );
    expect(
      AppConfig.needsServerAddress(
        debug: false,
        demo: false,
        address: 'https://api.saba.iq/api/v1',
      ),
      isFalse,
    );
    expect(
      AppConfig.needsServerAddress(debug: true, demo: false, address: ''),
      isFalse,
      reason: 'a debug run on this laptop',
    );
    expect(
      AppConfig.needsServerAddress(debug: false, demo: true, address: ''),
      isFalse,
      reason: 'the demo needs no server',
    );
  });

  test('every part of the app asks isDemoMode, not the raw switch', () {
    final readers = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            !file.path
                .replaceAll(r'\', '/')
                .endsWith('config/app_config.dart') &&
            file.readAsStringSync().contains('AppConfig.useMockData'))
          file.path,
    ];
    expect(readers, isEmpty, reason: 'these ignore production: $readers');
  });
}
