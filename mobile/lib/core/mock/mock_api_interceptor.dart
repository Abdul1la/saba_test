import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../location/governorate.dart';
import '../utils/formatters.dart';
import '../utils/iraqi_phone.dart';
import '../utils/search_text.dart';

import 'mock_data.dart';

part 'mock_state_saving.dart';

/// One canned reply.
class _Reply {
  const _Reply(
    this.data, {
    this.meta = const <String, dynamic>{},
    this.statusCode = 200,
  });

  final Object? data;
  final Map<String, dynamic> meta;

  /// Anything >= 400 is rejected rather than resolved, so demo mode can
  /// exercise the app's failure paths and not only its happy ones.
  final int statusCode;
}

/// One chat between a customer and a store.
class _Chat {
  _Chat({
    required this.id,
    required this.customerEmail,
    required this.customerName,
    required this.merchantId,
  });

  final String id;
  final String customerEmail;
  final String customerName;
  final String merchantId;

  /// Oldest first; `from` is CUSTOMER or STORE.
  final List<Map<String, dynamic>> messages = <Map<String, dynamic>>[];

  /// How many messages each side has seen.
  int customerRead = 0;
  int storeRead = 0;

  /// Each side's block (Apple 1.2): while either stands, nobody writes.
  bool customerBlocked = false;
  bool storeBlocked = false;
}

/// Everything one account owns in the demo backend, set aside while someone
/// else is signed in.
class _AccountSnapshot {
  const _AccountSnapshot({
    required this.cart,
    required this.coupon,
    required this.wishlist,
    required this.addresses,
    required this.orders,
    required this.returns,
    required this.ratedOrders,
    required this.ratingSkips,
    required this.tickets,
    required this.ticketMessages,
    required this.signup,
    required this.ownStore,
    required this.becameMerchant,
    required this.storeStatus,
    required this.newStoreName,
    required this.profileEdits,
  });

  /// An account with nothing in it yet but [addresses].
  _AccountSnapshot.fresh({required this.addresses})
    : cart = const [],
      coupon = null,
      wishlist = const {},
      orders = const [],
      returns = const [],
      ratedOrders = const {},
      ratingSkips = const {},
      tickets = const [],
      ticketMessages = const {},
      signup = null,
      ownStore = null,
      becameMerchant = false,
      storeStatus = 'APPROVED',
      newStoreName = null,
      profileEdits = const {};

  final List<Map<String, dynamic>> cart;
  final String? coupon;
  final Set<String> wishlist;
  final List<Map<String, dynamic>> addresses;
  final List<Map<String, dynamic>> orders;
  final List<Map<String, dynamic>> returns;
  final Set<String> ratedOrders;
  final Map<String, int> ratingSkips;
  final List<Map<String, dynamic>> tickets;
  final Map<String, List<Map<String, dynamic>>> ticketMessages;
  final Map<String, dynamic>? signup;
  final Map<String, dynamic>? ownStore;
  final bool becameMerchant;
  final String storeStatus;
  final String? newStoreName;
  final Map<String, dynamic> profileEdits;
}

/// Answers the real REST contract with in-memory data, so the UI is fully
/// navigable before any backend exists.
///
/// It sits at the Dio layer on purpose. Every repository, mapper, provider and
/// screen above it is the production code path — only the bytes are invented.
/// That means:
///
///  * the real mappers run, so a parsing bug surfaces now, not on launch day;
///  * turning this off is one flag and changes no screen;
///  * nothing in the app "knows" it is in demo mode.
///
/// Cart, wishlist, addresses, orders and tickets are genuinely stateful here,
/// so adding to the cart and checking out behave like the real thing for the
/// length of a session. Nothing survives a restart.
///
/// This deliberately contradicts specification section 70 ("no fake API
/// responses"), at the product owner's request, while the backend is built.
class MockApiInterceptor extends Interceptor {
  MockApiInterceptor({this.latency = const Duration(milliseconds: 350)});

  /// Simulated round-trip time, so loading skeletons and spinners are real.
  final Duration latency;

  // ----------------------------------------------------------------- state ---

  String _email = 'demo@saba.app';

  /// The language of the request being answered. A real backend words its
  /// own messages in the language the app asks for; so does this, where the
  /// app shows the server's words as they are.
  String _language = 'en';
  bool get _arabic => _language.startsWith('ar');

  /// Cart lines: `{id, productId, variantId, quantity, savedForLater}`.
  final List<Map<String, dynamic>> _cart = <Map<String, dynamic>>[];
  String? _coupon;

  final Set<String> _wishlist = <String>{};

  final List<Map<String, dynamic>> _addresses = _demoAddresses();

