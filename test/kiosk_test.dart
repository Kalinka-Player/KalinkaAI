import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/ext_device_events.dart';
import 'package:kalinka/data_model/kalinka_ws_api.dart';
import 'package:kalinka/data_model/playqueue_events.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/bit_perfect_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/kalinka_ws_api_provider.dart';
import 'package:kalinka/providers/kiosk_provider.dart';
import 'package:kalinka/providers/playback_time_provider.dart';
import 'package:kalinka/providers/renderer_host_provider.dart';
import 'package:kalinka/providers/renderer_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/providers/url_resolver.dart';
import 'package:kalinka/renderer/renderer_identity.dart';
import 'package:kalinka/screens/kiosk_screen.dart';
import 'package:kalinka/widgets/kiosk/kiosk_backdrop.dart';
import 'package:kalinka/widgets/kiosk/kiosk_cover_flow.dart';
import 'package:kalinka/widgets/kiosk/kiosk_progress_bar.dart';
import 'package:kalinka/widgets/kiosk/kiosk_splash.dart';
import 'package:kalinka/widgets/kiosk/kiosk_status_strip.dart';
import 'package:kalinka/widgets/kiosk/kiosk_volume_control.dart';
import 'package:kalinka/widgets/now_playing_content.dart';
import 'package:kalinka/widgets/renderer_switcher.dart'
    show RendererPickerContent;
import 'package:kalinka/widgets/procedural_album_art.dart';
import 'package:kalinka/widgets/settings_controls/settings_toggle.dart';
import 'package:kalinka/widgets/this_device_section.dart';
import 'package:kalinka/widgets/transport_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Queue extends PlayQueueStateStore {
  _Queue(this._initial);
  final PlayQueueState _initial;

  @override
  PlayQueueState build() => _initial;

  void set(PlayQueueState next) => state = next;
}

class _Device extends ExtDeviceStateStore {
  _Device(this._volume);
  final DeviceVolume _volume;

  @override
  ExtDeviceState build() =>
      ExtDeviceState(powerOn: true, volume: _volume, seq: 0);
}

final _adjustable = DeviceVolume(
  currentVolume: 40,
  maxVolume: 100,
  volumeGain: 0,
  supported: true,
);

class _Time extends PlaybackTimeMsNotifier {
  @override
  int build() => 60000;
}

class _Connection extends ConnectionStateNotifier {
  _Connection(this._status);
  final ConnectionStatus _status;

  @override
  ConnectionStatus build() => _status;
}

class _Renderers extends RendererListNotifier {
  _Renderers(this._hostname);
  final String _hostname;

  @override
  RendererListState build() => RendererListState(
    loaded: true,
    renderers: [
      RendererInfo(
        rendererId: 'r1',
        friendlyName: 'Living Room',
        status: 'connected',
        active: true,
        hostname: _hostname,
      ),
    ],
  );

  // The picker re-reads the list on opening; the fake's list is all there is.
  @override
  Future<void> refresh() async {}
}

/// Stands in for the REST client, which the output picker reaches for.
class _Proxy implements KalinkaPlayerProxy {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Api extends KalinkaWsApi {
  _Api(super.ref);
  final List<QueueCommand> sent = [];
  final List<DeviceCommand> deviceSent = [];

  @override
  Future<void> sendQueueCommand(QueueCommand command) async {
    sent.add(command);
  }

