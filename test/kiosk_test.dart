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
import 'package:kalinka/widgets/kiosk/kiosk_header.dart';
import 'package:kalinka/widgets/kiosk/kiosk_output_panel.dart';
import 'package:kalinka/widgets/kiosk/kiosk_progress_bar.dart';
import 'package:kalinka/widgets/kiosk/kiosk_splash.dart';
import 'package:kalinka/widgets/kiosk/kiosk_volume_control.dart';
import 'package:kalinka/widgets/now_playing_content.dart';
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

  /// The volume moved, from somewhere other than the display.
  void setLevel(int level) => state = ExtDeviceState(
    powerOn: true,
    volume: DeviceVolume(
      currentVolume: level,
      maxVolume: _volume.maxVolume,
      volumeGain: _volume.volumeGain,
      supported: _volume.supported,
    ),
    seq: state.seq + 1,
  );
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
  _Renderers(this._hostname, {this.alone = false});
  final String _hostname;

  /// The one output there is.
  final bool alone;
  final List<String> selected = [];

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
      if (!alone) ...[
        const RendererInfo(
          rendererId: 'r2',
          friendlyName: 'Den',
          status: 'connected',
        ),
        const RendererInfo(
          rendererId: 'r3',
          friendlyName: 'Kitchen',
          status: 'disconnected',
        ),
      ],
    ],
  );

  // The panel re-reads the list on opening; the fake's list is all there is.
  // Like the real one, it says so at once.
  @override
  Future<void> refresh() async {
    state = state.copyWith(loading: true);
    await Future<void>.value();
    state = state.copyWith(loading: false);
  }

  @override
  Future<void> select(String rendererId, {String? rendererName}) async {
    selected.add(rendererId);
    state = state.copyWith(
      renderers: [
        for (final r in state.renderers)
          r.copyWith(active: r.rendererId == rendererId),
      ],
    );
  }
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

