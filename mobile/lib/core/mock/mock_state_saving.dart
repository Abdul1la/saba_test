part of 'mock_api_interceptor.dart';

/// The demo server, kept on the phone.
///
/// A real server keeps every account's orders, cart and chats when the app
/// is closed; the demo one lived in memory and lost them all. Now its whole
/// state is written as one JSON document after each request that changed it,
/// and read back when the app starts, so signing back in - even after a
/// restart - finds everything where it was left.
///
/// An order is one record that both the shopper's list and the server's
/// order book point at, and a return is shared the same way with its store:
/// a store's step on it has to reach the shopper's copy. The document writes
/// such a record once and refers to it by id everywhere else, so that stays
/// true after reading it back.
extension _Saving on MockApiInterceptor {
  /// Bumped when the document's shape changes: an older one is dropped
  /// rather than half-read.
  // 2: a store's new order is PENDING, not NEW (BACKEND_PLAN.md 8.4). A
  // phone holding orders saved as NEW starts the demo fresh instead of
  // losing them from "To confirm".
  static const int _version = 2;

  static const String _ref = r'$ref';

  String _encodeState() {
    final refs = Map<Map<String, dynamic>, String>.identity();
    _placedOrders.forEach((id, order) => refs[order] = 'order:$id');
    for (final list in _storeReturns.values) {
      for (final request in list) {
        refs[request] = 'return:${request['id']}';
      }
    }
    Object keep(Map<String, dynamic> record) => switch (refs[record]) {
      final key? => <String, dynamic>{_ref: key},
      null => record,
    };

    return jsonEncode(<String, dynamic>{
      'version': _version,
      'email': _email,
      'counter': _counter,
      'cannedAt': _cannedAt.toIso8601String(),
      'accounts': <String, dynamic>{
        for (final entry in _setAside.entries)
          entry.key: _accountJson(entry.value, keep),
        _email: _accountJson(_snapshot(), keep),
      },
      'placedOrders': _placedOrders,
      'storeOrders': _storeOrders,
      'storeReturns': _storeReturns,
      'events': [
        for (final event in _events)
          <String, dynamic>{
            ...event,
            'en': _pair(event['en']),
            'ar': _pair(event['ar']),
          },
      ],
      'reviews': _reviews,
      'removedProducts': _removedProducts.toList(),
      'fixtureStatus': _fixtureStatus,
      'shown': _shown,
      'takenDown': _takenDown,
      'featuredStores': _featuredStores,
      'deletedAccounts': _deletedAccounts.toList(),
      'givenRatings': <String, dynamic>{
        for (final entry in _givenRatings.entries)
          entry.key: <String, dynamic>{
            'total': entry.value.$1,
            'count': entry.value.$2,
          },
      },
      'chats': [
        for (final chat in _chats.values)
          <String, dynamic>{
            'id': chat.id,
            'customerEmail': chat.customerEmail,
            'customerName': chat.customerName,
            'merchantId': chat.merchantId,
            'messages': chat.messages,
            'customerRead': chat.customerRead,
            'storeRead': chat.storeRead,
            'customerBlocked': chat.customerBlocked,
            'storeBlocked': chat.storeBlocked,
          },
      ],
      'seededChats': _seededChats,
      'phoneAccounts': _phoneAccounts,
      'readNotifications': _readNotifications,
      'storeCoupons': _storeCoupons,
      'storeProducts': _storeProducts,
      'storeReviews': _storeReviews,
      'storeDelivery': _storeDelivery,
      'stockOverrides': _stockOverrides,
      'closedStores': _closedStores,
      'storeDeletions': _storeDeletions,
      'addedBrands': _addedBrands,
      'searchCounts': <String, dynamic>{
        for (final entry in _searchCounts.entries)
          entry.key: [entry.value.$1, entry.value.$2],
      },
      // The demo's own products as their stores left them.
      'fixtures': <String, dynamic>{
        for (final entry in _fixtureOriginals.entries)
          entry.key: <String, dynamic>{
            'original': entry.value,
            'now': MockData.productById(entry.key),
          },
      },
    }, toEncodable: (value) => value is Set ? value.toList() : value);
  }

  static List<String> _pair(Object? value) {
    final (first, second) = value! as (String, String);
    return [first, second];
  }

