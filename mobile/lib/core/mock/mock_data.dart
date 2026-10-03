import 'dart:math';

import 'demo_photos.dart';

/// Seed data for demo mode.
///
/// Deliberately plain JSON rather than domain objects: it travels back through
/// the real mappers, so demo mode exercises the same parsing code the backend
/// will feed. A mapping bug shows up here instead of on launch day.
class MockData {
  const MockData._();

  static const String currency = 'IQD';

  static final Random _random = Random(20260317);

  // ------------------------------------------------------------ categories ---

  /// Category tree. Names mirror the seed list in specification section 7,
  /// but nothing is hard-coded in the UI — this arrives over the API like any
  /// other response.
  /// The seven categories version 1 sells, with the sub-categories that
  /// earn their place. Fixed in code for now; the real admin panel has to be
  /// able to add and rename them (`ADMIN_REQUIREMENTS.md`).
  ///
  /// No `productCount`: the numbers here were invented - Cameras claimed 10
  /// and had one product - and a count nobody keeps true is worse than no
  /// count. The screens work it out from the catalogue.
  static final List<Map<String, dynamic>> categories = <Map<String, dynamic>>[
    {
      'id': 'c-phones',
      'name': 'Phones',
      'nameAr': 'هواتف',
      'imageUrl': _photo('phones', 0),
      'children': [
        {'id': 'c-smartphones', 'name': 'Smartphones', 'nameAr': 'هواتف ذكية'},
        {'id': 'c-tablets', 'name': 'Tablets', 'nameAr': 'أجهزة لوحية'},
      ],
    },
    {
      'id': 'c-laptops',
      'name': 'Laptops',
      'nameAr': 'حواسيب محمولة',
      'imageUrl': _photo('laptops', 0),
      'children': [
        {'id': 'c-ultrabooks', 'name': 'Ultrabooks', 'nameAr': 'حواسيب نحيفة'},
        {
          'id': 'c-gaming-laptops',
          'name': 'Gaming laptops',
          'nameAr': 'حواسيب ألعاب',
        },
      ],
    },
    {
      'id': 'c-headphones',
      'name': 'Headphones',
      'nameAr': 'سماعات',
      'imageUrl': _photo('headphones', 0),
      'children': [],
    },
    {
      'id': 'c-watches',
      'name': 'Smartwatches',
      'nameAr': 'ساعات ذكية',
      'imageUrl': _photo('smartwatches', 0),
      'children': [],
    },
    {
      'id': 'c-cameras',
      'name': 'Cameras',
      'nameAr': 'كاميرات',
      'imageUrl': _photo('cameras', 0),
      'children': [],
    },
    {
      'id': 'c-home',
      'name': 'Home appliances',
      'nameAr': 'أجهزة منزلية',
      'imageUrl': _photo('home-appliances', 0),
      'children': [],
    },
    {
      'id': 'c-accessories',
      'name': 'Accessories',
      'nameAr': 'إكسسوارات',
      'imageUrl': _photo('accessories', 0),
      'children': [
        {
          'id': 'c-phone-cases',
          'name': 'Cases & Covers',
          'nameAr': 'أغطية وحافظات',
        },
        {'id': 'c-chargers', 'name': 'Chargers', 'nameAr': 'شواحن'},
      ],
    },
  ];

  /// Demo products their store keeps off sale, so every shelf tab of the
  /// two demo store logins has something in it: waiting, draft or rejected
  /// by Saba, or hidden by the store. Shoppers never see them.
  static const Map<String, String> seededStatus = <String, String>{
    // Nova
    'p-50': 'PENDING',
    'p-42': 'DRAFT',
    'p-41': 'REJECTED',
    // Atlas
    'p-4': 'PENDING',
    'p-10': 'DRAFT',
    'p-56': 'REJECTED',
  };
  static const Set<String> seededHidden = <String>{'p-51'};

  /// The demo's flash sales: a few of the stores' real discounts, and the
  /// hour, counted from when the app opens, each one ends on. Each ends at
  /// its own time, and then its price is what it was before the sale.
  static const Map<String, int> seededFlashSales = <String, int>{
    'p-7': 3, // Nova
    'p-1': 16, // Nova's phone, sold in options
    'p-21': 5,
    'p-37': 8,
    'p-45': 12,
    'p-31': 20,
    'p-22': 30,
  };

  /// Whether a demo product starts the demo on sale.
  static bool startsOnSale(Object? id) =>
      !seededStatus.containsKey(id) && !seededHidden.contains(id);

  static const List<Map<String, dynamic>> brands = <Map<String, dynamic>>[
    {'id': 'b-nova', 'name': 'Nova', 'productCount': 14},
    {'id': 'b-lumen', 'name': 'Lumen', 'productCount': 11},
    {'id': 'b-atlas', 'name': 'Atlas', 'productCount': 9},
    {'id': 'b-kite', 'name': 'Kite Audio', 'productCount': 7},
    {'id': 'b-orbit', 'name': 'Orbit', 'productCount': 5},
  ];

