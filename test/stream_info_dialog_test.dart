import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/playqueue_events.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/bit_perfect_provider.dart';
import 'package:kalinka/providers/dsp_meters_provider.dart';
import 'package:kalinka/providers/playback_time_provider.dart';
import 'package:kalinka/widgets/stream_info_dialog.dart';
import 'package:kalinka/providers/renderer_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/audio_signal_path.dart';

// The dialog is a debug read-out of /queue/state, so what it must get right is
// which fields it takes from the state and how it renders a value the server
// did not send.

Track _track() => Track(
  id: 'kalinka:localfiles:track:42',
  title: 'Sonata',
  duration: 296,
  album: Album(
    id: 'kalinka:localfiles:album:7',
    title: 'Nocturnes',
    year: 1899,
  ),
);

PlaybackState _playing({String? streamUrl}) => PlaybackState(
  state: PlayerStateType.playing,
  currentTrack: _track(),
  index: 3,
  position: 83000,
  mimeType: 'FLAC',
  audioInfo: AudioInfo(
    sampleRate: 44100,
    bitsPerSample: 16,
    channels: 2,
    durationMs: 296000,
  ),
  streamUrl: streamUrl,
);

String? _valueOf(List<StreamInfoField> fields, String label) {
  for (final field in fields) {
    if (field.label == label) return field.value;
  }
  return null;
}

class _SettableQueueNotifier extends PlayQueueStateStore {
  _SettableQueueNotifier(this._initialState);
  final PlayQueueState _initialState;

  @override
  PlayQueueState build() => _initialState;
}

class _FakePlaybackTimeNotifier extends PlaybackTimeMsNotifier {
  @override
  int build() => 83000;
}

class _Renderers extends RendererListNotifier {
  @override
  RendererListState build() => const RendererListState();
}

class _Meters extends DspMetersNotifier {
  _Meters(this._meters);
  final DspMeters? _meters;

  @override
  DspMeters? build() => _meters;
}

/// A DSD track the renderer converts, as the server reports it.
PlaybackState _converted() => _playing()
  ..mimeType = 'audio/dsf'
  ..audioInfo = AudioInfo.fromJson({
    'sample_format': 'DSD',
    'sample_rate': 2822400,
    'bits_per_sample': 1,
    'channels': 2,
    'duration_ms': 1000,
    'output': {
      'sample_format': 'PCM24_LE',
      'sample_rate': 176400,
      'bits_per_sample': 24,
      'channels': 2,
      'access': 'exclusive',
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
    },
  });

List<Override> _overrides(PlaybackState state, {DspMeters? meters}) => [
  playQueueStateStoreProvider.overrideWith(
    () => _SettableQueueNotifier(
      PlayQueueState(
        playbackState: state,
        trackList: [_track()],
        playbackMode: PlaybackMode.empty,
        seq: 0,
      ),
    ),
  ),
  playbackTimeMsProvider.overrideWith(() => _FakePlaybackTimeNotifier()),
  // Stands in for the device store the real verdict reads, which would open a
  // wire connection.
  bitPerfectProvider.overrideWithValue(true),
  volumeStateProvider.overrideWithValue(DeviceVolume.empty),
  sourceDisplayInfoProvider.overrideWithValue(const {}),
  rendererListProvider.overrideWith(_Renderers.new),
  dspMetersProvider.overrideWith(() => _Meters(meters)),
];

