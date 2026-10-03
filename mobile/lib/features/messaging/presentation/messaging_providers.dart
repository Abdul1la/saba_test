import 'dart:convert';
import 'dart:io' show File;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/api_endpoints.dart';
import '../../../core/config/app_config.dart';
import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_response.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/utils/json_reader.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../media/domain/entities.dart';

/// A conversation thread. The counterparty may be a merchant, support, or an
/// administrator (specification section 43).
@immutable
class Conversation {
  const Conversation({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.subtitle,
    this.avatarUrl,
    this.lastMessage,
    this.unreadCount = 0,
    this.lastMessageIsPhoto = false,
    this.blocked = false,
    this.blockedByMe = false,
  });

  final String id;
  final String title;
  final DateTime updatedAt;
  final String? subtitle;
  final String? avatarUrl;
  final String? lastMessage;
  final int unreadCount;

  /// The last message is a photo: [lastMessage] is null, and the row shows
  /// "Photo" in its place.
  final bool lastMessageIsPhoto;

  /// Either side has blocked the chat (Apple 1.2): nobody writes in it,
  /// and it stays readable.
  final bool blocked;

  /// This side's own block, which only this side can lift.
  final bool blockedByMe;
}

/// Why a chat photo is no longer shown: its sender's account was deleted, or
/// Saba took it down. The image is gone; a line stands in its place.
enum PhotoRemoval {
  account,
  saba;

  static PhotoRemoval? fromApi(Object? value) =>
      switch (value?.toString().toUpperCase()) {
        'ACCOUNT' => PhotoRemoval.account,
        'SABA' => PhotoRemoval.saba,
        _ => null,
      };
}

@immutable
class Message {
  const Message({
    required this.id,
    required this.body,
    required this.sentAt,
    required this.isMine,
    this.senderName,
    this.photoUrl,
    this.photoRemoved,
  });

  final String id;

  /// Empty for a photo message.
  final String body;
  final DateTime sentAt;

  /// True when the signed-in user sent it, as decided by the server.
  final bool isMine;

  final String? senderName;

  /// A signed link the server made, good for an hour or two; loaded as a
  /// plain image, no auth header. Null for a text message, or when the photo
  /// was removed ([photoRemoved]).
  final String? photoUrl;

  /// Set when the photo is gone: its sender's account was deleted, or Saba
  /// removed it. The bubble then shows a line, not an image.
  final PhotoRemoval? photoRemoved;

  /// A photo message, shown or removed, as against a text one.
  bool get isPhoto => photoUrl != null || photoRemoved != null;
}

abstract interface class MessagingRepository {
  Future<Result<List<Conversation>>> conversations();

  /// One thread's heading: who is on the other side.
  Future<Result<Conversation>> conversation(String conversationId);

  /// The customer's chat with a store: the one already there, or a new one.
  Future<Result<Conversation>> startWithStore(String merchantId);

  Future<Result<PaginatedList<Message>>> messages(
    String conversationId, {
    int page = 1,
  });

  Future<Result<Message>> send({
    required String conversationId,
    required String body,
  });

  /// Sends a photo, shrunk and re-encoded by the picker, as multipart. A
  /// blocked chat is refused with a [ConflictFailure] (409 chat.blocked); a
  /// file that is not an image, or over the limit, with a [ValidationFailure].
  Future<Result<Message>> sendPhoto({
    required String conversationId,
    required PickedMedia photo,
  });

  Future<Result<void>> markRead(String conversationId);

  /// Blocks the other side, or lifts this side's block.
  Future<Result<Conversation>> setBlocked(
    String conversationId, {
    required bool blocked,
  });
}

class MessagingRepositoryImpl implements MessagingRepository {
  const MessagingRepositoryImpl(this.client);

  final ApiClient client;

