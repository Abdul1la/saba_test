import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/failure.dart';
import '../errors/result.dart';
import '../network/api_response.dart';
import 'core_providers.dart';

/// State of an infinitely scrolling list.
///
/// The first page is represented by the surrounding `AsyncValue`; everything
/// after it lives in [isLoadingMore] and [loadMoreFailure], so a failure while
/// appending page 4 never wipes out the three pages already on screen.
@immutable
class PagedState<T> {
  const PagedState({
    required this.items,
    required this.meta,
    this.isLoadingMore = false,
    this.loadMoreFailure,
  });

  final List<T> items;
  final PaginationMeta meta;
  final bool isLoadingMore;
  final Failure? loadMoreFailure;

  bool get hasMore => meta.hasNextPage;
  bool get isEmpty => items.isEmpty;
  int get total => meta.total;

  PagedState<T> copyWith({
    List<T>? items,
    PaginationMeta? meta,
    bool? isLoadingMore,
    Failure? loadMoreFailure,
    bool clearFailure = false,
  }) {
    return PagedState<T>(
      items: items ?? this.items,
      meta: meta ?? this.meta,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      loadMoreFailure: clearFailure
          ? null
          : (loadMoreFailure ?? this.loadMoreFailure),
    );
  }
}

/// Base class for any paginated list controller.
///
/// A feature supplies [fetchPage] and gets first-page loading, append, retry
/// and refresh for free — so pagination is written once rather than in every
/// list screen.
abstract class PagedNotifier<T> extends AsyncNotifier<PagedState<T>> {
  /// Loads a single page from the repository.
  Future<Result<PaginatedList<T>>> fetchPage(int page);

  @override
  Future<PagedState<T>> build() async {
    // A list reads its repository when it pages, not when it is built, so it
    // follows a language switch here: the names come back in the new one.
    ref.watch(acceptLanguageProvider);
    final page = (await fetchPage(1)).unwrap();
    return PagedState<T>(items: page.items, meta: page.meta);
  }

  /// Appends the next page. Safe to call repeatedly from a scroll listener:
  /// it ignores calls while a fetch is in flight or when the list is complete.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.isLoadingMore || !current.hasMore) return;

    state = AsyncValue<PagedState<T>>.data(
      current.copyWith(isLoadingMore: true, clearFailure: true),
    );

    final result = await fetchPage(current.meta.nextPage);

    // The provider may have been disposed while the request was in flight.
    if (!ref.mounted) return;

    state = AsyncValue<PagedState<T>>.data(
      result.fold(
        ok: (page) => current.copyWith(
          items: <T>[...current.items, ...page.items],
          meta: page.meta,
          isLoadingMore: false,
          clearFailure: true,
        ),
        err: (failure) =>
            current.copyWith(isLoadingMore: false, loadMoreFailure: failure),
      ),
    );
  }

  /// Re-fetches from page one. Used by pull-to-refresh.
  Future<void> refresh() async {
    state = await AsyncValue.guard(() async {
      final page = (await fetchPage(1)).unwrap();
      return PagedState<T>(items: page.items, meta: page.meta);
    });
  }

  /// Retries only the failed append, keeping what is already displayed.
  Future<void> retryLoadMore() async {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue<PagedState<T>>.data(
      current.copyWith(clearFailure: true),
    );
    await loadMore();
  }
}
