import 'package:flutter/foundation.dart';

import '../../../core/location/governorate.dart';

/// A saved delivery address, the way an Iraqi address is actually found:
/// the governorate, the area, and the nearest landmark the driver can ask
/// for. No country - Saba delivers in Iraq only - and no postal code, which
/// nobody here uses.
@immutable
class Address {
  const Address({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.governorate,
    required this.area,
    required this.landmark,
    this.street,
    this.label,
    this.instructions,
    this.isDefault = false,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String fullName;

  /// The number the driver calls, +9647XXXXXXXXX.
  final String phone;

  /// Null only for an address whose city this app does not know.
  final Governorate? governorate;

  /// The district or neighbourhood: Al-Mansour, Karrada, Ainkawa.
  final String area;

  /// "Next to Al-Rasheed Mosque": how a driver finds a house here.
  final String landmark;

  /// Street, alley and house number, when there are any.
  final String? street;

  /// "Home", "Work", or whatever the customer typed.
  final String? label;

  final String? instructions;
  final bool isDefault;

  /// Reserved for delivery zones and distance calculation; the app does not
  /// depend on a specific maps provider (specification section 47).
  final double? latitude;
  final double? longitude;

  /// One line for lists: street, area, city, the city in [languageCode].
  String formattedIn(String languageCode) =>
      <String?>[street, area, governorate?.nameIn(languageCode)]
          .where((part) => part != null && part.trim().isNotEmpty)
          .join(
            // Arabic writes its own comma.
            languageCode == 'ar' ? '، ' : ', ',
          );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'fullName': fullName,
    'phone': phone,
    'governorate': ?governorate?.apiValue,
    'area': area,
    'landmark': landmark,
    'street': ?street,
    'label': ?label,
    'instructions': ?instructions,
    'isDefault': isDefault,
  };
}
