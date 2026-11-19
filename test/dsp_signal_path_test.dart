import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/playqueue_events.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/playback_events_provider.dart';
import 'package:kalinka/providers/wire_event_provider.dart';
import 'package:kalinka/widgets/dsp_readout.dart';

// A renderer reports what its DSP does to a track in the state, and what
// happens to the track as it plays on the queue socket. An older server sends
// neither.

const _path = SignalPath(
  steps: [
    SignalStep(
      kind: 'dsd_to_pcm',
      name: 'DSD to PCM',
      summary: 'DSD64 to 176.4 kHz, 30 kHz filter',
    ),
  ],
  latencyMs: 0.3,
);

const _track1 = 'kalinka:localfiles:track:1';
const _track2 = 'kalinka:localfiles:track:2';

Map<String, dynamic> _clippingJson({int seq = 7, int clipped = 1200}) => {
  'event_type': 'playback_event',
  'seq': seq,
  'kind': 'clipping',
  'details': {'clipped_samples': clipped},
};

PlayQueueEvent _clipping(int clipped) =>
    PlayQueueEvent.fromJson(_clippingJson(clipped: clipped));

class _Queue extends PlayQueueStateStore {
  @override
  PlayQueueState build() => PlayQueueState.empty;

  void set(PlayQueueState next) => state = next;
}

PlayQueueState _playing({
  String trackId = _track1,
  String renderer = 'pi',
  PlayerStateType state = PlayerStateType.playing,
  int position = 0,
}) => PlayQueueState(
  playbackState: PlaybackState(
    state: state,
    currentTrack: Track(id: trackId, title: 'Sonata', duration: 300),
    position: position,
    audioInfo: AudioInfo(output: OutputInfo(signalPath: _path)),
  ),
  trackList: const [],
  playbackMode: PlaybackMode.empty,
  seq: 1,
  currentRendererId: renderer,
);

typedef _Harness = ({
  ProviderContainer container,
  StreamController<PlayQueueEvent> events,
});

/// [queue] stands in for the queue store; without it the real one applies
/// the events.
_Harness _harness({_Queue Function()? queue}) {
  // Synchronous: two events can land before the store applies the first.
  final events = StreamController<PlayQueueEvent>(sync: true);
  final container = ProviderContainer(
    overrides: [
      if (queue != null) playQueueStateStoreProvider.overrideWith(queue),
      playQueueEventBusProvider.overrideWith((ref) => events.stream),
    ],
  );
  addTearDown(() {
    container.dispose();
    events.close();
  });
  // The queue store holds the socket open in the app.
  container.listen(playQueueStateStoreProvider, (_, _) {});
  container.listen(playbackEventsProvider, (_, _) {});
  return (container: container, events: events);
}

// Riverpod refreshes dependents on a zero-length timer.
void _settle(FakeAsync async) => async.elapse(Duration.zero);

Map<String, Map<String, Object?>> _kept(_Harness h) =>
    h.container.read(playbackEventsProvider);

/// What is kept once [next] follows a state the track clipped in.
Map<String, Map<String, Object?>> _keptAfter(PlayQueueState next) {
  late Map<String, Map<String, Object?>> after;
  fakeAsync((async) {
    final h = _harness(queue: _Queue.new);
    final queue = h.container.read(playQueueStateStoreProvider.notifier);
    (queue as _Queue).set(_playing());
    _settle(async);
    h.events.add(_clipping(3));
    _settle(async);
    expect(_kept(h), isNotEmpty);

    queue.set(next);
    _settle(async);
    after = _kept(h);
  });
  return after;
}

PlayQueueEvent _stateFor(String trackId, int seq) =>
    PlayQueueEvent.playbackStateChanged(
      state: PlaybackState(
        state: PlayerStateType.playing,
        currentTrack: Track(id: trackId, title: 'Sonata', duration: 300),
      ),
      seq: seq,
    );

