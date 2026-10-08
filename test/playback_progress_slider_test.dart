import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/kalinka_ws_api.dart';
import 'package:kalinka/data_model/playqueue_events.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/kalinka_ws_api_provider.dart';
import 'package:kalinka/providers/monotonic_clock_provider.dart';
import 'package:kalinka/widgets/kiosk/kiosk_progress_bar.dart';
import 'package:kalinka/widgets/playback_progress_slider.dart';

import 'support/haptic_recorder.dart';

const _duration = 120000;

PlayQueueState _queue({
  int position = 20000,
  int seq = 1,
  String track = 'one',
  PlayerStateType state = PlayerStateType.playing,
}) => PlayQueueState(
  playbackState: PlaybackState(
    currentTrack: Track(id: track, title: track, duration: 120),
    position: position,
    state: state,
  ),
  trackList: const [],
  playbackMode: PlaybackMode.empty,
  seq: seq,
);

class _Queue extends PlayQueueStateStore {
  @override
  PlayQueueState build() => _queue();
  void emit(PlayQueueState next) => state = next;
  void unrelatedEvent() => state = state.copyWith(seq: state.seq + 1);
}

class _Api extends KalinkaWsApi {
  _Api(super.ref);
  final commands = <SeekCommand>[];
  Future<void> Function()? onSend;

  @override
  Future<void> sendQueueCommand(QueueCommand command) async {
    commands.add(command as SeekCommand);
    await onSend?.call();
  }
}

Future<({_Queue queue, _Api api})> _pump(
  WidgetTester tester, {
  bool kiosk = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playQueueStateStoreProvider.overrideWith(_Queue.new),
        kalinkaWsApiProvider.overrideWith((ref) => _Api(ref)),
        // Freeze interpolation; actual server positions still flow through the
        // real playbackTimeMsProvider, rather than a separately updated fake.
        monotonicClockProvider.overrideWithValue(Stopwatch()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: kiosk
                  ? const KioskProgressBar(durationMs: _duration, scale: 1)
                  : const PlaybackProgressSlider(durationMs: _duration),
            ),
          ),
        ),
      ),
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(
      find.byType(kiosk ? KioskProgressBar : PlaybackProgressSlider),
    ),
  );
  return (
    queue: container.read(playQueueStateStoreProvider.notifier) as _Queue,
    api: container.read(kalinkaWsApiProvider) as _Api,
  );
}

int _position(WidgetTester tester) =>
    (tester.widget<Slider>(find.byType(Slider)).value * _duration).round();

Future<void> _seek(WidgetTester tester, double fraction) async {
  final slider = tester.widget<Slider>(find.byType(Slider));
  slider.onChangeStart?.call(slider.value);
  slider.onChanged!(fraction);
  slider.onChangeEnd!(fraction);
  await tester.pump();
}

