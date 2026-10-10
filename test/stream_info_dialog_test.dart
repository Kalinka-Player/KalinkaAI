import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/playqueue_events.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/bit_perfect_provider.dart';
import 'package:kalinka/providers/playback_time_provider.dart';
import 'package:kalinka/widgets/stream_info_dialog.dart';

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

List<Override> _overrides(PlaybackState state) => [
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
];

void main() {
  group('streamInfoFields', () {
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

      expect(find.text('Stream info'), findsOneWidget);
      expect(find.text('URL'), findsOneWidget);
      expect(find.text('https://cdn.test/42.flac'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
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
