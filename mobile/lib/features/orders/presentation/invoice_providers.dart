import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/entities.dart';
import 'orders_providers.dart';

final invoiceProvider = FutureProvider.family<Invoice, String>((
  ref,
  orderId,
) async {
  return (await ref.watch(ordersRepositoryProvider).fetchInvoice(orderId))
      .unwrap();
});
