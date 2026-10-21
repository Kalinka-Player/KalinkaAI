import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/kalinka_ws_api.dart';
import 'package:kalinka/data_model/playqueue_events.dart';
import 'package:kalinka/data_model/renderer_config.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/kalinka_ws_api_provider.dart';
import 'package:kalinka/providers/renderer_host_provider.dart';
import 'package:kalinka/providers/renderer_provider.dart';
import 'package:kalinka/providers/renderer_settings_route_provider.dart';
import 'package:kalinka/providers/toast_provider.dart';
import 'package:kalinka/providers/wire_event_provider.dart';
import 'package:kalinka/renderer/renderer_identity.dart';
import 'package:kalinka/screens/renderer_settings_screen.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/renderer_switcher.dart';
import 'package:kalinka/widgets/slide_in_panel.dart';
import 'package:kalinka/widgets/volume_control_slider.dart';

/// A `/renderer/list` body shaped like the server's, so the wire format is
/// pinned (ids vs names, status strings, the active/selected pair, and the
/// platform block the picker's supporting line is drawn from).
const _listPayload = '''
{"renderers":[
  {"renderer_id":"r-kitchen","instance_id":"i1","friendly_name":"Kitchen",
   "software_version":"0.1.0","kind":"native","status":"connected",
   "platform":{"os":"linux","hostname":"kitchen-pi","audio_backend":"alsa"},
   "connected_at":1.0,"last_seen":2.0,"active":false,"selected":false},
  {"renderer_id":"r-living","instance_id":"i2","friendly_name":"Living Room",
   "software_version":"0.1.0","kind":"native","status":"connected",
   "platform":{"os":"linux","hostname":"living-pi","audio_backend":"pipewire"},
   "connected_at":1.0,"last_seen":2.0,"active":true,"selected":true},
  {"renderer_id":"r-study","instance_id":"i3","friendly_name":"Study",
   "software_version":"0.1.0","kind":"native","status":"offline",
   "platform":{"os":"linux","hostname":"study-pi","audio_backend":"alsa"},
   "connected_at":1.0,"last_seen":2.0,"active":false,"selected":false},
  {"renderer_id":"r-pi","instance_id":"i4",
   "friendly_name":"Kalinka Renderer on raspberrypi",
   "software_version":"0.1.0","kind":"native","status":"connected",
   "platform":{"os":"linux","hostname":"raspberrypi","audio_backend":"alsa"},
   "connected_at":1.0,"last_seen":2.0,"active":false,"selected":false}
],"volume_control_modules":[]}
''';

List<RendererInfo> _parse(String body) => [
  for (final r in (jsonDecode(body) as Map)['renderers'] as List)
    RendererInfo.fromJson(Map<String, dynamic>.from(r as Map)),
];

/// The picker row carrying [name]. Its Stack is the item's full extent — the
/// play target underneath and any upgrade action over it.
Finder _rowOf(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(Stack)).first;

/// That row's gear, which is its own target rather than part of the row tap.
Finder _gearOf(String name) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics && widget.properties.label == '$name settings',
);

class _VolumeApi extends KalinkaWsApi {
  _VolumeApi(super.ref);
  final sent = <DeviceCommand>[];

  @override
  Future<void> sendDeviceCommand(DeviceCommand command) async =>
      sent.add(command);
}

/// Serves the captured list and records selections; everything else throws.
class _FakeApi implements KalinkaPlayerProxy {
  _FakeApi({this.unsupported = false, this.failWith});

  final bool unsupported;

  /// Thrown by [setActiveRenderer] when set, to exercise the failure path.
  final Object? failWith;

  int listCalls = 0;
  final List<String?> selected = [];

  /// The display name each select carried, so a refusal can be phrased in it.
  final List<String?> selectedNames = [];
  List<RendererInfo> renderers = _parse(_listPayload);

  /// Set when a settings page opened and asked this renderer for its config.
  String? configuredRenderer;

  /// Renderers asked to upgrade, in order.
  final List<String> upgraded = [];

  /// Thrown by [upgradeRenderer] when set.
  Object? upgradeFailsWith;

  @override
  Future<String> upgradeRenderer(String rendererId) async {
    if (upgradeFailsWith != null) throw upgradeFailsWith!;
    upgraded.add(rendererId);
    return 'upgrading to 0.4.0';
  }

  @override
  Future<RendererConfigSnapshot> getRendererConfig(String rendererId) async {
    configuredRenderer = rendererId;
    return const RendererConfigSnapshot();
  }

