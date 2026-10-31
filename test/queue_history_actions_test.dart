import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/kalinka_ws_api.dart';
import 'package:kalinka/data_model/playqueue_events.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/kalinka_ws_api_provider.dart';
import 'package:kalinka/providers/toast_provider.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/queue_item_row.dart';
import 'package:kalinka/widgets/queue_zone.dart';

import 'support/home_shell.dart';

class _QueueApi extends HomeApi {
  final moves = <(int, int)>[];
  final removals = <int>[];
  late ProviderContainer container;
  Exception? failure;
  Completer<void>? pending;

  void _apply(PlayQueueEvent event) {
    final state = container.read(playQueueStateStoreProvider);
    (container.read(playQueueStateStoreProvider.notifier) as SettableQueue).set(
      state.apply(event, 0),
    );
  }

  @override
  Future<StatusMessage> move(int fromIndex, int toIndex) async {
    moves.add((fromIndex, toIndex));
    await pending?.future;
    if (failure != null) throw failure!;
    _apply(
      PlayQueueEvent.trackMoved(fromIndex: fromIndex, toIndex: toIndex, seq: 1),
    );
    return StatusMessage();
  }

  @override
  Future<StatusMessage> remove(int index) async {
    removals.add(index);
    if (failure != null) throw failure!;
    final currentIndex = container
        .read(playQueueStateStoreProvider)
        .playbackState
        .index!;
    _apply(PlayQueueEvent.tracksRemoved(indices: [index], seq: 1));
    // The server follows removal with the adjusted playback state.
    if (index < currentIndex) {
      _apply(
        PlayQueueEvent.playbackStateChanged(
          state: PlaybackState(index: currentIndex - 1),
          seq: 2,
        ),
      );
    }
    return StatusMessage();
  }
}

class _Ws extends KalinkaWsApi {
  _Ws(super.ref);
  final sent = <QueueCommand>[];

  @override
  Future<void> sendQueueCommand(QueueCommand command) async =>
      sent.add(command);
}

