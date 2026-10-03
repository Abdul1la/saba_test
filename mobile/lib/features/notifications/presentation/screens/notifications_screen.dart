import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/paged_state.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/paged_list_view.dart';
import '../../../../core/widgets/results_chrome.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/skeletons.dart';
import '../notifications_providers.dart';
import '../widgets/notification_visuals.dart';
import '../notification_destination.dart';

/// The notification inbox.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(notificationListProvider);
    final notifier = ref.read(notificationListProvider.notifier);

    return Scaffold(
      appBar: SabaAppBar(
        title: l10n.notifications,
        trailing: TextButton(
          // Reports when it fails. It used to swallow the failure, leaving
          // the unread dots in place with nothing said — which reads as a
          // button that does not work.
          onPressed: () async {
            final failure = await notifier.markAllRead();
            if (!context.mounted || failure == null) return;
            AppSnackBar.failure(context, failure);
          },
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            textStyle: context.textStyles.labelLarge?.copyWith(fontSize: 12.5),
          ),
          child: Text(l10n.markAllRead),
        ),
      ),
      body: SafeArea(
        top: false,
        child: AsyncStateView<PagedState<AppNotification>>(
          value: state,
          onRetry: () => ref.invalidate(notificationListProvider),
          loadingBuilder: (_) => const ListSkeleton(itemHeight: 88),
          builder: (paged) => PagedListView<AppNotification>(
            state: paged,
            onLoadMore: notifier.loadMore,
            onRefresh: notifier.refresh,
            onRetryLoadMore: notifier.retryLoadMore,
            separatorHeight: AppSpacing.sm + 2,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.sm,
              AppSpacing.screenGutter,
              AppSpacing.xxl,
            ),
            emptyState: NoResultsView(
              icon: SabaIcons.bell,
              title: l10n.emptyNotifications,
              message: l10n.emptyNotificationsMessage,
            ),
            itemBuilder: (context, notification, _) => _NotificationCard(
              notification: notification,
              leadsSomewhere: _destinationOf(notification) != null,
              onTap: () => _open(context, ref, notification),
            ),
          ),
        ),
      ),
    );
  }

  /// Where this notification leads, or null when it is only a message.
  ///
  /// One function for both questions — whether to show the card as a door and
  /// where the door goes — so the two cannot drift apart. Plenty of
  /// notifications are announcements with nothing behind them, and a card that
  /// looks the same either way makes the customer press every one to find out.
  static String? _destinationOf(AppNotification notification) =>
      notificationDestination(notification.targetType, notification.targetId);

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    AppNotification notification,
  ) async {
    // Reading it is worth a tap on its own, so every card stays pressable
    // even when there is nowhere to go afterwards. Marked on the way, not
    // before going: the screen waited on the server to open anything.
    if (!notification.isRead) {
      unawaited(
        ref.read(notificationListProvider.notifier).markRead(notification.id),
      );
    }

    final destination = _destinationOf(notification);
    if (destination != null) context.push(destination);
  }
}

/// One notification.
///
/// Unread is carried by a bolder title, a dot and a warmer card, because a 5%
/// tint alone is invisible on a phone in daylight. The icon tile keeps its
/// kind's colour either way, so an order and an offer never look alike.
class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.leadsSomewhere,
    required this.onTap,
  });

  final AppNotification notification;

  /// Draws the chevron. Tapping is always allowed — it marks the card read —
  /// but only a card with somewhere to go says so.
  final bool leadsSomewhere;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    final l10n = context.l10n;
    final locale = l10n.locale.toLanguageTag();
    final isUnread = !notification.isRead;
    final radius = BorderRadius.circular(AppRadius.card);
    final (ink, fill) = notificationTint(context, notification.category);

    // "Today, 6:29 PM" reads at a glance; a full date on every card did not.
    final at = notification.createdAt.toLocal();
    final now = DateTime.now();
    final days = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(at.year, at.month, at.day)).inDays;
    final time = Formatters.time(at, locale: locale);
    final when = switch (days) {
      0 => '${l10n.today}, $time',
      1 => '${l10n.yesterday}, $time',
      _ => Formatters.dateTime(at, locale: locale),
    };

    return Material(
      color: isUnread
          ? Color.alphaBlend(
              market.accentSoft.withValues(alpha: 0.35),
              context.colors.surface,
            )
          : context.colors.surface,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md + 2),
          decoration: BoxDecoration(
            border: Border.all(
              color: isUnread
                  ? market.accent.withValues(alpha: 0.35)
                  : market.border,
            ),
            borderRadius: radius,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(AppRadius.action),
                ),
                child: SabaIcon(
                  notificationIcon(notification.category),
                  size: AppSizes.iconMd,
                  color: ink,
                ),
              ),
              const SizedBox(width: AppSpacing.md + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: context.textStyles.bodyLarge?.copyWith(
                              fontSize: 14,
                              height: 1.35,
                              fontWeight: isUnread
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (isUnread) ...[
                          const SizedBox(width: AppSpacing.sm),
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(top: 5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: market.accent,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      notification.body,
                      style: context.textStyles.bodySmall?.copyWith(
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs + 1),
                    Text(when, style: context.textStyles.labelSmall),
                  ],
                ),
              ),
              if (leadsSomewhere) ...[
                const SizedBox(width: AppSpacing.sm),
                SabaIcon(
                  context.isRtl
                      ? SabaIcons.chevronLeft
                      : SabaIcons.chevronRight,
                  size: AppSizes.iconSm,
                  color: market.textMuted,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
