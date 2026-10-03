// BUGS.md 60 gave the web's paged lists a Refresh button, since a mouse
// cannot pull to refresh. The user took it out: on a phone it is clutter.
// A list reads itself again on coming back to it, and the pull stays.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/network/api_response.dart';
import 'package:saba_marketplace/core/providers/paged_state.dart';
import 'package:saba_marketplace/core/widgets/paged_list_view.dart';

void main() {
  const state = PagedState<String>(
    items: ['SB-1', 'SB-2'],
    meta: PaginationMeta(page: 1, perPage: 20, total: 2, totalPages: 1),
  );

  Future<List<int>> pump(
    WidgetTester tester, {
    bool reloadOnReturn = true,
  }) async {
    final refreshed = [0];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(
          body: PagedListView<String>(
            state: state,
            reloadOnReturn: reloadOnReturn,
            itemBuilder: (context, item, _) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('order')),
                ),
              ),
              child: Text(item),
            ),
            onLoadMore: () {},
            onRefresh: () async => refreshed[0]++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return refreshed;
  }

  testWidgets('no Refresh button; back on the list, it reads itself again', (
    tester,
  ) async {
    final refreshed = await pump(tester);
    expect(find.text('Refresh'), findsNothing);
    expect(refreshed.single, 0, reason: 'read again before anything happened');

    await tester.tap(find.text('SB-1'));
    await tester.pumpAndSettle();
    expect(find.text('order'), findsOneWidget);
    expect(refreshed.single, 0, reason: 'read again while covered');

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(refreshed.single, 1, reason: 'not read again on coming back');

    // Back in the app, too.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(refreshed.single, 2, reason: 'not read again on coming back');
  });

  testWidgets('a product grid keeps its place instead', (tester) async {
    final refreshed = await pump(tester, reloadOnReturn: false);
    await tester.tap(find.text('SB-1'));
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(refreshed.single, 0);
  });
}