  static Map<String, dynamic> _accountJson(
    _AccountSnapshot account,
    Object Function(Map<String, dynamic>) keep,
  ) => <String, dynamic>{
    'cart': account.cart,
    'coupon': account.coupon,
    'wishlist': account.wishlist,
    'addresses': account.addresses,
    'orders': [for (final order in account.orders) keep(order)],
    'returns': [for (final request in account.returns) keep(request)],
    'ratedOrders': account.ratedOrders,
    'ratingSkips': account.ratingSkips,
    'tickets': account.tickets,
    'ticketMessages': account.ticketMessages,
    'signup': account.signup,
    'ownStore': account.ownStore,
    'becameMerchant': account.becameMerchant,
    'storeStatus': account.storeStatus,
    'newStoreName': account.newStoreName,
    'profileEdits': account.profileEdits,
  };

  /// Puts back what [_encodeState] wrote. Returns false, and changes
  /// nothing, for a document of another version.
  bool _decodeState(String document) {
    final data = jsonDecode(document) as Map<String, dynamic>;
    if (data['version'] != _version) return false;

    _placedOrders
      ..clear()
      ..addAll(_mapOf(data['placedOrders']));
    _storeOrders
      ..clear()
      ..addAll(_listsOf(data['storeOrders']));
    _storeReturns
      ..clear()
      ..addAll(_listsOf(data['storeReturns']));
    final shared = <String, Map<String, dynamic>>{
      for (final entry in _placedOrders.entries)
        'order:${entry.key}': entry.value,
      for (final list in _storeReturns.values)
        for (final request in list) 'return:${request['id']}': request,
    };
    Map<String, dynamic> resolve(Object? value) {
      final record = value! as Map<String, dynamic>;
      return switch (record[_ref]) {
        final String key => shared[key]!,
        _ => record,
      };
    }

    _setAside.clear();
    for (final entry in (data['accounts'] as Map<String, dynamic>).entries) {
      _setAside[entry.key] = _accountFrom(
        entry.value as Map<String, dynamic>,
        resolve,
      );
    }
    _email = data['email'] as String;
    _restore(
      _setAside.remove(_email) ??
          _AccountSnapshot.fresh(
            addresses: MockApiInterceptor._demoAddresses(),
          ),
    );
    _counter = data['counter'] as int;
    _cannedAt = DateTime.tryParse('${data['cannedAt']}') ?? _cannedAt;

    _events
      ..clear()
      ..addAll([
        for (final event in _maps(data['events']))
          <String, dynamic>{
            ...event,
            'en': _record(event['en']),
            'ar': _record(event['ar']),
          },
      ]);
    _reviews
      ..clear()
      ..addAll(_listsOf(data['reviews']));
    _removedProducts
      ..clear()
      ..addAll(_strings(data['removedProducts']));
    _fixtureStatus
      ..clear()
      ..addAll(<String, String>{
        for (final entry in (data['fixtureStatus'] as Map? ?? const {}).entries)
          '${entry.key}': '${entry.value}',
      });
    _shown
      ..clear()
      ..addAll(<String, bool>{
        for (final entry in (data['shown'] as Map? ?? const {}).entries)
          '${entry.key}': entry.value == true,
      });
    _takenDown
      ..clear()
      ..addAll(<String, String>{
        for (final entry in (data['takenDown'] as Map? ?? const {}).entries)
          '${entry.key}': '${entry.value}',
      });
    if (data['featuredStores'] is List) {
      _featuredStores
        ..clear()
        ..addAll(_strings(data['featuredStores']));
    }
    _deletedAccounts
      ..clear()
      ..addAll(_strings(data['deletedAccounts']));
    _givenRatings
      ..clear()
      ..addAll(<String, (num, int)>{
        for (final entry in (data['givenRatings'] as Map? ?? const {}).entries)
          '${entry.key}': (
            (entry.value as Map)['total'] as num,
            ((entry.value as Map)['count'] as num).toInt(),
          ),
      });
    _chats.clear();
    for (final chat in _maps(data['chats'])) {
      _chats['${chat['id']}'] =
          _Chat(
              id: chat['id'] as String,
              customerEmail: chat['customerEmail'] as String,
              customerName: chat['customerName'] as String,
              merchantId: chat['merchantId'] as String,
            )
            ..messages.addAll(_maps(chat['messages']))
            ..customerRead = chat['customerRead'] as int
            ..storeRead = chat['storeRead'] as int
            // Not in a document saved before blocking existed.
            ..customerBlocked = chat['customerBlocked'] as bool? ?? false
            ..storeBlocked = chat['storeBlocked'] as bool? ?? false;
    }
    _seededChats
      ..clear()
      ..addAll(_strings(data['seededChats']));
    // In one form, as they are kept now: a demo saved before kept a number
    // as it was sent.
    _phoneAccounts
      ..clear()
      ..addAll(<String, String>{
        for (final entry
            in (data['phoneAccounts'] as Map<String, dynamic>).entries)
          MockApiInterceptor._samePhone(entry.key): '${entry.value}',
      });
    _readNotifications
      ..clear()
      ..addAll(_strings(data['readNotifications']));
    _storeCoupons
      ..clear()
      ..addAll(_listsOf(data['storeCoupons']));
    _storeProducts
      ..clear()
      ..addAll(_maps(data['storeProducts']));
    _storeReviews
      ..clear()
      ..addAll(_mapOf(data['storeReviews']));
    _storeDelivery
      ..clear()
      ..addAll(_mapOf(data['storeDelivery']));
    _stockOverrides
      ..clear()
      ..addAll((data['stockOverrides'] as Map<String, dynamic>).cast());
    _closedStores
      ..clear()
      ..addAll(_strings(data['closedStores']));
    // Not in a document saved before stores could type a brand.
    _addedBrands
      ..clear()
      ..addAll(_maps(data['addedBrands'] ?? const <dynamic>[]));
    // Not in a document saved before store deletion existed.
    _storeDeletions
      ..clear()
      ..addAll(
        (data['storeDeletions'] as Map<String, dynamic>? ?? const {}).cast(),
      );
    _searchCounts
      ..clear()
      ..addAll({
        for (final entry
            in (data['searchCounts'] as Map<String, dynamic>).entries)
          entry.key: (
            (entry.value as List)[0] as String,
            (entry.value as List)[1] as int,
          ),
      });
    for (final entry in (data['fixtures'] as Map<String, dynamic>).entries) {
      final fixture = entry.value as Map<String, dynamic>;
      _fixtureOriginals[entry.key] =
          fixture['original'] as Map<String, dynamic>;
      MockData.productById(entry.key)
        ?..clear()
        ..addAll(fixture['now'] as Map<String, dynamic>);
    }
    return true;
  }

