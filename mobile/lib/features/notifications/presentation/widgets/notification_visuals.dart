import 'package:flutter/material.dart';

import '../../../../core/utils/context_extensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../domain/entities.dart';

/// The icon that stands for a notification category.
///
/// This switch existed twice — once in the inbox and once in the preferences
/// screen — so a category could be a parcel in one place and a box in the
/// other. It lives here once, and both read from it.
String notificationIcon(NotificationCategory category) => switch (category) {
  NotificationCategory.order => SabaIcons.receipt,
  NotificationCategory.payment => SabaIcons.creditCard,
  NotificationCategory.shipping ||
  NotificationCategory.delivery => SabaIcons.truck,
  NotificationCategory.returnRequest => SabaIcons.refresh,
  NotificationCategory.refund => SabaIcons.coin,
  NotificationCategory.promotion => SabaIcons.ticket,
  // A price *drop* drawn with a rising arrow is a small lie the customer
  // reads before the words.
  NotificationCategory.priceDrop => SabaIcons.trendingDown,
  NotificationCategory.backInStock => SabaIcons.box,
  NotificationCategory.message => SabaIcons.message,
  NotificationCategory.merchantApproval ||
  NotificationCategory.productApproval => SabaIcons.check,
  NotificationCategory.security => SabaIcons.shield,
  NotificationCategory.general => SabaIcons.bell,
};

/// The icon for a delivery channel.
/// Each kind of news in its own colour, as ink on a soft fill: money and
/// orders blue, anything on its way green, offers purple, account safety
/// amber.
(Color, Color) notificationTint(
  BuildContext context,
  NotificationCategory category,
) {
  final market = context.market;
  return switch (category) {
    NotificationCategory.order ||
    NotificationCategory.payment ||
    NotificationCategory.refund ||
    NotificationCategory.message => (market.info, market.infoSoft),
    NotificationCategory.shipping ||
    NotificationCategory.delivery ||
    NotificationCategory.merchantApproval ||
    NotificationCategory.productApproval => (
      market.success,
      market.successSoft,
    ),
    NotificationCategory.promotion ||
    NotificationCategory.priceDrop ||
    NotificationCategory.backInStock => (market.accent, market.accentSoft),
    NotificationCategory.returnRequest ||
    NotificationCategory.security => (market.warning, market.warningSoft),
    NotificationCategory.general => (market.textMuted, market.surfaceMuted),
  };
}

String notificationChannelIcon(NotificationChannel channel) =>
    switch (channel) {
      NotificationChannel.push => SabaIcons.bell,
      NotificationChannel.inApp => SabaIcons.phone,
      NotificationChannel.email => SabaIcons.mail,
      NotificationChannel.sms => SabaIcons.message,
    };
