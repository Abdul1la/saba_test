import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/error_mapper.dart';
import 'state_views.dart';

/// Renders the three states of an [AsyncValue] consistently.
///
/// Using this everywhere is what makes loading, error and retry behave the
/// same on every screen, and it guarantees no screen silently swallows an
/// error (specification section 72).
class AsyncStateView<T> extends StatelessWidget {
  const AsyncStateView({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
    this.loadingBuilder,
    this.compactError = false,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  /// Supply a skeleton here instead of the default spinner.
  final WidgetBuilder? loadingBuilder;

  final bool compactError;

  @override
  Widget build(BuildContext context) {
    return value.when(
      // A pull-to-refresh keeps the current content on screen rather than
      // flashing a spinner over it.
      skipLoadingOnRefresh: true,
      data: builder,
      loading: () => loadingBuilder?.call(context) ?? const LoadingView(),
      error: (error, _) => AppErrorView(
        failure: ErrorMapper.fromObject(error),
        onRetry: onRetry,
        compact: compactError,
      ),
    );
  }
}

/// Sliver flavour, for use inside a `CustomScrollView`.
class SliverAsyncStateView<T> extends StatelessWidget {
  const SliverAsyncStateView({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
    this.loadingBuilder,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;
  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: AsyncStateView<T>(
        value: value,
        builder: builder,
        onRetry: onRetry,
        loadingBuilder: loadingBuilder,
        compactError: true,
      ),
    );
  }
}
