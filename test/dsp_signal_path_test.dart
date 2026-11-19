import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/playqueue_events.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/dsp_meters_provider.dart';
import 'package:kalinka/providers/wire_event_provider.dart';
import 'package:kalinka/widgets/dsp_readout.dart';

// A renderer reports what its DSP does to a track in the state, and what it
// measures of it on the queue socket. An older server sends neither.

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

Map<String, dynamic> _meterJson({
  int seq = 9,
  int clipped = 0,
  num peak = -0.4,
  num load = 0.034,
}) => {
  'event_type': 'dsp_meters_changed',
  'seq': seq,
  'meters': {'clipped_samples': clipped, 'true_peak_dbfs': peak, 'load': load},
};

class _Queue extends PlayQueueStateStore {
  @override
  PlayQueueState build() => PlayQueueState.empty;

  void set(PlayQueueState next) => state = next;
}

PlayQueueState _playing({
  String trackId = 'kalinka:localfiles:track:1',
  SignalPath? path = _path,
  String renderer = 'pi',
}) => PlayQueueState(
  playbackState: PlaybackState(
    state: PlayerStateType.playing,
    currentTrack: Track(id: trackId, title: 'Sonata', duration: 300),
    audioInfo: AudioInfo(output: OutputInfo(signalPath: path)),
  ),
  trackList: const [],
  playbackMode: PlaybackMode.empty,
  seq: 1,
  currentRendererId: renderer,
);

typedef _Harness = ({
  ProviderContainer container,
  _Queue queue,
  StreamController<PlayQueueEvent> events,
});

_Harness _harness() {
  final events = StreamController<PlayQueueEvent>();
  final container = ProviderContainer(
    overrides: [
      playQueueStateStoreProvider.overrideWith(_Queue.new),
      playQueueEventBusProvider.overrideWith((ref) => events.stream),
    ],
  );
  addTearDown(() {
    container.dispose();
    events.close();
  });
  // The queue store holds the socket open in the app.
  container.listen(playQueueEventBusProvider, (_, _) {});
  container.listen(dspMetersProvider, (_, _) {});
  return (
    container: container,
    queue: container.read(playQueueStateStoreProvider.notifier) as _Queue,
    events: events,
  );
}

// Riverpod refreshes dependents on a zero-length timer.
void _settle(FakeAsync async) => async.elapse(Duration.zero);

void _report(_Harness h, FakeAsync async, {int clipped = 0}) {
  h.events.add(PlayQueueEvent.fromJson(_meterJson(clipped: clipped)));
  _settle(async);
}

/// The meters left after [next] follows a state they were live for.
DspMeters? _metersAfter(PlayQueueState next) {
  late DspMeters? after;
  fakeAsync((async) {
    final h = _harness();
    h.queue.set(_playing());
    _settle(async);
    _report(h, async);
    expect(h.container.read(dspMetersProvider), isNotNull);

    h.queue.set(next);
    _settle(async);
    after = h.container.read(dspMetersProvider);
  });
  return after;
}

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

    test('meters arrive on the queue socket', () {
      final event = PlayQueueEvent.fromJson(
        _meterJson(seq: 123, clipped: 7, peak: 0.2, load: 0.034),
      );

      final meters = (event as DspMetersChangedEvent).meters;
      expect(event.seq, 123);
      expect(meters.clippedSamples, 7);
      expect(meters.truePeakDbfs, 0.2);
      expect(meters.load, 0.034);
    });

    test('meters leave the queue state as it was', () {
      final before = _playing();
      expect(
        before.apply(PlayQueueEvent.fromJson(_meterJson()), 0),
        same(before),
      );
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
  });

  group('dspReadings', () {
    test('the latency stands without meters', () {
      expect(dspReadings(_path, null), [
        (label: 'DSP latency', value: '0.3 ms', alarm: false),
      ]);
    });

    test('meters read as counts, decibels and a share of a core', () {
      final readings = dspReadings(
        const SignalPath(steps: [SignalStep(kind: 'dither')]),
        const DspMeters(clippedSamples: 0, truePeakDbfs: -0.44, load: 0.034),
      );

      expect(readings, [
        (label: 'Clipped', value: '0', alarm: false),
        (label: 'True peak', value: '-0.4 dBFS', alarm: false),
        (label: 'DSP load', value: '3.4%', alarm: false),
      ]);
    });

    test('clipping is flagged, and a peak over full scale signed', () {
      final readings = dspReadings(
        _path,
        const DspMeters(clippedSamples: 12, truePeakDbfs: 0.83, load: 0.1),
      );

      expect(readings[1], (label: 'Clipped', value: '12', alarm: true));
      expect(readings[2].value, '+0.8 dBFS');
    });

    test('no sound yet is no peak', () {
      expect(dspReadings(null, const DspMeters())[1].value, '—');
    });

    test('an unprocessed track has nothing to read', () {
      expect(dspReadings(null, null), isEmpty);
    });
  });

  group('dspMetersProvider', () {
    test('meters live until a few seconds pass without a report', () {
      fakeAsync((async) {
        final h = _harness();
        h.queue.set(_playing());
        _settle(async);
        DspMeters? meters() => h.container.read(dspMetersProvider);

        _report(h, async, clipped: 3);
        expect(meters()?.clippedSamples, 3);

        async.elapse(const Duration(seconds: 2));
        _report(h, async, clipped: 4);
        async.elapse(const Duration(seconds: 2));
        expect(meters()?.clippedSamples, 4);

        async.elapse(const Duration(seconds: 1));
        expect(meters(), isNull);
      });
    });

    test('a new state for the same track keeps them', () {
      expect(
        _metersAfter(_playing()..playbackState.position = 9000),
        isNotNull,
      );
    });

    test('the next track does not inherit the last one\'s meters', () {
      expect(
        _metersAfter(_playing(trackId: 'kalinka:localfiles:track:2')),
        isNull,
      );
    });

    test('another renderer does not inherit them either', () {
      expect(_metersAfter(_playing(renderer: 'desk')), isNull);
    });

    test('meters go with the signal path', () {
      expect(_metersAfter(_playing(path: null)), isNull);
    });

    test('meters without a signal path are not taken', () {
      fakeAsync((async) {
        final h = _harness();
        h.queue.set(_playing(path: null));
        _settle(async);
        _report(h, async);

        expect(h.container.read(dspMetersProvider), isNull);
      });
    });
  });
}
