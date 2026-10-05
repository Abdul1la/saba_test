// GENERATED FILE - DO NOT EDIT BY HAND.
//
// Regenerate with: dart run tool/generate_localizations.dart
// Source of truth: strings_en.dart (keys) and strings_ar.dart (translations).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'strings_ar.dart';
import 'strings_en.dart';

/// Localized strings for the app.
///
/// No user-facing text is written inline in a widget; everything resolves
/// through here (specification section 60). A key missing from a translation
/// falls back to English rather than rendering a raw key.
class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ar'),
  ];

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations) ??
      const AppLocalizations(Locale('en'));

  /// Name of a locale, shown in the language picker in that language itself.
  static String displayName(Locale locale) => switch (locale.languageCode) {
        'ar' => 'العربية',
        _ => 'English',
      };

  Map<String, String> get _table => switch (locale.languageCode) {
        'ar' => stringsAr,
        _ => stringsEn,
      };

  bool get isRtl => locale.languageCode == 'ar';

  String _v(String key) => _table[key] ?? stringsEn[key] ?? key;

  String get appName => _v('appName');
  String get ok => _v('ok');
  String get cancel => _v('cancel');
  String get save => _v('save');
  String get delete => _v('delete');
  String get edit => _v('edit');
  String get remove => _v('remove');
  String get retry => _v('retry');
  String get close => _v('close');
  String get next => _v('next');
  String get back => _v('back');
  String get done => _v('done');
  String get confirm => _v('confirm');
  String get search => _v('search');
  String get apply => _v('apply');
  String get clear => _v('clear');
  String get clearAll => _v('clearAll');
  String get seeAll => _v('seeAll');
  String get loading => _v('loading');
  String get refresh => _v('refresh');
  String get share => _v('share');
  String get optional => _v('optional');
  String get required => _v('required');
  String get yes => _v('yes');
  String get no => _v('no');
  String get submit => _v('submit');
  String get skip => _v('skip');
  String get select => _v('select');
  String get total => _v('total');
  String get subtotal => _v('subtotal');
  String get decrease => _v('decrease');
  String get increase => _v('increase');
  String get quantity => _v('quantity');
  String get price => _v('price');
  String get status => _v('status');
  String get from => _v('from');
  String get to => _v('to');
  String get errorGeneric => _v('errorGeneric');
  String get errorNetwork => _v('errorNetwork');
  String get errorTimeout => _v('errorTimeout');
  String get errorServer => _v('errorServer');
  String get errorNotFound => _v('errorNotFound');
  String get errorUnauthorized => _v('errorUnauthorized');
  String get errorForbidden => _v('errorForbidden');
  String get errorValidation => _v('errorValidation');
  String get errorConflict => _v('errorConflict');
  String get errorPayment => _v('errorPayment');
  String get errorInventory => _v('errorInventory');
  String get errorParsing => _v('errorParsing');
  String get errorCancelled => _v('errorCancelled');
  String get errorExternalService => _v('errorExternalService');
  String get emptyTitle => _v('emptyTitle');
  String get emptyCart => _v('emptyCart');
  String get emptyCartMessage => _v('emptyCartMessage');
  String get emptyWishlist => _v('emptyWishlist');
  String get emptyWishlistMessage => _v('emptyWishlistMessage');
  String get emptyOrders => _v('emptyOrders');
  String get emptyOrdersMessage => _v('emptyOrdersMessage');
  String get emptySearch => _v('emptySearch');
  String get emptySearchMessage => _v('emptySearchMessage');
  String get emptyNotifications => _v('emptyNotifications');
  String get emptyAddresses => _v('emptyAddresses');
  String get emptyProducts => _v('emptyProducts');
  String get emptyConversations => _v('emptyConversations');
  String get emptyTickets => _v('emptyTickets');
  String get startShopping => _v('startShopping');
  String get signIn => _v('signIn');
  String get phoneTaken => _v('phoneTaken');
  String get signInInstead => _v('signInInstead');
  String get openStoreOnSaba => _v('openStoreOnSaba');
  String get signOut => _v('signOut');
  String get signUp => _v('signUp');
  String get welcomeToSaba => _v('welcomeToSaba');
  String get signInSubtitle => _v('signInSubtitle');
  String get email => _v('email');
  String get emailHint => _v('emailHint');
  String get password => _v('password');
  String get confirmPassword => _v('confirmPassword');
  String get newPassword => _v('newPassword');
  String get fullName => _v('fullName');
  String get phone => _v('phone');
  String get country => _v('country');
  String get city => _v('city');
  String get forgotPassword => _v('forgotPassword');
  String get forgotPasswordTitle => _v('forgotPasswordTitle');
  String get forgotPasswordSubtitle => _v('forgotPasswordSubtitle');
  String get sendResetLink => _v('sendResetLink');
  String get resetLinkSent => _v('resetLinkSent');
  String get resetPasswordTitle => _v('resetPasswordTitle');
  String get changePassword => _v('changePassword');
  String get passwordChanged => _v('passwordChanged');
  String get noAccount => _v('noAccount');
  String get createAnAccount => _v('createAnAccount');
  String get staffUseWebPanel => _v('staffUseWebPanel');
  String get exampleTemplate => _v('exampleTemplate');
  String get exPersonName => _v('exPersonName');
  String get exStreet => _v('exStreet');
  String get exInstructions => _v('exInstructions');
  String get exTicketSubject => _v('exTicketSubject');
  String get exTicketDescription => _v('exTicketDescription');
  String get exReport => _v('exReport');
  String get exReview => _v('exReview');
  String get exCancel => _v('exCancel');
  String get exReturn => _v('exReturn');
  String get exProductNameAr => _v('exProductNameAr');
  String get exProductNameEn => _v('exProductNameEn');
  String get exProductDescription => _v('exProductDescription');
  String get exWarranty => _v('exWarranty');
  String get exStoreName => _v('exStoreName');
  String get exStoreDescription => _v('exStoreDescription');
  String get exBusinessAddress => _v('exBusinessAddress');
  String get exDriverName => _v('exDriverName');
  String get exCouponCode => _v('exCouponCode');
  String get exRepeatPassword => _v('exRepeatPassword');
  String get haveAccount => _v('haveAccount');
  String get createCustomerAccount => _v('createCustomerAccount');
  String get registerAsMerchant => _v('registerAsMerchant');
  String get accountType => _v('accountType');
  String get customer => _v('customer');
  String get merchant => _v('merchant');
  String get customerAccountDescription => _v('customerAccountDescription');
  String get merchantAccountDescription => _v('merchantAccountDescription');
  String get signOutConfirmTitle => _v('signOutConfirmTitle');
  String get signOutConfirmMessage => _v('signOutConfirmMessage');
  String get merchantPendingApproval => _v('merchantPendingApproval');
  String get storeReviewAfterSignUp => _v('storeReviewAfterSignUp');
  String get validationRequired => _v('validationRequired');
  String get validationEmail => _v('validationEmail');
  String get validationPasswordLength => _v('validationPasswordLength');
  String get passwordHelper => _v('passwordHelper');
  String get validationPasswordMatch => _v('validationPasswordMatch');
  String get validationPhone => _v('validationPhone');
  String get validationMinLengthTemplate => _v('validationMinLengthTemplate');
  String get validationNumber => _v('validationNumber');
  String get validationPositive => _v('validationPositive');
  String get navHome => _v('navHome');
  String get navCategories => _v('navCategories');
  String get navCart => _v('navCart');
  String get navOrders => _v('navOrders');
  String get navAccount => _v('navAccount');
  String get navDashboard => _v('navDashboard');
  String get navProducts => _v('navProducts');
  String get navInventory => _v('navInventory');
  String get navAnalytics => _v('navAnalytics');
  String get homeGreeting => _v('homeGreeting');
  String get hello => _v('hello');
  String get introducing => _v('introducing');
  String get shopNow => _v('shopNow');
  String get recentSearches => _v('recentSearches');
  String get popularSearches => _v('popularSearches');
  String get searchPlaceholder => _v('searchPlaceholder');
  String get flashSales => _v('flashSales');
  String get dealsOfTheDay => _v('dealsOfTheDay');
  String get featuredProducts => _v('featuredProducts');
  String get trendingProducts => _v('trendingProducts');
  String get bestSellers => _v('bestSellers');
  String get newArrivals => _v('newArrivals');
  String get recommendedForYou => _v('recommendedForYou');
  String get allProducts => _v('allProducts');
  String get featuredMerchants => _v('featuredMerchants');
  String get popularBrands => _v('popularBrands');
  String get endsIn => _v('endsIn');
  String get categories => _v('categories');
  String get browse => _v('browse');
  String get searchProductsAndStores => _v('searchProductsAndStores');
  String get allCategories => _v('allCategories');
  String get brands => _v('brands');
  String get products => _v('products');
  String get filters => _v('filters');
  String get sortBy => _v('sortBy');
  String get sortRelevance => _v('sortRelevance');
  String get sortNewest => _v('sortNewest');
  String get sortPriceLowHigh => _v('sortPriceLowHigh');
  String get sortPriceHighLow => _v('sortPriceHighLow');
  String get sortBestSelling => _v('sortBestSelling');
  String get upTo => _v('upTo');
  String get noResultsFiltered => _v('noResultsFiltered');
  String get noResultsFilteredMessage => _v('noResultsFilteredMessage');
  String get priceRange => _v('priceRange');
  String get rating => _v('rating');
  String get availability => _v('availability');
  String get inStockOnly => _v('inStockOnly');
  String get onSale => _v('onSale');
  String get gridView => _v('gridView');
  String get listView => _v('listView');
  String get addToCart => _v('addToCart');
  String get buyNow => _v('buyNow');
  String get addToWishlist => _v('addToWishlist');
  String get removeFromWishlist => _v('removeFromWishlist');
  String get inStock => _v('inStock');
  String get outOfStock => _v('outOfStock');
  String get lowStock => _v('lowStock');
  String get soldBy => _v('soldBy');
  String get visitStore => _v('visitStore');
  String get visitStoreHint => _v('visitStoreHint');
  String get sizeGuide => _v('sizeGuide');
  String get readMore => _v('readMore');
  String get readLess => _v('readLess');
  String get description => _v('description');
  String get warranty => _v('warranty');
  String get returnPolicy => _v('returnPolicy');
  String get shippingInfo => _v('shippingInfo');
  String get estimatedDelivery => _v('estimatedDelivery');
  String get relatedProducts => _v('relatedProducts');
  String get selectVariant => _v('selectVariant');
  String get selectVariantFirst => _v('selectVariantFirst');
  String get addedToCart => _v('addedToCart');
  String get addedToWishlist => _v('addedToWishlist');
  String get off => _v('off');
  String get cart => _v('cart');
  String get myCart => _v('myCart');
  String get saveForLater => _v('saveForLater');
  String get savedForLater => _v('savedForLater');
  String get moveToCart => _v('moveToCart');
  String get removeItemTitle => _v('removeItemTitle');
  String get removeItemMessage => _v('removeItemMessage');
  String get couponCode => _v('couponCode');
  String get applyCoupon => _v('applyCoupon');
  String get couponApplied => _v('couponApplied');
  String get couponsForYou => _v('couponsForYou');
  String get amountOffTemplate => _v('amountOffTemplate');
  String get firstOrderOnly => _v('firstOrderOnly');
  String get onAnyOrder => _v('onAnyOrder');
  String get onOrdersOver => _v('onOrdersOver');
  String get couponCopied => _v('couponCopied');
  String get tapCouponToUse => _v('tapCouponToUse');
  String get removeCoupon => _v('removeCoupon');
  String get shipping => _v('shipping');
  String get tax => _v('tax');
  String get discount => _v('discount');
  String get storeSubtotal => _v('storeSubtotal');
  String get freeShipping => _v('freeShipping');
  String get totalNote => _v('totalNote');
  String get fromWord => _v('fromWord');
  String get eachStoreShips => _v('eachStoreShips');
  String get deliveryFee => _v('deliveryFee');
  String get grandTotal => _v('grandTotal');
  String get proceedToCheckout => _v('proceedToCheckout');
  String get itemsFromStore => _v('itemsFromStore');
  String get maxQuantityReached => _v('maxQuantityReached');
  String get checkout => _v('checkout');
  String get deliverTo => _v('deliverTo');
  String get change => _v('change');
  String get changeAddress => _v('changeAddress');
  String get noDelivery => _v('noDelivery');
  String get delivery => _v('delivery');
  String get deliveryWord => _v('deliveryWord');
  String get twoDeliveriesNote => _v('twoDeliveriesNote');
  String get codNote => _v('codNote');
  String get deliveryAddress => _v('deliveryAddress');
  String get selectAddress => _v('selectAddress');
  String get addAddress => _v('addAddress');
  String get editAddress => _v('editAddress');
  String get defaultAddress => _v('defaultAddress');
  String get setAsDefault => _v('setAsDefault');
  String get shippingMethod => _v('shippingMethod');
  String get paymentMethod => _v('paymentMethod');
  String get orderReview => _v('orderReview');
  String get placeOrder => _v('placeOrder');
  String get orderPlaced => _v('orderPlaced');
  String get orderPlacedMessage => _v('orderPlacedMessage');
  String get viewOrder => _v('viewOrder');
  String get continueShopping => _v('continueShopping');
  String get deliveryInstructions => _v('deliveryInstructions');
  String get cashOnDelivery => _v('cashOnDelivery');
  String get card => _v('card');
  String get wallet => _v('wallet');
  String get bankTransfer => _v('bankTransfer');
  String get totalsRecalculated => _v('totalsRecalculated');
  String get addresses => _v('addresses');
  String get state => _v('state');
  String get district => _v('district');
  String get street => _v('street');
  String get building => _v('building');
  String get apartment => _v('apartment');
  String get postalCode => _v('postalCode');
  String get deleteAddressTitle => _v('deleteAddressTitle');
  String get deleteAddressMessage => _v('deleteAddressMessage');
  String get orders => _v('orders');
  String get myOrders => _v('myOrders');
  String get orderNumber => _v('orderNumber');
  String get orderDate => _v('orderDate');
  String get orderTimeline => _v('orderTimeline');
  String get orderItems => _v('orderItems');
  String get orderDetails => _v('orderDetails');
  String get notAvailable => _v('notAvailable');
  String get invoice => _v('invoice');
  String get cancelOrder => _v('cancelOrder');
  String get cancelOrderTitle => _v('cancelOrderTitle');
  String get cancelOrderMessage => _v('cancelOrderMessage');
  String get requestReturn => _v('requestReturn');
  String get returnReason => _v('returnReason');
  String get orderStatusAll => _v('orderStatusAll');
  String get orderStatusPending => _v('orderStatusPending');
  String get orderStatusConfirmed => _v('orderStatusConfirmed');
  String get orderStatusProcessing => _v('orderStatusProcessing');
  String get stepPreparing => _v('stepPreparing');
  String get expectedArrivalTemplate => _v('expectedArrivalTemplate');
  String get orderFollowsSlowestTemplate => _v('orderFollowsSlowestTemplate');
  String get orderStatusShipped => _v('orderStatusShipped');
  String get orderStatusDelivered => _v('orderStatusDelivered');
  String get orderStatusCancelled => _v('orderStatusCancelled');
  String get orderStatusReturned => _v('orderStatusReturned');
  String get orderStatusRefunded => _v('orderStatusRefunded');
  String get paymentStatus => _v('paymentStatus');
  String get deliveryStatus => _v('deliveryStatus');
  String get account => _v('account');
  String get myProfile => _v('myProfile');
  String get editProfile => _v('editProfile');
  String get wishlist => _v('wishlist');
  String get notifications => _v('notifications');
  String get messages => _v('messages');
  String get support => _v('support');
  String get settings => _v('settings');
  String get language => _v('language');
  String get theme => _v('theme');
  String get themeSystem => _v('themeSystem');
  String get themeLight => _v('themeLight');
  String get themeDark => _v('themeDark');
  String get deleteAccount => _v('deleteAccount');
  String get deleteAccountTitle => _v('deleteAccountTitle');
  String get deleteAccountMessage => _v('deleteAccountMessage');
  String get profileUpdated => _v('profileUpdated');
  String get guestTitle => _v('guestTitle');
  String get guestMessage => _v('guestMessage');
  String get merchantDashboard => _v('merchantDashboard');
  String get myStore => _v('myStore');
  String get todaySales => _v('todaySales');
  String get totalSales => _v('totalSales');
  String get revenue => _v('revenue');
  String get pendingOrders => _v('pendingOrders');
  String get lowStockItems => _v('lowStockItems');
  String get outOfStockItems => _v('outOfStockItems');
  String get totalProducts => _v('totalProducts');
  String get totalOrders => _v('totalOrders');
  String get topProducts => _v('topProducts');
  String get myProducts => _v('myProducts');
  String get addProduct => _v('addProduct');
  String get editProduct => _v('editProduct');
  String get productName => _v('productName');
  String get sku => _v('sku');
  String get barcode => _v('barcode');
  String get stock => _v('stock');
  String get originalPrice => _v('originalPrice');
  String get saveDraft => _v('saveDraft');
  String get submitForApproval => _v('submitForApproval');
  String get productDraft => _v('productDraft');
  String get productPendingApproval => _v('productPendingApproval');
  String get productApproved => _v('productApproved');
  String get productRejected => _v('productRejected');
  String get inventory => _v('inventory');
  String get adjustStock => _v('adjustStock');
  String get availableStock => _v('availableStock');
  String get reservedStock => _v('reservedStock');
  String get soldStock => _v('soldStock');
  String get lowStockThreshold => _v('lowStockThreshold');
  String get merchantOrders => _v('merchantOrders');
  String get updateOrderStatus => _v('updateOrderStatus');
  String get analytics => _v('analytics');
  String get payouts => _v('payouts');
  String get grossSales => _v('grossSales');
  String get commission => _v('commission');
  String get netEarnings => _v('netEarnings');
  String get pendingPayout => _v('pendingPayout');
  String get availablePayout => _v('availablePayout');
  String get averageOrderValue => _v('averageOrderValue');
  String get storeSettings => _v('storeSettings');
  String get storeName => _v('storeName');
  String get storeDescription => _v('storeDescription');
  String get businessType => _v('businessType');
  String get businessAddress => _v('businessAddress');
  String get supportTickets => _v('supportTickets');
  String get newTicket => _v('newTicket');
  String get ticketSubject => _v('ticketSubject');
  String get ticketCategory => _v('ticketCategory');
  String get ticketDescription => _v('ticketDescription');
  String get ticketStatusOpen => _v('ticketStatusOpen');
  String get ticketStatusInProgress => _v('ticketStatusInProgress');
  String get ticketStatusWaiting => _v('ticketStatusWaiting');
  String get ticketStatusResolved => _v('ticketStatusResolved');
  String get ticketStatusClosed => _v('ticketStatusClosed');
  String get typeMessage => _v('typeMessage');
  String get send => _v('send');
  String get photo => _v('photo');
  String get sendPhoto => _v('sendPhoto');
  String get photoDeleted => _v('photoDeleted');
  String get photoRemovedBySaba => _v('photoRemovedBySaba');
  String get markAllRead => _v('markAllRead');
  String get or => _v('or');
  String get all => _v('all');
  String get update => _v('update');
  String get create => _v('create');
  String get reset => _v('reset');
  String get viewDetails => _v('viewDetails');
  String get saveChanges => _v('saveChanges');
  String get stores => _v('stores');
  String get store => _v('store');
  String get signInRequired => _v('signInRequired');
  String get signInToContinue => _v('signInToContinue');
  String get orderSummary => _v('orderSummary');
  String get shippingAddress => _v('shippingAddress');
  String get trackOrder => _v('trackOrder');
  String get selectCountry => _v('selectCountry');
  String get selectCity => _v('selectCity');
  String get statusApproved => _v('statusApproved');
  String get statusRejected => _v('statusRejected');
  String get statusSuspended => _v('statusSuspended');
  String get statusActive => _v('statusActive');
  String get statusInactive => _v('statusInactive');
  String get attachments => _v('attachments');
  String get sortAndFilter => _v('sortAndFilter');
  String get noImage => _v('noImage');
  String get salesChart => _v('salesChart');
  String get thisWeek => _v('thisWeek');
  String get thisMonth => _v('thisMonth');
  String get thisYear => _v('thisYear');
  String get today => _v('today');
  String get refunds => _v('refunds');
  String get returns => _v('returns');
  String get cancellations => _v('cancellations');
  String get productsSold => _v('productsSold');
  String get customers => _v('customers');
  String get orderStatusNew => _v('orderStatusNew');
  String get requestPayout => _v('requestPayout');
  String get payoutHistory => _v('payoutHistory');
  String get noPayouts => _v('noPayouts');
  String get stockAdjustment => _v('stockAdjustment');
  String get newQuantity => _v('newQuantity');
  String get reason => _v('reason');
  String get searchProducts => _v('searchProducts');
  String get period => _v('period');
  String get noProductsYet => _v('noProductsYet');
  String get addFirstProduct => _v('addFirstProduct');
  String get deleteProductTitle => _v('deleteProductTitle');
  String get deleteProductMessage => _v('deleteProductMessage');
  String get category => _v('category');
  String get selectCategory => _v('selectCategory');
  String get brand => _v('brand');
  String get brandHint => _v('brandHint');
  String get brandHelp => _v('brandHelp');
  String get markAsShipped => _v('markAsShipped');
  String get nextStatus => _v('nextStatus');
  String get customerName => _v('customerName');
  String get noStoreYet => _v('noStoreYet');
  String get addPhotos => _v('addPhotos');
  String get addPhoto => _v('addPhoto');
  String get takePhoto => _v('takePhoto');
  String get chooseFromGallery => _v('chooseFromGallery');
  String get attachFile => _v('attachFile');
  String get uploading => _v('uploading');
  String get uploadFailed => _v('uploadFailed');
  String get retryUpload => _v('retryUpload');
  String get cancelUpload => _v('cancelUpload');
  String get removeFile => _v('removeFile');
  String get setAsPrimary => _v('setAsPrimary');
  String get primaryImage => _v('primaryImage');
  String get noFilesSelected => _v('noFilesSelected');
  String get maxFilesReached => _v('maxFilesReached');
  String get mediaTooLarge => _v('mediaTooLarge');
  String get mediaUnsupportedType => _v('mediaUnsupportedType');
  String get mediaUnsupportedExtension => _v('mediaUnsupportedExtension');
  String get mediaImageTooSmall => _v('mediaImageTooSmall');
  String get mediaImageTooLarge => _v('mediaImageTooLarge');
  String get mediaUnreadable => _v('mediaUnreadable');
  String get someFilesRejected => _v('someFilesRejected');
  String get paymentPending => _v('paymentPending');
  String get paymentPendingMessage => _v('paymentPendingMessage');
  String get paymentConfirmed => _v('paymentConfirmed');
  String get paymentFailedTitle => _v('paymentFailedTitle');
  String get paymentFailedMessage => _v('paymentFailedMessage');
  String get checkPaymentStatus => _v('checkPaymentStatus');
  String get awaitingPayment => _v('awaitingPayment');
  String get productImages => _v('productImages');
  String get productImagesHint => _v('productImagesHint');
  String get productBasics => _v('productBasics');
  String get priceAndStock => _v('priceAndStock');
  String get productCodes => _v('productCodes');
  String get productPolicies => _v('productPolicies');
  String get variants => _v('variants');
  String get variantsHint => _v('variantsHint');
  String get addOption => _v('addOption');
  String get editOption => _v('editOption');
  String get optionName => _v('optionName');
  String get optionNameHint => _v('optionNameHint');
  String get optionValues => _v('optionValues');
  String get optionValuesHint => _v('optionValuesHint');
  String get inheritPrice => _v('inheritPrice');
  String get myReturns => _v('myReturns');
  String get noReturns => _v('noReturns');
  String get noReturnsMessage => _v('noReturnsMessage');
  String get returnStatusRequested => _v('returnStatusRequested');
  String get returnStatusApproved => _v('returnStatusApproved');
  String get returnStatusRejected => _v('returnStatusRejected');
  String get returnStatusPickup => _v('returnStatusPickup');
  String get returnStatusReceived => _v('returnStatusReceived');
  String get returnStatusRefundPending => _v('returnStatusRefundPending');
  String get returnStatusRefunded => _v('returnStatusRefunded');
  String get returnStatusClosed => _v('returnStatusClosed');
  String get returnDetails => _v('returnDetails');
  String get returnedItems => _v('returnedItems');
  String get returnRequestedOn => _v('returnRequestedOn');
  String get returnPhotos => _v('returnPhotos');
  String get rejectionReason => _v('rejectionReason');
  String get returnProgress => _v('returnProgress');
  String get refund => _v('refund');
  String get refundStatus => _v('refundStatus');
  String get refundAmount => _v('refundAmount');
  String get refundMethod => _v('refundMethod');
  String get refundReference => _v('refundReference');
  String get refundProcessedOn => _v('refundProcessedOn');
  String get refundExpectedBy => _v('refundExpectedBy');
  String get refundStatusPending => _v('refundStatusPending');
  String get refundStatusProcessing => _v('refundStatusProcessing');
  String get refundStatusCompleted => _v('refundStatusCompleted');
  String get refundStatusFailed => _v('refundStatusFailed');
  String get noRefundYet => _v('noRefundYet');
  String get viewInvoice => _v('viewInvoice');
  String get invoiceNumber => _v('invoiceNumber');
  String get issuedOn => _v('issuedOn');
  String get billedTo => _v('billedTo');
  String get unitPrice => _v('unitPrice');
  String get amount => _v('amount');
  String get downloadInvoice => _v('downloadInvoice');
  String get invoiceTotals => _v('invoiceTotals');
  String get amountPaid => _v('amountPaid');
  String get cancelReason => _v('cancelReason');
  String get selectCancelReason => _v('selectCancelReason');
  String get cancelReasonChangedMind => _v('cancelReasonChangedMind');
  String get cancelReasonFoundCheaper => _v('cancelReasonFoundCheaper');
  String get cancelReasonDeliveryTooSlow => _v('cancelReasonDeliveryTooSlow');
  String get cancelReasonOrderedByMistake => _v('cancelReasonOrderedByMistake');
  String get cancelReasonOther => _v('cancelReasonOther');
  String get cancelReasonNote => _v('cancelReasonNote');
  String get cancelReasonRequired => _v('cancelReasonRequired');
  String get returnReasonDamaged => _v('returnReasonDamaged');
  String get returnReasonWrongItem => _v('returnReasonWrongItem');
  String get returnReasonNotAsDescribed => _v('returnReasonNotAsDescribed');
  String get returnReasonMissingParts => _v('returnReasonMissingParts');
  String get returnReasonChangedMind => _v('returnReasonChangedMind');
  String get returnReasonOther => _v('returnReasonOther');
  String get emptyFilteredList => _v('emptyFilteredList');
  String get emptyFilteredListMessage => _v('emptyFilteredListMessage');
  String get showAll => _v('showAll');
  String get ticketCategoryOrder => _v('ticketCategoryOrder');
  String get ticketCategoryPayment => _v('ticketCategoryPayment');
  String get ticketCategoryDelivery => _v('ticketCategoryDelivery');
  String get ticketCategoryReturn => _v('ticketCategoryReturn');
  String get ticketCategoryProduct => _v('ticketCategoryProduct');
  String get ticketCategoryAccount => _v('ticketCategoryAccount');
  String get ticketCategoryOther => _v('ticketCategoryOther');
  String get emptyTicketsMessage => _v('emptyTicketsMessage');
  String get emptyProductsMessage => _v('emptyProductsMessage');
  String get emptyNotificationsMessage => _v('emptyNotificationsMessage');
  String get addressNickname => _v('addressNickname');
  String get addressNicknameHint => _v('addressNicknameHint');
  String get addressWho => _v('addressWho');
  String get addressWhere => _v('addressWhere');
  String get addressExtras => _v('addressExtras');
  String get emptyAddressesMessage => _v('emptyAddressesMessage');
  String get languageSystem => _v('languageSystem');
  String get languageSystemHint => _v('languageSystemHint');
  String get noReviewsMessage => _v('noReviewsMessage');
  String get merchantReplied => _v('merchantReplied');
  String get reportReview => _v('reportReview');
  String get report => _v('report');
  String get reportProduct => _v('reportProduct');
  String get reportStore => _v('reportStore');
  String get reportChat => _v('reportChat');
  String get reportThanks => _v('reportThanks');
  String get block => _v('block');
  String get unblock => _v('unblock');
  String get blockTitle => _v('blockTitle');
  String get blockMessage => _v('blockMessage');
  String get chatBlockedByMe => _v('chatBlockedByMe');
  String get chatBlocked => _v('chatBlocked');
  String get storeReviews => _v('storeReviews');
  String get reportReasonLabel => _v('reportReasonLabel');
  String get reportCounterfeit => _v('reportCounterfeit');
  String get reportProhibited => _v('reportProhibited');
  String get reportMisleading => _v('reportMisleading');
  String get reportOffensive => _v('reportOffensive');
  String get reportSpam => _v('reportSpam');
  String get reportOther => _v('reportOther');
  String get reportDetails => _v('reportDetails');
  String get reportSubmitted => _v('reportSubmitted');
  String get reportReasonRequired => _v('reportReasonRequired');
  String get noReviews => _v('noReviews');
  String get clearHistoryTitle => _v('clearHistoryTitle');
  String get clearHistoryMessage => _v('clearHistoryMessage');
  String get noMessagesYet => _v('noMessagesYet');
  String get noMessagesYetMessage => _v('noMessagesYetMessage');
  String get selectItemsToReturn => _v('selectItemsToReturn');
  String get removeOptionTitle => _v('removeOptionTitle');
  String get removeOptionMessage => _v('removeOptionMessage');
  String get variantsKeptIfEmpty => _v('variantsKeptIfEmpty');
  String get waitForUploads => _v('waitForUploads');
  String get keepOrder => _v('keepOrder');
  String get storeUpdated => _v('storeUpdated');
  String get moreOptions => _v('moreOptions');
  String get verified => _v('verified');
  String get revenueThisMonth => _v('revenueThisMonth');
  String get needsYouToday => _v('needsYouToday');
  String get oldestWaiting => _v('oldestWaiting');
  String get stillListedNotBuyable => _v('stillListedNotBuyable');
  String get replyWithin => _v('replyWithin');
  String get ordersThisMonth => _v('ordersThisMonth');
  String get storeRating => _v('storeRating');
  String get vsLastMonth => _v('vsLastMonth');
  String get previousPeriod => _v('previousPeriod');
  String get lastMonthSame => _v('lastMonthSame');
  String get noSalesYet => _v('noSalesYet');
  String get storeOpen => _v('storeOpen');
  String get storeClosed => _v('storeClosed');
  String get allCaughtUp => _v('allCaughtUp');
  String get viewAll => _v('viewAll');
  String get toConfirm => _v('toConfirm');
  String get preparing => _v('preparing');
  String get decline => _v('decline');
  String get whyDeclining => _v('whyDeclining');
  String get declineNote => _v('declineNote');
  String get reasonOutOfStock => _v('reasonOutOfStock');
  String get reasonCannotFulfil => _v('reasonCannotFulfil');
  String get reasonAddressProblem => _v('reasonAddressProblem');
  String get reasonCustomerAsked => _v('reasonCustomerAsked');
  String get orderDeclined => _v('orderDeclined');
  String get searchYourProducts => _v('searchYourProducts');
  String get lowStockFilter => _v('lowStockFilter');
  String get outFilter => _v('outFilter');
  String get hiddenFilter => _v('hiddenFilter');
  String get hidden => _v('hidden');
  String get hideFromShoppers => _v('hideFromShoppers');
  String get showToShoppers => _v('showToShoppers');
  String get productHidden => _v('productHidden');
  String get productShown => _v('productShown');
  String get inStockCount => _v('inStockCount');
  String get leftCount => _v('leftCount');
  String get restock => _v('restock');
  String get setStock => _v('setStock');
  String get flashSale => _v('flashSale');
  String get flashSaleUntilTemplate => _v('flashSaleUntilTemplate');
  String get salePrice => _v('salePrice');
  String get normalPriceTemplate => _v('normalPriceTemplate');
  String get salePriceInvalid => _v('salePriceInvalid');
  String get salePriceNotLower => _v('salePriceNotLower');
  String get endSaleQuestion => _v('endSaleQuestion');
  String get endSaleWarning => _v('endSaleWarning');
  String get saleEndPassed => _v('saleEndPassed');
  String get startSale => _v('startSale');
  String get endSaleNow => _v('endSaleNow');
  String get flashSaleSaved => _v('flashSaleSaved');
  String get flashSaleEnded => _v('flashSaleEnded');
  String get noProductsMatch => _v('noProductsMatch');
  String get productsRejected => _v('productsRejected');
  String get rejectedNeedsEdit => _v('rejectedNeedsEdit');
  String get sabaTagline => _v('sabaTagline');
  String get chooseYourLanguage => _v('chooseYourLanguage');
  String get changeLanguageLater => _v('changeLanguageLater');
  String get englishName => _v('englishName');
  String get englishOther => _v('englishOther');
  String get arabicName => _v('arabicName');
  String get arabicOther => _v('arabicOther');
  String get alreadyHaveAccount => _v('alreadyHaveAccount');
  String get whatsYourNumber => _v('whatsYourNumber');
  String get phoneStepCustomerMessage => _v('phoneStepCustomerMessage');
  String get phoneStepMerchantMessage => _v('phoneStepMerchantMessage');
  String get sendCode => _v('sendCode');
  String get enterTheCode => _v('enterTheCode');
  String get codeSentTo => _v('codeSentTo');
  String get verificationCode => _v('verificationCode');
  String get changeNumber => _v('changeNumber');
  String get didNotGetCode => _v('didNotGetCode');
  String get resendCode => _v('resendCode');
  String get codeSentAgain => _v('codeSentAgain');
  String get demoCodeNote => _v('demoCodeNote');
  String get validationOtpLength => _v('validationOtpLength');
  String get verify => _v('verify');
  String get verifyNumberTitle => _v('verifyNumberTitle');
  String get verifyNumberWhy => _v('verifyNumberWhy');
  String get verifyNumberToSignIn => _v('verifyNumberToSignIn');
  String get numberVerified => _v('numberVerified');
  String get businessTypeIndividual => _v('businessTypeIndividual');
  String get businessTypeSoleProprietorship => _v('businessTypeSoleProprietorship');
  String get businessTypeCompany => _v('businessTypeCompany');
  String get businessTypeDistributor => _v('businessTypeDistributor');
  String get demoAccountsTitle => _v('demoAccountsTitle');
  String get demoAccountsNote => _v('demoAccountsNote');
  String get demoShopper => _v('demoShopper');
  String get demoMerchant => _v('demoMerchant');
  String get yourProfile => _v('yourProfile');
  String get yourProfileSubtitle => _v('yourProfileSubtitle');
  String get yourStore => _v('yourStore');
  String get yourStoreSubtitle => _v('yourStoreSubtitle');
  String get storeSignUpSubtitle => _v('storeSignUpSubtitle');
  String get stepWord => _v('stepWord');
  String get ofWord => _v('ofWord');
  String get chooseBusinessType => _v('chooseBusinessType');
  String get changeLanguage => _v('changeLanguage');
  String get accountYou => _v('accountYou');
  String get accountGetHelp => _v('accountGetHelp');
  String get accountSecurity => _v('accountSecurity');
  String get itemRemoved => _v('itemRemoved');
  String get undo => _v('undo');
  String get removeUnavailable => _v('removeUnavailable');
  String get searchInStore => _v('searchInStore');
  String get noResultsInStore => _v('noResultsInStore');
  String get noResultsInStoreMessage => _v('noResultsInStoreMessage');
  String get copiedToClipboard => _v('copiedToClipboard');
  String get copy => _v('copy');
  String get makeMainImage => _v('makeMainImage');
  String get message => _v('message');
  String get emptyConversationsHint => _v('emptyConversationsHint');
  String get emptyConversationsStoreHint => _v('emptyConversationsStoreHint');
  String get aboutTopicTemplate => _v('aboutTopicTemplate');
  String get aboutOrderTemplate => _v('aboutOrderTemplate');
  String get codPlacedMessage => _v('codPlacedMessage');
  String get payOnDelivery => _v('payOnDelivery');
  String get paymentPaid => _v('paymentPaid');
  String get paymentFailedShort => _v('paymentFailedShort');
  String get coupons => _v('coupons');
  String get couponsTileHint => _v('couponsTileHint');
  String get newCoupon => _v('newCoupon');
  String get editCoupon => _v('editCoupon');
  String get couponCodeHelper => _v('couponCodeHelper');
  String get suggestCode => _v('suggestCode');
  String get discountPercent => _v('discountPercent');
  String get discountAmountIqd => _v('discountAmountIqd');
  String get discountLabel => _v('discountLabel');
  String get minimumOrderOptional => _v('minimumOrderOptional');
  String get minimumOrderHelper => _v('minimumOrderHelper');
  String get startsOn => _v('startsOn');
  String get endsOn => _v('endsOn');
  String get noEndDate => _v('noEndDate');
  String get usageLimitOptional => _v('usageLimitOptional');
  String get usageLimitHelper => _v('usageLimitHelper');
  String get couponUsedTemplate => _v('couponUsedTemplate');
  String get couponUsedOfTemplate => _v('couponUsedOfTemplate');
  String get couponScheduled => _v('couponScheduled');
  String get couponPaused => _v('couponPaused');
  String get couponEnded => _v('couponEnded');
  String get couponUsedUp => _v('couponUsedUp');
  String get untilDateTemplate => _v('untilDateTemplate');
  String get startsDateTemplate => _v('startsDateTemplate');
  String get pauseCoupon => _v('pauseCoupon');
  String get resumeCoupon => _v('resumeCoupon');
  String get deleteCouponQuestion => _v('deleteCouponQuestion');
  String get deleteCouponMessage => _v('deleteCouponMessage');
  String get couponSaved => _v('couponSaved');
  String get couponDeleted => _v('couponDeleted');
  String get noCouponsYet => _v('noCouponsYet');
  String get noCouponsYetMessage => _v('noCouponsYetMessage');
  String get couponPreview => _v('couponPreview');
  String get couponsFromTemplate => _v('couponsFromTemplate');
  String get atStoreTemplate => _v('atStoreTemplate');
  String get couponCodeInvalid => _v('couponCodeInvalid');
  String get discountInvalid => _v('discountInvalid');
  String get percentTooHigh => _v('percentTooHigh');
  String get endBeforeStart => _v('endBeforeStart');
  String get wholeNumber => _v('wholeNumber');
  String get yesterday => _v('yesterday');
  String get deleteStoreAccountHint => _v('deleteStoreAccountHint');
  String get deleteStoreAccountTitle => _v('deleteStoreAccountTitle');
  String get deleteStoreAccountMessage => _v('deleteStoreAccountMessage');
  String get storeDeletionTitle => _v('storeDeletionTitle');
  String get storeDeletionAskedTemplate => _v('storeDeletionAskedTemplate');
  String get storeDeletionWaitsFor => _v('storeDeletionWaitsFor');
  String get stillOpenOrdersTemplate => _v('stillOpenOrdersTemplate');
  String get openReturnsTemplate => _v('openReturnsTemplate');
  String get stillOwedTemplate => _v('stillOwedTemplate');
  String get returnsOpenUntilTemplate => _v('returnsOpenUntilTemplate');
  String get storeDeletionSoon => _v('storeDeletionSoon');
  String get storeDeletionSms => _v('storeDeletionSms');
  String get storeDeletionUnpaid => _v('storeDeletionUnpaid');
  String get keepMyAccount => _v('keepMyAccount');
  String get keepMyAccountTitle => _v('keepMyAccountTitle');
  String get keepMyAccountMessage => _v('keepMyAccountMessage');
  String get accountKept => _v('accountKept');
  String get storeBeingDeleted => _v('storeBeingDeleted');
  String get deleteAccountHint => _v('deleteAccountHint');
  String get yourCity => _v('yourCity');
  String get chooseYourCity => _v('chooseYourCity');
  String get deliverToTemplate => _v('deliverToTemplate');
  String get cityRequired => _v('cityRequired');
  String get useEmailInstead => _v('useEmailInstead');
  String get usePhoneInstead => _v('usePhoneInstead');
  String get emailOptional => _v('emailOptional');
  String get forgotPasswordPhoneSubtitle => _v('forgotPasswordPhoneSubtitle');
  String get saveNewPassword => _v('saveNewPassword');
  String get phoneSignInHelper => _v('phoneSignInHelper');
  String get area => _v('area');
  String get areaHint => _v('areaHint');
  String get nearestLandmark => _v('nearestLandmark');
  String get nearestLandmarkHint => _v('nearestLandmarkHint');
  String get streetAndHouse => _v('streetAndHouse');
  String get driverCallsThisNumber => _v('driverCallsThisNumber');
  String get cashToEachDriver => _v('cashToEachDriver');
  String get cashToEachDriverNote => _v('cashToEachDriverNote');
  String get cashToDriver => _v('cashToDriver');
  String get paidToDriver => _v('paidToDriver');
  String get collectInCash => _v('collectInCash');
  String get iqdSteps => _v('iqdSteps');
  String get deliverySameDay => _v('deliverySameDay');
  String get delivery1to2Days => _v('delivery1to2Days');
  String get delivery2to3Days => _v('delivery2to3Days');
  String get delivery3to5Days => _v('delivery3to5Days');
  String get delivery5to7Days => _v('delivery5to7Days');
  String get noDeliveryToTemplate => _v('noDeliveryToTemplate');
  String get deliversToTemplate => _v('deliversToTemplate');
  String get addressCityNoteTemplate => _v('addressCityNoteTemplate');
  String get deliverySettings => _v('deliverySettings');
  String get whereYouDeliver => _v('whereYouDeliver');
  String get wholeIraq => _v('wholeIraq');
  String get onlyMyCity => _v('onlyMyCity');
  String get feeInYourCity => _v('feeInYourCity');
  String get feeOtherCities => _v('feeOtherCities');
  String get timeInYourCity => _v('timeInYourCity');
  String get timeOtherCities => _v('timeOtherCities');
  String get zeroIsFree => _v('zeroIsFree');
  String get removeOrChangeAddress => _v('removeOrChangeAddress');
  String get chooseDeliveryTime => _v('chooseDeliveryTime');
  String get call => _v('call');
  String get orderStatusRefused => _v('orderStatusRefused');
  String get callShopperFirst => _v('callShopperFirst');
  String get iCalledConfirm => _v('iCalledConfirm');
  String get whoDelivers => _v('whoDelivers');
  String get driverName => _v('driverName');
  String get courierPhone => _v('courierPhone');
  String get refusedAtDoor => _v('refusedAtDoor');
  String get refusedConfirm => _v('refusedConfirm');
  String get driverLabel => _v('driverLabel');
  String get didYouReceive => _v('didYouReceive');
  String get yesReceived => _v('yesReceived');
  String get noNotReceived => _v('noNotReceived');
  String get receiptProblemNote => _v('receiptProblemNote');
  String get returnCashNote => _v('returnCashNote');
  String get returnWindowNote => _v('returnWindowNote');
  String get notOnThisReturn => _v('notOnThisReturn');
  String get notDeliveredYetReturn => _v('notDeliveredYetReturn');
  String get cancelledNothingToReturn => _v('cancelledNothingToReturn');
  String get returnedOrLate => _v('returnedOrLate');
  String get nothingToReturnNow => _v('nothingToReturnNow');
  String get returnRequests => _v('returnRequests');
  String get approveReturn => _v('approveReturn');
  String get declineReturn => _v('declineReturn');
  String get cashHandedBack => _v('cashHandedBack');
  String get oweSaba => _v('oweSaba');
  String get oweThisMonth => _v('oweThisMonth');
  String get deliveredSales => _v('deliveredSales');
  String get returnedCash => _v('returnedCash');
  String get sabaShare => _v('sabaShare');
  String get youOwe => _v('youOwe');
  String get oweHowItWorks => _v('oweHowItWorks');
  String get pastMonths => _v('pastMonths');
  String get noPastMonths => _v('noPastMonths');
  String get billDue => _v('billDue');
  String get billPaid => _v('billPaid');
  String get billPaidOnTemplate => _v('billPaidOnTemplate');
  String get billNothingOwed => _v('billNothingOwed');
  String get storeClosedNow => _v('storeClosedNow');
  String get storeClosedBuyNote => _v('storeClosedBuyNote');
  String get storeNowOpen => _v('storeNowOpen');
  String get storeNowClosed => _v('storeNowClosed');
  String get nameInArabic => _v('nameInArabic');
  String get nameInEnglish => _v('nameInEnglish');
  String get validationArabicLetters => _v('validationArabicLetters');
  String get termsOfUse => _v('termsOfUse');
  String get privacyPolicy => _v('privacyPolicy');
  String get legalUpdated => _v('legalUpdated');
  String get aboutSaba => _v('aboutSaba');
  String get agreeToTerms => _v('agreeToTerms');
  String get returnRuleShort => _v('returnRuleShort');
  String get returnRuleStore => _v('returnRuleStore');
  String get allCities => _v('allCities');
  String get deliveryAvailable => _v('deliveryAvailable');
  String get didYourOrderArrive => _v('didYourOrderArrive');
  String get yesItArrived => _v('yesItArrived');
  String get returnDeclineUsed => _v('returnDeclineUsed');
  String get returnDeclineIncomplete => _v('returnDeclineIncomplete');
  String get returnDeclineNotAsSaid => _v('returnDeclineNotAsSaid');
  String get whyDecliningReturn => _v('whyDecliningReturn');
  String get confirmApproveReturn => _v('confirmApproveReturn');
  String get confirmCashBack => _v('confirmCashBack');
  String get howWasYourOrder => _v('howWasYourOrder');
  String get notYet => _v('notYet');
  String get notNow => _v('notNow');
  String get anythingToAdd => _v('anythingToAdd');
  String get stockIsPerOption => _v('stockIsPerOption');
  String get merchantRejectedBanner => _v('merchantRejectedBanner');
  String get storePreview => _v('storePreview');
  String get previewNotListed => _v('previewNotListed');
  String get backToDashboard => _v('backToDashboard');
  String get setUpYourStore => _v('setUpYourStore');
  String get stepAddFirstProduct => _v('stepAddFirstProduct');
  String get stepSetDelivery => _v('stepSetDelivery');
  String get stepWaitForApproval => _v('stepWaitForApproval');
  String get storeWaitingApproval => _v('storeWaitingApproval');
  String get storeApprovedOpen => _v('storeApprovedOpen');
  String get storeApprovedClosed => _v('storeApprovedClosed');
  String get storeNotApproved => _v('storeNotApproved');
  String get sendForApproval => _v('sendForApproval');
  String get sendForApprovalHint => _v('sendForApprovalHint');
  String get productSaved => _v('productSaved');
  String get priceStepHint => _v('priceStepHint');
  String get waitingForApproval => _v('waitingForApproval');
  String get storeLogo => _v('storeLogo');
  String get previewWaitingMessage => _v('previewWaitingMessage');
  String get listSeparator => _v('listSeparator');
  String get nounItem => _v('nounItem');
  String get nounCharacter => _v('nounCharacter');
  String get nounProduct => _v('nounProduct');
  String get nounStore => _v('nounStore');
  String get nounOrder => _v('nounOrder');
  String get nounResult => _v('nounResult');
  String get nounCustomer => _v('nounCustomer');
  String get nounReturnRequest => _v('nounReturnRequest');
  String get nounDay => _v('nounDay');
  String get nounHour => _v('nounHour');
  String get nounMinute => _v('nounMinute');
  String get nounSecond => _v('nounSecond');
  String get nounTime => _v('nounTime');
  String get resendInTemplate => _v('resendInTemplate');
  String get waitingForTemplate => _v('waitingForTemplate');
  String get toConfirmSuffix => _v('toConfirmSuffix');
  String get waitingReplySuffix => _v('waitingReplySuffix');
  String get outOfStockSuffix => _v('outOfStockSuffix');
  String get notApprovedSuffix => _v('notApprovedSuffix');
  String get freeDelivery => _v('freeDelivery');
  String get takenDown => _v('takenDown');
  String get takenDownBySaba => _v('takenDownBySaba');
  String get sabaSaidNo => _v('sabaSaidNo');
  String get fixAndResend => _v('fixAndResend');
  String get editApprovedNote => _v('editApprovedNote');
  String get noteOrderReceived => _v('noteOrderReceived');
  String get reasonCustomerCancelled => _v('reasonCustomerCancelled');
  String get notInTotalTemplate => _v('notInTotalTemplate');
  String get productNotFound => _v('productNotFound');
  String get productNotFoundMessage => _v('productNotFoundMessage');
  String get cancelledNothingCharged => _v('cancelledNothingCharged');
  String get refusedNothingPaid => _v('refusedNothingPaid');
  // -------------------------------------------------- parameterized strings --

  /// A count and its noun, said the way the language says it: "1 item",
  /// "3 items"; "منتج واحد", "منتجان", "3 منتجات", "11 منتجًا", "100 منتج".
  ///
  /// Every count on screen goes through here. They each chose singular or
  /// plural on their own, which is two forms where Arabic has six, and read
  /// "2 منتجات من 2 متاجر" and "11 منتجات".
  ///
  /// The forms come from the translation file, `|` between them: English
  /// one|other; Arabic one|two|two after a preposition|3-10|11-99|other,
  /// the plural classes of CLDR. One and two are said without the number,
  /// as Arabic does. [genitive] picks the dual after a preposition: "من
  /// متجرين", not "من متجران".
  String counted(int count, CountNoun noun, {bool genitive = false}) {
    final forms = _v(noun.key).split('|');
    if (forms.length < 6) {
      return '$count ${count == 1 || forms.length == 1 ? forms[0] : forms[1]}';
    }
    final rest = count % 100;
    return switch (count) {
      1 => forms[0],
      2 => genitive ? forms[2] : forms[1],
      _ when rest >= 3 && rest <= 10 => '$count ${forms[3]}',
      _ when rest >= 11 => '$count ${forms[4]}',
      _ => '$count ${forms[5]}',
    };
  }

  /// "Tokyo, Japan" / "طوكيو، اليابان": the list comma of the language.
  String get comma => _v('listSeparator');

  /// "3 items from 2 stores. Each store ships on its own."
  String cartSummary(int items, int stores) =>
      '${counted(items, CountNoun.item)} ${_v('fromWord')} '
      '${counted(stores, CountNoun.store, genitive: true)}. '
      '${_v('eachStoreShips')}';

  /// The API's business-type token, in the reader's language. Built by
  /// title-casing the token before this, which left Arabic showing
  /// "Sole Proprietorship".
  String businessTypeLabel(String token) => switch (token) {
    'INDIVIDUAL' => _v('businessTypeIndividual'),
    'SOLE_PROPRIETORSHIP' => _v('businessTypeSoleProprietorship'),
    'COMPANY' => _v('businessTypeCompany'),
    'DISTRIBUTOR' => _v('businessTypeDistributor'),
    _ => token,
  };

  /// "Step 2 of 4"
  String stepOf(int step, int total) =>
      '${_v('stepWord')} $step ${_v('ofWord')} $total';

  /// "Out of stock - not charged"
  String outOfStockNotCharged() =>
      '${_v('outOfStock')} — ${_v('notCharged')}';

  /// "Delivery, 2 stores"
  String deliveryFromStores(int stores) =>
      '${_v('deliveryWord')}$comma${counted(stores, CountNoun.store)}';

  /// "Place order - 2,605,200 IQD"
  String placeOrderFor(String amount) =>
      '${_v('placeOrder')} · $amount';

  /// "10% off", "خصم 10%" - one template per language, because the amount
  /// sits on a different side of the words in each.
  String amountOff(String amount) =>
      _v('amountOffTemplate').replaceFirst('{amount}', amount);

  /// The first words of a chat started from a product or an order, so the
  /// store knows what the question is about.
  String aboutTopic(String topic) =>
      _v('aboutTopicTemplate').replaceFirst('{topic}', topic);

  /// "Doesn't deliver to Erbil", beside a store the shopper cannot buy from.
  String noDeliveryTo(String city) =>
      _v('noDeliveryToTemplate').replaceFirst('{city}', city);

  /// "Delivers to Erbil", beside a store that does.
  String deliversTo(String city) =>
      _v('deliversToTemplate').replaceFirst('{city}', city);

  /// Said at checkout when the address is not in the Home city.
  String addressCityNote({required String home, required String city}) =>
      _v('addressCityNoteTemplate')
          .replaceFirst('{home}', home)
          .replaceFirst('{city}', city);

  /// "Not in your total: Doesn't deliver to Erbil", on a store's part of
  /// the cart that cannot come.
  String notInTotal(String reason) => _v('notInTotalTemplate')
      .replaceFirst('{reason}', reason)
      .trim();

  /// "31 products", beside Home's Filters button.
  String productsFound(int count) => counted(count, CountNoun.product);

  /// "Deliver to Erbil", on the Home city button.
  String deliverToCity(String city) =>
      _v('deliverToTemplate').replaceFirst('{city}', city);

  String aboutOrder(String number) =>
      _v('aboutOrderTemplate').replaceFirst('{number}', number);

  /// "12 of 50 used", or "Used 12 times" when there is no limit.
  String couponUsage(int used, int? limit) => limit == null
      ? _v('couponUsedTemplate')
            .replaceFirst('{times}', counted(used, CountNoun.time))
      : _v('couponUsedOfTemplate')
            .replaceFirst('{used}', '$used')
            .replaceFirst('{limit}', '$limit');

  String untilDate(String date) =>
      _v('untilDateTemplate').replaceFirst('{date}', date);

  /// "e.g. 12,500": see BuildContextX.exampleOf.
  String example(String example) =>
      _v('exampleTemplate').replaceFirst('{example}', example);

  /// "Expected: 1–2 days", in a store's box on an order.
  String expectedArrival(String time) =>
      _v('expectedArrivalTemplate').replaceFirst('{time}', time);

  /// Under the order's badge, when more than one store is sending it.
  String orderFollowsSlowest(String status) =>
      _v('orderFollowsSlowestTemplate').replaceFirst('{status}', status);

  /// What a store's account deletion still waits for.
  String storeDeletionAsked(String date) =>
      _v('storeDeletionAskedTemplate').replaceFirst('{date}', date);

  String stillOpenOrders(int count) =>
      _v('stillOpenOrdersTemplate').replaceFirst('{count}', '$count');

  String openReturns(int count) =>
      _v('openReturnsTemplate').replaceFirst('{count}', '$count');

  String stillOwed(String amount) =>
      _v('stillOwedTemplate').replaceFirst('{amount}', amount);

  String returnsOpenUntil(String date) =>
      _v('returnsOpenUntilTemplate').replaceFirst('{date}', date);

  /// "Flash sale until 9:00 PM", on a product its store put on one.
  String flashSaleUntil(String time) =>
      _v('flashSaleUntilTemplate').replaceFirst('{time}', time);

  /// "Paid 2 Sep": a past month's bill, and the day Saba marked it paid.
  String billPaidOn(String date) =>
      _v('billPaidOnTemplate').replaceFirst('{date}', date);

  /// "The normal price is 61,250 IQD.", under the sale price being typed:
  /// the price without the sale, during one too.
  String normalPrice(String price) =>
      _v('normalPriceTemplate').replaceFirst('{price}', price);

  String startsDate(String date) =>
      _v('startsDateTemplate').replaceFirst('{date}', date);

  /// "At Nova Electronics": where a store's coupon can be used.
  String atStore(String store) =>
      _v('atStoreTemplate').replaceFirst('{store}', store);

  String couponsFrom(String store) =>
      _v('couponsFromTemplate').replaceFirst('{store}', store);

  String get storePhone => _v('storePhone');
  String get noteAutoDelivered => _v('noteAutoDelivered');
  String get emptyStoreReturns => _v('emptyStoreReturns');
  String get emptyStoreReturnsMessage => _v('emptyStoreReturnsMessage');
  String get returnNeedsAnswer => _v('returnNeedsAnswer');
  String get returnNeedsCash => _v('returnNeedsCash');

  /// "Not marked Delivered by Thu 9 Oct? Saba marks it delivered then."
  String autoDeliverOn(String date) =>
      _v('autoDeliverOnTemplate').replaceFirst('{date}', date);

  /// The design writes a discount as '− 25%' — a true minus sign and
  /// nothing else. 'off' is still translated and still used by screen
  /// readers through [discountBadgeLabel].
  // Isolated left-to-right: in Arabic a bare leading minus is a neutral
  // character, and the badge rendered as "20%-".
  String discountBadge(String percent) => '\u2066−$percent%\u2069';

  String discountBadgeLabel(String percent) =>
      '$percent% ${_v('off')}';

  /// "Too short. Use at least 2 characters." It said "Too short (2)".
  String minimumLength(int length) => _v('validationMinLengthTemplate')
      .replaceAll('{count}', counted(length, CountNoun.character, genitive: true));

  /// "Resend in 58 seconds"
  String resendAfter(int seconds) => _v('resendInTemplate')
      .replaceFirst('{time}', counted(seconds, CountNoun.second, genitive: true));

  /// "Waiting 3 hours": how long an order has waited for its store.
  String waitingFor(Duration elapsed) => _v('waitingForTemplate').replaceFirst(
    '{time}',
    elapsed.inDays >= 1
        ? counted(elapsed.inDays, CountNoun.day)
        : elapsed.inHours >= 1
        ? counted(elapsed.inHours, CountNoun.hour)
        : counted(elapsed.inMinutes, CountNoun.minute),
  );
}

/// What a count counts, for [AppLocalizations.counted]. Each names the key
/// in the translation files that holds its forms.
enum CountNoun {
  item('nounItem'),
  product('nounProduct'),
  store('nounStore'),
  order('nounOrder'),
  result('nounResult'),
  customer('nounCustomer'),
  returnRequest('nounReturnRequest'),
  day('nounDay'),
  hour('nounHour'),
  minute('nounMinute'),
  second('nounSecond'),
  time('nounTime'),
  character('nounCharacter');

  const CountNoun(this.key);

  final String key;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales
      .any((supported) => supported.languageCode == locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(AppLocalizations(locale));

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