void main() {
  testWidgets(
    'playback and unrelated queue updates cannot interrupt a held drag',
    (tester) async {
      final h = await _pump(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Slider)),
      );
      await gesture.moveBy(const Offset(80, 0));
      await tester.pump();
      final dragged = _position(tester);
      expect(dragged, greaterThan(60000));

      h.queue.emit(_queue(position: 21000, seq: 2));
      await tester.pump();
      expect(_position(tester), closeTo(dragged, 1));
      h.queue.unrelatedEvent();
      await tester.pump();
      expect(_position(tester), closeTo(dragged, 1));
      expect(h.api.commands, isEmpty);
      await gesture.up();
      await tester.pump();
      expect(h.api.commands.single.positionMs, closeTo(dragged, 1));
      expect(_position(tester), closeTo(dragged, 1));
    },
  );

  testWidgets(
    'holds the target through old positions until a fresh matching update',
    (tester) async {
      final h = await _pump(tester);
      await _seek(tester, 0.75);
      h.queue.unrelatedEvent();
      await tester.pump();
      expect(_position(tester), 90000);
      h.queue.emit(_queue(position: 22000, seq: 3));
      await tester.pump();
      expect(_position(tester), 90000);
      h.queue.emit(_queue(position: 90000, seq: 1)); // stale sequence
      await tester.pump();
      h.queue.emit(_queue(position: 23000, seq: 4));
      await tester.pump();
      expect(_position(tester), 90000);
      h.queue.emit(_queue(position: 90500, seq: 5));
      await tester.pump();
      expect(_position(tester), 90500);
      h.queue.emit(_queue(position: 91500, seq: 6));
      await tester.pump();
      expect(_position(tester), 91500);
      expect(h.api.commands.single.positionMs, 90000);
    },
  );

  testWidgets(
    'an earlier seek acknowledgement cannot replace a newer backward seek',
    (tester) async {
      final h = await _pump(tester);
      await _seek(tester, 0.75);
      await _seek(tester, 0.25);
      h.queue.emit(_queue(position: 90000, seq: 2));
      await tester.pump();
      expect(_position(tester), 30000);
      h.queue.emit(
        _queue(position: 30000, seq: 3, state: PlayerStateType.paused),
      );
      await tester.pump();
      h.queue.emit(_queue(position: 31000, seq: 4));
      await tester.pump();
      expect(_position(tester), 31000);
      expect(h.api.commands.map((c) => c.positionMs), [90000, 30000]);
    },
  );

  testWidgets(
    'missing confirmation eventually returns to the reported position',
    (tester) async {
      final h = await _pump(tester);
      await _seek(tester, 0.75);
      h.queue.emit(_queue(position: 22000, seq: 2));
      await tester.pump(const Duration(seconds: 4));
      expect(_position(tester), 90000);
      await tester.pump(const Duration(seconds: 2));
      expect(_position(tester), 22000);
    },
  );

  testWidgets('send failure clears only the seek that failed', (tester) async {
    final h = await _pump(tester);
    final first = Completer<void>();
    h.api.onSend = () => first.future;
    await _seek(tester, 0.75);
    h.api.onSend = null;
    await _seek(tester, 0.25);
    first.completeError(StateError('Connection closed'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(_position(tester), 30000);

    h.api.onSend = () => Future.error(StateError('Connection closed'));
    await _seek(tester, 0.5);
    expect(tester.takeException(), isNull);
    expect(_position(tester), 20000);
  });

  testWidgets(
    'track change cancels the gesture without seeking the new track',
    (tester) async {
      final h = await _pump(tester);
      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeStart?.call(slider.value);
      slider.onChanged!(0.75);
      h.queue.emit(_queue(track: 'two', position: 5000, seq: 2));
      await tester.pump();
      slider.onChanged!(0.8);
      slider.onChangeEnd!(0.8);
      await tester.pump();
      expect(_position(tester), 5000);
      expect(h.api.commands, isEmpty);
      await _seek(tester, 0.25);
      expect(h.api.commands.single.positionMs, 30000);
    },
  );

  testWidgets('stopping playback clears a pending seek', (tester) async {
    final h = await _pump(tester);
    await _seek(tester, 0.75);
    h.queue.emit(_queue(position: 0, seq: 2, state: PlayerStateType.stopped));
    await tester.pump();
    expect(_position(tester), 0);
  });

  testWidgets('a seek ticks every 5% and taps lightly on release', (
    tester,
  ) async {
    final haptics = HapticRecorder.install();
    await _pump(tester);
    final slider = tester.widget<Slider>(find.byType(Slider));
    final start = slider.value;

    slider.onChangeStart!(start);
    slider.onChanged!(start + 0.03);
    await tester.pump();
    expect(haptics.calls, isEmpty);

    slider.onChanged!(start + 0.06);
    await tester.pump();
    expect(haptics.calls, ['selectionClick']);

    slider.onChangeEnd!(start + 0.06);
    await tester.pump();
    expect(haptics.calls, ['selectionClick', 'lightImpact']);
  });

  testWidgets(
    'kiosk bar also holds its target across unrelated queue updates',
    (tester) async {
      final h = await _pump(tester, kiosk: true);
      final bar = tester.getRect(find.byType(KioskProgressBar));
      await tester.tapAt(Offset(bar.left + bar.width * 0.75, bar.center.dy));
      await tester.pump();
      h.queue.unrelatedEvent();
      await tester.pump();
      expect(find.text('1:30'), findsOneWidget);
      expect(h.api.commands.single.positionMs, 90000);
    },
  );
}
