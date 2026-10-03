import 'package:flutter/foundation.dart';

import '../../../core/location/governorate.dart';

/// The only three account types the platform has (specification section 2).
///
/// [unknown] exists solely so an unrecognised value from the API degrades into
/// "no permissions" instead of being silently treated as a privileged role.
enum UserRole {
  customer,
  merchant,
  admin,
  unknown;

  static UserRole fromApi(Object? value) =>
      switch (value?.toString().toUpperCase()) {
        'CUSTOMER' => UserRole.customer,
        'MERCHANT' => UserRole.merchant,
        'ADMIN' => UserRole.admin,
        _ => UserRole.unknown,
      };

  bool get isCustomer => this == UserRole.customer;
  bool get isMerchant => this == UserRole.merchant;
  bool get isAdmin => this == UserRole.admin;
}

enum AccountStatus {
  active,
  inactive,
  suspended,
  pendingVerification,
  deleted,
  unknown;

  static AccountStatus fromApi(Object? value) =>
      switch (value?.toString().toUpperCase()) {
        'ACTIVE' => AccountStatus.active,
        'INACTIVE' => AccountStatus.inactive,
        'SUSPENDED' => AccountStatus.suspended,
        'PENDING_VERIFICATION' => AccountStatus.pendingVerification,
        'DELETED' => AccountStatus.deleted,
        _ => AccountStatus.unknown,
      };

  bool get canUseApp =>
      this == AccountStatus.active || this == AccountStatus.pendingVerification;
}

/// Merchant approval lifecycle (specification section 21).
enum MerchantStatus {
  pending,
  approved,
  rejected,
  suspended,
  unknown;

  static MerchantStatus fromApi(Object? value) =>
      switch (value?.toString().toUpperCase()) {
        'PENDING' => MerchantStatus.pending,
        'APPROVED' => MerchantStatus.approved,
        'REJECTED' => MerchantStatus.rejected,
        'SUSPENDED' => MerchantStatus.suspended,
        _ => MerchantStatus.unknown,
      };
}

/// The merchant facts the app needs alongside the user record.
@immutable
class MerchantSummary {
  const MerchantSummary({
    required this.id,
    required this.storeName,
    required this.status,
    this.logoUrl,
    this.bannerUrl,
    this.rating,
    this.rejectionReason,
    this.deletionRequestedAt,
  });

  final String id;
  final String storeName;
  final MerchantStatus status;

  /// Why Saba did not approve the store, as the admin wrote it.
  final String? rejectionReason;

  /// When the owner asked for the account to be deleted: the store is
  /// closed until then, and cannot open.
  final DateTime? deletionRequestedAt;
  final String? logoUrl;
  final String? bannerUrl;
  final double? rating;

  /// Whether to show selling features. Purely presentational: the backend
  /// enforces selling eligibility on every request (specification section 21).
  bool get canSell => status == MerchantStatus.approved;
}

/// The authenticated user.
///
/// Never carries a password, a hash or a token — those either do not leave the
/// server or live in the secure keystore (specification sections 21 and 50).
@immutable
class User {
  const User({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.status,
    this.phone,
    this.avatarUrl,
    this.country,
    this.city,
    this.governorate,
    this.isEmailVerified = false,
    this.isPhoneVerified = false,
    this.merchant,
    this.createdAt,
  });

  final String id;
  final String fullName;

  /// Empty when the account has none: the phone is how an account signs in,
  /// and an email is optional.
  final String email;
  final UserRole role;
  final AccountStatus status;
  final String? phone;
  final String? avatarUrl;
  final String? country;
  final String? city;

  /// The shopper's city, asked at sign-up.
  final Governorate? governorate;
  final bool isEmailVerified;
  final bool isPhoneVerified;

  /// Present only when [role] is `merchant`.
  final MerchantSummary? merchant;

  final DateTime? createdAt;

  String get initials {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return _firstLetter(parts.first);
    return _firstLetter(parts.first) + _firstLetter(parts.last);
  }

  static String _firstLetter(String value) =>
      value.substring(0, 1).toUpperCase();