  static _AccountSnapshot _accountFrom(
    Map<String, dynamic> json,
    Map<String, dynamic> Function(Object?) resolve,
  ) => _AccountSnapshot(
    cart: _maps(json['cart']),
    coupon: json['coupon'] as String?,
    wishlist: _strings(json['wishlist']).toSet(),
    addresses: _maps(json['addresses']),
    orders: [for (final order in json['orders'] as List) resolve(order)],
    returns: [for (final request in json['returns'] as List) resolve(request)],
    ratedOrders: _strings(json['ratedOrders']).toSet(),
    ratingSkips: <String, int>{
      for (final entry in (json['ratingSkips'] as Map? ?? const {}).entries)
        '${entry.key}': (entry.value as num).toInt(),
    },
    tickets: _maps(json['tickets']),
    ticketMessages: _listsOf(json['ticketMessages']),
    signup: json['signup'] as Map<String, dynamic>?,
    ownStore: json['ownStore'] as Map<String, dynamic>?,
    becameMerchant: json['becameMerchant'] as bool,
    storeStatus: json['storeStatus'] as String,
    newStoreName: json['newStoreName'] as String?,
    profileEdits: json['profileEdits'] as Map<String, dynamic>,
  );

  static (String, String) _record(Object? value) {
    final pair = value! as List;
    return (pair[0] as String, pair[1] as String);
  }

  static List<String> _strings(Object? value) => [
    for (final item in value! as List) item as String,
  ];

  static List<Map<String, dynamic>> _maps(Object? value) => [
    for (final item in value! as List) item as Map<String, dynamic>,
  ];

  static Map<String, Map<String, dynamic>> _mapOf(Object? value) => {
    for (final entry in (value! as Map<String, dynamic>).entries)
      entry.key: entry.value as Map<String, dynamic>,
  };

  static Map<String, List<Map<String, dynamic>>> _listsOf(Object? value) => {
    for (final entry in (value! as Map<String, dynamic>).entries)
      entry.key: _maps(entry.value),
  };
}