  static Conversation _conversation(Map<String, dynamic> json) => Conversation(
    id: Json.str(json, const ['id', 'conversationId']),
    title: Json.str(json, const ['title', 'name', 'counterpartyName']),
    updatedAt:
        Json.date(json, const ['updatedAt', 'lastMessageAt']) ??
        DateTime.fromMillisecondsSinceEpoch(0),
    subtitle: Json.strOrNull(json, const ['subtitle', 'context', 'topic']),
    avatarUrl: Json.strOrNull(json, const ['avatarUrl', 'logoUrl']),
    lastMessage: Json.strOrNull(json, const ['lastMessage', 'lastMessageBody']),
    unreadCount: Json.integer(json, const ['unreadCount', 'unread']),
    lastMessageIsPhoto: Json.boolean(json, const ['lastMessageIsPhoto']),
    blocked: Json.boolean(json, const ['blocked']),
    blockedByMe: Json.boolean(json, const ['blockedByMe']),
  );

  static Message _message(Map<String, dynamic> json) => Message(
    id: Json.str(json, const ['id', 'messageId']),
    body: Json.str(json, const ['body', 'text', 'content']),
    sentAt:
        Json.date(json, const ['sentAt', 'createdAt']) ??
        DateTime.fromMillisecondsSinceEpoch(0),
    isMine: Json.boolean(json, const ['isMine', 'isOwn', 'fromMe']),
    senderName: Json.strOrNull(json, const ['senderName', 'authorName']),
    photoUrl: Json.strOrNull(json, const ['photoUrl']),
    photoRemoved: PhotoRemoval.fromApi(json['photoRemoved']),
  );

  @override
  Future<Result<List<Conversation>>> conversations() {
    return client.get<List<Conversation>>(
      ApiEndpoints.conversations,
      decoder: (envelope) => Json.mapList(envelope.dataAsList, _conversation),
    );
  }

  @override
  Future<Result<Conversation>> conversation(String conversationId) {
    return client.get<Conversation>(
      ApiEndpoints.conversation(conversationId),
      decoder: (envelope) => _conversation(envelope.dataAsMap),
    );
  }

  @override
  Future<Result<Conversation>> startWithStore(String merchantId) {
    return client.post<Conversation>(
      ApiEndpoints.conversations,
      data: <String, dynamic>{'merchantId': merchantId},
      decoder: (envelope) => _conversation(envelope.dataAsMap),
    );
  }

  @override
  Future<Result<PaginatedList<Message>>> messages(
    String conversationId, {
    int page = 1,
  }) {
    return client.getPage<Message>(
      ApiEndpoints.conversationMessages(conversationId),
      page: page,
      itemDecoder: _message,
    );
  }

  @override
  Future<Result<Message>> send({
    required String conversationId,
    required String body,
  }) {
    return client.post<Message>(
      ApiEndpoints.conversationMessages(conversationId),
      data: <String, dynamic>{'body': body},
      decoder: (envelope) => _message(envelope.dataAsMap),
    );
  }

  @override
  Future<Result<Message>> sendPhoto({
    required String conversationId,
    required PickedMedia photo,
  }) async {
    final endpoint = ApiEndpoints.conversationPhotos(conversationId);
    // The demo has no file server, so it keeps the picture itself: the bytes
    // the picker already holds, as a data URL the chat draws straight from
    // memory (the same trick product photos use). The real server takes the
    // file as multipart and signs a link back.
    if (AppConfig.isDemoMode) {
      final bytes = photo.bytes ?? await _bytesOf(photo.path);
      if (bytes == null) {
        return const Err<Message>(ValidationFailure(statusCode: null));
      }
      return client.post<Message>(
        endpoint,
        data: <String, dynamic>{
          'photoDataUrl':
              'data:${photo.mimeType};base64,${base64Encode(bytes)}',
        },
        decoder: (envelope) => _message(envelope.dataAsMap),
      );
    }

    final FormData formData;
    try {
      formData = FormData.fromMap(<String, dynamic>{
        'file': photo.bytes != null
            ? MultipartFile.fromBytes(photo.bytes!, filename: photo.fileName)
            : await MultipartFile.fromFile(
                photo.path!,
                filename: photo.fileName,
              ),
      });
    } on Object {
      return const Err<Message>(ValidationFailure(statusCode: null));
    }
    return client.upload<Message>(
      endpoint,
      formData: formData,
      decoder: (envelope) => _message(envelope.dataAsMap),
    );
  }

