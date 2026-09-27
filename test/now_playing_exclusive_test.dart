import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/ext_device_events.dart';
import 'package:kalinka/data_model/kalinka_ws_api.dart';
import 'package:kalinka/data_model/playqueue_events.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/bit_perfect_provider.dart';
import 'package:kalinka/providers/kalinka_ws_api_provider.dart';
import 'package:kalinka/providers/playback_time_provider.dart';
import 'package:kalinka/providers/renderer_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/providers/url_resolver.dart';
import 'package:kalinka/widgets/now_playing_content.dart';
import 'package:kalinka/widgets/playback_progress_slider.dart';

// A plugin playing exclusively, outside the queue (Qobuz Connect), as the
// now-playing screen shows it: its track, a note that the queue is not
// playing, and controls that reach it, without shuffle or repeat.

class _Queue extends PlayQueueStateStore {
  _Queue(this._state);
  final PlayQueueState _state;

  @override
  PlayQueueState build() => _state;
}

class _Device extends ExtDeviceStateStore {
  @override
  ExtDeviceState build() => ExtDeviceState(
    powerOn: true,
    volume: DeviceVolume(
      currentVolume: 40,
      maxVolume: 100,
      volumeGain: 0,
      supported: true,
    ),
    seq: 0,
  );
}

class _Time extends PlaybackTimeMsNotifier {
  @override
  int build() => 0;
}

class _Renderers extends RendererListNotifier {
  @override
  RendererListState build() => const RendererListState();
}

class _Api extends KalinkaWsApi {
  _Api(super.ref);
  final List<QueueCommand> sent = [];

  @override
  Future<void> sendQueueCommand(QueueCommand command) async {
    sent.add(command);
  }
}

const _qobuz = PlaybackControl.exclusive(
  pluginId: 'qobuz',
  title: 'Qobuz Connect',
);

final _connect = Track(
  id: 'kalinka:qobuz:track:111',
  title: 'Connect song',
  duration: 240,
  performer: Artist(id: 'p', name: 'Connect artist'),
);

PlayQueueState _held(
  PlayerStateType state, {
  PlaybackControl control = _qobuz,
}) => PlayQueueState(
  playbackState: PlaybackState(
    state: state,
    currentTrack: _connect,
    index: 0,
    audioInfo: AudioInfo(
      sampleRate: 96000,
      bitsPerSample: 24,
      channels: 2,
      durationMs: 241500,
    ),
  ),
  trackList: const [],
  playbackMode: PlaybackMode.empty,
  seq: 1,
  playbackControl: control,
);

Future<_Api> _pump(WidgetTester tester, PlayQueueState state) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      playQueueStateStoreProvider.overrideWith(() => _Queue(state)),
      extDeviceStateStoreProvider.overrideWith(() => _Device()),
      playbackTimeMsProvider.overrideWith(() => _Time()),
      rendererListProvider.overrideWith(() => _Renderers()),
      urlResolverProvider.overrideWithValue(UrlResolver('')),
      kalinkaWsApiProvider.overrideWith((ref) => _Api(ref)),
      bitPerfectProvider.overrideWithValue(false),
      sourceModulesProvider.overrideWith(
        (ref) => [
          ModuleInfo(
            name: 'qobuz',
            title: 'Qobuz',
            enabled: true,
            state: ModuleState.ready,
          ),
        ],
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: NowPlayingContent())),
    ),
  );
  await tester.pump();
  return container.read(kalinkaWsApiProvider) as _Api;
}

void main() {
  testWidgets('shows the plugin\'s track with an empty queue', (tester) async {
    await _pump(tester, _held(PlayerStateType.playing));

    expect(find.text('Connect song'), findsOneWidget);
    expect(find.text('Connect artist'), findsOneWidget);
    expect(find.text('No track'), findsNothing);
  });

  testWidgets('says which plugin it plays through', (tester) async {
    await _pump(tester, _held(PlayerStateType.playing));

    expect(find.text('Playing via Qobuz Connect'), findsOneWidget);
  });

  testWidgets('offers no shuffle or repeat, which the plugin cannot take', (
    tester,
  ) async {
    await _pump(tester, _held(PlayerStateType.playing));

    expect(find.byIcon(Icons.shuffle), findsNothing);
    expect(find.byIcon(Icons.repeat), findsNothing);
    expect(find.byIcon(Icons.repeat_one), findsNothing);
  });

  testWidgets('with the queue in control, shuffle and repeat are back', (
    tester,
  ) async {
    await _pump(
      tester,
      _held(PlayerStateType.playing, control: const PlaybackControl.queue()),
    );

    expect(find.byIcon(Icons.shuffle), findsOneWidget);
    expect(find.byIcon(Icons.repeat), findsOneWidget);
    expect(find.textContaining('Playing via'), findsNothing);
  });

  testWidgets('the progress bar runs to the stream\'s own length', (
    tester,
  ) async {
    await _pump(tester, _held(PlayerStateType.playing));

    final slider = tester.widget<PlaybackProgressSlider>(
      find.byType(PlaybackProgressSlider),
    );
    expect(slider.durationMs, 241500);
    expect(slider.enabled, isTrue);
  });

  testWidgets('previous, pause and next reach the plugin', (tester) async {
    final api = await _pump(tester, _held(PlayerStateType.playing));

    await tester.tap(find.byIcon(Icons.skip_previous_rounded));
    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.tap(find.byIcon(Icons.skip_next_rounded));
    await tester.pump();

    expect(api.sent, [
      const QueueCommand.prev(),
      const QueueCommand.pause(paused: true),
      const QueueCommand.next(),
    ]);
  });

  testWidgets('stopped, play would take the output back, so it sends nothing', (
    tester,
  ) async {
    final api = await _pump(tester, _held(PlayerStateType.stopped));

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();

    expect(api.sent, isEmpty);
  });
}