  /// Category-scoped attributes, which drive the dynamic filter sheet and the
  /// merchant product form (specification section 9).
  static const Map<String, List<Map<String, dynamic>>> attributesByCategory =
      <String, List<Map<String, dynamic>>>{
        'c-phones': [
          {
            'id': 'a-ram',
            'name': 'RAM',
            'type': 'SELECT',
            'unit': 'GB',
            'isFilterable': true,
            'values': [
              {'id': 'v-6', 'value': '6'},
              {'id': 'v-8', 'value': '8'},
              {'id': 'v-12', 'value': '12'},
            ],
          },
          {
            'id': 'a-storage',
            'name': 'Storage',
            'type': 'SELECT',
            'isFilterable': true,
            'isVariantOption': true,
            'values': [
              {'id': 'v-128', 'value': '128GB'},
              {'id': 'v-256', 'value': '256GB'},
              {'id': 'v-512', 'value': '512GB'},
            ],
          },
          {
            'id': 'a-color',
            'name': 'Color',
            'type': 'SELECT',
            'isFilterable': true,
            'isVariantOption': true,
            'values': [
              {'id': 'v-black', 'value': 'Black'},
              {'id': 'v-silver', 'value': 'Silver'},
              {'id': 'v-blue', 'value': 'Blue'},
            ],
          },
        ],
        'c-laptops': [
          {
            'id': 'a-cpu',
            'name': 'CPU',
            'type': 'SELECT',
            'isFilterable': true,
            'values': [
              {'id': 'v-i5', 'value': 'Core i5'},
              {'id': 'v-i7', 'value': 'Core i7'},
            ],
          },
          {
            'id': 'a-screen',
            'name': 'Screen Size',
            'type': 'SELECT',
            'unit': 'in',
            'isFilterable': true,
            'values': [
              {'id': 'v-14', 'value': '14'},
              {'id': 'v-16', 'value': '16'},
            ],
          },
        ],
      };

  // ------------------------------------------------------------- merchants ---

