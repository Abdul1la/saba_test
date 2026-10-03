import 'package:flutter/material.dart';

import '../theme/saba_icons.dart';
import '../utils/context_extensions.dart';
import '../utils/formatters.dart';
import 'governorate.dart';
import 'governorate_picker.dart';

/// How long a store takes to deliver: one of a few choices, so every store
/// says it the same way, in both languages.
enum DeliveryTime {
  sameDay('SAME_DAY'),
  oneToTwoDays('1_2_DAYS'),
  twoToThreeDays('2_3_DAYS'),
  threeToFiveDays('3_5_DAYS'),
  fiveToSevenDays('5_7_DAYS');

  const DeliveryTime(this.apiValue);

  final String apiValue;

  static DeliveryTime? fromApi(Object? value) {
    for (final time in values) {
      if (time.apiValue == value) return time;
    }
    return null;
  }

  String label(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      sameDay => l10n.deliverySameDay,
      oneToTwoDays => l10n.delivery1to2Days,
      twoToThreeDays => l10n.delivery2to3Days,
      threeToFiveDays => l10n.delivery3to5Days,
      fiveToSevenDays => l10n.delivery5to7Days,
    };
  }
}

/// Where a store delivers and what it asks: one fee and time in its own
/// city, one for everywhere else it goes. Each store sends its own driver
/// or delivery company, so each sets this itself.
@immutable
class StoreDelivery {
  const StoreDelivery({
    required this.governorates,
    required this.feeInside,
    required this.timeInside,
    this.feeOutside,
    this.timeOutside,
  });

  /// Every governorate it delivers to, its own included.
  final Set<Governorate> governorates;
  final num feeInside;
  final DeliveryTime timeInside;

  /// Null when it delivers in its own city only.
  final num? feeOutside;
  final DeliveryTime? timeOutside;

  bool deliversTo(Governorate city) => governorates.contains(city);

  /// The fee and time to [city] from a store in [storeCity], or null when
  /// it does not deliver there.
  (num, DeliveryTime)? to(Governorate city, {required Governorate? storeCity}) {
    if (!deliversTo(city)) return null;
    if (city == storeCity) return (feeInside, timeInside);
    final (fee, time) = (feeOutside, timeOutside);
    return fee == null || time == null ? null : (fee, time);
  }

  static StoreDelivery? fromJson(Object? json) {
    if (json is! Map) return null;
    final timeInside = DeliveryTime.fromApi(json['timeInside']);
    final feeInside = json['feeInside'];
    if (timeInside == null || feeInside is! num) return null;
    return StoreDelivery(
      governorates: {
        for (final code in (json['governorates'] as List?) ?? const [])
          ?Governorate.fromApi(code),
      },
      feeInside: feeInside,
      timeInside: timeInside,
      feeOutside: json['feeOutside'] as num?,
      timeOutside: DeliveryTime.fromApi(json['timeOutside']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'governorates': [for (final city in governorates) city.apiValue],
    'feeInside': feeInside,
    'timeInside': timeInside.apiValue,
    'feeOutside': ?feeOutside,
    'timeOutside': ?timeOutside?.apiValue,
  };
}

/// "Delivers to Erbil · 6,000 IQD · 3–5 days", or "Doesn't deliver to
/// Erbil": what a store's delivery means for the shopper's own city, said
/// before they fall for something it cannot bring them.
class StoreDeliveryLine extends StatelessWidget {
  const StoreDeliveryLine({
    super.key,
    required this.delivery,
    required this.storeCity,
    required this.shopperCity,
  });

  final StoreDelivery delivery;
  final Governorate? storeCity;
  final Governorate shopperCity;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final market = context.market;
    final city = shopperCity.label(context);
    final terms = delivery.to(shopperCity, storeCity: storeCity);

    final (icon, colour, text) = switch (terms) {
      null => (SabaIcons.alertCircle, market.warning, l10n.noDeliveryTo(city)),
      (final fee, final time) => (
        SabaIcons.truck,
        market.success,
        [
          l10n.deliversTo(city),
          if (fee <= 0)
            l10n.freeShipping
          else
            Formatters.money(
              fee,
              locale: l10n.locale.toLanguageTag(),
              currencyCode: 'IQD',
            ),
          time.label(context),
        ].join(' · '),
      ),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: SabaIcon(icon, size: 13, color: colour),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: context.textStyles.labelMedium?.copyWith(
              fontSize: 12,
              color: colour,
            ),
          ),
        ),
      ],
    );
  }
}
