import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the shared layer against Material leaking back into it.
///
/// Three batches of screen redesign still left the app looking half-old,
/// because the leaks were not in the screens — they were in `lib/core`, which
/// every screen draws through. `state_views.dart` alone carried ten Material
/// icons, so every empty state and every error state in the app was stock, on
/// screens that had otherwise been fully redrawn. `app_dialogs.dart` carried
/// four more, which is every snackbar.
///
/// Fixing the instances was never enough: the leaks kept coming back because
/// the *types* asked for them. `AppButton.icon`, `AppTextField.prefixIcon` and
/// `EmptyStateView.icon` were each declared `IconData`, so the signature
/// itself required every caller to reach for Material's family. These tests
/// pin both halves — no Material icons in the shared layer, and no shared API
/// that asks a caller for one.
void main() {
  /// Source with `//` comment lines removed, so a comment recalling the old
  /// value is a record of the fix rather than a repeat of it.
  String sourceOf(File file) => file
      .readAsLinesSync()
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');

  List<File> dartFilesIn(String directory) => Directory(directory)
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList();

  List<File> coreDartFiles() => dartFilesIn('lib/core');

  group('the shared layer speaks only the design system', () {
    test('no file in lib/core draws a Material icon', () {
      final offenders = <String>[];

      for (final file in coreDartFiles()) {
        // saba_icons.dart is where the design set is defined; nothing else
        // has a reason to name Material's.
        if (file.path.endsWith('saba_icons.dart')) continue;

        // `SabaIcons.` ends in `Icons.`, so strip the design set's own name
        // before looking for Material's. Dart's lookbehind support varies by
        // platform; removing the prefix outright cannot be got wrong.
        final source = sourceOf(file).replaceAll('SabaIcons.', '');
        if (source.contains(RegExp(r'\bIcons\.'))) {
          offenders.add(file.path);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'these shared files draw Material icons, so every screen that '
            'uses them shows the old family: ${offenders.join(", ")}',
      );
    });

    test('no shared widget asks a caller for an IconData', () {
      final offenders = <String>[];

      for (final file in coreDartFiles()) {
        if (file.path.endsWith('saba_icons.dart')) continue;

        final source = sourceOf(file);
        // A declaration, not a mention: `final IconData icon;` or a
        // `required IconData icon,` parameter. Prose in a doc comment is
        // already excluded by sourceOf.
        if (source.contains(RegExp(r'\bIconData\b'))) {
          offenders.add(file.path);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'an IconData in a shared signature makes every caller import '
            "Material's icons — take a SabaIcons path instead: "
            '${offenders.join(", ")}',
      );
    });
  });

  /// The screens themselves.
  ///
  /// `lib/core` was pinned first because a leak there shows on every screen
  /// at once. But sixty Material icons were still sitting in the feature
  /// folders - a stock bell on the merchant dashboard, a stock trash on the
  /// product row, stock mail on three auth screens - on screens that had
  /// otherwise been redrawn. Pinning only the shared layer left every screen
  /// free to reach past it.
  group('the screens speak only the design system', () {
    test('no file in lib/features draws a Material icon', () {
      final offenders = <String>[];

      for (final file in dartFilesIn('lib/features')) {
        final source = sourceOf(file).replaceAll('SabaIcons.', '');
        if (source.contains(RegExp(r'Icons\.'))) {
          offenders.add(file.path);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'these screens still draw Material icons rather than the design '
            'set: ${offenders.join(", ")}',
      );
    });

    test('no screen wears Material chrome', () {
      final offenders = <String>[];

      // A pushed screen gets a SabaAppBar, a tab screen a PageTitle.
      // Material's AppBar brings its own height, back arrow and title
      // alignment, none of which are the design's.
      final chrome = RegExp(r'appBar: AppBar\(|bottom: TabBar|TabBarView');

      for (final file in dartFilesIn('lib/features')) {
        if (sourceOf(file).contains(chrome)) offenders.add(file.path);
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'these screens still wear Material chrome: '
            '${offenders.join(", ")}',
      );
    });
  });
}