  static const List<Map<String, dynamic>> merchants = <Map<String, dynamic>>[
    {
      'id': 'm-1',
      'storeName': 'Nova Electronics',
      'logoUrl': 'assets/images/stores/nova-logo.jpg',
      'bannerUrl': 'assets/images/stores/nova-banner.jpg',
      'rating': 4.6,
      'reviewCount': 318,
      'productCount': 22,
      'description': 'Authorised reseller for phones, laptops and audio.',
      'descriptionAr': 'وكيل معتمد للهواتف والحواسيب والصوتيات.',
      'country': 'Iraq',
      'city': 'Baghdad',
      'governorate': 'BAGHDAD',
      'businessAddress': 'Al-Mansour, Street 14',
      'businessAddressAr': 'المنصور، شارع 14',
    },
    {
      'id': 'm-2',
      'storeName': 'Atlas Home',
      'logoUrl': 'assets/images/stores/atlas-logo.jpg',
      'bannerUrl': 'assets/images/stores/atlas-banner.jpg',
      'rating': 4.3,
      'reviewCount': 142,
      'productCount': 18,
      'description': 'Home appliances and kitchen essentials.',
      'descriptionAr': 'أجهزة منزلية ولوازم المطبخ.',
      'country': 'Iraq',
      'city': 'Basra',
      'governorate': 'BASRA',
      'businessAddress': 'Corniche Street, Al-Ashar',
      'businessAddressAr': 'شارع الكورنيش، العشار',
    },
    // Stores in the north, so Home's city chips have somewhere to go. Nova and
    // Atlas stay the two demo logins, with the same twelve products as
    // before: nothing below is assigned to them.
    {
      'id': 'm-3',
      'storeName': 'Zakho Mobile',
      'logoUrl': 'assets/images/stores/store-3-logo.jpg',
      'bannerUrl': 'assets/images/stores/store-3-banner.jpg',
      'rating': 4.5,
      'reviewCount': 96,
      'productCount': 5,
      'description':
          'Phones and accessories, delivered across Duhok the same day.',
      'descriptionAr': 'هواتف وإكسسوارات، توصيل في دهوك في نفس اليوم.',
      'country': 'Iraq',
      'city': 'Duhok',
      'governorate': 'DUHOK',
      'businessAddress': 'Kawa Street, Duhok',
      'businessAddressAr': 'شارع كاوا، دهوك',
      // Where it sends and at what price, as the store would set it.
      'delivery': {
        'governorates': ['DUHOK', 'ERBIL', 'NINEVEH'],
        'feeInside': 3000,
        'timeInside': 'SAME_DAY',
        'feeOutside': 5000,
        'timeOutside': '1_2_DAYS',
      },
    },
    {
      'id': 'm-4',
      'storeName': 'Duhok Home Center',
      'logoUrl': 'assets/images/stores/store-4-logo.jpg',
      'bannerUrl': 'assets/images/stores/store-4-banner.jpg',
      'rating': 4.2,
      'reviewCount': 57,
      'productCount': 4,
      'description': 'Coolers, fans and kitchen appliances for every home.',
      'descriptionAr': 'مبردات ومراوح وأجهزة مطبخ لكل بيت.',
      'country': 'Iraq',
      'city': 'Duhok',
      'governorate': 'DUHOK',
      'businessAddress': 'Nohadra Street, Duhok',
      'businessAddressAr': 'شارع نوهدرا، دهوك',
      // Where it sends and at what price, as the store would set it.
      'delivery': {
        'governorates': ['DUHOK', 'ERBIL', 'SULAYMANIYAH'],
        'feeInside': 4000,
        'timeInside': '1_2_DAYS',
        'feeOutside': 7000,
        'timeOutside': '2_3_DAYS',
      },
    },
    {
      'id': 'm-5',
      'storeName': 'Citadel Electronics',
      'logoUrl': 'assets/images/stores/store-5-logo.jpg',
      'bannerUrl': 'assets/images/stores/store-5-banner.jpg',
      'rating': 4.7,
      'reviewCount': 211,
      'productCount': 5,
      'description': 'Laptops and computer accessories, sent anywhere in Iraq.',
      'descriptionAr': 'حواسيب محمولة وملحقاتها، توصيل إلى كل العراق.',
      'country': 'Iraq',
      'city': 'Erbil',
      'governorate': 'ERBIL',
      'businessAddress': '100 Meter Road, Erbil',
      'businessAddressAr': 'شارع 100 متر، أربيل',
      // Where it sends and at what price, as the store would set it.
      'delivery': {
        'governorates': [
          'BAGHDAD',
          'BASRA',
          'NINEVEH',
          'ERBIL',
          'SULAYMANIYAH',
          'DUHOK',
          'KIRKUK',
          'NAJAF',
          'KARBALA',
          'BABYLON',
          'ANBAR',
          'DHI_QAR',
          'DIYALA',
          'SALAH_AL_DIN',
          'WASIT',
          'MAYSAN',
          'QADISIYAH',
          'MUTHANNA',
          'HALABJA',
        ],
        'feeInside': 3000,
        'timeInside': 'SAME_DAY',
        'feeOutside': 6000,
        'timeOutside': '2_3_DAYS',
      },
    },
    {
      'id': 'm-6',
      'storeName': 'Erbil Cool Air',
      'logoUrl': 'assets/images/stores/store-6-logo.jpg',
      'bannerUrl': 'assets/images/stores/store-6-banner.jpg',
      'rating': 4.4,
      'reviewCount': 88,
      'productCount': 5,
      'description': 'Air conditioners and fans, installed in Erbil.',
      'descriptionAr': 'مكيفات ومراوح، مع التركيب في أربيل.',
      'country': 'Iraq',
      'city': 'Erbil',
      'governorate': 'ERBIL',
      'businessAddress': 'Iskan, Erbil',
      'businessAddressAr': 'الإسكان، أربيل',
      // Where it sends and at what price, as the store would set it.
      'delivery': {
        'governorates': ['ERBIL', 'DUHOK', 'SULAYMANIYAH', 'KIRKUK'],
        'feeInside': 5000,
        'timeInside': '1_2_DAYS',
        'feeOutside': 8000,
        'timeOutside': '2_3_DAYS',
      },
    },
    {
      'id': 'm-7',
      'storeName': 'Slemani Gadgets',
      'logoUrl': 'assets/images/stores/store-7-logo.jpg',
      'bannerUrl': 'assets/images/stores/store-7-banner.jpg',
      'rating': 4.6,
      'reviewCount': 134,
      'productCount': 5,
      'description': 'Phones, tablets and gadgets.',
      'descriptionAr': 'هواتف وأجهزة لوحية وأجهزة ذكية.',
      'country': 'Iraq',
      'city': 'Sulaymaniyah',
      'governorate': 'SULAYMANIYAH',
      'businessAddress': 'Salim Street, Sulaymaniyah',
      'businessAddressAr': 'شارع سالم، السليمانية',
      // Where it sends and at what price, as the store would set it.
      'delivery': {
        'governorates': ['SULAYMANIYAH', 'HALABJA', 'ERBIL', 'KIRKUK'],
        'feeInside': 3000,
        'timeInside': 'SAME_DAY',
        'feeOutside': 6000,
        'timeOutside': '1_2_DAYS',
      },
    },
    {
      'id': 'm-8',
      'storeName': 'Mosul Appliances',
      'logoUrl': 'assets/images/stores/store-8-logo.jpg',
      'bannerUrl': 'assets/images/stores/store-8-banner.jpg',
      'rating': 4.3,
      'reviewCount': 75,
      'productCount': 4,
      'description': 'Washing machines, fridges and cookers.',
      'descriptionAr': 'غسالات وثلاجات وطباخات.',
      'country': 'Iraq',
      'city': 'Mosul',
      'governorate': 'NINEVEH',
      'businessAddress': 'Al-Faisaliya, Mosul',
      'businessAddressAr': 'الفيصلية، الموصل',
      // Where it sends and at what price, as the store would set it.
      'delivery': {
        'governorates': ['NINEVEH', 'DUHOK', 'ERBIL', 'KIRKUK', 'BAGHDAD'],
        'feeInside': 4000,
        'timeInside': '1_2_DAYS',
        'feeOutside': 7000,
        'timeOutside': '3_5_DAYS',
      },
    },
  ];