  @override
  Future<List<RendererInfo>> listRenderers() async {
    listCalls++;
    if (unsupported) throw RenderersUnsupportedException();
    return renderers;
  }

  @override
  Future<void> setActiveRenderer(
    String? rendererId, {
    String? rendererName,
  }) async {
    selected.add(rendererId);
    selectedNames.add(rendererName);
    if (failWith != null) throw failWith!;
    renderers = [
      for (final r in renderers)
        r.copyWith(
          active: r.rendererId == rendererId,
          selected: r.rendererId == rendererId,
        ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeConnectionNotifier extends ConnectionStateNotifier {
  _FakeConnectionNotifier(this._status);
  final ConnectionStatus _status;

  @override
  ConnectionStatus build() => _status;

  void set(ConnectionStatus status) => state = status;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'Kalinka.host': 'localhost',
      'Kalinka.port': 8080,
      'Kalinka.name': 'Test',
    });
    prefs = await SharedPreferences.getInstance();
  });

  // Return type is intentionally inferred — Riverpod's Override type is sealed
  // and its concrete form is resolved by the package internally.
  overrides(
    KalinkaPlayerProxy api, {
    ConnectionStatus status = ConnectionStatus.connected,
    Stream<PlayQueueEvent>? events,
    DeviceVolume? volume,
    bool holdsVolume = false,
  }) => [
    sharedPrefsProvider.overrideWithValue(prefs),
    kalinkaProxyProvider.overrideWithValue(api),
    connectionStateProvider.overrideWith(() => _FakeConnectionNotifier(status)),
    volumeStateProvider.overrideWithValue(volume ?? DeviceVolume.empty),
    playbackHoldsVolumeProvider.overrideWithValue(holdsVolume),
    kalinkaWsApiProvider.overrideWith(_VolumeApi.new),
    // The notifier subscribes to the queue socket; tests feed it directly
    // instead of letting the provider chain dial a real websocket.
    playQueueEventBusProvider.overrideWith(
      (ref) => events ?? const Stream<PlayQueueEvent>.empty(),
    ),
  ];

  ProviderContainer makeContainer(
    KalinkaPlayerProxy api, {
    ConnectionStatus status = ConnectionStatus.connected,
    Stream<PlayQueueEvent>? events,
    DeviceVolume? volume,
    bool holdsVolume = false,
  }) {
    final container = ProviderContainer(
      overrides: overrides(
        api,
        status: status,
        events: events,
        volume: volume,
        holdsVolume: holdsVolume,
      ),
    );
    addTearDown(container.dispose);
    return container;
  }

  test('RendererInfo parses the /renderer/list wire format', () {
    final list = _parse(_listPayload);
    expect(list, hasLength(4));
    expect(list[0].rendererId, 'r-kitchen');
    expect(list[0].friendlyName, 'Kitchen');
    expect(list[0].isConnected, isTrue);
    // The platform block is nested, and absent on a renderer that reported
    // none — it must not blow up the parse.
    expect(list[0].hostname, 'kitchen-pi');
    expect(list[0].audioBackend, 'alsa');
    expect(list[0].kind, 'native');
    expect(list[1].active, isTrue);
    expect(list[1].selected, isTrue);
    expect(list[2].isConnected, isFalse, reason: 'status is offline');
  });

  test('a renderer with no platform block still parses', () {
    final info = RendererInfo.fromJson(const {
      'renderer_id': 'r-bare',
      'friendly_name': 'Bare',
      'status': 'connected',
    });
    expect(info.hostname, isEmpty);
    expect(info.audioBackend, isEmpty);
    expect(info.isConnected, isTrue);
  });

  test('connecting loads the renderer list', () async {
    final api = _FakeApi();
    final container = makeContainer(api);
    container.listen(rendererListProvider, (_, _) {}, fireImmediately: true);
    await Future.delayed(const Duration(milliseconds: 50));

    expect(api.listCalls, 1);
    final state = container.read(rendererListProvider);
    expect(state.renderers.map((r) => r.friendlyName), [
      'Kitchen',
      'Living Room',
      'Study',
      'Kalinka Renderer on raspberrypi',
    ]);
    expect(state.active?.rendererId, 'r-living');
    expect(state.switcherVisible, isTrue);
  });

  test('the switcher stays hidden until a list is actually read', () {
    // Startup / server-switch default: nothing fetched yet, so the crossed
    // "no renderer" state must not flash.
    expect(const RendererListState().switcherVisible, isFalse);
  });

