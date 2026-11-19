import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/playqueue_events.dart';
import 'package:kalinka/providers/app_state_provider.dart';
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

Map<String, dynamic> _clippingJson({
  int seq = 7,
  int clipped = 1200,
  String? play,
}) => {
  'event_type': 'playback_event',
  'seq': seq,
  'play_id': ?play,
  'kind': 'clipping',
  'details': {'clipped_samples': clipped},
};

PlayQueueEvent _clipping(int clipped, {String? play}) =>
    PlayQueueEvent.fromJson(_clippingJson(clipped: clipped, play: play));

PlaybackState _playback(
  String? play, {
  String track = _track1,
  PlayerStateType state = PlayerStateType.playing,
}) => PlaybackState(
  state: state,
  currentTrack: Track(id: track, title: 'Sonata', duration: 300),
  audioInfo: AudioInfo(output: OutputInfo(signalPath: _path)),
  playId: play,
);

PlayQueueEvent _state(
  String? play, {
  String track = _track1,
  PlayerStateType state = PlayerStateType.playing,
}) => PlayQueueEvent.playbackStateChanged(
  state: _playback(play, track: track, state: state),
  seq: 1,
);

PlayQueueEvent _replay(String? play) => PlayQueueEvent.replayEvent(
  state: PlayQueueState(
    playbackState: _playback(play),
    trackList: const [],
    playbackMode: PlaybackMode.empty,
    seq: 1,
  ),
  serverTimeNs: 0,
  seq: 1,
);

/// The current play's events once the queue state has taken [events] in order.
Map<String, Map<String, Object?>> _shownAfter(List<PlayQueueEvent> events) =>
    events
        .fold(PlayQueueState.empty, (s, e) => s.apply(e, 0))
        .currentPlaybackEvents;

typedef _Harness = ({
  ProviderContainer container,
  StreamController<PlayQueueEvent> events,
});

/// The real queue store, fed what [_Harness.events] is given.
_Harness _harness() {
  // Synchronous: two events can land before the store applies the first.
  final events = StreamController<PlayQueueEvent>(sync: true);
  final container = ProviderContainer(
    overrides: [playQueueEventBusProvider.overrideWith((ref) => events.stream)],
  );
  addTearDown(() {
    container.dispose();
    events.close();
  });
  // The queue store holds the socket open in the app.
  container.listen(playQueueStateStoreProvider, (_, _) {});
  return (container: container, events: events);
}

// Riverpod refreshes dependents on a zero-length timer.
void _settle(FakeAsync async) => async.elapse(Duration.zero);