void main() {
  group('streamInfoFields', () {
    test('DASH shows the audio codec in stream information', () {
      final state = _playing()
        ..mimeType = 'application/dash+xml'
        ..audioCodec = 'flac';
      final fields = streamInfoFields(
        state,
        positionMs: 0,
        queueLength: 1,
        bitPerfect: false,
      );
      expect(_valueOf(fields, 'Format'), 'FLAC');
      expect(state.mimeType, 'application/dash+xml');
    });

    test('external playback has stream info without a local queue', () {
      final state = PlaybackState(
        state: PlayerStateType.playing,
        currentTrack: Track(
          id: 'kalinka:roon:track:42',
          title: 'Roon song',
          duration: 240,
        ),
        index: 3,
        audioInfo: AudioInfo(
          sampleRate: 0,
          bitsPerSample: 0,
          channels: 0,
          output: const OutputInfo(sampleRate: 44100, channels: 2),
        ),
      );
      final fields = streamInfoFields(
        state,
        positionMs: 1000,
        queueLength: 0,
        bitPerfect: false,
        exclusive: true,
      );
      expect(_valueOf(fields, 'Title'), 'Roon song');
      expect(_valueOf(fields, 'Output'), '44.1 kHz · 2 ch · unknown');
      expect(_valueOf(fields, 'Index'), isNull);
      expect(_valueOf(fields, 'Format'), isNull);
      expect(_valueOf(fields, 'Decoded'), isNull);
    });

    test('reports what the state carries', () {
      final fields = streamInfoFields(
        _playing(streamUrl: 'http://10.0.0.1:8000/content/localfiles/42'),
        positionMs: 83000,
        queueLength: 24,
        bitPerfect: false,
      );

      expect(_valueOf(fields, 'Title'), 'Sonata');
      expect(_valueOf(fields, 'Album'), 'Nocturnes · 1899');
      expect(_valueOf(fields, 'ID'), 'kalinka:localfiles:track:42');
      expect(_valueOf(fields, 'State'), 'PLAYING');
      expect(_valueOf(fields, 'Index'), '3 / 24');
      expect(_valueOf(fields, 'Position'), '1:23');
      expect(_valueOf(fields, 'Duration'), '4:56');
      expect(_valueOf(fields, 'Format'), 'FLAC');
      expect(_valueOf(fields, 'Decoded'), '16-bit · 44.1 kHz · 2 ch');
      expect(
        _valueOf(fields, 'URL'),
        'http://10.0.0.1:8000/content/localfiles/42',
      );
    });

    test('a position past the last sample is the one passed in', () {
      final fields = streamInfoFields(
        _playing(),
        positionMs: 90000,
        queueLength: 24,
        bitPerfect: false,
      );

      expect(_valueOf(fields, 'Position'), '1:30');
    });

    test('leaves out what the server did not say', () {
      // A server predating stream_url, on a renderer reporting no device.
      final fields = streamInfoFields(
        _playing(),
        positionMs: 0,
        queueLength: 1,
        bitPerfect: false,
      );

      expect(_valueOf(fields, 'URL'), isNull);
      expect(_valueOf(fields, 'Output'), isNull);
    });

    test('an unestablished path is never reported as an altered one', () {
      final state = _playing()
        ..audioInfo!.output = const OutputInfo(
          sampleRate: 48000,
          bitsPerSample: 32,
          channels: 2,
          access: DeviceAccess.shared,
        );

      final fields = streamInfoFields(
        state,
        positionMs: 0,
        queueLength: 1,
        bitPerfect: false,
      );

      expect(_valueOf(fields, 'Path'), 'Not established');
    });

    test('a path the renderer says it processed is reported so', () {
      final fields = streamInfoFields(
        _converted(),
        positionMs: 0,
        queueLength: 1,
        bitPerfect: false,
      );

      expect(_valueOf(fields, 'Path'), 'Processed');
    });

    test('no output device to judge is no verdict at all', () {
      final fields = streamInfoFields(
        _playing(),
        positionMs: 0,
        queueLength: 1,
        bitPerfect: false,
      );

      expect(_valueOf(fields, 'Path'), isNull);
    });

    test('the output device is reported apart from the decoded stream', () {
      final state = _playing()
        ..audioInfo!.output = const OutputInfo(
          sampleRate: 48000,
          bitsPerSample: 32,
          channels: 2,
          access: DeviceAccess.exclusive,
        );

      final fields = streamInfoFields(
        state,
        positionMs: 0,
        queueLength: 1,
        bitPerfect: true,
      );

      expect(_valueOf(fields, 'Decoded'), '16-bit · 44.1 kHz · 2 ch');
      expect(_valueOf(fields, 'Output'), '32-bit · 48 kHz · 2 ch · exclusive');
      expect(_valueOf(fields, 'Path'), 'Bit-perfect');
    });

    test('an emptied queue is nothing playing, sticky track or not', () {
      // Clear All leaves currentTrack behind for the transport to show.
      expect(
        streamInfoFields(
          _playing(),
          positionMs: 0,
          queueLength: 0,
          bitPerfect: false,
        ),
        isEmpty,
      );
    });

    test('nothing loaded is no fields at all', () {
      expect(
        streamInfoFields(
          PlaybackState.empty,
          positionMs: 0,
          queueLength: 0,
          bitPerfect: false,
        ),
        isEmpty,
      );
    });
  });

  group('signalStages', () {
    List<SignalStage> dsdPath(String transport, int rate) {
      final state = _playing()
        ..mimeType = 'audio/dsf'
        ..audioInfo = AudioInfo.fromJson({
          'sample_format': 'DSD',
          'sample_rate': 2822400,
          'bits_per_sample': 1,
          'channels': 2,
          'duration_ms': 1000,
          'output': {
            'sample_format': transport,
            'sample_rate': rate,
            'bits_per_sample': 24,
            'channels': 2,
          },
        });
      return signalStages(state, DeviceVolume.empty);
    }

    test('DoP identifies the carrier without claiming PCM conversion', () {
      final stages = dsdPath('DoP_S24_LE', 176400);
      expect(stages.map((s) => s.label), [
        'Source',
        'Decoded stream',
        'DSD over PCM',
        'Output',
      ]);
      expect(stages[1].detail, contains('DSD64 · 2.8224 MHz'));
      expect(stages[2].detail, contains('176.4 kHz carrier'));
    });
    test('native, converted and unknown transport remain distinct', () {
      expect(dsdPath('DSD_U32_LE', 88200)[2].label, 'Native DSD');
      expect(dsdPath('PCM24_LE', 88200)[2].label, 'DSD to PCM');
      expect(dsdPath('', 88200).map((s) => s.label), [
        'Source',
        'Decoded stream',
        'Output',
      ]);
    });
    test('the renderer\'s steps stand in for the inferred conversion', () {
      final stages = signalStages(_converted(), DeviceVolume.empty);

      expect(stages.map((s) => s.label), [
        'Source',
        'Decoded stream',
        'DSD to PCM',
        'DSD gain',
        'Dither',
        'Output',
      ]);
      expect(stages[2].detail, 'DSD64 to 176.4 kHz, 30 kHz filter');
      expect(stages[3].detail, '+2.8 dB');
      expect(stages[4].detail, 'TPDF at 24 bits');
    });
    test('a step of a kind the app does not know still shows', () {
      final state = _playing()
        ..audioInfo!.output = OutputInfo.fromJson({
          'sample_format': 'PCM32_LE',
          'sample_rate': 96000,
          'signal_path': {
            'steps': [
              {'kind': 'upsample', 'name': 'Upsampling', 'summary': 'to 96k'},
              {'kind': 'crossfeed'},
            ],
          },
        });

      final stages = signalStages(state, DeviceVolume.empty);
      expect(stages.map((s) => s.label), [
        'Source',
        'Decoded stream',
        'Upsampling',
        'crossfeed',
        'Output',
      ]);
      expect(stages[2].detail, 'to 96k');
    });
    test('software gain appears only below unity', () {
      final state = _playing()
        ..audioInfo!.output = const OutputInfo(sampleRate: 44100);
      DeviceVolume volume(int level) => DeviceVolume(
        currentVolume: level,
        maxVolume: 100,
        volumeGain: 0,
        supported: true,
        backend: VolumeBackend.software,
      );
      expect(
        signalStages(state, volume(40)).map((s) => s.label),
        contains('Software volume'),
      );
      expect(
        signalStages(state, volume(100)).map((s) => s.label),
        isNot(contains('Software volume')),
      );
    });
  });

  group('StreamInfoDialog', () {
    testWidgets('lists the stream fields', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(
            _playing(streamUrl: 'https://cdn.test/42.flac'),
          ),
          child: const MaterialApp(home: Scaffold(body: StreamInfoDialog())),
        ),
      );
      await tester.pump();

      expect(find.text('Signal path'), findsOneWidget);
      expect(find.text('Decoded stream'), findsOneWidget);
      await tester.ensureVisible(find.text('Stream details'));
      await tester.tap(find.text('Stream details'));
      await tester.pumpAndSettle();
      expect(find.text('URL'), findsOneWidget);
      expect(find.text('https://cdn.test/42.flac'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('shows the steps and, while live, the meters', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(
            _converted(),
            meters: const DspMeters(clippedSamples: 12, load: 0.034),
          ),
          child: const MaterialApp(home: Scaffold(body: StreamInfoDialog())),
        ),
      );
      await tester.pump();

      expect(find.text('DSD gain'), findsOneWidget);
      expect(find.text('TPDF at 24 bits'), findsOneWidget);
      expect(find.text('DSP LATENCY'), findsOneWidget);
      expect(find.text('0.3 ms'), findsOneWidget);
      expect(find.text('TRUE PEAK'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      expect(find.text('3.4%'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('12')).style?.color,
        KalinkaColors.statusError,
      );
    });

    testWidgets('an older server shows no DSP figures', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(_playing()),
          child: const MaterialApp(home: Scaffold(body: StreamInfoDialog())),
        ),
      );
      await tester.pump();

      expect(find.text('Decoded stream'), findsOneWidget);
      expect(find.text('DSP LATENCY'), findsNothing);
      expect(find.text('CLIPPED'), findsNothing);
    });

    testWidgets('says so when nothing is playing', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(PlaybackState.empty),
          child: const MaterialApp(home: Scaffold(body: StreamInfoDialog())),
        ),
      );
      await tester.pump();

      expect(find.text('Nothing is playing.'), findsOneWidget);
      expect(find.text('Copy'), findsNothing);
    });
  });
}