  // -------------------------------------------------------------- products ---

  /// Nova Electronics' and Atlas Home's own, alternating as they always have
  /// (p-1 Nova, p-2 Atlas, ...): name, Arabic name, category, brand, price,
  /// the price before a discount, and what it is sold in.
  ///
  /// Written out, not worked out. A formula made the 65W charger cost
  /// 519,000 IQD and the phone 49,000; a rotating brand put "Atlas" on
  /// Nova's laptop; the first four all had a phone's options, laptops too;
  /// and Atlas Home sold phones and laptops while Nova sold Atlas's air
  /// purifier. The Arabic names keep letters people type another way (أ, ة,
  /// ّ) on purpose, for search.
  static const List<(String, String, String, String, int, int?, _Sold)>
  _firstProducts = [
    (
      'Nova X5 Smartphone',
      'هاتف نوفا X5 الذكي',
      'c-smartphones',
      'b-nova',
      329000,
      389000,
      _Sold.phone,
    ),
    (
      'Atlas Air Fryer 5L',
      'قلاية هوائية أطلس 5 لتر',
      'c-home',
      'b-atlas',
      95000,
      null,
      _Sold.plain,
    ),
    (
      'Lumen Book 14 Ultrabook',
      'حاسوب لومن بوك 14 النحيف',
      'c-ultrabooks',
      'b-lumen',
      675000,
      null,
      _Sold.laptop,
    ),
    (
      'Atlas Steam Iron',
      'مكواة بخار أطلس',
      'c-home',
      'b-atlas',
      32000,
      38000,
      _Sold.plain,
    ),
    (
      'Kite Audio Studio Headphones',
      'سماعات كايت أوديو ستوديو',
      'c-headphones',
      'b-kite',
      145000,
      null,
      _Sold.plain,
    ),
    (
      'Atlas Robot Vacuum',
      'مكنسة روبوت أطلس',
      'c-home',
      'b-atlas',
      265000,
      null,
      _Sold.plain,
    ),
    (
      'Nova Watch Series 4',
      'ساعة نوفا الذكية الإصدار 4',
      'c-watches',
      'b-nova',
      189000,
      229000,
      _Sold.plain,
    ),
    (
      'Atlas Stand Mixer',
      'عجّانة أطلس الكهربائية',
      'c-home',
      'b-atlas',
      145000,
      null,
      _Sold.plain,
    ),
    (
      'Orbit Mirrorless Camera',
      'كاميرا أوربت بدون مرآة',
      'c-cameras',
      'b-orbit',
      950000,
      null,
      _Sold.plain,
    ),
    (
      'Atlas Espresso Machine',
      'ماكينة إسبريسو أطلس',
      'c-home',
      'b-atlas',
      185000,
      219000,
      _Sold.plain,
    ),
    (
      'Nova Fast Charger 65W',
      'شاحن نوفا السريع 65 واط',
      'c-chargers',
      'b-nova',
      25000,
      null,
      _Sold.plain,
    ),
    (
      'Atlas Rice Cooker',
      'طباخة رز أطلس',
      'c-home',
      'b-atlas',
      45000,
      null,
      _Sold.plain,
    ),
  ];

