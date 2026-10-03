/// Iraq's 19 governorates: where Saba sells, and the one way a place is
/// chosen anywhere in the app - a store's home, a shopper's city. Halabja
/// became the 19th in 2025.
///
/// The biggest cities first, so most people find theirs without scrolling.
/// Where a governorate goes by another name than its main city, the city is
/// in brackets, so nobody looks for Mosul and finds only Nineveh.
enum Governorate {
  baghdad('BAGHDAD', 'Baghdad', 'بغداد'),
  basra('BASRA', 'Basra', 'البصرة'),
  nineveh('NINEVEH', 'Nineveh (Mosul)', 'نينوى (الموصل)'),
  erbil('ERBIL', 'Erbil', 'أربيل'),
  sulaymaniyah('SULAYMANIYAH', 'Sulaymaniyah', 'السليمانية'),
  duhok('DUHOK', 'Duhok', 'دهوك'),
  kirkuk('KIRKUK', 'Kirkuk', 'كركوك'),
  najaf('NAJAF', 'Najaf', 'النجف'),
  karbala('KARBALA', 'Karbala', 'كربلاء'),
  babylon('BABYLON', 'Babylon (Hillah)', 'بابل (الحلة)'),
  anbar('ANBAR', 'Anbar (Ramadi)', 'الأنبار (الرمادي)'),
  dhiQar('DHI_QAR', 'Dhi Qar (Nasiriyah)', 'ذي قار (الناصرية)'),
  diyala('DIYALA', 'Diyala (Baqubah)', 'ديالى (بعقوبة)'),
  salahAlDin('SALAH_AL_DIN', 'Salah al-Din (Tikrit)', 'صلاح الدين (تكريت)'),
  wasit('WASIT', 'Wasit (Kut)', 'واسط (الكوت)'),
  maysan('MAYSAN', 'Maysan (Amarah)', 'ميسان (العمارة)'),
  qadisiyah('QADISIYAH', 'Qadisiyah (Diwaniyah)', 'القادسية (الديوانية)'),
  muthanna('MUTHANNA', 'Muthanna (Samawah)', 'المثنى (السماوة)'),
  halabja('HALABJA', 'Halabja', 'حلبجة');

  const Governorate(this.apiValue, this.english, this.arabic);

  /// The stable code the backend stores and sends.
  final String apiValue;
  final String english;
  final String arabic;

  /// Its name in a language: Arabic, or English for anything else.
  String nameIn(String languageCode) => languageCode == 'ar' ? arabic : english;

  /// The governorate a value names - its code, or its name in either
  /// language, with or without the city in brackets - so a store saved as
  /// "Baghdad" before this list existed still reads as Baghdad, and "Mosul"
  /// finds Nineveh. Null for anything else.
  static Governorate? fromApi(Object? value) {
    final wanted = value?.toString().trim().toLowerCase() ?? '';
    if (wanted.isEmpty) return null;
    for (final governorate in values) {
      for (final name in [
        governorate.apiValue,
        governorate.english,
        governorate.arabic,
      ]) {
        final lower = name.toLowerCase();
        final parts = lower
            .split(RegExp(r'\s*[()]\s*'))
            .where((part) => part.isNotEmpty);
        if (lower == wanted || parts.contains(wanted)) return governorate;
      }
    }
    return null;
  }
}