  static List<Map<String, dynamic>> _demoAddresses() => <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'addr-1',
      'label': 'Home',
      'labelAr': 'المنزل',
      'fullName': 'Amina Saleh',
      'phone': '+9647701234567',
      'governorate': 'BAGHDAD',
      'area': 'Al-Mansour',
      'areaAr': 'المنصور',
      'street': 'Street 14, House 7',
      'streetAr': 'شارع 14، دار 7',
      'landmark': 'Behind Al-Mansour Mall',
      'landmarkAr': 'خلف مول المنصور',
      'isDefault': true,
    },
  ];

  final List<Map<String, dynamic>> _orders = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _returns = <Map<String, dynamic>>[];
  final Map<String, List<Map<String, dynamic>>> _reviews =
      <String, List<Map<String, dynamic>>>{};

  /// What shoppers have given each store since the demo started: the stars
  /// added up, and how many gave them. Shared, because a store's rating is
  /// public - every shopper sees the same one.
  final Map<String, (num, int)> _givenRatings = <String, (num, int)>{};

  /// Orders this shopper has answered the rating sheet for, and how many
  /// times they have put it off. Theirs, so they travel with the account.
  final Set<String> _ratedOrders = <String>{};
  final Map<String, int> _ratingSkips = <String, int>{};

  /// An order is offered for rating three times, then let go.
  static const int _ratingAsks = 3;

  /// Demo state deliberately lives for the whole process, so a cart or a
  /// revoked session survives navigation the way a real backend would.
  /// `DioFactory` therefore holds one shared instance - which makes tests in
  /// the same run share it too. This puts it back to a known state.
  @visibleForTesting
  void resetForTesting() {
    _save = null;
    _saved = null;
    resetDemoData();
  }

  /// Everything back to the first day of the demo, and that written to the
  /// phone at once. What is kept on the device stays kept: this is the demo
  /// starting again, not the saving being turned off.
  void resetDemoData() {
    _pushAddresses.clear();
    _email = 'demo@saba.app';
    _cannedAt = DateTime.now();
    _cart.clear();
    _coupon = null;
    _wishlist.clear();
    _orders.clear();
    _returns.clear();
    _reviews.clear();
    _givenRatings.clear();
    _ratedOrders.clear();
    _ratingSkips.clear();
    _storeOrders.clear();
    _placedOrders.clear();
    _events.clear();
    _stockOverrides.clear();
    _otpCode = null;
    _otpPhone = null;
    phoneChecks = true;
    _unverifiedPhones.clear();
    _becameMerchant = false;
    _newStoreName = null;
    _storeStatus = 'APPROVED';
    _signup = null;
    _ownStore = null;
    _addresses
      ..clear()
      ..addAll(_demoAddresses());
    _tickets.clear();
    _ticketMessages.clear();
    _chats.clear();
    _seededChats.clear();
    _storeCoupons.clear();
    _profileEdits.clear();
    _readNotifications.clear();
    _phoneAccounts.clear();
    _storeDelivery.clear();
    _storeReturns.clear();
    _setAside.clear();
    _deletedAccounts.clear();
    _closedStores.clear();
    _storeDeletions.clear();
    _searchCounts.clear();
    for (final entry in _fixtureOriginals.entries) {
      MockData.productById(entry.key)
        ?..clear()
        ..addAll(entry.value);
    }
    _fixtureOriginals.clear();
    _addedBrands.clear();
    hiddenCategories.clear();
    _storeProducts.clear();
    _removedProducts.clear();
    _fixtureStatus.clear();
    _shown.clear();
    _takenDown.clear();
    _storeReviews.clear();
    _saveIfChanged();
  }

  final List<Map<String, dynamic>> _tickets = <Map<String, dynamic>>[];
  final Map<String, List<Map<String, dynamic>>> _ticketMessages =
      <String, List<Map<String, dynamic>>>{};

  /// Every chat between a customer and a store, kept once, the way a server
  /// keeps it: what a customer writes is what the store's inbox shows, and
  /// the store's answer comes back the same way. Not part of an account's
  /// snapshot, because both sides of a chat read the same copy.
  final Map<String, _Chat> _chats = <String, _Chat>{};

  /// The accounts whose demo chats have been written.
  final Set<String> _seededChats = <String>{};

  /// Accounts made in this session, by the phone they signed up with.
  final Map<String, String> _phoneAccounts = <String, String>{};

  /// Notifications read, as "email/id".
  final Set<String> _readNotifications = <String>{};

  /// Every store's orders, by store, kept once like the chats: a shopper's
  /// checkout writes each store its own part, the store moves it along, and
  /// the shopper's order reads the store's steps back.
  final Map<String, List<Map<String, dynamic>>> _storeOrders =
      <String, List<Map<String, dynamic>>>{};

  /// Every order a shopper placed, by id, whoever is signed in now - so a
  /// store's step reaches the shopper's own copy.
  final Map<String, Map<String, dynamic>> _placedOrders =
      <String, Map<String, dynamic>>{};

  /// What happened to one side because of the other - a new order at a
  /// store, a store's step on a shopper's order - newest first. `to` is an
  /// email, or `store:<id>` for a store's inbox.
  final List<Map<String, dynamic>> _events = <Map<String, dynamic>>[];

  /// Every store's coupons, kept once like the chats: the store writes them
  /// and every shopper reads them.
  final Map<String, List<Map<String, dynamic>>> _storeCoupons =
      <String, List<Map<String, dynamic>>>{};

  int _counter = 0;

  /// When the demo's own notifications - "Welcome", "A new order" - were
  /// sent: once, when the demo started. They were stamped "now" on every
  /// read, so they showed the time of the last sign-in (the tester).
  DateTime _cannedAt = DateTime.now();

  String _nextId(String prefix) => '$prefix-${++_counter}';

  // ----------------------------------------------------------- on the phone ---

  /// Where the state goes after each change; null keeps it in memory only,
  /// as tests do.
  void Function(String document)? _save;

  /// The document last handed to [_save].
  String? _saved;

  /// Keeps this demo server on the phone: puts back [saved], the document
  /// [save] was last given, and gives [save] every change from now on.
  ///
  /// A document from an older version of the app is dropped, and the demo
  /// starts as new.
  void keepOnDevice({
    required String? saved,
    required void Function(String document) save,
  }) {
    if (saved != null) {
      try {
        if (_decodeState(saved)) _saved = saved;
      } on Object catch (error) {
        // A damaged document must not stop the app from opening.
        debugPrint('Demo data could not be read, starting fresh: $error');
      }
    }
    _save = save;
  }

  void _saveIfChanged() {
    final save = _save;
    if (save == null) return;
    final document = _encodeState();
    if (document == _saved) return;
    _saved = document;
    save(document);
  }

  // ------------------------------------------------------------ interception ---

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    await Future<void>.delayed(latency);

    final segments = options.path
        .split('?')
        .first
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);

    _language = options.headers['Accept-Language']?.toString() ?? 'en';
    _endSalesPast();
    final reply = _route(options.method.toUpperCase(), segments, options);
    _saveIfChanged();

    if (reply.statusCode >= 400) {
      handler.reject(
        DioException.badResponse(
          statusCode: reply.statusCode,
          requestOptions: options,
          response: Response<dynamic>(
            requestOptions: options,
            statusCode: reply.statusCode,
            data: <String, dynamic>{
              'success': false,
              'message':
                  (reply.data as Map<String, dynamic>?)?['message'] ?? '',
              'code': ?(reply.data as Map<String, dynamic>?)?['code'],
              // Which field each problem belongs to. It was dropped here, so
              // every demo error arrived as a banner and never on its field.
              'errors': ?(reply.data as Map<String, dynamic>?)?['errors'],
              'data': null,
              'meta': const <String, dynamic>{},
            },
          ),
        ),
      );
      return;
    }

    handler.resolve(
      Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
        data: <String, dynamic>{
          'success': true,
          'message': '',
          // The admin reads names in both languages, whatever it asks in
          // (API_CONTRACT.md 1.6): nothing of its is turned into Arabic.
          'data': _arabic && segments.first != 'admin'
              ? _inArabic(_asSaved(reply.data))
              : _asSaved(reply.data),
          'meta': reply.meta,
        },
      ),
    );
  }

  /// Every store an owner has saved, by id: the one signed in now and the
  /// ones set aside when someone else signed in.
  ///
  /// The demo keeps a store twice: as MockData made it, which products, the
  /// session and the lists copy, and as its owner last saved it. Saving
  /// wrote the second and almost every reply read the first, so a new logo
  /// or a new city reached the store page and nothing else.
  Map<String, Map<String, dynamic>> get _savedStores => {
    for (final store in [
      for (final account in _setAside.values) account.ownStore,
      _ownStore,
    ].nonNulls)
      '${store['id']}': store,
  };

  static const List<String> _storeFaceKeys = [
    'storeName',
    'logoUrl',
    'governorate',
  ];

  /// [value] with every copy of a saved store as it is now: its name, its
  /// logo and its city.
  Object? _asSaved(Object? value, [Map<String, Map<String, dynamic>>? saved]) {
    saved ??= _savedStores;
    if (saved.isEmpty) return value;
    if (value is List) return [for (final item in value) _asSaved(item, saved)];
    if (value is! Map) return value;
    final map = <String, dynamic>{
      for (final entry in value.entries)
        '${entry.key}': _asSaved(entry.value, saved),
    };
    final store = saved['${map['id']}'];
    if (store != null && map.containsKey('storeName')) {
      for (final key in _storeFaceKeys) {
        if (store.containsKey(key)) map[key] = store[key];
      }
    }
    return map;
  }

  /// [value] in Arabic, as a server picks it by Accept-Language.
  ///
  /// Any field beside its Arabic - `description` and `descriptionAr`,
  /// `name` and `nameAr` - answers with the Arabic. It used to be the name
  /// alone, so a product's description and warranty, a store's description
  /// and address, and a chat's title stayed English in Arabic. A field with
  /// no Arabic keeps what it has. Option words ("Black", "Color") are
  /// translated where they appear: an option's label, a product's options,
  /// the colours they are painted in, and the filter they come from.
  Object? _inArabic(Object? value) {
    if (value is List) return [for (final item in value) _inArabic(item)];
    if (value is! Map) return value;
    final map = <String, dynamic>{
      for (final entry in value.entries) '${entry.key}': _inArabic(entry.value),
    };
    for (final entry in value.entries) {
      final key = '${entry.key}';
      if (key.length > 2 &&
          key.endsWith('Ar') &&
          entry.value is String &&
          (entry.value as String).isNotEmpty) {
        map[key.substring(0, key.length - 2)] = entry.value;
      }
    }
    if (map['variantLabel'] case final String label) {
      map['variantLabel'] = label.split(' · ').map(_optionWord).join(' · ');
    }
    for (final key in const ['options', 'optionColours']) {
      if (map[key] case final Map<dynamic, dynamic> words) {
        map[key] = <String, dynamic>{
          for (final entry in words.entries)
            _optionWord('${entry.key}'): entry.value is String
                ? _optionWord(entry.value as String)
                : entry.value,
        };
      }
    }
    // A filter attribute (`a-...`) and its values (`v-...`).
    if (map['id'] case final String id
        when id.startsWith('a-') || id.startsWith('v-')) {
      for (final key in const ['name', 'value', 'unit']) {
        if (map[key] case final String word) map[key] = _optionWord(word);
      }
    }
    return map;
  }

  /// Option words in Arabic; anything else as it is ("128GB", "Core i5").
  static String _optionWord(String word) => _optionWordsAr[word] ?? word;

  static const Map<String, String> _optionWordsAr = <String, String>{
    'Color': 'اللون',
    'Storage': 'السعة',
    'RAM': 'الذاكرة',
    'CPU': 'المعالج',
    'Screen Size': 'حجم الشاشة',
    'Black': 'أسود',
    'Silver': 'فضي',
    'Blue': 'أزرق',
    'in': 'إنش',
  };

  Map<String, dynamic> _body(RequestOptions options) {
    final data = options.data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return const <String, dynamic>{};
  }

  int _queryInt(RequestOptions options, String key, int fallback) {
    final raw = options.queryParameters[key];
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '') ?? fallback;
  }

  // --------------------------------------------------------------- routing ---

  _Reply _route(String method, List<String> path, RequestOptions options) {
    if (path.isEmpty) return const _Reply(<String, dynamic>{});

    return switch (path.first) {
      'auth' => _auth(method, path, options),
      'customers' => _customers(method, path, options),
      'categories' => _categories(method, path),
      'brands' => const _Reply(MockData.brands),
      'attributes' => const _Reply(<Map<String, dynamic>>[]),
      'products' => _products(method, path, options),
      'home' => _home(path),
      'stores' when path.length > 1 && path[1] == 'cities' => _Reply(
        _storeCities(),
      ),
      'search' => _search(method, path, options),
      'cart' => _cartRoutes(method, path, options),
      'wishlist' => _wishlistRoutes(method, path, options),
      'checkout' => _checkout(method, path, options),
      'orders' => _ordersRoutes(method, path, options),
      'returns' => _returnsRoutes(method, path, options),
      'refunds' => const _Reply(<Map<String, dynamic>>[]),
      'merchants' => _merchants(method, path, options),
      'notifications' => _notifications(method, path, options),
      'messages' => _messages(method, path, options),
      'reports' when method == 'POST' => _report(_body(options)),
      'support' => _support(method, path, options),
      'promotions' => _Reply(
        MockData.productSummaries.where(_isListed).take(6).toList(),
      ),
      'coupons' =>
        path.length == 1 && method == 'GET'
            ? _Reply(_availableCoupons())
            : const _Reply(<String, dynamic>{}),
      'admin' => _admin(method, path, options),
      'media' => _media(method, path, options),
      'devices' => _devices(method, options),
      // Anything unmapped answers successfully with nothing, so a screen shows
      // an empty state rather than an error.
      _ => const _Reply(<Map<String, dynamic>>[]),
    };
  }

  /// What an admin does: see what is waiting, and answer it.
  ///
  /// The demo admin signs in like anyone else and only reaches this if the
  /// account really is an admin - the same check a real server makes, so
  /// the web admin can take these routes as they are.
  /// One product as the admin queue shows it.
  /// A store's name, a new one's included: the demo's own are in MockData,
  /// one opened in the app only in its review.
  String _storeNameOf(String store) =>
      '${_storeReviews[store]?['storeName'] ?? _storeFace(store)['title']}';

  /// A category and the one above it, by id.
  static Map<dynamic, dynamic>? _categoryById(Object? id) {
    for (final parent in MockData.categories) {
      if (parent['id'] == id) return parent;
      for (final child in parent['children'] as List? ?? const <dynamic>[]) {
        if ((child as Map)['id'] == id) return child;
      }
    }
    return null;
  }

  /// A product as the admin reads it (API_CONTRACT.md 2, AdminProduct):
  /// both names whatever the language, its store and where the store stands,
  /// every photo and option. The queue sent one name already translated, so
  /// an admin approving it never saw what shoppers read in the other
  /// language.
  Map<String, dynamic> _adminProduct(Map<String, dynamic> product) {
    final id = '${product['id']}';
    final own = _storeProducts.contains(product);
    final store =
        '${product['merchantId'] ?? (product['merchant'] as Map)['id']}';
    final (:status, :isActive) = own
        ? (status: '${product['status']}', isActive: _shown[id] ?? true)
        : _shelfState(product);
    final stocked = _withStock(product);
    final category = _categoryById(product['categoryId']);
    final brand = product['brand'] as Map?;
    return <String, dynamic>{
      'id': id,
      'nameEn': product['nameEn'] ?? '',
      'nameAr': product['nameAr'] ?? '',
      'description': ?product['description'],
      'price': product['price'],
      'originalPrice': ?product['originalPrice'],
      'discountPercentage': ?product['discountPercentage'],
      'currencyCode': MockData.currency,
      'stockStatus': stocked['stockStatus'],
      'availableQuantity': stocked['availableQuantity'],
      'categoryId': product['categoryId'],
      'categoryName': category?['name'] ?? '',
      'categoryNameAr': category?['nameAr'] ?? '',
      if (brand != null)
        'brand': <String, dynamic>{'id': brand['id'], 'name': brand['name']},
      'merchant': <String, dynamic>{
        'id': store,
        'storeName': _storeNameOf(store),
        'status': _storeReviews[store]?['status'] ?? 'APPROVED',
      },
      'imageUrl': ?product['imageUrl'],
      'images': product['images'] ?? const <dynamic>[],
      'warranty': ?product['warranty'],
      'variants': [
        for (final variant in stocked['variants'] as List? ?? const [])
          <String, dynamic>{
            'id': (variant as Map)['id'],
            'price': variant['price'],
            'availableQuantity': variant['availableQuantity'],
            'stockStatus': variant['stockStatus'],
            'options': variant['options'] ?? const <String, dynamic>{},
          },
      ],
      'createdAt': product['createdAt'] ?? '',
      'status': status,
      'rejectionReason': ?product['rejectionReason'],
      'isActive': isActive,
      'takenDown': _takenDown.containsKey(id),
      'takenDownReason': ?_takenDown[id],
    };
  }

  /// A store as the admin reads it (API_CONTRACT.md 2, AdminStore).
  Map<String, dynamic> _adminStore(Map<String, dynamic> review) {
    final id = '${review['id']}';
    return <String, dynamic>{
      'id': id,
      'storeName': review['storeName'] ?? '',
      'status': review['status'],
      'fullName': review['fullName'] ?? '',
      'phone': review['phone'] ?? '',
      'country': review['country'] ?? 'Iraq',
      'governorate': review['governorate'],
      'reviewCount': 0,
      'delivery': ?_storeDelivery[id],
      'submittedAt': review['submittedAt'],
      'answeredAt': ?review['answeredAt'],
      'rejectionReason': ?review['rejectionReason'],
      // Drafts are the store's own business.
      'productCount': _storeProducts
          .where((p) => p['merchantId'] == id && p['status'] != 'DRAFT')
          .length,
    };
  }

  /// Why an admin's answer is refused, as API_CONTRACT.md 1.4 codes it.
  _Reply _adminRefusal(
    int statusCode,
    String code, {
    required String en,
    required String ar,
    String? field,
  }) {
    final message = _arabic ? ar : en;
    return _Reply(<String, dynamic>{
      'code': code,
      'message': message,
      if (field != null) 'errors': <String, dynamic>{field: message},
    }, statusCode: statusCode);
  }

  _Reply _admin(String method, List<String> path, RequestOptions options) {
    if (_currentUser()['role'] != 'ADMIN') {
      return _Reply(<String, dynamic>{
        'message': _arabic ? 'هذه الصفحة للمشرفين.' : 'Admins only.',
      }, statusCode: 403);
    }

    final what = path.length > 1 ? path[1] : '';
    final id = path.length > 2 ? path[2] : '';
    final step = path.length > 3 ? path[3] : '';

    // GET|PUT /admin/featured-stores - Home's rail (API_CONTRACT.md 3.9).
    // The PUT sends `storeIds`; both reply with `featured`.
    if (what == 'featured-stores') {
      if (method == 'PUT') {
        final body = _body(options)['storeIds'];
        if (body is! List) {
          return const _Reply(<String, dynamic>{}, statusCode: 422);
        }
        final ids = [for (final id in body) '$id'];
        final approved = {
          for (final merchant in MockData.merchants) '${merchant['id']}',
          for (final review in _storeReviews.values)
            if (review['status'] == 'APPROVED') '${review['id']}',
        };
        if (ids.toSet().length != ids.length || !approved.containsAll(ids)) {
          return const _Reply(<String, dynamic>{}, statusCode: 409);
        }
        _featuredStores
          ..clear()
          ..addAll(ids);
      }
      return _Reply(<String, dynamic>{
        'featured': [..._featuredStores],
      });
    }

    // GET /admin/queue - everything waiting for an answer.
    if (what == 'queue') {
      int oldestFirst(
        Map<String, dynamic> a,
        Map<String, dynamic> b,
        String by,
      ) => '${a[by]}'.compareTo('${b[by]}');
      return _Reply(<String, dynamic>{
        'stores': [
          for (final review in _storeReviews.values)
            if (_waiting(review['status'])) _adminStore(review),
        ]..sort((a, b) => oldestFirst(a, b, 'submittedAt')),
        'products': [
          for (final product in _storeProducts)
            if (product['status'] == 'PENDING') _adminProduct(product),
          // One of the demo's own products its store sent back for review.
          // "Submit for approval" moved it to waiting and the admin never
          // saw it, so it sat there for ever - the bug step 4 fixed for
          // new products, back again for the old ones.
          for (final entry in _fixtureStatus.entries)
            if (entry.value == 'PENDING')
              if (MockData.productById(entry.key) case final product?)
                _adminProduct(product),
        ]..sort((a, b) => oldestFirst(a, b, 'createdAt')),
      });
    }

    // POST /admin/products/:id/hide {reason} and /unhide - Saba's own
    // takedown (API_CONTRACT.md 6.8), apart from the store's switch.
    if (what == 'products' && (step == 'hide' || step == 'unhide')) {
      final product = _findProduct(id);
      if (product == null) {
        return const _Reply(<String, dynamic>{}, statusCode: 404);
      }
      if (step == 'unhide') {
        _takenDown.remove(id);
        return _Reply(_adminProduct(product));
      }
      final why = '${_body(options)['reason'] ?? ''}'.trim();
      if (why.isEmpty) return _noReason();
      _takenDown[id] = why;
      final name = '${product['name']}';
      final nameAr = '${product['nameAr'] ?? name}';
      _notify(
        'store:${product['merchantId'] ?? (product['merchant'] as Map)['id']}',
        'PRODUCT_APPROVAL',
        en: ('$name was taken down by Saba', 'Reason: $why.'),
        ar: ('أوقف سبأ عرض $nameAr', 'السبب: $why.'),
        target: ('STORE_PRODUCT', id),
      );
      return _Reply(_adminProduct(product));
    }

    // POST /admin/tickets/:id/status {status} - Saba moves a customer's
    // ticket (API_CONTRACT.md 3.8). The ticket is in whichever account
    // opened it, set aside while Saba is signed in.
    if (what == 'tickets' && step == 'status' && method == 'POST') {
      final ticket = [
        for (final account in _setAside.values) ...account.tickets,
        ..._tickets,
      ].where((t) => t['id'] == id).firstOrNull;
      if (ticket == null) {
        return const _Reply(<String, dynamic>{}, statusCode: 404);
      }
      final status = '${_body(options)['status']}';
      const statuses = [
        'OPEN',
        'IN_PROGRESS',
        'WAITING_FOR_CUSTOMER',
        'RESOLVED',
        'CLOSED',
      ];
      if (!statuses.contains(status)) {
        return const _Reply(<String, dynamic>{}, statusCode: 422);
      }
      if (status == ticket['status']) {
        return const _Reply(<String, dynamic>{}, statusCode: 409);
      }
      ticket
        ..['status'] = status
        ..['updatedAt'] = DateTime.now().toIso8601String();
      return _Reply(ticket);
    }

    final answer = switch (step) {
      'approve' => 'APPROVED',
      'reject' => 'REJECTED',
      _ => null,
    };
    // A rejection says why, and the store is told (API_CONTRACT.md 6.2): a
    // reject with no reason told the store nothing it could act on.
    final reason = '${_body(options)['reason'] ?? ''}'.trim();
    final noReason = answer == 'REJECTED' && reason.isEmpty;

    // POST /admin/products/:id/approve|reject for one of the demo's own
    // products: the answer is kept beside it, as the submit was, and the
    // reason on the product itself.
    if (what == 'products' &&
        answer != null &&
        method == 'POST' &&
        _fixtureStatus.containsKey(id)) {
      final product = MockData.productById(id)!;
      if (_fixtureStatus[id] != 'PENDING') return _answeredAlready();
      if (noReason) return _noReason();
      if (answer == 'APPROVED' && _noArabic(product)) return _needsArabic();
      _fixtureStatus[id] = answer;
      _keepFixture(product);
      _answerProduct(product, answer, reason);
      return _Reply(_adminProduct(product));
    }

    // POST /admin/stores/:id/approve|reject
    if (what == 'stores' && answer != null && method == 'POST') {
      final review = _storeReviews[id];
      if (review == null) {
        return const _Reply(<String, dynamic>{}, statusCode: 404);
      }
      if (!_waiting(review['status'])) return _answeredAlready();
      if (noReason) return _noReason();
      review['status'] = answer;
      review['answeredAt'] = DateTime.now().toUtc().toIso8601String();
      if (answer == 'REJECTED') {
        review['rejectionReason'] = reason;
      } else {
        review.remove('rejectionReason');
      }
      // Addressed to the store, not to the person who owns it: a store's
      // inbox is keyed `store:<id>`, so a notice sent to the owner's email
      // went where nothing reads, and an approved store was never told. The
      // product approval below always used the right key, which is why that
      // one arrived and this one did not.
      _notify(
        'store:$id',
        'STORE',
        en: answer == 'APPROVED'
            ? ('Your store is approved', 'You can start selling on Saba.')
            : ('Your store was not approved', 'Reason: $reason'),
        ar: answer == 'APPROVED'
            ? ('تمت الموافقة على متجرك', 'يمكنك البدء بالبيع على سبأ.')
            : ('لم تتم الموافقة على متجرك', 'السبب: $reason'),
        target: ('STORE', id),
      );
      return _Reply(_adminStore(review));
    }

    // POST /admin/products/:id/approve|reject
    if (what == 'products' && answer != null && method == 'POST') {
      final product = _storeProducts.firstWhere(
        (p) => p['id'] == id,
        orElse: () => <String, dynamic>{},
      );
      if (product.isEmpty) {
        return const _Reply(<String, dynamic>{}, statusCode: 404);
      }
      if (product['status'] != 'PENDING') return _answeredAlready();
      if (noReason) return _noReason();
      if (answer == 'APPROVED' && _noArabic(product)) return _needsArabic();
      product['status'] = answer;
      _answerProduct(product, answer, reason);
      return _Reply(_adminProduct(product));
    }

    // POST /admin/demo/reset - the whole demo back to its first day.
    return const _Reply(<String, dynamic>{}, statusCode: 404);
  }

  /// A store Saba can still answer.
  static bool _waiting(Object? status) => status == 'PENDING';

  static bool _noArabic(Map<String, dynamic> product) =>
      '${product['nameAr'] ?? ''}'.trim().isEmpty;

  _Reply _answeredAlready() => _adminRefusal(
    409,
    'CONFLICT_ERROR',
    en: 'This has been answered already.',
    ar: 'تمت الإجابة عن هذا من قبل.',
  );

  _Reply _noReason() => _adminRefusal(
    422,
    'VALIDATION_ERROR',
    field: 'reason',
    en: 'Write a reason.',
    ar: 'اكتب السبب.',
  );

  _Reply _needsArabic() => _adminRefusal(
    422,
    'BUSINESS_RULE_ERROR',
    field: 'nameAr',
    en: 'A product needs its Arabic name before it is approved.',
    ar: 'يحتاج المنتج إلى اسمه بالعربية قبل الموافقة عليه.',
  );

  /// Saba's answer on [product]: the reason kept with a rejection, cleared
  /// by an approval, and the store told either way - with the reason.
  void _answerProduct(
    Map<String, dynamic> product,
    String answer,
    String reason,
  ) {
    if (answer == 'REJECTED') {
      product['rejectionReason'] = reason;
    } else {
      product.remove('rejectionReason');
    }
    final name = '${product['name']}';
    final nameAr = '${product['nameAr'] ?? name}';
    _notify(
      'store:${product['merchantId'] ?? (product['merchant'] as Map)['id']}',
      'PRODUCT_APPROVAL',
      en: answer == 'APPROVED'
          ? ('$name is approved', 'Shoppers can find it now.')
          : (
              '$name was not approved',
              'Reason: $reason. Change it and send it again.',
            ),
      ar: answer == 'APPROVED'
          ? ('تمت الموافقة على $nameAr', 'يستطيع المتسوقون إيجاده الآن.')
          : (
              'لم تتم الموافقة على $nameAr',
              'السبب: $reason. عدّله وأرسله مرة أخرى.',
            ),
      target: ('STORE_PRODUCT', '${product['id']}'),
    );
  }

  /// Demo SMS. A real gateway sends the code and never says what it was; here
  /// it comes back in the response and the screen prints it, because a tester
  /// with no SIM would otherwise be stuck on a screen they cannot pass. The
  /// one field `demoCode` is the whole difference - drop it and this is the
  /// real contract.
  /// Set when a merchant signs up: the account is theirs, with a new store,
  /// rather than the demo persona behind the email.
  bool _becameMerchant = false;

  /// A brand new store is not approved yet, and the dashboard says so.
  String _storeStatus = 'APPROVED';

  /// Who signed up in this session, as they described themselves.
  ///
  /// Sign-up used to keep the email and nothing else, and the role came from
  /// whether the address contained "merchant". So a merchant who signed up as
  /// omar@gmail.com landed in the shopper app as the demo customer, and the
  /// name, store, city and country they had typed were all thrown away.
  Map<String, dynamic>? _signup;

  /// The signed-in merchant's own store, as they last saved it.
  ///
  /// Null means the demo store, untouched. Merchant sign-up creates
  /// it; Store settings updates it. Everything that shows the store reads it,
  /// so what the merchant types is what the account, the settings screen and
  /// the public store page all say. Before, Store settings saved into the
  /// "open a store" branch - it turned the demo merchant into a new store
  /// under review - and reading the store always returned the demo record,
  /// so no edit ever showed.
  Map<String, dynamic>? _ownStore;

  /// What the account holder changed on Edit profile. It was returned by
  /// the save and then forgotten, so the old name came back the next time
  /// the account was read.
  final Map<String, dynamic> _profileEdits = <String, dynamic>{};

  /// Push addresses by token, as the real server keeps them (S10): one
  /// phone, one address, and it moves to whoever signs in on that phone.
  final Map<String, Map<String, dynamic>> _pushAddresses =
      <String, Map<String, dynamic>>{};

  @visibleForTesting
  Map<String, Map<String, dynamic>> get pushAddresses =>
      Map<String, Map<String, dynamic>>.unmodifiable(_pushAddresses);

  _Reply _devices(String method, RequestOptions options) {
    final token = '${_body(options)['token'] ?? ''}';
    if (token.isEmpty) return const _Reply(<String, dynamic>{});
    if (method == 'PUT') {
      _pushAddresses[token] = <String, dynamic>{
        'account': _currentUser()['id'],
        'platform': _body(options)['platform'],
        'language': _body(options)['language'],
      };
    } else if (method == 'DELETE') {
      _pushAddresses.remove(token);
    }
    return const _Reply(<String, dynamic>{});
  }

  Map<String, dynamic> _currentUser() {
    final user = _signedInUser();
    // Asked to be deleted: a fact of the store, as its review is. Read by the
    // id on the account itself: _shelfStore asks this.
    if (user['merchant'] case final Map<String, dynamic> store
        when _storeDeletions.containsKey(store['id'])) {
      return <String, dynamic>{
        ...user,
        'merchant': <String, dynamic>{
          ...store,
          'deletionRequestedAt': _storeDeletions[store['id']],
        },
      };
    }
    return user;
  }

  Map<String, dynamic> _signedInUser() {
    final user = <String, dynamic>{
      ...MockData.userFor(_email),
      // Each account its own id. The three demo people keep theirs; any
      // other account is named by the email or phone it signed up with,
      // which no one else has. Every shopper used to be "u-customer", so
      // the app could not tell one account from the next.
      if (!MockData.demoPhones.containsValue(_email)) 'id': 'u-$_email',
    };
    final signup = _signup;
    if (signup != null) {
      // The account they created, not the demo persona behind the email.
      user
        ..remove('merchant')
        ..remove('city')
        ..addAll(signup);
    }
    user.addAll(_profileEdits);
    // A shopper is named as the admin web names them, from the phone
    // (website/src/data/people.ts), so an order placed here finds the same
    // person there. Settled by the role the account was made with, before
    // any store it opens: the id never changes. Only a phone that is the
    // account's own: an old email-only account borrows the demo persona's,
    // and would share Amina's id and so her cached lists.
    final ownsPhone =
        signup != null || MockData.demoPhones.containsValue(_email);
    if (user['phone'] case final String phone
        when ownsPhone && user['role'] == 'CUSTOMER' && phone.isNotEmpty) {
      user['id'] = _customerIdOf(phone);
    }
    final store = _ownStore;
    if (!_becameMerchant && store == null) return user;
    if (!_becameMerchant) {
      if (user['merchant'] is! Map<String, dynamic>) return user;
      // The demo merchant after editing their store: same store, new words.
      return <String, dynamic>{
        ...user,
        'merchant': <String, dynamic>{
          ...(user['merchant'] as Map<String, dynamic>),
          'storeName': store!['storeName'],
        },
      };
    }
    return <String, dynamic>{
      ...user,
      'role': 'MERCHANT',
      'merchant': <String, dynamic>{
        'id': store?['id'] ?? _newStoreId,
        'storeName': store?['storeName'] ?? _newStoreName ?? 'My store',
        // Where the admin's review has got to; a store cannot decide this
        // for itself, so it is not kept with the account.
        'status':
            _storeReviews[store?['id'] ?? _newStoreId]?['status'] ??
            _storeStatus,
        'rejectionReason':
            ?_storeReviews[store?['id'] ?? _newStoreId]?['rejectionReason'],
      },
    };
  }

  /// What each account owned when someone else signed in, by email, so
  /// signing back in finds it where it was left.
  final Map<String, _AccountSnapshot> _setAside = <String, _AccountSnapshot>{};

  /// Accounts that deleted themselves. A demo sign-in accepts any address,
  /// so without this the same one would come straight back with its old
  /// things; instead it starts as a new account would.
  final Set<String> _deletedAccounts = <String>{};

  /// Someone else is now signed in.
  ///
  /// The demo backend holds one cart, one order list, one address book for
  /// the whole session, and they passed from account to account: a shopper
  /// who signed up opened My orders on the orders someone else had placed.
  /// Each account now has its own. A new one starts empty; one that signed
  /// in before gets back what it left; the demo persona starts as it does
  /// when the app opens.
  void _switchAccount(String email, {required bool isNew}) {
    if (email != _email) _setAside[_email] = _snapshot();
    final saved = _setAside.remove(email);
    // An account that deleted itself comes back as a stranger, not as the
    // demo persona with its addresses.
    final deleted = _deletedAccounts.contains(email.toLowerCase());
    _restore(
      isNew || deleted || saved == null
          ? _AccountSnapshot.fresh(
              addresses: isNew || deleted ? const [] : _demoAddresses(),
            )
          : saved,
    );
    _email = email;
  }

  _AccountSnapshot _snapshot() => _AccountSnapshot(
    cart: [..._cart],
    coupon: _coupon,
    wishlist: {..._wishlist},
    addresses: [..._addresses],
    orders: [..._orders],
    returns: [..._returns],
    ratedOrders: {..._ratedOrders},
    ratingSkips: {..._ratingSkips},
    tickets: [..._tickets],
    ticketMessages: {..._ticketMessages},
    signup: _signup,
    ownStore: _ownStore,
    becameMerchant: _becameMerchant,
    storeStatus: _storeStatus,
    newStoreName: _newStoreName,
    profileEdits: {..._profileEdits},
  );

  void _restore(_AccountSnapshot account) {
    _cart
      ..clear()
      ..addAll(account.cart);
    _coupon = account.coupon;
    _wishlist
      ..clear()
      ..addAll(account.wishlist);
    _addresses
      ..clear()
      ..addAll(account.addresses);
    _orders
      ..clear()
      ..addAll(account.orders);
    _returns
      ..clear()
      ..addAll(account.returns);
    _ratedOrders
      ..clear()
      ..addAll(account.ratedOrders);
    _ratingSkips
      ..clear()
      ..addAll(account.ratingSkips);
    _tickets
      ..clear()
      ..addAll(account.tickets);
    _ticketMessages
      ..clear()
      ..addAll(account.ticketMessages);
    _signup = account.signup;
    _ownStore = account.ownStore;
    _becameMerchant = account.becameMerchant;
    _storeStatus = account.storeStatus;
    _newStoreName = account.newStoreName;
    _profileEdits
      ..clear()
      ..addAll(account.profileEdits);
  }

  /// The id of the store this account opened. Every new store was "m-new",
  /// so two stores opened on one phone shared their orders, coupons and
  /// delivery settings.
  String get _newStoreId =>
      'm-new-${_email.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '')}';

  /// A new store: the merchant's words, waiting for review.
  void _openStore(Map<String, dynamic> body, {required String status}) {
    final name = (body['storeName'] ?? '').toString().trim();
    _newStoreName = name;
    _becameMerchant = true;
    _storeStatus = status;
    _storeReviews[_newStoreId] = <String, dynamic>{
      'id': _newStoreId,
      'storeName': name,
      'owner': _email,
      'fullName': '${body['fullName'] ?? ''}'.trim(),
      'phone': _samePhone(body['phone']),
      'country': body['country'] ?? 'Iraq',
      'status': status,
      'submittedAt': DateTime.now().toUtc().toIso8601String(),
      'governorate': ?body['governorate'],
    };
    _ownStore = <String, dynamic>{
      'id': _newStoreId,
      'storeName': name,
      'businessType': body['businessType'] ?? 'INDIVIDUAL',
      'businessAddress': ?body['businessAddress'],
      'description': ?(body['description'] ?? body['businessDescription']),
      'country': body['country'] ?? 'Iraq',
      'governorate': ?body['governorate'],
      'rating': 0,
      'reviewCount': 0,
      'productCount': 0,
    };
  }

  /// The signed-in merchant's store record: their saved one, or the demo's.
  Map<String, dynamic> _ownStoreRecord() {
    final id = _shelfStore;
    final merchant = MockData.merchants.firstWhere(
      (m) => m['id'] == id,
      orElse: () => MockData.merchants.first,
    );
    return _ownStore ??
        <String, dynamic>{
          ...merchant,
          'businessType': 'COMPANY',
          'businessAddress': id == 'm-2'
              ? 'Corniche Street, Al-Ashar'
              : 'Al-Mansour, Street 14',
        };
  }

  /// The demo store the signed-in owner runs. It was always Nova: every
  /// store login opened the same shelf, orders and settings.
  String get _shelfStore => _myStoreId ?? 'm-1';

  String? _newStoreName;

  /// An account created in this session. It has no history of its own, so
  /// it gets none of the demo persona's: a merchant who signed up as "lolav"
  /// was shown the demo store's 18,420,000 in revenue and 142 orders.
  bool get _isNewAccount => _signup != null;

  /// A store opened in this session, at merchant sign-up.
  /// It has sold nothing, so it has no orders, revenue, payouts or rating,
  /// and its shelf holds only what the merchant has added.
  bool get _isNewStore => _becameMerchant;

  /// Every product a store has added, newest first, as full product
  /// records, each carrying the store it belongs to.
  ///
  /// Kept once and shared, the way a server keeps it: a product belongs to
  /// its store, not to whoever is signed in. It used to sit in the signed-in
  /// account's own things, so it vanished the moment anyone else signed in -
  /// and no admin could ever see it to approve it.
  final List<Map<String, dynamic>> _storeProducts = <Map<String, dynamic>>[];

  /// This store's own products.
  List<Map<String, dynamic>> get _addedProducts => <Map<String, dynamic>>[
    for (final product in _storeProducts)
      if (product['merchantId'] == _shelfStore) product,
  ];

  /// Demo products a store has deleted, and demo products whose approval
  /// has moved since the demo started. Shared, like the products
  /// themselves: `MockData.products` is const, so what a store does to one
  /// is kept beside it rather than written into it.
  final Set<String> _removedProducts = <String>{};
  final Map<String, String> _fixtureStatus = <String, String>{};

  /// Products a store has hidden from shoppers, or shown again, this
  /// session: true shown, false hidden. Over the demo's own start.
  final Map<String, bool> _shown = <String, bool>{};

  /// Products Saba took down, by id, with why (API_CONTRACT.md 6.8). Apart
  /// from the store's own switch: out of the shop whatever [_shown] says,
  /// and only Saba puts one back.
  final Map<String, String> _takenDown = <String, String>{};

  /// A product every shopper can see: its store added it and an admin
  /// approved it (specification section 10).
  bool _isOnSale(Map<String, dynamic> product) =>
      product['status'] == 'APPROVED' &&
      (_shown[product['id']] ?? true) &&
      !_takenDown.containsKey(product['id']);

  /// Where one of the demo's own products stands with its store: approved
  /// or not, and shown or hidden. The one rule the store's shelf and the
  /// shop both follow - the shelf said "hidden", "waiting" and "rejected"
  /// while the shop went on selling all of them.
  ///
  /// The two demo store logins keep a few off sale so every shelf tab has
  /// something in it; every other demo product is approved and shown.
  ({String status, bool isActive}) _shelfState(Map<String, dynamic> product) {
    final id = '${product['id']}';
    return (
      status: _fixtureStatus[id] ?? MockData.seededStatus[id] ?? 'APPROVED',
      isActive: _shown[id] ?? !MockData.seededHidden.contains(id),
    );
  }

  /// A product a shopper may see and buy: approved, not hidden, not
  /// deleted. Search, a category, a store's page, Home, related products,
  /// the wishlist and the cart all ask this.
  bool _isListed(Map<String, dynamic> product) {
    if (_removedProducts.contains(product['id'])) return false;
    if (_takenDown.containsKey(product['id'])) return false;
    if (_storeProducts.contains(product)) return _isOnSale(product);
    final state = _shelfState(product);
    return state.status == 'APPROVED' && state.isActive;
  }

  bool _isListedId(Object? id) => switch (_findProduct('$id')) {
    final product? => _isListed(product),
    null => false,
  };

  /// What each store that opened in the app is waiting for, by store id:
  /// its name, its owner, and where the review has got to. Shared, because
  /// an admin has to see a store they are not signed in as.
  final Map<String, Map<String, dynamic>> _storeReviews =
      <String, Map<String, dynamic>>{};

  /// One product: one a store added, or one of the demo's own.
  Map<String, dynamic>? _findProduct(String id) {
    if (_removedProducts.contains(id)) return null;
    for (final product in _storeProducts) {
      if (product['id'] == id) return product;
    }
    return MockData.productById(id);
  }

  /// A full product record from what the product form sends. New products
  /// wait for the catalogue team's review before buyers can see them.
  Map<String, dynamic> _productFromDraft(
    Map<String, dynamic> body, {
    required String id,
    String status = 'PENDING',
  }) {
    final store = _ownStoreRecord();
    final price = (body['price'] as num?)?.toDouble() ?? 0;
    final stock = (body['stock'] as num?)?.toInt() ?? 0;
    final images = [
      for (final url in (body['images'] as List?) ?? const <dynamic>[])
        url.toString(),
    ];
    final variants = (body['variants'] as List?) ?? const <dynamic>[];

    final english = '${body['name'] ?? ''}'.trim();
    final arabic = '${body['nameAr'] ?? ''}'.trim();
    return <String, dynamic>{
      'id': id,
      // What it is called where no language is asked for.
      'name': english.isEmpty ? arabic : english,
      if (english.isNotEmpty) 'nameEn': english,
      'nameAr': arabic,
      'description': ?body['description'],
      'price': price,
      'originalPrice': ?body['originalPrice'],
      'currencyCode': MockData.currency,
      'stockStatus': stock == 0
          ? 'OUT_OF_STOCK'
          : stock <= ((body['lowStockThreshold'] as num?) ?? 5)
          ? 'LOW_STOCK'
          : 'IN_STOCK',
      'availableQuantity': stock,
      'lowStockThreshold': (body['lowStockThreshold'] as num?)?.toInt() ?? 5,
      'sku': ?body['sku'],
      'barcode': ?body['barcode'],
      'categoryId': body['categoryId'],
      // Its city and logo too, as a demo product's store has them: without
      // a city the page drew no city pill and charged the out-of-town fee,
      // 6,000 to Baghdad from Baghdad, while checkout charged 3,000.
      'merchant': <String, dynamic>{
        'id': store['id'],
        'storeName': store['storeName'],
        'governorate': ?_storeCityOf('${store['id']}'),
        'logoUrl': ?store['logoUrl'],
      },
      'imageUrl': images.isEmpty ? null : images.first,
      'images': [
        for (var index = 0; index < images.length; index++)
          <String, dynamic>{
            'id': '$id-img$index',
            'url': images[index],
            'isPrimary': index == 0,
          },
      ],
      'warranty': ?body['warranty'],
      'returnPolicy': ?body['returnPolicy'],
      'attributes': body['attributes'] ?? const <dynamic>[],
      if (variants.isNotEmpty)
        'variants': [
          for (var index = 0; index < variants.length; index++)
            <String, dynamic>{
              // A new option gets a new id. By its place in the list it took
              // the id of the option that sat there, and that option's stock:
              // M changed to L reopened Red/L with Red/M's 2 (the tester).
              'id': (variants[index] as Map)['id'] ?? _nextId('$id-v'),
              'sku': (variants[index] as Map)['sku'],
              'price': (variants[index] as Map)['price'] ?? price,
              'availableQuantity': (variants[index] as Map)['stock'] ?? 0,
              // The form sends a list of name/value pairs; the catalogue
              // reads a map, as the demo products carry it.
              'options': <String, dynamic>{
                for (final option
                    in ((variants[index] as Map)['options'] as List?) ??
                        const <dynamic>[])
                  (option as Map)['name'].toString(): option['value'],
              },
            },
        ],
      'status': status,
      'rating': 0,
      'reviewCount': 0,
    };
  }

  // ------------------------------------------------------------ flash sales ---

  /// Flash sales whose end has come, ended: each product's price is again
  /// what it was before its sale. Run before every request, so nothing -
  /// Home, a product's page, the cart, checkout - reads a sale that is over.
  /// A real backend has to work the price out the same way when it reads
  /// it, or end sales with a scheduled job.
  void _endSalesPast() {
    final now = DateTime.now();
    for (final product in [..._storeProducts, ...MockData.products]) {
      if (DateTime.tryParse('${product['saleEndsAt']}') case final ends?
          when !ends.isAfter(now)) {
        _endSale(product);
      }
    }
  }

  /// One of this store's own products, or null.
  Map<String, dynamic>? _ownProduct(String id) {
    final product = _findProduct(id);
    if (product == null) return null;
    final store = product['merchantId'] ?? (product['merchant'] as Map)['id'];
    return store == _shelfStore ? product : null;
  }

  /// What a demo product was before a store first changed it, kept so a
  /// demo reset puts it back and the saved demo keeps the change.
  void _keepFixture(Map<String, dynamic> product) {
    final id = '${product['id']}';
    if (identical(MockData.productById(id), product)) {
      _fixtureOriginals.putIfAbsent(id, () => Map<String, dynamic>.of(product));
    }
  }

  /// A flash sale on [product], or a new price and end for the one running:
  /// the price before the sale becomes the original price, and the sale
  /// price the price. Each option comes down by the same amount.
  ///
  /// No review: the store owns its price, so it owns the discount.
  _Reply _startSale(Map<String, dynamic> product, Map<String, dynamic> body) {
    // Before the sale: the price now, plus what a running sale takes off.
    // Every option came down by that same amount.
    final offNow = _saleOff(product);
    num before(Map<dynamic, dynamic> priced) =>
        (priced['price'] as num) + offNow;

    final was = before(product);
    final sale = body['salePrice'];
    final ends = DateTime.tryParse('${body['saleEndsAt'] ?? ''}');
    final errors = <String, String>{};
    if (sale is! num || sale <= 0) {
      errors['salePrice'] = _arabic
          ? 'أدخل سعر العرض.'
          : 'Enter the sale price.';
    } else if (sale % 250 != 0) {
      errors['salePrice'] = _arabic ? _stepsAr : _stepsEn;
    } else if (sale >= was) {
      errors['salePrice'] = _arabic
          ? 'يجب أن يكون سعر العرض أقل من السعر العادي.'
          : 'The sale price must be lower than the normal price.';
    }
    if (ends == null || !ends.isAfter(DateTime.now())) {
      errors['saleEndsAt'] = _arabic
          ? 'اختر وقت انتهاء لم يمضِ بعد.'
          : 'Pick an end time that has not passed.';
    }

    final off = sale is num ? was - sale : 0;
    final options = [
      for (final variant in product['variants'] as List? ?? const <dynamic>[])
        <String, dynamic>{
          ...(variant as Map).cast<String, dynamic>(),
          'originalPrice': before(variant),
          'price': before(variant) - off,
          'discountPercentage': (off / before(variant) * 100).round(),
        },
    ];
    if (errors.isEmpty && options.any((o) => (o['price'] as num) < 250)) {
      errors['salePrice'] = _arabic
          ? 'هذا الخصم أكبر من سعر أحد خيارات المنتج.'
          : 'That takes more off than one of its options costs.';
    }
    if (errors.isNotEmpty) {
      return _Reply(<String, dynamic>{
        'message': errors.values.first,
        'errors': errors,
      }, statusCode: 422);
    }

    _keepFixture(product);
    product
      ..['originalPrice'] = was
      ..['price'] = sale
      ..['discountPercentage'] = (off / was * 100).round()
      ..['saleEndsAt'] = ends!.toUtc().toIso8601String();
    if (options.isNotEmpty) product['variants'] = options;
    return const _Reply(<String, dynamic>{});
  }

  /// What [product]'s running flash sale takes off; nothing without one.
  static num _saleOff(Map<String, dynamic> product) {
    if (product['saleEndsAt'] == null) return 0;
    final price = product['price'] as num;
    return ((product['originalPrice'] as num?) ?? price) - price;
  }

  /// [product]'s flash sale over: its price, and each option's, is what it
  /// was before. Worked out from what the sale took off rather than read
  /// from each option, which an edit during the sale does not send.
  void _endSale(Map<String, dynamic> product) {
    final off = _saleOff(product);
    _keepFixture(product);
    product
      ..['price'] = (product['price'] as num) + off
      ..remove('originalPrice')
      ..remove('discountPercentage')
      ..remove('saleEndsAt');
    final variants = product['variants'] as List? ?? const <dynamic>[];
    if (variants.isEmpty) return;
    product['variants'] = [
      for (final variant in variants)
        <String, dynamic>{
            ...(variant as Map).cast<String, dynamic>(),
            'price': (variant['price'] as num) + off,
          }
          ..remove('originalPrice')
          ..remove('discountPercentage'),
    ];
  }

  String? _otpCode;
  String? _otpPhone;

  /// Whether Saba is checking numbers by SMS. Off (the user's call) means
  /// sign-up sends no code: the server hands back the token itself, and new
  /// accounts are left unverified until checks come back. On by default, as a
  /// release build ships; a test flips it to walk the other mode.
  @visibleForTesting
  bool phoneChecks = true;

  /// Accounts that signed up while [phoneChecks] was off: their next sign-in
  /// once checks are on is refused with PHONE_NOT_VERIFIED until a code.
  final Set<String> _unverifiedPhones = <String>{};

  _Reply _otpRoutes(List<String> path, RequestOptions options) {
    final action = path.length > 2 ? path[2] : '';
    final body = _body(options);

    switch (action) {
      case 'send':
        final phone = (body['phone'] ?? '').toString().replaceAll(
          RegExp(r'\D'),
          '',
        );
        if (phone.length < 8) {
          final message = _arabic
              ? 'أدخل رقم هاتف صحيحًا'
              : 'Enter a valid phone number';
          return _Reply(<String, dynamic>{
            'message': message,
            'errors': <String, dynamic>{'phone': message},
          }, statusCode: 422);
        }
        // Signing up with a number that already has an account is refused
        // here, before any code: it went on to register, and the new
        // account took the number, and with it the old one, for good.
        // One number however it is written: 0751..., +964 751..., 964...,
        // Arabic digits. "+" before the typed digits made "+0751..." of a
        // number written with its 0, which matched nothing.
        final number = _samePhone(body['phone']);
        if (body['purpose'] == 'SIGN_UP' && _phoneIsTaken(number)) {
          return _Reply(<String, dynamic>{
            'message': _phoneTakenMessage,
          }, statusCode: 409);
        }
        // A forgotten password, for a number that has no account to reset.
        if (body['purpose'] == 'PASSWORD_RESET' && !_phoneIsTaken(number)) {
          return _Reply(<String, dynamic>{
            'message': _noAccountMessage,
            'errors': <String, dynamic>{'phone': _noAccountMessage},
          }, statusCode: 422);
        }
        // Checks off, and this is a sign-up: no code goes out. The token the
        // code screen would have made is handed back here, and sign-up skips
        // to the details form. Reset and verify-at-sign-in always send a code
        // (the user's call), so they fall through.
        if (!phoneChecks && body['purpose'] == 'SIGN_UP') {
          _otpPhone = number;
          return _Reply(<String, dynamic>{
            'expiresInSeconds': 0,
            'verificationToken': 'otp-$number',
          });
        }
        _otpPhone = number;
        // Derived from the number rather than random, so a hot restart in the
        // middle of a demo does not invalidate the code already on screen;
        // from its one form, so every way of writing it has the same code.
        final digits = number.replaceAll(RegExp(r'\D'), '');
        _otpCode = (digits.hashCode.abs() % 900000 + 100000).toString();
        return _Reply(<String, dynamic>{
          'expiresInSeconds': 60,
          'demoCode': _otpCode,
        });

      case 'verify':
        final code = (body['code'] ?? '').toString().trim();
        if (_otpCode == null || code != _otpCode) {
          final message = _arabic
              ? 'هذا الرمز غير صحيح.'
              : 'That code is not right.';
          return _Reply(<String, dynamic>{
            'message': message,
            'errors': <String, dynamic>{'code': message},
          }, statusCode: 400);
        }
        return _Reply(<String, dynamic>{'verificationToken': 'otp-$_otpPhone'});

      default:
        return const _Reply(<String, dynamic>{});
    }
  }

  /// A name over its limit - a person's 50, a store's 40 - or null. A
  /// 140-letter name was accepted and squashed unreadably on Home.
  _Reply? _nameTooLong(Map<String, dynamic> body) {
    for (final (field, most) in const [('fullName', 50), ('storeName', 40)]) {
      if ('${body[field] ?? ''}'.trim().length <= most) continue;
      final message = _arabic
          ? 'الاسم أطول من $most حرفاً.'
          : 'Keep the name to $most characters or fewer.';
      return _Reply(<String, dynamic>{
        'message': message,
        'errors': <String, dynamic>{field: message},
      }, statusCode: 422);
    }
    return null;
  }

  /// A store other than [except] in [city] already called [name], case and
  /// spaces aside, as a refusal on the store name; or null. Only in the same
  /// city: shop names repeat across Iraq, and two in different governorates
  /// are plausibly both real. A second "Nova Electronics" in Baghdad was
  /// created with no warning.
  // ponytail: a demo store renamed this session is still matched by its seed
  // name; the real backend checks its own table.
  _Reply? _storeNameTaken(Object? name, Object? city, {Object? except}) {
    String plain(Object? text) =>
        '${text ?? ''}'.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final wanted = plain(name);
    final taken =
        [
          for (final store in MockData.merchants)
            (
              store['id'],
              store['governorate'],
              [store['storeName'], store['storeNameAr']],
            ),
          for (final store in _storeReviews.values)
            (store['id'], store['governorate'], [store['storeName']]),
        ].any(
          (store) =>
              store.$1 != except &&
              store.$2 == city &&
              store.$3.any((known) => known != null && plain(known) == wanted),
        );
    if (!taken || wanted.isEmpty) return null;
    final message = _arabic
        ? 'يوجد متجر بهذا الاسم في هذه المحافظة. اختر اسماً آخر.'
        : 'A store in this city already has this name. Choose another.';
    return _Reply(<String, dynamic>{
      'message': message,
      'errors': <String, dynamic>{'storeName': message},
    }, statusCode: 422);
  }

  /// A number in its one form, +9647512223344, however it was written:
  /// with its 0, with +964 or 964, with spaces, in Arabic digits. Anything
  /// that is not an Iraqi mobile is compared as it was sent. Written two
  /// ways, one number made two accounts.
  static String _samePhone(Object? raw) =>
      IraqiPhone.normalize('${raw ?? ''}') ?? '${raw ?? ''}'.trim();

  /// Whether [phone] belongs to an account that still exists.
  bool _phoneIsTaken(String phone) {
    final number = _samePhone(phone);
    final account = _phoneAccounts[number] ?? MockData.demoPhones[number];
    return account != null && !_deletedAccounts.contains(account.toLowerCase());
  }

  String get _noAccountMessage =>
      _arabic ? 'لا يوجد حساب بهذا الرقم.' : 'No account uses this number.';

  String get _phoneTakenMessage => _arabic
      ? 'هذا الرقم مسجّل بحساب. سجّل الدخول بدلاً من ذلك.'
      : 'This number already has an account. Sign in instead.';

  // ------------------------------------------------------------------- auth ---

  _Reply _auth(String method, List<String> path, RequestOptions options) {
    final action = path.length > 1 ? path[1] : '';

    switch (action) {
      case 'login':
        final body = _body(options);
        // By phone, the usual way; the number finds the account.
        final phone = body['phone']?.toString();
        final byPhone = phone == null
            ? null
            : MockData.demoPhones[_samePhone(phone)] ??
                  _phoneAccounts[_samePhone(phone)];
        if (phone != null && byPhone == null) {
          final message = _arabic
              ? 'لا يوجد حساب بهذا الرقم. أنشئ حساباً أولاً.'
              : 'No account uses this number. Sign up first.';
          return _Reply(<String, dynamic>{
            'message': message,
            'errors': <String, dynamic>{'phone': message},
          }, statusCode: 422);
        }
        final email = byPhone ?? (body['email'] ?? _email).toString();
        // An account that deleted itself does not sign in again, by email
        // or by number: it is gone, as the screen promised.
        if (_deletedAccounts.contains(email.toLowerCase())) {
          final message = _arabic
              ? 'حُذف هذا الحساب. أنشئ حساباً جديداً.'
              : 'This account was deleted. Create a new one.';
          return _Reply(<String, dynamic>{'message': message}, statusCode: 422);
        }
        // Checks are on and this account's number was never proven (it signed
        // up while checks were off): the first sign-in is refused, and the
        // second carries the code from a VERIFY_PHONE send.
        final number = phone == null ? null : _samePhone(phone);
        if (phoneChecks &&
            number != null &&
            _unverifiedPhones.contains(number)) {
          final code = '${body['code'] ?? ''}'.trim();
          if (code.isEmpty) {
            final message = _arabic
                ? 'على سبأ أن تتحقق من رقمك مرة واحدة. اطلب رمزاً ثم سجّل الدخول به.'
                : 'Saba needs to check your number once. Ask for a code, then sign in with it.';
            return _Reply(<String, dynamic>{
              'code': 'PHONE_NOT_VERIFIED',
              'message': message,
            }, statusCode: 403);
          }
          if (_otpCode == null || code != _otpCode || _otpPhone != number) {
            final message = _arabic
                ? 'هذا الرمز غير صحيح.'
                : 'That code is not right.';
            return _Reply(<String, dynamic>{
              'message': message,
              'errors': <String, dynamic>{'code': message},
            }, statusCode: 422);
          }
          // Proven now, and signed in.
          _unverifiedPhones.remove(number);
        }
        // Someone else signing in gets their own account, not the last one's
        // store, orders or cart.
        if (email != _email) _switchAccount(email, isNew: false);
        return _Reply(<String, dynamic>{
          ..._currentUser(),
          ...MockData.tokensFor(_email),
        });

      case 'register':
        final body = _body(options);
        // An email is optional: without one, the phone names the account.
        final email = '${body['email'] ?? ''}'.trim();
        final phone = _samePhone(body['phone']);
        // Never over an account that has the number: sign-in opened the new
        // one, and the old one could not be reached again.
        if (_phoneIsTaken(phone)) {
          return _Reply(<String, dynamic>{
            'message': _phoneTakenMessage,
          }, statusCode: 409);
        }
        if (_nameTooLong(body) case final tooLong?) return tooLong;
        if (path.length > 2 && path[2] == 'merchant') {
          final taken = _storeNameTaken(body['storeName'], body['governorate']);
          if (taken != null) return taken;
        }
        final account = email.isNotEmpty ? email : phone;
        _switchAccount(account, isNew: true);
        _phoneAccounts[phone] = account;
        // Signed up while checks were off: no SMS proved this number, so a
        // later sign-in waits for one once checks are back on.
        if (!phoneChecks) _unverifiedPhones.add(phone);
        final asMerchant = path.length > 2 && path[2] == 'merchant';
        _signup = <String, dynamic>{
          'fullName': ?body['fullName'],
          'email': email.isEmpty ? null : email,
          'phone': phone.isEmpty ? null : phone,
          'country': body['country'] ?? 'Iraq',
          'governorate': ?body['governorate'],
          'role': asMerchant ? 'MERCHANT' : 'CUSTOMER',
        };
        if (asMerchant) {
          _openStore(body, status: 'PENDING');
        }
        return _Reply(<String, dynamic>{
          ..._currentUser(),
          ...MockData.tokensFor(_email),
        });

      case 'otp':
        return _otpRoutes(path, options);

      case 'refresh':
        return _Reply(MockData.tokensFor(_email));

      case 'reset-password':
        // The code sent by SMS to that number is the proof.
        // ponytail: the demo signs in with any password, so the new one is
        // checked but not kept; the real backend verifies the code and
        // stores the password (BUGS.md 122).
        final body = _body(options);
        final phone = _samePhone(body['phone']);
        if (!_phoneIsTaken(phone)) {
          return _Reply(<String, dynamic>{
            'message': _noAccountMessage,
            'errors': <String, dynamic>{'phone': _noAccountMessage},
          }, statusCode: 422);
        }
        if ('${body['password'] ?? ''}'.length < 8) {
          final message = _arabic
              ? 'كلمة المرور 8 أحرف على الأقل.'
              : 'Use at least 8 characters.';
          return _Reply(<String, dynamic>{
            'message': message,
            'errors': <String, dynamic>{'password': message},
          }, statusCode: 422);
        }
        if (body['token'] != _otpCode || _otpPhone != phone) {
          final message = _arabic
              ? 'هذا الرمز غير صحيح.'
              : 'That code is not right.';
          return _Reply(<String, dynamic>{
            'message': message,
            'errors': <String, dynamic>{'code': message},
          }, statusCode: 422);
        }
        return const _Reply(<String, dynamic>{});

      default:
        // logout, forgot-password, change-password
        return const _Reply(<String, dynamic>{});
    }
  }

  // -------------------------------------------------------------- customers ---

  _Reply _customers(String method, List<String> path, RequestOptions options) {
    // /customers/me/...
    final sub = path.length > 2 ? path[2] : '';

    if (sub == 'addresses') {
      return _addressRoutes(method, path, options);
    }

    // DELETE /customers/me - the account really goes. Everything it owned
    // is dropped and nothing is set aside for it, so signing up again with
    // the same address starts clean. It used to answer 200 and keep the
    // lot, so the account came back whole at the next sign-in.
    if (method == 'DELETE') {
      _setAside.remove(_email);
      _deletedAccounts.add(_email.toLowerCase());
      // Its number too. Left behind, the number still found the account at
      // sign-in, and the app opened on the demo shopper's profile with two
      // phone numbers on it.
      _phoneAccounts.removeWhere((_, account) => account == _email);
      _restore(_AccountSnapshot.fresh(addresses: const []));
      return const _Reply(<String, dynamic>{});
    }

    // GET/PATCH/DELETE /customers/me
    if (method == 'PATCH') {
      final body = _body(options);
      if (_nameTooLong(body) case final tooLong?) return tooLong;
      _profileEdits.addAll(<String, dynamic>{
        for (final field in const ['fullName', 'governorate'])
          if (body[field] != null) field: body[field],
      });
      return _Reply(_currentUser());
    }

    return _Reply(_currentUser());
  }

  _Reply _addressRoutes(
    String method,
    List<String> path,
    RequestOptions options,
  ) {
    final id = path.length > 3 ? path[3] : null;

    switch (method) {
      case 'POST':
        if (_nameTooLong(_body(options)) case final tooLong?) return tooLong;
        final address = <String, dynamic>{
          ..._body(options),
          'id': _nextId('addr'),
        };
        if (address['isDefault'] == true) {
          for (final existing in _addresses) {
            existing['isDefault'] = false;
          }
        }
        _addresses.add(address);
        return _Reply(address);

      case 'PUT':
        // /addresses/:id/default sets the default; /addresses/:id replaces it.
        if (path.length > 4 && path[4] == 'default') {
          for (final existing in _addresses) {
            existing['isDefault'] = existing['id'] == id;
          }
          return const _Reply(<String, dynamic>{});
        }
        if (_nameTooLong(_body(options)) case final tooLong?) return tooLong;
        final index = _addresses.indexWhere((a) => a['id'] == id);
        if (index >= 0) {
          _addresses[index] = <String, dynamic>{..._body(options), 'id': id};
          if (_addresses[index]['isDefault'] == true) {
            for (var i = 0; i < _addresses.length; i++) {
              if (i != index) _addresses[i]['isDefault'] = false;
            }
          }
          return _Reply(_addresses[index]);
        }
        return const _Reply(<String, dynamic>{});

      case 'DELETE':
        _addresses.removeWhere((a) => a['id'] == id);
        return const _Reply(<String, dynamic>{});

      default:
        return _Reply(_addresses);
    }
  }

  // ---------------------------------------------------------------- catalog ---

  _Reply _categories(String method, List<String> path) {
    if (path.length == 1) return _Reply(_shownCategories());

    final id = path[1];

    if (path.length > 2 && path[2] == 'attributes') {
      // Subcategories inherit their parent's attribute set.
      final direct = MockData.attributesByCategory[id];
      if (direct != null) return _Reply(direct);

      for (final parent in MockData.categories) {
        final children = parent['children'] as List<dynamic>? ?? const [];
        final isChild = children.any((child) => (child as Map)['id'] == id);
        if (isChild) {
          return _Reply(
            MockData.attributesByCategory[parent['id']] ??
                const <Map<String, dynamic>>[],
          );
        }
      }
      return const _Reply(<Map<String, dynamic>>[]);
    }

    if (path.length > 2 && path[2] == 'children') {
      for (final parent in MockData.categories) {
        if (parent['id'] == id) return _Reply(parent['children']);
      }
      return const _Reply(<Map<String, dynamic>>[]);
    }

    for (final category in MockData.categories) {
      if (category['id'] == id) return _Reply(category);
    }
    return const _Reply(<String, dynamic>{});
  }

  _Reply _products(String method, List<String> path, RequestOptions options) {
    if (path.length == 1) {
      final to = options.queryParameters['deliverTo']?.toString();
      return _page([
        for (final product in _filteredSummaries(options))
          _withDelivery(_withStock(product), to),
      ], options);
    }

    final id = path[1];
    final sub = path.length > 2 ? path[2] : '';

    switch (sub) {
      // The product's own category, and only it: headphones were followed
      // by an air fryer and a laptop. The store and the brand do not count.
      case 'related':
        final category = _findProduct(id)?['categoryId'];
        final others = [
          for (final product in _filteredSummaries(
            RequestOptions(queryParameters: <String, dynamic>{}),
          ))
            if (product['id'] != id &&
                category != null &&
                _findProduct('${product['id']}')?['categoryId'] == category)
              _withStock(product),
        ].take(6).toList();
        return _Reply(others);

      case 'variants':
        final product = _findProduct(id);
        return _Reply(product?['variants'] ?? const <Map<String, dynamic>>[]);

      default:
        final product = _findProduct(id);
        final ownStore =
            product != null && (product['merchant'] as Map)['id'] == _myStoreId;
        if (product == null || (!ownStore && !_isListed(product))) {
          return _Reply(<String, dynamic>{
            'message': _arabic
                ? 'هذا المنتج غير متوفر.'
                : 'This product is not available.',
          }, statusCode: 404);
        }
        final merchant = Map<String, dynamic>.from(product['merchant'] as Map);
        final category = _categoryById(product['categoryId']);
        return _Reply(<String, dynamic>{
          ..._withStock(product),
          'isWishlisted': _wishlist.contains(id),
          // Whether buyers can see it: its own store can open it when not.
          'isListed': _isListed(product),
          // Named, for the page's category pill.
          'categoryName': ?category?['name'],
          'categoryNameAr': ?category?['nameAr'],
          // Where its store delivers, so the page can say before the cart,
          // from the city the store is in now.
          'merchant': <String, dynamic>{
            ..._withRating(merchant),
            'governorate': ?_storeCityOf('${merchant['id']}'),
            'delivery': _deliveryOf('${merchant['id']}'),
            'isOpen': !_closedStores.contains('${merchant['id']}'),
          },
        });
    }
  }

  /// A product as it stands now: the stock its store set, or sold down to,
  /// not what it started the demo with. A product with options keeps each
  /// option's own count.
  // ponytail: the whole product's count, not each option's; per-option
  // stock when the demo needs it.
  /// [product] saying whether its store delivers to [to], the shopper's
  /// governorate - "Delivery available" on its card. Unsaid without one.
  Map<String, dynamic> _withDelivery(Map<String, dynamic> product, String? to) {
    if (to == null || to.isEmpty) return product;
    final store = '${(product['merchant'] as Map)['id']}';
    return <String, dynamic>{
      ...product,
      'deliveryAvailable':
          !_closedStores.contains(store) && _deliveryTerms(store, to) != null,
    };
  }

  /// [product] with the stock it has now, its options included.
  ///
  /// A product with options gets the sum of theirs, so the number on the
  /// page and the numbers on the colours can never disagree again.
  Map<String, dynamic> _withStock(Map<String, dynamic> product) {
    final variants = product['variants'] as List<dynamic>? ?? const [];
    // A list's card carries no options, so its stock is read from the whole
    // product: a card with options showed the catalogue's first count.
    final stock = _productStock(_findProduct('${product['id']}') ?? product);
    return <String, dynamic>{
      ...product,
      'availableQuantity': stock,
      'stockStatus': _stockStatus(stock),
      if (variants.isNotEmpty)
        'variants': [
          for (final variant in variants)
            <String, dynamic>{
              ...(variant as Map).cast<String, dynamic>(),
              'availableQuantity': _variantStock(variant),
              'stockStatus': _stockStatus(_variantStock(variant)),
            },
        ],
    };
  }

  /// Applies the filters the UI sends, so the filter sheet visibly works.
  List<Map<String, dynamic>> _filteredSummaries(RequestOptions options) {
    final query = options.queryParameters;
    // The demo's own products, and every product a store added that an
    // admin has approved.
    var results = <Map<String, dynamic>>[
      for (final product in _storeProducts)
        if (_isOnSale(product)) MockData.summaryOf(product),
      for (final product in MockData.productSummaries)
        if (_isListedId(product['id'])) product,
    ];

    final term = query['q']?.toString().trim();
    if (term != null && term.isNotEmpty) {
      results = results
          .where((p) => _found(term, _findProduct('${p['id']}')))
          .toList();
      // Counted once per search, on its first page, and only when it found
      // something: a typo nobody could use is not a popular search.
      if (results.isNotEmpty && _queryInt(options, 'page', 1) == 1) {
        final key = SearchText.normalize(term);
        final (text, count) = _searchCounts[key] ?? (term, 0);
        _searchCounts[key] = (text, count + 1);
      }
    }

    // A store is in one governorate, and its products are where it is.
    final governorate = query['governorate']?.toString();
    if (governorate != null && governorate.isNotEmpty) {
      final saved = _savedStores;
      results = results.where((p) {
        final merchant = p['merchant'] as Map;
        final now = saved['${merchant['id']}'];
        final city = now != null && now.containsKey('governorate')
            ? now['governorate']
            : merchant['governorate'];
        return city == governorate;
      }).toList();
    }

    final categoryId = query['categoryId']?.toString();
    if (categoryId != null && categoryId.isNotEmpty) {
      final ids = _categoryAndChildren(categoryId);
      results = results.where((p) {
        final full = _findProduct(p['id'].toString());
        return ids.contains(full?['categoryId']);
      }).toList();
    }

    final merchantId = query['merchantId']?.toString();
    if (merchantId != null && merchantId.isNotEmpty) {
      results = results
          .where((p) => (p['merchant'] as Map?)?['id'] == merchantId)
          .toList();
    }

    final brandIds = query['brandIds']?.toString().split(',') ?? const [];
    if (brandIds.isNotEmpty && brandIds.first.isNotEmpty) {
      results = results
          .where((p) => brandIds.contains((p['brand'] as Map?)?['id']))
          .toList();
    }

    final minPrice = double.tryParse(query['minPrice']?.toString() ?? '');
    final maxPrice = double.tryParse(query['maxPrice']?.toString() ?? '');
    if (minPrice != null) {
      results = results.where((p) => (p['price'] as num) >= minPrice).toList();
    }
    if (maxPrice != null) {
      results = results.where((p) => (p['price'] as num) <= maxPrice).toList();
    }

    // From the stock now, as the grid shows it, not the catalogue's first
    // count: a product sold out since stayed under "In stock only".
    if (query['inStock'] == true || query['inStock'] == 'true') {
      results = results.where((p) {
        final full = _findProduct('${p['id']}');
        return full != null &&
            _stockStatus(_productStock(full)) != 'OUT_OF_STOCK';
      }).toList();
    }

    if (query['onSale'] == true || query['onSale'] == 'true') {
      results = results.where((p) => p['originalPrice'] != null).toList();
    }

    final sorted = <Map<String, dynamic>>[...results];
    switch (query['sort']?.toString()) {
      case 'price_asc':
        sorted.sort((a, b) => (a['price'] as num).compareTo(b['price'] as num));
      case 'price_desc':
        sorted.sort((a, b) => (b['price'] as num).compareTo(a['price'] as num));
      case 'newest':
        // By the day it was added. Ids compared as text put p-9 above p-12.
        sorted.sort(
          (a, b) => '${b['createdAt']}'.compareTo('${a['createdAt']}'),
        );
      default:
        break;
    }

    return sorted;
  }

  /// Whether [term] finds [product]: its name in either language, or the
  /// name of its category or the category above it, folded by [SearchText]
  /// so every way of typing the Arabic meets.
  bool _found(String term, Map<String, dynamic>? product) {
    if (product == null) return false;
    final categoryId = product['categoryId'];
    return SearchText.matches(term, <String?>[
      '${product['name']}',
      product['nameEn'] as String?,
      product['nameAr'] as String?,
      for (final parent in MockData.categories)
        for (final category in <Map<dynamic, dynamic>>[
          parent,
          for (final child in parent['children'] as List? ?? const [])
            child as Map,
        ])
          if (category['id'] == categoryId) ...<String?>[
            if (!identical(category, parent)) ...<String?>[
              '${parent['name']}',
              parent['nameAr'] as String?,
            ],
            '${category['name']}',
            category['nameAr'] as String?,
          ],
    ]);
  }

  /// Searches that found something, by their folded form: the words as first
  /// typed, and how many times. Everyone's, like a real server's count.
  final Map<String, (String, int)> _searchCounts = <String, (String, int)>{};

  Set<String> _categoryAndChildren(String categoryId) {
    final ids = <String>{categoryId};
    for (final parent in MockData.categories) {
      final children = (parent['children'] as List<dynamic>? ?? const [])
          .map((child) => (child as Map)['id'].toString())
          .toList();
      if (parent['id'] == categoryId) ids.addAll(children);
    }
    return ids;
  }

  /// Slices a list into the page the client asked for.
  _Reply _page(List<Map<String, dynamic>> items, RequestOptions options) {
    final page = _queryInt(options, 'page', 1);
    final perPage = _queryInt(options, 'perPage', 20);
    final start = (page - 1) * perPage;

    final slice = start >= items.length
        ? const <Map<String, dynamic>>[]
        : items.sublist(start, math.min(start + perPage, items.length));

    return _Reply(
      slice,
      meta: <String, dynamic>{
        'page': page,
        'perPage': perPage,
        'total': items.length,
        'totalPages': perPage == 0 ? 1 : (items.length / perPage).ceil(),
      },
    );
  }

  // ------------------------------------------------------------------- home ---

  /// Home: the admin's banners, then what is on offer. Every product on Saba
  /// comes after these, in the app's own grid, from `/products`.
  ///
  /// The flash sale is the stores' own: every product whose store put it on
  /// a flash sale that has not ended, the soonest to end first, counting
  /// down to that one's end.
  _Reply _home(List<String> path) {
    final banners = <Map<String, dynamic>>[
      for (final banner in MockData.homeBanners)
        <String, dynamic>{
          ...banner,
          if (_arabic) ...?_bannerWordsAr[banner['id']],
        },
    ];
    if (path.length > 1 && path[1] == 'banners') return _Reply(banners);

    // The demo's own products and every one a store added that Saba
    // approved, less what is deleted or hidden. Home read the demo's alone,
    // so a store's own product never reached the flash sale.
    final listed = <Map<String, dynamic>>[
      for (final product in [..._storeProducts, ...MockData.products])
        if (_isListed(product)) product,
    ];

    // What a shopper can buy now: in stock, at a store that is open.
    final shelf = <Map<String, dynamic>>[
      for (final product in listed)
        if (!_closedStores.contains('${(product['merchant'] as Map)['id']}'))
          _withStock(MockData.summaryOf(product)),
    ].where((product) => product['stockStatus'] != 'OUT_OF_STOCK').toList();

    // The flash sales running, the soonest to end first. Every one kept
    // here ends in the future: those past their end were ended before this.
    final onSale = <Map<String, dynamic>>[
      for (final product in shelf)
        if (product['saleEndsAt'] != null) product,
    ]..sort((a, b) => '${a['saleEndsAt']}'.compareTo('${b['saleEndsAt']}'));

    // Only the stores Saba featured, in Saba's order (API_CONTRACT.md 6.11).
    final stores = <Map<String, dynamic>>[
      for (final id in _featuredStores)
        if (MockData.merchants.where((m) => m['id'] == id).firstOrNull
            case final merchant?)
          <String, dynamic>{
            ..._withRating(merchant),
            'productCount': listed
                .where((p) => (p['merchant'] as Map)['id'] == merchant['id'])
                .length,
          },
    ];

    return _Reply(<Map<String, dynamic>>[
      <String, dynamic>{'id': 's-banners', 'type': 'BANNER', 'items': banners},
      <String, dynamic>{
        'id': 's-categories',
        'type': 'CATEGORY',
        'title': _arabic ? 'تسوّق حسب القسم' : 'Shop by category',
        'items': _shownCategories(),
      },
      if (onSale.isNotEmpty)
        <String, dynamic>{
          'id': 's-flash',
          'type': 'FLASH_SALE',
          'endsAt': onSale.first['saleEndsAt'],
          'items': onSale,
        },
      // Where the admin placed it. It carries no items: the offers are per
      // account and come from /coupons.
      const <String, dynamic>{'id': 's-coupons', 'type': 'COUPONS'},
      // Left out, not sent empty, when no store is featured.
      if (stores.isNotEmpty)
        <String, dynamic>{
          'id': 's-merchants',
          'type': 'MERCHANT',
          'items': stores,
        },
    ]);
  }

  /// The stores on Home's rail, in order: Saba's choice (API_CONTRACT.md
  /// 3.9). The demo starts with every demo store, as Home had them.
  final List<String> _featuredStores = [
    for (final merchant in MockData.merchants) '${merchant['id']}',
  ];

  /// Every governorate with an open, approved store, in the list's order:
  /// Home's city chips, which no longer come from the featured rail.
  List<String> _storeCities() {
    final saved = _savedStores;
    final cities = <String>{
      for (final merchant in MockData.merchants)
        if (!_closedStores.contains(merchant['id']))
          '${saved['${merchant['id']}']?['governorate'] ?? merchant['governorate']}',
      for (final review in _storeReviews.values)
        if (review['status'] == 'APPROVED' &&
            review['governorate'] != null &&
            !_closedStores.contains(review['id']))
          '${saved['${review['id']}']?['governorate'] ?? review['governorate']}',
    };
    return [
      for (final city in Governorate.values)
        if (cities.contains(city.apiValue)) city.apiValue,
    ];
  }

  /// The banners' words in Arabic. A real backend stores both languages and
  /// answers in the one the app asks for.
  static const Map<String, Map<String, String>> _bannerWordsAr = {
    'ban-1': {
      'title': 'تخفيضات منتصف الموسم',
      'subtitle': 'خصم حتى 40% على إلكترونيات مختارة',
    },
    'ban-2': {'title': 'وصل حديثاً', 'subtitle': 'جديد متاجرنا'},
    'ban-3': {
      'title': 'أسبوع التوصيل المجاني',
      'subtitle': 'للطلبات فوق 50,000 د.ع',
    },
    'ban-4': {'title': 'المنزل والمطبخ', 'subtitle': 'خصم حتى 50% على الأجهزة'},
  };

  // ----------------------------------------------------------------- search ---

  _Reply _search(String method, List<String> path, RequestOptions options) {
    final sub = path.length > 1 ? path[1] : '';

    switch (sub) {
      case 'suggestions':
        final term = options.queryParameters['q']?.toString().trim() ?? '';
        final matches = MockData.products
            .where((p) => _isListed(p) && _found(term, p))
            .take(8)
            .map(
              (p) => <String, dynamic>{
                'text': _arabic ? (p['nameAr'] ?? p['name']) : p['name'],
                'type': 'PRODUCT',
                'productId': p['id'],
              },
            )
            .toList();
        return _Reply(matches);

      case 'popular':
        // What people have searched for and found, most often first.
        final counted = _searchCounts.values.toList()
          ..sort((a, b) => b.$2.compareTo(a.$2));
        return _Reply(<Map<String, dynamic>>[
          for (final (text, _) in counted.take(6)) {'text': text},
        ]);

      case 'history':
        if (method == 'DELETE') return const _Reply(<String, dynamic>{});
        return const _Reply(<Map<String, dynamic>>[]);

      case 'filters':
        return const _Reply(<Map<String, dynamic>>[]);

      // With the stock as it is now, as /products has it: search results
      // kept the catalogue's first count, "available" after the last one
      // was bought (the tester).
      default:
        final to = options.queryParameters['deliverTo']?.toString();
        return _page([
          for (final product in _filteredSummaries(options))
            _withDelivery(_withStock(product), to),
        ], options);
    }
  }

  // ------------------------------------------------------------------- cart ---

  _Reply _cartRoutes(String method, List<String> path, RequestOptions options) {
    final sub = path.length > 1 ? path[1] : '';

    if (sub == 'coupon') {
      if (method == 'DELETE') {
        _coupon = null;
        return _Reply(_buildCart());
      }
      // Only a code that exists goes on. Any other - a typo included - was
      // "applied" at no discount and reported as a success.
      final code = (_body(options)['code'] ?? '').toString().trim();
      final coupon = _couponFor(code);
      if (coupon == null) {
        // One that has not started says when it does: it said "not valid or
        // has expired" (the tester).
        final starts = [
          for (final store in _storeCoupons.values)
            for (final c in store)
              if (c['code'] == code.toUpperCase())
                DateTime.tryParse('${c['startsAt']}'),
        ].nonNulls.where((at) => at.isAfter(DateTime.now())).firstOrNull;
        final day = starts == null
            ? null
            : Formatters.monthDay(starts, locale: _language);
        final message = day != null
            ? (_arabic
                  ? 'يبدأ هذا الرمز في $day.'
                  : 'This code starts on $day.')
            : _arabic
            ? 'هذا الرمز غير صالح أو انتهت صلاحيته.'
            : 'This code is not valid or has expired.';
        return _Reply(<String, dynamic>{
          'message': message,
          'errors': <String, dynamic>{'code': message},
        }, statusCode: 422);
      }
      // A store's code takes money off that store's things only, so the
      // cart has to hold some, and enough of them.
      final storeId = coupon['merchantId'];
      if (storeId != null) {
        final store = coupon['merchantName'];
        final atStore = _storeSubtotal('$storeId');
        final minimum = coupon['minOrderAmount'] as num?;
        String? problem;
        if (atStore <= 0) {
          problem = _arabic
              ? 'هذا الرمز خاص بـ$store. أضف شيئاً من هذا المتجر أولاً.'
              : 'This code is for $store. Add something from that store first.';
        } else if (minimum != null && atStore < minimum) {
          final amount = _grouped(minimum);
          problem = _arabic
              ? 'اشترِ بـ$amount د.ع على الأقل من $store لاستخدام هذا الرمز.'
              : 'Spend at least $amount IQD at $store to use this code.';
        }
        if (problem != null) {
          return _Reply(<String, dynamic>{
            'message': problem,
            'errors': <String, dynamic>{'code': problem},
          }, statusCode: 422);
        }
      }
      _coupon = coupon['code'] as String;
      return _Reply(_buildCart());
    }

    if (sub == 'items') {
      final itemId = path.length > 2 ? path[2] : null;
      final action = path.length > 3 ? path[3] : '';

      switch (method) {
        case 'POST':
          if (action == 'save-for-later' || action == 'move-to-cart') {
            final line = _cart.firstWhere(
              (entry) => entry['id'] == itemId,
              orElse: () => <String, dynamic>{},
            );
            if (line.isNotEmpty) {
              line['savedForLater'] = action == 'save-for-later';
            }
            return _Reply(_buildCart());
          }

          final body = _body(options);
          final productId = body['productId'].toString();
          final variantId = body['variantId']?.toString();
          final quantity = (body['quantity'] as num?)?.toInt() ?? 1;

          // Nothing that has run out goes in, as the real server refuses it.
          // More than is left still does: checkout says "Only N left".
          final key = _stockKey(productId, variantId);
          if (_stockOf(key, _seededFor(key)) <= 0) {
            return _Reply(<String, dynamic>{
              'code': 'INVENTORY_ERROR',
              'message': _arabic
                  ? 'نفد هذا من المخزون، فلا يمكن إضافته إلى السلة.'
                  : "This has run out, so it can't go in the cart.",
            }, statusCode: 422);
          }

          // Adding the same variant again bumps the existing line, which is
          // what a real cart does.
          final existing = _cart.firstWhere(
            (entry) =>
                entry['productId'] == productId &&
                entry['variantId'] == variantId &&
                entry['savedForLater'] != true,
            orElse: () => <String, dynamic>{},
          );

          if (existing.isNotEmpty) {
            existing['quantity'] = (existing['quantity'] as int) + quantity;
          } else {
            _cart.add(<String, dynamic>{
              'id': _nextId('ci'),
              'productId': productId,
              'variantId': variantId,
              'quantity': quantity,
              'savedForLater': false,
            });
          }
          return _Reply(_buildCart());

        case 'PATCH':
          final line = _cart.firstWhere(
            (entry) => entry['id'] == itemId,
            orElse: () => <String, dynamic>{},
          );
          if (line.isNotEmpty) {
            line['quantity'] =
                (_body(options)['quantity'] as num?)?.toInt() ?? 1;
          }
          return _Reply(_buildCart());

        case 'DELETE':
          _cart.removeWhere((entry) => entry['id'] == itemId);
          return _Reply(_buildCart());
      }
    }

    return _Reply(_buildCart());
  }

  /// Builds the cart response, including the totals the server owns.
  /// The cart, priced. With [only], those lines instead - Buy now - with
  /// no coupon, since a coupon is applied to the cart.
  ///
  /// Delivery is each store's own, to the governorate of [addressId] - or
  /// of the default address, before one is chosen.
  Map<String, dynamic> _buildCart({
    List<Map<String, dynamic>>? only,
    Object? addressId,
  }) {
    final city = _deliveryCity(addressId);
    final active = only ?? _cart.where((line) => line['savedForLater'] != true);
    final saved = only == null
        ? _cart.where((line) => line['savedForLater'] == true)
        : const <Map<String, dynamic>>[];

    final groups = <String, List<Map<String, dynamic>>>{};

    for (final line in active) {
      final item = _cartItemJson(line);
      final merchantId = item['merchantId'].toString();
      groups.putIfAbsent(merchantId, () => <Map<String, dynamic>>[]).add(item);
    }

    // What this store asks to bring each part to that city - or nothing, if
    // it does not go there, or is closed. A part that cannot come is not in
    // the total: it counted things nobody could deliver.
    final reach = <String, ({num fee, String time})?>{
      for (final store in groups.keys)
        store: _closedStores.contains(store)
            ? null
            : _deliveryTerms(store, city),
    };
    num subtotal = 0;
    for (final entry in groups.entries) {
      if (reach[entry.key] == null) continue;
      for (final item in entry.value) {
        if (item['stockStatus'] == 'OUT_OF_STOCK') continue;
        subtotal += item['lineTotal'] as num;
      }
    }

    // What the applied coupon takes off, by its own rule: a store's coupon,
    // off that store's things. Rounded down to 250 IQD, the smallest note,
    // so every amount can be paid to a driver in cash.
    final applied = _coupon == null || only != null
        ? null
        : _couponFor(_coupon!);
    final storeId = applied?['merchantId'];
    final num base = storeId == null
        ? subtotal
        : reach[storeId] == null
        ? 0
        : (groups[storeId] ?? const <Map<String, dynamic>>[]).fold<num>(
            0,
            (total, item) => total + (item['lineTotal'] as num),
          );
    final minimum = applied?['minOrderAmount'] as num?;
    final num rawDiscount =
        applied == null || base <= 0 || (minimum != null && base < minimum)
        ? 0
        : applied['discountType'] == 'PERCENTAGE'
        ? base * (applied['value'] as num) / 100
        : math.min((applied['value'] as num).toDouble(), base);
    final num couponDiscount = _cashSteps(rawDiscount);

    final groupJson = <Map<String, dynamic>>[];
    num shipping = 0;

    for (final entry in groups.entries) {
      final merchant = MockData.merchants.firstWhere(
        (m) => m['id'] == entry.key,
        orElse: () => MockData.merchants.first,
      );
      // What can be bought: an out-of-stock line says "not charged".
      final groupSubtotal = entry.value.fold<num>(
        0,
        (total, item) => item['stockStatus'] == 'OUT_OF_STOCK'
            ? total
            : total + (item['lineTotal'] as num),
      );
      // A closed store takes no orders, wherever they are going.
      final closed = _closedStores.contains(entry.key);
      final terms = reach[entry.key];
      final num fee = terms?.fee ?? 0;
      shipping += fee;

      // ponytail: every coupon is one store's in v1; a Saba-wide one would
      // need its discount shared out across the stores' parts.
      final num discount = entry.key == '$storeId' ? couponDiscount : 0;

      groupJson.add(<String, dynamic>{
        'merchant': merchant,
        'items': entry.value,
        'subtotal': groupSubtotal,
        'discount': discount,
        // What this store's driver collects at the door; nothing from a
        // store that is not coming. The split listed it anyway, and the
        // cash added up to more than the total.
        'amountDue': ?(terms == null ? null : groupSubtotal - discount + fee),
        'currencyCode': MockData.currency,
        'deliversHere': terms != null,
        'shippingFee': ?terms?.fee,
        'deliveryTime': ?terms?.time,
        'shippingMethodName': ?(terms == null
            ? null
            : _arabic
            ? 'توصيل المتجر'
            : 'Store delivery'),
        'estimatedDelivery': closed
            ? (_arabic ? 'مغلق الآن' : 'Closed right now')
            : terms == null
            ? _noDeliveryText(city)
            : _timeText(terms.time),
      });
    }

    // No tax line: Iraq charges no VAT on these goods, and a price is what
    // the shopper pays. The total is the drivers' amounts added up.
    final total = subtotal - couponDiscount + shipping;

    return <String, dynamic>{
      'id': 'cart-1',
      'groups': groupJson,
      'savedForLater': saved.map(_cartItemJson).toList(),
      'totals': <String, dynamic>{
        'subtotal': subtotal,
        'discount': 0,
        'couponDiscount': couponDiscount,
        'shipping': shipping,
        'total': total,
        'currencyCode': MockData.currency,
      },
      if (applied != null)
        'coupon': <String, dynamic>{
          'code': applied['code'],
          'discountAmount': couponDiscount,
          'description': _couponDescription(applied),
          // On, but taking nothing off: under its minimum, or the store's
          // things left the cart. The chip stayed green (the tester).
          'applies': couponDiscount > 0,
          'minOrderAmount': ?applied['minOrderAmount'],
        },
    };
  }

  /// The coupons this account can use now (specification section 39): every
  /// store's own that is running today. Saba's own - SABA10, WELCOME - wait
  /// for v2: in a cash-only v1 there is nothing for Saba to pay them from.
  List<Map<String, dynamic>> _availableCoupons() => <Map<String, dynamic>>[
    for (final merchantId in <String>{
      for (final merchant in MockData.merchants) merchant['id'] as String,
      ..._storeCoupons.keys,
    })
      for (final coupon in _couponsOf(merchantId))
        if (_isLive(coupon)) _asOffer(coupon),
  ];

  /// A store's coupons, the demo stores' written the first time they are
  /// asked for. A store opened this session starts with none.
  List<Map<String, dynamic>> _couponsOf(String merchantId) =>
      _storeCoupons.putIfAbsent(merchantId, () {
        final now = DateTime.now();
        String day(int offset) =>
            DateTime(now.year, now.month, now.day + offset).toIso8601String();
        // Ends at the close of its last day, as a store's own coupon does.
        String end(int offset) => DateTime(
          now.year,
          now.month,
          now.day + offset,
          23,
          59,
          59,
        ).toIso8601String();
        return switch (merchantId) {
          'm-1' => <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'sc-nova10',
              'merchantId': 'm-1',
              'code': 'NOVA10',
              'discountType': 'PERCENTAGE',
              'value': 10,
              'minOrderAmount': 100000,
              'startsAt': day(-10),
              'endsAt': end(20),
              'usageLimit': 50,
              'usedCount': 12,
              'isActive': true,
            },
            <String, dynamic>{
              'id': 'sc-weekend15',
              'merchantId': 'm-1',
              'code': 'WEEKEND15',
              'discountType': 'PERCENTAGE',
              'value': 15,
              'startsAt': day(3),
              'endsAt': end(5),
              'usedCount': 0,
              'isActive': true,
            },
          ],
          'm-2' => <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'sc-atlas5000',
              'merchantId': 'm-2',
              'code': 'ATLAS5000',
              'discountType': 'FIXED',
              'value': 5000,
              'minOrderAmount': 50000,
              'startsAt': day(-3),
              'usageLimit': 100,
              'usedCount': 40,
              'isActive': true,
            },
          ],
          _ => <Map<String, dynamic>>[],
        };
      });

  /// Running today: not paused, started, not ended, uses left.
  static bool _isLive(Map<String, dynamic> coupon) {
    final now = DateTime.now();
    final starts = DateTime.tryParse('${coupon['startsAt']}');
    final ends = DateTime.tryParse('${coupon['endsAt'] ?? ''}');
    final limit = coupon['usageLimit'] as num?;
    return coupon['isActive'] != false &&
        (starts == null || !now.isBefore(starts)) &&
        (ends == null || now.isBefore(ends)) &&
        (limit == null || (coupon['usedCount'] as num? ?? 0) < limit);
  }

  /// A store coupon as a shopper is offered it.
  static Map<String, dynamic> _asOffer(Map<String, dynamic> coupon) =>
      <String, dynamic>{
        'code': coupon['code'],
        'discountType': coupon['discountType'],
        'value': coupon['value'],
        'currencyCode': MockData.currency,
        'minOrderAmount': coupon['minOrderAmount'],
        'merchantId': coupon['merchantId'],
        'merchantName': _storeFace(coupon['merchantId'] as String)['title'],
      };

  /// /merchants/me/coupons[/:id] - the signed-in store's own codes.
  _Reply _merchantCouponRoutes(
    String method,
    List<String> path,
    RequestOptions options,
  ) {
    final store = _myStoreId;
    if (store == null) {
      return const _Reply(<String, dynamic>{}, statusCode: 403);
    }
    final coupons = _couponsOf(store);
    final id = path.length > 3 ? path[3] : null;

    if (id == null) {
      if (method != 'POST') return _Reply(<Map<String, dynamic>>[...coupons]);
      final body = _couponFields(_body(options));
      final problem = _couponProblem(body, exceptId: null);
      if (problem != null) return problem;
      final coupon = <String, dynamic>{
        ...body,
        'id': _nextId('sc'),
        'merchantId': store,
        'usedCount': 0,
      };
      coupons.insert(0, coupon);
      return _Reply(coupon);
    }

    final index = coupons.indexWhere((coupon) => coupon['id'] == id);
    if (index < 0) return const _Reply(<String, dynamic>{}, statusCode: 404);

    switch (method) {
      case 'DELETE':
        coupons.removeAt(index);
        return const _Reply(<String, dynamic>{});
      case 'PATCH':
        coupons[index] = <String, dynamic>{
          ...coupons[index],
          'isActive': _body(options)['isActive'] == true,
        };
        return _Reply(coupons[index]);
      case 'PUT':
        final body = _couponFields(_body(options));
        final problem = _couponProblem(body, exceptId: id);
        if (problem != null) return problem;
        coupons[index] = <String, dynamic>{...coupons[index], ...body};
        return _Reply(coupons[index]);
      default:
        return _Reply(coupons[index]);
    }
  }

  /// What a store sent, tidied the way the server stores it.
  static Map<String, dynamic> _couponFields(Map<String, dynamic> body) {
    num? positive(Object? value) {
      final number = value is num ? value : num.tryParse('${value ?? ''}');
      return number == null || number <= 0 ? null : number;
    }

    return <String, dynamic>{
      'code': '${body['code'] ?? ''}'.trim().toUpperCase(),
      'discountType': body['discountType'] == 'FIXED' ? 'FIXED' : 'PERCENTAGE',
      'value': positive(body['value']) ?? 0,
      'minOrderAmount': positive(body['minOrderAmount']),
      'startsAt': body['startsAt'] ?? DateTime.now().toIso8601String(),
      'endsAt': body['endsAt'],
      'usageLimit': positive(body['usageLimit'])?.toInt(),
      'isActive': body['isActive'] != false,
    };
  }

  /// Why a coupon cannot be saved, as the server answers it, or null.
  _Reply? _couponProblem(Map<String, dynamic> coupon, {String? exceptId}) {
    _Reply fail(String field, String en, String ar) {
      final message = _arabic ? ar : en;
      return _Reply(<String, dynamic>{
        'message': message,
        'errors': <String, dynamic>{field: message},
      }, statusCode: 422);
    }

    final code = coupon['code'] as String;
    if (!RegExp(r'^[A-Z0-9]{3,15}$').hasMatch(code)) {
      return fail(
        'code',
        'Use 3 to 15 letters or numbers.',
        'استخدم من 3 إلى 15 حرفاً أو رقماً.',
      );
    }
    // A code is typed into any cart, so it has to be the only one of its
    // name anywhere on Saba, not only in this store.
    // Every store's, including one whose coupons nobody has opened yet.
    final taken =
        <String>{
          for (final merchant in MockData.merchants) merchant['id'] as String,
          ..._storeCoupons.keys,
        }.any(
          (store) => _couponsOf(
            store,
          ).any((other) => other['code'] == code && other['id'] != exceptId),
        );
    if (taken) {
      return fail(
        'code',
        'This code is already in use. Try another.',
        'هذا الرمز مستخدم بالفعل. جرّب رمزاً آخر.',
      );
    }
    final value = coupon['value'] as num;
    if (value <= 0) {
      return fail(
        'value',
        'Enter a discount above 0.',
        'أدخل خصماً أكبر من 0.',
      );
    }
    if (coupon['discountType'] != 'PERCENTAGE' && value % 250 != 0) {
      return fail('value', _stepsEn, _stepsAr);
    }
    if (coupon['discountType'] == 'PERCENTAGE' && value > 90) {
      return fail(
        'value',
        'A percentage can be at most 90.',
        'لا يمكن أن تزيد النسبة على 90.',
      );
    }
    final starts = DateTime.tryParse('${coupon['startsAt']}');
    final ends = DateTime.tryParse('${coupon['endsAt'] ?? ''}');
    if (starts != null && ends != null && !ends.isAfter(starts)) {
      return fail(
        'endsAt',
        'The end date must be after the start.',
        'يجب أن يكون تاريخ الانتهاء بعد البداية.',
      );
    }
    return null;
  }

  /// One of this account's coupons by its code, in any letter case.
  Map<String, dynamic>? _couponFor(String code) {
    final wanted = code.trim().toUpperCase();
    for (final coupon in _availableCoupons()) {
      if (coupon['code'] == wanted) return coupon;
    }
    return null;
  }

  String _couponDescription(Map<String, dynamic> coupon) {
    final value = coupon['value'] as num;
    final off = coupon['discountType'] == 'PERCENTAGE'
        ? '${value.round()}%'
        : _arabic
        ? '${_grouped(value)} د.ع'
        : '${_grouped(value)} IQD';
    final store = coupon['merchantName'];
    if (store != null) {
      return _arabic ? 'خصم $off في $store' : '$off off at $store';
    }
    return _arabic ? 'خصم $off على طلبك' : '$off off your order';
  }

  /// 100000 as "100,000".
  static String _grouped(num value) =>
      value.round().toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+$)'),
        (match) => '${match[1]},',
      );

  /// What the cart holds from one store, before any discount.
  num _storeSubtotal(String merchantId) => _cart
      .where((line) => line['savedForLater'] != true)
      .map(_cartItemJson)
      .where((item) => item['merchantId'] == merchantId)
      .fold<num>(0, (total, item) => total + (item['lineTotal'] as num));

  /// The applied coupon has been used once more, if it is a store's.
  void _countCouponUse() {
    final applied = _coupon == null ? null : _couponFor(_coupon!);
    final storeId = applied?['merchantId'];
    if (storeId == null) return;
    for (final coupon in _couponsOf('$storeId')) {
      if (coupon['code'] == applied!['code']) {
        coupon['usedCount'] = (coupon['usedCount'] as num? ?? 0) + 1;
      }
    }
  }

  Map<String, dynamic> _cartItemJson(Map<String, dynamic> line) {
    final product = _withStock(
      _findProduct(line['productId'].toString()) ?? MockData.products.first,
    );
    final variantId = line['variantId']?.toString();

    Map<String, dynamic>? variant;
    for (final candidate
        in (product['variants'] as List<dynamic>? ?? const [])) {
      if ((candidate as Map)['id'] == variantId) {
        variant = Map<String, dynamic>.from(candidate);
      }
    }

    final unitPrice = (variant?['price'] ?? product['price']) as num;
    final quantity = line['quantity'] as int;
    final options = variant?['options'] as Map?;

    return <String, dynamic>{
      'id': line['id'],
      'productId': product['id'],
      'variantId': variantId,
      'name': product['name'],
      'nameAr': ?product['nameAr'],
      'unitPrice': unitPrice,
      // An option's own original, or none: never the product's.
      'originalUnitPrice': variant == null
          ? product['originalPrice']
          : variant['originalPrice'],
      'quantity': quantity,
      'lineTotal': unitPrice * quantity,
      'currencyCode': MockData.currency,
      // Taken off sale since it went in: shown, not bought, not charged.
      'stockStatus': _isListed(product)
          ? (variant?['stockStatus'] ?? product['stockStatus'])
          : 'OUT_OF_STOCK',
      'availableQuantity':
          variant?['availableQuantity'] ?? product['availableQuantity'],
      'imageUrl': variant?['imageUrl'] ?? product['imageUrl'],
      'variantLabel': options?.values.join(' · '),
      'merchantId': (product['merchant'] as Map)['id'],
      'merchantName': (product['merchant'] as Map)['storeName'],
    };
  }

  // --------------------------------------------------------------- wishlist ---

  _Reply _wishlistRoutes(
    String method,
    List<String> path,
    RequestOptions options,
  ) {
    final productId = path.length > 2 ? path[2] : null;

    switch (method) {
      case 'POST':
        _wishlist.add(_body(options)['productId'].toString());
        return const _Reply(<String, dynamic>{});

      case 'DELETE':
        if (productId != null) _wishlist.remove(productId);
        return const _Reply(<String, dynamic>{});

      default:
        final items = MockData.productSummaries
            .where((p) => _wishlist.contains(p['id']) && _isListedId(p['id']))
            .map((p) => <String, dynamic>{...p, 'isWishlisted': true})
            .toList();
        return _Reply(items);
    }
  }

  // --------------------------------------------------------------- checkout ---

  _Reply _checkout(String method, List<String> path, RequestOptions options) {
    final sub = path.length > 1 ? path[1] : '';

    // Buy now sends the one line it is for; the cart sends none.
    final only = _buyNowLines(_body(options));

    if (sub == 'place-order') {
      final method = _body(options)['paymentMethodId'];
      if (method != null && method != 'pm-cod') {
        return _Reply(<String, dynamic>{
          'message': _arabic
              ? 'الدفع عند الاستلام فقط حالياً.'
              : 'Only cash on delivery for now.',
        }, statusCode: 422);
      }
      final priced = _buildCart(
        only: only,
        addressId: _body(options)['addressId'],
      );
      final refusal =
          _outOfStock(priced) ??
          _overFirstOrderLimit((priced['totals'] as Map)['total'] as num) ??
          _undeliverable(priced).firstOrNull;
      if (refusal != null) {
        return _Reply(<String, dynamic>{'message': refusal}, statusCode: 422);
      }
      final order = _createOrder(_body(options), only: only);
      if (only == null) {
        // A use only when it took something off: counted at 0 it burned a
        // one-use coupon for nothing (the tester).
        if (((order['discount'] as num?) ?? 0) > 0) _countCouponUse();
        _cart.clear();
        _coupon = null;
      }
      return _Reply(<String, dynamic>{
        'order': order,
        // Demo mode settles payment immediately rather than pretending to
        // redirect to a provider that does not exist.
        'requiresPaymentAction': false,
      });
    }

    // review, session, shipping-options, payment-methods
    final cart = _buildCart(only: only, addressId: _body(options)['addressId']);
    final totals = cart['totals'] as Map<String, dynamic>;
    final over = _overFirstOrderLimit(totals['total'] as num);
    final undeliverable = _undeliverable(cart);
    final gone = _outOfStock(cart);

    return _Reply(<String, dynamic>{
      'canPlaceOrder': over == null && undeliverable.isEmpty && gone == null,
      // A store that does not deliver here is said on its own delivery
      // row; it sat in this box with the cash limit, two unrelated things
      // in one warning (BUGS.md 17).
      'warnings': [?gone, ?over],
      'groups': [
        for (final group in cart['groups'] as List<dynamic>)
          <String, dynamic>{
            'merchantId': ((group as Map)['merchant'] as Map)['id'],
            'merchantName': (group['merchant'] as Map)['storeName'],
            // Units, not lines: two of one phone is two items, and it
            // read "1 item" above "2 × Nova X5 Smartphone".
            'itemCount': (group['items'] as List).fold<int>(
              0,
              (total, item) => total + ((item as Map)['quantity'] as int),
            ),
            'items': [
              for (final item in group['items'] as List)
                <String, dynamic>{
                  'name': (item as Map)['name'],
                  'quantity': item['quantity'],
                  'variantLabel': item['variantLabel'],
                },
            ],
            'subtotal': group['subtotal'],
            'discount': group['discount'],
            'amountDue': group['amountDue'],
            'currencyCode': MockData.currency,
            'shippingFee': group['shippingFee'],
            'estimatedDelivery': group['estimatedDelivery'],
            'deliversHere': group['deliversHere'],
            // One way: the store's own driver, at the store's own price.
            'selectedShippingOptionId': 'ship-store',
            'shippingOptions': [
              if (group['deliversHere'] == true)
                <String, dynamic>{
                  'id': 'ship-store',
                  'name': group['shippingMethodName'],
                  'fee': group['shippingFee'],
                  'currencyCode': MockData.currency,
                  'estimatedDelivery': group['estimatedDelivery'],
                },
            ],
          },
      ],
      'totals': totals,
      // Cash only in v1, and only cash is offered: a greyed-out card row
      // saying "coming soon" is a promise version 1 does not make.
      'paymentMethods': [
        <String, dynamic>{
          'id': 'pm-cod',
          'type': 'COD',
          'label': _arabic ? 'الدفع عند الاستلام' : 'Cash on delivery',
          'description': _arabic
              ? 'ادفع للمندوب نقداً عند وصول طلبك'
              : 'Pay the driver in cash when your order arrives',
        },
      ],
    });
  }

  /// Why this cart cannot be bought, or null: something in it has run out
  /// while the shopper was deciding.
  ///
  /// Checked when the order is placed, not only when the cart is drawn: two
  /// shoppers can be looking at the last one at the same time.
  String? _outOfStock(Map<String, dynamic> cart) {
    for (final group in cart['groups'] as List<dynamic>) {
      for (final item in (group as Map)['items'] as List<dynamic>) {
        final line = item as Map;
        final key = _stockKey(line['productId'], line['variantId']);
        // Taken off sale since it went in the cart: as good as gone.
        final left = _isListedId(line['productId'])
            ? _stockOf(key, _seededFor(key))
            : 0;
        if (left >= (line['quantity'] as num)) continue;
        final name = line['variantLabel'] == null
            ? '${line['name']}'
            : '${line['name']} - ${line['variantLabel']}';
        return left <= 0
            ? (_arabic
                  ? 'نفد $name. احذفه من السلة لإتمام الطلب.'
                  : '$name has run out. Take it out of the cart to order.')
            : (_arabic
                  ? 'بقي $left فقط من $name.'
                  : 'Only $left of $name left.');
      }
    }
    return null;
  }

  /// Saba's rule for a shopper who has never received and paid for an
  /// order: up to 1,000,000 IQD, in cash. A driver carrying more than that
  /// to someone unknown is the risk; one order delivered and paid lifts it.
  static const int _firstOrderLimit = 1000000;

  /// Why this total is too much for this shopper yet, or null.
  String? _overFirstOrderLimit(num total) {
    final trusted = _orders.any(
      (order) =>
          order['status'] == 'DELIVERED' && order['paymentStatus'] == 'PAID',
    );
    if (trusted || total <= _firstOrderLimit) return null;
    final limit = _grouped(_firstOrderLimit);
    return _arabic
        ? 'يمكن أن يصل طلبك الأول إلى $limit د.ع. احذف شيئاً من السلة، أو '
              'اشترِ الباقي بعد وصول هذا الطلب.'
        : 'Your first order can be up to $limit IQD. Take something out, or '
              'buy the rest once this order has arrived.';
  }

  static const String _stepsEn = 'Use steps of 250 IQD, like 12,250 or 12,500.';
  static const String _stepsAr =
      'استخدم مضاعفات 250 د.ع، مثل 12,250 أو 12,500.';

  /// [amount] down to a multiple of 250 IQD, the smallest note.
  static num _cashSteps(num amount) => (amount / 250).floor() * 250;

  /// A price a store typed that cash cannot pay exactly, refused.
  _Reply? _notInCashSteps(Map<String, dynamic> body) {
    final prices = <(String, Object?)>[
      ('price', body['price']),
      ('originalPrice', body['originalPrice']),
      for (final variant in (body['variants'] as List?) ?? const <dynamic>[])
        ('variants', (variant as Map)['price']),
    ];
    for (final (field, value) in prices) {
      if (value is num && value % 250 != 0) {
        final message = _arabic ? _stepsAr : _stepsEn;
        return _Reply(<String, dynamic>{
          'message': message,
          'errors': <String, dynamic>{field: message},
        }, statusCode: 422);
      }
    }
    return null;
  }

  /// Where each store delivers and what it asks, as it last saved them.
  /// Shared by every account: a store sets it, and every shopper's
  /// checkout reads it.
  final Map<String, Map<String, dynamic>> _storeDelivery =
      <String, Map<String, dynamic>>{};

  /// A store's delivery settings, the demo stores' written the first time.
  Map<String, dynamic> _deliveryOf(
    String merchantId,
  ) => _storeDelivery.putIfAbsent(
    merchantId,
    () => switch (merchantId) {
      // Nova, in Baghdad, sends everywhere.
      'm-1' => <String, dynamic>{
        'governorates': [for (final city in Governorate.values) city.apiValue],
        'feeInside': 3000,
        'timeInside': '1_2_DAYS',
        'feeOutside': 6000,
        'timeOutside': '3_5_DAYS',
      },
      // Atlas, in Basra, sends around the south and to Baghdad.
      'm-2' => <String, dynamic>{
        'governorates': ['BASRA', 'MAYSAN', 'DHI_QAR', 'MUTHANNA', 'BAGHDAD'],
        'feeInside': 2000,
        'timeInside': 'SAME_DAY',
        'feeOutside': 5000,
        'timeOutside': '2_3_DAYS',
      },
      // A demo store with its terms on its record: a copy, so a change to
      // them stays in this session.
      _ when _fixtureDelivery(merchantId) != null => <String, dynamic>{
        ..._fixtureDelivery(merchantId)!,
        'governorates': [
          ...(_fixtureDelivery(merchantId)!['governorates'] as List),
        ],
      },
      // A store opened this session delivers nowhere until its owner says
      // where and for how much. It was handed 5,000 IQD to its own city, a
      // fee nobody chose, which ticked "Set your delivery fee" for them.
      _ => <String, dynamic>{'governorates': <Object?>[]},
    },
  );

  static Map<String, dynamic>? _fixtureDelivery(String merchantId) {
    for (final merchant in MockData.merchants) {
      if (merchant['id'] == merchantId) {
        return merchant['delivery'] as Map<String, dynamic>?;
      }
    }
    return null;
  }

  /// The governorate a store is in, as its owner last saved it. It read the
  /// demo's first record, so a store that moved still charged the cart its
  /// old city's fee while the product page showed the new one.
  String? _storeCityOf(String merchantId) {
    if (_savedStores[merchantId]?['governorate'] case final String saved) {
      return saved;
    }
    for (final merchant in MockData.merchants) {
      if (merchant['id'] == merchantId) return '${merchant['governorate']}';
    }
    return _ownStore?['governorate'] as String?;
  }

  /// What [merchantId] asks to bring an order to [city]: its fee and time,
  /// or null when it does not go there. No city yet means its own.
  ({num fee, String time})? _deliveryTerms(String merchantId, String? city) {
    final delivery = _deliveryOf(merchantId);
    final home = _storeCityOf(merchantId);
    final to = city ?? home;
    if (!(delivery['governorates'] as List).contains(to)) return null;
    if (to == home) {
      return (
        fee: delivery['feeInside'] as num,
        time: '${delivery['timeInside']}',
      );
    }
    final fee = delivery['feeOutside'] as num?;
    final time = delivery['timeOutside'];
    return fee == null || time == null ? null : (fee: fee, time: '$time');
  }

  /// The governorate an order goes to: the chosen address's, else the
  /// default address's, as checkout picks it.
  String? _deliveryCity(Object? addressId) {
    Map<String, dynamic>? chosen;
    for (final address in _addresses) {
      if (address['id'] == addressId) chosen = address;
    }
    chosen ??=
        _addresses.where((a) => a['isDefault'] == true).firstOrNull ??
        _addresses.firstOrNull;
    return chosen?['governorate'] as String?;
  }

  /// "Atlas Home: Doesn't deliver to Erbil", for each store in [cart] that
  /// cannot bring its part to the address.
  List<String> _undeliverable(Map<String, dynamic> cart) => [
    for (final group in cart['groups'] as List)
      if ((group as Map)['deliversHere'] != true)
        '${(group['merchant'] as Map)['storeName']}: '
            '${group['estimatedDelivery']}',
  ];

  String _noDeliveryText(String? city) {
    final name =
        Governorate.fromApi(city)?.nameIn(_arabic ? 'ar' : 'en') ?? '$city';
    return _arabic ? 'لا يوصّل إلى $name' : "Doesn't deliver to $name";
  }

  /// The delivery times a store picks from, in both languages, slowest last.
  static const Map<String, (String, String)> _deliveryTimes = {
    'SAME_DAY': ('Same day', 'في نفس اليوم'),
    '1_2_DAYS': ('1–2 days', '1–2 يوم'),
    '2_3_DAYS': ('2–3 days', '2–3 أيام'),
    '3_5_DAYS': ('3–5 days', '3–5 أيام'),
    '5_7_DAYS': ('5–7 days', '5–7 أيام'),
  };

  String _timeText(Object? code) {
    final words = _deliveryTimes[code];
    if (words == null) return '';
    return _arabic ? words.$2 : words.$1;
  }

  /// Why a store's delivery settings cannot be saved, or null.
  _Reply? _deliveryProblem(Map<dynamic, dynamic> delivery, Object? home) {
    _Reply fail(String field, String en, String ar) {
      final message = _arabic ? ar : en;
      return _Reply(<String, dynamic>{
        'message': message,
        'errors': <String, dynamic>{field: message},
      }, statusCode: 422);
    }

    for (final field in const ['feeInside', 'feeOutside']) {
      final fee = delivery[field];
      if (fee != null && (fee is! num || fee < 0 || fee % 250 != 0)) {
        return fail(field, _stepsEn, _stepsAr);
      }
    }
    if (delivery['feeInside'] == null ||
        !_deliveryTimes.containsKey(delivery['timeInside'])) {
      return fail(
        'feeInside',
        'Enter the fee and time in your city.',
        'أدخل الأجرة والمدة داخل مدينتك.',
      );
    }
    final goesOut = ((delivery['governorates'] as List?) ?? const []).any(
      (city) => city != home,
    );
    if (goesOut &&
        (delivery['feeOutside'] == null ||
            !_deliveryTimes.containsKey(delivery['timeOutside']))) {
      return fail(
        'feeOutside',
        'Enter the fee and time for other cities.',
        'أدخل الأجرة والمدة للمدن الأخرى.',
      );
    }
    return null;
  }

  /// The lines a Buy now checkout is for, or null for the cart.
  static List<Map<String, dynamic>>? _buyNowLines(Map<String, dynamic> body) {
    final items = body['items'];
    if (items is! List || items.isEmpty) return null;
    return <Map<String, dynamic>>[
      for (final item in items.whereType<Map>())
        <String, dynamic>{
          'productId': item['productId'],
          'variantId': ?item['variantId'],
          'quantity': item['quantity'] ?? 1,
        },
    ];
  }

  Map<String, dynamic> _createOrder(
    Map<String, dynamic> selection, {
    List<Map<String, dynamic>>? only,
  }) {
    final cart = _buildCart(only: only, addressId: selection['addressId']);
    final totals = cart['totals'] as Map<String, dynamic>;
    final id = _nextId('order');

    final items = <Map<String, dynamic>>[];
    for (final group in cart['groups'] as List<dynamic>) {
      // The store's coupon, shared over its lines by price: what each unit
      // really cost, and so what a return of it gives back.
      final subtotal = ((group as Map)['subtotal'] as num?) ?? 0;
      final discount = (group['discount'] as num?) ?? 0;
      for (final item in group['items'] as List<dynamic>) {
        final line = item as Map<String, dynamic>;
        final unit = line['unitPrice'] as num;
        items.add(<String, dynamic>{
          'id': _nextId('oi'),
          'productId': line['productId'],
          // Which option, when it has options. Without it a purchase came off
          // the product's own count - a number nothing reads once a product
          // has options - so "Silver 128GB: 3" sold three and still said 3,
          // and a store with 3 on the shelf could take orders for ever.
          'variantId': line['variantId'],
          // Snapshot fields: the order keeps these even if the product changes
          // later (specification section 16).
          'productName': line['name'],
          'productNameAr': ?line['nameAr'],
          'sku': 'SKU-${line['productId']}',
          'variantLabel': line['variantLabel'],
          'imageUrl': line['imageUrl'],
          'merchantId': line['merchantId'],
          'merchantName': line['merchantName'],
          'unitPrice': line['unitPrice'],
          // In cash steps, as every amount here: 130,565 cannot be handed
          // back, there is no note under 250 (the tester). Down, so a store
          // never gives back more than it took.
          'paidUnitPrice': _cashSteps(
            subtotal <= 0 ? unit : unit - unit * discount / subtotal,
          ),
          'quantity': line['quantity'],
          'lineTotal': line['lineTotal'],
          'currencyCode': MockData.currency,
          // Waiting for its store: only the store confirms an order, by
          // saying so on its own screen. This said CONFIRMED the moment
          // the shopper paid, while the store still had it as new.
          'status': 'PENDING',
          // Both open when the store delivers: a review of something not
          // received, or a return of it, means nothing.
          'canReturn': false,
        });
      }
    }

    final addressId = selection['addressId']?.toString();
    final address = _addresses.firstWhere(
      (a) => a['id'] == addressId,
      orElse: () => _addresses.isEmpty
          ? <String, dynamic>{'fullName': 'Demo', 'area': 'Demo area'}
          : _addresses.first,
    );

    final now = DateTime.now();

    final order = <String, dynamic>{
      'id': id,
      'orderNumber': 'SB-${100000 + _counter}',
      // The account that placed it, for the admin web (API_CONTRACT.md 5,
      // BUGS 106); it found the shopper by phone.
      'customerId': _currentUser()['id'],
      'placedAt': now.toIso8601String(),
      'status': 'PENDING',
      'paymentStatus': 'PENDING',
      'items': items,
      'itemCount': items.fold<int>(
        0,
        (total, item) => total + (item['quantity'] as int),
      ),
      'subtotal': totals['subtotal'],
      'discount': totals['couponDiscount'],
      'shipping': totals['shipping'],
      'total': totals['total'],
      // What each store's driver collects: the shopper pays each one.
      'storeParts': [
        for (final group in cart['groups'] as List<dynamic>)
          <String, dynamic>{
            'merchantId': ((group as Map)['merchant'] as Map)['id'],
            'amountDue': group['amountDue'],
            // When this store's parcel should come, for its box on the
            // order: each store has its own time.
            'deliveryTime': ?group['deliveryTime'],
          },
      ],
      'currencyCode': MockData.currency,
      'previewImageUrl': items.isEmpty ? null : items.first['imageUrl'],
      'merchantNames': items
          .map((item) => item['merchantName'].toString())
          .toSet()
          .toList(),
      // Copied as it is now: editing the address later must not move a
      // parcel already on its way.
      'shippingAddress': <String, dynamic>{
        for (final field in const [
          'fullName',
          'phone',
          'governorate',
          'area',
          'street',
          'landmark',
          'instructions',
        ])
          field: address[field],
      },
      'paymentMethodLabel': _arabic ? 'الدفع عند الاستلام' : 'Cash on delivery',
      'paymentMethodType': 'COD',
      // The slowest store's time: when the whole order will have come.
      'estimatedDelivery': _timeText(
        _deliveryTimes.keys.lastWhere(
          (time) => (cart['groups'] as List).any(
            (group) => (group as Map)['deliveryTime'] == time,
          ),
          orElse: () => '',
        ),
      ),
      'canCancel': true,
      'canReturn': false,
      // One entry, as a code the app puts in the reader's language: a
      // sentence stayed in the language the order was placed in. There was
      // a second, "Payment recorded", written the moment the order was
      // placed - on a cash order nobody had paid yet - and it made the
      // store's own "Confirmed" step appear twice.
      'timeline': [
        <String, dynamic>{
          'status': 'PENDING',
          'occurredAt': now.toIso8601String(),
          'noteCode': 'ORDER_RECEIVED',
        },
      ],
    };

    _orders.insert(0, order);
    _placedOrders[id] = order;

    // Each store gets its own part, as one checkout splits on a real
    // marketplace: its lines, its delivery, the customer's name and address,
    // and nothing from the other store.
    final customer = '${address['fullName'] ?? ''}';
    for (final group in cart['groups'] as List<dynamic>) {
      final store = '${((group as Map)['merchant'] as Map)['id']}';
      final lines = <Map<String, dynamic>>[
        for (final item in items)
          if (item['merchantId'] == store) item,
      ];
      if (lines.isEmpty) continue;
      final count = lines.fold<int>(
        0,
        (total, line) => total + (line['quantity'] as int),
      );
      final partId = _nextId('so');
      _ordersOf(store).insert(0, <String, dynamic>{
        'id': partId,
        'merchantId': store,
        'customerOrderId': id,
        'customerEmail': _email,
        'customerId': order['customerId'],
        'orderNumber': order['orderNumber'],
        'placedAt': now.toIso8601String(),
        // PENDING, as the real server says it (BACKEND_PLAN.md 8.4).
        'status': 'PENDING',
        'subtotal': group['subtotal'],
        'discount': group['discount'],
        'shipping': group['shippingFee'],
        // What the driver collects at the door.
        'total': group['amountDue'],
        'currencyCode': MockData.currency,
        'itemCount': count,
        'customerName': customer,
        'customerArea': address['area'],
        'customerGovernorate': address['governorate'],
        'deliveryTime': group['deliveryTime'],
        'customerPhone': address['phone'],
        'shippingAddress': order['shippingAddress'],
        'paymentMethodLabel': order['paymentMethodLabel'],
        'previewImageUrl': lines.first['imageUrl'],
        'items': <Map<String, dynamic>>[
          for (final line in lines)
            <String, dynamic>{
              'id': line['id'],
              'productId': line['productId'],
              // So a part turned down puts the stock back on the option it
              // came from, not on the product's unread count.
              'variantId': line['variantId'],
              'name': line['productName'],
              'imageUrl': line['imageUrl'],
              'sku': line['sku'],
              'variantLabel': line['variantLabel'],
              'quantity': line['quantity'],
              'price': line['unitPrice'],
            },
        ],
      });
      _notify(
        'store:$store',
        'ORDER',
        en: (
          'New order ${order['orderNumber']}',
          '$customer ordered $count ${count == 1 ? 'item' : 'items'}. '
              'Confirm it to start.',
        ),
        ar: (
          'طلب جديد ${order['orderNumber']}',
          'طلب من $customer، عدد المنتجات: $count. أكّده لتبدأ.',
        ),
        target: ('STORE_ORDER', partId),
      );
    }

    // What was bought is no longer on the shelf, for the store and for the
    // next shopper alike.
    for (final item in items) {
      final key = _stockKey(item['productId'], item['variantId']);
      final left = _stockOf(key, _seededFor(key)) - (item['quantity'] as int);
      _stockOverrides[key] = math.max(0, left);
    }
    return order;
  }

  // ----------------------------------------------------------------- orders ---

  _Reply _ordersRoutes(
    String method,
    List<String> path,
    RequestOptions options,
  ) {
    _orders.forEach(_applyReturnWindow);
    if (path.length == 1) {
      final status = options.queryParameters['status']?.toString();
      var results = _orders;
      if (status != null && status.isNotEmpty) {
        results = _orders.where((o) => o['status'] == status).toList();
      }
      return _page(results, options);
    }

    // GET /orders/rating-due - the delivered order this shopper has not
    // rated yet, if there is one. One sheet, one order, every store in it.
    if (path[1] == 'rating-due') return _Reply(_ratingDue());

    final id = path[1];
    final sub = path.length > 2 ? path[2] : '';

    // POST /orders/:id/rating - the stars the shopper gave each store, and
    // one comment for the order. Rating it also answers "did it arrive".
    if (sub == 'rating') {
      return _takeRating(id, _body(options));
    }

    // POST /orders/:id/rating-skipped - not now. Asked twice more, then
    // never again for this order.
    if (sub == 'rating-skipped') {
      _ratingSkips[id] = (_ratingSkips[id] ?? 0) + 1;
      return const _Reply(<String, dynamic>{});
    }

    // POST /orders/:id/received - "did you receive it?", per store. A no
    // goes to the store, who calls the shopper about it.
    if (sub == 'received') {
      final body = _body(options);
      final order = _orders.firstWhere(
        (o) => o['id'] == id,
        orElse: () => <String, dynamic>{},
      );
      if (order.isEmpty) {
        return const _Reply(<String, dynamic>{}, statusCode: 404);
      }
      final store = '${body['merchantId']}';
      final received = body['received'] == true;
      for (final entry in (order['storeParts'] as List? ?? const [])) {
        if ((entry as Map)['merchantId'] == store) entry['received'] = received;
      }
      if (!received) _notReceived(order, store);
      return _Reply(order);
    }

    if (sub == 'cancel') {
      final body = _body(options);
      // A reason is required, and it is one of the list: a cancel with none
      // went through, and the store was told nothing about why.
      const reasons = {
        'CHANGED_MIND',
        'FOUND_CHEAPER',
        'DELIVERY_TOO_SLOW',
        'ORDERED_BY_MISTAKE',
        'OTHER',
      };
      if (!reasons.contains(body['reason'])) {
        final message = _arabic
            ? 'اختر سبب الإلغاء'
            : 'Choose why you are cancelling';
        return _Reply(<String, dynamic>{
          'message': message,
          'errors': <String, dynamic>{'reason': message},
        }, statusCode: 422);
      }
      for (final order in _orders) {
        if (order['id'] == id) {
          order['status'] = 'CANCELLED';
          order['paymentStatus'] = 'CANCELLED';
          order['canCancel'] = false;
          order['canReturn'] = false;
          // Keep what the customer chose, so the timeline can show it back.
          order['cancelReason'] = body['reason'];
          order['cancelNote'] = body['note'];
          // The reason as its code, and whatever the shopper typed as typed.
          (order['timeline'] as List).add(<String, dynamic>{
            'status': 'CANCELLED',
            'occurredAt': DateTime.now().toIso8601String(),
            'reasonCode': ?body['reason'],
            'note': ?body['note'],
          });
          // Each store's part stops where it is, and the store is told.
          for (final part in _partsOf(id)) {
            if (_stage(part['status']) > 1) continue;
            if (!_isOff(part['status'])) _restock(part);
            part['status'] = 'CANCELLED';
            part['cancellationReason'] = 'CUSTOMER_CANCELLED';
            for (final item in order['items'] as List) {
              (item as Map)['status'] = 'CANCELLED';
            }
            _notify(
              'store:${part['merchantId']}',
              'ORDER',
              en: (
                'Order ${order['orderNumber']} was cancelled',
                '${part['customerName']} cancelled it before it shipped.',
              ),
              ar: (
                'أُلغي الطلب ${order['orderNumber']}',
                'ألغاه ${part['customerName']} قبل شحنه.',
              ),
              target: ('STORE_ORDER', '${part['id']}'),
            );
          }
          return _Reply(order);
        }
      }
    }

    // An order that is not this shopper's is not found. It answered an
    // empty order, and the invoice drew blank, dated 1970 (the tester).
    final missing = _Reply(<String, dynamic>{
      'message': _arabic ? 'لم نجد هذا الطلب.' : 'This order was not found.',
    }, statusCode: 404);
    if (sub == 'invoice') {
      for (final order in _orders) {
        if (order['id'] == id) return _Reply(_invoiceFor(order));
      }
      return missing;
    }

    for (final order in _orders) {
      if (order['id'] == id) return _Reply(order);
    }
    return missing;
  }

  /// Builds an invoice from an order's own figures.
  ///
  /// Nothing is recomputed: the invoice has to keep saying what was actually
  /// charged, which is the point of specification section 16.
  Map<String, dynamic> _invoiceFor(Map<String, dynamic> order) {
    final items = (order['items'] as List).cast<Map<String, dynamic>>();
    final merchants = (order['merchantNames'] as List?) ?? const <dynamic>[];

    return <String, dynamic>{
      'orderId': order['id'],
      'orderNumber': order['orderNumber'],
      'invoiceNumber': 'INV-${order['orderNumber']}',
      'issuedAt': order['placedAt'],
      // An order line stores `productName`, `unitPrice` and `lineTotal`.
      // This read `name` and `price`, so every field came back null and the
      // cast on the last one threw — which the client could only report as a
      // failed request. The invoice screen had never once drawn in demo mode.
      // The line total is taken, not recomputed, for the same reason the
      // screen recomputes nothing.
      'lines': [
        for (final item in items)
          <String, dynamic>{
            'description': item['productName'],
            'descriptionAr': ?item['productNameAr'],
            'merchantName': item['merchantName'],
            'quantity': item['quantity'],
            'unitPrice': item['unitPrice'],
            'total': item['lineTotal'],
          },
      ],
      'subtotal': order['subtotal'],
      'discount': order['discount'],
      'shipping': order['shipping'],
      'tax': order['tax'],
      'total': order['total'],
      'currencyCode': order['currencyCode'],
      'paymentMethodLabel': order['paymentMethodLabel'],
      'paymentStatus': order['paymentStatus'],
      'billedTo': order['shippingAddress'],
      // One seller only when there is one: a two-store invoice said "Sold
      // by Nova Electronics" over Atlas's air fryer too. Each line names
      // its own store.
      'sellerName': merchants.length == 1 ? merchants.first : null,
    };
  }

  // ---------------------------------------------------------------- returns ---

  _Reply _returnsRoutes(
    String method,
    List<String> path,
    RequestOptions options,
  ) {
    if (method == 'POST' && path.length == 1) {
      return _createReturn(_body(options));
    }

    if (path.length == 1) {
      final status = options.queryParameters['status']?.toString();
      var results = _returns;
      if (status != null && status.isNotEmpty) {
        results = _returns.where((r) => r['status'] == status).toList();
      }
      return _page(results, options);
    }

    final id = path[1];
    for (final request in _returns) {
      if (request['id'] == id) return _Reply(request);
    }
    return const _Reply(<String, dynamic>{});
  }

  /// Turns a return request into a record the list and detail can show, with a
  /// pending refund attached so the refund section is not permanently empty.
  _Reply _createReturn(Map<String, dynamic> body) {
    final id = _nextId('ret');
    final orderId = (body['orderId'] ?? '').toString();
    final order = _orders.firstWhere(
      (o) => o['id'] == orderId,
      orElse: () => <String, dynamic>{},
    );
    if (order.isNotEmpty) _applyReturnWindow(order);

    final requestedLines =
        (body['items'] as List?)?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];
    final orderItems =
        (order['items'] as List?)?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];
    _Reply refuse(String en, String ar) => _Reply(<String, dynamic>{
      'message': _arabic ? ar : en,
    }, statusCode: 422);

    final items = <Map<String, dynamic>>[];
    final stores = <String>{};
    num refundTotal = 0;
    for (final line in requestedLines) {
      final match = orderItems.firstWhere(
        (i) => i['id'] == line['orderItemId'],
        orElse: () => <String, dynamic>{},
      );
      // Once: one pair of headphones went back three times and was paid
      // for twice (the tester). _applyReturnWindow closes an item that has
      // a return already.
      if (_returnedItems.contains(match['id'])) {
        return refuse(
          'This item already has a return.',
          'لهذا المنتج طلب إرجاع من قبل.',
        );
      }
      if (match['canReturn'] != true) {
        return refuse(
          'You can return it within 7 days of delivery.',
          'يمكنك الإرجاع خلال 7 أيام من الاستلام.',
        );
      }
      stores.add('${match['merchantId']}');
      final quantity = (line['quantity'] as num?)?.toInt() ?? 1;
      final bought = (match['quantity'] as num?)?.toInt() ?? 1;
      if (quantity < 1 || quantity > bought) {
        return refuse(
          'You can return at most the number you bought.',
          'يمكنك إرجاع ما اشتريته فقط، لا أكثر.',
        );
      }
      // What it cost after the store's coupon, not its shelf price: a
      // refund of 145,000 for headphones bought at 130,500 with NOVA10
      // handed back more cash than was taken.
      final price =
          (match['paidUnitPrice'] as num?) ?? (match['unitPrice'] as num?) ?? 0;
      refundTotal += price * quantity;
      items.add(<String, dynamic>{
        'orderItemId': line['orderItemId'],
        'productId': match['productId'],
        'name': match['productName'] ?? 'Item',
        'quantity': quantity,
        'imageUrl': match['imageUrl'],
        'variantLabel': match['variantLabel'],
        'refundAmount': price * quantity,
      });
    }

    if (items.isEmpty) {
      return refuse('Choose what to return.', 'اختر ما تريد إرجاعه.');
    }
    // Each store picks up its own things, so one store at a time.
    if (stores.length > 1) {
      return refuse(
        "Return one store's items at a time.",
        'أرجع منتجات متجر واحد في كل مرة.',
      );
    }
    final store = stores.single;

    final now = DateTime.now();
    final currency = order['currencyCode'] ?? MockData.currency;
    final request = <String, dynamic>{
      'id': id,
      'orderId': orderId,
      'orderNumber': order['orderNumber'] ?? '-',
      'status': 'REQUESTED',
      'requestedAt': now.toIso8601String(),
      'reason': body['reason'] ?? 'OTHER',
      'description': body['description'],
      'merchantId': store,
      'merchantName': _storeFace(store)['title'],
      'customerEmail': _email,
      'customerName': (order['shippingAddress'] as Map?)?['fullName'],
      'items': items,
      'itemCount': items.fold<int>(
        0,
        (total, item) => total + (item['quantity'] as num).toInt(),
      ),
      'currencyCode': currency,
      'refundAmount': refundTotal,
      'previewImageUrl': items.isEmpty ? null : items.first['imageUrl'],
      'refund': <String, dynamic>{
        'amount': refundTotal,
        'currencyCode': currency,
        'status': 'PENDING',
        // Paid in cash at the door, so given back in cash, by the store,
        // when it collects the item.
        'method': _arabic ? 'نقداً، يعيده لك المتجر' : 'Cash, from the store',
        'expectedAt': now.add(const Duration(days: 3)).toIso8601String(),
      },
      'timeline': <Map<String, dynamic>>[
        <String, dynamic>{
          'status': 'REQUESTED',
          'occurredAt': now.toIso8601String(),
          'noteCode': 'RETURN_REQUESTED',
        },
      ],
      'photos': body['photos'] ?? <String>[],
    };

    _returns.insert(0, request);
    // The same record, for the store: its answer reaches the shopper's.
    _storeReturns.putIfAbsent(store, () => []).insert(0, request);
    // Its lines are no longer returnable: the order says so at once.
    _applyReturnWindow(order);
    final number = request['orderNumber'];
    final who = request['customerName'] ?? '';
    _notify(
      'store:$store',
      'ORDER',
      en: (
        'Return request, order $number',
        '$who wants to return ${items.length} item(s). Approve it to pick '
            'it up.',
      ),
      ar: (
        'طلب إرجاع، الطلب $number',
        'يريد $who إرجاع منتجات: ${items.length}. وافق لتستلمها.',
      ),
      target: ('STORE_ORDER', _partIdOf(orderId, store)),
    );
    return _Reply(request);
  }

  /// Every order line that has a return, answered or not.
  Set<Object?> get _returnedItems => {
    for (final request in [
      ..._returns,
      for (final list in _storeReturns.values) ...list,
    ])
      for (final item in request['items'] as List) (item as Map)['orderItemId'],
  };

  /// Every store's return requests, the same records the shoppers hold.
  final Map<String, List<Map<String, dynamic>>> _storeReturns =
      <String, List<Map<String, dynamic>>>{};

  /// A store answers a return: approve and collect it, decline it, or say
  /// the item is back and the cash handed over.
  _Reply _storeAnswersReturn(String id, Map<String, dynamic> body) {
    final request = (_storeReturns[_shelfStore] ?? const [])
        .where((r) => r['id'] == id)
        .firstOrNull;
    if (request == null) {
      return const _Reply(<String, dynamic>{}, statusCode: 404);
    }
    final next = '${body['status']}';
    final allowed = switch (request['status']) {
      'REQUESTED' => const {'APPROVED', 'REJECTED'},
      'APPROVED' => const {'REFUNDED'},
      _ => const <String>{},
    };
    if (!allowed.contains(next)) {
      return _Reply(<String, dynamic>{
        'message': _arabic
            ? 'لا يمكن نقل هذا الطلب إلى هذه الحالة.'
            : 'This return cannot go to that step.',
      }, statusCode: 422);
    }
    // A decline says why, and the shopper is told it.
    final reason = '${body['reason'] ?? ''}'.trim();
    if (next == 'REJECTED' && reason.isEmpty) return _noReason();
    final now = DateTime.now().toIso8601String();
    request['status'] = next;
    if (next == 'REJECTED') request['rejectionReason'] = reason;
    (request['timeline'] as List).add(<String, dynamic>{
      'status': next,
      'occurredAt': now,
    });
    if (next == 'REFUNDED') {
      (request['refund'] as Map)['status'] = 'COMPLETED';
      (request['refund'] as Map)['completedAt'] = now;
      // The item is back on the shelf.
      _restock(<String, dynamic>{'items': request['items']});
    }
    final name = request['merchantName'];
    final number = request['orderNumber'];
    final (String, String) en = switch (next) {
      'APPROVED' => (
        '$name will pick up your return',
        'Order $number. They will call you to arrange it.',
      ),
      'REJECTED' => (
        '$name declined your return',
        'Order $number. Message them to ask why.',
      ),
      _ => ('$name gave your cash back', 'Order $number. Your return is done.'),
    };
    final (String, String) ar = switch (next) {
      'APPROVED' => (
        'سيستلم $name المرتجع',
        'الطلب $number. سيتصل بك لترتيب ذلك.',
      ),
      'REJECTED' => ('رفض $name الإرجاع', 'الطلب $number. راسله لتعرف السبب.'),
      _ => ('أعاد $name مبلغك نقداً', 'الطلب $number. تم الإرجاع.'),
    };
    _notify(
      '${request['customerEmail'] ?? _email}',
      'ORDER',
      en: en,
      ar: ar,
      target: ('RETURN', '${request['id']}'),
    );
    return _Reply(request);
  }

  // ---------------------------------------------------------------- reviews ---

  /// [store] with the rating it has now: what it opened the demo with, and
  /// every rating a shopper has given it since. One helper, used wherever a
  /// store leaves this server, so the storefront, the rail on Home, a
  /// product's seller card and the store's own dashboard never disagree.
  Map<String, dynamic> _withRating(Map<String, dynamic> store) {
    final given = _givenRatings['${store['id']}'];
    if (given == null) return store;
    final seededCount = (store['reviewCount'] as num?)?.toInt() ?? 0;
    final seededTotal = ((store['rating'] as num?) ?? 0) * seededCount;
    final count = seededCount + given.$2;
    return <String, dynamic>{
      ...store,
      'rating': count == 0 ? 0 : (seededTotal + given.$1) / count,
      'reviewCount': count,
    };
  }

  /// What shoppers have said about one store, newest first.
  List<Map<String, dynamic>> _reviewsFor(String key) {
    return <Map<String, dynamic>>[
      ..._reviews.putIfAbsent(key, () => _seedReviews(key)),
    ]..sort(
      (a, b) => b['createdAt'].toString().compareTo(a['createdAt'].toString()),
    );
  }

  List<Map<String, dynamic>> _seedReviews(String key) {
    const authors = <String>[
      'Amina Saleh',
      'Omar Haddad',
      'Lina Nasser',
      'Yousef Khalil',
      'Rana Odeh',
      'Tariq Mansour',
    ];
    const bodies = <String>[
      'Exactly as described. Shipping was quick.',
      'Good value, but the box arrived a little dented.',
      'Works well so far. Battery life is better than I expected.',
      'Decent, though the colour is darker than the photos.',
      'Would buy again. The seller answered my question quickly.',
      'Not what I hoped for at this price.',
    ];
    final now = DateTime.now();

    return <Map<String, dynamic>>[
      for (var i = 0; i < authors.length; i++)
        <String, dynamic>{
          'id': '$key-rev-$i',
          'rating': 5 - (i % 5),
          'title': i.isEven ? 'Happy with it' : null,
          'body': bodies[i],
          'authorName': authors[i],
          'createdAt': now
              .subtract(Duration(days: i * 6 + 1))
              .toIso8601String(),
          'isVerifiedPurchase': i % 3 != 2,
          'photos': i == 0
              ? <String>[
                  'https://picsum.photos/seed/$key-rev-a/300/300',
                  'https://picsum.photos/seed/$key-rev-b/300/300',
                ]
              : <String>[],
          if (i == 1)
            'merchantResponse': <String, dynamic>{
              'body':
                  'Sorry about the packaging. We have raised it with our '
                  'courier.',
              'merchantName': 'Nova Electronics',
              'respondedAt': now
                  .subtract(Duration(days: i * 6))
                  .toIso8601String(),
            },
        },
    ];
  }

  // -------------------------------------------------------------- merchants ---

  _Reply _merchants(String method, List<String> path, RequestOptions options) {
    final id = path.length > 1 ? path[1] : '';

    if (id != 'me') {
      final sub = path.length > 2 ? path[2] : '';

      if (sub == 'products') {
        final items = MockData.productSummaries
            .where(
              (p) => (p['merchant'] as Map)['id'] == id && _isListedId(p['id']),
            )
            .map(_withStock)
            .toList();
        return _page(items, options);
      }

      if (sub == 'coupons') {
        // What a shopper can use at this store today.
        return _Reply(<Map<String, dynamic>>[
          for (final coupon in _couponsOf(id))
            if (_isLive(coupon)) _asOffer(coupon),
        ]);
      }

      if (sub == 'reviews') {
        // A store opened this session has sold nothing, so no one has
        // reviewed it.
        if (_isNewStore && id == _ownStore?['id']) {
          return _page(const <Map<String, dynamic>>[], options);
        }
        return _page(_reviewsFor('store-$id'), options);
      }

      // /merchants/:id/store - what a shopper sees, including the city and
      // country the merchant gave, as they last saved them.
      final own = _ownStore;
      final merchant = own != null && own['id'] == id
          ? own
          : MockData.merchants.firstWhere(
              (m) => m['id'] == id,
              orElse: () => MockData.merchants.first,
            );
      return _Reply(<String, dynamic>{
        ..._withRating(merchant),
        'delivery': _deliveryOf(id),
        'isOpen': !_closedStores.contains(id),
      });
    }

    // ---- /merchants/me/... : the signed-in merchant's own store ----
    final sub = path.length > 2 ? path[2] : '';

    switch (sub) {
      case 'returns' when path.length > 3 && method == 'PATCH':
        return _storeAnswersReturn(path[3], _body(options));
      case 'dashboard':
        return _Reply(_merchantDashboard());

      case 'deletion':
        return _storeDeletion(method);

      case 'store' when path.length > 3 && path[3] == 'open':
        if (_body(options)['isOpen'] != false &&
            _storeDeletions.containsKey(_shelfStore)) {
          return _Reply(<String, dynamic>{
            'message': _arabic
                ? 'يجري حذف حساب متجرك. ألغِ الحذف لتفتحه من جديد.'
                : "Your store's account is being deleted. Cancel the "
                      'deletion to open it again.',
          }, statusCode: 409);
        }
        if (_body(options)['isOpen'] == false) {
          _closedStores.add(_shelfStore);
        } else {
          _closedStores.remove(_shelfStore);
        }
        return _Reply(<String, dynamic>{
          'isOpen': !_closedStores.contains(_shelfStore),
          ..._stillOpen(),
        });

      case 'products':
        return _merchantProductRoutes(method, path, options);

      case 'brands':
        // Saba's checked brands, and those this store's own products use,
        // checked or not (the admin's brands page).
        final own = <Object?>{
          for (final product in [..._storeProducts, ...MockData.products])
            if ((product['merchantId'] ??
                    (product['merchant'] as Map?)?['id']) ==
                _shelfStore)
              (product['brand'] as Map?)?['id'],
        };
        Map<String, dynamic> row(Map<String, dynamic> brand) =>
            <String, dynamic>{
              'id': brand['id'],
              'name': brand['name'],
              'nameAr': brand['nameAr'],
            };
        return _Reply(<Map<String, dynamic>>[
          for (final brand in MockData.brands) row(brand),
          for (final brand in _addedBrands)
            if (own.contains(brand['id'])) row(brand),
        ]);

      case 'inventory':
        return _merchantInventoryRoutes(method, path, options);

      case 'orders':
        return _merchantOrderRoutes(method, path, options);

      case 'analytics':
        return _Reply(
          _merchantAnalytics(
            options.queryParameters['period']?.toString() ?? 'month',
          ),
        );

      case 'bills':
        return _Reply(_sabaBills());

      case 'coupons':
        return _merchantCouponRoutes(method, path, options);

      case 'promotions':
        return const _Reply(<Map<String, dynamic>>[]);

      case 'store':
      default:
        if (sub == 'store' && (method == 'PUT' || method == 'PATCH')) {
          final body = _body(options);
          if (_nameTooLong(body) case final tooLong?) return tooLong;
          final name = (body['storeName'] ?? '').toString().trim();
          if (name.isEmpty) {
            final message = _arabic
                ? 'المتجر يحتاج إلى اسم'
                : 'A store needs a name';
            return _Reply(<String, dynamic>{
              'message': message,
              'errors': <String, dynamic>{'storeName': message},
            }, statusCode: 422);
          }
          final home = body['governorate'] ?? _ownStoreRecord()['governorate'];
          final taken = _storeNameTaken(
            name,
            home,
            except: _ownStoreRecord()['id'],
          );
          if (taken != null) return taken;
          final delivery = body['delivery'];
          if (delivery is Map) {
            if (_deliveryProblem(delivery, home) case final problem?) {
              return problem;
            }
            _storeDelivery[_shelfStore] = <String, dynamic>{
              ...delivery.cast<String, dynamic>(),
              // It always delivers where it is.
              'governorates': <Object?>{
                home,
                ...(delivery['governorates'] as List? ?? const []),
              }.toList(),
            };
          }
          // Editing the store they have: same store, same standing. What
          // they wrote replaces the words in both languages: the Arabic kept
          // beside an edited field would still answer in Arabic.
          _ownStore = <String, dynamic>{
            for (final entry in _ownStoreRecord().entries)
              if (!(entry.key.endsWith('Ar') &&
                  body.containsKey(
                    entry.key.substring(0, entry.key.length - 2),
                  )))
                entry.key: entry.value,
            for (final entry in body.entries)
              if (entry.value != null && entry.key != 'delivery')
                entry.key: entry.value,
            // Sent empty: the owner took the logo away.
            if (body.containsKey('logoUrl') && body['logoUrl'] == null)
              'logoUrl': null,
          };
          return _Reply(_ownStoreRecord());
        }
        final store = _ownStoreRecord();
        return _Reply(<String, dynamic>{
          'storeName': store['storeName'],
          'description': store['description'],
          'businessType': store['businessType'],
          'businessAddress': store['businessAddress'],
          'country': store['country'],
          'governorate': store['governorate'],
          'logoUrl': store['logoUrl'],
          'shippingPolicy': store['shippingPolicy'],
          'returnPolicy': store['returnPolicy'],
          'delivery': _deliveryOf(_shelfStore),
        });
    }
  }

  Map<String, dynamic> _merchantDashboard() {
    final own = _merchantProducts(null);

    // Counted from the same lists the screens read, not typed in here. The
    // dashboard said "7 orders to confirm" and the queue behind it held two:
    // a to-do list that disagrees with the work is worse than none, because
    // the merchant stops believing the number and checks manually every time.
    final orders = _merchantOrderStore;
    final pending = orders.where((o) => o['status'] == 'PENDING').length;
    final returns = orders.where((o) => o['status'] == 'RETURNED').length;
    final outOfStock = own.where((p) => (p['stock'] as int) <= 0).length;
    // Sent back by Saba: not on sale until the store changes them.
    final rejected = own.where((p) => p['status'] == 'REJECTED').length;
    final lowStock = own
        .where(
          (p) =>
              (p['stock'] as int) > 0 &&
              (p['stock'] as int) <= (p['lowStockThreshold'] as int),
        )
        .length;

    // Nothing sold, so no revenue, no history to compare with and no rating
    // - absent rather than zero where the screen tells the two apart.
    if (_isNewStore) {
      return <String, dynamic>{
        'currencyCode': MockData.currency,
        'revenue': 0,
        'orderCount': 0,
        'productCount': own.length,
        'pendingOrders': pending,
        'lowStockCount': lowStock,
        'outOfStockCount': outOfStock,
        'rejectedCount': rejected,
        'returnCount': returns,
        'isOpen': !_closedStores.contains(_shelfStore),
        'salesSeries': const <Map<String, dynamic>>[],
        'topProducts': const <Map<String, dynamic>>[],
      };
    }

    // This month, as Analytics' month tab counts it: the same calculation,
    // so the two screens cannot disagree. They did - 10 orders and -12%
    // here, 3 orders and +40% there, for the same revenue.
    final now = DateTime.now();
    final (from: _, :sold, :before) = _periodSales('month');
    final waiting = [
      for (final o in orders)
        if (o['status'] == 'PENDING') DateTime.tryParse('${o['placedAt']}'),
    ].nonNulls;
    final store = MockData.merchants
        .where((m) => m['id'] == _shelfStore)
        .firstOrNull;

    return <String, dynamic>{
      'currencyCode': MockData.currency,
      'revenue': sold.goods,
      'orderCount': sold.parts.length,
      'productCount': own.length,
      'pendingOrders': pending,
      'lowStockCount': lowStock,
      'outOfStockCount': outOfStock,
      'rejectedCount': rejected,
      'returnCount': returns,
      'refundTotal': sold.returned,
      'isOpen': !_closedStores.contains(_shelfStore),
      // Only what last month has to compare with: no deliveries then means
      // no "up 12%" drawn against nothing.
      if (before.parts.isNotEmpty) ...{
        'previousRevenue': before.goods,
        'comparisonDays': now.day,
      },
      if (before.parts.isNotEmpty)
        'orderCountDelta': sold.parts.length - before.parts.length,
      if (waiting.isNotEmpty)
        'oldestPendingHours': now
            .difference(waiting.reduce((a, b) => a.isBefore(b) ? a : b))
            .inHours,
      'rating': ?(store == null ? null : _withRating(store)['rating']),
      'ratingCount': ?(store == null
          ? null
          : _withRating(store)['reviewCount']),
      // The last six months, this one lit. Nine days drew a single bar
      // for a store that delivers a few times a week (the tester). Each
      // point says when it starts, for the app to name in its language:
      // "D-0" and "W1" stayed Latin in Arabic.
      'salesSeries': [
        for (var back = 5; back >= 0; back--)
          <String, dynamic>{
            'label': 'M-$back',
            'from': DateTime(now.year, now.month - back).toIso8601String(),
            'unit': 'MONTH',
            'value': _sales(
              DateTime(now.year, now.month - back),
              back == 0 ? now : DateTime(now.year, now.month - back + 1),
            ).goods,
          },
      ],
    };
  }

  /// Stock the merchant has changed in this session.
  ///
  /// Adjusting stock used to reply 200 with an empty body onto a list read
  /// straight from the fixtures, so the stepper moved, the list refreshed,
  /// and the number came back exactly as it was.
  final Map<String, int> _stockOverrides = <String, int>{};

  /// Stock is kept per *thing sold*: a product with no options, or one
  /// option of a product that has them. A product used to carry a count of
  /// its own beside its options' - the page said 12 while its colours said
  /// 5, 4 and 3 - and only the product's own number ever moved.
  int _stockOf(String key, int seeded) => _stockOverrides[key] ?? seeded;

  /// The key stock is kept under for a line: its option, or the product.
  static String _stockKey(Object? productId, Object? variantId) =>
      '${variantId ?? productId}';

  /// One option's stock as it stands.
  int _variantStock(Map<dynamic, dynamic> variant) => _stockOf(
    '${variant['id']}',
    (variant['availableQuantity'] as num?)?.toInt() ?? 0,
  );

  /// How many of [product] can be sold: its own count, or the sum of its
  /// options' when it has options. There is no third number.
  int _productStock(Map<String, dynamic> product) {
    final variants = product['variants'] as List<dynamic>? ?? const [];
    if (variants.isEmpty) {
      return _stockOf(
        '${product['id']}',
        (product['availableQuantity'] as num?)?.toInt() ?? 0,
      );
    }
    var total = 0;
    for (final variant in variants) {
      total += _variantStock(variant as Map<dynamic, dynamic>);
    }
    return total;
  }

  /// A count as a status, the one rule for both.
  static String _stockStatus(int left) => left <= 0
      ? 'OUT_OF_STOCK'
      : left < 6
      ? 'LOW_STOCK'
      : 'IN_STOCK';

  _Reply _merchantProductRoutes(
    String method,
    List<String> path,
    RequestOptions options,
  ) {
    final productId = path.length > 3 ? path[3] : '';

    if (productId == 'counts') {
      final rows = _merchantProducts(null);
      int count(bool Function(Map<String, dynamic>) test) =>
          rows.where(test).length;
      return _Reply(<String, dynamic>{
        'all': rows.length,
        'waiting': count(
          (r) => r['status'] == 'PENDING' || r['status'] == 'DRAFT',
        ),
        'low': count(
          (r) =>
              (r['stock'] as int) > 0 &&
              (r['stock'] as int) <= (r['lowStockThreshold'] as int),
        ),
        'out': count((r) => (r['stock'] as int) <= 0),
        'hidden': count((r) => r['isActive'] == false),
      });
    }

    // POST /merchants/me/products/:id/submit - the paper plane. A draft
    // or a rejected product goes back to Saba to be looked at. It used to
    // fall through to an empty 200, so the icon reported success and the
    // row kept the status it had.
    if (productId.isNotEmpty && path.length > 4 && path[4] == 'submit') {
      final own = _storeProducts.indexWhere(
        (p) => p['id'] == productId && p['merchantId'] == _shelfStore,
      );
      if (own >= 0) {
        _storeProducts[own]['status'] = 'PENDING';
      } else {
        _fixtureStatus[productId] = 'PENDING';
      }
      return const _Reply(<String, dynamic>{});
    }

    // POST /merchants/me/products/:id/visibility {isActive} - the eye on
    // the shelf. The store could not hide a product at all: only Saba could.
    if (productId.isNotEmpty && path.length > 4 && path[4] == 'visibility') {
      final shown = _body(options)['isActive'];
      if (shown is! bool) {
        return const _Reply(<String, dynamic>{}, statusCode: 422);
      }
      // Saba took it down: only Saba puts it back.
      if (_takenDown.containsKey(productId)) {
        return _Reply(<String, dynamic>{
          'code': 'BUSINESS_RULE_ERROR',
          'message': _arabic
              ? 'أوقف سبأ عرض هذا المنتج، ولا يعود إلا بقرار منه.'
              : 'Saba took this product down; only Saba can put it back.',
        }, statusCode: 409);
      }
      _shown[productId] = shown;
      return const _Reply(<String, dynamic>{});
    }

    // POST /merchants/me/products/:id/flash-sale {salePrice, saleEndsAt}
    // starts a flash sale, or changes the one running; DELETE ends it now.
    if (productId.isNotEmpty && path.length > 4 && path[4] == 'flash-sale') {
      final product = _ownProduct(productId);
      if (product == null) {
        return const _Reply(<String, dynamic>{}, statusCode: 404);
      }
      if (method == 'DELETE') {
        if (product['saleEndsAt'] != null) _endSale(product);
        return const _Reply(<String, dynamic>{});
      }
      // Only what shoppers can see and buy: a hidden product took a sale
      // nobody could see. One already running can still be ended.
      if (!_isListed(product)) {
        return _Reply(<String, dynamic>{
          'code': 'CONFLICT_ERROR',
          'message': _arabic
              ? 'لا يدخل العرض السريع إلا منتج يراه المتسوقون.'
              : 'Only a product shoppers can see goes on a flash sale.',
        }, statusCode: 409);
      }
      return _startSale(product, _body(options));
    }

    // Setting stock straight from the list: the design's stepper and its
    // Restock button both land here.
    if (productId.isNotEmpty && path.length > 4 && path[4] == 'stock') {
      final body = _body(options);
      final value = body['stock'];
      if (value is num) {
        _stockOverrides[productId] = value.toInt().clamp(0, 99999);
      }
      return const _Reply(<String, dynamic>{});
    }

    // GET /merchants/me/products/:id - one of my own products, in full.
    //
    // The edit form had no way to ask for this, so it was built from the
    // list row: a name, a price, a SKU and a stock level. Everything else on
    // the product was invisible while editing it, and the images the form
    // did send were the one thumbnail the row carried - so saving a price
    // change replaced three photographs with one.
    if (method == 'GET' && productId.isNotEmpty) {
      final product = _findProduct(productId);
      if (product == null) {
        return const _Reply(<String, dynamic>{}, statusCode: 404);
      }
      // Named, as the server names it: the form shows a category Saba hid
      // since by this name, the tree no longer having it.
      final category = _categoryById(product['categoryId']);
      return _Reply(<String, dynamic>{
        ..._withStock(product),
        'categoryName': ?category?['name'],
        'categoryNameAr': ?category?['nameAr'],
      });
    }

    if (method == 'POST' || method == 'PUT' || method == 'PATCH') {
      if (_notInCashSteps(_body(options)) case final refused?) return refused;
      // A save of the product itself, not a step on it such as "submit".
      if (path.length <= 4) {
        if (_noArabicName(_body(options)) case final refused?) return refused;
      }
    }

    // POST /merchants/me/products - a new product, kept for the session.
    if (method == 'POST' && productId.isEmpty) {
      final body = _body(options);
      if (_hiddenCategoryChosen(body, null) case final refused?) return refused;
      final (brand, badBrand) = _savedBrand(null, body);
      if (badBrand != null) return badBrand;
      final product = _productFromDraft(body, id: _nextId('p-new'))
        ..['merchantId'] = _shelfStore
        ..['createdAt'] = DateTime.now().toUtc().toIso8601String();
      if (brand != null) product['brand'] = brand;
      _storeProducts.insert(0, product);
      return _Reply(product);
    }

    // PUT and DELETE on a product the merchant added. The demo products
    // themselves stay as they are.
    final added = _storeProducts.indexWhere(
      (p) => p['id'] == productId && p['merchantId'] == _shelfStore,
    );
    if (added >= 0 && path.length == 4) {
      if (method == 'DELETE') {
        _storeProducts.removeAt(added);
        return const _Reply(<String, dynamic>{});
      }
      if (method == 'PUT' || method == 'PATCH') {
        final previous = _storeProducts[added];
        final (stocks, moved) = _savedStocks(previous, _body(options));
        if (moved != null) return moved;
        final hidden = _hiddenCategoryChosen(
          _body(options),
          previous['categoryId'],
        );
        if (hidden != null) return hidden;
        final (brand, badBrand) = _savedBrand(
          previous['brand'] as Map<String, dynamic>?,
          _body(options),
        );
        if (badBrand != null) return badBrand;
        _storeProducts[added] =
            _productFromDraft(
                <String, dynamic>{
                  // A blank field is sent as absent and means "unchanged".
                  if (previous['description'] != null)
                    'description': previous['description'],
                  ..._body(options),
                },
                id: productId,
                status: previous['status'].toString(),
              )
              ..['merchantId'] = _shelfStore
              // An edit while a flash sale runs keeps it running.
              ..['saleEndsAt'] = previous['saleEndsAt']
              ..['createdAt'] = previous['createdAt']
              ..['rejectionReason'] = previous['rejectionReason'];
        if (brand != null) _storeProducts[added]['brand'] = brand;
        _stockOverrides.addAll(stocks);
        return _Reply(_storeProducts[added]);
      }
    }

    // A demo product of this store, edited: changed where it is kept, so the
    // shelf, the edit form and the shopper's page all show the new one. It
    // replied "saved" and kept nothing.
    final fixture = MockData.productById(productId);
    if (fixture != null &&
        (fixture['merchant'] as Map)['id'] == _shelfStore &&
        path.length == 4 &&
        (method == 'PUT' || method == 'PATCH')) {
      _fixtureOriginals.putIfAbsent(
        productId,
        () => Map<String, dynamic>.of(fixture),
      );
      final body = _body(options);
      final (stocks, moved) = _savedStocks(fixture, body);
      if (moved != null) return moved;
      final hidden = _hiddenCategoryChosen(body, fixture['categoryId']);
      if (hidden != null) return hidden;
      final (brand, badBrand) = _savedBrand(
        (fixture['brand'] as Map?)?.cast<String, dynamic>(),
        body,
      );
      if (badBrand != null) return badBrand;
      if (brand == null) {
        fixture.remove('brand');
      } else {
        fixture['brand'] = brand;
      }
      final edited = _productFromDraft(body, id: productId);
      for (final field in const [
        'name',
        'nameEn',
        'nameAr',
        'price',
        'originalPrice',
        'description',
        // The form has one of each: what it saves is the words in both
        // languages, so the Arabic kept beside them goes.
        'descriptionAr',
        'sku',
        'barcode',
        'warranty',
        'warrantyAr',
        'returnPolicy',
        'lowStockThreshold',
        // The category and the options were sent, accepted and dropped, so
        // a store that moved a product to another category, or changed a
        // colour, was told it had saved and found the old one still there.
        'categoryId',
        'variants',
        'optionColours',
      ]) {
        if (edited.containsKey(field)) {
          fixture[field] = edited[field];
        } else if (field != 'description') {
          fixture.remove(field);
        }
      }
      if ((body['images'] as List?)?.isNotEmpty ?? false) {
        fixture['images'] = edited['images'];
        fixture['imageUrl'] = edited['imageUrl'];
      }
      _stockOverrides.addAll(stocks);
      return _Reply(fixture);
    }

    // DELETE on one of the demo's own products. It used to answer 200 and
    // leave the product exactly where it was, on the shelf and in the shop.
    if (method == 'DELETE' && productId.isNotEmpty) {
      final fixture = MockData.productById(productId);
      if (fixture != null &&
          (fixture['merchant'] as Map)['id'] == _shelfStore) {
        _removedProducts.add(productId);
        return const _Reply(<String, dynamic>{});
      }
    }

    if (method != 'GET') return const _Reply(<String, dynamic>{});
    return _page(_merchantProducts(options), options);
  }

  /// Why a product cannot be saved without its Arabic name, or null. Most
  /// shoppers in Iraq read Arabic; the English name is the optional one.
  /// The brand a product save names, as the server has it (the admin's
  /// brands page): `brandId` picked from the list, or null to take it off;
  /// `brandName` typed, found whatever the case in either language, or
  /// added to wait for Saba's check. [current] when the save names neither.
  (Map<String, dynamic>?, _Reply?) _savedBrand(
    Map<String, dynamic>? current,
    Map<String, dynamic> body,
  ) {
    final all = <Map<String, dynamic>>[...MockData.brands, ..._addedBrands];
    Map<String, dynamic> onProduct(Map<String, dynamic> brand) =>
        <String, dynamic>{'id': brand['id'], 'name': brand['name']};
    if (body.containsKey('brandId')) {
      if (body['brandId'] == null) return (null, null);
      final found = all.where((b) => b['id'] == body['brandId']).firstOrNull;
      if (found != null) return (onProduct(found), null);
      final message = _arabic
          ? 'اختر علامة تجارية من القائمة.'
          : 'Choose a brand from the list.';
      return (
        current,
        _Reply(<String, dynamic>{
          'message': message,
          'errors': <String, dynamic>{'brandId': message},
        }, statusCode: 422),
      );
    }
    final typed = '${body['brandName'] ?? ''}'.trim();
    if (typed.isEmpty) return (current, null);
    final folded = typed.toLowerCase();
    final found = all
        .where(
          (b) =>
              '${b['name']}'.toLowerCase() == folded ||
              '${b['nameAr'] ?? ''}'.toLowerCase() == folded,
        )
        .firstOrNull;
    if (found != null) return (onProduct(found), null);
    final added = <String, dynamic>{'id': _nextId('b-new'), 'name': typed};
    _addedBrands.add(added);
    return (onProduct(added), null);
  }

  /// A category Saba hid, or one under a hidden one.
  bool _isHiddenCategory(Object? id) {
    if (hiddenCategories.contains(id)) return true;
    for (final parent in MockData.categories) {
      if (!hiddenCategories.contains(parent['id'])) continue;
      for (final child in parent['children'] as List? ?? const <dynamic>[]) {
        if ((child as Map)['id'] == id) return true;
      }
    }
    return false;
  }

  /// The categories shoppers and stores see: less what Saba hid, and what
  /// sits under it.
  List<Map<String, dynamic>> _shownCategories() => <Map<String, dynamic>>[
    for (final parent in MockData.categories)
      if (!hiddenCategories.contains(parent['id']))
        <String, dynamic>{
          ...parent,
          'children': <dynamic>[
            for (final child in parent['children'] as List? ?? const [])
              if (!hiddenCategories.contains((child as Map)['id'])) child,
          ],
        },
  ];

  /// A save that puts a product in a category Saba hid. One already in it
  /// keeps it (the admin's categories page).
  _Reply? _hiddenCategoryChosen(Map<String, dynamic> body, Object? current) {
    final id = body['categoryId'];
    if (id == null || id == current || !_isHiddenCategory(id)) return null;
    final message = _arabic
        ? 'أخفت سبأ هذا القسم. اختر قسماً آخر.'
        : 'Saba has hidden this category. Choose another one.';
    return _Reply(<String, dynamic>{
      'message': message,
      'errors': <String, dynamic>{'categoryId': message},
    }, statusCode: 422);
  }

  _Reply? _noArabicName(Map<String, dynamic> body) {
    final arabic = '${body['nameAr'] ?? ''}'.trim();
    if (arabic.length >= 3 && RegExp('[\u0600-\u06FF]').hasMatch(arabic)) {
      return null;
    }
    final message = _arabic
        ? 'اكتب اسم المنتج بالعربية.'
        : 'Write the product name in Arabic.';
    return _Reply(<String, dynamic>{
      'message': message,
      'errors': <String, dynamic>{'nameAr': message},
    }, statusCode: 422);
  }

  /// The stocks a save of [current] leaves, by what is sold, as the server
  /// has it (cd6228c): the store's number only where it changed the box
  /// from what the form showed (`stockBefore`). Unchanged, or sent without
  /// it, a stock stays, so what sold while the form was open stays sold;
  /// changed while it moved underneath, the save is refused (409). A new
  /// option starts at what was sent.
  (Map<String, int>, _Reply?) _savedStocks(
    Map<String, dynamic> current,
    Map<String, dynamic> body,
  ) {
    final stocks = <String, int>{};
    _Reply moved(int now, String? option) => _Reply(<String, dynamic>{
      'message': switch ((option, _arabic)) {
        (null, false) =>
          'Stock changed while you were editing: $now left now. '
              'Check it and save again.',
        (null, true) =>
          'تغيّر المخزون أثناء التعديل: المتبقي الآن $now. '
              'تحقّق منه واحفظ مرة أخرى.',
        (_, false) =>
          'The stock of $option changed while you were editing: $now left '
              'now. Check it and save again.',
        (_, true) =>
          'تغيّر مخزون $option أثناء التعديل: المتبقي الآن $now. '
              'تحقّق منه واحفظ مرة أخرى.',
      },
    }, statusCode: 409);
    // The stock to keep, or null when it moved under a changed box.
    int? edited(int now, Object? sent, Object? before) {
      final number = (sent as num?)?.toInt() ?? 0;
      final shown = (before as num?)?.toInt();
      if (shown == null || number == shown) return now;
      return now == shown ? number : null;
    }

    final saved = [
      for (final variant in current['variants'] as List? ?? const [])
        (variant as Map).cast<String, dynamic>(),
    ];
    final sent = [
      for (final variant in body['variants'] as List? ?? const [])
        (variant as Map).cast<String, dynamic>(),
    ];
    final id = '${current['id']}';
    if (sent.isEmpty) {
      // Options taken away: the product is sold as one thing, from what
      // was sent.
      if (saved.isNotEmpty) {
        return ({id: (body['stock'] as num?)?.toInt() ?? 0}, null);
      }
      final now = _productStock(current);
      final kept = edited(now, body['stock'], body['stockBefore']);
      if (kept == null) return (const <String, int>{}, moved(now, null));
      return ({id: kept}, null);
    }
    for (final variant in sent) {
      final match = saved.where((s) => s['id'] == variant['id']).firstOrNull;
      if (variant['id'] == null || match == null) continue;
      final now = _variantStock(match);
      final kept = edited(now, variant['stock'], variant['stockBefore']);
      if (kept == null) {
        final label = [
          for (final option in variant['options'] as List? ?? const [])
            (option as Map)['value'],
        ].join(' · ');
        return (const <String, int>{}, moved(now, label));
      }
      stocks['${match['id']}'] = kept;
    }
    return (stocks, null);
  }

  /// What [key] - a product, or one of its options - started the demo with.
  int _seededFor(String key) {
    final product = _findProduct(key);
    if (product != null) {
      return (product['availableQuantity'] as num?)?.toInt() ?? 0;
    }
    for (final candidate in [..._storeProducts, ...MockData.products]) {
      for (final variant
          in (candidate['variants'] as List<dynamic>? ?? const [])) {
        if ((variant as Map)['id'] == key) {
          return (variant['availableQuantity'] as num?)?.toInt() ?? 0;
        }
      }
    }
    return 0;
  }

  _Reply _merchantInventoryRoutes(
    String method,
    List<String> path,
    RequestOptions options,
  ) {
    // /merchants/me/inventory/:id/adjust - a delta, applied by the server.
    if (path.length > 4 && path[4] == 'adjust') {
      // `inv-p-3` is a product, `inv-p-3-v1` one of its options. The row is
      // keyed by the thing whose stock it shows, and that is the key the
      // number is kept under - an option's adjustment used to be written
      // under the option's id and read back from the product's, so the
      // sheet saved and the row came back exactly as it was.
      final id = path[3];
      final key = id.startsWith('inv-') ? id.substring(4) : id;
      final delta = _body(options)['quantity'];
      if (delta is num) {
        final next = _stockOf(key, _seededFor(key)) + delta.toInt();
        _stockOverrides[key] = next.clamp(0, 99999);
      }
      return const _Reply(<String, dynamic>{});
    }

    if (method != 'GET') return const _Reply(<String, dynamic>{});
    return _page(_merchantInventory(), options);
  }

  List<Map<String, dynamic>> _merchantProducts(RequestOptions? options) {
    final status = options?.queryParameters['status']?.toString();
    // The design's shelf is sorted by what is sellable, not by what the
    // catalogue team approved: all, running low, out, hidden.
    final filter = options?.queryParameters['filter']?.toString().toLowerCase();
    final query = options?.queryParameters['q']?.toString().trim();

    // What the merchant added first, then - for the demo store only - the
    // demo shelf. A new store's shelf is what it has added and nothing else.
    final shelf = <(Map<String, dynamic>, String, bool, int)>[
      for (final product in _addedProducts)
        (
          product,
          product['status'].toString(),
          _shown[product['id']] ?? true,
          (product['availableQuantity'] as num).toInt(),
        ),
    ];
    if (!_isNewStore) {
      for (final product in MockData.products) {
        if ((product['merchant'] as Map)['id'] != _shelfStore) continue;
        if (_removedProducts.contains(product['id'])) continue;

        // The same answer the shop gives: what the shelf says is waiting or
        // hidden is not for sale.
        final (:status, :isActive) = _shelfState(product);
        final rowStatus = status;
        // What the shopper is told, too. The shelf set its third product
        // to none, so its "Out" tab had something in it, and the store
        // read "Out of stock" for headphones shoppers were buying.
        final seeded = (product['availableQuantity'] as num).toInt();
        shelf.add((product, rowStatus, isActive, seeded));
      }
    }

    final rows = <Map<String, dynamic>>[];
    for (final (product, rowStatus, isActive, seeded) in shelf) {
      if (status != null && status.isNotEmpty && status != rowStatus) continue;

      final id = product['id'].toString();
      final variants = product['variants'] as List<dynamic>? ?? const [];
      // A product with options is as stocked as its options together.
      final stock = variants.isEmpty
          ? _stockOf(id, seeded)
          : _productStock(product);
      final threshold = (product['lowStockThreshold'] as num?)?.toInt() ?? 5;

      final matchesFilter = switch (filter) {
        'waiting' => rowStatus == 'PENDING' || rowStatus == 'DRAFT',
        'low' => stock > 0 && stock <= threshold,
        'out' => stock <= 0,
        'hidden' => !isActive,
        _ => true,
      };
      if (!matchesFilter) continue;

      if (query != null &&
          query.isNotEmpty &&
          !SearchText.matches(query, <String?>[
            '${product['name']}',
            product['nameEn'] as String?,
            product['nameAr'] as String?,
            product['sku'] as String?,
          ])) {
        continue;
      }

      rows.add(<String, dynamic>{
        'id': id,
        'name': product['name'],
        'nameAr': ?product['nameAr'],
        'price': product['price'],
        'originalPrice': ?product['originalPrice'],
        'saleEndsAt': ?product['saleEndsAt'],
        'currencyCode': MockData.currency,
        'status': rowStatus,
        'imageUrl': product['imageUrl'],
        'sku': product['sku'],
        'stock': stock,
        'hasVariants': variants.isNotEmpty,
        'lowStockThreshold': threshold,
        'isActive': isActive,
        'takenDown': _takenDown.containsKey(id),
        'takenDownReason': ?_takenDown[id],
        // Saba's reason, as the admin wrote it; the demo's own rejected
        // products keep the one they start with.
        if (rowStatus == 'REJECTED')
          'rejectionReason':
              product['rejectionReason'] ??
              'Images do not meet the catalogue guidelines.',
        if (rowStatus == 'REJECTED' && product['rejectionReason'] == null)
          'rejectionReasonAr': 'الصور لا تطابق إرشادات الكتالوج.',
      });
    }
    return rows;
  }

  List<Map<String, dynamic>> _merchantInventory() {
    final rows = <Map<String, dynamic>>[];
    // Same rule as the shelf: a new store stocks only what it has added.
    final products = [
      ..._addedProducts,
      if (!_isNewStore)
        ...MockData.products.where(
          (product) =>
              (product['merchant'] as Map)['id'] == _shelfStore &&
              !_removedProducts.contains(product['id']),
        ),
    ];

    for (final product in products) {
      final variants = product['variants'] as List<dynamic>? ?? const [];
      if (variants.isEmpty) {
        rows.add(<String, dynamic>{
          'id': 'inv-${product['id']}',
          'productId': product['id'],
          'name': product['name'],
          'sku': product['sku'],
          'imageUrl': product['imageUrl'],
          'available': _productStock(product),
          'reserved': _moved(product['id']).reserved,
          'sold': _moved(product['id']).sold,
          'lowStockThreshold': product['lowStockThreshold'] ?? 5,
        });
        continue;
      }

      for (final variant in variants) {
        final entry = variant as Map<String, dynamic>;
        final options = entry['options'] as Map;
        rows.add(<String, dynamic>{
          'id': 'inv-${entry['id']}',
          'productId': product['id'],
          'name': product['name'],
          'variantLabel': options.values.join(' · '),
          'sku': entry['sku'],
          'imageUrl': entry['imageUrl'] ?? product['imageUrl'],
          'available': _variantStock(entry),
          'reserved': _moved(
            product['id'],
            options.values.join(' · '),
          ).reserved,
          'sold': _moved(product['id'], options.values.join(' · ')).sold,
          'lowStockThreshold': product['lowStockThreshold'] ?? 5,
        });
      }
    }
    return rows;
  }

  /// The demo merchant's orders are stored, not regenerated per request.
  ///
  /// They used to be rebuilt on every call from `index % statuses.length`,
  /// which broke the two things this screen is for: the status query was
  /// ignored, so all eight tabs listed the same eight orders, and a status
  /// change reported success onto a card that then re-read as its old
  /// status. The merchant pressed "Next: Confirmed", was told "Confirmed",
  /// and watched nothing move.
  /// Built on first use and cleared by [resetForTesting], like every other
  /// piece of demo state here: the backend is one instance for the whole
  /// process, so an order advanced in one test would otherwise arrive
  /// already advanced in the next.
  /// A new store has had no orders; the demo store's are not theirs.
  List<Map<String, dynamic>> get _merchantOrderStore =>
      _isNewStore ? <Map<String, dynamic>>[] : _ordersOf(_shelfStore);

  /// One store's orders: the demo's history, then whatever shoppers order.
  /// Its history's refunded returns are seeded with it.
  List<Map<String, dynamic>> _ordersOf(String store) =>
      _storeOrders.putIfAbsent(store, () {
        _storeReturns
            .putIfAbsent(store, () => [])
            .addAll(_historyReturnsOf(store));
        return _seedMerchantOrders(store);
      });

  /// Each store's part of one shopper's order.
  List<Map<String, dynamic>> _partsOf(String orderId) => <Map<String, dynamic>>[
    for (final orders in _storeOrders.values)
      for (final part in orders)
        if (part['customerOrderId'] == orderId) part,
  ];

  _Reply _merchantOrderRoutes(
    String method,
    List<String> path,
    RequestOptions options,
  ) {
    final orderId = path.length > 3 ? path[3] : '';

    if (orderId.isEmpty) {
      final status = options.queryParameters['status']?.toString();
      // A comma list, because the merchant's queue is three buckets and
      // "Preparing" is two states of the workflow at once.
      final wanted = (status ?? '')
          .split(',')
          .map((value) => value.trim().toUpperCase())
          .where((value) => value.isNotEmpty)
          .toSet();
      final rows = wanted.isEmpty
          ? _merchantOrderStore
          : _merchantOrderStore
                .where((o) => wanted.contains(o['status']))
                .toList();
      return _page(rows, options);
    }

    // /merchants/me/orders/counts - one call for every pill's number, rather
    // than three list requests fired only to read their totals.
    if (orderId == 'counts') {
      final counts = <String, dynamic>{};
      for (final order in _merchantOrderStore) {
        final key = order['status'].toString();
        counts[key] = (counts[key] as int? ?? 0) + 1;
      }
      return _Reply(counts);
    }

    final order = _merchantOrderStore.firstWhere(
      (o) => o['id'] == orderId,
      orElse: () => <String, dynamic>{},
    );
    if (order.isEmpty) {
      return const _Reply(<String, dynamic>{}, statusCode: 404);
    }

    if (method == 'GET') {
      return _Reply(<String, dynamic>{
        ...order,
        'returns': [
          for (final request in _storeReturns[_shelfStore] ?? const [])
            // A seeded order has no shopper's order; its return names it.
            if (request['orderId'] == (order['customerOrderId'] ?? order['id']))
              request,
        ],
      });
    }

    // PATCH /merchants/me/orders/:id/status
    final body = _body(options);
    final next = body['status']?.toString();
    if (next == 'SHIPPED') {
      // The shopper is told who is coming and how to reach them.
      final name = '${body['courierName'] ?? ''}'.trim();
      final phone = '${body['courierPhone'] ?? ''}'.trim();
      if (name.isEmpty || phone.isEmpty) {
        final message = _arabic
            ? 'اذكر من يوصّل الطلب ورقم هاتفه.'
            : 'Say who delivers it, and their phone.';
        return _Reply(<String, dynamic>{
          'message': message,
          'errors': <String, dynamic>{
            name.isEmpty ? 'courierName' : 'courierPhone': message,
          },
        }, statusCode: 422);
      }
      // The store's own driver: v1 has no delivery companies.
      order['courierType'] = 'DRIVER';
      order['courierName'] = name;
      order['courierPhone'] = phone;
    }
    final wasLive = !_isOff(order['status']);
    if (next != null && next.isNotEmpty) order['status'] = next;
    if (wasLive && _isOff(next)) _restock(order);
    if (next == 'DELIVERED') {
      order['deliveredAt'] = DateTime.now().toIso8601String();
    }
    // Declining is not just a status: the customer's money goes back. The
    // reason is kept because the merchant was asked for one, and a reason
    // collected and then discarded is a question that wasted their time.
    final reason = body['reason']?.toString();
    if (reason != null && reason.isNotEmpty) {
      order['cancellationReason'] = reason;
      order['refundedAt'] = DateTime.now().toIso8601String();
    }
    if (next != null && next.isNotEmpty) _storeMoved(order);
    return _Reply(order);
  }

  /// The delivered order this shopper still owes a rating, or an empty
  /// reply when there is none.
  ///
  /// Oldest first: the order that has waited longest is the one asked about.
  /// An order that has been put off [_ratingAsks] times is let go.
  Map<String, dynamic> _ratingDue() {
    for (final order in _orders.reversed) {
      final id = '${order['id']}';
      if (_ratedOrders.contains(id)) continue;
      if ((_ratingSkips[id] ?? 0) >= _ratingAsks) continue;
      final delivered = <String, String>{};
      for (final part in (order['storeParts'] as List? ?? const [])) {
        if ((part as Map)['status'] != 'DELIVERED') continue;
        // Answered on the order page already: "did it arrive" is one
        // question, and asked twice it kept coming back.
        if (part['received'] != null) continue;
        // An order's store parts carry no name, so the sheet named no store
        // at all (BUGS.md 85): the name comes from the store itself.
        final store = '${part['merchantId']}';
        delivered[store] = '${_storeFace(store)['title']}';
      }
      if (delivered.isEmpty) continue;
      return <String, dynamic>{
        'orderId': id,
        'orderNumber': order['orderNumber'],
        'stores': [
          for (final store in delivered.entries)
            <String, dynamic>{'id': store.key, 'storeName': store.value},
        ],
      };
    }
    return const <String, dynamic>{};
  }

  /// The shopper's answer to the rating sheet.
  ///
  /// `received: false` means the parcel never came, so there is nothing to
  /// rate: the stores are told instead, exactly as the "did you receive it"
  /// answer does. Either way the order is not asked about again.
  _Reply _takeRating(String orderId, Map<String, dynamic> body) {
    final order = _orders.firstWhere(
      (o) => o['id'] == orderId,
      orElse: () => <String, dynamic>{},
    );
    if (order.isEmpty) {
      return const _Reply(<String, dynamic>{}, statusCode: 404);
    }

    _ratedOrders.add(orderId);

    if (body['received'] == false) {
      for (final part in (order['storeParts'] as List? ?? const [])) {
        if ((part as Map)['status'] != 'DELIVERED') continue;
        part['received'] = false;
        _notReceived(order, '${part['merchantId']}');
      }
      return _Reply(order);
    }

    final comment = '${body['comment'] ?? ''}'.trim();
    final stars = (body['ratings'] as Map?) ?? const <String, dynamic>{};
    final now = DateTime.now();
    final who = _currentUser()['fullName'] ?? '';

    stars.forEach((storeId, value) {
      final rating = (value as num?)?.toInt() ?? 0;
      if (rating < 1 || rating > 5) return;
      final key = 'store-$storeId';
      _reviews
          .putIfAbsent(key, () => _seedReviews(key))
          .insert(0, <String, dynamic>{
            'id': _nextId('rev'),
            'rating': rating,
            'body': comment.isEmpty ? null : comment,
            'authorName': who,
            'createdAt': now.toIso8601String(),
            'isVerifiedPurchase': true,
          });
      final given = _givenRatings['$storeId'] ?? (0, 0);
      _givenRatings['$storeId'] = (given.$1 + rating, given.$2 + 1);
    });
    // "Yes, it arrived" is for the whole order, stars or not: only the
    // stores given stars were marked, and the order page asked about the
    // rest again.
    for (final part in (order['storeParts'] as List? ?? const [])) {
      if ((part as Map)['status'] == 'DELIVERED') part['received'] = true;
    }

    return _Reply(order);
  }

  /// A store told that its parcel never arrived, so it can call the shopper.
  void _notReceived(Map<String, dynamic> order, String store) {
    final number = order['orderNumber'];
    final who = (order['shippingAddress'] as Map?)?['fullName'] ?? '';
    _notify(
      'store:$store',
      'ORDER',
      en: (
        'Order $number: not received',
        '$who says the parcel did not arrive. Call them about it.',
      ),
      ar: (
        'الطلب $number: لم يُستلم',
        'يقول $who إن الطرد لم يصل. اتصل به بشأنه.',
      ),
      target: ('STORE_ORDER', _partIdOf('${order['id']}', store)),
    );
  }

  /// [store]'s part of the shopper's order [orderId], for its notification.
  String _partIdOf(String orderId, String store) =>
      '${_partsOf(orderId).firstWhere((part) => part['merchantId'] == store, orElse: () => const <String, dynamic>{})['id']}';

  /// A part the store will not deliver: declined, or refused at the door.
  static bool _isOff(Object? status) =>
      status == 'CANCELLED' || status == 'REFUSED';

  /// What a store closing leaves behind: its orders not yet delivered or
  /// called off, what it owes Saba (this month so far and every month
  /// still due), and the last day a shopper can still ask for a return.
  Map<String, dynamic> _stillOpen() {
    final parts = _merchantOrderStore;
    final bills = _sabaBills();
    num owed = (bills['current'] as Map)['owed'] as num;
    for (final past in bills['past'] as List) {
      if ((past as Map)['status'] == 'DUE') owed += past['owed'] as num;
    }
    final now = DateTime.now();
    DateTime? returnsUntil;
    for (final part in parts) {
      if (part['status'] != 'DELIVERED') continue;
      final at = DateTime.tryParse('${part['deliveredAt']}');
      if (at == null) continue;
      final until = at.add(_returnWindow);
      if (until.isAfter(now) &&
          (returnsUntil == null || until.isAfter(returnsUntil))) {
        returnsUntil = until;
      }
    }
    return <String, dynamic>{
      'openOrders': parts
          .where((p) => p['status'] != 'DELIVERED' && !_isOff(p['status']))
          .length,
      'openReturns': (_storeReturns[_shelfStore] ?? const [])
          .where((r) => r['status'] == 'REQUESTED' || r['status'] == 'APPROVED')
          .length,
      'owed': owed,
      'returnsOpenUntil': returnsUntil?.toIso8601String(),
    };
  }

  /// The owner asks for the store's account to be deleted: the store closes
  /// at once, and the rest waits for what [_stillOpen] lists. The real
  /// server deletes it on its hourly round once nothing is; the demo has no
  /// clock, so here it stays asked for until taken back.
  _Reply _storeDeletion(String method) {
    final store = _shelfStore;
    if (method == 'DELETE') {
      _storeDeletions.remove(store);
      return const _Reply(<String, dynamic>{});
    }
    if (method == 'POST') {
      _storeDeletions.putIfAbsent(
        store,
        () => DateTime.now().toUtc().toIso8601String(),
      );
      _closedStores.add(store);
    }
    return _Reply(<String, dynamic>{
      'requestedAt': _storeDeletions[store],
      'currencyCode': 'IQD',
      ..._stillOpen(),
    });
  }

  /// What a store's part held goes back on its shelf.
  void _restock(Map<String, dynamic> part) {
    for (final item in (part['items'] as List? ?? const [])) {
      final key = _stockKey((item as Map)['productId'], item['variantId']);
      _stockOverrides[key] =
          _stockOf(key, _seededFor(key)) + (item['quantity'] as num).toInt();
    }
  }

  /// Returns are taken for 7 days after a store's part is delivered.
  static const Duration _returnWindow = Duration(days: 7);

  /// Which of [order]'s lines can still go back, and so whether it can.
  void _applyReturnWindow(Map<String, dynamic> order) {
    final items = (order['items'] as List).cast<Map<String, dynamic>>();
    final returned = _returnedItems;
    for (final item in items) {
      final at = DateTime.tryParse('${item['deliveredAt']}');
      item['canReturn'] =
          item['status'] == 'DELIVERED' &&
          at != null &&
          DateTime.now().difference(at) <= _returnWindow &&
          // An item is returned once: "Request a return" stayed after it.
          !returned.contains(item['id']);
    }
    order['canReturn'] = items.any((item) => item['canReturn'] == true);
  }

  /// Where an order has got to, to find the part furthest behind.
  static int _stage(Object? status) => switch ('$status') {
    'PENDING' => 0,
    'CONFIRMED' => 1,
    'PROCESSING' => 2,
    'SHIPPED' => 3,
    _ => 4,
  };

  /// A store moved its part of a shopper's order: the shopper's order says
  /// so - that store's lines, the order as far as its slowest store has
  /// got, the step in its history - and the shopper is told.
  void _storeMoved(Map<String, dynamic> part) {
    final order = _placedOrders[part['customerOrderId']];
    // One of the demo's own orders, with no shopper behind it.
    if (order == null) return;

    final store = '${part['merchantId']}';
    final status = part['status'] == 'PENDING'
        ? 'CONFIRMED'
        : '${part['status']}';
    final items = (order['items'] as List).cast<Map<String, dynamic>>();
    final now = DateTime.now().toIso8601String();
    for (final item in items) {
      if (item['merchantId'] != store) continue;
      item['status'] = status;
      if (status == 'DELIVERED') {
        item['deliveredAt'] = now;
      }
    }
    // Who is bringing it, for the shopper to call.
    for (final entry in (order['storeParts'] as List? ?? const [])) {
      if ((entry as Map)['merchantId'] != store) continue;
      entry['status'] = status;
      for (final field in const [
        'courierType',
        'courierName',
        'courierPhone',
      ]) {
        if (part[field] != null) entry[field] = part[field];
      }
    }
    // A store that turned its part down, or whose parcel was refused, is
    // left out; the others decide.
    final live = <String>[
      for (final item in items)
        if (!_isOff(item['status'])) '${item['status']}',
    ];
    final slowest = live.isEmpty
        ? null
        : live.reduce((a, b) => _stage(a) <= _stage(b) ? a : b);
    // As far as the slowest store, exactly: it read "Confirmed" while one
    // store had not confirmed, under a line promising the slowest store's
    // step (the tester). Each store's own step is in its box.
    order['status'] =
        slowest ??
        (items.every((item) => item['status'] == 'REFUSED')
            ? 'REFUSED'
            : 'CANCELLED');
    order['canCancel'] = live.isNotEmpty && live.every((s) => _stage(s) <= 1);
    // Nothing is coming, so nothing is paid: the invoice kept saying the
    // money was still to come.
    if (live.isEmpty) order['paymentStatus'] = 'CANCELLED';
    _applyReturnWindow(order);
    final driver = part['courierName'];
    // Written as every number is: it read +9647701112222 (the user).
    final driverPhone = part['courierPhone'] == null
        ? null
        // Kept left to right inside the Arabic words.
        : Formatters.ltrIsolate(IraqiPhone.display('${part['courierPhone']}'));
    // Cash is paid to the driver, so once everything has arrived it has been.
    if (order['paymentMethodType'] == 'COD' &&
        live.isNotEmpty &&
        live.every((s) => s == 'DELIVERED')) {
      order['paymentStatus'] = 'PAID';
    }

    final name = '${_storeFace(store)['title']}';
    final reason = status == 'CANCELLED' ? part['cancellationReason'] : null;
    (order['timeline'] as List).add(<String, dynamic>{
      'status': status,
      'occurredAt': DateTime.now().toIso8601String(),
      'store': name,
      'reasonCode': ?reason,
    });

    final number = '${order['orderNumber']}';
    (String, String) words({required bool arabic}) => switch (status) {
      'CONFIRMED' =>
        arabic
            ? ('أكّد $name طلبك', 'يجري تجهيز الطلب $number.')
            : (
                '$name confirmed your order',
                'Order $number is being prepared.',
              ),
      'PROCESSING' =>
        arabic
            ? ('يجهّز $name طلبك', 'سيُشحن الطلب $number قريباً.')
            : ('$name is preparing your order', 'Order $number ships soon.'),
      'SHIPPED' =>
        arabic
            ? (
                'طردك من $name في الطريق',
                driver == null
                    ? 'الطلب $number'
                    : 'الطلب $number · يوصله $driver، $driverPhone',
              )
            : (
                'Your parcel from $name is on its way',
                driver == null
                    ? 'Order $number'
                    : 'Order $number · $driver brings it, $driverPhone',
              ),
      'DELIVERED' =>
        arabic
            ? ('وصل طردك من $name', 'تم تسليم الطلب $number.')
            : (
                'Your parcel from $name arrived',
                'Order $number was delivered.',
              ),
      'REFUSED' =>
        arabic
            ? ('رفضت الطرد من $name', 'الطلب $number. لا تدفع شيئاً عنه.')
            : (
                'You refused the parcel from $name',
                'Order $number. There is nothing to pay for it.',
              ),
      _ =>
        arabic
            ? (
                'ألغى $name جزءاً من طلبك',
                'الطلب $number${reason == null ? '' : ': $reason'}. '
                    'أي مبلغ دفعته عنه يعود إليك.',
              )
            : (
                '$name cancelled part of your order',
                'Order $number${reason == null ? '' : ': $reason'}. '
                    'Anything you paid for it comes back to you.',
              ),
    };
    _notify(
      '${part['customerEmail']}',
      switch (status) {
        'SHIPPED' => 'SHIPPING',
        'DELIVERED' => 'DELIVERY',
        _ => 'ORDER',
      },
      en: words(arabic: false),
      ar: words(arabic: true),
      target: ('ORDER', '${order['id']}'),
    );
  }

  /// Something for one inbox: an email, or `store:<id>`.
  ///
  /// [target] is what it is about, `(type, id)`, for the app to open when it
  /// is tapped: ORDER (the shopper's order), STORE_ORDER (a store's part of
  /// one), RETURN, STORE_PRODUCT, STORE or CONVERSATION. Every one had none
  /// but the shopper's order steps, so tapping the rest opened nothing - a
  /// store's "New order" above all (the user).
  void _notify(
    String to,
    String type, {
    required (String, String) en,
    required (String, String) ar,
    required (String, String) target,
  }) {
    _events.insert(0, <String, dynamic>{
      'id': _nextId('ev'),
      'to': to,
      'type': type,
      'en': en,
      'ar': ar,
      'targetType': target.$1,
      'targetId': target.$2,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  /// Whose notifications are being read: the store's, for its owner.
  String get _inbox {
    final store = _myStoreId;
    return store == null ? _email : 'store:$store';
  }

  /// The demo stores' customers, one in each city they send to.
  static const Map<String, Map<String, String>> _seedCustomers =
      <String, Map<String, String>>{
        'BAGHDAD': {
          'name': 'Sara Ahmed',
          'nameAr': 'سارة أحمد',
          'phone': '+9647705550142',
          'displayPhone': '+964 770 555 0142',
          'area': 'Karrada',
          'areaAr': 'الكرادة',
          'street': 'Street 62, House 9',
          'streetAr': 'شارع 62، دار 9',
          'landmark': 'Behind the Karrada Maternity Hospital',
          'landmarkAr': 'خلف مستشفى الكرادة للولادة',
        },
        'ERBIL': {
          'name': 'Yousef Karim',
          'nameAr': 'يوسف كريم',
          'phone': '+9647515550198',
          'displayPhone': '+964 751 555 0198',
          'area': 'Ainkawa',
          'areaAr': 'عينكاوا',
          'street': 'Block 3',
          'streetAr': 'بلوك 3',
          'landmark': 'Next to Ainkawa Mall',
          'landmarkAr': 'بجانب مول عينكاوا',
        },
        'BASRA': {
          'name': 'Zainab Hussein',
          'nameAr': 'زينب حسين',
          'phone': '+9647805550117',
          'displayPhone': '+964 780 555 0117',
          'area': 'Al-Jazaer',
          'areaAr': 'الجزائر',
          'street': 'Street 5, House 21',
          'streetAr': 'شارع 5، دار 21',
          'landmark': 'Near Al-Jazaer Park',
          'landmarkAr': 'قرب متنزه الجزائر',
        },
        'DUHOK': {
          'name': 'Rawand Omar',
          'nameAr': 'رواند عمر',
          'phone': '+9647505550163',
          'displayPhone': '+964 750 555 0163',
          'area': 'Masike',
          'areaAr': 'ماسيكي',
          'street': 'Street 12',
          'streetAr': 'شارع 12',
          'landmark': 'Behind the Masike mosque',
          'landmarkAr': 'خلف جامع ماسيكي',
        },
        'SULAYMANIYAH': {
          'name': 'Shilan Aziz',
          'nameAr': 'شيلان عزيز',
          'phone': '+9647705550184',
          'displayPhone': '+964 770 555 0184',
          'area': 'Bakhtiyari',
          'areaAr': 'بختياري',
          'street': 'Street 40, House 3',
          'streetAr': 'شارع 40، دار 3',
          'landmark': 'Opposite the Bakhtiyari clinic',
          'landmarkAr': 'مقابل مستوصف بختياري',
        },
        'NINEVEH': {
          'name': 'Omar Younis',
          'nameAr': 'عمر يونس',
          'phone': '+9647715550126',
          'displayPhone': '+964 771 555 0126',
          'area': 'Al-Zuhur',
          'areaAr': 'الزهور',
          'street': 'Street 8, House 14',
          'streetAr': 'شارع 8، دار 14',
          'landmark': 'Near Al-Zuhur market',
          'landmarkAr': 'قرب سوق الزهور',
        },
      };

  List<Map<String, dynamic>> _seedMerchantOrders(String store) {
    const statuses = <String>[
      'PENDING',
      'CONFIRMED',
      'PROCESSING',
      'SHIPPED',
      'DELIVERED',
    ];

    // Its customers live where it delivers - one in its own city, one in
    // another it sends to - and pay what it asks for that city. Every seeded
    // order charged a flat 5,000, and Atlas, which does not go to Erbil,
    // had orders delivered there.
    final home = _storeCityOf(store) ?? 'BAGHDAD';
    final away = [
      for (final city in _deliveryOf(store)['governorates'] as List)
        if (city != home && _seedCustomers.containsKey(city)) '$city',
    ];
    final cities = <String>[home, away.isEmpty ? home : away.first];

    // The store's own products only: Nova's history listed Atlas's goods.
    final shelf = <Map<String, dynamic>>[
      for (final product in MockData.products)
        if ((product['merchant'] as Map)['id'] == store) product,
    ];
    if (shelf.isEmpty) return <Map<String, dynamic>>[];
    final prefix = store == 'm-1' ? 'mo' : '$store-mo';
    final firstNumber = store == 'm-1' ? 200100 : 200200;

    final orders = <Map<String, dynamic>>[];

    for (var index = 0; index < 8; index++) {
      final itemCount = 1 + index % 3;
      final items = <Map<String, dynamic>>[];

      for (var line = 0; line < itemCount; line++) {
        final product = shelf[(index + line) % shelf.length];
        final quantity = 1 + line % 2;
        final price = (product['price'] as num).toDouble();
        items.add(<String, dynamic>{
          'id': '${prefix}i-$index-$line',
          'productId': product['id'],
          'name': product['name'],
          'nameAr': ?product['nameAr'],
          'imageUrl': product['imageUrl'],
          'sku': product['sku'],
          'quantity': quantity,
          'price': price,
        });
      }

      final status = statuses[index % statuses.length];
      final city = cities[index % 2];
      orders.add(
        _seededPart(
          store: store,
          id: '$prefix-${index + 1}',
          orderNumber: 'SB-${firstNumber + index}',
          placedAt: DateTime.now().subtract(Duration(hours: 6 * index)),
          status: status,
          deliveredAt: status == 'DELIVERED'
              ? DateTime.now().subtract(Duration(hours: 6 * index - 4))
              : null,
          items: items,
          customer: _seedCustomers[city]!,
          city: city,
          withDriver: status == 'SHIPPED' || status == 'DELIVERED',
        ),
      );
    }

    return [...orders, ..._historyOf(store)];
  }

  /// A seeded shopper's id, as the admin web makes it from the phone
  /// (website/src/data/people.ts, customerIdOf), so both demos agree.
  static String _customerIdOf(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return 'cu-${digits.substring(math.max(0, digits.length - 7))}';
  }

  /// One seeded order, as its store sees it: [items] to [customer] in
  /// [city], at the store's own fee for that city.
  Map<String, dynamic> _seededPart({
    required String store,
    required String id,
    required String orderNumber,
    required DateTime placedAt,
    required String status,
    required DateTime? deliveredAt,
    required List<Map<String, dynamic>> items,
    required Map<String, String> customer,
    required String city,
    required bool withDriver,
  }) {
    final driver = withDriver ? _storeDrivers[store] : null;
    final subtotal = items.fold<double>(
      0,
      (sum, item) =>
          sum + (item['price'] as double) * (item['quantity'] as int),
    );
    final shipping = _deliveryTerms(store, city)!.fee.toDouble();
    return <String, dynamic>{
      'id': id,
      'merchantId': store,
      'orderNumber': orderNumber,
      'customerId': _customerIdOf(customer['displayPhone']!),
      'placedAt': placedAt.toIso8601String(),
      'status': status,
      'deliveredAt': ?deliveredAt?.toIso8601String(),
      'subtotal': subtotal,
      'shipping': shipping,
      'total': subtotal + shipping,
      'currencyCode': MockData.currency,
      'itemCount': items.fold<int>(
        0,
        (total, item) => total + (item['quantity'] as int),
      ),
      'customerName': customer['name'],
      'customerNameAr': customer['nameAr'],
      'customerArea': customer['area'],
      'customerAreaAr': customer['areaAr'],
      'customerGovernorate': city,
      'paymentMethodLabel': 'Cash on delivery',
      'paymentMethodLabelAr': 'الدفع عند الاستلام',
      'customerPhone': customer['displayPhone'],
      'shippingAddress': <String, dynamic>{
        'fullName': customer['name'],
        'fullNameAr': customer['nameAr'],
        'phone': customer['phone'],
        'governorate': city,
        'area': customer['area'],
        'areaAr': customer['areaAr'],
        'street': customer['street'],
        'streetAr': customer['streetAr'],
        'landmark': customer['landmark'],
        'landmarkAr': customer['landmarkAr'],
      },
      'previewImageUrl': items.first['imageUrl'],
      'items': items,
      // Who took it out: the store's own driver, as it names them when it
      // ships. The seed gave a tracking number and no driver.
      if (driver != null) ...<String, dynamic>{
        'courierType': 'DRIVER',
        'courierName': driver.$1,
        'courierNameAr': driver.$2,
        'courierPhone': driver.$3,
      },
    };
  }

  /// Each demo store's own driver, as the admin web has them
  /// (website/src/data/orders.ts, DRIVERS): the name, in Arabic, the phone.
  static const Map<String, (String, String, String)> _storeDrivers = {
    'm-1': ('Haider Salim', 'حيدر سالم', '+9647705550311'),
    'm-2': ('Mustafa Adnan', 'مصطفى عدنان', '+9647805550322'),
    'm-3': ('Rebwar Sabah', 'ريبوار صباح', '+9647505550333'),
    'm-4': ('Shivan Ahmed', 'شيفان أحمد', '+9647505550344'),
    'm-5': ('Hemin Rashid', 'هيمن رشيد', '+9647505550355'),
    'm-6': ('Karwan Omer', 'كاروان عمر', '+9647505550366'),
    'm-7': ('Aram Jalal', 'آرام جلال', '+9647705550377'),
    'm-8': ('Yasser Thamer', 'ياسر ثامر', '+9647705550388'),
  };

  /// The shoppers the demo stores delivered to before today, in the admin
  /// web's order (website/src/data/orders.ts, CUSTOMER_ADDRESSES).
  static final List<Map<String, String>> _historyCustomers = [
    {..._seedCustomers['BAGHDAD']!, 'governorate': 'BAGHDAD'},
    {..._seedCustomers['ERBIL']!, 'governorate': 'ERBIL'},
    {
      'name': 'Noor Hadi',
      'nameAr': 'نور هادي',
      'phone': '+9647805550167',
      'displayPhone': '+964 780 555 0167',
      'governorate': 'BASRA',
      'area': 'Al-Jazaer',
      'areaAr': 'الجزائر',
      'street': 'Street 20, House 7',
      'streetAr': 'شارع 20، دار 7',
      'landmark': 'Near Al-Jazaer Park',
      'landmarkAr': 'قرب متنزه الجزائر',
    },
    {
      'name': 'Ahmed Jasim',
      'nameAr': 'أحمد جاسم',
      'phone': '+9647705550211',
      'displayPhone': '+964 770 555 0211',
      'governorate': 'BAGHDAD',
      'area': 'Al-Mansour',
      'areaAr': 'المنصور',
      'street': 'Street 14, House 30',
      'streetAr': 'شارع 14، دار 30',
      'landmark': 'Near Al-Rowad Mosque',
      'landmarkAr': 'قرب جامع الرواد',
    },
    {
      'name': 'Hawre Kamal',
      'nameAr': 'هاوري كمال',
      'phone': '+9647505550224',
      'displayPhone': '+964 750 555 0224',
      'governorate': 'SULAYMANIYAH',
      'area': 'Bakhtiari',
      'areaAr': 'بختياري',
      'street': 'Street 40, House 12',
      'streetAr': 'شارع 40، دار 12',
      'landmark': 'Behind Family Mall',
      'landmarkAr': 'خلف فاميلي مول',
    },
    {
      'name': 'Zahraa Ali',
      'nameAr': 'زهراء علي',
      'phone': '+9647805550237',
      'displayPhone': '+964 780 555 0237',
      'governorate': 'NAJAF',
      'area': 'Al-Adala',
      'areaAr': 'العدالة',
      'street': 'Street 9, House 4',
      'streetAr': 'شارع 9، دار 4',
      'landmark': 'Near the Kufa University gate',
      'landmarkAr': 'قرب باب جامعة الكوفة',
    },
    {
      'name': 'Omar Farouk',
      'nameAr': 'عمر فاروق',
      'phone': '+9647705550243',
      'displayPhone': '+964 770 555 0243',
      'governorate': 'NINEVEH',
      'area': 'Al-Muthanna',
      'areaAr': 'المثنى',
      'street': 'Street 3, House 18',
      'streetAr': 'شارع 3، دار 18',
      'landmark': 'Opposite the Al-Muthanna school',
      'landmarkAr': 'مقابل مدرسة المثنى',
    },
    {
      'name': 'Lana Aziz',
      'nameAr': 'لانا عزيز',
      'phone': '+9647505550256',
      'displayPhone': '+964 750 555 0256',
      'governorate': 'DUHOK',
      'area': 'Malta',
      'areaAr': 'مالطا',
      'street': 'Street 11, House 6',
      'streetAr': 'شارع 11، دار 6',
      'landmark': 'Next to Duhok Gate',
      'landmarkAr': 'بجانب بوابة دهوك',
    },
    {
      'name': 'Mariam Saleh',
      'nameAr': 'مريم صالح',
      'phone': '+9647705550262',
      'displayPhone': '+964 770 555 0262',
      'governorate': 'KIRKUK',
      'area': 'Rahimawa',
      'areaAr': 'رحيم آوه',
      'street': 'Street 21, House 9',
      'streetAr': 'شارع 21، دار 9',
      'landmark': 'Near the Rahimawa bakery',
      'landmarkAr': 'قرب مخبز رحيم آوه',
    },
    {
      'name': 'Hussein Karim',
      'nameAr': 'حسين كريم',
      'phone': '+9647805550278',
      'displayPhone': '+964 780 555 0278',
      'governorate': 'BABYLON',
      'area': 'Al-Jamiaa',
      'areaAr': 'الجامعة',
      'street': 'Street 7, House 25',
      'streetAr': 'شارع 7، دار 25',
      'landmark': 'Behind the Hillah courthouse',
      'landmarkAr': 'خلف محكمة الحلة',
    },
    {
      'name': 'Dilshad Omer',
      'nameAr': 'دلشاد عمر',
      'phone': '+9647505550283',
      'displayPhone': '+964 750 555 0283',
      'governorate': 'ERBIL',
      'area': 'Italian Village',
      'areaAr': 'القرية الإيطالية',
      'street': 'Villa 44',
      'streetAr': 'فيلا 44',
      'landmark': 'Near the village gate',
      'landmarkAr': 'قرب بوابة القرية',
    },
  ];

  /// [store]'s delivered orders from the first of the month three months
  /// back until yesterday, newest first, so "What you owe Saba" has past
  /// months. The app had only today's orders, so the store saw "No past
  /// months yet" while the admin web billed it for three.
  List<Map<String, dynamic>> _historyOf(String store) => [
    for (final part in _history().reversed)
      if (part['merchantId'] == store) part,
  ];

  /// Every demo store's history, oldest first.
  ///
  /// The same fixed arithmetic as the admin web's historyOrders
  /// (website/src/data/orders.ts), numbered across all eight demo stores in
  /// the order they were placed, so an order and a month's bill read the
  /// same on both. Only what was on sale when the demo opened: a product
  /// waiting for approval, a draft or a hidden one was never bought.
  List<Map<String, dynamic>> _history() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final made = <({int n, DateTime placedAt, Map<String, dynamic> part})>[];
    var n = 0;
    // Each store's own count of orders, to walk its whole shelf.
    final sold = List.filled(8, 0);
    for (var back = 3; back >= 0; back--) {
      for (var s = 0; s < 8; s++) {
        final storeId = 'm-${s + 1}';
        final shelf = [
          for (final product in MockData.products)
            if ((product['merchant'] as Map)['id'] == storeId &&
                MockData.startsOnSale(product['id']))
              product,
        ];
        final reachable = [
          for (final customer in _historyCustomers)
            if (_deliveryTerms(storeId, customer['governorate']) != null)
              customer,
        ];
        for (var k = 0; k < 2 + (s + back) % 3; k++, n++) {
          final deliveredAt = DateTime(
            now.year,
            now.month - back,
            3 + k * 8 + s % 4,
            11 + n % 7,
          );
          if (!deliveredAt.isBefore(today)) continue;
          final nth = sold[s]++;
          final placedAt = deliveredAt.subtract(Duration(days: 1 + n % 3));
          final customer = reachable[n % reachable.length];
          final items = <Map<String, dynamic>>[];
          for (var line = 0; line < 1 + n % 2; line++) {
            final product = shelf[(nth + line) % shelf.length];
            items.add(<String, dynamic>{
              'id': 'hi-$n-$line',
              'productId': product['id'],
              'name': product['name'],
              'nameAr': ?product['nameAr'],
              'imageUrl': product['imageUrl'],
              'sku': product['sku'],
              'quantity': line == 0 && n % 3 == 0 ? 2 : 1,
              'price': (product['price'] as num).toDouble(),
            });
          }
          made.add((
            n: n,
            placedAt: placedAt,
            part: _seededPart(
              store: storeId,
              id: '',
              orderNumber: '',
              placedAt: placedAt,
              status: 'DELIVERED',
              deliveredAt: deliveredAt,
              items: items,
              customer: customer,
              city: customer['governorate']!,
              withDriver: true,
            ),
          ));
        }
      }
    }
    // Numbered by when they were placed; a tie keeps the web's order.
    made.sort((a, b) {
      final byTime = a.placedAt.compareTo(b.placedAt);
      return byTime != 0 ? byTime : a.n.compareTo(b.n);
    });
    return [
      for (final (index, order) in made.indexed)
        <String, dynamic>{
          ...order.part,
          'id': 'ho-${index + 1}',
          'orderNumber': 'SB-${190001 + index}',
        },
    ];
  }

  static const List<String> _returnReasons = [
    'DAMAGED',
    'WRONG_ITEM',
    'NOT_AS_DESCRIBED',
    'MISSING_PARTS',
    'CHANGED_MIND',
    'OTHER',
  ];

  /// The returns [store]'s history ended in, newest first: the refunded
  /// ones, which take their cash off its bill.
  ///
  /// The admin web's seedReturns (website/src/data/returns.ts): every ninth
  /// delivered order, from the fifth, is returned; asked for two days after
  /// delivery and refunded three days after that, one of its first item.
  /// The fourth is declined. The newest are still being answered there;
  /// only the refunded ones are here, as they are the ones a bill counts.
  /// Today's orders sort after every history order old enough to be
  /// refunded, so leaving them out moves none of these.
  List<Map<String, dynamic>> _historyReturnsOf(String store) {
    final now = DateTime.now();
    DateTime at(Map<String, dynamic> part, String key) =>
        DateTime.parse('${part[key]}');
    // By delivery; a tie is broken as the web lists orders: newest placed
    // first, then by number.
    final delivered = [..._history().indexed]
      ..sort((a, b) {
        final byDelivery = at(
          a.$2,
          'deliveredAt',
        ).compareTo(at(b.$2, 'deliveredAt'));
        if (byDelivery != 0) return byDelivery;
        final byPlaced = at(b.$2, 'placedAt').compareTo(at(a.$2, 'placedAt'));
        return byPlaced != 0 ? byPlaced : a.$1.compareTo(b.$1);
      });
    final returns = <Map<String, dynamic>>[];
    for (var d = 4, i = 0; d < delivered.length; d += 9, i++) {
      final order = delivered[d].$2;
      final asked = at(order, 'deliveredAt').add(const Duration(days: 2));
      final refunded = asked.add(const Duration(days: 3));
      if (i == 3 || refunded.isAfter(now) || order['merchantId'] != store) {
        continue;
      }
      final line = (order['items'] as List).first as Map<String, dynamic>;
      final amount = line['price'] as num;
      returns.insert(0, <String, dynamic>{
        'id': 'seed-ret-${i + 1}',
        'orderId': order['id'],
        'orderNumber': order['orderNumber'],
        'status': 'REFUNDED',
        'requestedAt': asked.toIso8601String(),
        'reason': _returnReasons[i % _returnReasons.length],
        'merchantId': store,
        'merchantName': _storeFace(store)['title'],
        'customerName': order['customerName'],
        'customerNameAr': order['customerNameAr'],
        'items': [
          <String, dynamic>{
            'orderItemId': line['id'],
            'productId': line['productId'],
            'name': line['name'],
            'nameAr': ?line['nameAr'],
            'quantity': 1,
            'imageUrl': line['imageUrl'],
            'refundAmount': amount,
          },
        ],
        'itemCount': 1,
        'currencyCode': MockData.currency,
        'refundAmount': amount,
        'previewImageUrl': line['imageUrl'],
        'refund': <String, dynamic>{
          'amount': amount,
          'currencyCode': MockData.currency,
          'status': 'COMPLETED',
          'method': 'Cash, from the store',
          'methodAr': 'نقداً، يعيده لك المتجر',
          'completedAt': refunded.toIso8601String(),
        },
        'timeline': <Map<String, dynamic>>[
          <String, dynamic>{
            'status': 'REQUESTED',
            'occurredAt': asked.toIso8601String(),
            'noteCode': 'RETURN_REQUESTED',
          },
          <String, dynamic>{
            'status': 'APPROVED',
            'occurredAt': asked.add(const Duration(days: 1)).toIso8601String(),
          },
          <String, dynamic>{
            'status': 'REFUNDED',
            'occurredAt': refunded.toIso8601String(),
          },
        ],
        'photos': <String>[],
      });
    }
    return returns;
  }

  /// One period's delivered sales, from its start to now, and the same
  /// stretch of the period before (this month so far against last month's
  /// first as many days). The dashboard and Analytics both read this.
  ({DateTime from, _Sold sold, _Sold before}) _periodSales(String period) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final (from, previous) = switch (period.toLowerCase()) {
      'week' => (
        today.subtract(const Duration(days: 6)),
        today.subtract(const Duration(days: 13)),
      ),
      'year' => (DateTime(now.year), DateTime(now.year - 1)),
      _ => (DateTime(now.year, now.month), DateTime(now.year, now.month - 1)),
    };
    return (
      from: from,
      sold: _sales(from, now),
      before: _sales(previous, previous.add(now.difference(from))),
    );
  }

  /// Analytics for one period.
  ///
  /// The screen sends `?period=week|month|year` and this ignored it, so all
  /// three tabs showed the same revenue over the same six bars — the same
  /// fault as the order filter that was sent and dropped, on a second screen.
  /// A merchant comparing this week against this year saw one number twice.
  ///
  /// The shape is also fixed per period rather than random per request: the
  /// figures were re-rolled on every call, so pulling to refresh, or leaving
  /// a tab and coming back, redrew a different chart for the same week.
  Map<String, dynamic> _merchantAnalytics(String period) {
    // A new store: nothing sold in any period, and no earlier period at all.
    if (_isNewStore) {
      return <String, dynamic>{
        'currencyCode': MockData.currency,
        'revenue': 0,
        'orderCount': 0,
        'productsSold': 0,
        'averageOrderValue': 0,
        'refundTotal': 0,
        'cancellationCount': 0,
        'series': const <Map<String, dynamic>>[],
        'topProducts': const <Map<String, dynamic>>[],
      };
    }

    // This week by day, this month by week, this year by month; each against
    // the same stretch just before it.
    final now = DateTime.now();
    final (:from, :sold, :before) = _periodSales(period);
    final (points, prefix, step) = switch (period.toLowerCase()) {
      'week' => (7, 'D', 'day'),
      'year' => (now.month, 'M', 'month'),
      _ => ((now.day + 6) ~/ 7, 'W', 'week'),
    };
    DateTime edge(int index) => switch (step) {
      'day' => from.add(Duration(days: index)),
      'month' => DateTime(from.year, from.month + index),
      _ => from.add(Duration(days: 7 * index)),
    };
    final cancelled = _merchantOrderStore.where((part) {
      final at = DateTime.tryParse('${part['placedAt']}');
      return _isOff(part['status']) && at != null && !at.isBefore(from);
    }).length;

    final quantities = <String, int>{};
    for (final part in sold.parts) {
      for (final item in part['items'] as List) {
        quantities.update(
          '${(item as Map)['productId']}',
          (count) => count + (item['quantity'] as int),
          ifAbsent: () => item['quantity'] as int,
        );
      }
    }
    final rows = {for (final row in _merchantProducts(null)) row['id']: row};
    final best = quantities.keys.where(rows.containsKey).toList()
      ..sort((a, b) => quantities[b]!.compareTo(quantities[a]!));

    return <String, dynamic>{
      'currencyCode': MockData.currency,
      'revenue': sold.goods,
      if (before.parts.isNotEmpty) 'previousRevenue': before.goods,
      'orderCount': sold.parts.length,
      'productsSold': quantities.values.fold<int>(0, (a, b) => a + b),
      'averageOrderValue': sold.parts.isEmpty
          ? 0
          : sold.goods / sold.parts.length,
      'refundTotal': sold.returned,
      'cancellationCount': cancelled,
      'series': [
        for (var index = 0; index < points; index++)
          <String, dynamic>{
            'label': '$prefix${index + 1}',
            'from': edge(index).toIso8601String(),
            'unit': step.toUpperCase(),
            'value': _sales(edge(index), edge(index + 1)).goods,
          },
      ],
      'topProducts': [for (final id in best.take(5)) rows[id]],
    };
  }

  /// Saba's one rate, in percent, on every store's delivered sales.
  static const int _commissionPercent = 8;

  /// Stores their owners have closed for now. They take no orders.
  final Set<String> _closedStores = <String>{};

  /// Stores whose owners asked for the account to be deleted, and when.
  final Map<String, String> _storeDeletions = <String, String>{};

  /// Demo products as they were before their store edited them, to put back
  /// on reset.
  final Map<String, Map<String, dynamic>> _fixtureOriginals =
      <String, Map<String, dynamic>>{};

  /// Brands a store typed that were not on the list: they wait for Saba's
  /// check, so the shop's list leaves them out and the store's own has them.
  final List<Map<String, dynamic>> _addedBrands = <Map<String, dynamic>>[];

  /// Categories Saba hid on the admin's categories page. The demo has no
  /// admin, so only tests hide one.
  @visibleForTesting
  final Set<String> hiddenCategories = <String>{};

  /// What this store delivered between [from] and [to], its goods after its
  /// own coupons, and the cash it gave back on returns in that time. The
  /// delivery fee is the store's, for its own driver, so it is not a sale.
  _Sold _sales(DateTime from, DateTime to) {
    bool within(Object? at) {
      final time = DateTime.tryParse('$at');
      return time != null && !time.isBefore(from) && time.isBefore(to);
    }

    final parts = [
      for (final part in _merchantOrderStore)
        if (part['status'] == 'DELIVERED' && within(part['deliveredAt'])) part,
    ];
    return (
      parts: parts,
      goods: parts.fold<num>(
        0,
        (sum, part) =>
            sum +
            ((part['subtotal'] as num?) ?? 0) -
            ((part['discount'] as num?) ?? 0),
      ),
      returned: [
        for (final request in _storeReturns[_shelfStore] ?? const [])
          if (request['status'] == 'REFUNDED' &&
              within((request['refund'] as Map)['completedAt']))
            request['refundAmount'] as num,
      ].fold<num>(0, (sum, amount) => sum + amount),
    );
  }

  /// One month's bill: 8% of what was delivered, less what was handed back,
  /// to the nearest 250 IQD.
  Map<String, dynamic> _bill(DateTime month, {required bool isOpen}) {
    final sold = _sales(month, DateTime(month.year, month.month + 1));
    final base = sold.goods - sold.returned;
    final owed = base <= 0
        ? 0
        : (base * _commissionPercent / 100 / 250).round() * 250;
    return <String, dynamic>{
      'month': month.toIso8601String(),
      'orderCount': sold.parts.length,
      'sales': sold.goods,
      'returned': sold.returned,
      'owed': owed,
      // ponytail: every past month stays due; Saba marks one paid from the
      // web admin, which comes after the app.
      'status': isOpen ? 'OPEN' : 'DUE',
    };
  }

  /// What the store owes Saba: this month so far, and each month before it
  /// that had a delivery or a refund (API_CONTRACT.md 6.6). A month with
  /// only a refund stays, so the refund is still taken off. Nothing here is
  /// older than the store's approval: it sold nothing before it.
  Map<String, dynamic> _sabaBills() {
    final now = DateTime.now();
    final month = DateTime(now.year, now.month);
    final earlier = <DateTime>{
      for (final when in [
        for (final part in _merchantOrderStore)
          if (part['status'] == 'DELIVERED') part['deliveredAt'],
        for (final request in _storeReturns[_shelfStore] ?? const [])
          if (request['status'] == 'REFUNDED')
            (request['refund'] as Map)['completedAt'],
      ])
        if (DateTime.tryParse('$when') case final at?)
          if (at.isBefore(month)) DateTime(at.year, at.month),
    }.toList()..sort((a, b) => b.compareTo(a));
    return <String, dynamic>{
      'currencyCode': MockData.currency,
      'ratePercent': _commissionPercent,
      'current': _bill(month, isOpen: true),
      'past': [for (final past in earlier) _bill(past, isOpen: false)],
    };
  }

  /// How many of [productId] (in [variant], when it has options) the store's
  /// open orders hold, and how many it has delivered.
  ({int reserved, int sold}) _moved(Object? productId, [String? variant]) {
    var reserved = 0;
    var sold = 0;
    for (final part in _merchantOrderStore) {
      if (_isOff(part['status'])) continue;
      for (final item in part['items'] as List) {
        if ((item as Map)['productId'] != productId) continue;
        if (variant != null && item['variantLabel'] != variant) continue;
        final quantity = item['quantity'] as int;
        if (part['status'] == 'DELIVERED') {
          sold += quantity;
        } else {
          reserved += quantity;
        }
      }
    }
    return (reserved: reserved, sold: sold);
  }

  // ---------------------------------------------------------- notifications ---

  _Reply _notifications(
    String method,
    List<String> path,
    RequestOptions options,
  ) {
    final sub = path.length > 1 ? path[1] : '';

    // Read is remembered, per account. It was not: "Mark all as read"
    // cleared the dots until the list was fetched again, and back they came.
    String key(String id) => '$_email/$id';
    final mine = <Map<String, dynamic>>[
      for (final event in _events)
        if (event['to'] == _inbox) event,
    ];
    if (sub == 'read-all') {
      _readNotifications.addAll([for (var i = 1; i <= 10; i++) key('n-$i')]);
      _readNotifications.addAll([
        for (final event in mine) key('${event['id']}'),
      ]);
      return const _Reply(<String, dynamic>{});
    }
    if (sub.isNotEmpty && sub != 'unread-count' && method != 'GET') {
      _readNotifications.add(key(sub));
      return const _Reply(<String, dynamic>{});
    }

    // A new account has been sent nothing yet - not the demo customer's
    // "Your order is confirmed", and no lit dot on the bell.
    if (sub == 'unread-count') {
      return _Reply(<String, dynamic>{
        'count':
            mine
                .where(
                  (event) =>
                      !_readNotifications.contains(key('${event['id']}')),
                )
                .length +
            (_isNewAccount
                ? 0
                : [
                    for (var i = 1; i <= 3; i++)
                      if (!_readNotifications.contains(key('n-$i'))) i,
                  ].length),
      });
    }
    if (method != 'GET') return const _Reply(<String, dynamic>{});

    // What the other side did, first: a store's step, a shopper's order.
    final happened = <Map<String, dynamic>>[
      for (final event in mine)
        <String, dynamic>{
          'id': event['id'],
          'title':
              ((_arabic ? event['ar'] : event['en']) as (String, String)).$1,
          'body':
              ((_arabic ? event['ar'] : event['en']) as (String, String)).$2,
          'type': event['type'],
          'entityType':
              event['targetType'] ??
              (event['orderId'] == null ? null : 'ORDER'),
          'entityId': event['targetId'] ?? event['orderId'],
          'createdAt': event['createdAt'],
          'isRead': _readNotifications.contains(key('${event['id']}')),
        },
    ];
    if (_isNewAccount) return _page(happened, options);

    // What each side is actually sent. A store's inbox used to carry the
    // shopper's seeded ones - "Your order is confirmed", "Your parcel has
    // shipped", "Welcome to Saba, pay in cash" - which a shop owner reading
    // their own notifications could make no sense of at all.
    final types = _isStore
        ? const <String>['ORDER', 'PRODUCT_APPROVAL', 'MESSAGE', 'PAYMENT']
        // No seeded "Your order is confirmed" or "Your parcel has shipped"
        // for a shopper: she had no such order (BUGS.md 41). What happens
        // to her real orders reaches her above, as it happens.
        : const <String>['PROMOTION', 'PRICE_DROP', 'MESSAGE', 'SECURITY'];
    final seeded = types.length;

    final items = <Map<String, dynamic>>[
      ...happened,
      for (var index = 0; index < seeded; index++)
        <String, dynamic>{
          'id': 'n-${index + 1}',
          // Words a customer would be sent, in their language. Every one
          // used to read "Demo notification while the backend is being
          // built", on the customer's own screen.
          'title': _notificationWords(types[index % types.length]).$1,
          'body': _notificationWords(types[index % types.length]).$2,
          'type': types[index % types.length],
          // Some notifications lead somewhere and some are announcements,
          // and the demo had none of the first kind — so the inbox could
          // never show what tapping one does. A promotion and a sign-in
          // notice keep no target on purpose: they are messages, not doors.
          'entityType': switch (types[index % types.length]) {
            'ORDER' || 'SHIPPING' =>
              _isStore
                  ? (_merchantOrderStore.isEmpty ? null : 'ORDER')
                  : (_orders.isEmpty ? null : 'ORDER'),
            'PRICE_DROP' || 'PRODUCT_APPROVAL' => 'PRODUCT',
            'MESSAGE' => 'CONVERSATION',
            _ => null,
          },
          'entityId': switch (types[index % types.length]) {
            'ORDER' || 'SHIPPING' => _firstOrderId(),
            'PRICE_DROP' || 'PRODUCT_APPROVAL' => 'p-1',
            'MESSAGE' => _demoChatId(),
            _ => null,
          },
          'createdAt': _cannedAt
              .subtract(Duration(hours: index * 5))
              .toIso8601String(),
          'isRead':
              index > 2 || _readNotifications.contains(key('n-${index + 1}')),
        },
    ];

    return _page(items, options);
  }

  /// The order a seeded notification points at: this store's newest, or
  /// this shopper's.
  Object? _firstOrderId() {
    final orders = _isStore ? _merchantOrderStore : _orders;
    return orders.isEmpty ? null : orders.first['id'];
  }

  /// Whether the signed-in account runs a store.
  bool get _isStore => _currentUser()['role'] == 'MERCHANT';

  (String, String) _notificationWords(String type) => switch (type) {
    // The same code says different things to the two sides: a shopper is
    // told their order was confirmed, a store that one arrived.
    'ORDER' when _isStore =>
      _arabic
          ? ('طلب جديد', 'وصلك طلب جديد. أكّده لتبدأ بتجهيزه.')
          : (
              'A new order',
              'A customer ordered from you. Confirm it to start.',
            ),
    'PRODUCT_APPROVAL' =>
      _arabic
          ? ('تمت الموافقة على منتجك', 'يستطيع المتسوقون إيجاده الآن.')
          : ('Your product is approved', 'Shoppers can find it now.'),
    'PAYMENT' when _isStore =>
      _arabic
          ? ('فاتورة هذا الشهر', 'اطّلع على ما تدين به لسبأ من حسابك.')
          : ("This month's bill", 'See what you owe Saba from your account.'),
    'ORDER' =>
      _arabic
          ? ('تم تأكيد طلبك', 'يجهّز المتجر طلبك الآن.')
          : ('Your order is confirmed', 'The store is getting it ready.'),
    'PROMOTION' =>
      _arabic
          ? (
              'أهلاً بك في سبأ',
              'ادفع نقداً عند وصول طلبك. كل متجر يوصل طلباته بنفسه.',
            )
          : (
              'Welcome to Saba',
              'Pay in cash when your order arrives. Each store delivers its own.',
            ),
    'SHIPPING' =>
      _arabic
          ? ('تم شحن طردك', 'سيصلك خلال 2 إلى 3 أيام.')
          : ('Your parcel has shipped', 'It should reach you in 2 to 3 days.'),
    'PRICE_DROP' =>
      _arabic
          ? ('انخفض سعر منتج محفوظ', 'أصبح سعر منتج في قائمة أمنياتك أقل.')
          : (
              'A saved item dropped in price',
              'Something on your wishlist costs less now.',
            ),
    // A store is written to by its customers: Nova's own list said "Nova
    // Electronics answered you" (the tester). Sara is the demo store's
    // customer still waiting for an answer.
    'MESSAGE' when _isStore =>
      _arabic
          ? ('رسالة جديدة من زبون', 'سألتك سارة أحمد عن طلبها.')
          : (
              'New message from a customer',
              'Sara Ahmed asked about her order.',
            ),
    'MESSAGE' =>
      _arabic
          ? ('رسالة جديدة من متجر', 'ردّ متجر نوفا للإلكترونيات على سؤالك.')
          : ('New message from a store', 'Nova Electronics answered you.'),
    _ =>
      _arabic
          ? (
              'تسجيل دخول جديد إلى حسابك',
              'كروم على ويندوز، بغداد. لست أنت؟ راجع جلساتك.',
            )
          : (
              'New sign-in to your account',
              'Chrome on Windows, Baghdad. Not you? Check your sessions.',
            ),
  };

  // -------------------------------------------------------------- messaging ---

  _Reply _messages(String method, List<String> path, RequestOptions options) {
    // /messages/conversations[/:id[/messages|read]]
    _seedChats();
    final conversationId = path.length > 2 ? path[2] : null;
    final sub = path.length > 3 ? path[3] : '';
    final myStore = _myStoreId;

    if (conversationId == null) {
      if (method == 'POST') {
        // "Message the store": the chat already there, or a new empty one.
        final merchantId = _body(options)['merchantId']?.toString() ?? '';
        if (merchantId.isEmpty) {
          return _Reply(<String, dynamic>{
            'message': _arabic
                ? 'اختر متجرًا لمراسلته.'
                : 'Choose a store to message.',
          }, statusCode: 422);
        }
        return _Reply(_chatCard(_chatWith(merchantId)));
      }
      // A store's owner reads the store's inbox; anyone else, their own
      // chats. A chat opened and never written in is not listed.
      final cards = <Map<String, dynamic>>[
        for (final chat in _chats.values)
          if (chat.messages.isNotEmpty &&
              (myStore != null
                  ? chat.merchantId == myStore
                  : chat.customerEmail == _email))
            _chatCard(chat),
      ]..sort((a, b) => '${b['updatedAt']}'.compareTo('${a['updatedAt']}'));
      return _Reply(cards);
    }

    final chat = _chats[conversationId];
    if (chat == null ||
        (chat.customerEmail != _email && chat.merchantId != myStore)) {
      return const _Reply(<String, dynamic>{}, statusCode: 404);
    }
    final asStore = chat.merchantId == myStore;

    if (sub == 'read') {
      if (asStore) {
        chat.storeRead = chat.messages.length;
      } else {
        chat.customerRead = chat.messages.length;
      }
      return const _Reply(<String, dynamic>{});
    }
    if (sub.isEmpty) return _Reply(_chatCard(chat));

    // Each side lifts only its own block; the chat stays readable.
    if (sub == 'block') {
      if (asStore) {
        chat.storeBlocked = method == 'POST';
      } else {
        chat.customerBlocked = method == 'POST';
      }
      return _Reply(_chatCard(chat));
    }

    if (method == 'POST' && (chat.customerBlocked || chat.storeBlocked)) {
      return _Reply(<String, dynamic>{
        'message': _arabic
            ? 'الرسائل متوقفة في هذه المحادثة لأنها محظورة.'
            : "Messages are off in this chat: it's blocked.",
      }, statusCode: 409);
    }

    // A photo: the app sends the picture itself as a data URL (the demo has
    // no file server), and it rides in the thread like any other message.
    final isPhoto = sub == 'photos';
    if (method == 'POST') {
      final message = <String, dynamic>{
        'id': _nextId('msg'),
        'body': isPhoto ? '' : _body(options)['body'],
        'photoUrl': isPhoto ? _body(options)['photoDataUrl'] : null,
        'from': asStore ? 'STORE' : 'CUSTOMER',
        'sentAt': DateTime.now().toIso8601String(),
      };
      chat.messages.add(message);
      // What you wrote, you have read.
      if (asStore) {
        chat.storeRead = chat.messages.length;
      } else {
        chat.customerRead = chat.messages.length;
      }
      _toldOfMessage(
        chat,
        '${message['body'] ?? ''}',
        fromStore: asStore,
        isPhoto: isPhoto,
      );
      return _Reply(_messageFor(chat, message, asStore: asStore));
    }

    // Newest first, matching the contract the controller reverses.
    return _page(<Map<String, dynamic>>[
      for (final message in chat.messages.reversed)
        _messageFor(chat, message, asStore: asStore),
    ], options);
  }

  /// A product, a store or a chat reported to Saba (Apple 1.2), as the
  /// server takes it: only what the reporter can see, never their own, for
  /// one of the review report's reasons. Saba's side is the admin web's.
  _Reply _report(Map<String, dynamic> body) {
    const reasons = {
      'COUNTERFEIT',
      'PROHIBITED',
      'MISLEADING',
      'OFFENSIVE',
      'SPAM',
      'OTHER',
    };
    if (!reasons.contains(body['reason'])) {
      return _Reply(<String, dynamic>{
        'message': _arabic ? 'اختر سببًا.' : 'Choose a reason.',
      }, statusCode: 422);
    }
    final id = '${body['targetId']}';
    final mine = _myStoreId;
    final seen = switch (body['targetType']) {
      'PRODUCT' => switch (_findProduct(id)) {
        final product? =>
          _isListed(product) &&
              '${(product['merchant'] as Map?)?['id'] ?? product['merchantId']}' !=
                  mine,
        null => false,
      },
      'STORE' => id != mine && MockData.merchants.any((m) => m['id'] == id),
      'CONVERSATION' => switch (_chats[id]) {
        final chat? => chat.customerEmail == _email || chat.merchantId == mine,
        null => false,
      },
      _ => false,
    };
    if (!seen) return const _Reply(<String, dynamic>{}, statusCode: 404);
    return const _Reply(<String, dynamic>{});
  }

  /// The other side of [chat] is told of a message: only the chat's own dot
  /// changed, so a store missed a shopper's message unless it happened to
  /// open its chats (the user). Support's chats have no store to tell.
  void _toldOfMessage(
    _Chat chat,
    String body, {
    required bool fromStore,
    bool isPhoto = false,
  }) {
    // A photo's notification reads "Sent a photo", not its (empty) words.
    final text = isPhoto
        ? (_arabic ? 'أرسل صورة' : 'Sent a photo')
        : (body.length <= 80 ? body : '${body.substring(0, 79)}…');
    if (fromStore) {
      final store = '${_storeFace(chat.merchantId)['title']}';
      _notify(
        chat.customerEmail,
        'MESSAGE',
        en: ('Message from $store', text),
        ar: ('رسالة من $store', text),
        target: ('CONVERSATION', chat.id),
      );
    } else if (chat.merchantId != 'support') {
      _notify(
        'store:${chat.merchantId}',
        'MESSAGE',
        en: ('Message from ${chat.customerName}', text),
        ar: ('رسالة من ${chat.customerName}', text),
        target: ('CONVERSATION', chat.id),
      );
    }
  }

  /// The signed-in store owner's store, or null for anyone else.
  String? get _myStoreId {
    final user = _currentUser();
    if (user['role'] != 'MERCHANT') return null;
    return (user['merchant'] as Map<String, dynamic>?)?['id'] as String?;
  }

  static String _chatId(String merchantId, String email) =>
      'conv-$merchantId-'
      '${email.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '')}';

  /// The signed-in customer's chat with a store, started if not there yet.
  _Chat _chatWith(String merchantId) {
    final id = _chatId(merchantId, _email);
    return _chats.putIfAbsent(
      id,
      () => _Chat(
        id: id,
        customerEmail: _email,
        customerName: '${_currentUser()['fullName'] ?? 'Customer'}',
        merchantId: merchantId,
      ),
    );
  }

  /// Where the demo's "New message from a store" notification leads.
  String _demoChatId() {
    final store = _myStoreId;
    return store == null
        ? _chatId('m-1', _email)
        : _chatId(store, 'sara@saba.app');
  }

  /// The store's name and logo as a customer sees them.
  static Map<String, dynamic> _storeFace(String merchantId) {
    if (merchantId == 'support') {
      return const <String, dynamic>{
        'title': 'Saba Support',
        'titleAr': 'دعم سبأ',
      };
    }
    for (final merchant in MockData.merchants) {
      if (merchant['id'] == merchantId) {
        return <String, dynamic>{
          'title': merchant['storeName'],
          'avatarUrl': merchant['logoUrl'],
        };
      }
    }
    return const <String, dynamic>{'title': 'Store', 'titleAr': 'متجر'};
  }

  /// A chat as the one reading it sees it: the other side's name, and what
  /// the other side wrote that this side has not read yet.
  Map<String, dynamic> _chatCard(_Chat chat) {
    final asStore = chat.merchantId == _myStoreId;
    final last = chat.messages.isEmpty ? null : chat.messages.last;
    final theirs = asStore ? 'CUSTOMER' : 'STORE';
    return <String, dynamic>{
      'id': chat.id,
      ...asStore
          ? <String, dynamic>{'title': chat.customerName}
          : _storeFace(chat.merchantId),
      // A photo has no words: the row shows "Photo" in the message's place.
      'lastMessage': last?['photoUrl'] != null ? null : last?['body'],
      'lastMessageIsPhoto': last?['photoUrl'] != null,
      'updatedAt': last?['sentAt'] ?? DateTime.now().toIso8601String(),
      'unreadCount': chat.messages
          .skip(asStore ? chat.storeRead : chat.customerRead)
          .where((message) => message['from'] == theirs)
          .length,
      'blocked': chat.customerBlocked || chat.storeBlocked,
      'blockedByMe': asStore ? chat.storeBlocked : chat.customerBlocked,
    };
  }

  Map<String, dynamic> _messageFor(
    _Chat chat,
    Map<String, dynamic> message, {
    required bool asStore,
  }) {
    final fromStore = message['from'] == 'STORE';
    return <String, dynamic>{
      'id': message['id'],
      'body': message['body'] ?? '',
      'sentAt': message['sentAt'],
      'isMine': fromStore == asStore,
      'senderName': fromStore
          ? _storeFace(chat.merchantId)['title']
          : chat.customerName,
      // A photo: the data URL the demo kept, since it has no file server.
      'photoUrl': ?message['photoUrl'],
    };
  }

  /// The demo's chats, written the first time an account that is not new
  /// looks: the demo customer has asked every store something and been
  /// answered, and the demo store has two customers, one still waiting.
  /// A new account or a new store starts with none.
  void _seedChats() {
    if (_isNewAccount || !_seededChats.add(_email)) return;
    final now = DateTime.now();
    String ago(int hours) =>
        now.subtract(Duration(hours: hours)).toIso8601String();

    final store = _myStoreId;
    if (store == null) {
      // Each its own question: the same two lines under every store made
      // the list read as one chat three times.
      for (final (merchantId, question, answer, hours)
          in <(String, String, String, int)>[
            (
              'm-1',
              'Hello, when will my order ship?',
              'It ships tomorrow morning. Our driver calls before coming.',
              5,
            ),
            (
              'm-2',
              'Can I change the delivery address on my order?',
              'Yes, send us the new address and we will change it before '
                  'it ships.',
              28,
            ),
            (
              'support',
              'How do I return an item?',
              'Open the order and tap Request a return. We will guide you '
                  'from there.',
              75,
            ),
          ]) {
        final chat = _chatWith(merchantId);
        if (chat.messages.isNotEmpty) continue;
        chat.messages.addAll(<Map<String, dynamic>>[
          <String, dynamic>{
            'id': _nextId('msg'),
            'body': question,
            'from': 'CUSTOMER',
            'sentAt': ago(hours),
          },
          <String, dynamic>{
            'id': _nextId('msg'),
            'body': answer,
            'from': 'STORE',
            'sentAt': ago(hours - 1),
          },
        ]);
        chat
          ..storeRead = 2
          // One answer from the first store is still unread.
          ..customerRead = merchantId == 'm-1' ? 1 : 2;
      }
      return;
    }

    for (final (email, name, question, answer, hours)
        in <(String, String, String, String?, int)>[
          (
            'sara@saba.app',
            'Sara Ahmed',
            'Is this phone in stock in blue?',
            null,
            1,
          ),
          (
            'ali@saba.app',
            'Ali Hassan',
            'Do you deliver to Erbil?',
            'Yes, in 3 to 4 days.',
            20,
          ),
        ]) {
      final chat = _chats.putIfAbsent(
        _chatId(store, email),
        () => _Chat(
          id: _chatId(store, email),
          customerEmail: email,
          customerName: name,
          merchantId: store,
        ),
      );
      if (chat.messages.isNotEmpty) continue;
      chat.messages.add(<String, dynamic>{
        'id': _nextId('msg'),
        'body': question,
        'from': 'CUSTOMER',
        'sentAt': ago(hours),
      });
      if (answer != null) {
        chat.messages.add(<String, dynamic>{
          'id': _nextId('msg'),
          'body': answer,
          'from': 'STORE',
          'sentAt': ago(hours - 1),
        });
      }
      chat
        ..customerRead = chat.messages.length
        ..storeRead = answer == null ? 0 : chat.messages.length;
    }
  }

  // ---------------------------------------------------------------- support ---

  /// Who opens a ticket: a shopper, or a store by its name (API_CONTRACT.md
  /// 3.8, BUGS 105). A real server takes it from the session.
  Map<String, dynamic> _openedBy() {
    final user = _currentUser();
    final store = _myStoreId;
    return <String, dynamic>{
      'kind': store == null ? 'SHOPPER' : 'STORE',
      'name': store == null
          ? user['fullName']
          : (user['merchant'] as Map)['storeName'],
      'phone': user['phone'],
      'storeId': ?store,
    };
  }

  _Reply _support(String method, List<String> path, RequestOptions options) {
    final ticketId = path.length > 2 ? path[2] : null;
    final sub = path.length > 3 ? path[3] : '';

    if (ticketId == null) {
      if (method == 'POST') {
        final body = _body(options);
        final id = _nextId('tk');
        final ticket = <String, dynamic>{
          'id': id,
          'reference': 'T-${5000 + _counter}',
          'subject': body['subject'],
          'category': body['category'],
          'status': 'OPEN',
          'createdAt': DateTime.now().toIso8601String(),
          'lastMessage': body['description'],
          'openedBy': _openedBy(),
        };
        _tickets.insert(0, ticket);
        _ticketMessages[id] = <Map<String, dynamic>>[
          <String, dynamic>{
            'id': _nextId('tm'),
            'body': body['description'],
            'isFromCustomer': true,
            'sentAt': DateTime.now().toIso8601String(),
          },
        ];
        return _Reply(ticket);
      }
      return _Reply(_tickets);
    }

    if (sub == 'messages') {
      final thread = _ticketMessages.putIfAbsent(
        ticketId,
        () => <Map<String, dynamic>>[],
      );

      if (method == 'POST') {
        final ticket = _tickets.where((t) => t['id'] == ticketId).firstOrNull;
        // A closed ticket takes no replies; the customer's reply reopens a
        // waiting or resolved one (API_CONTRACT.md 3.8, 6.10).
        if (ticket?['status'] == 'CLOSED') {
          return const _Reply(<String, dynamic>{}, statusCode: 409);
        }
        final now = DateTime.now().toIso8601String();
        final message = <String, dynamic>{
          'id': _nextId('tm'),
          'body': _body(options)['body'],
          'isFromCustomer': true,
          'sentAt': now,
        };
        thread.add(message);
        if (ticket != null) {
          if (ticket['status'] == 'WAITING_FOR_CUSTOMER' ||
              ticket['status'] == 'RESOLVED') {
            ticket['status'] = 'OPEN';
          }
          ticket
            ..['updatedAt'] = now
            ..['lastMessage'] = message['body'];
        }
        return _Reply(message);
      }
      return _Reply(thread);
    }

    for (final ticket in _tickets) {
      if (ticket['id'] == ticketId) return _Reply(ticket);
    }
    return const _Reply(<String, dynamic>{});
  }

  // ------------------------------------------------------------------ media ---

  _Reply _media(String method, List<String> path, RequestOptions options) {
    if (method == 'DELETE') return const _Reply(<String, dynamic>{});

    final id = _nextId('media');

    // Echo back the kind the merchant actually uploaded. Answering IMAGE for
    // everything would make a picked video render as a broken photo, which is
    // a demo-mode artefact the real backend would never produce.
    final isVideo =
        _uploadedName(options).endsWith('.mp4') ||
        _uploadedName(options).endsWith('.mov') ||
        _uploadedName(options).endsWith('.webm') ||
        _uploadedName(options).endsWith('.m4v');

    if (isVideo) {
      return _Reply(<String, dynamic>{
        'id': id,
        'url': 'https://cdn.saba.test/demo/$id.mp4',
        'thumbnailUrl': 'https://picsum.photos/seed/$id/200/200',
        'kind': 'VIDEO',
      });
    }

    return _Reply(<String, dynamic>{
      'id': id,
      'url': 'https://picsum.photos/seed/$id/800/800',
      'thumbnailUrl': 'https://picsum.photos/seed/$id/200/200',
      'kind': 'IMAGE',
    });
  }

  /// Lowercased filename of the first uploaded part, or '' if there is none.
  String _uploadedName(RequestOptions options) {
    final data = options.data;
    if (data is! FormData || data.files.isEmpty) return '';
    return (data.files.first.value.filename ?? '').toLowerCase();
  }
}

/// What a store delivered in a stretch: the orders, their goods after the
/// store's own coupons, and the cash handed back on returns.
typedef _Sold = ({List<Map<String, dynamic>> parts, num goods, num returned});
