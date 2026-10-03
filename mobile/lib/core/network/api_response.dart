import 'package:flutter/foundation.dart';

/// Pagination information carried in the `meta` object of a list response.
@immutable
class PaginationMeta {
  const PaginationMeta({
    required this.page,
    required this.perPage,
    required this.total,
    required this.totalPages,
    this.nextCursor,
  });

  factory PaginationMeta.fromJson(Map<String, dynamic>? json) {
    final meta = json ?? const <String, dynamic>{};
    // Tolerate either a flat meta object or `meta.pagination`.
    final source = meta['pagination'] is Map
        ? Map<String, dynamic>.from(meta['pagination'] as Map)
        : meta;
    final page = _toInt(source['page']) ?? 1;
    final perPage = _toInt(source['perPage'] ?? source['per_page']) ?? 0;
    final total = _toInt(source['total'] ?? source['totalItems']) ?? 0;
    final totalPages =
        _toInt(source['totalPages'] ?? source['total_pages']) ??
        (perPage > 0 ? (total / perPage).ceil() : 1);
    return PaginationMeta(
      page: page,
      perPage: perPage,
      total: total,
      totalPages: totalPages,
      nextCursor: (source['nextCursor'] ?? source['next_cursor'])?.toString(),
    );
  }

  const PaginationMeta.empty()
    : page = 1,
      perPage = 0,
      total = 0,
      totalPages = 1,
      nextCursor = null;

  final int page;
  final int perPage;
  final int total;
  final int totalPages;
  final String? nextCursor;

  bool get hasNextPage => nextCursor != null || page < totalPages;
  int get nextPage => page + 1;

  static int? _toInt(Object? value) => switch (value) {
    final int v => v,
    final num v => v.toInt(),
    final String v => int.tryParse(v),
    _ => null,
  };
}

/// A page of results plus the pagination metadata that produced it.
@immutable
class PaginatedList<T> {
  const PaginatedList({required this.items, required this.meta});

  const PaginatedList.empty()
    : items = const [],
      meta = const PaginationMeta.empty();

  final List<T> items;
  final PaginationMeta meta;

  bool get isEmpty => items.isEmpty;
  bool get hasNextPage => meta.hasNextPage;

  /// Appends the next page, used by infinite-scroll controllers.
  PaginatedList<T> append(PaginatedList<T> next) =>
      PaginatedList<T>(items: <T>[...items, ...next.items], meta: next.meta);
}

/// The success envelope defined in specification section 54:
/// `{ "success": true, "message": "...", "data": {}, "meta": {} }`
@immutable
class ApiEnvelope {
  const ApiEnvelope({
    required this.success,
    required this.message,
    required this.data,
    required this.meta,
  });

  factory ApiEnvelope.fromResponse(Object? body) {
    if (body is Map<String, dynamic>) {
      // A well-formed envelope.
      if (body.containsKey('success') || body.containsKey('data')) {
        return ApiEnvelope(
          success: body['success'] as bool? ?? true,
          message: body['message']?.toString() ?? '',
          data: body['data'],
          meta: body['meta'] is Map
              ? Map<String, dynamic>.from(body['meta'] as Map)
              : const <String, dynamic>{},
        );
      }
      // A bare object: treat the whole body as the payload.
      return ApiEnvelope(
        success: true,
        message: '',
        data: body,
        meta: const <String, dynamic>{},
      );
    }
    return ApiEnvelope(
      success: true,
      message: '',
      data: body,
      meta: const <String, dynamic>{},
    );
  }

  final bool success;
  final String message;
  final Object? data;
  final Map<String, dynamic> meta;

  Map<String, dynamic> get dataAsMap => data is Map
      ? Map<String, dynamic>.from(data! as Map)
      : const <String, dynamic>{};

  /// Accepts `data: [...]` as well as `data: { items: [...] }`.
  List<Map<String, dynamic>> get dataAsList {
    final payload = data;
    if (payload is List) {
      return payload
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList(growable: false);
    }
    if (payload is Map) {
      for (final key in const ['items', 'results', 'records', 'rows']) {
        final nested = payload[key];
        if (nested is List) {
          return nested
              .whereType<Map>()
              .map(Map<String, dynamic>.from)
              .toList(growable: false);
        }
      }
    }
    return const <Map<String, dynamic>>[];
  }

  /// Pagination may sit in `meta`, or beside the items inside `data`.
  PaginationMeta get pagination {
    if (meta.isNotEmpty) return PaginationMeta.fromJson(meta);
    final payload = data;
    if (payload is Map && payload['meta'] is Map) {
      return PaginationMeta.fromJson(
        Map<String, dynamic>.from(payload['meta'] as Map),
      );
    }
    return const PaginationMeta.empty();
  }
}
