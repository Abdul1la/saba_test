import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/paged_state.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/paged_list_view.dart';
import '../../../../core/widgets/results_chrome.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../auth/presentation/auth_providers.dart';
import '../../domain/entities.dart';
import '../reviews_providers.dart';
import '../widgets/report_dialog.dart';
import '../widgets/review_card.dart';

/// G9 — reviews of a store (specification section 22).
///
/// ponytail: a separate screen off the storefront header rather than a tab
/// inside it. The storefront is one paged product grid, so adding a TabBar
/// would mean restructuring it; upgrade to a real tab if the storefront grows
/// more sections.
class MerchantReviewsScreen extends ConsumerWidget {
  const MerchantReviewsScreen({super.key, required this.merchantId});

  final String merchantId;

  Future<void> _report(
    BuildContext context,
    WidgetRef ref,
    Review review,
  ) async {
    // As every other report: a guest signs in first. It was asked why, then
    // shown the server's refusal.
    if (!ref.read(isAuthenticatedProvider)) {
      context.push(AppRoutes.login);
      return;
    }
    final choice = await ReportDialog.show(context);
    if (choice == null || !context.mounted) return;

    final result = await ref
        .read(reviewsRepositoryProvider)
        .reportReview(
          reviewId: review.id,
          reason: choice.apiValue,
          description: choice.description,
        );
    if (!context.mounted) return;
    result.fold(
      ok: (_) => AppSnackBar.success(context, context.l10n.reportSubmitted),
      err: (failure) => AppSnackBar.failure(context, failure),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(merchantReviewsProvider(merchantId));
    final notifier = ref.read(merchantReviewsProvider(merchantId).notifier);

    return Scaffold(
      appBar: SabaAppBar(title: l10n.storeReviews),
      body: SafeArea(
        top: false,
        child: AsyncStateView<PagedState<Review>>(
          value: state,
          onRetry: () => ref.invalidate(merchantReviewsProvider(merchantId)),
          builder: (paged) => PagedListView<Review>(
            state: paged,
            onLoadMore: notifier.loadMore,
            onRefresh: notifier.refresh,
            onRetryLoadMore: notifier.retryLoadMore,
            separatorHeight: AppSpacing.md + 2,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.sm,
              AppSpacing.screenGutter,
              AppSpacing.xxl,
            ),
            emptyState: NoResultsView(
              icon: SabaIcons.store,
              title: l10n.noReviews,
              message: l10n.noReviewsMessage,
            ),
            itemBuilder: (context, review, _) => ReviewCard(
              review: review,
              onReport: () => _report(context, ref, review),
            ),
          ),
        ),
      ),
    );
  }
}
