import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/kalinka_ws_api.dart';
import 'package:kalinka/providers/kalinka_ws_api_provider.dart';
import 'package:kalinka/providers/renderer_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/coach_marks_overlay.dart';
import 'package:kalinka/widgets/kalinka_top_bar.dart';
import 'package:kalinka/widgets/mini_player.dart';
import 'package:kalinka/widgets/now_playing_content.dart';
import 'package:kalinka/widgets/player_queue_view.dart';
import 'package:kalinka/widgets/player_view_switch.dart';
import 'package:kalinka/widgets/queue_zone.dart';
import 'package:kalinka/widgets/renderer_switcher.dart';
import 'package:kalinka/widgets/search/search_composer.dart';
import 'package:kalinka/widgets/search/search_session_view.dart';
import 'package:kalinka/widgets/server_chip.dart';

import 'support/home_shell.dart';

class _Renderers extends RendererListNotifier {
  @override
  RendererListState build() => const RendererListState(
    loaded: true,
    renderers: [
      RendererInfo(
        rendererId: 'smsl',
        friendlyName: 'SMSL SU-1',
        status: 'connected',
        active: true,
      ),
    ],
  );

  @override
  Future<void> refresh() async {}
}

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

final _queueView = find.byType(PlayerQueueView);

/// One side of the player's view switch.
Finder _side(String label) => find.descendant(
  of: find.byType(PlayerViewSwitch),
  matching: find.text(label),
);

/// The mini-player over the player's queue, not the one under Home.
final _queueMiniPlayer = find.descendant(
  of: find.byType(QueueMiniPlayer),
  matching: find.byType(MiniPlayer),
);

/// Opens the phone player from Home's mini-player and turns it to the queue.
Future<void> _openQueue(WidgetTester tester) async {
  await tester.tap(find.byType(MiniPlayer));
  await tester.pumpAndSettle();
  await tester.tap(_side('QUEUE'));
  await tester.pumpAndSettle();
}

class _RecordingWsApi extends KalinkaWsApi {
  _RecordingWsApi(super.ref);

  final List<QueueCommand> sent = [];

  @override
  Future<void> sendQueueCommand(QueueCommand command) async {
    sent.add(command);
  }
}

