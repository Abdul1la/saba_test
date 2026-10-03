// S10, the reviewer's item 4: pushes come through Firebase where the build
// has the project's config files, and the app must run without them.
// Firebase itself needs a phone; this checks what the app decides around it.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/push/firebase_push.dart';
import 'package:saba_marketplace/core/push/push_service.dart';

void main() {
  test('a build without the config files runs without pushes', () async {
    final push = await startPush(
      start: () async => throw Exception('[core/no-app] No Firebase App'),
    );
    expect(push, isA<NoPush>());
  });

  test('the web and desktop never start Firebase', () async {
    var started = false;
    for (final platform in [TargetPlatform.windows, TargetPlatform.macOS]) {
      debugDefaultTargetPlatformOverride = platform;
      final push = await startPush(start: () async => started = true);
      debugDefaultTargetPlatformOverride = null;
      expect(push, isA<NoPush>());
    }
    expect(started, isFalse);
  });

  test("a push's data opens what its notification opens", () {
    final tap = PushTap.fromData(const {
      'notificationId': '41',
      'targetType': 'ORDER',
      'targetId': '1007',
    });
    expect(
      (tap.notificationId, tap.targetType, tap.targetId),
      ('41', 'ORDER', '1007'),
    );
    final empty = PushTap.fromData(const {});
    expect((empty.notificationId, empty.targetType), (null, null));
  });
}
