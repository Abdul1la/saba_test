import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/api_endpoints.dart';
import '../../../core/config/app_config.dart';
import '../../../core/network/live_channel.dart';
import '../../../core/network/live_updates.dart';
import '../../../core/providers/core_providers.dart';
import '../../auth/presentation/auth_providers.dart';
import 'notifications_providers.dart';

/// The server's live changes for whoever is signed in: opened at sign-in,
/// closed at sign-out, and opened again for the next account when the phone
/// changes hands. The demo server has no stream: there, the app's own
/// announcements are the only ones, as before. See `BACKEND_READY.md`,
/// "How to switch the app over".
///
/// Kept open by the app itself ([SabaApp] listens to it).
final liveChannelProvider = Provider<LiveChannel?>((ref) {
  final account = ref.watch(accountIdProvider);
  if (account == null || AppConfig.isDemoMode) return null;

  // A store's approval, rejection, suspension or its lifting reaches the
  // store as a notification of type STORE; the dashboard's banner reads the
  // signed-in account, so the account is read again (BACKEND_PLAN.md §9,
  // item 7). Checked on every notifications change and each (re)connect,
  // by the newest notification, and once for each.
  String? lastStoreNotice;
  var checking = false;
  Future<void> storeAnswered() async {
    if (checking) return;
    final user = ref.read(currentUserProvider);
    if (user == null || !user.role.isMerchant) return;
    checking = true;
    try {
      final newest = (await ref.read(notificationsRepositoryProvider).fetch())
          .valueOrNull
          ?.items
          .firstOrNull;
      if (newest == null || newest.targetType != 'STORE') return;
      if (newest.id == lastStoreNotice) return;
      lastStoreNotice = newest.id;
      await ref.read(authControllerProvider.notifier).refreshUser();
    } finally {
      checking = false;
    }
  }

  final channel = LiveChannel(
    dio: ref.watch(dioProvider),
    live: ref.watch(liveUpdatesProvider),
    path: ApiEndpoints.events,
    onServerTopic: (topic) {
      if (topic == LiveTopic.notifications) storeAnswered();
    },
  )..start();
  ref.onDispose(channel.stop);
  return channel;
});