void main() {
  testWidgets('the app opens on Home, the queue in the player', (tester) async {
    await pumpHomeShell(tester, queue: SettableQueue(queueOf(4)));

    expect(find.byType(SearchSessionView), findsOneWidget);
    expect(find.byType(KalinkaTopBar), findsOneWidget);
    expect(find.byType(QueueZone), findsNothing);
  });

  testWidgets('the player turns to its queue; back closes it', (tester) async {
    final calls = _recordSystemCalls();
    await pumpHomeShell(tester, queue: SettableQueue(queueOf(4, index: 1)));

    await _openQueue(tester);
    expect(_queueView, findsOneWidget);
    expect(find.byTooltip('Queue options'), findsOneWidget);
    expect(_queueMiniPlayer, findsOneWidget);
    // The queue keeps only the way out and the switch back.
    expect(find.byIcon(Icons.fullscreen_rounded), findsNothing);
    expect(_side('PLAYING'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(NowPlayingContent), findsNothing);
    expect(calls, isNot(contains('SystemNavigator.pop')));
  });

  testWidgets('the queue\'s menu holds the queue actions', (tester) async {
    await pumpHomeShell(tester, queue: SettableQueue(queueOf(3, index: 1)));
    await _openQueue(tester);

    await tester.tap(find.byTooltip('Queue options'));
    await tester.pumpAndSettle();
    expect(find.text('Clear queue'), findsOneWidget);
    expect(find.text('Clear played'), findsOneWidget);
  });

  testWidgets('the queue\'s menu turns shuffle on', (tester) async {
    late _RecordingWsApi ws;
    await pumpHomeShell(
      tester,
      queue: SettableQueue(queueOf(3)),
      overrides: [
        kalinkaWsApiProvider.overrideWith((ref) => ws = _RecordingWsApi(ref)),
      ],
    );
    await _openQueue(tester);
    await tester.tap(find.byTooltip('Queue options'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byWidgetPredicate(
        (w) =>
            w is AnimatedContainer &&
            w.constraints ==
                const BoxConstraints.tightFor(width: 42, height: 24),
      ),
    );
    await tester.pump();
    expect(
      ws.sent,
      contains(
        const QueueCommand.setPlaybackMode(
          shuffle: true,
          repeatAll: false,
          repeatSingle: false,
        ),
      ),
    );
  });

  testWidgets('the player switches between the track and its queue', (
    tester,
  ) async {
    await pumpHomeShell(tester, queue: SettableQueue(queueOf(3)));

    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerViewSwitch), findsOneWidget);
    expect(_queueView, findsNothing);
    expect(_queueMiniPlayer.hitTestable(), findsNothing);

    await tester.tap(_side('QUEUE'));
    await tester.pumpAndSettle();
    expect(_queueView, findsOneWidget);

    await tester.tap(_side('PLAYING'));
    await tester.pumpAndSettle();
    expect(_queueView, findsNothing);
    expect(find.byType(PlayerViewSwitch), findsOneWidget);

    // The queue's mini-player is a way back too.
    await tester.tap(_side('QUEUE'));
    await tester.pumpAndSettle();
    await tester.tap(_queueMiniPlayer);
    await tester.pumpAndSettle();
    expect(_queueView, findsNothing);
  });

  testWidgets('the view switch says which side is on', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpHomeShell(tester, queue: SettableQueue(queueOf(3)));
    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.bySemanticsLabel('Now playing')),
      isSemantics(isButton: true, isSelected: true),
    );
    await tester.tap(_side('QUEUE'));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.bySemanticsLabel('Now playing')),
      isSemantics(isButton: true, isSelected: false),
    );
    semantics.dispose();
  });

  testWidgets('player and queue fit a short landscape window', (tester) async {
    await pumpHomeShell(
      tester,
      queue: SettableQueue(queueOf(3)),
      size: const Size(812, 375),
    );
    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(_side('QUEUE'));
    await tester.pumpAndSettle();
    expect(_queueView, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('enlarged player keeps its playback controls reachable', (
    tester,
  ) async {
    final container = await pumpHomeShell(
      tester,
      queue: SettableQueue(queueOf(3)),
      size: const Size(375, 812),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: NowPlayingContent(showOverlayHeader: true, onClose: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byIcon(Icons.skip_next_rounded),
      200,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.skip_next_rounded).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the mini-player opens on the track, whatever was shown last', (
    tester,
  ) async {
    await pumpHomeShell(tester, queue: SettableQueue(queueOf(3)));
    await _openQueue(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();
    expect(find.byType(NowPlayingContent), findsOneWidget);
    expect(_queueView, findsNothing);
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

  testWidgets('the empty queue leads back to search', (tester) async {
    final container = await pumpHomeShell(
      tester,
      queue: SettableQueue(queueOf(0)),
    );
    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();
    await tester.tap(_side('QUEUE'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Find music'));
    await tester.pumpAndSettle();
    expect(find.byType(NowPlayingContent), findsNothing);
    expect(find.byType(SearchComposer), findsOneWidget);
    expect(container.read(searchEntryModeProvider), isTrue);
  });

  testWidgets('on a wide window the queue takes the player panel', (
    tester,
  ) async {
    await pumpHomeShell(
      tester,
      queue: SettableQueue(queueOf(3)),
      size: const Size(1280, 800),
    );

    await tester.tap(_side('QUEUE'));
    await tester.pumpAndSettle();
    expect(_queueView, findsOneWidget);
    expect(
      tester.getRect(_queueView).left,
      greaterThanOrEqualTo(
        tester.getRect(find.byType(SearchSessionView)).right,
      ),
    );
    // A panel, not a sheet: Home stays usable beside it.
    expect(find.byType(SearchSessionView).hitTestable(), findsOneWidget);

    await tester.tap(_side('PLAYING'));
    await tester.pumpAndSettle();
    expect(_queueView, findsNothing);
    expect(find.byType(PlayerViewSwitch), findsOneWidget);
  });

  testWidgets(
    'the panes share one top bar, and their divider starts below it',
    (tester) async {
      await pumpHomeShell(
        tester,
        queue: SettableQueue(queueOf(3)),
        size: const Size(1400, 900),
      );

      // One wordmark, leading browsing's half at the window's start.
      final wordmark = find.byType(KalinkaWordmark);
      expect(wordmark, findsOneWidget);
      final player = tester.getRect(find.byType(NowPlayingContent));
      expect(player.right, 1400);
      expect(tester.getRect(wordmark).right, lessThan(player.left));

      // The view tabs and the connection chip share a centre line.
      final tabs = tester.getCenter(_side('PLAYING')).dy;
      final chip = tester.getCenter(find.byType(ServerChip)).dy;
      expect(tabs, closeTo(chip, 2));

      // Nothing divides the panes across the bar itself.
      final divider = find.byWidgetPredicate(
        (w) =>
            w is Positioned &&
            w.width == 1 &&
            w.left ==
                player.left -
                    kalinkaNavigationRailWidth(1400, windowHeight: 900) -
                    1 &&
            (w.top ?? 0) > 0,
      );
      expect(divider, findsOneWidget);
      expect(
        tester.widget<Positioned>(divider).top,
        greaterThanOrEqualTo(kKalinkaTopBarHeight),
      );
      // And it paints: a hairline down to the foot of the window.
      final line = tester.getRect(
        find.descendant(of: divider, matching: find.byType(ColoredBox)),
      );
      expect(line.width, 1);
      expect(line.bottom, 900);
    },
  );

  testWidgets('a wide window bounds the player; the queue bar spans it', (
    tester,
  ) async {
    await pumpHomeShell(
      tester,
      queue: SettableQueue(queueOf(3)),
      size: const Size(1600, 900),
    );

    // Browsing takes the room the player does not need, the player the
    // window's right.
    final player = tester.getRect(find.byType(NowPlayingContent));
    expect(player.width, 440);
    expect(player.right, 1600);
    final browsing = tester.getRect(find.byType(SearchSessionView));
    expect(browsing.left, 200);
    expect(browsing.right, 1159);

    await tester.tap(_side('QUEUE'));
    await tester.pumpAndSettle();
    final bar = tester.getRect(_queueMiniPlayer);
    // Under the rail too, edge to edge.
    expect(bar.left, 0);
    expect(bar.right, 1600);
    // Browsing and the rail end above the bar rather than running under it.
    expect(
      tester.getRect(find.byType(SearchSessionView)).bottom,
      lessThanOrEqualTo(bar.top + 1),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('navigation-rail'))).bottom,
      lessThanOrEqualTo(bar.top + 1),
    );
  });

  testWidgets('the output sheet opens over the player, from it or its bar', (
    tester,
  ) async {
    await pumpHomeShell(
      tester,
      queue: SettableQueue(queueOf(3)),
      size: const Size(1400, 900),
      overrides: [rendererListProvider.overrideWith(_Renderers.new)],
    );
    final player = tester.getRect(find.byType(NowPlayingContent));

    void expectOverPlayer() {
      final sheet = tester.getRect(find.byType(RendererPickerContent));
      expect(sheet.left, greaterThanOrEqualTo(player.left));
      expect(sheet.right, lessThanOrEqualTo(player.right));
    }

    await tester.tap(find.text('SMSL SU-1'));
    await tester.pumpAndSettle();
    expectOverPlayer();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(RendererPickerContent), findsNothing);

    await tester.tap(_side('QUEUE'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: _queueMiniPlayer, matching: find.text('SMSL SU-1')),
    );
    await tester.pumpAndSettle();
    expectOverPlayer();
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
