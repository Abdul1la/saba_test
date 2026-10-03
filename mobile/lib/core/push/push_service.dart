import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/api_endpoints.dart';
import '../network/api_client.dart';
import '../providers/core_providers.dart';

/// A push the person tapped: what it is about, as its notification says.
@immutable
class PushTap {
  const PushTap({this.notificationId, this.targetType, this.targetId});

  /// A push's data, as the server sends it: all strings (BACKEND_READY.md,
  /// "Push notifications, the app's side").
  factory PushTap.fromData(Map<String, dynamic> data) => PushTap(
    notificationId: data['notificationId']?.toString(),
    targetType: data['targetType']?.toString(),
    targetId: data['targetId']?.toString(),
  );

  final String? notificationId;
  final String? targetType;
  final String? targetId;
}

/// The phone's push messaging (BACKEND_PLAN.md §7, S10 and M10).
///
/// Firebase (`firebase_push.dart`) where the build has the project's config
/// files; [NoPush] where it has not, and on the web and desktop, so the
/// phone has no push address and nothing is registered. `main.dart` picks.
abstract interface class PushService {
  /// This phone's push address, or null when it has none.
  Future<String?> token();

  /// A new address, when the push service replaces the old one.
  Stream<String> get tokenChanges;

  /// Pushes the person tapped, the one that opened the app included.
  Stream<PushTap> get taps;

  /// Asks to show pushes; the app works on whatever the answer.
  Future<void> askPermission();
}

/// No push messaging on this build.
class NoPush implements PushService {
  const NoPush();

  @override
  Future<String?> token() async => null;

  @override
  Stream<String> get tokenChanges => const Stream<String>.empty();

  @override
  Stream<PushTap> get taps => const Stream<PushTap>.empty();

  @override
  Future<void> askPermission() async {}
}

final pushServiceProvider = Provider<PushService>((ref) => const NoPush());

/// This phone's push address on the server: sent for whoever is signed in,
/// in the language the app is in, and taken back at sign-out so the next
/// person on the phone does not get the last one's pushes.
class PushDevice {
  PushDevice(this._client, this._push, this._language);

  final ApiClient _client;
  final PushService _push;
  final String _language;
  String? _sent;

  /// "ANDROID" or "IOS"; null where there are no pushes (the web, desktop).
  static String? get platform {
    if (kIsWeb) return null;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'ANDROID',
      TargetPlatform.iOS => 'IOS',
      _ => null,
    };
  }

  Future<void> register() async {
    final platform = PushDevice.platform;
    if (platform == null) return;
    final token = await _push.token();
    if (token == null || token.isEmpty) return;
    final sent = await _client.command(
      ApiEndpoints.devices,
      method: 'PUT',
      data: <String, dynamic>{
        'token': token,
        'platform': platform,
        'language': _language,
      },
    );
    if (sent.isOk) _sent = token;
  }

  /// Best effort, and quick: signing out never waits on it for long.
  Future<void> forget() async {
    final token = _sent ?? await _push.token();
    if (token == null || token.isEmpty || platform == null) return;
    try {
      await _client
          .command(
            ApiEndpoints.devices,
            method: 'DELETE',
            data: <String, dynamic>{'token': token},
          )
          .timeout(const Duration(seconds: 5));
    } on TimeoutException {
      // The server moves the address to whoever signs in next anyway.
    }
    _sent = null;
  }
}

final pushDeviceProvider = Provider<PushDevice>(
  (ref) => PushDevice(
    ref.watch(apiClientProvider),
    ref.watch(pushServiceProvider),
    ref.watch(acceptLanguageProvider),
  ),
);
