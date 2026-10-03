import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/dark_header_card.dart';
import '../../../../core/widgets/skeletons.dart';
import '../../../auth/domain/entities.dart';
import '../../../auth/presentation/auth_providers.dart';
import '../../../messaging/presentation/messaging_providers.dart';
import '../../domain/entities.dart';
import '../merchant_providers.dart';
import '../widgets/merchant_widgets.dart';
import '../widgets/store_setup_checklist.dart';
import '../../../../core/widgets/saba_nav_bar.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../../core/widgets/saba_logo.dart';

/// Merchant home.
///
/// This was eight metric cards in a grid. Five of them did nothing at all,
/// three opened a list broader than the number they showed, and not one of
/// them said what the merchant should *do*. A dashboard that only counts is
/// a report; the design makes it a to-do list with a revenue figure on top.
///
/// Three rules it now follows:
///
///   * A row with a chevron does something, and opens exactly what it names —
///     "7 orders to confirm" opens the seven, not all thirty-eight.
///   * A stat card has no chevron, because it is a fact, not a door.
///   * A figure the backend did not send is absent, never zero. "+0%" and
///     "we do not know" must not look the same.
class MerchantDashboardScreen extends ConsumerWidget {
  const MerchantDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(merchantDashboardProvider);
    final auth = ref.watch(authControllerProvider).value;

    return Scaffold(
      body: AsyncStateView<MerchantDashboard>(
        value: dashboard,
        onRetry: () => ref.invalidate(merchantDashboardProvider),
        loadingBuilder: (_) => const ListSkeleton(itemHeight: 96),
        builder: (data) => RefreshIndicator(
          onRefresh: () => ref.refresh(merchantDashboardProvider.future),
          child: ListView(
            padding: EdgeInsets.only(bottom: SabaNavBar.clearance(context)),
            children: [
              WhiteHeader(
                child: _RevenueHeader(data: data, store: auth?.user?.merchant),
              ),
              if (auth != null && !auth.canSell)
                const Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.screenGutter,
                    AppSpacing.lg,
                    AppSpacing.screenGutter,
                    0,
                  ),
                  child: PendingApprovalBanner(),
                ),
              const SizedBox(height: AppSpacing.sectionGap - 8),
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.screenGutter,
                  0,
                  AppSpacing.screenGutter,
                  AppSpacing.lg,
                ),
                child: StoreSetupChecklist(),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenGutter,
                ),
                child: _NeedsYouToday(data: data),
              ),
              const SizedBox(height: AppSpacing.lg + 2),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenGutter,
                ),
                child: _StatRow(data: data),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The dark band: who the store is, what it earned, and how that compares.
class _RevenueHeader extends ConsumerWidget {
  const _RevenueHeader({required this.data, this.store});

  final MerchantDashboard data;
  final MerchantSummary? store;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final market = context.market;
    final locale = l10n.locale.toLanguageTag();

    String money(num value) => Formatters.money(
      value,
      locale: locale,
      currencyCode: data.currencyCode,
    );

    // Only computed when the backend sent something to compare against. A
    // percentage invented from a missing number is the most confident kind
    // of lie a dashboard can tell.
    final previous = data.previousRevenue;
    final delta = (previous != null && previous > 0)
        ? ((data.revenue - previous) / previous) * 100
        : null;