Map<String, Map<String, Object?>> _shown(_Harness h) =>
    h.container.read(playbackEventsProvider);

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

    test('an event without a kind is not taken', () {
      expect(
        () => PlayQueueEvent.fromJson({
          'event_type': 'playback_event',
          'seq': 9,
          'details': {'clipped_samples': 5},
        }),
        throwsA(isA<TypeError>()),
      );
    });

    test('a playback event names the play it happened in', () {
      final event = PlayQueueEvent.fromJson(_clippingJson(play: '17'));
      expect((event as PlaybackEvent).playId, '17');
    });

    test('an older server\'s playback event names no play', () {
      final event = PlayQueueEvent.fromJson(_clippingJson());
      expect((event as PlaybackEvent).playId, isNull);
    });

    test('the state names its play, and a state naming none clears it', () {
      final playing = PlaybackState.fromJson({
        'state': 'PLAYING',
        'play_id': '17',
      });
      expect(playing.playId, '17');
      expect(PlaybackState.fromJson(playing.toJson()).playId, '17');

      final stopped = PlaybackState.fromJson({'state': 'STOPPED'});
      expect(stopped.playId, isNull);
      expect(playing.copyWith(stopped).playId, isNull);
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

  group('the queue state', () {
    test('keeps the latest details of each kind in the play', () {
      expect(
        _shownAfter([
          _state('17'),
          _clipping(3, play: '17'),
          const PlayQueueEvent.playbackEvent(
            kind: 'output_underrun',
            details: {'frames': 512},
            playId: '17',
            seq: 8,
          ),
          _clipping(1200, play: '17'),
        ]),
        {
          'clipping': {'clipped_samples': 1200},
          'output_underrun': {'frames': 512},
        },
      );
    });

    test('a new state of the same play keeps them', () {
      expect(
        _shownAfter([
          _state('17'),
          _clipping(3, play: '17'),
          _state('17', state: PlayerStateType.paused),
        ]),
        {
          'clipping': {'clipped_samples': 3},
        },
      );
    });

    test('a replay of the same track starts with none', () {
      expect(
        _shownAfter([_state('17'), _clipping(3, play: '17'), _state('18')]),
        isEmpty,
      );
    });

    test(
      'an event ahead of its play\'s state shows once the state names it',
      () {
        final ahead = [_state('17'), _clipping(5, play: '18')];
        expect(_shownAfter(ahead), isEmpty);
        expect(_shownAfter([...ahead, _state('18', track: _track2)]), {
          'clipping': {'clipped_samples': 5},
        });
      },
    );

    test('the last play\'s event, arriving late, does not show', () {
      expect(
        _shownAfter([
          _state('17'),
          _state('18', track: _track2),
          _clipping(5, play: '17'),
        ]),
        isEmpty,
      );
    });

    test('a state naming no play between two of one play\'s keeps them', () {
      final stopped = [
        _state('17'),
        _clipping(5, play: '17'),
        _state(null, state: PlayerStateType.stopped),
      ];
      expect(_shownAfter(stopped), isEmpty, reason: 'nothing plays to show');
      expect(_shownAfter([...stopped, _state('17')]), {
        'clipping': {'clipped_samples': 5},
      });
    });

    test('a stop and then another play drops them', () {
      expect(
        _shownAfter([
          _state('17'),
          _clipping(5, play: '17'),
          _state(null, state: PlayerStateType.stopped),
          _state('18', track: _track2),
        ]),
        isEmpty,
      );
    });

    test('a plugin\'s play goes when the queue takes the output back', () {
      final released = [
        const PlayQueueEvent.playbackControlChanged(
          control: PlaybackControl.exclusive(
            pluginId: 'qobuz',
            title: 'Qobuz Connect',
          ),
          seq: 1,
        ),
        _state('19'),
        _clipping(5, play: '19'),
        const PlayQueueEvent.playbackControlChanged(
          control: PlaybackControl.queue(),
          seq: 2,
        ),
      ];
      expect(_shownAfter(released), isEmpty);
      expect(_shownAfter([...released, _state('20', track: _track2)]), isEmpty);
    });

    test('an event naming no play is dropped while the state names one', () {
      expect(_shownAfter([_state('17'), _clipping(5)]), isEmpty);
    });

    test('from an older server, a track\'s events show until the next', () {
      final clipped = [_state(null), _clipping(5)];
      expect(_shownAfter(clipped), {
        'clipping': {'clipped_samples': 5},
      });
      expect(
        _shownAfter([...clipped, _state(null, state: PlayerStateType.paused)]),
        isNotEmpty,
      );
      expect(_shownAfter([...clipped, _state(null, track: _track2)]), isEmpty);
    });

    test('an event leaves the queue and its seq as they were', () {
      final before = PlayQueueState.empty.apply(_state('17'), 0);
      final after = before.apply(_clipping(5, play: '17'), 0);

      expect(after.seq, before.seq);
      expect(after.playbackState, same(before.playbackState));
      expect(after.trackList, same(before.trackList));
    });
  });

  group('playbackEventsProvider', () {
    test('takes events and states in the order they came, with no expiry', () {
      fakeAsync((async) {
        final h = _harness();
        h.events
          ..add(_state('17'))
          ..add(_clipping(5, play: '18'))
          ..add(_state('18', track: _track2));
        _settle(async);
        async.elapse(const Duration(minutes: 5));

        expect(_shown(h), {
          'clipping': {'clipped_samples': 5},
        });
      });
    });

    test('an event of another play rebuilds nothing', () {
      fakeAsync((async) {
        final h = _harness();
        h.events.add(_state('17'));
        _settle(async);
        var changes = 0;
        h.container.listen(playbackEventsProvider, (_, _) => changes++);

        h.events.add(_clipping(5, play: '18'));
        _settle(async);
        expect(changes, 0);

        h.events.add(_clipping(5, play: '17'));
        _settle(async);
        expect(changes, 1);
      });
    });

    for (final (play, kept) in [('17', true), ('18', false)]) {
      test('a reconnect to play $play ${kept ? 'keeps' : 'drops'} them', () {
        fakeAsync((async) {
          final h = _harness();
          h.events
            ..add(_state('17'))
            ..add(_clipping(5, play: '17'));
          _settle(async);

          h.events.addError(StateError('connection lost'));
          _settle(async);
          expect(_shown(h), isEmpty);

          h.events.add(_replay(play));
          _settle(async);
          expect(_shown(h), kept ? isNotEmpty : isEmpty);
        });
      });
    }
  });
}
