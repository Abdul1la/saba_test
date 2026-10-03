import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/skeletons.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../domain/entities.dart';
import '../merchant_providers.dart';

/// What the store owes Saba: one rate on what it delivered, billed monthly.
/// The shopper pays the store's driver in cash, so the money is the store's
/// and Saba's share is what it pays back.
///
/// Every figure is read from the server; nothing is worked out here.
class MerchantPayoutsScreen extends ConsumerWidget {
  const MerchantPayoutsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: SabaAppBar(
        title: l10n.oweSaba,
        backFallback: AppRoutes.merchantDashboard,
      ),
      body: AsyncStateView<SabaBills>(
        value: ref.watch(sabaBillsProvider),
        onRetry: () => ref.invalidate(sabaBillsProvider),
        loadingBuilder: (_) => const ListSkeleton(itemHeight: 72),
        builder: (bills) {
          final locale = l10n.locale.toLanguageTag();
          String money(num value) => Formatters.money(
            value,
            locale: locale,
            currencyCode: bills.currencyCode,
          );
          final now = bills.current;

          return RefreshIndicator(
            onRefresh: () => ref.refresh(sabaBillsProvider.future),
            child: ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
              children: [
                Container(
                  margin: const EdgeInsets.all(AppSpacing.screenGutter),
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  // A dark surface, not a button: navy, not the purple.
                  decoration: BoxDecoration(
                    color: context.market.surfaceDark,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.oweThisMonth,
                        style: context.textStyles.labelMedium?.copyWith(
                          color: context.market.onDarkMuted,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        money(now.owed),
                        style: context.textStyles.displaySmall?.copyWith(
                          color: context.market.onDark,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenGutter,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      border: Border.all(color: context.market.border),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Column(
                      children: [
                        _Line(
                          label:
                              '${l10n.deliveredSales} '
                              '(${l10n.counted(now.orderCount, CountNoun.order)})',
                          value: money(now.sales),
                        ),
                        if (now.returned > 0)
                          _Line(
                            label: l10n.returnedCash,
                            value: Formatters.deduction(
                              now.returned,
                              locale: locale,
                              currencyCode: bills.currencyCode,
                            ),
                          ),
                        _Line(
                          label: '${l10n.sabaShare} (${bills.ratePercent}%)',
                          value: money(now.owed),
                        ),
                        const Divider(height: AppSpacing.xxl),
                        _Line(
                          label: l10n.youOwe,
                          value: money(now.owed),
                          emphasize: true,
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenGutter,
                    AppSpacing.md,
                    AppSpacing.screenGutter,
                    0,
                  ),
                  child: Text(
                    l10n.oweHowItWorks,
                    style: context.textStyles.bodySmall,
                  ),
                ),
                SectionHeader(title: l10n.pastMonths),
                if (bills.past.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.screenGutter,
                    ),
                    child: Text(
                      l10n.noPastMonths,
                      style: context.textStyles.bodySmall,
                    ),
                  )
                else
                  for (final bill in bills.past)
                    ListTile(
                      title: Text(
                        Formatters.monthYear(bill.month, locale: locale),
                        style: context.textStyles.titleSmall,
                      ),
                      // What the month's share was taken from: its sales,
                      // and the cash handed back on returns, when there was
                      // any. Without it, Atlas's August read 1,005,000 in
                      // sales and 68,750 owed, which is not 8% of it.
                      subtitle: Text(
                        [
                          money(bill.sales),
                          l10n.counted(bill.orderCount, CountNoun.order),
                          if (bill.returned > 0)
                            '${l10n.returnedCash} ${Formatters.deduction(bill.returned, locale: locale, currencyCode: bills.currencyCode)}',
                        ].join(' · '),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            money(bill.owed),
                            style: context.textStyles.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          // The amount decides, not the status: the demo
                          // sends DUE for every past month, and a month
                          // with nothing owed read "Due".
                          StatusBadge(
                            label: bill.owed == 0
                                ? l10n.billNothingOwed
                                : bill.isDue
                                ? l10n.billDue
                                // The day it was paid, when the server says.
                                : bill.paidAt == null
                                ? l10n.billPaid
                                : l10n.billPaidOn(
                                    Formatters.monthDay(
                                      bill.paidAt!,
                                      locale: locale,
                                    ),
                                  ),
                            tone: bill.owed == 0
                                ? StatusTone.neutral
                                : (bill.isDue
                                      ? StatusTone.caution
                                      : StatusTone.positive),
                            compact: true,
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: emphasize
                  ? context.textStyles.titleSmall
                  : context.textStyles.bodySmall,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            value,
            style: emphasize
                ? context.textStyles.titleMedium
                : context.textStyles.bodyMedium,
          ),
        ],
      ),
    );
  }
}