Future<_QueueApi> _pump(
  WidgetTester tester, {
  PlayQueueState? initial,
  Size size = const Size(375, 800),
  double scale = 1,
  bool reducedMotion = false,
}) async {
  final api = _QueueApi();
  final container = await pumpHomeShell(
    tester,
    queue: SettableQueue(initial ?? queueOf(5, index: 2)),
    api: api,
    size: size,
    overrides: [kalinkaWsApiProvider.overrideWith(_Ws.new)],
  );
  api.container = container;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: reducedMotion,
          ),
          child: child!,
        ),
        home: const Scaffold(body: QueueZone(bottomPadding: 16)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

Finder _row(String id) => find.byWidgetPredicate(
  (widget) => widget is QueueItemRow && widget.track.id == id,
);

Future<void> _swipe(WidgetTester tester, Finder row, double dx) async {
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  // Start clear of the edges so the gesture stays in a phone-sized viewport.
  final box = tester.getRect(row);
  final start = Offset(dx > 0 ? box.left + 60 : box.right - 90, box.center.dy);
  await tester.dragFrom(start, Offset(dx, 0));
  await tester.pumpAndSettle();
}

void main() {
  for (final playedIndex in [0, 1]) {
    testWidgets(
      'right swipe moves played occurrence $playedIndex after current',
      (tester) async {
        final api = await _pump(tester);
        await _swipe(tester, _row('t$playedIndex'), 180);

        final state = api.container.read(playQueueStateStoreProvider);
        expect(api.moves, [(playedIndex, 2)]);
        expect(api.removals, isEmpty);
        expect(state.trackList.map((t) => t.id), [
          playedIndex == 0 ? 't1' : 't0',
          't2',
          't$playedIndex',
          't3',
          't4',
        ]);
        expect(state.playbackState.index, 1);
        expect(state.playbackState.state, PlayerStateType.playing);
        expect(
          tester.widget<QueueItemRow>(_row('t$playedIndex')).isHistory,
          isFalse,
        );
        expect((api.container.read(kalinkaWsApiProvider) as _Ws).sent, isEmpty);
        expect(tester.takeException(), isNull);
        api.container.dispose();
      },
    );
  }

  testWidgets(
    'left swipe removes a played occurrence and keeps current playing',
    (tester) async {
      final api = await _pump(tester);
      await _swipe(tester, _row('t0'), -180);

      final state = api.container.read(playQueueStateStoreProvider);
      expect(api.removals, [0]);
      expect(api.moves, isEmpty);
      expect(state.trackList.map((t) => t.id), ['t1', 't2', 't3', 't4']);
      expect(state.playbackState.index, 1);
      expect(state.playbackState.state, PlayerStateType.playing);
      expect(_row('t0'), findsNothing);
      expect(tester.takeException(), isNull);
      api.container.dispose();
    },
  );

  testWidgets('tapping history still plays its existing queue index', (
    tester,
  ) async {
    final api = await _pump(tester);
    await tester.tap(find.text('Track t0'));
    await tester.pump();
    expect((api.container.read(kalinkaWsApiProvider) as _Ws).sent, [
      const QueueCommand.play(index: 0),
    ]);
    expect(api.moves, isEmpty);
    expect(api.removals, isEmpty);
    api.container.dispose();
  });

  testWidgets('current and upcoming rows retain left-swipe removal only', (
    tester,
  ) async {
    final api = await _pump(tester);
    await _swipe(tester, _row('t2'), 180);
    await _swipe(tester, _row('t3'), 180);
    expect(api.moves, isEmpty);
    expect(api.removals, isEmpty);
    await _swipe(tester, _row('t3'), -180);
    expect(api.removals, [3]);
    await _swipe(tester, _row('t2'), -180);
    expect(api.removals, [3, 2]);
    api.container.dispose();
  });

  for (final dx in [-180.0, 180.0]) {
    testWidgets(
      'failed ${dx < 0 ? 'removal' : 'play next'} leaves history usable',
      (tester) async {
        final api = await _pump(tester);
        api.failure = Exception('Server refused');
        await _swipe(tester, _row('t0'), dx);
        expect(
          api.container.read(playQueueStateStoreProvider).trackList.length,
          5,
        );
        expect(tester.getSize(_row('t0')).height, greaterThan(44));
        expect(api.container.read(toastProvider).last.isError, isTrue);

        api.failure = null;
        await _swipe(tester, _row('t0'), dx);
        expect(dx < 0 ? api.removals.length : api.moves.length, 2);
        expect(tester.takeException(), isNull);
        api.container.dispose();
      },
    );
  }

  testWidgets('a pending play-next move cannot be sent twice', (tester) async {
    final api = await _pump(tester);
    api.pending = Completer<void>();
    await _swipe(tester, _row('t0'), 180);
    await _swipe(tester, _row('t0'), 180);
    expect(api.moves, [(0, 2)]);
    api.pending!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    api.container.dispose();
  });

  testWidgets('history gestures stay inactive while reconnecting', (
    tester,
  ) async {
    final api = await _pump(tester);
    (api.container.read(connectionStateProvider.notifier) as SettableConnection)
        .set(ConnectionStatus.reconnecting);
    await tester.pumpAndSettle();
    await _swipe(tester, _row('t0'), 180);
    await _swipe(tester, _row('t0'), -180);
    expect(api.moves, isEmpty);
    expect(api.removals, isEmpty);
    api.container.dispose();
  });

  testWidgets(
    'replaying a song already up next keeps both occurrences usable',
    (tester) async {
      final initial = queueOf(4, index: 1);
      final earlier = initial.trackList[0];
      final later = earlier.copyWith();
      final api = await _pump(
        tester,
        initial: initial.copyWith(
          trackList: [
            earlier,
            initial.trackList[1],
            later,
            initial.trackList[3],
          ],
          seq: 0,
        ),
      );
      await _swipe(
        tester,
        find.byWidgetPredicate(
          (widget) =>
              widget is QueueItemRow && identical(widget.track, earlier),
        ),
        180,
      );

      expect(api.moves, [(0, 1)]);
      expect(tester.takeException(), isNull);
      expect(_row('t0'), findsNWidgets(2));
      expect(
        tester
            .widgetList<QueueItemRow>(_row('t0'))
            .map((row) => row.key)
            .toSet(),
        hasLength(2),
      );
      await _swipe(
        tester,
        find.byWidgetPredicate(
          (widget) => widget is QueueItemRow && identical(widget.track, later),
        ),
        -180,
      );
      expect(api.removals, [2]);
      expect(
        api.container.read(playQueueStateStoreProvider).trackList[1],
        same(earlier),
      );
      api.container.dispose();
    },
  );

  testWidgets('reconnecting disables history accessibility actions', (
    tester,
  ) async {
    final api = await _pump(tester);
    Iterable<String> actionLabels() => tester
        .widgetList<Semantics>(
          find.descendant(of: _row('t0'), matching: find.byType(Semantics)),
        )
        .expand(
          (semantics) =>
              semantics.properties.customSemanticsActions?.keys.map(
                (action) => action.label!,
              ) ??
              <String>[],
        );
    expect(actionLabels(), containsAll(['Play next', 'Remove from queue']));
    (api.container.read(connectionStateProvider.notifier) as SettableConnection)
        .set(ConnectionStatus.reconnecting);
    await tester.pumpAndSettle();
    expect(actionLabels(), isEmpty);
    api.container.dispose();
  });

  for (final (size, scale) in [
    (const Size(375, 800), 2.0),
    (const Size(800, 375), 1.0),
  ]) {
    testWidgets(
      'history works at $size / ${scale}x with reduced motion and no upcoming tracks',
      (tester) async {
        final api = await _pump(
          tester,
          initial: queueOf(3, index: 2),
          size: size,
          scale: scale,
          reducedMotion: true,
        );
        await _swipe(tester, _row('t1'), 180);
        expect(api.moves, [(1, 2)]);
        expect(
          api.container
              .read(playQueueStateStoreProvider)
              .trackList
              .map((t) => t.id),
          ['t0', 't2', 't1'],
        );
        expect(tester.takeException(), isNull);
        api.container.dispose();
      },
    );
  }
}
