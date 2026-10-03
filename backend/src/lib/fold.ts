// A port of the app's lib/core/utils/search_text.dart. "The real backend must
// fold the same way, or search changes on launch day." Both sides of a match
// go through fold(): the stored search_text and the typed query.

/** [text] lower-cased, Arabic letter forms made one, marks dropped, digits 0-9, spaces single. */
export function fold(text: string): string {
  let out = ''
  for (const char of text.toLowerCase()) {
    const folded = foldCode(char.codePointAt(0)!)
    if (folded !== null) out += String.fromCodePoint(folded)
  }
  return out.replace(/\s+/g, ' ').trim()
}

/** The words of [query], each without a leading ال when longer than 3 letters. */
export function searchWords(query: string): string[] {
  return fold(query)
    .split(' ')
    .filter(Boolean)
    .map((word) => (word.length > 3 && word.startsWith('ال') ? word.slice(2) : word))
}

function foldCode(c: number): number | null {
  // Vowel marks, the dagger alef, the tatweel.
  if ((c >= 0x064b && c <= 0x065f) || c === 0x0670 || c === 0x0640) return null
  if (c >= 0x0660 && c <= 0x0669) return c - 0x0660 + 0x30
  if (c >= 0x06f0 && c <= 0x06f9) return c - 0x06f0 + 0x30
  switch (c) {
    case 0x0622:
    case 0x0623:
    case 0x0625:
    case 0x0671:
      return 0x0627 // آ أ إ ٱ → ا
    case 0x0649:
    case 0x06cc:
    case 0x0626:
      return 0x064a // ى ی ئ → ي
    case 0x0629:
      return 0x0647 // ة → ه
    case 0x0624:
      return 0x0648 // ؤ → و
    case 0x06a9:
      return 0x0643 // ک → ك
    default:
      return c
  }
}
