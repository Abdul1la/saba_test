import '../../../core/location/governorate.dart';
import '../domain/entities.dart';

/// Converts API JSON into domain entities.
///
/// Every accessor is defensive: a missing or unexpected field yields a safe
/// default rather than throwing inside a widget build.
class UserMapper {
  const UserMapper._();

  static User fromJson(Map<String, dynamic> json) {
    // The user may be nested under `user` on auth responses.
    final source = json['user'] is Map
        ? Map<String, dynamic>.from(json['user'] as Map)
        : json;

    return User(
      id: (source['id'] ?? source['userId'] ?? '').toString(),
      fullName: (source['fullName'] ?? source['name'] ?? '').toString(),
      email: (source['email'] ?? '').toString(),
      role: UserRole.fromApi(source['role'] ?? source['type']),
      status: AccountStatus.fromApi(
        source['status'] ?? source['accountStatus'],
      ),
      phone: source['phone']?.toString(),
      avatarUrl:
          (source['avatarUrl'] ?? source['profileImage'] ?? source['avatar'])
              ?.toString(),
      country: source['country']?.toString(),
      city: source['city']?.toString(),
      governorate: Governorate.fromApi(source['governorate'] ?? source['city']),
      isEmailVerified: _bool(
        source['isEmailVerified'] ?? source['emailVerified'],
      ),
      isPhoneVerified: _bool(
        source['isPhoneVerified'] ?? source['phoneVerified'],
      ),
      merchant: _merchant(source),
      createdAt: _date(source['createdAt']),
    );
  }

  static MerchantSummary? _merchant(Map<String, dynamic> source) {
    final raw = source['merchant'] ?? source['store'];
    if (raw is! Map) return null;
    final merchant = Map<String, dynamic>.from(raw);
    return MerchantSummary(
      id: (merchant['id'] ?? merchant['merchantId'] ?? '').toString(),
      storeName: (merchant['storeName'] ?? merchant['businessName'] ?? '')
          .toString(),
      status: MerchantStatus.fromApi(merchant['status']),
      logoUrl: merchant['logoUrl']?.toString(),
      bannerUrl: merchant['bannerUrl']?.toString(),
      rating: _double(merchant['rating']),
      rejectionReason: merchant['rejectionReason']?.toString(),
      deletionRequestedAt: _date(merchant['deletionRequestedAt']),
    );
  }

  static bool _bool(Object? value) => switch (value) {
    final bool v => v,
    final num v => v != 0,
    final String v => v.toLowerCase() == 'true' || v == '1',
    _ => false,
  };

  static double? _double(Object? value) => switch (value) {
    final num v => v.toDouble(),
    final String v => double.tryParse(v),
    _ => null,
  };

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.tryParse(value.toString());
}