  @override
  Future<void> sendDeviceCommand(DeviceCommand command) async {
    deviceSent.add(command);
  }
}

Track _track(int n) => Track(
  id: 'kalinka:qobuz:track:$n',
  title: 'Song $n',
  duration: 240,
  performer: Artist(id: 'p', name: 'Artist $n'),
);

PlayQueueState _queue(PlayerStateType state, {int index = 0, int seq = 1}) {
  final tracks = [_track(1), _track(2), _track(3)];
  return PlayQueueState(
    playbackState: PlaybackState(
      state: state,
      currentTrack: tracks[index],
      index: index,
      mimeType: 'audio/flac',
      audioInfo: AudioInfo(
        sampleRate: 96000,
        bitsPerSample: 24,
        channels: 2,
        durationMs: 0,
      ),
    ),
    trackList: tracks,
    playbackMode: PlaybackMode.empty,
    seq: seq,
    playbackControl: const PlaybackControl.queue(),
  );
}

final _emptyQueue = PlayQueueState(
  playbackState: PlaybackState(state: PlayerStateType.stopped),
  trackList: const [],
  playbackMode: PlaybackMode.empty,
  seq: 1,
  playbackControl: const PlaybackControl.queue(),
);

typedef _Harness = ({ProviderContainer container, _Api api, _Queue queue});

Future<_Harness> _pump(
  WidgetTester tester,
  PlayQueueState state, {
  Size size = const Size(1024, 600),
  bool launched = false,
  bool deviceLocked = false,
  String rendererHost = '',
  Widget home = const KioskScreen(),
  ConnectionStatus connection = ConnectionStatus.connected,
  bool bitPerfect = false,
  DeviceVolume? volume,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    ConnectionSettingsNotifier.sharedPrefName: 'Den server',
    ConnectionSettingsNotifier.sharedPrefHost: '10.0.0.2',
    ConnectionSettingsNotifier.sharedPrefPort: 8000,
    if (deviceLocked) KioskNotifier.sharedPrefLocked: true,
  });
  final prefs = await SharedPreferences.getInstance();
  final queue = _Queue(state);
  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      kioskLaunchProvider.overrideWithValue(launched),
      playQueueStateStoreProvider.overrideWith(() => queue),
      extDeviceStateStoreProvider.overrideWith(
        () => _Device(volume ?? DeviceVolume.empty),
      ),
      playbackTimeMsProvider.overrideWith(() => _Time()),
      connectionStateProvider.overrideWith(() => _Connection(connection)),
      rendererListProvider.overrideWith(() => _Renderers(rendererHost)),
      rendererIdentityProvider.overrideWith(
        (ref) => Completer<RendererIdentity>().future,
      ),
      urlResolverProvider.overrideWithValue(UrlResolver('')),
      kalinkaWsApiProvider.overrideWith((ref) => _Api(ref)),
      kalinkaProxyProvider.overrideWithValue(_Proxy()),
      bitPerfectProvider.overrideWithValue(bitPerfect),
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
      child: MaterialApp(home: home),
    ),
  );
  await tester.pump();
  return (
    container: container,
    api: container.read(kalinkaWsApiProvider) as _Api,
    queue: queue,
  );
}

