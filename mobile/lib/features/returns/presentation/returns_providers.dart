import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/result.dart';
import '../../../core/network/api_response.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/providers/paged_state.dart';
import '../data/returns_repository_impl.dart';
import '../domain/entities.dart';
import '../domain/returns_repository.dart';
import '../../auth/presentation/auth_providers.dart';

final returnsRepositoryProvider = Provider<ReturnsRepository>((ref) {
  ref.watch(accountIdProvider);
  return ReturnsRepositoryImpl(ref.watch(apiClientProvider));
});

/// Paginated return requests for one status filter. `null` means "all".
class ReturnListNotifier extends PagedNotifier<ReturnSummary> {
  ReturnListNotifier(this.status);

  final ReturnStatus? status;

  @override
  Future<PagedState<ReturnSummary>> build() {
    ref.watch(accountIdProvider);
    return super.build();
  }

  @override
  Future<Result<PaginatedList<ReturnSummary>>> fetchPage(int page) {
    return ref
        .read(returnsRepositoryProvider)
        .fetchReturns(status: status, page: page);
  }
}

final returnListProvider =
    AsyncNotifierProvider.family<
      ReturnListNotifier,
      PagedState<ReturnSummary>,
      ReturnStatus?
    >(ReturnListNotifier.new);

final returnDetailProvider = FutureProvider.family<ReturnDetail, String>((
  ref,
  id,
) async {
  return (await ref.watch(returnsRepositoryProvider).fetchReturn(id)).unwrap();
});
