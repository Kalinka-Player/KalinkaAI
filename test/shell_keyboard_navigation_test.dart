import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/kalinka_ws_api.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/kalinka_ws_api_provider.dart';
import 'package:kalinka/providers/renderer_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/providers/shell_nav_provider.dart';
import 'package:kalinka/widgets/mini_player.dart';
import 'package:kalinka/widgets/coach_marks_overlay.dart';
import 'package:kalinka/widgets/discovery_screen.dart';
import 'package:kalinka/widgets/now_playing_content.dart';
import 'package:kalinka/widgets/queue_item_row.dart';
import 'package:kalinka/widgets/search/search_session_view.dart';
import 'package:kalinka/widgets/shell_navigation.dart';
import 'package:kalinka/widgets/server_sheet.dart';
import 'package:kalinka/widgets/playback_progress_slider.dart';
import 'package:kalinka/widgets/renderer_switcher.dart';
import 'package:kalinka/widgets/transport_button.dart';

import 'support/focus.dart';
import 'support/home_shell.dart';

Future<void> tab(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.pumpAndSettle();
}

String? get area =>
    FocusManager.instance.primaryFocus?.nearestScope?.debugLabel;

class _KeyboardApi extends KalinkaWsApi {
  _KeyboardApi(super.ref);
  final queueCommands = <QueueCommand>[];
  final deviceCommands = <DeviceCommand>[];

  @override
  Future<void> sendQueueCommand(QueueCommand command) async =>
      queueCommands.add(command);

  @override
  Future<void> sendDeviceCommand(DeviceCommand command) async =>
      deviceCommands.add(command);
}

class _KeyboardRenderers extends RendererListNotifier {
  @override
  RendererListState build() => const RendererListState(
    loaded: true,
    renderers: [
      RendererInfo(
        rendererId: 'kitchen',
        friendlyName: 'Kitchen',
        status: 'connected',
        active: true,
        selected: true,
      ),
    ],
  );

  @override
  Future<void> refresh() async {}
}

