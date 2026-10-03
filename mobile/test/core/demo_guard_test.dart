import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/config/app_config.dart';
import 'package:saba_marketplace/features/auth/domain/entities.dart';

void main() {
  test('only a demo build shows the SMS code a server sent', () {
    const sent = <String, dynamic>{'expiresInSeconds': 90, 'demoCode': 123456};

    final demo = OtpChallenge.fromJson(sent, demo: true);
    expect(demo.demoCode, '123456');
    expect(demo.expiresInSeconds, 90);

    final real = OtpChallenge.fromJson(sent, demo: false);
    expect(real.demoCode, isNull, reason: 'a real build printed the code');
    expect(real.expiresInSeconds, 90);
  });

  test('a production build is never a demo', () {
    // Run with --dart-define=APP_ENV=production to check the other side.
    expect(
      AppConfig.isDemoMode,
      !AppConfig.isProduction && AppConfig.useMockData,
    );
    if (AppConfig.isProduction) expect(AppConfig.isDemoMode, isFalse);
  });
}
