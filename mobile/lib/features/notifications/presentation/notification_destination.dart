import '../../../core/router/app_routes.dart';

/// Where a notification leads, or null when it is only a message. The list
/// and a tapped push both ask this, so the two open the same screen.
String? notificationDestination(String? targetType, String? targetId) {
  if (targetId == null || targetId.isEmpty) return null;

  // Each opens what it is about. A store's notifications - its new order
  // above all, the one it taps most - and a return's opened nothing.
  return switch (targetType?.toUpperCase()) {
    'ORDER' => AppRoutes.orderDetailPath(targetId),
    'STORE_ORDER' => AppRoutes.merchantOrderDetailPath(targetId),
    'RETURN' => AppRoutes.returnDetailPath(targetId),
    'PRODUCT' => AppRoutes.productDetailPath(targetId),
    'STORE_PRODUCT' => AppRoutes.merchantProductEditPath(targetId),
    'STORE' => AppRoutes.merchantDashboard,
    'CONVERSATION' => AppRoutes.conversationPath(targetId),
    'TICKET' => AppRoutes.supportTicketPath(targetId),
    _ => null,
  };
}