  static Future<Uint8List?> _bytesOf(String? path) async {
    if (path == null) return null;
    try {
      return await File(path).readAsBytes();
    } on Object {
      return null;
    }
  }

  @override
  Future<Result<void>> markRead(String conversationId) =>
      client.command(ApiEndpoints.markConversationRead(conversationId));

  @override
  Future<Result<Conversation>> setBlocked(
    String conversationId, {
    required bool blocked,
  }) => blocked
      ? client.post<Conversation>(
          ApiEndpoints.conversationBlock(conversationId),
          decoder: (envelope) => _conversation(envelope.dataAsMap),
        )
      : client.delete<Conversation>(
          ApiEndpoints.conversationBlock(conversationId),
          decoder: (envelope) => _conversation(envelope.dataAsMap),
        );
}

final messagingRepositoryProvider = Provider<MessagingRepository>((ref) {
  ref.watch(accountIdProvider);
  return MessagingRepositoryImpl(ref.watch(apiClientProvider));
});

/// The signed-in account's chats; none while signed out. Keyed to who is
/// signed in, so the next account never opens on the last one's inbox.
final conversationsProvider = FutureProvider<List<Conversation>>((ref) async {
  final who = ref.watch(
    currentUserProvider.select(
      (user) => user == null ? null : (user.email, user.phone),
    ),
  );
  if (who == null) return const <Conversation>[];
  return (await ref.watch(messagingRepositoryProvider).conversations())
      .unwrap();
});

/// Messages waiting to be read, across every chat: the dot on the chat
/// icon and the count on the Messages row.
final unreadMessageCountProvider = Provider<int>(
  (ref) =>
      ref
          .watch(conversationsProvider)
          .value
          ?.fold<int>(0, (sum, chat) => sum + chat.unreadCount) ??
      0,
);

/// Who a thread is with, for the top of the chat.
final conversationInfoProvider = FutureProvider.family<Conversation, String>(
  (ref, id) async =>
      (await ref.watch(messagingRepositoryProvider).conversation(id)).unwrap(),
);

/// Messages in one thread, newest last.
///
/// The repository is polled on demand rather than streamed; the domain is
/// shaped so a WebSocket can push into this controller later without any
/// change to the UI (specification section 43).
class ConversationController extends AsyncNotifier<List<Message>> {
  ConversationController(this.conversationId);

  final String conversationId;

  MessagingRepository get _repository => ref.read(messagingRepositoryProvider);

  @override
  Future<List<Message>> build() async {
    ref.watch(accountIdProvider);
    final page = (await _repository.messages(conversationId)).unwrap();
    // The API returns newest first; the chat view reads oldest first.
    final messages = page.items.reversed.toList();
    await _repository.markRead(conversationId);
    // Read now, so the dot and the count go out.
    ref.invalidate(conversationsProvider);
    return messages;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() async {
      final page = (await _repository.messages(conversationId)).unwrap();
      return page.items.reversed.toList();
    });
  }

  Future<Result<Message>> send(String body) async {
    final result = await _repository.send(
      conversationId: conversationId,
      body: body,
    );

    if (result case Ok<Message>(:final value)) {
      _append(value);
    }

    return result;
  }

  Future<Result<Message>> sendPhoto(PickedMedia photo) async {
    final result = await _repository.sendPhoto(
      conversationId: conversationId,
      photo: photo,
    );
    if (result case Ok<Message>(:final value)) {
      _append(value);
    }
    return result;
  }

  void _append(Message message) {
    state = AsyncValue<List<Message>>.data(<Message>[
      ...state.value ?? const <Message>[],
      message,
    ]);
    ref.invalidate(conversationsProvider);
  }
}

final conversationProvider =
    AsyncNotifierProvider.family<ConversationController, List<Message>, String>(
      ConversationController.new,
    );