  /// The northern stores' products: name, Arabic name, category, store,
  /// price and the price before a discount. Named so no word the search
  /// tests look for (Nova, Atlas, ساعة...) is in them.
  static const List<(String, String, String, String, int, int?)>
  _moreProducts = [
    (
      'Zagros Z10 Smartphone',
      'هاتف زاغروس Z10 الذكي',
      'c-smartphones',
      'm-3',
      289000,
      339000,
    ),
    (
      'Zagros Z10 Clear Case',
      'غطاء شفاف لهاتف زاغروس Z10',
      'c-phone-cases',
      'm-3',
      9000,
      null,
    ),
    (
      'Tigris Power Bank 20000mAh',
      'باور بانك دجلة 20000 ملي أمبير',
      'c-chargers',
      'm-3',
      32000,
      null,
    ),
    (
      'Zagros Z7 Smartphone',
      'هاتف زاغروس Z7',
      'c-smartphones',
      'm-3',
      199000,
      null,
    ),
    (
      'Leather Flip Cover',
      'غطاء جلد قلاب',
      'c-phone-cases',
      'm-3',
      12500,
      15000,
    ),
    (
      'Gara Air Cooler 60L',
      'مبردة هواء كارا 60 لتر',
      'c-home',
      'm-4',
      245000,
      280000,
    ),
    ('Gara Standing Fan', 'مروحة كارا عمودية', 'c-home', 'm-4', 55000, null),
    (
      'Khabur Water Heater 50L',
      'سخان ماء خابور 50 لتر',
      'c-home',
      'm-4',
      175000,
      null,
    ),
    (
      'Khabur Electric Kettle',
      'غلاية كهربائية خابور',
      'c-home',
      'm-4',
      22500,
      27500,
    ),
    (
      'Citadel Book 15 Laptop',
      'حاسوب سيتادل بوك 15',
      'c-ultrabooks',
      'm-5',
      690000,
      790000,
    ),
    (
      'Citadel Gamer 17',
      'حاسوب ألعاب سيتادل 17',
      'c-gaming-laptops',
      'm-5',
      1250000,
      null,
    ),
    (
      'Citadel Book Air 13',
      'حاسوب سيتادل بوك إير 13',
      'c-ultrabooks',
      'm-5',
      540000,
      null,
    ),
    (
      'Erbil Fit Band 3',
      'سوار أربيل الرياضي 3',
      'c-watches',
      'm-5',
      45000,
      55000,
    ),
    (
      'Wireless Mouse and Keyboard Set',
      'طقم فأرة ولوحة مفاتيح لاسلكي',
      'c-accessories',
      'm-5',
      35000,
      null,
    ),
    (
      'Frost Split AC 1.5 Ton',
      'مكيف سبليت فروست 1.5 طن',
      'c-home',
      'm-6',
      620000,
      700000,
    ),
    (
      'Frost Split AC 2 Ton',
      'مكيف سبليت فروست 2 طن',
      'c-home',
      'm-6',
      780000,
      null,
    ),
    ('Frost Portable AC', 'مكيف فروست متنقل', 'c-home', 'm-6', 410000, null),
    ('Frost Ceiling Fan', 'مروحة سقفية فروست', 'c-home', 'm-6', 48000, null),
    (
      'Frost Voltage Stabiliser',
      'منظم فولتية فروست',
      'c-home',
      'm-6',
      60000,
      72000,
    ),
    (
      'Sirwan S8 Smartphone',
      'هاتف سيروان S8 الذكي',
      'c-smartphones',
      'm-7',
      355000,
      null,
    ),
    (
      'Sirwan Kids Tablet',
      'تابلت سيروان للأطفال',
      'c-tablets',
      'm-7',
      120000,
      150000,
    ),
    (
      'Goizha Fitness Band',
      'سوار كويزة الرياضي',
      'c-watches',
      'm-7',
      39000,
      null,
    ),
    (
      'Magnetic Car Phone Holder',
      'حامل هاتف مغناطيسي للسيارة',
      'c-accessories',
      'm-7',
      15000,
      null,
    ),
    (
      'Sirwan Game Controller',
      'ذراع ألعاب سيروان',
      'c-accessories',
      'm-7',
      42500,
      null,
    ),
    (
      'Hadba Washing Machine 9kg',
      'غسالة الحدباء 9 كغم',
      'c-home',
      'm-8',
      385000,
      430000,
    ),
    (
      'Hadba Refrigerator 18ft',
      'ثلاجة الحدباء 18 قدم',
      'c-home',
      'm-8',
      720000,
      null,
    ),
    (
      'Hadba Gas Cooker 5 Burners',
      'طباخ غاز الحدباء 5 عيون',
      'c-home',
      'm-8',
      265000,
      null,
    ),
    (
      'Hadba Microwave 30L',
      'مايكروويف الحدباء 30 لتر',
      'c-home',
      'm-8',
      98000,
      115000,
    ),
    // Cameras had one product in the whole shop, headphones two and
    // smartwatches three, while home appliances had twelve. These fill the
    // thin shelves, spread over the stores and cities that would really
    // sell them.
    (
      'Orbit Action Camera 4K',
      'كاميرا أوربت أكشن 4K',
      'c-cameras',
      'm-1',
      215000,
      249000,
    ),
    (
      'Orbit Security Camera Indoor',
      'كاميرا أوربت للمراقبة الداخلية',
      'c-cameras',
      'm-1',
      48000,
      null,
    ),
    (
      'Sirwan Dash Camera',
      'كاميرا سروان للسيارة',
      'c-cameras',
      'm-7',
      72000,
      89000,
    ),
    (
      'Citadel Webcam 1080p',
      'كاميرا ويب سيتاديل 1080p',
      'c-cameras',
      'm-5',
      35000,
      null,
    ),
    (
      'Zagros Wireless Earbuds',
      'سماعات زاغروس اللاسلكية',
      'c-headphones',
      'm-3',
      42000,
      55000,
    ),
    (
      'Goizha Over-Ear Headphones',
      'سماعات كويژة فوق الأذن',
      'c-headphones',
      'm-7',
      78000,
      null,
    ),
    (
      'Citadel Gaming Headset',
      'سماعة ألعاب سيتاديل',
      'c-headphones',
      'm-5',
      65000,
      79000,
    ),
    // A speaker is not headphones.
    (
      'Tigris Bluetooth Speaker',
      'مكبر صوت دجلة بلوتوث',
      'c-accessories',
      'm-3',
      39000,
      null,
    ),
    (
      'Zagros Smartwatch Pro',
      'ساعة زاغروس الذكية برو',
      'c-watches',
      'm-3',
      125000,
      149000,
    ),
    ('Nova Watch Lite', 'ساعة نوفا لايت', 'c-watches', 'm-1', 89000, null),
    ('Nova Tab 11', 'جهاز نوفا اللوحي 11', 'c-tablets', 'm-1', 310000, 359000),
    (
      'Citadel Tab Go',
      'جهاز سيتاديل اللوحي جو',
      'c-tablets',
      'm-5',
      165000,
      null,
    ),
    // Mosul Appliances sells appliances; it had a laptop stand.
    (
      'Hadba Electric Oven 45L',
      'فرن كهربائي الحدباء 45 لتر',
      'c-home',
      'm-8',
      95000,
      null,
    ),
    (
      'Gara Laptop Cooling Pad',
      'قاعدة تبريد حاسوب گارا',
      'c-accessories',
      'm-4',
      22000,
      27000,
    ),
    // Erbil Cool Air sells air conditioning; it had a phone charger.
    (
      'Frost AC Outdoor Cover',
      'غطاء الوحدة الخارجية لمكيف فروست',
      'c-home',
      'm-6',
      18000,
      null,
    ),
    ('Atlas Kitchen Blender', 'خلاط أطلس للمطبخ', 'c-home', 'm-2', 54000, null),
  ];

