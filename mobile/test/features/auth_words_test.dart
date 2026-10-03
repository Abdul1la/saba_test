// The auth screens' words: an error said "Too short (2)"; a read-only phone
// was labelled "(Optional)" over "You sign in with this number".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/utils/validators.dart';
import 'package:saba_marketplace/core/widgets/app_text_field.dart';

void main() {
  test('a short name is told in words, in both languages', () {
    expect(
      Validators.minLength('A', 2, const AppLocalizations(Locale('en'))),
      'Too short. Use at least 2 characters.',
    );
    expect(
      Validators.minLength('أ', 2, const AppLocalizations(Locale('ar'))),
      'قصير جداً. اكتب حرفين على الأقل.',
    );
  });

  testWidgets('a read-only field is not "optional"', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(
          body: AppTextField(
            label: 'Phone',
            controller: TextEditingController(text: '+9647701234567'),
            readOnly: true,
          ),
        ),
      ),
    );
    expect(find.textContaining('Optional'), findsNothing);
    expect(find.textContaining('optional'), findsNothing);
  });
}
