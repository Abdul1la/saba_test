/// Search text, folded so the ways people type Arabic in Iraq all meet.
///
/// A shopper types احمد for أحمد, مكتبه for مكتبة, مصطفي for مصطفى, leaves out
/// the vowel marks, and types on a Persian or Kurdish keyboard whose ی and ک
/// are other letters than ي and ك. Both sides of a match go through
/// [normalize], so each of those still finds the product.
///
/// The real backend must fold the same way, or search changes on launch day.
class SearchText {
  const SearchText._();

  /// [text] lower-cased, with the letter forms above made one and the marks
  /// that do not change a word taken out. Arabic and Persian digits become
  /// 0-9, and runs of spaces become one.
  static String normalize(String text) {
    final out = StringBuffer();
    for (final rune in text.toLowerCase().runes) {
      final folded = _fold(rune);
      if (folded != null) out.writeCharCode(folded);
    }
    return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Whether every word of [query] is somewhere in [fields]. "سماعة سوني"
  /// needs both words; the order they appear in does not matter.
  static bool matches(String query, Iterable<String?> fields) {
    final words = _words(query);
    if (words.isEmpty) return true;
    final haystack = normalize(fields.whereType<String>().join(' '));
    return words.every(haystack.contains);
  }

  /// The words of [query], each without a leading ال, so الساعة finds ساعة.
  /// A short word keeps it: ال on its own, or الم, is a word by itself.
  static List<String> _words(String query) => [
    for (final word in normalize(query).split(' '))
      if (word.isNotEmpty)
        word.length > 3 && word.startsWith('ال') ? word.substring(2) : word,
  ];

  /// One code point folded, or null to drop it.
  static int? _fold(int c) {
    // Vowel marks (fatha, damma, kasra, shadda, sukun, tanween and the rest),
    // the dagger alef, and the tatweel that stretches a word.
    if ((c >= 0x064B && c <= 0x065F) || c == 0x0670 || c == 0x0640) {
      return null;
    }
    if (c >= 0x0660 && c <= 0x0669) return c - 0x0660 + 0x30; // ٠-٩
    if (c >= 0x06F0 && c <= 0x06F9) return c - 0x06F0 + 0x30; // ۰-۹
    return switch (c) {
      0x0622 || 0x0623 || 0x0625 || 0x0671 => 0x0627, // آ أ إ ٱ to ا
      0x0649 || 0x06CC || 0x0626 => 0x064A, // ى ی ئ to ي
      0x0629 => 0x0647, // ة to ه
      0x0624 => 0x0648, // ؤ to و
      0x06A9 => 0x0643, // ک to ك
      _ => c,
    };
  }
}
