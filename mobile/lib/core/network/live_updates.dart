import 'dart:async';

/// What changed on the server, so every screen showing it reloads at once.
///
/// A screen used to keep whatever it had loaded: a new order was missing
/// from My orders until the list was pulled down, and the dot on the bell
/// never changed at all.
///
/// One announcement, read by both sides of the app: whoever changes
/// something says which subject it belongs to, and every list, detail
/// screen and badge showing that subject loads again. Today the app is the
/// only thing that changes anything, so [ApiClient] announces its own
/// writes; with a real backend the same announcements arrive from the
/// server, and nothing above this line changes. See `BACKEND_READY.md`.
enum LiveTopic {
  /// Orders and their steps, on both the shopper's and the store's side.
  orders,

  /// Notifications, and the unread dot on the bell.
  notifications,
}

/// The announcements themselves.
class LiveUpdates {
  final StreamController<LiveTopic> _topics =
      StreamController<LiveTopic>.broadcast();

  /// Every change, as it happens.
  Stream<LiveTopic> get changes => _topics.stream;

  void announce(LiveTopic topic) {
    if (!_topics.isClosed) _topics.add(topic);
  }

  /// Announces what a write to [path] changed.
  ///
  /// The path is the subject: `/orders/…`, `/merchants/me/orders/…` and
  /// checking out all change orders, and each of them also leaves the other
  /// side a notification.
  void announceWrite(String path) {
    for (final topic in topicsOf(path)) {
      announce(topic);
    }
  }

  static Set<LiveTopic> topicsOf(String path) {
    final subject = path.toLowerCase();
    if (subject.contains('order') ||
        subject.contains('checkout') ||
        subject.contains('return')) {
      return const {LiveTopic.orders, LiveTopic.notifications};
    }
    // A chat message leaves the other side a notification too.
    if (subject.contains('notification') || subject.contains('messages')) {
      return const {LiveTopic.notifications};
    }
    return const {};
  }

  void dispose() => _topics.close();
}