void main() {
  for (final (width, queueVisible) in [
    (1024.0, false),
    (1440.0, false),
    (1440.0, true),
  ]) {
    testWidgets(
      'server picker exposes only visible areas at $width with queue $queueVisible',
      (tester) async {
        final container = await pumpHomeShell(
          tester,
          queue: SettableQueue(queueOf(3)),
          size: Size(width, 900),
        );
        if (queueVisible) {
          container.read(playerViewProvider.notifier).show(PlayerView.queue);
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(const ValueKey('navigation-changeServer')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final picker = find.byType(DiscoveryScreen);
        final visited = <String?>{};
        for (var i = 0; i < 8; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          visited.add(area);
          expect(
            focusIsOn(picker) ||
                focusIsOn(find.byType(ShellNavigation)) ||
                (queueVisible && focusIsOn(find.byType(MiniPlayer))),
            isTrue,
          );
        }
        expect(visited, {
          'navigation',
          'content',
          if (queueVisible) 'playback',
        });
        await tester.pump(const Duration(seconds: 8));
      },
    );
  }

  testWidgets('walkthrough owns Tab and activation until dismissed', (
    tester,
  ) async {
    await pumpHomeShell(
      tester,
      queue: SettableQueue(queueOf(3)),
      size: const Size(375, 800),
      coachMarksShown: false,
    );
    final tour = find.byType(CoachMarksOverlay);
    await tester.pump();
    expect(focusIsOn(tour), isTrue);
    expect(traversableFocusNodesIn(find.byType(MiniPlayer)), isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Find music'), findsNothing);
    final targets = <FocusNode>{};
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focusIsOn(tour), isTrue);
      targets.add(FocusManager.instance.primaryFocus!);
    }
    expect(targets, hasLength(2));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(tour, findsNothing);
    expect(await tabTo(tester, find.byType(MiniPlayer)), isTrue);
  });

  testWidgets('player sheet shares Tab with its visible rail', (tester) async {
    await pumpHomeShell(
      tester,
      queue: SettableQueue(queueOf(3)),
      size: const Size(1024, 600),
    );
    expect(await tabTo(tester, find.byType(MiniPlayer)), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(NowPlayingContent), findsOneWidget);
    final rail = find.byType(ShellNavigation);
    expect(await tabTo(tester, rail, stops: 3), isTrue);
    await tab(tester);
    expect(area, 'player');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tab(tester);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(focusIsOn(rail), isTrue);
    expect(traversableFocusNodesIn(find.byType(SearchSessionView)), isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(NowPlayingContent), findsNothing);
  });
  for (final width in [1024.0, 1440.0, 1920.0]) {
    testWidgets(
      'mini-player arrows reach every control without seeking at $width',
      (tester) async {
        late _KeyboardApi api;
        final container = await pumpHomeShell(
          tester,
          queue: SettableQueue(queueOf(3)),
          size: Size(width, 900),
          overrides: [
            kalinkaWsApiProvider.overrideWith((ref) => api = _KeyboardApi(ref)),
            rendererListProvider.overrideWith(_KeyboardRenderers.new),
            volumeStateProvider.overrideWithValue(
              DeviceVolume(
                currentVolume: 50,
                maxVolume: 100,
                supported: true,
                volumeGain: 0,
              ),
            ),
          ],
        );
        container.read(kalinkaWsApiProvider);
        container.read(playerViewProvider.notifier).show(PlayerView.queue);
        await tester.pumpAndSettle();
        final mini = find.byType(MiniPlayer);
        final progress = find.descendant(
          of: mini,
          matching: find.byType(PlaybackProgressSlider),
        );
        expect(progress, findsOneWidget);
        expect(await tabTo(tester, mini), isTrue);

        for (var i = 0; i < 12; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          await tester.pumpAndSettle();
        }
        final targets = traversableFocusNodesIn(mini).toSet();
        final visited = <FocusNode>{};
        for (var i = 0; i < 12; i++) {
          visited.add(FocusManager.instance.primaryFocus!);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pumpAndSettle();
          expect(area, 'playback');
        }
        expect(visited, containsAll(targets));
        expect(api.queueCommands, isEmpty);
        expect(api.deviceCommands, isEmpty);

        final play = find.ancestor(
          of: find.descendant(
            of: mini,
            matching: find.byIcon(Icons.pause_rounded),
          ),
          matching: find.byType(TransportButton),
        );
        for (var i = 0; i < 12 && !focusIsOn(play); i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          await tester.pumpAndSettle();
        }
        expect(focusIsOn(play), isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(api.queueCommands, [const QueueCommand.pause(paused: true)]);

        for (var i = 0; i < 12 && !focusIsOn(progress); i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          await tester.pumpAndSettle();
        }
        expect(focusIsOn(progress), isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(
          api.queueCommands.whereType<SeekCommand>().single.positionMs,
          greaterThan(0),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(focusIsOn(progress), isTrue);

        final output = find.descendant(
          of: mini,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is RendererSwitcherDropdown ||
                widget is RendererSwitcherButton,
          ),
        );
        for (var i = 0; i < 12 && !focusIsOn(output); i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pumpAndSettle();
        }
        expect(focusIsOn(output), isTrue);
        expect(api.queueCommands.whereType<SeekCommand>(), hasLength(1));
        expect(api.deviceCommands, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'toolbar connection control opens with Space and restores focus',
    (tester) async {
      await pumpHomeShell(
        tester,
        queue: SettableQueue(queueOf(2)),
        size: const Size(1440, 900),
      );
      await tab(tester);
      await tab(tester);
      expect(area, 'toolbar');
      final caller = FocusManager.instance.primaryFocus;
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.byType(ServerSheetContent), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, same(caller));
    },
  );

  testWidgets('large text keeps area navigation with reduced motion', (
    tester,
  ) async {
    await pumpHomeShell(
      tester,
      queue: SettableQueue(queueOf(2)),
      size: const Size(1024, 800),
      textScaler: const TextScaler.linear(3),
      reducedMotion: true,
    );
    for (final expected in ['toolbar', 'content', 'playback', 'toolbar']) {
      await tab(tester);
      expect(area, expected);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'queue arrows reach every row and keep it above the playback bar',
    (tester) async {
      final container = await pumpHomeShell(
        tester,
        queue: SettableQueue(queueOf(60)),
        size: const Size(1440, 900),
      );
      container.read(playerViewProvider.notifier).show(PlayerView.queue);
      await tester.pumpAndSettle();
      final first = FocusManager.instance.rootScope.descendants.firstWhere(
        (node) =>
            node.canRequestFocus &&
            !node.skipTraversal &&
            node.context
                    ?.findAncestorWidgetOfExactType<QueueItemRow>()
                    ?.index ==
                0,
      );
      first.requestFocus();
      await tester.pump();
      for (var index = 1; index < 60; index++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        final node = FocusManager.instance.primaryFocus!;
        expect(
          node.context?.findAncestorWidgetOfExactType<QueueItemRow>()?.index,
          index,
        );
        expect(
          node.rect.bottom,
          lessThanOrEqualTo(
            tester.getTopLeft(find.byType(MiniPlayer)).dy + 0.1,
          ),
          reason: 'row $index must clear the bar',
        );
      }
    },
  );

  testWidgets('phone player opens from keyboard focus on playback artwork', (
    tester,
  ) async {
    await pumpHomeShell(
      tester,
      queue: SettableQueue(queueOf(2)),
      size: const Size(375, 800),
    );
    await tab(tester);
    await tab(tester);
    await tab(tester);
    expect(area, 'playback');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(NowPlayingContent), findsOneWidget);
    await tab(tester);
    expect(area, 'player');
  });

  testWidgets('desktop queue cycles through all five visible shell areas', (
    tester,
  ) async {
    final container = await pumpHomeShell(
      tester,
      queue: SettableQueue(queueOf(30)),
      size: const Size(1440, 900),
    );
    container.read(playerViewProvider.notifier).show(PlayerView.queue);
    await tester.pumpAndSettle();
    for (var cycle = 0; cycle < 2; cycle++) {
      for (final expected in [
        'navigation',
        'toolbar',
        'content',
        'playback',
        'player',
      ]) {
        await tab(tester);
        expect(area, expected, reason: 'cycle $cycle');
      }
    }
    expect(focusIsOn(find.byType(NowPlayingContent)), isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(375, 800),
    const Size(800, 375),
    const Size(1024, 600),
  ]) {
    testWidgets('compact shell uses only visible areas at $size', (
      tester,
    ) async {
      await pumpHomeShell(tester, queue: SettableQueue(queueOf(2)), size: size);
      final rail = find.byType(ShellNavigation).evaluate().isNotEmpty;
      final expected = [
        if (rail) 'navigation',
        'toolbar',
        'content',
        'playback',
      ];
      for (var cycle = 0; cycle < 2; cycle++) {
        for (final name in expected) {
          await tab(tester);
          expect(area, name);
        }
      }
      expect(focusIsOn(find.byType(MiniPlayer)), isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'changing queue view and resizing drops hidden areas from Tab order',
    (tester) async {
      final container = await pumpHomeShell(
        tester,
        queue: SettableQueue(queueOf(2)),
        size: const Size(1440, 900),
      );
      container.read(playerViewProvider.notifier).show(PlayerView.queue);
      await tester.pumpAndSettle();
      for (var i = 0; i < 4; i++) {
        await tab(tester);
      }
      expect(area, 'playback');
      container.read(playerViewProvider.notifier).show(PlayerView.nowPlaying);
      await tester.pumpAndSettle();
      final visited = <String?>{};
      for (var i = 0; i < 6; i++) {
        await tab(tester);
        visited.add(area);
      }
      expect(
        visited,
        containsAll(['navigation', 'toolbar', 'content', 'player']),
      );
      expect(visited, isNot(contains('playback')));
      tester.view.physicalSize = const Size(375, 800);
      await tester.pumpAndSettle();
      visited.clear();
      for (var i = 0; i < 5; i++) {
        await tab(tester);
        visited.add(area);
      }
      expect(visited, containsAll(['toolbar', 'content', 'playback']));
      expect(visited, isNot(contains('navigation')));
      expect(visited, isNot(contains('player')));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('catalog toolbar and content remain separate areas', (
    tester,
  ) async {
    final container = await pumpHomeShell(
      tester,
      queue: SettableQueue(queueOf(2)),
      size: const Size(1440, 900),
    );
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(id: 'kalinka:localfiles:catalog:albums', title: 'Albums');
    await tester.pumpAndSettle();
    await tab(tester);
    expect(area, 'navigation');
    await tab(tester);
    expect(area, 'toolbar');
    expect(focusIsOn(find.byType(SearchSessionView)), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(area, 'toolbar');
    await tab(tester);
    expect(area, isNot('toolbar'));
    expect(tester.takeException(), isNull);
  });
}