  test('a server without /renderer/* hides the switcher', () async {
    final api = _FakeApi(unsupported: true);
    final container = makeContainer(api);
    container.listen(rendererListProvider, (_, _) {}, fireImmediately: true);
    await Future.delayed(const Duration(milliseconds: 50));

    final state = container.read(rendererListProvider);
    expect(state.supported, isFalse);
    expect(state.switcherVisible, isFalse);
  });

  test('select() PUTs the renderer id and moves the active marker', () async {
    final api = _FakeApi();
    final container = makeContainer(api);
    container.listen(rendererListProvider, (_, _) {}, fireImmediately: true);
    await Future.delayed(const Duration(milliseconds: 50));

    await container.read(rendererListProvider.notifier).select('r-kitchen');

    expect(api.selected, ['r-kitchen']);
    final state = container.read(rendererListProvider);
    expect(state.active?.rendererId, 'r-kitchen');
  });

  test('a rejected switch rethrows and re-reads the server list', () async {
    final api = _FakeApi(
      failWith: const RendererSwitchException('That output is busy'),
    );
    final container = makeContainer(api);
    container.listen(rendererListProvider, (_, _) {}, fireImmediately: true);
    await Future.delayed(const Duration(milliseconds: 50));
    final callsBefore = api.listCalls;

    await expectLater(
      container.read(rendererListProvider.notifier).select('r-kitchen'),
      throwsA(isA<RendererSwitchException>()),
    );

    expect(api.listCalls, callsBefore + 1, reason: 'reconciled after failure');
    final state = container.read(rendererListProvider);
    expect(state.active?.rendererId, 'r-living', reason: 'playback unmoved');
  });