  User copyWith({
    String? fullName,
    String? phone,
    String? avatarUrl,
    String? country,
    String? city,
    bool? isEmailVerified,
    MerchantSummary? merchant,
  }) {
    return User(
      id: id,
      fullName: fullName ?? this.fullName,
      email: email,
      role: role,
      status: status,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      country: country ?? this.country,
      city: city ?? this.city,
      governorate: governorate,
      isEmailVerified: isEmailVerified ?? this.isEmailVerified,
      isPhoneVerified: isPhoneVerified,
      merchant: merchant ?? this.merchant,
      createdAt: createdAt,
    );
  }
}

/// What a code is asked for; the server applies the rule that goes with it.
enum OtpPurpose {
  /// Signing up: refused for a number that already has an account.
  signUp('SIGN_UP'),

  /// A forgotten password: refused for a number with no account.
  passwordReset('PASSWORD_RESET'),

  /// Checking the number of an account that has one but never verified it,
  /// so it can sign in once Saba has turned SMS checks back on.
  verifyPhone('VERIFY_PHONE'),
  other(null);

  const OtpPurpose(this.apiValue);

  final String? apiValue;
}

/// What the server says once an SMS code is on its way — or, when Saba has
/// SMS checks switched off, that no code is coming and the number is already
/// proven.
///
/// [demoCode] is filled in by the demo backend only. There is no SMS gateway
/// behind a demo build, so without it a tester is parked on a screen they have
/// no way to pass. A real backend omits the field and the screen shows nothing.
///
/// [verificationToken] is present only when checks are off (the user's call,
/// so Saba pays for no SMS at launch): no code was sent, and this stands in
/// for the one the code screen would have produced. With it, sign-up skips
/// straight to the details form; without it, the code screen as before.
@immutable
class OtpChallenge {
  const OtpChallenge({
    required this.expiresInSeconds,
    this.demoCode,
    this.verificationToken,
  });

  /// [demo] is whether this is a demo build. Only a demo build takes the
  /// code: a real server that sent one by mistake would otherwise print
  /// every sign-in code on the screen it is meant to prove a phone to.
  factory OtpChallenge.fromJson(
    Map<String, dynamic> json, {
    required bool demo,
  }) => OtpChallenge(
    expiresInSeconds: int.tryParse('${json['expiresInSeconds']}') ?? 60,
    demoCode: demo ? json['demoCode']?.toString() : null,
    verificationToken:
        (json['verificationToken'] as String?)?.trim().isEmpty ?? true
        ? null
        : json['verificationToken'] as String,
  );

  final int expiresInSeconds;
  final String? demoCode;

  /// When non-null, no code was sent: use it as the phone-verification token
  /// and skip the code screen.
  final String? verificationToken;
}

/// Payload for creating a customer account.
@immutable
class CustomerRegistration {
  const CustomerRegistration({
    required this.fullName,
    required this.password,
    required this.phone,
    this.email,
    this.phoneVerificationToken,
    this.country,
    this.governorate,
  });

  final String fullName;

  /// Optional: the phone is how the account signs in.
  final String? email;
  final String password;
  final String phone;

  /// Proof the SMS step was passed. The server rejects a sign-up without it,
  /// which is what stops anyone from deep-linking past phone verification.
  final String? phoneVerificationToken;
  final String? country;

  /// A `Governorate` code: the shopper's city.
  final String? governorate;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'fullName': fullName,
    'email': ?email,
    'password': password,
    'phone': phone,
    'phoneVerificationToken': ?phoneVerificationToken,
    'country': ?country,
    'governorate': ?governorate,
  };
}

/// Payload for creating a merchant account and its pending store.
@immutable
class MerchantRegistration {
  const MerchantRegistration({
    required this.fullName,
    required this.password,
    required this.phone,
    required this.storeName,
    this.email,
    required this.businessType,
    this.phoneVerificationToken,
    this.businessAddress,
    this.businessDescription,
    this.country,
    this.governorate,
  });

  final String fullName;

  /// Optional, as for a shopper.
  final String? email;
  final String password;
  final String phone;
  final String storeName;
  final String businessType;
  final String? phoneVerificationToken;
  final String? businessAddress;
  final String? businessDescription;
  final String? country;

  /// A `Governorate` code: where the store is.
  final String? governorate;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'fullName': fullName,
    'email': ?email,
    'password': password,
    'phone': phone,
    'storeName': storeName,
    'businessType': businessType,
    'phoneVerificationToken': ?phoneVerificationToken,
    'businessAddress': ?businessAddress,
    'businessDescription': ?businessDescription,
    'country': ?country,
    'governorate': ?governorate,
  };
}
