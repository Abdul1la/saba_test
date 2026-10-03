// What the rule pages must say.
//
// The Privacy policy is the page Saba gives the app stores,
// backend/public/privacy.html, in both languages (DEPLOYMENT.md §6). The
// app's left out OTPIQ, Firebase, DigitalOcean, the IP address and the
// notification ID, and deleted store replies to reviews that do not exist
// (the final review, 2026-10-01). The Terms say what Apple 1.2 asks of an
// app with reviews and chats.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/features/legal/legal_screen.dart';

/// The web page in [lang] as the app writes it: no title or date line; each
/// h2 a heading, each p or li a paragraph; text marked dir="ltr" isolated as
/// the app isolates it; tags dropped, spaces collapsed.
List<List<String>> _web(String html, String lang) {
  final page = RegExp(
    '<section lang="$lang"[^>]*>([\\s\\S]*?)</section>',
  ).firstMatch(html)!.group(1)!;
  final sections = <List<String>>[];
  for (final m in RegExp(
    r'<(h1|h2|p|li)\b([^>]*)>([\s\S]*?)</\1>',
  ).allMatches(page)) {
    final (tag, attributes, inner) = (m.group(1)!, m.group(2)!, m.group(3)!);
    if (tag == 'h1' || attributes.contains('class="lead"')) continue;
    final text = inner
        .replaceAllMapped(
          RegExp(r'<a\b[^>]*\bdir="ltr"[^>]*>([\s\S]*?)</a>'),
          (a) => '\u2066${a.group(1)}\u2069',
        )
        .replaceAll(RegExp('<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (tag == 'h2') {
      sections.add([text]);
    } else {
      if (sections.isEmpty) sections.add(['']);
      sections.last.add(text);
    }
  }
  return sections;
}

void main() {
  final html = File('../backend/public/privacy.html').readAsStringSync();

  for (final lang in ['en', 'ar']) {
    test('the Privacy policy is the web page, word for word ($lang)', () {
      final app = [
        for (final (heading, body) in LegalPage.privacy.sectionsIn(lang))
          [heading, ...body.split('\n')],
      ];
      expect(app, _web(html, lang));
    });
  }

  for (final (lang, said) in const [
    (
      'en',
      [
        'zero tolerance for objectionable content and abusive users',
        'acts on reports quickly',
        'removes the accounts of users who abuse others',
      ],
    ),
    (
      'ar',
      [
        'لا تتسامح سبأ مطلقاً مع المحتوى المسيء ولا مع المستخدمين المسيئين',
        'وتتعامل سبأ مع البلاغات بسرعة',
        'وتحذف حسابات من يسيئون إلى غيرهم',
      ],
    ),
  ]) {
    test('the Terms say what Apple asks of reviews and chats ($lang)', () {
      final terms = [
        for (final (_, body) in LegalPage.terms.sectionsIn(lang)) body,
      ].join('\n');
      for (final words in said) {
        expect(terms, contains(words));
      }
    });
  }
}
