import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A counter that increments each time the backend rejects our refresh token.
///
/// This exists to break what would otherwise be a dependency cycle: the network
/// layer needs to announce "the session is over", but it must not depend on the
/// auth feature. The auth controller watches this instead, and the router
/// reacts to the auth controller.
class SessionEvents extends Notifier<int> {
  @override
  int build() => 0;

  /// Called by the auth interceptor once a refresh attempt has definitively
  /// failed. Safe to call repeatedly.
  void reportExpired() => state = state + 1;
}

final sessionEventsProvider = NotifierProvider<SessionEvents, int>(
  SessionEvents.new,
);