void main() {
  group('the wire', () {
    test('the signal path is read in order, step by step', () {
      final output = OutputInfo.fromJson({
        'sample_format': 'PCM24_LE',
        'sample_rate': 176400,
        'lossless_path': false,
        'signal_path': {
          'steps': [
            {
              'kind': 'dsd_to_pcm',
              'name': 'DSD to PCM',
              'summary': 'DSD64 to 176.4 kHz, 30 kHz filter',
            },
            {'kind': 'dsd_gain', 'name': 'DSD gain', 'summary': '+2.8 dB'},
            {'kind': 'dither', 'name': 'Dither', 'summary': 'TPDF at 24 bits'},
          ],
          'latency_ms': 0.3,
        },
      });

      final path = output.signalPath!;
      expect(path.steps.map((s) => s.kind), [
        'dsd_to_pcm',
        'dsd_gain',
        'dither',
      ]);
      expect(path.steps[1].summary, '+2.8 dB');
      expect(path.latencyMs, 0.3);
      expect(
        OutputInfo.fromJson(output.toJson()).signalPath!.steps.last.name,
        'Dither',
      );
    });

    test('an older server, or an untouched path, has no signal path', () {
      expect(OutputInfo.fromJson({'sample_rate': 44100}).signalPath, isNull);
      expect(OutputInfo.fromJson({'signal_path': null}).signalPath, isNull);
      expect(
        OutputInfo.fromJson({
          'signal_path': {'steps': [], 'latency_ms': 0},
        }).signalPath,
        isNull,
      );
    });

    test('a playback event arrives on the queue socket', () {
      final event = PlayQueueEvent.fromJson(_clippingJson());

      expect(
        event,
        const PlayQueueEvent.playbackEvent(
          kind: 'clipping',
          details: {'clipped_samples': 1200},
          seq: 7,
        ),
      );
    });

    test('a kind the app does not know is taken with its details', () {
      final event = PlayQueueEvent.fromJson({
        'event_type': 'playback_event',
        'seq': 8,
        'kind': 'output_underrun',
        'details': {
          'frames': 512,
          'device': {'name': 'hw:0'},
        },
      });

      expect(event, isA<PlaybackEvent>());
      event as PlaybackEvent;
      expect(event.kind, 'output_underrun');
      expect(event.details, {
        'frames': 512,
        'device': {'name': 'hw:0'},
      });
    });

    test('an event without details has none', () {
      final event = PlayQueueEvent.fromJson({
        'event_type': 'playback_event',
        'seq': 9,
        'kind': 'output_underrun',
      });

      expect((event as PlaybackEvent).details, isEmpty);
    });

    test('playback events leave the queue state as it was', () {
      final before = _playing();
      expect(before.apply(_clipping(1200), 0), same(before));
    });

    test('an event type the app does not know is skipped', () async {
      final bus = makeEventBusProvider<PlayQueueEvent>(
        openStream: (_, _) => Stream.fromIterable([
          '{"event_type": "something_new", "seq": 1}',
          '{"event_type": "request_more_tracks", "seq": 2}',
        ]),
        decodeEvent: (json) =>
            PlayQueueEvent.fromJson(json as Map<String, Object?>),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.listen(bus, (_, _) {});

      final first = await container.read(bus.future);
      expect(first, const PlayQueueEvent.requestMoreTracks(seq: 2));
    });

    test('a playback event of an unknown kind comes through', () async {
      final bus = makeEventBusProvider<PlayQueueEvent>(
        openStream: (_, _) => Stream.fromIterable([
          '{"event_type": "playback_event", "seq": 1, "kind": "underrun",'
              ' "details": {"frames": 512}}',
          '{"event_type": "request_more_tracks", "seq": 2}',
        ]),
        decodeEvent: (json) =>
            PlayQueueEvent.fromJson(json as Map<String, Object?>),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.listen(bus, (_, _) {});

      final first = await container.read(bus.future);
      expect((first as PlaybackEvent).kind, 'underrun');
    });
  });

  group('dspReadings', () {
    test('the latency stands without a playback event', () {
      expect(dspReadings(_path, const {}), [
        (label: 'DSP latency', value: '0.3 ms', alarm: false),
      ]);
    });

    test('clipping reads as the latest count, flagged', () {
      expect(
        dspReadings(_path, const {
          'clipping': {'clipped_samples': 1200},
        }),
        [
          (label: 'DSP latency', value: '0.3 ms', alarm: false),
          (label: 'Clipped', value: '1200', alarm: true),
        ],
      );
    });

    test('a track that has not clipped shows no count, not 0', () {
      const steps = SignalPath(steps: [SignalStep(kind: 'dither')]);

      expect(dspReadings(steps, const {}), isEmpty);
      expect(
        dspReadings(steps, const {
          'clipping': {'clipped_samples': 0},
        }),
        isEmpty,
      );
    });

    test('only the kinds it knows are read', () {
      expect(
        dspReadings(null, const {
          'output_underrun': {'clipped_samples': 5},
        }),
        isEmpty,
      );
    });

    test('a count that is not a number is not read', () {
      expect(
        dspReadings(null, const {
          'clipping': {'clipped_samples': 'many'},
        }),
        isEmpty,
      );
      expect(dspReadings(null, const {'clipping': {}}), isEmpty);
    });
  });

  group('playbackEventsProvider', () {
    test('the latest details of each kind are kept, with no expiry', () {
      fakeAsync((async) {
        final h = _harness(queue: _Queue.new);
        final queue =
            h.container.read(playQueueStateStoreProvider.notifier) as _Queue;
        queue.set(_playing());
        _settle(async);
        expect(_kept(h), isEmpty);

        h.events
          ..add(_clipping(3))
          ..add(
            const PlayQueueEvent.playbackEvent(
              kind: 'output_underrun',
              details: {'frames': 512},
              seq: 8,
            ),
          )
          ..add(_clipping(1200));
        _settle(async);
        async.elapse(const Duration(minutes: 5));

        expect(_kept(h), {
          'clipping': {'clipped_samples': 1200},
          'output_underrun': {'frames': 512},
        });
      });
    });

    test('a new state for the same track keeps them', () {
      expect(
        _keptAfter(_playing(state: PlayerStateType.paused, position: 9000)),
        isNotEmpty,
      );
    });

    test('the next track does not inherit the last one\'s', () {
      expect(_keptAfter(_playing(trackId: _track2)), isEmpty);
    });

    test('another renderer does not inherit them either', () {
      expect(_keptAfter(_playing(renderer: 'desk')), isEmpty);
    });

    test('an event right behind the next track\'s state is that track\'s', () {
      fakeAsync((async) {
        final h = _harness();
        h.events.add(_stateFor(_track1, 1));
        _settle(async);

        h.events
          ..add(_stateFor(_track2, 2))
          ..add(_clipping(5));
        _settle(async);

        expect(h.container.read(playerStateProvider).currentTrack?.id, _track2);
        expect(_kept(h), {
          'clipping': {'clipped_samples': 5},
        });
      });
    });

    test(
      'an event right ahead of the next track\'s state is the last one\'s',
      () {
        fakeAsync((async) {
          final h = _harness();
          h.events.add(_stateFor(_track1, 1));
          _settle(async);

          h.events
            ..add(_clipping(5))
            ..add(_stateFor(_track2, 2));
          _settle(async);

          expect(_kept(h), isEmpty);
        });
      },
    );
  });
}
