import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'push_service.dart';

/// Firebase Cloud Messaging on a phone (S10).
class FirebasePush implements PushService {
  FirebasePush(this._messaging);

  final FirebaseMessaging _messaging;
  bool _openedAppTaken = false;

  @override
  Future<String?> token() async {
    try {
      return await _messaging.getToken();
    } on Object catch (_) {
      // On an iPhone, before Apple has given the phone its push address.
      // The address comes later through [tokenChanges].
      return null;
    }
  }

  @override
  Stream<String> get tokenChanges => _messaging.onTokenRefresh;

  @override
  Stream<PushTap> get taps async* {
    // The push that opened the app from closed, handed over once: the stream
    // is read again when the app rebuilds, and would open it a second time.
    if (!_openedAppTaken) {
      _openedAppTaken = true;
      final opened = await _messaging.getInitialMessage();
      if (opened != null) yield PushTap.fromData(opened.data);
    }
    yield* FirebaseMessaging.onMessageOpenedApp.map(
      (message) => PushTap.fromData(message.data),
    );
  }

  @override
  Future<void> askPermission() async {
    try {
      await _messaging.requestPermission();
      // An iPhone shows a push that arrives with the app open, as Android
      // does not: the list and the dot already say it there.
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } on Object catch (_) {
      // Refused, or not asked: the app works the same, without pushes.
    }
  }
}

/// Firebase, where the build has its config files (google-services.json,
/// GoogleService-Info.plist; mobile/README.md); no pushes where it has not,
/// and on the web and desktop. Firebase says it has no config by failing to
/// start, and the app runs on without it. [start] is for tests.
Future<PushService> startPush({Future<void> Function()? start}) async {
  if (kIsWeb) return const NoPush();
  if (defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS) {
    return const NoPush();
  }
  try {
    await (start ?? Firebase.initializeApp)();
    return FirebasePush(FirebaseMessaging.instance);
  } on Object catch (error) {
    debugPrint('No push on this build: $error');
    return const NoPush();
  }
}
