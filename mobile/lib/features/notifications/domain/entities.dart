import 'package:flutter/foundation.dart';

/// What a notification is about, which decides its icon, where tapping it goes
/// and which preference row it obeys (specification section 45).
enum NotificationCategory {
  order('ORDER'),
  payment('PAYMENT'),
  shipping('SHIPPING'),
  delivery('DELIVERY'),
  returnRequest('RETURN'),
  refund('REFUND'),
  promotion('PROMOTION'),
  priceDrop('PRICE_DROP'),
  backInStock('BACK_IN_STOCK'),
  message('MESSAGE'),
  merchantApproval('MERCHANT_APPROVAL'),
  productApproval('PRODUCT_APPROVAL'),
  security('SECURITY'),
  general('GENERAL');

  const NotificationCategory(this.apiValue);

  /// Stable wire code. Never a translated string, so the backend and the admin
  /// panel are not parsing display text.
  final String apiValue;

  static NotificationCategory fromApi(Object? value) {
    final code = value?.toString().toUpperCase();
    for (final category in NotificationCategory.values) {
      if (category.apiValue == code) return category;
    }
    return NotificationCategory.general;
  }

  /// Security alerts (new sign-in, password change, session revoked) cannot be
  /// switched off. Letting an attacker's victim silence the one message that
  /// would warn them defeats the purpose of sending it.
  bool get isAlwaysOn => this == NotificationCategory.security;

  /// Categories a customer can actually configure, in the order section 45
  /// lists them.
  static List<NotificationCategory> get configurable => NotificationCategory
      .values
      .where((c) => c != NotificationCategory.general)
      .toList(growable: false);
}

/// How a notification reaches the customer (specification section 45).
enum NotificationChannel {
  push('PUSH'),
  inApp('IN_APP'),
  email('EMAIL'),
  sms('SMS');

  const NotificationChannel(this.apiValue);

  final String apiValue;

  static NotificationChannel? fromApi(Object? value) {
    final code = value?.toString().toUpperCase();
    for (final channel in NotificationChannel.values) {
      if (channel.apiValue == code) return channel;
    }
    return null;
  }
}

/// Per-channel × per-category opt-in, held server-side so the choice follows
/// the account to every device (specification section 45).
///
/// A category is delivered on a channel only when **both** the master channel
/// switch and that category's switch are on. Two levels rather than one,
/// because "no SMS at all" is a different intent from "no SMS about
/// promotions" and a customer wants to express both.
@immutable
class NotificationPreferences {
  const NotificationPreferences({
    required this.channels,
    required this.categories,
  });

  /// Everything on except SMS, which costs money and is the one channel a
  /// customer is most likely to resent by default.
  factory NotificationPreferences.defaults() {
    return NotificationPreferences(
      channels: <NotificationChannel, bool>{
        for (final channel in NotificationChannel.values)
          channel: channel != NotificationChannel.sms,
      },
      categories: <NotificationCategory, Map<NotificationChannel, bool>>{
        for (final category in NotificationCategory.values)
          category: <NotificationChannel, bool>{
            for (final channel in NotificationChannel.values)
              channel:
                  category.isAlwaysOn || channel != NotificationChannel.sms,
          },
      },
    );
  }

  /// Master switch per channel.
  final Map<NotificationChannel, bool> channels;

  /// Per category, one flag per channel.
  final Map<NotificationCategory, Map<NotificationChannel, bool>> categories;

  bool channelEnabled(NotificationChannel channel) =>
      channels[channel] ?? false;

  /// The stored flag for one cell, ignoring the master switch. This is what the
  /// switch in the UI shows, so toggling a master off does not silently erase
  /// the customer's per-category choices.
  bool isEnabled(NotificationCategory category, NotificationChannel channel) {
    if (category.isAlwaysOn) return true;
    return categories[category]?[channel] ?? false;
  }

  /// Whether a notification would actually be delivered: both switches on.
  bool isDelivered(NotificationCategory category, NotificationChannel channel) {
    if (category.isAlwaysOn) return true;
    return channelEnabled(channel) && isEnabled(category, channel);
  }

  NotificationPreferences setChannel(
    NotificationChannel channel,
    bool enabled,
  ) {
    return NotificationPreferences(
      channels: <NotificationChannel, bool>{...channels, channel: enabled},
      categories: categories,
    );
  }

  /// No-op for an always-on category, so a mis-wired widget cannot turn a
  /// security alert off.
  NotificationPreferences setCategory(
    NotificationCategory category,
    NotificationChannel channel,
    bool enabled,
  ) {
    if (category.isAlwaysOn) return this;
    final row = <NotificationChannel, bool>{
      ...?categories[category],
      channel: enabled,
    };
    return NotificationPreferences(
      channels: channels,
      categories: <NotificationCategory, Map<NotificationChannel, bool>>{
        ...categories,
        category: row,
      },
    );
  }

  /// Starts from the defaults and overlays whatever the server sent, so a
  /// category the backend has not heard of yet still has a sane value.
  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    var result = NotificationPreferences.defaults();

    final channels = json['channels'];
    if (channels is Map) {
      channels.forEach((key, value) {
        final channel = NotificationChannel.fromApi(key);
        if (channel != null && value is bool) {
          result = result.setChannel(channel, value);
        }
      });
    }

    final categories = json['categories'];
    if (categories is Map) {
      categories.forEach((categoryKey, row) {
        if (row is! Map) return;
        final category = NotificationCategory.fromApi(categoryKey);
        row.forEach((channelKey, value) {
          final channel = NotificationChannel.fromApi(channelKey);
          if (channel != null && value is bool) {
            result = result.setCategory(category, channel, value);
          }
        });
      });
    }

    return result;
  }

  /// Sent whole rather than as a patch: the screen always holds the complete
  /// picture, and a full document is far easier for the backend to store
  /// transactionally than a stream of single-cell edits.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'channels': <String, bool>{
      for (final entry in channels.entries) entry.key.apiValue: entry.value,
    },
    'categories': <String, Map<String, bool>>{
      for (final entry in categories.entries)
        entry.key.apiValue: <String, bool>{
          for (final cell in entry.value.entries) cell.key.apiValue: cell.value,
        },
    },
  };
}