PlayQueueState _queue(
  PlayerStateType state, {
  int index = 0,
  int seq = 1,
  PlaybackMode? mode,
}) {
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
    playbackMode: mode ?? PlaybackMode.empty,
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
  bool aloneOutput = false,
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
      rendererListProvider.overrideWith(
        () => _Renderers(rendererHost, alone: aloneOutput),
      ),
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

Finder openPanel() => find.byType(KioskOutputPanel);

/// The panel's slider; the volume hanging from the pill holds one too.
Finder panelSlider() =>
    find.descendant(of: openPanel(), matching: find.byType(KioskVolumeSlider));

double volumeOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(
      find.descendant(
        of: find.byType(KioskVolumePopup),
        matching: find.byType(AnimatedOpacity),
      ),
    )
    .opacity;

Finder logo() => find.descendant(
  of: find.byType(KioskLogo),
  matching: find.byType(SvgPicture),
);

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

  test('under the header\'s clock, the date is short', () {
    expect(kioskShortDate(DateTime(2026, 10, 2)), 'Fri 2 Oct 2026');
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
    expect(find.text('NOW PLAYING'), findsOneWidget);
    expect(find.text('FLAC 24-bit 96 kHz'), findsOneWidget);
    expect(find.text('Qobuz'), findsOneWidget);
    expect(find.byType(KioskProgressBar), findsOneWidget);
    // Elapsed and the whole length, not what is left.
    expect(find.text('1:00'), findsOneWidget);
    expect(find.text('4:00'), findsOneWidget);
  });

  testWidgets('the format line is only shown, not a way into details', (
    tester,
  ) async {
    await _pump(tester, _queue(PlayerStateType.paused));

    await tester.tap(find.textContaining('FLAC'));
    await tester.pumpAndSettle();
    expect(find.text('Stream info'), findsNothing);
  });

  testWidgets('carries the Kalinka mark at the top left, where it plays and '
      'the time at the top right', (tester) async {
    await _pump(tester, _queue(PlayerStateType.paused), launched: true);
    await tester.pumpAndSettle();

    final mark = tester.getRect(logo());
    final output = tester.getRect(find.byType(KioskOutputPill));
    final cover = tester.getRect(find.byType(KioskCoverFlow));
    expect(mark.left, closeTo(cover.left, 0.5));
    expect(mark.bottom, lessThan(cover.top));
    expect(output.left, greaterThan(mark.right));
    expect(output.center.dx, greaterThan(512));
    expect(find.text('OPEN SOURCE MUSIC STREAMER'), findsNothing);
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

      // A fixed volume and no outputs to choose: nothing to open.
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
      await tester.tap(find.text('THIS DEVICE'));
      await tester.pumpAndSettle();
      expect(find.byType(KioskOutputPanel), findsNothing);
    });
  }

  testWidgets('locked, the output panel holds the volume and no other '
      'outputs', (tester) async {
    await _pump(
      tester,
      _queue(PlayerStateType.paused),
      launched: true,
      volume: _adjustable,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(KioskOutputPill));
    await tester.pumpAndSettle();
    expect(panelSlider(), findsOneWidget);
    expect(find.text('OTHER OUTPUTS'), findsNothing);
    expect(find.text('Den'), findsNothing);
  });

  testWidgets('the output pill opens its volume over the other outputs; '
      'choosing one plays there', (tester) async {
    final h = await _pump(
      tester,
      _queue(PlayerStateType.paused),
      volume: _adjustable,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Living Room'));
    await tester.pumpAndSettle();
    expect(openPanel(), findsOneWidget);
    final slider = tester.getRect(panelSlider());
    final others = tester.getRect(find.text('OTHER OUTPUTS'));
    expect(slider.bottom, lessThan(others.top));
    expect(tester.getRect(find.text('Den')).top, greaterThan(others.bottom));

    // An output that is offline is listed but cannot be chosen.
    final renderers =
        h.container.read(rendererListProvider.notifier) as _Renderers;
    await tester.tap(find.text('Kitchen'));
    await tester.pumpAndSettle();
    expect(renderers.selected, isEmpty);

    await tester.tap(find.text('Den'));
    await tester.pumpAndSettle();
    expect(renderers.selected, ['r2']);
    expect(openPanel(), findsNothing);
    expect(find.textContaining('Den'), findsOneWidget);
  });

  testWidgets('with no other output there is no outputs section; with a '
      'fixed volume too, the pill opens nothing', (tester) async {
    await _pump(
      tester,
      _queue(PlayerStateType.paused),
      volume: _adjustable,
      aloneOutput: true,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(KioskOutputPill));
    await tester.pumpAndSettle();
    expect(panelSlider(), findsOneWidget);
    expect(find.text('OTHER OUTPUTS'), findsNothing);
    expect(find.textContaining('Looking'), findsNothing);

    await _pump(tester, _queue(PlayerStateType.paused), aloneOutput: true);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
    await tester.tap(find.byType(KioskOutputPill));
    await tester.pumpAndSettle();
    expect(openPanel(), findsNothing);
  });

  testWidgets('the panel\'s slider sets the volume without the volume bar', (
    tester,
  ) async {
    final h = await _pump(
      tester,
      _queue(PlayerStateType.paused),
      volume: _adjustable,
    );
    await tester.tap(find.byType(KioskOutputPill));
    await tester.pumpAndSettle();

    final bar = tester.getRect(
      find.descendant(of: panelSlider(), matching: find.byType(CustomPaint)),
    );
    await tester.dragFrom(
      bar.centerLeft + const Offset(4, 0),
      Offset(bar.width * 0.8, 0),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final last = h.api.deviceSent.last as SetVolumeCommand;
    expect(last.volume, greaterThan(70));
    expect(volumeOpacity(tester), 0);
  });

  for (final (size, place) in const [
    (Size(1024, 600), 'under'),
    (Size(800, 480), 'under'),
    (Size(980, 950), 'under'),
    (Size(390, 844), 'over'),
    (Size(844, 390), 'full'),
    (Size(300, 300), 'full'),
  ]) {
    testWidgets('at ${size.width}x${size.height} the panel '
        '${place == 'full' ? 'fills the screen' : 'floats $place the pill'}', (
      tester,
    ) async {
      await _pump(
        tester,
        _queue(PlayerStateType.paused),
        size: size,
        volume: _adjustable,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(KioskOutputPill));
      await tester.pumpAndSettle();

      final panel = tester.getRect(openPanel());
      final pill = tester.getRect(find.byType(KioskOutputPill));
      final screen = Offset.zero & size;
      switch (place) {
        case 'full':
          expect(panel, screen);
        case 'under':
          expect(panel.top, greaterThan(pill.bottom));
          expect(panel.right, closeTo(pill.right, 0.5));
          expect(panel.width, lessThan(size.width * 0.6));
        case 'over':
          expect(panel.bottom, lessThan(pill.top));
          expect(panel.center.dx, closeTo(pill.center.dx, 0.5));
          expect(panel.height, lessThan(size.height / 2));
      }
      expect(screen.contains(panel.topLeft), isTrue);
      expect(screen.contains(panel.bottomRight - const Offset(1, 1)), isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the panel closes on a tap beside it, and when left alone', (
    tester,
  ) async {
    await _pump(tester, _queue(PlayerStateType.paused), volume: _adjustable);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(KioskOutputPill));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 580));
    await tester.pumpAndSettle();
    expect(openPanel(), findsNothing);

    await tester.tap(find.byType(KioskOutputPill));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    // Used, it stays a while longer.
    await tester.tap(find.text('OTHER OUTPUTS'));
    await tester.pump(const Duration(seconds: 10));
    expect(openPanel(), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(openPanel(), findsNothing);
  });

  testWidgets('Escape closes the panel before it leaves the display', (
    tester,
  ) async {
    final h = await _pump(tester, _queue(PlayerStateType.paused));
    h.container.read(kioskProvider.notifier).enter();
    await tester.pumpAndSettle();

    await tester.tap(find.byType(KioskOutputPill));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(openPanel(), findsNothing);
    expect(h.container.read(kioskActiveProvider), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(h.container.read(kioskActiveProvider), isFalse);
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

  testWidgets('the controls are one size and keep within the cover\'s '
      'height', (tester) async {
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
      final cover = tester.getRect(find.byType(KioskCoverFlow));
      final rect = tester.getRect(
        find
            .ancestor(
              of: find.byIcon(Icons.play_arrow_rounded),
              matching: find.byType(TransportButton),
            )
            .first,
      );
      expect(rect.bottom, lessThanOrEqualTo(cover.bottom + 0.5));
      // All of the text shows: its last line ends above the progress bar.
      final stream = tester.getRect(find.textContaining('FLAC'));
      final bar = tester.getRect(find.byType(KioskProgressBar));
      expect(stream.bottom, lessThanOrEqualTo(bar.top));
      expect(
        tester.getRect(find.text('NOW PLAYING')).top,
        greaterThan(cover.top - 0.5),
      );
      // However long the title, the lines start where the progress bar does.
      expect(
        tester.getRect(find.text('NOW PLAYING')).left,
        closeTo(bar.left, 0.5),
      );
      expect(tester.getRect(find.text(title)).left, closeTo(bar.left, 0.5));
      return rect;
    }

    const long = 'A rather long title that will certainly need two lines here';
    final short = await disc('Short');
    final twoLines = await disc(long);
    expect(twoLines.size, short.size);
    await disc(long, size: const Size(815, 528));
  });

  for (final size in const [Size(700, 700), Size(300, 300), Size(480, 320)]) {
    testWidgets('on a small or square screen at ${size.width}x${size.height} '
        'the cover fills it, the track and controls over its foot', (
      tester,
    ) async {
      await _pump(tester, _queue(PlayerStateType.paused), size: size);
      await tester.pumpAndSettle();

      expect(find.byType(KioskCoverFlow), findsNothing);
      expect(tester.getRect(find.byType(KioskCoverFill)), Offset.zero & size);
      final title = tester.getRect(find.text('Song 1'));
      final stream = tester.getRect(find.textContaining('FLAC'));
      final bar = tester.getRect(find.byType(KioskProgressBar));
      final play = tester.getRect(
        find
            .ancestor(
              of: find.byIcon(Icons.play_arrow_rounded),
              matching: find.byType(TransportButton),
            )
            .first,
      );
      final pill = tester.getRect(find.byType(KioskOutputPill));
      // Under the header: the lines, then the controls, then the progress.
      expect(title.top, greaterThan(pill.bottom));
      expect(stream.bottom, lessThanOrEqualTo(play.top + 0.01));
      expect(play.bottom, lessThanOrEqualTo(bar.top + 0.01));
      expect(bar.bottom, lessThanOrEqualTo(size.height));
      // Everything the wide screen shows is here too.
      expect(find.byType(KioskLogo), findsOneWidget);
      expect(find.byType(KioskOutputPill), findsOneWidget);
      expect(find.text('Qobuz'), findsOneWidget);
      expect(find.text('Artist 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('on a phone everything sits on the centre line', (tester) async {
    const size = Size(390, 844);
    await _pump(tester, _queue(PlayerStateType.paused), size: size);
    await tester.pumpAndSettle();

    for (final finder in [
      find.byType(KioskCoverFlow),
      find.text('NOW PLAYING'),
      find.text('Song 1'),
      find.text('Artist 1'),
      find.byType(KioskProgressBar),
      find.byType(KioskOutputPill),
      find
          .ancestor(
            of: find.byIcon(Icons.play_arrow_rounded),
            matching: find.byType(TransportButton),
          )
          .first,
    ]) {
      expect(tester.getCenter(finder).dx, closeTo(size.width / 2, 0.5));
    }
    // The mark and the time either side of the top, where it plays at the
    // foot.
    final mark = tester.getRect(logo());
    final cover = tester.getRect(find.byType(KioskCoverFlow));
    expect(mark.bottom, lessThan(cover.top));
    expect(
      tester.getRect(find.byType(KioskOutputPill)).top,
      greaterThan(tester.getRect(find.byType(KioskProgressBar)).bottom),
    );
    expect(tester.takeException(), isNull);
  });

  for (final size in const [
    Size(1024, 600),
    Size(800, 480),
    Size(1280, 800),
    Size(600, 1024),
    Size(390, 844),
    Size(844, 390),
    Size(300, 300),
    Size(480, 320),
    Size(720, 720),
  ]) {
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

  testWidgets('the controls stay up while music plays', (tester) async {
    final h = await _pump(tester, _queue(PlayerStateType.playing));

    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.skip_next_rounded));
    await tester.pump();
    expect(h.api.sent, [const QueueCommand.next()]);
  });

  const small = Size(300, 300);

  testWidgets('over a cover that fills a small screen, the controls rest '
      'while music plays; a touch only wakes them', (tester) async {
    final h = await _pump(tester, _queue(PlayerStateType.playing), size: small);

    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    // At rest they give their room back to the cover.
    expect(find.byIcon(Icons.skip_next_rounded), findsNothing);

    // The touch that brings them back opens nothing.
    await tester.tap(find.byType(KioskOutputPill));
    await tester.pumpAndSettle();
    expect(find.byType(KioskOutputPanel), findsNothing);

    await tester.tap(find.byIcon(Icons.skip_next_rounded));
    await tester.pump();
    expect(h.api.sent, [const QueueCommand.next()]);
  });

  testWidgets('on a large near-square screen the controls stay up', (
    tester,
  ) async {
    final h = await _pump(
      tester,
      _queue(PlayerStateType.playing),
      size: const Size(980, 950),
    );

    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.byType(KioskCoverFill), findsOneWidget);
    await tester.tap(find.byIcon(Icons.skip_next_rounded));
    await tester.pump();
    expect(h.api.sent, [const QueueCommand.next()]);
  });

  testWidgets('on a small screen a new track keeps the controls at rest; '
      'pausing wakes them', (tester) async {
    final h = await _pump(tester, _queue(PlayerStateType.playing), size: small);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();

    h.queue.set(_queue(PlayerStateType.buffering, index: 1, seq: 2));
    await tester.pump();
    h.queue.set(_queue(PlayerStateType.playing, index: 1, seq: 3));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.skip_next_rounded), findsNothing);

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

  _Device device(_Harness h) =>
      h.container.read(extDeviceStateStoreProvider.notifier) as _Device;

  testWidgets('the volume stays away when the screen is touched, comes up '
      'when it changes elsewhere, and goes 3 s after', (tester) async {
    final h = await _pump(
      tester,
      _queue(PlayerStateType.paused),
      volume: _adjustable,
    );
    await tester.pump();

    expect(volumeOpacity(tester), 0);
    await tester.tap(find.text('Song 1'));
    await tester.tap(find.byIcon(Icons.skip_next_rounded));
    await tester.pump();
    expect(volumeOpacity(tester), 0);

    device(h).setLevel(55);
    await tester.pump();
    expect(volumeOpacity(tester), 1);
    await tester.pump(const Duration(milliseconds: 2900));
    expect(volumeOpacity(tester), 1);
    await tester.pump(const Duration(milliseconds: 200));
    expect(volumeOpacity(tester), 0);
  });

  for (final (size, above) in const [
    (Size(1024, 600), false),
    (Size(980, 950), false),
    (Size(390, 844), true),
  ]) {
    testWidgets('at ${size.width}x${size.height} the volume hangs '
        '${above ? 'over' : 'under'} the output pill, never at the edge', (
      tester,
    ) async {
      final h = await _pump(
        tester,
        _queue(PlayerStateType.paused),
        size: size,
        volume: _adjustable,
      );
      await tester.pumpAndSettle();

      expect(find.byType(KioskVolumeControl), findsNothing);
      expect(volumeOpacity(tester), 0);
      device(h).setLevel(68);
      await tester.pumpAndSettle();
      expect(volumeOpacity(tester), 1);
      expect(find.text('68%'), findsOneWidget);
      final pill = tester.getRect(find.byType(KioskOutputPill));
      final hung = tester.getRect(find.byType(KioskVolumePopup));
      if (above) {
        expect(hung.bottom, lessThan(pill.top));
      } else {
        expect(hung.top, greaterThan(pill.bottom));
      }
      expect(hung.center.dx, closeTo(pill.center.dx, 0.5));
      final screen = Offset.zero & size;
      expect(screen.contains(hung.topLeft), isTrue);
      expect(screen.contains(hung.bottomRight - const Offset(1, 1)), isTrue);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(volumeOpacity(tester), 0);
    });
  }

  testWidgets('dragging the volume up turns it up', (tester) async {
    final h = await _pump(
      tester,
      _queue(PlayerStateType.paused),
      volume: _adjustable,
    );
    await tester.pump();
    device(h).setLevel(45);
    await tester.pumpAndSettle();

    final bar = tester.getRect(
      find.descendant(
        of: find.byType(KioskVolumePopup),
        matching: find.byType(CustomPaint),
      ),
    );
    await tester.dragFrom(
      bar.centerLeft + const Offset(4, 0),
      Offset(bar.width * 0.8, 0),
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

    expect(find.byType(KioskVolumeSlider), findsNothing);
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

  testWidgets('shuffle and repeat switch the queue\'s playback mode', (
    tester,
  ) async {
    final h = await _pump(
      tester,
      _queue(
        PlayerStateType.paused,
        mode: PlaybackMode(
          repeatAll: true,
          repeatSingle: false,
          shuffle: false,
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.shuffle_rounded));
    await tester.tap(find.byIcon(Icons.repeat_rounded));
    expect(h.api.sent, [
      const QueueCommand.setPlaybackMode(
        shuffle: true,
        repeatAll: true,
        repeatSingle: false,
      ),
      // All, then one.
      const QueueCommand.setPlaybackMode(
        shuffle: false,
        repeatAll: false,
        repeatSingle: true,
      ),
    ]);
  });

  testWidgets('a plugin\'s playback takes no shuffle or repeat', (
    tester,
  ) async {
    await _pump(
      tester,
      PlayQueueState(
        playbackState: PlaybackState(
          state: PlayerStateType.playing,
          currentTrack: _track(1),
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

    expect(find.byIcon(Icons.shuffle_rounded), findsNothing);
    expect(find.byIcon(Icons.repeat_rounded), findsNothing);
    expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
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

  for (final size in const [Size(1024, 600), Size(390, 844), Size(300, 300)]) {
    testWidgets('at ${size.width}x${size.height} the way out is never smaller '
        'than a fingertip', (tester) async {
      await _pump(tester, _queue(PlayerStateType.playing), size: size);
      await tester.pumpAndSettle();

      final button = tester.getSize(
        find
            .ancestor(
              of: find.byIcon(Icons.fullscreen_exit_rounded),
              matching: find.byType(TransportButton),
            )
            .first,
      );
      expect(button.width, greaterThanOrEqualTo(44));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the way out grows with the system text size', (tester) async {
    Future<double> diameter(double textScale) async {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(tester, _queue(PlayerStateType.playing));
      await tester.pumpAndSettle();
      return tester
          .getSize(
            find
                .ancestor(
                  of: find.byIcon(Icons.fullscreen_exit_rounded),
                  matching: find.byType(TransportButton),
                )
                .first,
          )
          .width;
    }

    final plain = await diameter(1);
    expect(await diameter(1.5), closeTo(plain * 1.5, 0.5));
  });

  testWidgets('Escape leaves a display opened from the player', (tester) async {
    final h = await _pump(tester, _queue(PlayerStateType.playing));
    h.container.read(kioskProvider.notifier).enter();
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(h.container.read(kioskActiveProvider), isFalse);
  });

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

  testWidgets('on a phone, five taps on the mark leave too', (tester) async {
    final h = await _pump(
      tester,
      _queue(PlayerStateType.playing),
      size: const Size(390, 844),
      deviceLocked: true,
    );
    await tester.pumpAndSettle();

    for (var i = 0; i < 5; i++) {
      await tester.tap(logo());
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
