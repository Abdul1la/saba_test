import 'package:flutter/material.dart';

import '../localization/failure_messages.dart';
import '../providers/paged_state.dart';
import '../theme/app_dimensions.dart';
import '../theme/saba_icons.dart';
import '../utils/context_extensions.dart';

/// Infinite-scrolling list or grid with pull-to-refresh.
///
/// Reads a [PagedState] and calls back when the user nears the end. Pass a
/// [gridDelegate] to render a grid instead of a list (specification
/// section 11).
class PagedListView<T> extends StatefulWidget {
  const PagedListView({
    super.key,
    required this.state,
    required this.itemBuilder,
    required this.onLoadMore,
    required this.onRefresh,
    this.onRetryLoadMore,
    this.emptyState,
    this.header,
    this.padding = const EdgeInsets.all(AppSpacing.screenGutter),
    this.gridDelegate,
    this.separatorHeight = AppSpacing.md,
    this.reloadOnReturn = true,
  });

  final PagedState<T> state;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final VoidCallback onLoadMore;
  final Future<void> Function() onRefresh;
  final VoidCallback? onRetryLoadMore;

  /// Shown when the first page came back empty.
  final Widget? emptyState;

  /// Optional content pinned above the collection, inside the same scroll view.
  final Widget? header;

  final EdgeInsets padding;
  final SliverGridDelegate? gridDelegate;
  final double separatorHeight;

  /// Read again on coming back to it - from a screen opened over it, or to
  /// the app - in place of the Refresh button the web had, which was
  /// clutter on a phone (the user). The pull still reloads it by hand.
  ///
  /// Off for a product grid: back from a product, a shopper deep in the
  /// results would be dropped to the first page, and nothing they do there
  /// changes the grid.
  final bool reloadOnReturn;

  @override
  State<PagedListView<T>> createState() => _PagedListViewState<T>();
}

class _PagedListViewState<T> extends State<PagedListView<T>>
    with WidgetsBindingObserver {
  /// Start fetching this far from the bottom so the next page is usually
  /// already there by the time the user arrives.
  static const double _loadMoreThreshold = 400;

  final _refresh = GlobalKey<RefreshIndicatorState>();

  /// Another screen is open over this one.
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    if (_covered && isCurrent) _reload();
    _covered = !isCurrent;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_covered) _reload();
  }

  /// After the frame: this runs while the screen is being built, and the
  /// list's provider cannot change then.
  void _reload() {
    if (!widget.reloadOnReturn) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onRefresh();
    });
  }

  bool _shouldLoadMore(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    final remaining =
        notification.metrics.maxScrollExtent - notification.metrics.pixels;
    return remaining <= _loadMoreThreshold;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;

    final isEmpty = state.isEmpty && widget.emptyState != null;

    // One shape, empty or not.
    //
    // The empty case used to return the RefreshIndicator bare while the
    // populated one wrapped it in this listener. Two different widget types
    // at the root of the same screen means that going from "some results" to
    // "none" tore down everything beneath it — the header included — and
    // built it again from scratch. Anything the header was holding went with
    // it: a search field in a storefront header lost the very word that had
    // just emptied the list, leaving a screen that said "nothing matches"
    // above an empty search box.
    //
    // Now only the sliver after the header differs, so the header keeps its
    // element, its state and its focus.
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (!isEmpty &&
            _shouldLoadMore(notification) &&
            state.hasMore &&
            !state.isLoadingMore &&
            state.loadMoreFailure == null) {
          widget.onLoadMore();
        }
        return false;
      },
      child: RefreshIndicator(
        key: _refresh,
        onRefresh: widget.onRefresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (widget.header != null) SliverToBoxAdapter(child: widget.header),
            if (isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: widget.emptyState!,
              )
            else ...[
              SliverPadding(
                padding: widget.padding,
                sliver: widget.gridDelegate != null
                    ? SliverGrid(
                        gridDelegate: widget.gridDelegate!,
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => widget.itemBuilder(
                            context,
                            state.items[index],
                            index,
                          ),
                          childCount: state.items.length,
                        ),
                      )
                    : SliverList.separated(
                        itemCount: state.items.length,
                        separatorBuilder: (_, _) =>
                            SizedBox(height: widget.separatorHeight),
                        itemBuilder: (context, index) => widget.itemBuilder(
                          context,
                          state.items[index],
                          index,
                        ),
                      ),
              ),
              SliverToBoxAdapter(child: _footer(context, state)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _footer(BuildContext context, PagedState<T> state) {
    if (state.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(
          child: SizedBox(
            height: 24,
            width: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }

    final failure = state.loadMoreFailure;
    if (failure != null) {
      // An append failure keeps the loaded pages visible and offers a retry
      // that only re-requests the page that failed.
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: [
            Text(
              failure.localizedMessage(context.l10n),
              textAlign: TextAlign.center,
              style: context.textStyles.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: widget.onRetryLoadMore,
              icon: SabaIcon(SabaIcons.refresh, size: AppSizes.iconMd),
              label: Text(context.l10n.retry),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, AppSizes.buttonHeightSmall),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(height: widget.padding.bottom);
  }
}
