import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/api_endpoints.dart';
import '../../../core/errors/result.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/utils/json_reader.dart';
import '../../auth/presentation/auth_providers.dart';

/// Ticket lifecycle (specification section 44).
/// What the ticket is about.
///
/// The dropdown used to list the bare API codes, so a customer chose
/// between "ORDER" and "PAYMENT" in English whatever their language.
/// The code the backend stores and the words the customer reads are two
/// different things.
enum TicketCategory {
  order('ORDER'),
  payment('PAYMENT'),
  delivery('DELIVERY'),
  returnRequest('RETURN'),
  product('PRODUCT'),
  account('ACCOUNT'),
  other('OTHER');

  const TicketCategory(this.apiValue);

  final String apiValue;
}

enum TicketStatus {
  open,
  inProgress,
  waitingForCustomer,
  resolved,
  closed,
  unknown;

  static TicketStatus fromApi(Object? value) =>
      switch (value?.toString().toUpperCase()) {
        'OPEN' => TicketStatus.open,
        'IN_PROGRESS' => TicketStatus.inProgress,
        'WAITING_FOR_CUSTOMER' => TicketStatus.waitingForCustomer,
        'RESOLVED' => TicketStatus.resolved,
        'CLOSED' => TicketStatus.closed,
        _ => TicketStatus.unknown,
      };
}

@immutable
class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.reference,
    required this.subject,
    required this.status,
    required this.createdAt,
    this.category,
    this.lastMessage,
    this.updatedAt,
  });

  final String id;
  final String reference;
  final String subject;
  final TicketStatus status;
  final DateTime createdAt;
  final String? category;
  final String? lastMessage;
  final DateTime? updatedAt;
}

@immutable
class TicketMessage {
  const TicketMessage({
    required this.id,
    required this.body,
    required this.sentAt,
    required this.isFromCustomer,
    this.authorName,
  });

  final String id;
  final String body;
  final DateTime sentAt;
  final bool isFromCustomer;
  final String? authorName;
}

abstract interface class SupportRepository {
  Future<Result<List<SupportTicket>>> tickets();

  Future<Result<SupportTicket>> ticket(String id);

  Future<Result<List<TicketMessage>>> messages(String ticketId);

  Future<Result<SupportTicket>> create({
    required String subject,
    required String category,
    required String description,
  });

  Future<Result<TicketMessage>> reply({
    required String ticketId,
    required String body,
  });
}

class SupportRepositoryImpl implements SupportRepository {
  const SupportRepositoryImpl(this.client);

  final ApiClient client;

  static SupportTicket _ticket(Map<String, dynamic> json) => SupportTicket(
    id: Json.str(json, const ['id', 'ticketId']),
    reference: Json.str(json, const ['reference', 'number', 'code']),
    subject: Json.str(json, const ['subject', 'title']),
    status: TicketStatus.fromApi(json['status']),
    createdAt:
        Json.date(json, const ['createdAt']) ??
        DateTime.fromMillisecondsSinceEpoch(0),
    category: Json.strOrNull(json, const ['category', 'type']),
    lastMessage: Json.strOrNull(json, const ['lastMessage']),
    updatedAt: Json.date(json, const ['updatedAt']),
  );

  static TicketMessage _message(Map<String, dynamic> json) => TicketMessage(
    id: Json.str(json, const ['id', 'messageId']),
    body: Json.str(json, const ['body', 'message', 'text']),
    sentAt:
        Json.date(json, const ['sentAt', 'createdAt']) ??
        DateTime.fromMillisecondsSinceEpoch(0),
    isFromCustomer: Json.boolean(json, const [
      'isFromCustomer',
      'isMine',
      'fromMe',
    ]),
    authorName: Json.strOrNull(json, const ['authorName', 'senderName']),
  );

  @override
  Future<Result<List<SupportTicket>>> tickets() {
    return client.get<List<SupportTicket>>(
      ApiEndpoints.supportTickets,
      decoder: (envelope) => Json.mapList(envelope.dataAsList, _ticket),
    );
  }

  @override
  Future<Result<SupportTicket>> ticket(String id) {
    return client.get<SupportTicket>(
      ApiEndpoints.supportTicket(id),
      decoder: (envelope) => _ticket(envelope.dataAsMap),
    );
  }

  @override
  Future<Result<List<TicketMessage>>> messages(String ticketId) {
    return client.get<List<TicketMessage>>(
      ApiEndpoints.supportTicketMessages(ticketId),
      decoder: (envelope) => Json.mapList(envelope.dataAsList, _message),
    );
  }

  @override
  Future<Result<SupportTicket>> create({
    required String subject,
    required String category,
    required String description,
  }) {
    return client.post<SupportTicket>(
      ApiEndpoints.supportTickets,
      data: <String, dynamic>{
        'subject': subject,
        'category': category,
        'description': description,
      },
      decoder: (envelope) => _ticket(envelope.dataAsMap),
    );
  }

  @override
  Future<Result<TicketMessage>> reply({
    required String ticketId,
    required String body,
  }) {
    return client.post<TicketMessage>(
      ApiEndpoints.supportTicketMessages(ticketId),
      data: <String, dynamic>{'body': body},
      decoder: (envelope) => _message(envelope.dataAsMap),
    );
  }
}

final supportRepositoryProvider = Provider<SupportRepository>((ref) {
  ref.watch(accountIdProvider);
  return SupportRepositoryImpl(ref.watch(apiClientProvider));
});

final supportTicketsProvider = FutureProvider<List<SupportTicket>>((ref) async {
  return (await ref.watch(supportRepositoryProvider).tickets()).unwrap();
});

final supportTicketProvider = FutureProvider.family<SupportTicket, String>((
  ref,
  id,
) async {
  return (await ref.watch(supportRepositoryProvider).ticket(id)).unwrap();
});

final ticketMessagesProvider =
    FutureProvider.family<List<TicketMessage>, String>((ref, id) async {
      return (await ref.watch(supportRepositoryProvider).messages(id)).unwrap();
    });