  /// Every product in the demo catalogue, built once.
  static final List<Map<String, dynamic>> products = List.generate(
    _firstProducts.length + _moreProducts.length,
    _buildProduct,
    growable: false,
  );

  static Map<String, dynamic> _buildProduct(int index) {
    final id = 'p-${index + 1}';
    // The first twelve alternate Nova and Atlas, as they always have; the
    // rest are the northern stores', each named in [_moreProducts].
    final first = index < _firstProducts.length ? _firstProducts[index] : null;
    final more = first == null
        ? _moreProducts[index - _firstProducts.length]
        : null;
    final name = first?.$1 ?? more!.$1;
    // Iraqi prices: whole thousands of dinars, never decimals.
    final price = (first?.$5 ?? more!.$5).toDouble();
    final originalPrice = (first == null ? more!.$6 : first.$6)?.toDouble();
    final merchant = first != null
        ? merchants[index % 2]
        : merchants.firstWhere((store) => store['id'] == more!.$4);
    final brand = first == null
        ? null
        : brands.firstWhere((brand) => brand['id'] == first.$4);
    final stock = index % 7 == 5 ? 0 : 3 + (index * 5) % 40;
    final sold = first?.$7 ?? _Sold.plain;
    final categoryId = first?.$3 ?? more!.$3;
    final photo = _photoFor(categoryId, index);
    // On the hour, as a store would set it.
    final now = DateTime.now();
    final saleEndsAt = switch (seededFlashSales[id]) {
      final hours? => DateTime(
        now.year,
        now.month,
        now.day,
        now.hour + hours,
      ).toUtc().toIso8601String(),
      null => null,
    };

    return <String, dynamic>{
      'id': id,
      'name': name,
      'nameEn': name,
      'nameAr': first?.$2 ?? more!.$2,
      // Four days apart, the twelfth newest; the northern stores' older.
      'createdAt': DateTime.now()
          .subtract(
            Duration(
              days: first != null
                  ? (_firstProducts.length - index) * 4
                  : 5 + (index - _firstProducts.length) * 2,
            ),
          )
          .toIso8601String(),
      // What a shopper reads under the product. It said "A demo product
      // used while the backend is being built", in English, to a client.
      'description':
          'Sold and delivered by its store. Pay in cash when it arrives, and '
          'return it within 7 days if it is not right.',
      'descriptionAr':
          'يبيعه المتجر ويوصله إليك. ادفع نقدًا عند الاستلام، ويمكنك إرجاعه '
          'خلال 7 أيام إن لم يكن مناسبًا.',
      'price': price,
      'originalPrice': ?originalPrice,
      'discountPercentage': ?(originalPrice == null
          ? null
          : ((1 - price / originalPrice) * 100).round()),
      'saleEndsAt': ?saleEndsAt,
      'currencyCode': currency,
      'stockStatus': stock == 0
          ? 'OUT_OF_STOCK'
          : stock < 6
          ? 'LOW_STOCK'
          : 'IN_STOCK',
      'availableQuantity': stock,
      'sku': 'SKU-${1000 + index}',
      'barcode': '628${100000 + index}',
      'categoryId': categoryId,
      'brand': ?brand,
      'merchant': merchant,
      'imageUrl': photo,
      'images': [
        if (photo != null)
          for (var image = 0; image < 3; image++)
            {'id': '$id-img$image', 'url': photo, 'isPrimary': image == 0},
      ],
      // What its kind would carry: every product said 12 months, a 9,000
      // IQD phone case too (the tester). A case, or anything that cheap,
      // none; chargers and other accessories 6 months.
      ...switch ((categoryId, price)) {
        ('c-phone-cases', _) || (_, < 20000) => const <String, dynamic>{},
        ('c-chargers' || 'c-accessories', _) => const <String, dynamic>{
          'warranty': '6 months manufacturer warranty',
          'warrantyAr': 'ضمان الشركة المصنّعة لمدة 6 أشهر',
        },
        _ => const <String, dynamic>{
          'warranty': '12 months manufacturer warranty',
          'warrantyAr': 'ضمان الشركة المصنّعة لمدة 12 شهرًا',
        },
      },
      if (sold != _Sold.plain) ...<String, dynamic>{
        'variants': _variantsFor(id, sold, price, stock, photo, originalPrice),
        // The shape the backend will supply: an option value to the colour it
        // actually is, so the design's swatches have something to paint.
        'optionColours': <String, String>{
          'Black': '#14181D',
          'Silver': '#C3CAD3',
          if (sold == _Sold.phone) 'Blue': '#1A56C4',
        },
        if (sold == _Sold.phone)
          'sizeGuide':
              'Measurements are taken flat, in centimetres.\n\n'
              '128GB - 146 x 71 x 7.6 mm, 172 g\n'
              '256GB - 146 x 71 x 7.6 mm, 174 g\n\n'
              'If you are between two options, take the larger one.',
      },
    };
  }

