import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/api_endpoints.dart';
import '../../../core/errors/result.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/utils/json_reader.dart';
import '../../auth/presentation/auth_providers.dart';

/// One autocomplete row.
@immutable
class SearchSuggestion {
  const SearchSuggestion({
    required this.text,
    this.type = 'QUERY',
    this.categoryId,
    this.productId,
  });

  final String text;

  /// QUERY | PRODUCT | CATEGORY | BRAND
  final String type;

  final String? categoryId;
  final String? productId;
}

abstract interface class SearchRepository {
  Future<Result<List<SearchSuggestion>>> suggestions(String term);

  Future<Result<List<String>>> popularSearches();

  Future<Result<List<String>>> history();

  Future<Result<void>> clearHistory();
}

class SearchRepositoryImpl implements SearchRepository {
  const SearchRepositoryImpl(this.client);

  final ApiClient client;

  @override
  Future<Result<List<SearchSuggestion>>> suggestions(String term) {
    return client.get<List<SearchSuggestion>>(
      ApiEndpoints.searchSuggestions,
      queryParameters: <String, dynamic>{'q': term},
      decoder: (envelope) => Json.mapList(
        envelope.dataAsList,
        (json) => SearchSuggestion(
          text: Json.str(json, const ['text', 'term', 'value', 'name']),
          type: Json.str(json, const ['type'], fallback: 'QUERY'),
          categoryId: Json.strOrNull(json, const ['categoryId']),
          productId: Json.strOrNull(json, const ['productId']),
        ),
      ),
    );
  }

  @override
  Future<Result<List<String>>> popularSearches() {
    return client.get<List<String>>(
      ApiEndpoints.popularSearches,
      decoder: (envelope) => envelope.dataAsList
          .map((json) => Json.str(json, const ['text', 'term', 'value']))
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
    );
  }

  @override
  Future<Result<List<String>>> history() {
    return client.get<List<String>>(
      ApiEndpoints.searchHistory,
      decoder: (envelope) => envelope.dataAsList
          .map((json) => Json.str(json, const ['text', 'term', 'query']))
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
    );
  }

  @override
  Future<Result<void>> clearHistory() =>
      client.command(ApiEndpoints.searchHistory, method: 'DELETE');
}

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  ref.watch(accountIdProvider);
  return SearchRepositoryImpl(ref.watch(apiClientProvider));
});

/// The term currently typed into the search field. Gone with the search page:
/// kept, the page opened again with an empty box but the last word's
/// suggestions, and no recent or popular searches.
class SearchTermController extends Notifier<String> {
  @override
  String build() {
    ref.watch(accountIdProvider);
    return '';
  }

  void setTerm(String value) => state = value;
}

final searchTermProvider =
    NotifierProvider.autoDispose<SearchTermController, String>(
      SearchTermController.new,
    );

/// Suggestions for the current term.
///
/// Debounced so a fast typist produces one request per pause rather than one
/// per keystroke.
final searchSuggestionsProvider =
    FutureProvider.family<List<SearchSuggestion>, String>((ref, term) async {
      final trimmed = term.trim();
      if (trimmed.length < 2) return const <SearchSuggestion>[];

      await Future<void>.delayed(const Duration(milliseconds: 300));
      // If the user typed again during the delay this provider is already disposed.
      if (!ref.mounted) return const <SearchSuggestion>[];

      final result = await ref
          .read(searchRepositoryProvider)
          .suggestions(trimmed);
      // Suggestions are a convenience: a failure here should not take over the
      // screen, so an empty list is returned instead of throwing.
      return result.valueOrNull ?? const <SearchSuggestion>[];
    });

/// Read each time the search page opens, not once for the life of the app:
/// a search made since then counts.
final popularSearchesProvider = FutureProvider.autoDispose<List<String>>((
  ref,
) async {
  final result = await ref.watch(searchRepositoryProvider).popularSearches();
  return result.valueOrNull ?? const <String>[];
});

/// Server-side history for signed-in customers; the device-local list in
/// `AppPreferences` covers guests.
final searchHistoryProvider = FutureProvider<List<String>>((ref) async {
  final result = await ref.watch(searchRepositoryProvider).history();
  return result.valueOrNull ?? const <String>[];
});
