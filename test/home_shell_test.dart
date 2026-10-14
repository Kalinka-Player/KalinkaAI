import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/screens/queue_page.dart';
import 'package:kalinka/widgets/coach_marks_overlay.dart';
import 'package:kalinka/widgets/kalinka_top_bar.dart';
import 'package:kalinka/widgets/mini_player.dart';
import 'package:kalinka/widgets/now_playing_content.dart';
import 'package:kalinka/widgets/queue_zone.dart';
import 'package:kalinka/widgets/search/search_session_view.dart';

import 'support/home_shell.dart';

/// Records whether the system back left the app.
List<String> _recordSystemCalls() {
  final calls = <String>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    calls.add(call.method);
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return calls;
}

void main() {
  testWidgets('the app opens on Home, the queue a page away', (tester) async {
    await pumpHomeShell(tester, queue: SettableQueue(queueOf(4)));

    expect(find.byType(SearchSessionView), findsOneWidget);
    expect(find.byType(KalinkaTopBar), findsOneWidget);
    expect(find.byType(QueueZone), findsNothing);
    expect(find.text('UP NEXT'), findsOneWidget);
    expect(find.text('4 tracks · 13 min'), findsOneWidget);
  });

  testWidgets('an empty queue leaves Up next off Home', (tester) async {
    await pumpHomeShell(tester, queue: SettableQueue(queueOf(0)));
    expect(find.text('UP NEXT'), findsNothing);
  });

  testWidgets('Up next opens the queue, and back returns to Home', (
    tester,
  ) async {
    final calls = _recordSystemCalls();
    await pumpHomeShell(tester, queue: SettableQueue(queueOf(4, index: 1)));

    await tester.tap(find.text('QUEUE'));
    await tester.pumpAndSettle();
    expect(find.byType(QueuePage), findsOneWidget);
    expect(find.text('Your queue'), findsOneWidget);
    // From the playing track on.
    expect(
      find.descendant(
        of: find.byType(QueuePage),
        matching: find.text('3 tracks · 10 min'),
      ),
      findsOneWidget,
    );
    // The page's header carries the menu; the list's own stays away.
    expect(find.byTooltip('Queue options'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(QueuePage), findsNothing);
    expect(find.byType(SearchSessionView).hitTestable(), findsOneWidget);
    expect(calls, isNot(contains('SystemNavigator.pop')));
  });

  testWidgets('the queue page\'s menu holds the queue actions', (tester) async {
    await pumpHomeShell(tester, queue: SettableQueue(queueOf(3, index: 1)));
    await tester.tap(find.text('QUEUE'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Queue options'));
    await tester.pumpAndSettle();
    expect(find.text('Clear queue'), findsOneWidget);
    expect(find.text('Clear played'), findsOneWidget);
  });

  testWidgets('back at Home\'s top level leaves the app', (tester) async {
    final calls = _recordSystemCalls();
    await pumpHomeShell(tester, queue: SettableQueue(queueOf(2)));

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(calls, contains('SystemNavigator.pop'));
  });

  testWidgets('back from a catalog page unwinds Home first', (tester) async {
    final calls = _recordSystemCalls();
    final container = await pumpHomeShell(
      tester,
      queue: SettableQueue(queueOf(2)),
    );
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(id: 'kalinka:localfiles:catalog:albums', title: 'Albums');
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(container.read(searchSessionProvider).catalogPage.isRoot, isTrue);
    expect(calls, isNot(contains('SystemNavigator.pop')));
  });

  testWidgets('the Now Playing sheet opens the queue', (tester) async {
    await pumpHomeShell(tester, queue: SettableQueue(queueOf(3)));

    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();
    expect(find.byType(NowPlayingContent), findsOneWidget);

    await tester.tap(find.byTooltip('Queue'));
    await tester.pumpAndSettle();
    expect(find.byType(NowPlayingContent), findsNothing);
    expect(find.byType(QueuePage), findsOneWidget);
  });

  testWidgets('the empty queue leads back to search', (tester) async {
    final container = await pumpHomeShell(
      tester,
      queue: SettableQueue(queueOf(0)),
    );
    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Queue'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Find music'));
    await tester.pumpAndSettle();
    expect(find.byType(QueuePage), findsNothing);
    expect(find.text('SMART SEARCH'), findsOneWidget);
    expect(container.read(searchEntryModeProvider), isTrue);
  });

  testWidgets('on a wide window the queue opens beside Now Playing', (
    tester,
  ) async {
    await pumpHomeShell(
      tester,
      queue: SettableQueue(queueOf(3)),
      size: const Size(1280, 800),
    );
    final nowPlaying = tester.getRect(find.byType(NowPlayingContent));

    await tester.tap(find.byTooltip('Queue'));
    await tester.pumpAndSettle();
    final page = tester.getRect(find.byType(QueuePage));
    expect(page.left, greaterThan(nowPlaying.right));
    expect(find.byType(NowPlayingContent).hitTestable(), findsOneWidget);
  });

  testWidgets('the first-run tour starts at the search entry', (tester) async {
    await pumpHomeShell(
      tester,
      queue: SettableQueue(queueOf(2)),
      coachMarksShown: false,
    );
    expect(find.byType(CoachMarksOverlay), findsOneWidget);
    expect(find.text('Find music'), findsOneWidget);
  });
}