  /// The [index]th photo of a demo category, going round when it has fewer
  /// photos than products; null while it has none. Written by
  /// `tool/demo_photos.py`.
  static String? _photo(String group, int index) {
    final count = demoPhotoCounts[group] ?? 0;
    return count == 0
        ? null
        : 'assets/images/products/$group-${index % count + 1}.jpg';
  }

  /// Its top-level category's photo, for a product in [categoryId]: one
  /// shared photo per category, which reads as a placeholder until a store
  /// uploads its own. Photos rotated within a category put an air fryer on
  /// a fridge and a keyboard on a charger, which read as mistakes.
  static String? _photoFor(String categoryId, int index) {
    const groups = <String, String>{
      'c-phones': 'phones',
      'c-laptops': 'laptops',
      'c-headphones': 'headphones',
      'c-watches': 'smartwatches',
      'c-cameras': 'cameras',
      'c-home': 'home-appliances',
      'c-accessories': 'accessories',
    };
    final top = categories.firstWhere(
      (category) =>
          category['id'] == categoryId ||
          (category['children'] as List).any(
            (child) => (child as Map)['id'] == categoryId,
          ),
    );
    return _photo(groups[top['id']]!, index);
  }

  /// A phone in three colours and two sizes; a laptop in two colours and
  /// two sizes, the larger dearer by what it costs.
  static List<Map<String, dynamic>> _variantsFor(
    String productId,
    _Sold sold,
    double basePrice,
    int stock,
    String? photo,
    double? originalPrice,
  ) {
    final phone = sold == _Sold.phone;
    final colors = phone
        ? const <String>['Black', 'Silver', 'Blue']
        : const <String>['Silver', 'Black'];
    final storages = phone
        ? const <String>['128GB', '256GB']
        : const <String>['512GB', '1TB'];

    final variants = <Map<String, dynamic>>[];
    var index = 0;

    for (final color in colors) {
      for (final storage in storages) {
        final extra = storage == storages.last ? (phone ? 80000 : 120000) : 0;
        // One deliberately sold-out combination, so the UI's out-of-stock path
        // is reachable in demo mode.
        final variantStock = (color == colors.last && storage == storages.last)
            ? 0
            : stock;

        variants.add(<String, dynamic>{
          'id': '$productId-v$index',
          'sku': 'SKU-$productId-$index',
          'price': basePrice + extra,
          // Its own original, when the product is on sale: the same saving
          // on the dearer option, and a badge that is true for it.
          if (originalPrice != null) 'originalPrice': originalPrice + extra,
          if (originalPrice != null)
            'discountPercentage':
                ((1 - (basePrice + extra) / (originalPrice + extra)) * 100)
                    .round(),
          'availableQuantity': variantStock,
          'stockStatus': variantStock == 0 ? 'OUT_OF_STOCK' : 'IN_STOCK',
          'options': {'Color': color, 'Storage': storage},
          'imageUrl': photo,
        });
        index++;
      }
    }
    return variants;
  }

  static Map<String, dynamic>? productById(String id) {
    for (final product in products) {
      if (product['id'] == id) return product;
    }
    return null;
  }

