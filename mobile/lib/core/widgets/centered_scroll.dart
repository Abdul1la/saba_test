import 'package:flutter/material.dart';

/// Its child in the middle of the space it is given, and scrollable when the
/// child is taller than that space.
///
/// For the short screens - pick a role, enter a number, enter a code - which
/// stood at the top with their button at the bottom and a blank half-screen
/// between. Centred with the button beside what it acts on, the eye has one
/// place to look. It scrolls rather than squeezes, so a large font or an open
/// keyboard never pushes the button out of reach: that is what a Spacer did
/// here once.
class CenteredScroll extends StatelessWidget {
  const CenteredScroll({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: child),
        ),
      ),
    );
  }
}
