import '../constants/app_constants.dart';
import '../localization/app_localizations.dart';
import 'formatters.dart';
import 'iraqi_phone.dart';

/// Client-side form validation.
///
/// This exists purely to give fast feedback. It is never the authority: the
/// backend re-validates every input and its field errors are merged into the
/// same form (specification sections 9 and 20).
class Validators {
  const Validators._();

  static final RegExp _emailPattern = RegExp(
    r'^[\w.!#$%&*+/=?^`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?'
    r'(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$',
  );

  static final RegExp _phonePattern = RegExp(r'^\+?[0-9\s\-()]{7,20}$');

  static String? required(String? value, AppLocalizations l10n) {
    if (value == null || value.trim().isEmpty) return l10n.validationRequired;
    return null;
  }

  static String? email(String? value, AppLocalizations l10n) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return l10n.validationRequired;
    if (!_emailPattern.hasMatch(trimmed)) return l10n.validationEmail;
    return null;
  }

  /// Length only, for signing in and for a new password alike. Upper and
  /// lower case letters and a digit were required as well, which an Arabic
  /// keyboard has no easy way to give; a minimum length is the rule.
  static String? password(String? value, AppLocalizations l10n) {
    final text = value ?? '';
    if (text.isEmpty) return l10n.validationRequired;
    if (text.length < AppConstants.minPasswordLength) {
      return l10n.validationPasswordLength;
    }
    return null;
  }

  static String? confirmPassword(
    String? value,
    String original,
    AppLocalizations l10n,
  ) {
    if (value == null || value.isEmpty) return l10n.validationRequired;
    if (value != original) return l10n.validationPasswordMatch;
    return null;
  }

  static String? phone(String? value, AppLocalizations l10n) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return l10n.validationRequired;
    if (!_phonePattern.hasMatch(trimmed)) return l10n.validationPhone;
    return null;
  }

  /// An Iraqi mobile, typed any of the ways people type one.
  static String? iraqiPhone(String? value, AppLocalizations l10n) {
    if ((value ?? '').trim().isEmpty) return l10n.validationRequired;
    return IraqiPhone.normalize(value) == null ? l10n.validationPhone : null;
  }

  /// Nothing, or a well-formed address: an email is optional on Saba.
  static String? optionalEmail(String? value, AppLocalizations l10n) =>
      (value ?? '').trim().isEmpty ? null : email(value, l10n);

  /// A name a shopper reading Arabic can read: at least three characters,
  /// in Arabic letters.
  static String? arabicName(String? value, AppLocalizations l10n) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return l10n.validationRequired;
    if (trimmed.length < 3) return l10n.minimumLength(3);
    if (!RegExp('[\u0600-\u06FF]').hasMatch(trimmed)) {
      return l10n.validationArabicLetters;
    }
    return null;
  }

  static String? minLength(String? value, int length, AppLocalizations l10n) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return l10n.validationRequired;
    if (trimmed.length < length) return l10n.minimumLength(length);
    return null;
  }

  /// Empty is allowed; anything typed has to be long enough to be worth
  /// reading. For fields where saying nothing is a real answer — a star
  /// rating with no words is the commonest review there is — but "ok" is
  /// not.
  static String? optionalMinLength(
    String? value,
    int length,
    AppLocalizations l10n,
  ) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (trimmed.length < length) return l10n.minimumLength(length);
    return null;
  }

  /// A non-negative number, used for stock and similar integer inputs.
  static String? number(String? value, AppLocalizations l10n) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return l10n.validationRequired;
    final parsed = Formatters.typedNumber(trimmed);
    if (parsed == null || parsed < 0) return l10n.validationNumber;
    return null;
  }

  /// Strictly greater than zero, used for prices and quantities.
  static String? positiveNumber(String? value, AppLocalizations l10n) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return l10n.validationRequired;
    final parsed = Formatters.typedNumber(trimmed);
    if (parsed == null) return l10n.validationNumber;
    if (parsed <= 0) return l10n.validationPositive;
    return null;
  }

  /// A price in dinars that cash pays exactly: above 0, in steps of 250
  /// IQD, the smallest note. Every order is paid to a driver in cash.
  static String? cashPrice(String? value, AppLocalizations l10n) {
    final problem = positiveNumber(value, l10n);
    if (problem != null) return problem;
    return Formatters.typedNumber(value!)! % 250 == 0 ? null : l10n.iqdSteps;
  }

  /// A fee in dinars: 0 for free, else in steps of 250 IQD like a price.
  static String? cashFee(String? value, AppLocalizations l10n) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return l10n.validationRequired;
    final parsed = Formatters.typedNumber(trimmed);
    if (parsed == null || parsed < 0) return l10n.validationNumber;
    return parsed % 250 == 0 ? null : l10n.iqdSteps;
  }

  /// [cashPrice], for a field that may be left empty.
  static String? optionalCashPrice(String? value, AppLocalizations l10n) =>
      (value ?? '').trim().isEmpty ? null : cashPrice(value, l10n);

  /// Runs several validators and returns the first message produced.
  static String? Function(String?) compose(
    List<String? Function(String?)> validators,
  ) {
    return (value) {
      for (final validator in validators) {
        final error = validator(value);
        if (error != null) return error;
      }
      return null;
    };
  }
}
