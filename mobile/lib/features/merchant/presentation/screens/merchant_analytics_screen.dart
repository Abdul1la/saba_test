import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/dark_header_card.dart';
import '../../../../core/widgets/filter_chip_row.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/skeletons.dart';
import '../../domain/entities.dart';
import '../merchant_providers.dart';
import '../widgets/merchant_widgets.dart';
import '../../../../core/widgets/saba_nav_bar.dart';

/// Merchant analytics (specification section 28).
///
/// Laid out like the dashboard's revenue card, which is the part of the
/// merchant app people already read: the period's revenue large on the dark
/// card with its growth and its bars, then the figures behind it, then what
/// sold. "Today" is gone - a day is too short to chart, and the dashboard
/// already answers "how is today going".
class MerchantAnalyticsScreen extends ConsumerStatefulWidget {
  const MerchantAnalyticsScreen({super.key});

  @override
  ConsumerState<MerchantAnalyticsScreen> createState() =>
      _MerchantAnalyticsScreenState();
}

class _MerchantAnalyticsScreenState
    extends ConsumerState<MerchantAnalyticsScreen> {
  static const List<String> _periods = <String>['week', 'month', 'year'];

  int _selected = 1;

  String get _period => _periods[_selected];

  String _periodLabel(String period) {
    final l10n = context.l10n;
    return switch (period) {
      'week' => l10n.thisWeek,
      'month' => l10n.thisMonth,
      _ => l10n.thisYear,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final market = context.market;
    final analytics = ref.watch(merchantAnalyticsProvider(_period));

    return Scaffold(
      body: Column(
        children: [
          PageTitle(title: l10n.analytics),
          const SizedBox(height: AppSpacing.lg),
          // The same pill row as every other filter in the app, rather than
          // Material's segmented control with its tick.
          TextFilterChips(
            labels: [for (final period in _periods) _periodLabel(period)],
            selectedIndex: _selected,
            onSelected: (index) => setState(() => _selected = index),
          ),
          const SizedBox(height: AppSpacing.md + 2),
          Expanded(
            child: AsyncStateView<MerchantAnalytics>(
              value: analytics,
              onRetry: () => ref.invalidate(merchantAnalyticsProvider(_period)),
              loadingBuilder: (_) => const ListSkeleton(itemHeight: 96),
              builder: (data) {
                final locale = l10n.locale.toLanguageTag();

                String money(num value) => Formatters.money(
                  value,
                  locale: locale,
                  currencyCode: data.currencyCode,
                );

                // One colour per figure, so each is found by its colour.
                final metrics = <Widget>[
                  MetricCard(
                    label: l10n.totalOrders,
                    value: '${data.orderCount}',
                    icon: SabaIcons.receipt,
                    accent: market.info,
                  ),
                  MetricCard(
                    label: l10n.productsSold,
                    value: '${data.productsSold}',
                    icon: SabaIcons.shoppingBag,
                    accent: market.accent,
                  ),
                  MetricCard(
                    label: l10n.averageOrderValue,
                    value: money(data.averageOrderValue),
                    icon: SabaIcons.barChart,
                    accent: market.success,
                  ),
                  MetricCard(
                    label: l10n.refunds,
                    value: money(data.refundTotal),
                    icon: SabaIcons.coin,
                    accent: context.colors.error,
                  ),
                ];

                return RefreshIndicator(
                  onRefresh: () =>
                      ref.refresh(merchantAnalyticsProvider(_period).future),
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.screenGutter,
                      0,
                      AppSpacing.screenGutter,
                      SabaNavBar.clearance(context),
                    ),
                    children: [
                      WhiteHeader(
                        child: _RevenueCard(
                          data: data,
                          title: '${l10n.revenue} · ${_periodLabel(_period)}',
                          money: money,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      // Rows rather than a grid with a guessed aspect ratio:
                      // each pair is as tall as its taller card, at any text
                      // size.
                      for (var index = 0; index < metrics.length; index += 2)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: metrics[index]),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(child: metrics[index + 1]),
                              ],
                            ),
                          ),
                        ),
                      _CancellationsRow(count: data.cancellationCount),
                      if (data.topProducts.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xl),
                        SectionCard(
                          title: l10n.topProducts,
                          child: Column(
                            children: [
                              for (
                                var index = 0;
                                index < data.topProducts.length;
                                index++
                              )
                                _TopProductRow(
                                  rank: index + 1,
                                  product: data.topProducts[index],
                                  price: Formatters.money(
                                    data.topProducts[index].price,
                                    locale: locale,
                                    currencyCode:
                                        data.topProducts[index].currencyCode,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The period's revenue, drawn the way the dashboard draws the month's.
class _RevenueCard extends StatelessWidget {
  const _RevenueCard({
    required this.data,
    required this.title,
    required this.money,
  });

  final MerchantAnalytics data;
  final String title;
  final String Function(num) money;

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    final previous = data.previousRevenue;
    // Only when the backend sent something to compare against.
    final delta = (previous != null && previous > 0)
        ? ((data.revenue - previous) / previous) * 100
        : null;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg + 2),
      decoration: BoxDecoration(
        color: market.surfaceDark,
        border: Border.all(color: market.onDarkBorder),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.labelSmall?.copyWith(
                    color: market.onDarkMuted,
                  ),
                ),
              ),
              if (delta != null) DeltaPill(percent: delta),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              money(data.revenue),
              maxLines: 1,
              style: context.textStyles.displaySmall?.copyWith(
                fontSize: 28,
                color: market.onDark,
              ),
            ),
          ),
          if (previous != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              '${context.l10n.previousPeriod}: ${money(previous)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textStyles.labelSmall?.copyWith(
                color: market.onDarkMuted,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          SalesBarChart(points: data.series, height: 120, onDark: true),
        ],
      ),
    );
  }
}

/// Cancellations, on a row of its own: a count to watch, not a total.
class _CancellationsRow extends StatelessWidget {
  const _CancellationsRow({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final market = context.market;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md + 2),
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border.all(color: market.border),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          Container(
            width: AppSizes.tileIcon,
            height: AppSizes.tileIcon,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: market.warningSoft,
              borderRadius: BorderRadius.circular(AppRadius.action),
            ),
            child: SabaIcon(
              SabaIcons.alertCircle,
              size: AppSizes.iconMd,
              color: market.warning,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              context.l10n.cancellations,
              style: context.textStyles.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            '$count',
            style: context.textStyles.titleLarge?.copyWith(
              fontSize: 19,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// One best seller: its place, its picture, its name and price.
class _TopProductRow extends StatelessWidget {
  const _TopProductRow({
    required this.rank,
    required this.product,
    required this.price,
  });

  final int rank;
  final MerchantProductRow product;
  final String price;

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    // The best seller is lit; the next two are warm; the rest are quiet.
    final (fill, ink) = switch (rank) {
      1 => (market.accent, market.onAccent),
      2 || 3 => (market.accentSoft, market.accent),
      _ => (market.surfaceMuted, context.colors.onSurfaceVariant),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
            child: Text(
              '$rank',
              style: context.textStyles.labelMedium?.copyWith(
                color: ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          AppNetworkImage(
            url: product.imageUrl,
            width: 44,
            height: 44,
            radius: AppRadius.action,
            fallbackIcon: SabaIcons.box,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              product.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.textStyles.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            price,
            style: context.textStyles.titleSmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
