import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/api_endpoints.dart';
import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_response.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/providers/paged_state.dart';
import '../../../core/utils/json_reader.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/entities.dart';
import '../../../core/network/live_updates.dart';

export '../domain/entities.dart' show NotificationCategory;

@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.createdAt,
    this.isRead = false,
    this.targetType,
    this.targetId,
  });

  final String id;
  final String title;
  final String body;
  final NotificationCategory category;
  final DateTime createdAt;
  final bool isRead;

  /// ORDER | PRODUCT | CONVERSATION | TICKET, and the id to open.
  final String? targetType;
  final String? targetId;
}

abstract interface class NotificationsRepository {
  Future<Result<PaginatedList<AppNotification>>> fetch({int page = 1});

  Future<Result<void>> markRead(String id);

  Future<Result<void>> markAllRead();

  Future<Result<int>> unreadCount();
}

class NotificationsRepositoryImpl implements NotificationsRepository {
  const NotificationsRepositoryImpl(this.client);

  final ApiClient client;

  @override
  Future<Result<PaginatedList<AppNotification>>> fetch({int page = 1}) {
    return client.getPage<AppNotification>(
      ApiEndpoints.notifications,
      page: page,
      itemDecoder: (json) => AppNotification(
        id: Json.str(json, const ['id']),
        title: Json.str(json, const ['title', 'subject']),
        body: Json.str(json, const ['body', 'message', 'text']),
        category: NotificationCategory.fromApi(
          json['type'] ?? json['category'],
        ),
        createdAt:
            Json.date(json, const ['createdAt', 'sentAt']) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        isRead: Json.boolean(json, const ['isRead', 'read']),
        targetType: Json.strOrNull(json, const ['targetType', 'entityType']),
        targetId: Json.strOrNull(json, const ['targetId', 'entityId']),
      ),
    );
  }

  @override
  Future<Result<void>> markRead(String id) => client.command(
    ApiEndpoints.notification(id),
    method: 'PATCH',
    data: <String, dynamic>{'isRead': true},
  );

  @override
  Future<Result<void>> markAllRead() =>
      client.command(ApiEndpoints.markAllNotificationsRead);

  @override
  Future<Result<int>> unreadCount() {
    return client.get<int>(
      ApiEndpoints.unreadCount,
      decoder: (envelope) => Json.integer(envelope.dataAsMap, const ['count']),
    );
  }
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>((
  ref,
) {
  ref.watch(accountIdProvider);
  return NotificationsRepositoryImpl(ref.watch(apiClientProvider));
});

class NotificationListNotifier extends PagedNotifier<AppNotification> {
  @override
  Future<PagedState<AppNotification>> build() {
    ref.watch(accountIdProvider);
    ref.watch(liveTopicProvider(LiveTopic.notifications));
    return super.build();
  }

  @override
  Future<Result<PaginatedList<AppNotification>>> fetchPage(int page) =>
      ref.read(notificationsRepositoryProvider).fetch(page: page);

  Future<void> markRead(String id) async {
    final result = await ref.read(notificationsRepositoryProvider).markRead(id);
    if (result.isOk) await refresh();
  }

  /// Marks everything read, and hands back the failure when it did not.
  ///
  /// This swallowed the failure: on an error the dots simply stayed, with
  /// nothing said, which reads as a broken button.
  Future<Failure?> markAllRead() async {
    final result = await ref
        .read(notificationsRepositoryProvider)
        .markAllRead();
    if (result.isOk) {
      await refresh();
      return null;
    }
    return result.failureOrNull;
  }
}

final notificationListProvider =
    AsyncNotifierProvider<
      NotificationListNotifier,
      PagedState<AppNotification>
    >(NotificationListNotifier.new);

/// Badge count for the app bar. Returns zero rather than failing loudly,
/// because a badge is not worth an error state.
final unreadNotificationCountProvider = FutureProvider<int>((ref) async {
  if (ref.watch(accountIdProvider) == null) return 0;
  ref.watch(liveTopicProvider(LiveTopic.notifications));
  final result = await ref.watch(notificationsRepositoryProvider).unreadCount();
  return result.valueOrNull ?? 0;
});
