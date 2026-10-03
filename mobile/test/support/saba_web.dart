import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:saba_marketplace/core/errors/failure.dart';
import 'package:saba_marketplace/core/location/governorate.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';

// Saba's answers, as the web gives them, for the tests: the in-app admin
// is gone (Q12, BUGS 145) and the web is Saba's admin; the demo server still
// answers the web's routes, so a test can approve a store or a product.

const adminQueuePath = '/admin/queue';
String adminStoreAnswerPath(String id, {required bool approve}) =>
    '/admin/stores/$id/${approve ? 'approve' : 'reject'}';
String adminProductAnswerPath(String id, {required bool approve}) =>
    '/admin/products/$id/${approve ? 'approve' : 'reject'}';

/// One thing waiting for Saba's answer: a store that has just opened, or a
/// product a store has just added.
@immutable
class AdminReview {
  const AdminReview({
    required this.id,
    required this.title,
    this.titleAr = '',
    this.subtitle = '',
    this.city,
  });

  final String id;

  /// A store's name; a product's English name.
  final String title;

  /// A product's Arabic name: an admin approving it sees what shoppers read
  /// in either language. Empty when the store left it out.
  final String titleAr;

  /// A product's store.
  final String subtitle;

  /// A store's city. The queue named a new store by its owner's phone
  /// number, which tells Saba nothing about where it sells.
  final Governorate? city;
}

/// Everything waiting for an answer.
@immutable
class AdminQueue {
  const AdminQueue({required this.stores, required this.products});

  final List<AdminReview> stores;
  final List<AdminReview> products;

  bool get isEmpty => stores.isEmpty && products.isEmpty;
}

final adminQueueProvider = FutureProvider<AdminQueue>((ref) async {
  ref.watch(accountIdProvider);
  final result = await ref
      .watch(apiClientProvider)
      .get<AdminQueue>(
        adminQueuePath,
        decoder: (envelope) {
          final json = envelope.dataAsMap;
          List<Map<String, dynamic>> items(String key) => [
            for (final item in (json[key] as List? ?? const <dynamic>[]))
              (item as Map).cast<String, dynamic>(),
          ];
          return AdminQueue(
            // A store is named by its own name, and known by its city; a
            // product by its name, and by the store it belongs to.
            stores: [
              for (final store in items('stores'))
                AdminReview(
                  id: '${store['id']}',
                  title: '${store['storeName'] ?? ''}',
                  city: Governorate.fromApi(store['governorate']),
                ),
            ],
            products: [
              for (final product in items('products'))
                AdminReview(
                  id: '${product['id']}',
                  title: '${product['nameEn'] ?? ''}',
                  titleAr: '${product['nameAr'] ?? ''}',
                  subtitle:
                      '${(product['merchant'] as Map?)?['storeName'] ?? ''}',
                ),
            ],
          );
        },
      );
  return result.unwrap();
});

/// What the admin can answer. Each answer reloads what is left.
class AdminAnswers {
  const AdminAnswers(this._ref);

  final Ref _ref;

  /// A rejection needs [reason]: the store is told it, and keeps it.
  Future<Failure?> store(String id, {required bool approve, String? reason}) =>
      _send(adminStoreAnswerPath(id, approve: approve), reason);

  Future<Failure?> product(
    String id, {
    required bool approve,
    String? reason,
  }) => _send(adminProductAnswerPath(id, approve: approve), reason);

  Future<Failure?> _send(String path, [String? reason]) async {
    final result = await _ref
        .read(apiClientProvider)
        .command(
          path,
          data: reason == null ? null : <String, dynamic>{'reason': reason},
        );
    _ref.invalidate(adminQueueProvider);
    return result.failureOrNull;
  }
}

final adminAnswersProvider = Provider<AdminAnswers>(AdminAnswers.new);