  /// Mirrors how MusicPlayerScreen hosts the renderer settings panel: an
  /// overlay driven by the route provider, not a pushed route — that is what
  /// lets the tablet layout put it in the left panel.
  Widget switcherTree({double textScale = 1}) => MaterialApp(
    theme: AppTheme.dark(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Center(child: RendererSwitcherButton()),
          Consumer(
            builder: (context, ref, _) {
              final route = ref.watch(rendererSettingsRouteProvider);
              if (route == null) return const SizedBox.shrink();
              return RendererSettingsScreen(
                key: ValueKey(route.rendererId),
                rendererId: route.rendererId,
                rendererName: route.rendererName,
                onClose: () =>
                    ref.read(rendererSettingsRouteProvider.notifier).close(),
              );
            },
          ),
        ],
      ),
    ),
  );

  /// Pass [container] to read provider state the tree wrote — the toasts a
  /// failed action leaves behind have no host widget here.
  Widget wrap(
    KalinkaPlayerProxy api, {
    Stream<PlayQueueEvent>? events,
    ProviderContainer? container,
    double textScale = 1,
  }) => container != null
      ? UncontrolledProviderScope(
          container: container,
          child: switcherTree(textScale: textScale),
        )
      : ProviderScope(
          overrides: overrides(api, events: events),
          child: switcherTree(textScale: textScale),
        );

  testWidgets('no renderers → crossed icon, sheet says so', (tester) async {
    final api = _FakeApi()..renderers = const [];
    await tester.pumpWidget(wrap(api));
    await tester.pumpAndSettle();

    final inButton = find.descendant(
      of: find.byType(RendererSwitcherButton),
      matching: find.byIcon(Icons.close),
    );
    expect(find.byIcon(Icons.speaker_group_outlined), findsOneWidget);
    expect(inButton, findsOneWidget);
    expect(find.byTooltip('No renderer available'), findsOneWidget);

    await tester.tap(find.byType(RendererSwitcherButton));
    await tester.pumpAndSettle();

    expect(find.text('No renderer available'), findsOneWidget);
  });

  testWidgets('the dropdown names the empty state', (tester) async {
    final api = _FakeApi()..renderers = const [];
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(api),
        child: const MaterialApp(
          home: Scaffold(body: Center(child: RendererSwitcherDropdown())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No renderer available'), findsOneWidget);
    final inDropdown = find.descendant(
      of: find.byType(RendererSwitcherDropdown),
      matching: find.byIcon(Icons.close),
    );
    expect(inDropdown, findsOneWidget);
  });

  for (final empty in [false, true]) {
    testWidgets(
      '${empty ? 'empty' : 'long-name'} dropdown fits a narrow metadata column and opens the picker',
      (tester) async {
        const longName = 'Living room amplifier by the window';
        final api = _FakeApi()
          ..renderers = empty
              ? const []
              : const [
                  RendererInfo(
                    rendererId: 'r-living',
                    friendlyName: longName,
                    status: 'connected',
                    active: true,
                  ),
                ];
        await tester.pumpWidget(
          ProviderScope(
            overrides: overrides(api),
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: const Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 200,
                    child: RendererSwitcherDropdown(
                      framed: true,
                      maxNameWidth: 220,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final output = find.byType(RendererSwitcherDropdown);
        expect(tester.getSize(output).width, lessThanOrEqualTo(200));
        expect(tester.takeException(), isNull);
        await tester.tap(output);
        await tester.pumpAndSettle();
        expect(find.byTooltip('Close output picker'), findsOneWidget);
        expect(
          find.text(empty ? 'No renderer available' : 'PLAYING ON'),
          findsWidgets,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a server without /renderer/* renders nothing', (tester) async {
    final api = _FakeApi(unsupported: true);
    await tester.pumpWidget(wrap(api));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.speaker_group_outlined), findsNothing);
    expect(find.byTooltip('No renderer available'), findsNothing);
  });

  testWidgets('the playbar cast icon is crossed only with no live output', (
    tester,
  ) async {
    // With Living Room active and connected the icon carries no ornament.
    final api = _FakeApi();
    await tester.pumpWidget(wrap(api));
    await tester.pumpAndSettle();
    final inButton = find.descendant(
      of: find.byType(RendererSwitcherButton),
      matching: find.byIcon(Icons.close),
    );
    expect(find.byIcon(Icons.speaker_group_outlined), findsOneWidget);
    expect(inButton, findsNothing);

    // Nothing active: the grey cross appears.
    api.renderers = [
      for (final r in api.renderers) r.copyWith(active: false, selected: false),
    ];
    await tester.tap(find.byIcon(Icons.speaker_group_outlined));
    await tester.pumpAndSettle(); // sheet's refresh re-reads the list
    await tester.tapAt(const Offset(5, 5)); // dismiss the sheet
    await tester.pumpAndSettle();
    expect(inButton, findsOneWidget);
  });

  testWidgets('the picker separates the current output from other outputs', (
    tester,
  ) async {
    final api = _FakeApi();
    await tester.pumpWidget(wrap(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.speaker_group_outlined));
    await tester.pumpAndSettle();

    expect(find.text('PLAYING ON'), findsOneWidget);
    expect(find.text('OTHER OUTPUTS'), findsOneWidget);
    expect(find.text('Kitchen'), findsOneWidget);
    expect(find.text('Living Room'), findsOneWidget);
    expect(find.text('Study'), findsOneWidget);
    final currentBottom = tester.getBottomLeft(find.text('Living Room')).dy;
    final volumeTop = tester
        .getTopLeft(find.byType(NowPlayingVolumeControl))
        .dy;
    final othersTop = tester.getTopLeft(find.text('OTHER OUTPUTS')).dy;
    expect(currentBottom, lessThan(volumeTop));
    expect(volumeTop, lessThan(othersTop));
    expect(othersTop, lessThan(tester.getTopLeft(find.text('Kitchen')).dy));
    expect(
      find.ancestor(
        of: find.text('Living Room'),
        matching: find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.selected == true,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'volume adjusts in the picker and becomes inert when disconnected',
    (tester) async {
      final api = _FakeApi();
      final container = makeContainer(
        api,
        volume: DeviceVolume(
          supported: true,
          currentVolume: 18,
          maxVolume: 100,
          volumeGain: 0,
        ),
        holdsVolume: true,
      );
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(wrap(api, container: container));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.speaker_group_outlined));
      await tester.pumpAndSettle();
      expect(find.text('18%'), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).value, 0.18);
      await tester.dragFrom(
        tester.getCenter(find.byType(Slider)),
        const Offset(70, 0),
      );
      await tester.pump();
      final commands =
          (container.read(kalinkaWsApiProvider) as _VolumeApi).sent;
      expect(commands, isNotEmpty);
      expect(commands, everyElement(isA<SetVolumeCommand>()));
      expect(find.text('18%'), findsNothing);
      expect(
        api.selected,
        isEmpty,
        reason: 'changing volume does not select an output',
      );
      final sentCount = commands.length;
      (container.read(
        connectionStateProvider.notifier,
      ) as _FakeConnectionNotifier).set(ConnectionStatus.offline);
      await tester.pump();
      expect(find.bySemanticsLabel('Volume unavailable'), findsOneWidget);
      await tester.dragFrom(
        tester.getCenter(find.byType(Slider)),
        const Offset(70, 0),
      );
      await tester.pump();
      expect(commands, hasLength(sentCount));
      await tester.tap(find.byTooltip('Close output picker'));
      await tester.pumpAndSettle();
      expect(find.byType(RendererPickerContent), findsNothing);
      semantics.dispose();
    },
  );

  for (final unavailable in [
    'fixed',
    'no range',
    'idle',
    'no active output',
    'offline output',
  ]) {
    testWidgets('$unavailable keeps a grey, inactive volume slider visible', (
      tester,
    ) async {
      final api = _FakeApi();
      if (unavailable == 'no active output') {
        api.renderers = [
          for (final r in api.renderers) r.copyWith(active: false),
        ];
      } else if (unavailable == 'offline output') {
        api.renderers = [
          for (final r in api.renderers)
            r.active
                ? RendererInfo(
                    rendererId: r.rendererId,
                    friendlyName: r.friendlyName,
                    status: 'offline',
                    active: true,
                  )
                : r,
        ];
      }
      final container = makeContainer(
        api,
        volume: DeviceVolume(
          supported: unavailable != 'fixed',
          currentVolume: 18,
          maxVolume: unavailable == 'no range' ? 0 : 100,
          volumeGain: 0,
        ),
        holdsVolume: unavailable != 'idle',
      );
      await tester.pumpWidget(wrap(api, container: container));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.speaker_group_outlined));
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsOneWidget);
      final dim = tester.widget<Opacity>(
        find
            .descendant(
              of: find.byType(NowPlayingVolumeControl),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(dim.opacity, lessThan(1));
      await tester.dragFrom(
        tester.getCenter(find.byType(Slider)),
        const Offset(70, 0),
      );
      await tester.pump();
      expect(
        (container.read(kalinkaWsApiProvider) as _VolumeApi).sent,
        isEmpty,
      );
      expect(api.selected, isEmpty);
    });
  }

  for (final (size, scale) in [
    (const Size(375, 812), 1.0),
    (const Size(320, 568), 2.0),
    (const Size(812, 375), 1.0),
    (const Size(640, 900), 3.2),
  ]) {
    testWidgets(
      'picker scrolls while Close stays reachable at $size and ${scale}x text',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final api = _FakeApi();
        api.renderers = [
          RendererInfo(
            rendererId: 'r-living',
            friendlyName: 'Living room amplifier beside the window',
            status: 'connected',
            active: true,
          ),
          for (var i = 0; i < 12; i++)
            RendererInfo(
              rendererId: 'room-$i',
              friendlyName: 'Listening room $i',
              status: 'connected',
            ),
        ];
        await tester.pumpWidget(wrap(api, textScale: scale));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.speaker_group_outlined));
        await tester.pumpAndSettle();
        final close = find.byTooltip('Close output picker');
        final closeBounds = tester.getRect(close);
        expect(close.hitTestable(), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Listening room 11'),
          180,
          scrollable: find.descendant(
            of: find.byType(RendererPickerContent),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.getRect(close), closeBounds);
        expect(close.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(find.byType(RendererPickerContent), findsNothing);
      },
    );
  }

  testWidgets('each row says which host it is and how it plays', (
    tester,
  ) async {
    // Friendly names alone don't tell two boxes apart, which is the whole
    // reason the picker exists.
    await tester.pumpWidget(wrap(_FakeApi()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.speaker_group_outlined));
    await tester.pumpAndSettle();

    expect(find.text('kitchen-pi · ALSA'), findsOneWidget);
    expect(find.text('living-pi · PipeWire'), findsOneWidget);
    // Offline leads: it's why the row can't be tapped.
    expect(find.text('Offline · study-pi'), findsOneWidget);
    // Host dropped when the name already carries it — the server's default
    // friendly name is "Kalinka Renderer on <host>".
    expect(find.text('ALSA'), findsOneWidget);
  });

  testWidgets('one button upgrades a renderer that has a release waiting', (
    tester,
  ) async {
    final api = _FakeApi();
    api.renderers = [
      RendererInfo.fromJson(const {
        'renderer_id': 'r-old',
        'friendly_name': 'Attic',
        'status': 'connected',
        'kind': 'native',
        'compatible': false,
        'update_available': true,
        'platform': {'hostname': 'attic-pi'},
      }),
      ...api.renderers,
    ];
    await tester.pumpWidget(wrap(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.speaker_group_outlined));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.system_update_alt));
    await tester.pumpAndSettle();
    // It restarts the renderer, so it asks first.
    expect(find.text('Upgrade Attic?'), findsOneWidget);
    await tester.tap(find.text('Upgrade'));
    await tester.pumpAndSettle();

    expect(api.upgraded, ['r-old']);
  });

  testWidgets('tapping a renderer that cannot play offers the upgrade', (
    tester,
  ) async {
    // Doing nothing at all reads as a broken app rather than as a renderer
    // that needs new software.
    final api = _FakeApi();
    api.renderers = [
      RendererInfo.fromJson(const {
        'renderer_id': 'r-old',
        'friendly_name': 'Attic',
        'status': 'connected',
        'kind': 'native',
        'compatible': false,
        'update_available': true,
      }),
    ];
    await tester.pumpWidget(wrap(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.speaker_group_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Attic'));
    await tester.pumpAndSettle();

    expect(find.text('Upgrade Attic?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.upgraded, isEmpty, reason: 'cancel means cancel');
  });

  testWidgets('no upgrade button without a release to install', (tester) async {
    // The server only flags a renderer it could actually bring forward, so an
    // unflagged row must not offer a button that would refuse.
    final api = _FakeApi();
    await tester.pumpWidget(wrap(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.speaker_group_outlined));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.system_update_alt), findsNothing);
  });

  testWidgets('a renderer that needs upgrading offers only that', (
    tester,
  ) async {
    // Its settings are read over the socket that cannot carry them, so a gear
    // there is a target that does nothing.
    final api = _FakeApi();
    api.renderers = [
      RendererInfo.fromJson(const {
        'renderer_id': 'r-old',
        'friendly_name': 'Attic',
        'status': 'connected',
        'kind': 'native',
        'compatible': false,
        'update_available': true,
      }),
    ];
    await tester.pumpWidget(wrap(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.speaker_group_outlined));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.system_update_alt), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsNothing);
  });

  testWidgets('a renderer nothing can fix offers neither button', (
    tester,
  ) async {
    // Built from source, or a flatpak: the server has no upgrade to give it,
    // and its settings are behind the same socket that cannot carry them.
    final api = _FakeApi();
    api.renderers = [
      RendererInfo.fromJson(const {
        'renderer_id': 'r-src',
        'friendly_name': 'Workshop',
        'status': 'connected',
        'kind': 'native',
        'compatible': false,
        'update_available': false,
      }),
    ];
    await tester.pumpWidget(wrap(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.speaker_group_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Workshop'), findsOneWidget);
    expect(find.byIcon(Icons.system_update_alt), findsNothing);
    expect(find.byIcon(Icons.settings_outlined), findsNothing);
  });

  testWidgets('the current renderer keeps its settings alongside the upgrade', (
    tester,
  ) async {
    final api = _FakeApi();
    api.renderers = [
      RendererInfo.fromJson(const {
        'renderer_id': 'r-ok',
        'active': true,
        'friendly_name': 'Kitchen',
        'status': 'connected',
        'kind': 'native',
        'update_available': true,
      }),
    ];
    await tester.pumpWidget(wrap(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.speaker_group_outlined));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.system_update_alt), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });

  testWidgets('a refused upgrade says why', (tester) async {
    final api = _FakeApi();
    api.upgradeFailsWith = const RendererUpgradeException(
      'That output is playing',
    );
    api.renderers = [
      RendererInfo.fromJson(const {
        'renderer_id': 'r-old',
        'friendly_name': 'Attic',
        'status': 'connected',
        'kind': 'native',
        'update_available': true,
      }),
      ...api.renderers,
    ];
    final container = ProviderContainer(overrides: overrides(api));
    addTearDown(container.dispose);
    await tester.pumpWidget(wrap(api, container: container));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.speaker_group_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.system_update_alt));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upgrade'));
    await tester.pumpAndSettle();

    expect(
      container.read(toastProvider).map((t) => t.message),
      contains('That output is playing'),
    );
    // The toast retires itself on a timer the container outlives; left
    // pending, it fails the test after the tree is gone.
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('a renderer the server cannot talk to is shown but not usable', (
    tester,
  ) async {
    // It is listed precisely so it can be reached and upgraded; tapping it
    // would send playback somewhere it provably cannot arrive.
    final api = _FakeApi();
    api.renderers = [
      RendererInfo.fromJson(const {
        'renderer_id': 'r-old',
        'friendly_name': 'Attic',
        'status': 'connected',
        'kind': 'native',
        'compatible': false,
        'platform': {'hostname': 'attic-pi', 'audio_backend': 'alsa'},
      }),
      ...api.renderers,
    ];
    await tester.pumpWidget(wrap(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.speaker_group_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Attic'), findsOneWidget);
    expect(find.text('Needs upgrade · attic-pi · ALSA'), findsOneWidget);

    await tester.tap(find.text('Attic'));
    await tester.pumpAndSettle();
    expect(api.selected, isEmpty, reason: 'playback must not be sent there');
  });

  testWidgets('the app\'s own renderer is named "This browser"', (
    tester,
  ) async {
    final api = _FakeApi();
    api.renderers = [
      ...api.renderers,
      // Two browser renderers: ours and someone else's — only ours renames.
      RendererInfo.fromJson(const {
        'renderer_id': 'r-self',
        'friendly_name': 'Chrome on Linux',
        'kind': 'web',
        'status': 'connected',
        'platform': {'os': 'web'},
      }),
      RendererInfo.fromJson(const {
        'renderer_id': 'r-other',
        'friendly_name': 'Firefox on Windows',
        'kind': 'web',
        'status': 'connected',
        'platform': {'os': 'web'},
      }),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overrides(api),
          rendererIdentityProvider.overrideWith(
            (ref) async => const RendererIdentity(
              rendererId: 'r-self',
              instanceId: 'i-self',
              friendlyName: 'Chrome on Linux',
              softwareVersion: '0.0.0',
              os: 'web',
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: Center(child: RendererSwitcherButton())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.speaker_group_outlined));
    await tester.pumpAndSettle();

    expect(find.text('This browser'), findsOneWidget);
    expect(find.text('Chrome on Linux'), findsNothing);
    // The other browser keeps its registered name and the kind detail; the
    // self row's name already says it, so no detail repeats it.
    expect(find.text('Firefox on Windows'), findsOneWidget);
    expect(find.text('Browser'), findsOneWidget);
  });

  test('pushed events drive the list and the current marker', () async {
    final events = StreamController<PlayQueueEvent>();
    addTearDown(events.close);
    final container = makeContainer(
      _FakeApi(),
      status: ConnectionStatus.offline, // no REST fetch; events are the source
      events: events.stream,
    );
    final sub = container.listen(rendererListProvider, (_, _) {});
    addTearDown(sub.close);

    events.add(
      PlayQueueEvent.renderersChanged(
        renderers: const [
          RendererInfo(
            rendererId: 'r-a',
            friendlyName: 'A',
            status: 'connected',
          ),
          RendererInfo(
            rendererId: 'r-b',
            friendlyName: 'B',
            status: 'connected',
          ),
        ],
        seq: 1,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    var state = container.read(rendererListProvider);
    expect(state.loaded, isTrue);
    expect(state.renderers.map((r) => r.rendererId), ['r-a', 'r-b']);
    expect(state.active, isNull, reason: 'rows arrive unflagged');

    events.add(
      PlayQueueEvent.currentRendererChanged(rendererId: 'r-b', seq: 2),
    );
    await Future<void>.delayed(Duration.zero);
    state = container.read(rendererListProvider);
    expect(state.active?.rendererId, 'r-b');
  });

  test(
    'the replay seeds the list; a pre-events replay defers to REST',
    () async {
      final events = StreamController<PlayQueueEvent>();
      addTearDown(events.close);
      final container = makeContainer(
        _FakeApi(),
        status: ConnectionStatus.offline,
        events: events.stream,
      );
      final sub = container.listen(rendererListProvider, (_, _) {});
      addTearDown(sub.close);

      PlayQueueState replayState({List<RendererInfo>? renderers}) =>
          PlayQueueState(
            playbackState: PlaybackState.empty,
            trackList: const [],
            playbackMode: PlaybackMode.empty,
            seq: 1,
            renderers: renderers,
            currentRendererId: renderers == null ? null : 'r-a',
          );

      events.add(
        PlayQueueEvent.replayEvent(
          state: replayState(
            renderers: const [
              RendererInfo(
                rendererId: 'r-a',
                friendlyName: 'A',
                status: 'connected',
              ),
            ],
          ),
          serverTimeNs: 0,
          seq: 1,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      var state = container.read(rendererListProvider);
      expect(state.loaded, isTrue);
      expect(state.active?.rendererId, 'r-a');

      // A replay with no renderers field (old server) must not wipe anything.
      events.add(
        PlayQueueEvent.replayEvent(
          state: replayState(renderers: null),
          serverTimeNs: 0,
          seq: 2,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      state = container.read(rendererListProvider);
      expect(state.renderers, hasLength(1));
    },
  );

  testWidgets('a pushed renderers event updates the open sheet', (
    tester,
  ) async {
    // What replaced the refresh button: the sheet follows the queue socket.
    final events = StreamController<PlayQueueEvent>();
    addTearDown(events.close);
    final api = _FakeApi();
    await tester.pumpWidget(wrap(api, events: events.stream));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.speaker_group_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Attic'), findsNothing);

    events.add(
      PlayQueueEvent.renderersChanged(
        renderers: const [
          RendererInfo(
            rendererId: 'r-attic',
            friendlyName: 'Attic',
            status: 'connected',
          ),
        ],
        seq: 1,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Attic'), findsOneWidget);
    expect(find.text('PLAY ON'), findsOneWidget, reason: 'sheet stays open');
  });

  testWidgets('choosing a renderer PUTs its id and closes the sheet', (
    tester,
  ) async {
    final api = _FakeApi();
    await tester.pumpWidget(wrap(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.speaker_group_outlined));
    await tester.pumpAndSettle();
    // tapAt, not tap: the label ignores pointers so the whole row is one
    // target, which means the finder's widget isn't the one that's hit.
    await tester.tapAt(tester.getCenter(find.text('Kitchen')));
    await tester.pumpAndSettle();

    expect(api.selected, ['r-kitchen']);
    expect(api.selectedNames, ['Kitchen']);
    expect(
      find.byType(RendererPickerContent),
      findsNothing,
      reason: 'sheet dismissed',
    );
  });

  testWidgets('the whole row is the target, not just the label', (
    tester,
  ) async {
    // Hovering or tapping the blank stretch right of the name has to act on
    // the row — the highlight covers the full item, so the hit area must too.
    final api = _FakeApi();
    await tester.pumpWidget(wrap(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.speaker_group_outlined));
    await tester.pumpAndSettle();
    final row = tester.getRect(_rowOf('Kitchen'));
    // Blank space to the right of the text remains part of the target.
    await tester.tapAt(Offset(row.right - 60, row.center.dy));
    await tester.pumpAndSettle();

    expect(api.selected, ['r-kitchen']);
  });

  testWidgets('the gear opens that renderer\'s settings page', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(wrap(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.speaker_group_outlined));
    await tester.pumpAndSettle();
    // Settings are available only for the current output.
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    expect(_gearOf('Kitchen'), findsNothing);
    await tester.tap(_gearOf('Living Room'));
    await tester.pumpAndSettle();

    expect(api.selected, isEmpty, reason: 'configuring is not switching');
    expect(find.byType(RendererSettingsScreen), findsOneWidget);
    expect(find.text('Living Room'), findsOneWidget);
    expect(api.configuredRenderer, 'r-living');
  });

  testWidgets('the settings panel is an overlay, not a pushed route', (
    tester,
  ) async {
    // A route would always span the window; the tablet layout needs the panel
    // inside its left half, so it has to be host-placed and slide itself in.
    await tester.pumpWidget(wrap(_FakeApi()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.speaker_group_outlined));
    await tester.pumpAndSettle();
    await tester.tap(_gearOf('Living Room'));
    await tester.pumpAndSettle();

    // Same panel widget the server settings screen uses — one animation.
    expect(find.byType(SlideInPanel), findsOneWidget);
    // The switcher underneath is still mounted, so nothing was pushed over it.
    expect(find.byType(RendererSwitcherButton), findsOneWidget);
  });

  testWidgets('back slides the panel away and clears the route', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(_FakeApi()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.speaker_group_outlined));
    await tester.pumpAndSettle();
    await tester.tap(_gearOf('Living Room'));
    await tester.pumpAndSettle();
    expect(find.byType(RendererSettingsScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    // Mid-slide the panel is still there; only the host removes it, and only
    // once the animation has run.
    await tester.pump();
    await tester.pump(kSlideInPanelDuration ~/ 2);
    expect(find.byType(RendererSettingsScreen), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byType(RendererSettingsScreen), findsNothing);
    expect(find.byType(RendererSwitcherButton), findsOneWidget);
  });

  testWidgets('an offline renderer has no gear to tap', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(wrap(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.speaker_group_outlined));
    await tester.pumpAndSettle();
    expect(_gearOf('Study'), findsNothing);

    expect(find.byType(RendererSettingsScreen), findsNothing);
    expect(api.configuredRenderer, isNull);
  });

  testWidgets('an offline renderer cannot be chosen', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(wrap(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.speaker_group_outlined));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.text('Study')));
    await tester.pumpAndSettle();

    expect(api.selected, isEmpty);
    expect(
      find.byType(RendererPickerContent),
      findsOneWidget,
      reason: 'sheet stays open',
    );
  });
}