    return DarkHeaderCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The logo it saved in Store settings; Saba's mark until then.
              AppNetworkImage(
                url: store?.logoUrl,
                width: AppSizes.iconCircle,
                height: AppSizes.iconCircle,
                radius: AppRadius.action,
                fallback: const SabaMark(size: AppSizes.iconCircle),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The screen's heading, like Home's greeting, and like
                    // it shrinks to fit rather than end in "…": the switch
                    // and two buttons share its row.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        store?.storeName ?? l10n.merchantDashboard,
                        maxLines: 1,
                        style: AppTypography.heading(
                          context,
                          size: AppTypography.barTitleSize,
                          color: market.onDark,
                        ),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      // Exactly what is true, in one line. "Store closed"
                      // was shown to a store still waiting to be approved,
                      // with no switch to open it and nothing saying why.
                      switch (store?.status) {
                        _ when store?.deletionRequestedAt != null =>
                          l10n.storeBeingDeleted,
                        MerchantStatus.approved =>
                          data.isOpen
                              ? l10n.storeApprovedOpen
                              : l10n.storeApprovedClosed,
                        MerchantStatus.rejected => l10n.storeNotApproved,
                        MerchantStatus.suspended => l10n.statusSuspended,
                        _ => l10n.storeWaitingApproval,
                      },
                      style: context.textStyles.labelSmall?.copyWith(
                        color: market.onDarkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              // Not while its account is being deleted: it cannot open.
              if (store?.status == MerchantStatus.approved &&
                  store?.deletionRequestedAt == null)
                _OpenSwitch(isOpen: data.isOpen),
              const SizedBox(width: AppSpacing.sm),
              // Customers' questions, with the dot while one waits.
              DarkIconButton(
                icon: SabaIcons.message,
                tooltip: l10n.messages,
                showDot: ref.watch(unreadMessageCountProvider) > 0,
                onPressed: () => context.push(AppRoutes.conversations),
              ),
              const SizedBox(width: AppSpacing.sm),
              DarkIconButton(
                icon: SabaIcons.bell,
                tooltip: l10n.notifications,
                onPressed: () => context.push(AppRoutes.notifications),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg + 2),
          OnDarkRaisedCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.revenueThisMonth,
                        style: context.textStyles.labelSmall?.copyWith(
                          color: market.onDarkMuted,
                        ),
                      ),
                    ),
                    if (delta != null) DeltaPill(percent: delta),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  money(data.revenue),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.displaySmall?.copyWith(
                    fontSize: 26,
                    color: market.onDark,
                  ),
                ),
                if (previous != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    // Nineteen days against nineteen days. Comparing a part
                    // month with a whole one makes every month look like a
                    // collapse until the last week of it.
                    data.comparisonDays != null
                        ? '${l10n.lastMonthSame} '
                              '${l10n.counted(data.comparisonDays!, CountNoun.day)}: '
                              '${money(previous)}'
                        : money(previous),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.labelSmall?.copyWith(
                      color: market.onDarkMuted,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                SalesBarChart(
                  points: data.salesSeries,
                  height: 96,
                  onDark: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The merchant's to-do list.
///
/// Every row here is something the merchant can act on, and only rows with
/// work in them are drawn — a permanent "0 orders to confirm" trains people
/// to stop reading the section.
class _NeedsYouToday extends ConsumerWidget {
  const _NeedsYouToday({required this.data});

  final MerchantDashboard data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final hours = data.oldestPendingHours;
    // Customers whose last word the store has not read yet.
    final waiting = [
      for (final chat
          in ref.watch(conversationsProvider).value ?? const <Conversation>[])
        if (chat.unreadCount > 0) chat,
    ];

    final rows = <Widget>[
      // A question unanswered loses the sale, so it sits with the orders.
      if (waiting.isNotEmpty)
        _NeedsRow(
          icon: SabaIcons.message,
          tone: context.market.info,
          title:
              '${l10n.counted(waiting.length, CountNoun.customer)} '
              '${l10n.waitingReplySuffix}',
          subtitle: [
            waiting.first.title,
            ?waiting.first.lastMessage,
          ].join(': '),
          // One waiting: straight into that chat. More: the inbox.
          onTap: () => context.push(
            waiting.length == 1
                ? AppRoutes.conversationPath(waiting.first.id)
                : AppRoutes.conversations,
          ),
        ),
      if (data.pendingOrders > 0)
        _NeedsRow(
          icon: SabaIcons.clock,
          tone: context.market.warning,
          title:
              '${l10n.counted(data.pendingOrders, CountNoun.order)} '
              '${l10n.toConfirmSuffix}',
          // Only said when the backend actually measured it.
          subtitle: hours == null
              ? null
              : '${l10n.oldestWaiting} '
                    '${l10n.counted(hours, CountNoun.hour)}',
          onTap: () =>
              context.go(AppRoutes.merchantOrdersPath(status: 'PENDING')),
        ),
      if (data.outOfStockCount > 0)
        _NeedsRow(
          icon: SabaIcons.alert,
          tone: context.colors.error,
          title:
              '${l10n.counted(data.outOfStockCount, CountNoun.product)} '
              '${l10n.outOfStockSuffix}',
          subtitle: l10n.stillListedNotBuyable,
          onTap: () => context.push(AppRoutes.merchantInventory),
        ),
      // Saba said no, and why: the row goes to the shelf, where each one
      // shows the reason and opens to be fixed.
      if (data.rejectedCount > 0)
        _NeedsRow(
          icon: SabaIcons.close,
          tone: context.colors.error,
          title:
              '${l10n.counted(data.rejectedCount, CountNoun.product)} '
              '${l10n.notApprovedSuffix}',
          subtitle: l10n.rejectedNeedsEdit,
          onTap: () => context.go(AppRoutes.merchantProducts),
        ),
      if (data.returnCount > 0)
        _NeedsRow(
          icon: SabaIcons.refresh,
          tone: context.market.textMuted,
          title: l10n.counted(data.returnCount, CountNoun.returnRequest),
          subtitle: '${l10n.replyWithin} ${l10n.counted(48, CountNoun.hour)}',
          // No door, because there is nothing behind it yet. This opened
          // ?status=RETURNED, and no bucket in the queue holds that status,
          // so the merchant was silently dropped on "To confirm" — shown new
          // orders under a row that promised returns. Merchant returns are a
          // backend-phase item; until the queue can show them, the row states
          // the deadline and offers nothing it cannot open.
          onTap: null,
        ),
    ];

    // A store with nothing on its shelf has one job, and the setup checklist
    // above says it. "Nothing needs you right now" under it would say the
    // opposite, and a second "Add your first product" said it twice.
    if (rows.isEmpty && data.productCount == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.needsYouToday, style: AppTypography.sectionTitle(context)),
        const SizedBox(height: AppSpacing.md + 2),
        if (rows.isEmpty)
          // An empty to-do list is good news and should read as good news,
          // not as a section that failed to load.
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: context.colors.surface,
              border: Border.all(color: context.market.border),
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Row(
              children: [
                SabaIcon(
                  SabaIcons.check,
                  size: AppSizes.iconMd,
                  color: context.market.success,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    l10n.allCaughtUp,
                    style: context.textStyles.bodyMedium?.copyWith(
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          for (final row in rows) ...[
            row,
            if (row != rows.last) const SizedBox(height: AppSpacing.md),
          ],
      ],
    );
  }
}

class _NeedsRow extends StatelessWidget {
  const _NeedsRow({
    required this.icon,
    required this.tone,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final String icon;
  final Color tone;
  final String title;
  final String? subtitle;

  /// Null when there is nowhere to go, and then no chevron is drawn: a row
  /// with a chevron does something, and opens exactly what it names.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.card);

    return Material(
      color: context.colors.surface,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md + 2),
          constraints: const BoxConstraints(minHeight: AppSizes.minTapTarget),
          decoration: BoxDecoration(
            border: Border.all(color: context.market.border),
            borderRadius: radius,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: SabaIcon(icon, size: AppSizes.iconMd, color: tone),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.titleSmall?.copyWith(
                        fontSize: 14,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.textStyles.labelSmall,
                      ),
                    ],
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: AppSpacing.sm),
                SabaIcon(
                  context.isRtl
                      ? SabaIcons.chevronLeft
                      : SabaIcons.chevronRight,
                  size: AppSizes.iconMd,
                  color: context.market.textMuted,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Two facts, side by side.
///
/// Deliberately not tappable and deliberately without a chevron: the metric
/// cards they replace looked identical whether they opened something or not,
/// so a merchant learned that tapping a number does nothing and stopped
/// trying — including on the five cards that did work.
class _StatRow extends StatelessWidget {
  const _StatRow({required this.data});

  final MerchantDashboard data;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = l10n.locale.toLanguageTag();
    final delta = data.orderCountDelta;
    final rating = data.rating;

    // Not a bare `stretch`: a Row inside a ListView has no bounded height,
    // so stretching its children hands them an infinite constraint and the
    // whole screen fails to lay out. IntrinsicHeight gives the Row a real
    // height first, so both cards match the taller of the two.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _StatCard(
              label: l10n.ordersThisMonth,
              value: Formatters.number(data.orderCount, locale: locale),
              note: delta == null
                  ? null
                  : '${delta >= 0 ? '+' : ''}$delta ${l10n.vsLastMonth}',
              noteColor: delta == null
                  ? null
                  : (delta >= 0
                        ? context.market.success
                        : context.colors.error),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _StatCard(
              label: l10n.storeRating,
              // A store with no ratings has no rating. Printing 0.0 would
              // tell the merchant their customers hate them.
              value: rating == null ? '—' : rating.toStringAsFixed(1),
              valueIcon: rating == null ? null : SabaIcons.starFilled,
              note: data.ratingCount == null
                  ? null
                  : '${l10n.fromWord} '
                        '${l10n.counted(data.ratingCount!, CountNoun.order, genitive: true)}',
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    this.note,
    this.noteColor,
    this.valueIcon,
  });

  final String label;
  final String value;
  final String? note;
  final Color? noteColor;
  final String? valueIcon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md + 2),
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border.all(color: context.market.border),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, maxLines: 1, style: context.textStyles.labelSmall),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.titleLarge,
                ),
              ),
              if (valueIcon != null) ...[
                const SizedBox(width: AppSpacing.xs),
                SabaIcon(valueIcon!, size: 14, color: context.market.star),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            note ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textStyles.labelSmall?.copyWith(color: noteColor),
          ),
        ],
      ),
    );
  }
}

/// Open or closed for orders, in one tap. Closed, shoppers see the store
/// but cannot buy from it.
class _OpenSwitch extends ConsumerStatefulWidget {
  const _OpenSwitch({required this.isOpen});

  final bool isOpen;

  @override
  ConsumerState<_OpenSwitch> createState() => _OpenSwitchState();
}

class _OpenSwitchState extends ConsumerState<_OpenSwitch> {
  bool _saving = false;

  Future<void> _set(bool open) async {
    setState(() => _saving = true);
    final result = await ref.read(merchantRepositoryProvider).setOpen(open);
    if (!mounted) return;
    setState(() => _saving = false);
    result.fold(
      ok: (_) {
        ref.invalidate(merchantDashboardProvider);
        AppSnackBar.info(
          context,
          open ? context.l10n.storeNowOpen : context.l10n.storeNowClosed,
        );
      },
      err: (failure) => AppSnackBar.failure(context, failure),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.l10n.storeOpen,
      child: Switch(
        value: widget.isOpen,
        activeTrackColor: context.market.success,
        onChanged: _saving ? null : _set,
      ),
    );
  }
}