  /// Slims a full product down to the shape a card needs.
  static Map<String, dynamic> summaryOf(Map<String, dynamic> product) {
    return <String, dynamic>{
      'id': product['id'],
      'name': product['name'],
      'nameAr': product['nameAr'],
      'createdAt': product['createdAt'],
      'price': product['price'],
      'originalPrice': product['originalPrice'],
      'discountPercentage': product['discountPercentage'],
      'saleEndsAt': product['saleEndsAt'],
      'currencyCode': product['currencyCode'],
      'stockStatus': product['stockStatus'],
      'availableQuantity': product['availableQuantity'],
      'imageUrl': product['imageUrl'],
      'merchant': product['merchant'],
      'brand': product['brand'],
      'hasVariants': (product['variants'] as List?)?.isNotEmpty ?? false,
    };
  }

  static List<Map<String, dynamic>> get productSummaries =>
      products.map(summaryOf).toList(growable: false);

  // ------------------------------------------------------------------ home ---

  /// The pictures the admin puts at the top of Home. Every other section
  /// is worked out from the catalogue and the orders, by the server.
  static const List<Map<String, dynamic>> homeBanners = <Map<String, dynamic>>[
    // Pictures the admin uploads, each linked to a product, a store or a
    // category, or to nothing (link null), as the server sends them. The
    // words are what a screen reader says, and what shows until the
    // photograph is there. The demo has no photographs for these on
    // purpose: the offer is printed in the picture, and a picture cannot
    // switch to Arabic, so the demo shows the words in both languages.
    {
      'id': 'ban-1',
      'title': 'Mid-season sale',
      'subtitle': 'Up to 40% off selected electronics',
      'link': null,
    },
    {
      'id': 'ban-2',
      'title': 'New arrivals',
      'subtitle': 'Fresh from our merchants',
      'link': null,
    },
    {
      'id': 'ban-3',
      'title': 'Free delivery week',
      'subtitle': 'On orders over 50,000 IQD',
      'link': null,
    },
    {
      'id': 'ban-4',
      'title': 'Home and kitchen',
      'subtitle': 'Up to 50% off appliances',
      'link': {'type': 'CATEGORY', 'id': 'c-home'},
    },
  ];

  // ----------------------------------------------------------------- users ---

  /// The second demo store's owner, who runs Atlas Home. Every other
  /// "merchant" address opens Nova Electronics, as it always has.
  static const String secondMerchantEmail = 'merchant2@saba.app';

  /// The demo accounts by phone, the way people sign in: Amina the shopper,
  /// Omar of Nova Electronics, Layla of Atlas Home.
  static const Map<String, String> demoPhones = <String, String>{
    '+9647701234567': 'shopper@saba.app',
    '+9647711234567': 'merchant@saba.app',
    '+9647801234567': secondMerchantEmail,
    '+9647709999999': adminEmail,
  };

  /// Any credentials are accepted in demo mode. An address containing
  /// "merchant" signs in to the merchant experience, which is how both shells
  /// stay reachable without a backend.
  /// Saba's own staff. Not shown on the sign-in screen with the others:
  /// it is there for whoever runs the demo, not for whoever is watching it.
  static const String adminEmail = 'admin@saba.app';

  static Map<String, dynamic> userFor(String email) {
    if (email.toLowerCase() == adminEmail) {
      return <String, dynamic>{
        'id': 'u-admin',
        'fullName': 'Saba admin',
        'email': adminEmail,
        'phone': '+9647709999999',
        'role': 'ADMIN',
        'status': 'ACTIVE',
        'isEmailVerified': true,
        'country': 'Iraq',
        'city': 'Baghdad',
        'avatarUrl': null,
      };
    }
    final isMerchant = email.toLowerCase().contains('merchant');
    final isSecond = email.toLowerCase() == secondMerchantEmail;
    final store = merchants[isSecond ? 1 : 0];

    return <String, dynamic>{
      'id': !isMerchant
          ? 'u-customer'
          : isSecond
          ? 'u-merchant-2'
          : 'u-merchant',
      'fullName': !isMerchant
          ? 'Amina Saleh'
          : isSecond
          ? 'Layla Kareem'
          : 'Omar Al-Sayed',
      'email': email.isEmpty ? 'demo@saba.app' : email,
      'phone': !isMerchant
          ? '+9647701234567'
          : isSecond
          ? '+9647801234567'
          : '+9647711234567',
      'role': isMerchant ? 'MERCHANT' : 'CUSTOMER',
      'status': 'ACTIVE',
      'isEmailVerified': true,
      'country': 'Iraq',
      'city': isSecond ? 'Basra' : 'Baghdad',
      'avatarUrl': null,
      if (isMerchant)
        'merchant': {
          'id': store['id'],
          'storeName': store['storeName'],
          'status': 'APPROVED',
          'logoUrl': store['logoUrl'],
          'rating': store['rating'],
        },
    };
  }

  static Map<String, dynamic> tokensFor(String email) => <String, dynamic>{
    'accessToken': 'demo-access-token',
    'refreshToken': 'demo-refresh-token',
    'expiresIn': 3600,
  };

  static int randomInt(int max) => _random.nextInt(max);
}

/// What a demo product is sold in.
enum _Sold { plain, phone, laptop }