void main() {
  group('launch flag', () {
    final page = Uri.parse('http://streamer.local:8080/');

    test('off unless asked for', () {
      expect(parseKioskLaunch('', null, page), isFalse);
    });

    test('any value but an off word turns it on', () {
      expect(parseKioskLaunch('true', null, page), isTrue);
      expect(parseKioskLaunch('locked', null, page), isTrue);
      expect(parseKioskLaunch('false', null, page), isFalse);
      expect(parseKioskLaunch('', 'true', page), isTrue);
    });

    test('a browser asks through the page URL', () {
      expect(parseKioskLaunch('', null, page.replace(query: 'kiosk')), isTrue);
      expect(
        parseKioskLaunch('', null, page.replace(query: 'kiosk=off')),
        isFalse,
      );
    });

    test('the build flag outranks the URL', () {
      expect(
        parseKioskLaunch('false', null, page.replace(query: 'kiosk')),
        isFalse,
      );
    });
  });

  group('the way out', () {
    Future<ProviderContainer> container({
      bool launched = false,
      bool deviceLocked = false,
    }) async {
      SharedPreferences.setMockInitialValues({
        if (deviceLocked) KioskNotifier.sharedPrefLocked: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          kioskLaunchProvider.overrideWithValue(launched),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('opened from the player, the exit button leaves', () async {
      final c = await container();
      final kiosk = c.read(kioskProvider.notifier);
      expect(c.read(kioskActiveProvider), isFalse);

      kiosk.enter();
      expect(c.read(kioskProvider).lock, KioskLock.none);
      kiosk.exit();
      expect(c.read(kioskActiveProvider), isFalse);
    });

    test('this device\'s setting holds it across launches', () async {
      final first = await container();
      await first.read(kioskProvider.notifier).lockToDevice();
      expect(first.read(kioskProvider).lock, KioskLock.device);

      final prefs = await SharedPreferences.getInstance();
      final next = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          kioskLaunchProvider.overrideWithValue(false),
        ],
      );
      addTearDown(next.dispose);
      expect(
        next.read(kioskProvider),
        const KioskState(active: true, lock: KioskLock.device),
      );
    });

    test('held by the setting, only the unlock leaves, and it turns the '
        'setting off', () async {
      final c = await container(deviceLocked: true);
      final kiosk = c.read(kioskProvider.notifier);

      kiosk.exit();
      expect(c.read(kioskActiveProvider), isTrue);

      await kiosk.unlockDevice();
      expect(c.read(kioskActiveProvider), isFalse);
      expect(kiosk.lockedToDevice, isFalse);
    });

    test('started by the launch flag, nothing leaves', () async {
      final c = await container(launched: true, deviceLocked: true);
      final kiosk = c.read(kioskProvider.notifier);
      expect(c.read(kioskProvider).lock, KioskLock.launch);

      kiosk.exit();
      await kiosk.unlockDevice();
      expect(c.read(kioskActiveProvider), isTrue);
    });
  });

  test('the date reads plainly, without the year', () {
    expect(kioskDate(DateTime(2026, 9, 29)), 'Tuesday, 29 September');
  });

  test('a renderer left at its default name goes by its machine', () {
    const named = RendererInfo(
      rendererId: 'a',
      friendlyName: 'Living Room',
      status: 'connected',
    );
    const unnamed = RendererInfo(
      rendererId: 'b',
      friendlyName: 'Kalinka Renderer on raspberrypi',
      status: 'connected',
    );
    expect(kioskOutputName(named, isSelf: false), 'Living Room');
    expect(kioskOutputName(unnamed, isSelf: false), 'raspberrypi');
  });

  testWidgets('shows the track and where it plays', (tester) async {
    await _pump(tester, _queue(PlayerStateType.playing));

    expect(find.text('Song 1'), findsOneWidget);
    expect(find.text('Artist 1'), findsOneWidget);
    expect(find.textContaining('Living Room'), findsOneWidget);
    expect(find.text('Qobuz · FLAC · 24-bit / 96 kHz'), findsOneWidget);
    expect(find.byType(KioskProgressBar), findsOneWidget);
  });

  testWidgets('the format line is only shown, not a way into details', (
    tester,
  ) async {
    await _pump(tester, _queue(PlayerStateType.paused));

    await tester.tap(find.textContaining('FLAC'));
    await tester.pumpAndSettle();
    expect(find.text('Stream info'), findsNothing);
  });

  testWidgets('carries the Kalinka mark at the top centre', (tester) async {
    await _pump(tester, _queue(PlayerStateType.paused), launched: true);
    await tester.pumpAndSettle();

    final strip = find.byType(KioskStatusStrip);
    final mark = tester.getRect(
      find.descendant(of: strip, matching: find.byType(SvgPicture)),
    );
    expect(mark.center.dx, closeTo(tester.getRect(strip).center.dx, 0.5));
    expect(find.text('Powered by'), findsNothing);
  });

  testWidgets('an output on this device is called that, not by its name', (
    tester,
  ) async {
    await _pump(
      tester,
      _queue(PlayerStateType.paused),
      rendererHost: Platform.localHostname,
    );

    expect(find.text('THIS DEVICE'), findsOneWidget);
    expect(find.textContaining('Living Room'), findsNothing);
  });

  for (final (label, launched, deviceLocked) in const [
    ('the setting', false, true),
    ('the launch flag', true, false),
  ]) {
    testWidgets('locked by $label, the output cannot be changed here', (
      tester,
    ) async {
      await _pump(
        tester,
        _queue(PlayerStateType.paused),
        launched: launched,
        deviceLocked: deviceLocked,
        rendererHost: Platform.localHostname,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('THIS DEVICE'));
      await tester.pumpAndSettle();
      expect(find.byType(RendererPickerContent), findsNothing);
    });
  }

  testWidgets('opened from the player, the output opens the picker', (
    tester,
  ) async {
    await _pump(
      tester,
      _queue(PlayerStateType.paused),
      rendererHost: Platform.localHostname,
    );

    await tester.tap(find.text('THIS DEVICE'));
    await tester.pumpAndSettle();
    expect(find.byType(RendererPickerContent), findsOneWidget);
    await tester.tapAt(const Offset(5, 5)); // dismiss the sheet
    await tester.pumpAndSettle();
  });

  testWidgets('the settings switch warns, then holds the device to the '
      'display', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        kioskLaunchProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ThisDeviceSection())),
      ),
    );

    await tester.tap(find.byType(SettingsToggle));
    await tester.pumpAndSettle();
    expect(find.textContaining('five times'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(container.read(kioskActiveProvider), isFalse);

    await tester.tap(find.byType(SettingsToggle));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch'));
    await tester.pumpAndSettle();
    expect(
      container.read(kioskProvider),
      const KioskState(active: true, lock: KioskLock.device),
    );
    expect(prefs.getBool(KioskNotifier.sharedPrefLocked), isTrue);
  });

  testWidgets('marks bit-perfect playback 1:1', (tester) async {
    await _pump(tester, _queue(PlayerStateType.playing), bitPerfect: true);

    expect(find.text('1:1'), findsOneWidget);
  });

  testWidgets('a plugin with only a large cover still colours the backdrop', (
    tester,
  ) async {
    final spotify = Track(
      id: 'kalinka:spotify:track:1',
      title: 'Spotify song',
      duration: 200,
      album: Album(
        id: 'kalinka:spotify:album:1',
        title: 'Spotify album',
        image: AlbumImage.fromJson({
          'small': '',
          'thumbnail': '',
          'large': 'https://i.scdn.co/image/abc',
        }),
      ),
    );
    await _pump(
      tester,
      PlayQueueState(
        playbackState: PlaybackState(
          state: PlayerStateType.playing,
          currentTrack: spotify,
          index: 0,
        ),
        trackList: const [],
        playbackMode: PlaybackMode.empty,
        seq: 1,
        playbackControl: const PlaybackControl.exclusive(
          pluginId: 'spotify',
          title: 'Spotify Connect',
        ),
      ),
    );

    expect(
      tester.widget<KioskBackdrop>(find.byType(KioskBackdrop)).imageUrl,
      'https://i.scdn.co/image/abc',
    );
  });

  testWidgets('with nothing queued, it is a clock ready to play', (
    tester,
  ) async {
    await _pump(tester, _emptyQueue);

    expect(find.text('Ready to play'), findsOneWidget);
    expect(
      find.text('Choose music in the Kalinka app to play here.'),
      findsOneWidget,
    );
    expect(find.byType(KioskProgressBar), findsNothing);
    expect(find.text('Play again'), findsNothing);
  });

  testWidgets('stopped at the end of the queue, it offers to play it again', (
    tester,
  ) async {
    final h = await _pump(tester, _queue(PlayerStateType.stopped, index: 2));

    expect(find.text('Ready to play'), findsOneWidget);
    expect(find.text('Song 3'), findsNothing);
    await tester.tap(find.text('Play again'));
    expect(h.api.sent, [const QueueCommand.play(index: 0)]);
  });

  testWidgets('stopped mid-queue, it resumes where it was', (tester) async {
    final h = await _pump(tester, _queue(PlayerStateType.stopped, index: 1));

    await tester.tap(find.text('Resume'));
    expect(h.api.sent, [const QueueCommand.play()]);
  });

  testWidgets('a lost connection says so, not "ready"', (tester) async {
    await _pump(tester, _emptyQueue, connection: ConnectionStatus.reconnecting);

    expect(find.text('Ready to play'), findsNothing);
    expect(find.text('Preparing…'), findsOneWidget);
    expect(
      find.text('Waiting for Den server. This screen picks up by itself.'),
      findsOneWidget,
    );
    expect(find.text('Waiting for Den server…'), findsOneWidget);
  });

  testWidgets('offline reads the same as reconnecting, never "ready"', (
    tester,
  ) async {
    await _pump(tester, _emptyQueue, connection: ConnectionStatus.offline);

    expect(find.text('Ready to play'), findsNothing);
    expect(find.text('Preparing…'), findsOneWidget);
    expect(
      find.text('Waiting for Den server. This screen picks up by itself.'),
      findsOneWidget,
    );
    expect(find.text('Waiting for Den server…'), findsOneWidget);
  });

  testWidgets('paused, the cover and track stay', (tester) async {
    await _pump(tester, _queue(PlayerStateType.paused));

    expect(find.text('Song 1'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets('the controls are one size and stand on the cover\'s edge', (
    tester,
  ) async {
    Future<Rect> disc(String title, {Size size = const Size(1024, 600)}) async {
      final t = Track(
        id: 'kalinka:qobuz:track:$title',
        title: title,
        duration: 240,
        performer: Artist(id: 'p', name: 'Artist'),
        album: Album(id: 'a', title: 'Album', year: 1990),
      );
      await _pump(
        tester,
        PlayQueueState(
          playbackState: PlaybackState(
            state: PlayerStateType.paused,
            currentTrack: t,
            index: 0,
            mimeType: 'audio/flac',
            audioInfo: AudioInfo(
              sampleRate: 96000,
              bitsPerSample: 24,
              channels: 2,
              durationMs: 0,
            ),
          ),
          trackList: [t],
          playbackMode: PlaybackMode.empty,
          seq: 1,
          playbackControl: const PlaybackControl.queue(),
        ),
        size: size,
      );
      await tester.pumpAndSettle();
      final cover = find.byType(KioskCoverFlow);
      final coverBottom =
          tester.getTopLeft(cover).dy +
          tester.widget<KioskCoverFlow>(cover).size;
      final rect = tester.getRect(
        find
            .ancestor(
              of: find.byIcon(Icons.play_arrow_rounded),
              matching: find.byType(TransportButton),
            )
            .first,
      );
      expect(rect.bottom, closeTo(coverBottom, 0.5));
      // All of the text shows: its last line ends above the buttons.
      final stream = tester.getRect(find.textContaining('FLAC'));
      expect(stream.bottom, lessThanOrEqualTo(rect.top));
      return rect;
    }

    const long = 'A rather long title that will certainly need two lines here';
    final short = await disc('Short');
    final twoLines = await disc(long);
    expect(short.size, const Size(100, 100));
    expect(twoLines.size, short.size);
    await disc(long, size: const Size(815, 528));
  });

  testWidgets('on a narrow screen the text lies over the cover', (
    tester,
  ) async {
    await _pump(
      tester,
      _queue(PlayerStateType.paused),
      size: const Size(700, 700),
    );
    await tester.pumpAndSettle();

    final cover = find.byType(KioskCoverFlow);
    final flow = tester.widget<KioskCoverFlow>(cover);
    expect(flow.reflected, isFalse);
    final coverBottom = tester.getTopLeft(cover).dy + flow.size;
    final title = tester.getRect(find.text('Song 1'));
    final stream = tester.getRect(find.textContaining('FLAC'));
    final bar = tester.getRect(find.byType(KioskProgressBar));
    expect(title.top, lessThan(coverBottom));
    expect(stream.bottom, lessThanOrEqualTo(bar.top));
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(1024, 600), Size(800, 480), Size(600, 1024)]) {
    testWidgets('lays out without overflow at ${size.width}x${size.height}', (
      tester,
    ) async {
      await _pump(tester, _queue(PlayerStateType.playing), size: size);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a new track swings in and replaces the old one', (tester) async {
    final h = await _pump(tester, _queue(PlayerStateType.playing));

    h.queue.set(_queue(PlayerStateType.playing, index: 1, seq: 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Song 2'), findsWidgets);

    await tester.pumpAndSettle();
    expect(find.text('Song 2'), findsOneWidget);
    expect(find.text('Song 1'), findsNothing);
  });

  testWidgets('controls rest while music plays; a touch only wakes them', (
    tester,
  ) async {
    final h = await _pump(tester, _queue(PlayerStateType.playing));

    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.skip_next_rounded), warnIfMissed: false);
    await tester.pump();
    expect(h.api.sent, isEmpty);

    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.skip_next_rounded));
    await tester.pump();
    expect(h.api.sent, [const QueueCommand.next()]);
  });

  testWidgets('a new track keeps the display at rest; pausing wakes it', (
    tester,
  ) async {
    final h = await _pump(tester, _queue(PlayerStateType.playing));
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();

    h.queue.set(_queue(PlayerStateType.buffering, index: 1, seq: 2));
    await tester.pump();
    h.queue.set(_queue(PlayerStateType.playing, index: 1, seq: 3));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.skip_next_rounded), warnIfMissed: false);
    await tester.pump();
    expect(h.api.sent, isEmpty);

    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    h.queue.set(_queue(PlayerStateType.paused, index: 1, seq: 4));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.skip_next_rounded));
    await tester.pump();
    expect(h.api.sent, [const QueueCommand.next()]);
  });

  testWidgets('paused, the controls stay up', (tester) async {
    final h = await _pump(tester, _queue(PlayerStateType.paused));

    await tester.pump(const Duration(seconds: 11));
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(h.api.sent, [const QueueCommand.pause(paused: false)]);
  });

  testWidgets('idle, it dims; the touch that wakes it acts on nothing', (
    tester,
  ) async {
    final h = await _pump(tester, _queue(PlayerStateType.stopped, index: 1));

    await tester.pump(const Duration(minutes: 2, seconds: 1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resume'), warnIfMissed: false);
    await tester.pump();
    expect(h.api.sent, isEmpty);

    await tester.pumpAndSettle();
    await tester.tap(find.text('Resume'));
    expect(h.api.sent, [const QueueCommand.play()]);
  });

  testWidgets('music starting on a dimmed display undims it', (tester) async {
    final h = await _pump(tester, _queue(PlayerStateType.stopped, index: 1));
    double dim() => tester
        .widget<AnimatedOpacity>(
          find.ancestor(
            of: find.byWidgetPredicate(
              (w) => w is ColoredBox && w.color == const Color(0xB3000000),
            ),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;

    await tester.pump(const Duration(minutes: 2, seconds: 1));
    await tester.pumpAndSettle();
    expect(dim(), 1);

    h.queue.set(_queue(PlayerStateType.playing, index: 1, seq: 2));
    await tester.pumpAndSettle();
    expect(dim(), 0);
  });

  testWidgets('volume stays out of sight until the screen is touched', (
    tester,
  ) async {
    await _pump(tester, _queue(PlayerStateType.paused), volume: _adjustable);
    await tester.pump();
    final control = find.byType(KioskVolumeControl);

    double opacity() => tester
        .widget<AnimatedOpacity>(
          find.descendant(of: control, matching: find.byType(AnimatedOpacity)),
        )
        .opacity;

    expect(opacity(), 0);
    await tester.tap(find.text('Song 1'));
    await tester.pump();
    expect(opacity(), 1);

    await tester.pump(const Duration(seconds: 5));
    expect(opacity(), 0);
  });

  testWidgets('dragging the volume bar up turns it up', (tester) async {
    final h = await _pump(
      tester,
      _queue(PlayerStateType.paused),
      volume: _adjustable,
    );
    await tester.pump();
    await tester.tap(find.text('Song 1'));
    await tester.pump();

    final bar = tester.getRect(
      find.descendant(
        of: find.byType(KioskVolumeControl),
        matching: find.byType(CustomPaint),
      ),
    );
    await tester.dragFrom(
      bar.bottomCenter - const Offset(0, 4),
      Offset(0, -bar.height * 0.8),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final last = h.api.deviceSent.last as SetVolumeCommand;
    expect(last.volume, greaterThan(70));
  });

  testWidgets('a fixed-volume output shows no volume control', (tester) async {
    await _pump(tester, _queue(PlayerStateType.paused));
    await tester.pump();
    await tester.tap(find.text('Song 1'));
    await tester.pump();

    expect(find.byIcon(Icons.volume_up_rounded), findsNothing);
    expect(find.byIcon(Icons.volume_down_rounded), findsNothing);
  });

  group('the cover turns the way playback went', () {
    PlayQueueState held(int n, int seq) => PlayQueueState(
      playbackState: PlaybackState(
        state: PlayerStateType.playing,
        currentTrack: _track(n),
        index: 0,
      ),
      trackList: const [],
      playbackMode: PlaybackMode.empty,
      seq: seq,
      playbackControl: const PlaybackControl.exclusive(
        pluginId: 'spotify',
        title: 'Spotify Connect',
      ),
    );

    /// Where the newcomer is, mid-swing, against the cover's resting centre.
    Future<double> swing(WidgetTester tester, double centre) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      final covers = find.descendant(
        of: find.byType(KioskCoverFlow),
        matching: find.byType(ProceduralAlbumArt),
      );
      final x = tester.getCenter(covers.last).dx - centre;
      await tester.pumpAndSettle();
      return x;
    }

    testWidgets('by the queue\'s position', (tester) async {
      final h = await _pump(tester, _queue(PlayerStateType.playing, index: 1));
      final centre = tester.getCenter(find.byType(KioskCoverFlow)).dx;

      h.queue.set(_queue(PlayerStateType.playing, index: 2, seq: 2));
      expect(await swing(tester, centre), greaterThan(0));
      h.queue.set(_queue(PlayerStateType.playing, index: 1, seq: 3));
      expect(await swing(tester, centre), lessThan(0));
    });

    testWidgets('by the viewer\'s skip, where the position cannot tell', (
      tester,
    ) async {
      final h = await _pump(tester, held(1, 1));
      final centre = tester.getCenter(find.byType(KioskCoverFlow)).dx;

      await tester.tap(find.byIcon(Icons.skip_next_rounded));
      h.queue.set(held(2, 2));
      expect(await swing(tester, centre), greaterThan(0));

      await tester.tap(find.byIcon(Icons.skip_previous_rounded));
      h.queue.set(held(1, 3));
      expect(await swing(tester, centre), lessThan(0));
    });
  });

  testWidgets('tapping along the bar seeks there', (tester) async {
    final h = await _pump(tester, _queue(PlayerStateType.playing));

    final bar = tester.getRect(find.byType(KioskProgressBar));
    await tester.tapAt(Offset(bar.left + bar.width / 4, bar.bottom - 22));
    await tester.pump();

    final seek = h.api.sent.single as SeekCommand;
    expect(seek.positionMs, closeTo(60000, 5));
  });

  testWidgets('launched as a display, the logo shows first, then goes', (
    tester,
  ) async {
    await _pump(tester, _queue(PlayerStateType.playing), launched: true);

    expect(find.byType(KioskSplash), findsOneWidget);
    // Two seconds rising, one holding: still fully up just before the fade.
    await tester.pump(const Duration(milliseconds: 2950));
    expect(find.byType(KioskSplash), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.byType(KioskSplash), findsNothing);
  });

  testWidgets('started on this device\'s setting, the logo shows too', (
    tester,
  ) async {
    await _pump(tester, _queue(PlayerStateType.playing), deviceLocked: true);

    expect(find.byType(KioskSplash), findsOneWidget);
  });

  testWidgets('entered from the app, there is no logo', (tester) async {
    await _pump(tester, _queue(PlayerStateType.playing));

    expect(find.byType(KioskSplash), findsNothing);
  });

  testWidgets('entered from the app, the way out is in plain sight', (
    tester,
  ) async {
    final h = await _pump(tester, _queue(PlayerStateType.playing));
    h.container.read(kioskProvider.notifier).enter();

    await tester.tap(find.byIcon(Icons.fullscreen_exit_rounded));
    expect(h.container.read(kioskActiveProvider), isFalse);
  });

  testWidgets('Escape leaves a display opened from the player', (tester) async {
    final h = await _pump(tester, _queue(PlayerStateType.playing));
    h.container.read(kioskProvider.notifier).enter();
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(h.container.read(kioskActiveProvider), isFalse);
  });

  Finder logo() => find.descendant(
    of: find.byType(KioskStatusStrip),
    matching: find.byType(SvgPicture),
  );

  testWidgets('held by this device\'s setting, five taps on the logo leave '
      'it', (tester) async {
    final h = await _pump(
      tester,
      _queue(PlayerStateType.playing),
      deviceLocked: true,
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.fullscreen_exit_rounded), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    for (var i = 0; i < 4; i++) {
      await tester.tap(logo());
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(h.container.read(kioskActiveProvider), isTrue);

    await tester.tap(logo());
    await tester.pump();
    expect(h.container.read(kioskActiveProvider), isFalse);
    expect(h.container.read(kioskProvider.notifier).lockedToDevice, isFalse);
  });

  bool isMark(Widget w, String asset) =>
      w is SvgPicture &&
      (w.bytesLoader as SvgAssetLoader).assetName.endsWith(asset);

  testWidgets('on a narrow screen the K mark leads the strip, and five taps '
      'on it leave', (tester) async {
    final h = await _pump(
      tester,
      _queue(PlayerStateType.playing),
      size: const Size(600, 1024),
      deviceLocked: true,
    );
    await tester.pumpAndSettle();

    final k = find.byWidgetPredicate((w) => isMark(w, 'kalinka_icon.svg'));
    expect(k, findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => isMark(w, 'kalinka_logo.svg')),
      findsNothing,
    );
    expect(
      tester.getRect(k).right,
      lessThan(tester.getRect(find.byIcon(Icons.speaker_outlined)).left),
    );

    for (var i = 0; i < 5; i++) {
      await tester.tap(k);
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(h.container.read(kioskActiveProvider), isFalse);
  });

  testWidgets('started by the launch flag, there is no way out', (
    tester,
  ) async {
    final h = await _pump(
      tester,
      _queue(PlayerStateType.playing),
      launched: true,
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.fullscreen_exit_rounded), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    for (var i = 0; i < 5; i++) {
      await tester.tap(logo());
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(h.container.read(kioskActiveProvider), isTrue);
  });

  testWidgets('the player\'s button opens the display', (tester) async {
    final h = await _pump(
      tester,
      _queue(PlayerStateType.playing),
      home: const Scaffold(body: NowPlayingContent()),
    );

    await tester.tap(find.byIcon(Icons.fullscreen_rounded));
    expect(h.container.read(kioskActiveProvider), isTrue);
  });

  testWidgets('from the phone\'s player sheet, the sheet closes first', (
    tester,
  ) async {
    final h = await _pump(
      tester,
      _queue(PlayerStateType.playing),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(
                  body: NowPlayingContent(showOverlayHeader: true),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.fullscreen_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(NowPlayingContent), findsNothing);
    expect(h.container.read(kioskActiveProvider), isTrue);
  });
}
