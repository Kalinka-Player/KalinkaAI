import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/data_model.dart'
    show
        RendererInfo,
        PlaybackState,
        PlayerStateType,
        DeviceVolume,
        AudioInfo,
        OutputInfo,
        SignalPath,
        SignalStep;
import 'package:kalinka/data_model/presentation_schema.dart';
import 'package:kalinka/data_model/renderer_config.dart';
import 'package:kalinka/data_model/renderer_config_adapter.dart';
import 'package:kalinka/data_model/playqueue_events.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/bit_perfect_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';

import 'support/focus.dart';

import 'package:kalinka/widgets/kalinka_back_button.dart';
import 'package:kalinka/widgets/settings_controls/settings_jump_target.dart';

import 'support/home_shell.dart' show SettableQueue, homeTrack;

import 'package:kalinka/providers/wire_event_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/demo_mode.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/renderer_provider.dart';
import 'package:kalinka/providers/renderer_settings_provider.dart';
import 'package:kalinka/screens/renderer_settings_screen.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/expert_field_list.dart';
import 'package:kalinka/widgets/settings_controls/settings_enum_dropdown.dart';
import 'package:kalinka/widgets/settings_top_bar.dart';
import 'package:kalinka/widgets/demo_read_only_dialog.dart';
import 'package:kalinka/widgets/kalinka_button.dart';
import 'package:kalinka/widgets/playback_chain_diagram.dart';
import 'package:kalinka/widgets/renderer_name_dialog.dart';
import 'package:kalinka/widgets/settings_controls/settings_readonly_card.dart';
import 'package:kalinka/widgets/settings_controls/settings_text_input.dart';
import 'package:kalinka/widgets/settings_controls/settings_slider.dart';
import 'package:kalinka/widgets/settings_controls/settings_card.dart';
import 'package:kalinka/widgets/settings_controls/inline_markdown.dart';

/// A `/renderer/{id}/config` body shaped like the live one from a Pi renderer:
/// enum fields whose options are resolved per request, text values in both
/// directions, a per-field apply cost, and the tier the field belongs on.
///
/// `output.volume_mode` deliberately declares no tier — a renderer built before
/// the tier existed says nothing, and its fields belong on the page proper.
const _configPayload = '''
{"config_version":"0af6bb750fbe4865","sections":[
  {"path":"output","title":"Output","description":"",
   "fields":[
     {"path":"output.driver","title":"Driver","description":"","type":"enum",
      "value":"alsa","default":"alsa",
      "options":[{"value":"alsa","label":"ALSA","description":""}],
      "apply":"restart_required","read_only":false,"importance":"simple"},
     {"path":"output.device","title":"Device","description":"","type":"enum",
      "value":"default","default":"default",
      "options":[
        {"value":"default","label":"default (not present)","description":""},
        {"value":"hw:CARD=Headphones,DEV=0","label":"bcm2835 Headphones, bcm2835 Headphones \\u00b7 Direct hardware device without any conversions","description":""},
        {"value":"plughw:CARD=Headphones,DEV=0","label":"bcm2835 Headphones, bcm2835 Headphones \\u00b7 Hardware device with all software conversions","description":""},
        {"value":"hw:CARD=sndrpihifiberry,DEV=0","label":"HiFiBerry Digi+ Pro","description":"Bit-perfect S/PDIF"}],
      "apply":"interrupts_playback","read_only":false,"importance":"simple"},
     {"path":"output.volume_mode","title":"Volume control",
      "description":"How volume is applied","type":"enum",
      "value":"auto","default":"auto",
      "options":[
        {"value":"auto","label":"auto","description":""},
        {"value":"software","label":"software","description":""}],
      "apply":"instant","read_only":false},
     {"path":"output.exclusive","title":"Exclusive mode","description":"",
      "type":"bool","value":"false","default":"false","options":[],
      "apply":"instant","read_only":false,"importance":"simple"},
     {"path":"output.latency_ms","title":"Latency","description":"",
      "type":"int","value":"100","default":"100","options":[],
      "apply":"restart_required","read_only":false,"importance":"expert",
      "range":{"min":20,"max":1000,"step":10},"unit":"ms","widget":"slider"},
     {"path":"output.buffer_bytes","title":"Buffer","description":"",
      "type":"int","value":"768000","default":"768000","options":[],
      "apply":"instant","read_only":false,"importance":"expert",
      "range":{"min":64000,"max":33554432,"step":0},"unit":"bytes",
      "widget":"number"},
     {"path":"output.reset","title":"Reset","description":"","type":"trigger",
      "value":"","default":"","options":[],
      "apply":"instant","read_only":false,"importance":"simple"}
   ]},
  {"path":"clock","title":"Clock","description":"",
   "fields":[
     {"path":"clock.resync_ms","title":"Resync window","description":"",
      "type":"int","value":"20","default":"20","options":[],
      "apply":"instant","read_only":false,"importance":"expert"}
   ]}
]}
''';

/// A renderer whose name was fixed with `--name`, so the field arrives
/// read-only.
const _readonlyNamePayload = '''
{"config_version":"1","sections":[
  {"path":"renderer","title":"Renderer","description":"",
   "fields":[
     {"path":"renderer.name","title":"Name","description":"","type":"string",
      "value":"Living Room","default":"Kalinka","options":[],
      "apply":"restart_required","read_only":true,"importance":"simple"}
   ]}
]}
''';

RendererConfigSnapshot _snapshot([String body = _configPayload]) =>
    RendererConfigSnapshot.fromJson(
      Map<String, dynamic>.from(jsonDecode(body) as Map),
    );

String _firPayload({
  String value = 'off',
  String cost = 'instant',
  bool direct = false,
}) =>
    '''
{"sections":[{"path":"output","title":"Output","fields":[
  {"path":"output.direct_mode","title":"Direct output","type":"bool",
   "value":"$direct","apply":"interrupts_playback"},
  {"path":"output.rew_fir_profile","title":"REW FIR filter","type":"enum",
   "description":"Applies the selected impulse at its sample rate.","value":"$value","apply":"$cost","options":[
     {"value":"off","label":"Off"},{"value":"test.wav","label":"Test filter"}]},
  {"path":"output.volume_mode","title":"Volume control","type":"enum",
   "value":"auto","apply":"instant","options":[
     {"value":"auto","label":"Automatic"},{"value":"software","label":"Software"}]}
]}]}
''';

/// Serves the captured config and records writes; everything else throws.
class _FakeApi implements KalinkaPlayerProxy {
  _FakeApi({this.loadError, this.outcomes, this.payload = _configPayload});

  /// Thrown by [getRendererConfig] when set.
  final Object? loadError;

  /// Served by [getRendererConfig].
  String payload;

  /// Returned by [updateRendererConfig] when set; defaults to "all applied".
  final List<Map<String, dynamic>>? outcomes;

  int loadCalls = 0;
  final List<Map<String, String>> writes = [];
  final List<String> tones = [];
  String? toneRendererId;

  /// While set, a read or a write answers only once it completes.
  Completer<void>? holdLoad;
  Completer<void>? holdWrite;

  @override
  Future<RendererConfigSnapshot> getRendererConfig(String rendererId) async {
    loadCalls++;
    await holdLoad?.future;
    if (loadError != null) throw loadError!;
    return _snapshot(payload);
  }

  @override
  Future<RendererConfigResult> updateRendererConfig(
    String rendererId,
    Map<String, String> changes,
  ) async {
    writes.add(changes);
    await holdWrite?.future;
    return RendererConfigResult.fromJson({
      'config_version': 'v2',
      'effect': 'interrupts_playback',
      'outcomes':
          outcomes ??
          [
            for (final e in changes.entries)
              {'path': e.key, 'applied': true, 'value': e.value, 'error': ''},
          ],
    });
  }

  @override
  Future<void> testTone(
    String channel, {
    String? device,
    String? rendererId,
  }) async {
    tones.add(channel);
    toneRendererId = rendererId;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeConnectionNotifier extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

/// A fixed renderer list; the real notifier arms socket listeners.
class _StubRendererList extends RendererListNotifier {
  _StubRendererList(this.renderers);
  final List<RendererInfo> renderers;

  @override
  RendererListState build() =>
      RendererListState(renderers: renderers, loaded: true);
}

/// Apply in the top bar, there while anything is staged.
final _apply = find.byKey(const ValueKey('pending-changes-apply'));

Future<void> openSection(WidgetTester tester, String title) async {
  await tester.ensureVisible(find.text(title));
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const rendererId = 'r-living';
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
  overrides(KalinkaPlayerProxy api) => [
    playQueueEventBusProvider.overrideWith((ref) => const Stream.empty()),
    sharedPrefsProvider.overrideWithValue(prefs),
    kalinkaProxyProvider.overrideWithValue(api),
    connectionStateProvider.overrideWith(_FakeConnectionNotifier.new),
  ];

  /// Holds the settings open, as their page does.
  ProviderContainer makeContainer(KalinkaPlayerProxy api) {
    final container = ProviderContainer(overrides: overrides(api));
    addTearDown(container.dispose);
    container.listen(rendererSettingsProvider(rendererId), (_, _) {});
    return container;
  }

  // ── Adapter ───────────────────────────────────────────────────────────────

  group('adaptRendererConfig', () {
    test('maps renderer field types onto the shared schema widgets', () {
      final view = adaptRendererConfig(_snapshot());

      expect(view.sections, hasLength(1));
      expect(view.sections.single.title, 'Output');
      final widgets = {for (final f in view.expertFields) f.path: f.widget};
      expect(widgets['output.driver'], WidgetKind.enumDropdown);
      expect(widgets['output.device'], WidgetKind.enumDropdown);
      expect(widgets['output.exclusive'], WidgetKind.toggle);
      expect(widgets['clock.resync_ms'], WidgetKind.numberInput);
    });

    test('drops trigger fields, which have no control to render', () {
      final view = adaptRendererConfig(_snapshot());
      final paths = view.sections.single.fields.map((f) => f.path);
      expect(paths, isNot(contains('output.reset')));
      expect(
        view.expertFields.map((f) => f.path),
        isNot(contains('output.reset')),
      );
      expect(view.values.containsKey('output.reset'), isFalse);
    });

    test('keeps expert fields off the simple page', () {
      final view = adaptRendererConfig(_snapshot());

      expect(view.sections.single.fields.map((f) => f.path), [
        'output.driver',
        'output.device',
        'output.volume_mode',
        'output.exclusive',
      ]);
      // A section with nothing but expert fields is left out entirely.
      expect(view.sections.map((s) => s.id), isNot(contains('clock')));
    });

    test('a field that declares no tier stays on the simple page', () {
      final view = adaptRendererConfig(_snapshot());
      final volumeMode = view.sections.single.fields.firstWhere(
        (f) => f.path == 'output.volume_mode',
      );
      expect(volumeMode.importance, Importance.simple);
    });

    test('expertFields lists every field, both tiers, sorted by path', () {
      final view = adaptRendererConfig(_snapshot());

      expect(view.expertFields.map((f) => f.path), [
        'clock.resync_ms',
        'output.buffer_bytes',
        'output.device',
        'output.driver',
        'output.exclusive',
        'output.latency_ms',
        'output.volume_mode',
      ]);
      final latency = view.expertFields.firstWhere(
        (f) => f.path == 'output.latency_ms',
      );
      expect(latency.importance, Importance.expert);
    });

    test('a bounded field the renderer wants dragged becomes a slider', () {
      final view = adaptRendererConfig(_snapshot());
      final latency = view.expertFields.firstWhere(
        (f) => f.path == 'output.latency_ms',
      );

      expect(latency.widget, WidgetKind.numberSlider);
      expect(latency.constraints!.ge, 20);
      expect(latency.constraints!.le, 1000);
      expect(latency.constraints!.sliderMin, 20);
      expect(latency.constraints!.sliderMax, 1000);
      expect(latency.constraints!.step, 10);
      expect(latency.constraints!.unit, 'ms');
    });

    test('a bounded field the renderer wants typed stays a number input', () {
      final view = adaptRendererConfig(_snapshot());
      final buffer = view.expertFields.firstWhere(
        (f) => f.path == 'output.buffer_bytes',
      );

      expect(buffer.widget, WidgetKind.numberInput);
      expect(buffer.constraints!.ge, 64000);
      expect(buffer.constraints!.le, 33554432);
      expect(buffer.constraints!.unit, 'bytes');
      expect(buffer.constraints!.step, isNull, reason: '0 is "any value"');
    });

    test('a field the renderer left unbounded gets no constraints', () {
      final view = adaptRendererConfig(_snapshot());
      final resync = view.expertFields.firstWhere(
        (f) => f.path == 'clock.resync_ms',
      );

      expect(resync.widget, WidgetKind.numberInput);
      expect(resync.constraints, isNull);
    });

    test('an expert field keeps its value, options and cost', () {
      final view = adaptRendererConfig(_snapshot());
      expect(view.values['output.latency_ms'], 100);
      expect(view.values['clock.resync_ms'], 20);
      expect(
        view.applyCosts['output.latency_ms'],
        RendererApplyCost.restartRequired,
      );
    });

    test('decodes wire text into the types the controls edit', () {
      final view = adaptRendererConfig(_snapshot());
      expect(view.values['output.device'], 'default');
      expect(view.values['output.exclusive'], false);
      expect(view.values['output.latency_ms'], 100);
    });

    test('carries per-request enum options through as live options', () {
      final view = adaptRendererConfig(_snapshot());
      final options = view.options['output.device']!;
      expect(options.map((o) => o.value), [
        'default',
        'hw:CARD=Headphones,DEV=0',
        'plughw:CARD=Headphones,DEV=0',
        'hw:CARD=sndrpihifiberry,DEV=0',
      ]);
      expect(options[0].description, isNull, reason: 'empty is not a subtitle');
    });

    test('splits the detail the renderer packs into an option label', () {
      final view = adaptRendererConfig(_snapshot());
      final device = view.options['output.device']!;

      expect(device[1].label, 'bcm2835 Headphones, bcm2835 Headphones');
      expect(
        device[1].description,
        'Direct hardware device without any conversions',
      );
      expect(device[2].label, 'bcm2835 Headphones, bcm2835 Headphones');
      expect(
        device[2].description,
        'Hardware device with all software conversions',
      );
    });

    test('a description the renderer did send is left alone', () {
      final view = adaptRendererConfig(_snapshot());
      final device = view.options['output.device']!;
      expect(device[3].label, 'HiFiBerry Digi+ Pro');
      expect(device[3].description, 'Bit-perfect S/PDIF');
    });

    test('a label with no separator stays whole', () {
      final view = adaptRendererConfig(_snapshot());
      expect(view.options['output.device']![0].label, 'default (not present)');
      expect(view.options['output.driver']!.single.label, 'ALSA');
      expect(view.options['output.volume_mode']![0].label, 'auto');
    });

    test('keeps each field apply cost for the pending-changes warning', () {
      final view = adaptRendererConfig(_snapshot());
      expect(
        view.applyCosts['output.device'],
        RendererApplyCost.interruptsPlayback,
      );
      expect(
        view.applyCosts['output.driver'],
        RendererApplyCost.restartRequired,
      );
      expect(view.applyCosts['output.volume_mode'], RendererApplyCost.instant);
    });

    test('encode is the inverse of decode', () {
      expect(encodeRendererValue(false), 'false');
      expect(encodeRendererValue(true), 'true');
      expect(encodeRendererValue(100), '100');
      expect(encodeRendererValue('hw:CARD=x'), 'hw:CARD=x');
      expect(
        decodeRendererValue(
          RendererFieldType.boolean,
          encodeRendererValue(true),
        ),
        true,
      );
      expect(
        decodeRendererValue(RendererFieldType.integer, encodeRendererValue(42)),
        42,
      );
    });
  });

  // ── Provider ──────────────────────────────────────────────────────────────

  group('rendererSettingsProvider', () {
    test('load() fills the page from the renderer', () async {
      final api = _FakeApi();
      final container = makeContainer(api);
      await container
          .read(rendererSettingsProvider(rendererId).notifier)
          .load();

      final state = container.read(rendererSettingsProvider(rendererId));
      expect(api.loadCalls, 1);
      expect(state.loaded, isTrue);
      expect(state.sections, hasLength(1));
      expect(state.expertFields, hasLength(7), reason: 'both tiers, flat');
      expect(state.values['output.volume_mode'], 'auto');
      expect(state.hasPendingChanges, isFalse);
    });

    test('staging back to the stored value unstages', () async {
      final api = _FakeApi();
      final container = makeContainer(api);
      final notifier = container.read(
        rendererSettingsProvider(rendererId).notifier,
      );
      await notifier.load();

      notifier.stage('output.volume_mode', 'software');
      expect(
        container.read(rendererSettingsProvider(rendererId)).pendingCount,
        1,
      );

      notifier.stage('output.volume_mode', 'auto');
      expect(
        container.read(rendererSettingsProvider(rendererId)).pendingCount,
        0,
      );
    });

    test('pendingCost reports the worst staged cost', () async {
      final api = _FakeApi();
      final container = makeContainer(api);
      final notifier = container.read(
        rendererSettingsProvider(rendererId).notifier,
      );
      await notifier.load();

      notifier.stage('output.volume_mode', 'software');
      expect(
        container.read(rendererSettingsProvider(rendererId)).pendingCost,
        RendererApplyCost.instant,
      );

      notifier.stage('output.driver', 'wasapi');
      expect(
        container.read(rendererSettingsProvider(rendererId)).pendingCost,
        RendererApplyCost.restartRequired,
      );
    });

    test('save() writes wire text and re-reads the page', () async {
      final api = _FakeApi();
      final container = makeContainer(api);
      final notifier = container.read(
        rendererSettingsProvider(rendererId).notifier,
      );
      await notifier.load();

      notifier.stage('output.exclusive', true);
      notifier.stage('output.latency_ms', 250);
      await notifier.save();

      expect(api.writes, [
        {'output.exclusive': 'true', 'output.latency_ms': '250'},
      ]);
      expect(api.loadCalls, 2, reason: 'a change can reshape the page');
      final state = container.read(rendererSettingsProvider(rendererId));
      expect(state.hasPendingChanges, isFalse);
      expect(state.error, isNull);
    });

    test('a load under way when a save starts does not end it', () async {
      final api = _FakeApi();
      final container = makeContainer(api);
      final notifier = container.read(
        rendererSettingsProvider(rendererId).notifier,
      );
      await notifier.load();
      notifier.stage('output.exclusive', true);

      final read = api.holdLoad = Completer<void>();
      final load = notifier.load(keepStaged: true);
      api.holdLoad = null;
      final write = api.holdWrite = Completer<void>();
      final save = notifier.save();
      read.complete();
      await load;

      var state = container.read(rendererSettingsProvider(rendererId));
      expect(state.saving, isTrue);
      expect(state.loading, isFalse);
      expect(state.staged, {'output.exclusive': true});

      write.complete();
      await save;
      state = container.read(rendererSettingsProvider(rendererId));
      expect(state.saving, isFalse);
      expect(state.hasPendingChanges, isFalse);
    });

    test('a refused setting is reported and survives the reload', () async {
      final api = _FakeApi(
        outcomes: [
          {
            'path': 'output.device',
            'applied': false,
            'value': 'default',
            'error': 'device is busy',
          },
        ],
      );
      final container = makeContainer(api);
      final notifier = container.read(
        rendererSettingsProvider(rendererId).notifier,
      );
      await notifier.load();

      notifier.stage('output.device', 'hw:CARD=Headphones,DEV=0');
      await notifier.save();

      final state = container.read(rendererSettingsProvider(rendererId));
      expect(state.error, contains('device is busy'));
      expect(state.hasPendingChanges, isFalse, reason: 'the reload is truth');
    });

    test('an unreachable renderer surfaces its own message', () async {
      final api = _FakeApi(
        loadError: const RendererConfigException('That output isn’t connected'),
      );
      final container = makeContainer(api);
      await container
          .read(rendererSettingsProvider(rendererId).notifier)
          .load();

      final state = container.read(rendererSettingsProvider(rendererId));
      expect(state.error, 'That output isn’t connected');
      expect(state.sections, isEmpty);
    });
  });

  // ── Screen ────────────────────────────────────────────────────────────────

  group('RendererSettingsScreen', () {
    // The panel carries no Scaffold of its own — it is hosted inside
    // MusicPlayerScreen's, which is where Material comes from.
    Widget wrap(
      KalinkaPlayerProxy api, {
      VoidCallback? onClose,
      bool demo = false,
    }) => ProviderScope(
      overrides: [
        ...overrides(api),
        if (demo) demoModeProvider.overrideWithValue(true),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: RendererSettingsScreen(
            rendererId: rendererId,
            rendererName: 'Living Room',
            onClose: onClose,
          ),
        ),
      ),
    );

    // As [wrap], with a known renderer list for the address badge to read.
    Widget wrapWithList(KalinkaPlayerProxy api, List<RendererInfo> rows) =>
        ProviderScope(
          overrides: [
            ...overrides(api),
            rendererListProvider.overrideWith(() => _StubRendererList(rows)),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: RendererSettingsScreen(
                rendererId: rendererId,
                rendererName: 'Living Room',
              ),
            ),
          ),
        );

    testWidgets('renders the renderer page with the shared settings chrome', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(_FakeApi()));
      await tester.pumpAndSettle();

      // The renderer's name is the page's title.
      expect(
        find.descendant(
          of: find.byType(SettingsTopBar),
          matching: find.text('Living Room'),
        ),
        findsOneWidget,
      );
      expect(find.text('Output settings'), findsNothing);
      expect(find.text('Room EQ'), findsNothing);
      expect(find.text('AUDIO OUTPUT'), findsOneWidget);
      expect(find.text('Device'), findsOneWidget);
      expect(find.text('Volume control'), findsOneWidget);
      // Trigger field dropped, per the adapter.
      expect(find.text('Reset'), findsNothing);
      expect(find.text('Speaker test'), findsOneWidget);
      expect(find.text('Test'), findsOneWidget);
    });

    testWidgets('editable rows divide the content evenly and stack on phones', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1120, 900);
      addTearDown(tester.view.reset);
      final config = jsonDecode(_configPayload);
      final fields = config['sections'].first['fields'] as List;
      fields.firstWhere((f) => f['path'] == 'output.latency_ms')['importance'] =
          'simple';
      fields.add({
        'path': 'output.status',
        'title': 'Output status',
        'description': 'Available formats',
        'type': 'string',
        'value': 'Connected',
        'read_only': true,
        'importance': 'simple',
      });
      await tester.pumpWidget(wrap(_FakeApi(payload: jsonEncode(config))));
      await tester.pumpAndSettle();
      final dropdown = find.descendant(
        of: find.byKey(const ValueKey('output.device')),
        matching: find.byType(SettingsEnumDropdown),
      );
      final slider = find.descendant(
        of: find.byKey(const ValueKey('output.latency_ms')),
        matching: find.byType(SettingsSlider),
      );
      final desktop = tester.getRect(dropdown);
      final audioCard = find.ancestor(
        of: dropdown,
        matching: find.byType(SettingsCard),
      );
      expect(tester.getSize(audioCard).width, closeTo(750, 0.01));
      expect(tester.getCenter(audioCard).dx, closeTo(560, 0.01));
      final deviceRow = find.byKey(const ValueKey('output.device'));
      final label = find
          .ancestor(
            of: find.descendant(of: deviceRow, matching: find.text('Device')),
            matching: find.byType(Wrap),
          )
          .first;
      final labelColumn = tester.getRect(
        find.ancestor(of: label, matching: find.byType(SizedBox)).first,
      );
      expect(desktop.width, closeTo(labelColumn.width, .01));
      expect(desktop.left - labelColumn.right, closeTo(12, .01));
      final description = find.descendant(
        of: find.byKey(const ValueKey('output.status')),
        matching: find.byType(InlineMarkdown),
      );
      final descriptionBox = tester.renderObject<RenderBox>(description);
      expect(
        descriptionBox.constraints.maxWidth,
        closeTo(desktop.right - labelColumn.left, .01),
      );
      expect(tester.getRect(slider).width, closeTo(desktop.width, 0.01));
      expect(tester.getRect(slider).right, closeTo(desktop.right, 0.01));
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(tester.getSize(dropdown).width, greaterThan(300));
      expect(
        tester.getTopLeft(dropdown).dy,
        greaterThan(tester.getBottomLeft(label).dy),
      );
      expect(
        tester.getSize(slider).width,
        closeTo(tester.getSize(dropdown).width, 0.01),
      );
    });

    testWidgets(
      'browser settings keep Core controls without native features at phone width',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(375, 812);
        addTearDown(tester.view.reset);
        final api = _FakeApi(
          payload: jsonEncode({
            'sections': [
              {
                'path': 'core.output',
                'title': 'Connected device',
                'fields': [
                  {
                    'path': 'core.output.device_module',
                    'title': 'Volume and power',
                    'type': 'enum',
                    'value': '',
                    'options': [
                      {'value': '', 'label': 'This renderer'},
                      {'value': 'receiver', 'label': 'Receiver'},
                    ],
                  },
                  {
                    'path': 'core.output.replaygain',
                    'title': 'ReplayGain',
                    'type': 'enum',
                    'value': 'Disabled',
                    'read_only': true,
                  },
                ],
              },
            ],
          }),
        );
        await tester.pumpWidget(
          wrapWithList(api, const [
            RendererInfo(
              rendererId: rendererId,
              friendlyName: 'Firefox on Linux',
              status: 'connected',
              kind: 'web',
            ),
          ]),
        );
        await tester.pumpAndSettle();
        expect(find.text('Browser playback'), findsOneWidget);
        expect(find.text('PLAYBACK CHAIN'), findsNothing);
        for (final name in [
          'Rename',
          'DSD',
          'Room EQ',
          'Sound card',
          'Output limits',
        ]) {
          expect(find.text(name), findsNothing);
        }
        expect(find.text('Disabled'), findsOneWidget);
        expect(find.byType(SettingsEnumDropdown), findsOneWidget);
        await tester.ensureVisible(find.text('This renderer'));
        await tester.tap(find.text('This renderer'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Receiver'));
        await tester.pumpAndSettle();
        await tester.tap(_apply);
        await tester.pumpAndSettle();
        expect(api.writes, [
          {'core.output.device_module': 'receiver'},
        ]);
      },
    );

    String renamePayload(String name) {
      final config = jsonDecode(_configPayload) as Map<String, dynamic>;
      final identity =
          (jsonDecode(_readonlyNamePayload)['sections'] as List).single;
      final field = (identity['fields'] as List).single;
      field['value'] = name;
      field['read_only'] = false;
      (config['sections'] as List).add(identity);
      return jsonEncode(config);
    }

    testWidgets('Rename edits in a dialog and writes only the confirmed name', (
      tester,
    ) async {
      final api = _FakeApi(payload: renamePayload('Living Room'));
      await tester.pumpWidget(wrap(api));
      await tester.pumpAndSettle();
      final scope = ProviderScope.containerOf(
        tester.element(find.byType(RendererSettingsScreen)),
      );
      final provider = rendererSettingsProvider(rendererId);
      scope.read(provider.notifier).stage('output.volume_mode', 'software');
      await tester.pumpAndSettle();
      await openSection(tester, 'Rename');
      expect(find.text('Rename renderer'), findsOneWidget);
      final input = find.descendant(
        of: find.byType(RendererNameDialog),
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(input).controller!.text, 'Living Room');
      await tester.enterText(input, 'Temporary');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(api.writes, isEmpty);
      expect(scope.read(provider).staged, {'output.volume_mode': 'software'});
      await openSection(tester, 'Rename');
      expect(tester.widget<TextField>(input).controller!.text, 'Living Room');
      await tester.enterText(input, '  Studio  ');
      api.payload = renamePayload('Studio');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(api.writes, [
        {'renderer.name': 'Studio'},
      ]);
      expect(find.byType(RendererNameDialog), findsNothing);
      expect(
        find.text('Studio'),
        findsNWidgets(2),
      ); // Header and identity card.
      expect(find.text('AUDIO OUTPUT'), findsOneWidget);
      expect(scope.read(provider).staged, {'output.volume_mode': 'software'});

      await openSection(tester, 'Rename');
      api.payload = renamePayload('Kalinka');
      await tester.enterText(input, '');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(api.writes.last, {'renderer.name': ''});
      expect(find.text('Kalinka'), findsNWidgets(2));
    });

    testWidgets('a refused rename keeps the dialog and draft', (tester) async {
      final api = _FakeApi(
        payload: renamePayload('Living Room'),
        outcomes: [
          {
            'path': 'renderer.name',
            'applied': false,
            'value': 'Living Room',
            'error': 'Name is locked',
          },
        ],
      );
      await tester.pumpWidget(wrap(api));
      await tester.pumpAndSettle();
      await openSection(tester, 'Rename');
      final dialog = find.byType(RendererNameDialog);
      final input = find.descendant(
        of: dialog,
        matching: find.byType(TextField),
      );
      await tester.enterText(input, 'Studio');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, 'Studio');
      expect(
        find.descendant(
          of: dialog,
          matching: find.textContaining('Name is locked'),
        ),
        findsOneWidget,
      );
      expect(api.writes, [
        {'renderer.name': 'Studio'},
      ]);
    });

    Future<void> pumpChain(
      WidgetTester tester,
      SettableQueue queue,
      _FakeApi api,
    ) async {
      const info = RendererInfo(
        rendererId: rendererId,
        friendlyName: 'Living Room',
        status: 'connected',
        active: true,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...overrides(api),
            rendererListProvider.overrideWith(() => _StubRendererList([info])),
            playQueueStateStoreProvider.overrideWith(() => queue),
            volumeStateProvider.overrideWithValue(DeviceVolume.empty),
            bitPerfectProvider.overrideWithValue(false),
            sourceDisplayInfoProvider.overrideWithValue(const {}),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: RendererSettingsScreen(
                rendererId: rendererId,
                rendererName: 'Living Room',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'chain shortcuts follow reported capabilities and preserve settings on navigation',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.reset);
        final config = jsonDecode(_configPayload);
        final sections = config['sections'] as List;
        sections.add({
          'path': 'dsd',
          'title': 'DSD',
          'fields': [
            {
              'path': 'output.dsd_pcm_rate',
              'title': 'Conversion rate',
              'type': 'enum',
              'options': [
                {'value': 'auto', 'label': 'Automatic'},
              ],
              'value': 'auto',
            },
            {
              'path': 'output.dsd_gain_db',
              'title': 'DSD level',
              'type': 'enum',
              'value': 'safe',
              'importance': 'expert',
              'options': [
                {'value': 'safe', 'label': 'Safe'},
              ],
            },
          ],
        });
        sections.add({
          'path': 'dsp',
          'title': 'DSP',
          'fields': [
            {
              'path': 'dsp.profile',
              'title': 'EQ preset',
              'type': 'enum',
              'value': 'none',
            },
            {
              'path': 'dsp.preamp',
              'title': 'Preamp',
              'type': 'enum',
              'value': 'auto',
              'options': [
                {'value': 'auto', 'label': 'Automatic'},
              ],
            },
          ],
        });
        final api = _FakeApi(payload: jsonEncode(config));
        final track = homeTrack('kalinka:localfiles:track:1');
        final queue = SettableQueue(
          PlayQueueState(
            currentRendererId: rendererId,
            playbackState: PlaybackState(
              state: PlayerStateType.playing,
              currentTrack: track,
              mimeType: 'audio/dsf',
              audioInfo: AudioInfo(
                sampleFormat: 'DSD',
                sampleRate: 2822400,
                channels: 2,
                bitsPerSample: 1,
                output: OutputInfo(
                  sampleFormat: 'PCM24_LE',
                  sampleRate: 176400,
                  bitsPerSample: 24,
                  channels: 2,
                  signalPath: const SignalPath(
                    steps: [
                      SignalStep(kind: 'dsd_to_pcm', name: 'Convert DSD'),
                      SignalStep(kind: 'dsd_gain', name: 'Conversion gain'),
                      SignalStep(kind: 'preamp', name: 'Headroom'),
                      SignalStep(kind: 'fir', name: 'Room filter'),
                      SignalStep(kind: 'dither', name: 'Dither'),
                      SignalStep(kind: 'future_kind', name: 'Output'),
                    ],
                  ),
                ),
              ),
            ),
            trackList: [track],
            playbackMode: PlayQueueState.empty.playbackMode,
            seq: 1,
          ),
        );
        await pumpChain(tester, queue, api);
        final diagram = find.byType(PlaybackChainDiagram);
        final links = tester.widget<PlaybackChainDiagram>(diagram).shortcutFor;
        for (final kind in [
          'source',
          'decoded',
          'fir',
          'dither',
          'future_kind',
          'sample_rate_change',
        ]) {
          expect(links(kind), isNull, reason: kind);
        }
        Finder button(String name) => find.descendant(
          of: diagram,
          matching: find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.properties.button == true &&
                (w.properties.label ?? '').split(',').first == name,
          ),
        );
        await tester.ensureVisible(button('Convert DSD'));
        await tester.pumpAndSettle();
        await tester.tap(button('Convert DSD'));
        await tester.pumpAndSettle();
        expect(
          focusIsOn(find.byKey(const ValueKey('output.dsd_pcm_rate'))),
          isTrue,
        );
        await tester.ensureVisible(button('Output'));
        await tester.pumpAndSettle();
        traversableFocusNodesIn(button('Output')).first.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(focusIsOn(find.byKey(const ValueKey('output.device'))), isTrue);

        await tester.ensureVisible(button('Conversion gain'));
        await tester.pumpAndSettle();
        await tester.tap(button('Conversion gain'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ExpertFieldList>(find.byType(ExpertFieldList))
              .initialQuery,
          'output.dsd_gain_db',
        );
        expect(find.text('DSD level'), findsOneWidget);
        expect(find.text('Volume control'), findsNothing);
        await tester.tap(find.byType(KalinkaBackButton));
        await tester.pumpAndSettle();
        await tester.ensureVisible(button('Headroom'));
        await tester.pumpAndSettle();
        await tester.tap(button('Headroom'));
        await tester.pumpAndSettle();
        final target = find.ancestor(
          of: find.text('Headroom'),
          matching: find.byType(SettingsJumpTarget),
        );
        expect(target, findsOneWidget);
        expect(tester.getTopLeft(target).dy, greaterThanOrEqualTo(0));
        expect(tester.getBottomLeft(target).dy, lessThanOrEqualTo(844));
        expect(api.writes, isEmpty);
        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'playback chain follows the current renderer and keeps its endpoints while stopped',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1024, 900);
        addTearDown(tester.view.reset);
        final track = homeTrack('kalinka:localfiles:track:1');
        final playing = PlaybackState(
          state: PlayerStateType.playing,
          currentTrack: track,
          mimeType: 'audio/flac',
          audioInfo: AudioInfo(
            sampleFormat: 'PCM24_LE',
            sampleRate: 192000,
            bitsPerSample: 24,
            channels: 2,
            output: OutputInfo(
              sampleFormat: 'PCM24_LE',
              sampleRate: 192000,
              bitsPerSample: 24,
              channels: 2,
              signalPath: const SignalPath(
                steps: [
                  SignalStep(
                    kind: 'fir',
                    name: 'FIR room correction',
                    summary: '4096 taps',
                  ),
                  SignalStep(
                    kind: 'peq',
                    name: 'Parametric EQ',
                    summary: 'Current EQ',
                  ),
                  SignalStep(
                    kind: 'preamp',
                    name: 'Preamp',
                    summary: '−9.10 dB',
                  ),
                  SignalStep(
                    kind: 'dither',
                    name: 'Dither',
                    summary: 'TPDF at 24 bits',
                  ),
                ],
              ),
            ),
          ),
        );
        PlayQueueState session(String id, PlaybackState playback) =>
            PlayQueueState(
              currentRendererId: id,
              playbackState: playback,
              trackList: [track],
              playbackMode: PlayQueueState.empty.playbackMode,
              seq: 1,
            );
        final queue = SettableQueue(session('other-renderer', playing));
        await pumpChain(tester, queue, _FakeApi());
        expect(find.text('PLAYBACK CHAIN'), findsNothing);
        queue.set(session(rendererId, playing));
        await tester.pumpAndSettle();
        expect(find.text('PLAYBACK CHAIN'), findsOneWidget);
        expect(find.text('Source'), findsOneWidget);
        List<Offset> markers() => find
            .descendant(
              of: find.byType(PlaybackChainDiagram),
              matching: find.byType(Icon),
            )
            .evaluate()
            .map((e) => tester.getCenter(find.byWidget(e.widget)))
            .toList();

        final rail = markers();
        expect(rail, hasLength(7));
        expect(rail.map((p) => p.dx).toSet(), hasLength(1));
        expect(
          rail.map((p) => p.dy),
          orderedEquals(rail.map((p) => p.dy).toList()..sort()),
        );
        final chainHeading = tester.getTopLeft(find.text('PLAYBACK CHAIN'));
        final settingsHeading = tester.getTopLeft(find.text('AUDIO OUTPUT'));
        expect(chainHeading.dy, settingsHeading.dy);
        expect(chainHeading.dx, lessThan(settingsHeading.dx));

        tester.view.physicalSize = const Size(750, 900);
        await tester.pumpAndSettle();
        final folded = markers();
        expect(folded.take(4).map((p) => p.dy).toSet(), hasLength(1));
        expect(folded[4].dx, folded[3].dx);
        expect(folded[4].dx, greaterThan(folded.last.dx));
        expect(folded.last.dx, folded[1].dx);

        tester.view.physicalSize = const Size(390, 844);
        await tester.pumpAndSettle();
        final phone = markers();
        expect(phone[0].dx, lessThan(phone[1].dx));
        expect(phone.map((p) => p.dy).toSet(), hasLength(4));
        for (final i in [1, 3, 5]) {
          expect(phone[i].dy, phone[i - 1].dy);
          expect(phone[i].dx, phone[i + 1].dx);
          expect(phone[i].dy, lessThan(phone[i + 1].dy));
        }
        expect(phone[2].dx, greaterThan(phone[3].dx));
        expect(phone[4].dx, lessThan(phone[5].dx));

        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();
        expect(markers().map((p) => p.dx).toSet(), hasLength(1));
        expect(tester.takeException(), isNull);

        queue.set(
          session(
            rendererId,
            PlaybackState(state: PlayerStateType.stopped, currentTrack: track),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('PLAYBACK CHAIN'), findsOneWidget);
        expect(find.text('No track playing'), findsOneWidget);
        expect(find.text('Configured output'), findsOneWidget);
        expect(find.text('FIR room correction'), findsNothing);
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        tester.view.physicalSize = const Size(800, 900);
        await tester.pumpAndSettle();
        final idle = markers();
        expect(idle, hasLength(2));
        expect(idle.first.dx, idle.last.dx);
        expect(
          tester.getTopLeft(find.text('PLAYBACK CHAIN')).dy,
          tester.getTopLeft(find.text('AUDIO OUTPUT')).dy,
        );
      },
    );

    testWidgets('the page proper shows nothing the renderer marked expert', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(_FakeApi()));
      await tester.pumpAndSettle();

      expect(find.text('Latency'), findsNothing);
      expect(find.text('CLOCK'), findsNothing);
      expect(find.text('Resync window'), findsNothing);
    });

    testWidgets('expert lists every setting by path, both tiers', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(_FakeApi()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('expert-mode-toggle')));
      await tester.pumpAndSettle();

      // Paths, not section cards — sorted, so the expert-only section leads.
      expect(find.text('clock.resync_ms'), findsOneWidget);
      expect(find.text('output.device'), findsOneWidget);
      expect(find.text('OUTPUT'), findsNothing, reason: 'flat list, no cards');
      // The speaker test belongs to the page, not the flat list.
      expect(find.text('Test'), findsNothing);

      // The rest are below the fold of an 800x600 window.
      await tester.scrollUntilVisible(
        find.text('output.latency_ms'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ExpertFieldList),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('output.latency_ms'), findsOneWidget);
    });

    testWidgets('on the demo server Apply explains instead of writing', (
      tester,
    ) async {
      final api = _FakeApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...overrides(api),
            demoModeProvider.overrideWithValue(true),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: RendererSettingsScreen(
                rendererId: rendererId,
                rendererName: 'Living Room',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('expert-mode-toggle')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'buffer');
      await tester.pump(const Duration(milliseconds: 200)); // debounce
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '900000');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.tap(_apply);
      await tester.pumpAndSettle();
      expect(find.byType(DemoReadOnlyDialog), findsOneWidget);
      expect(api.writes, isEmpty);
      expect(find.byTooltip('Apply 1 change'), findsOneWidget);
    });

    testWidgets('an expert row stages against the same renderer', (
      tester,
    ) async {
      final api = _FakeApi();
      await tester.pumpWidget(wrap(api));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('expert-mode-toggle')));
      await tester.pumpAndSettle();

      // Narrow to the one row, so the only other text field on screen is the
      // search box itself.
      await tester.enterText(find.byType(TextField).first, 'buffer');
      await tester.pump(const Duration(milliseconds: 200)); // debounce
      await tester.pumpAndSettle();
      expect(find.text('output.buffer_bytes'), findsOneWidget);
      expect(find.text('output.device'), findsNothing);

      await tester.enterText(find.byType(TextField).last, '900000');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.byTooltip('Apply 1 change'), findsOneWidget);

      await tester.tap(_apply);
      await tester.pumpAndSettle();
      expect(api.writes, [
        {'output.buffer_bytes': '900000'},
      ]);
    });

    testWidgets('a number outside the declared range is pulled back in', (
      tester,
    ) async {
      final api = _FakeApi();
      await tester.pumpWidget(wrap(api));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('expert-mode-toggle')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'buffer');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      // Below the renderer's minimum, which it would refuse on apply.
      await tester.enterText(find.byType(TextField).last, '10');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.tap(_apply);
      await tester.pumpAndSettle();
      expect(api.writes, [
        {'output.buffer_bytes': '64000'},
      ]);
    });

    testWidgets('a slider is drawn for a knob the renderer wants dragged', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(_FakeApi()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('expert-mode-toggle')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'latency');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(find.byType(Slider), findsOneWidget);
      // The range reads in the unit the renderer named.
      expect(find.text('20 ms'), findsOneWidget);
      expect(find.text('1000 ms'), findsOneWidget);
      // Continuous underneath: the discrete mode animates the thumb toward
      // each stop and reads as lag. Stops are ours, from the declared step.
      expect(tester.widget<Slider>(find.byType(Slider)).divisions, isNull);
    });

    testWidgets('a field description reads as a second line under its label', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(_FakeApi()));
      await tester.pumpAndSettle();

      expect(find.text('Volume control'), findsOneWidget);
      expect(find.text('How volume is applied'), findsOneWidget);
    });

    testWidgets('the popup dims an option detail onto its own line', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(_FakeApi()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('default (not present)'));
      await tester.pumpAndSettle();

      // Name and detail are separate lines, not one run-on label.
      expect(
        find.text('bcm2835 Headphones, bcm2835 Headphones'),
        findsNWidgets(2),
      );
      expect(
        find.text('Direct hardware device without any conversions'),
        findsOneWidget,
      );
      expect(
        find.text('Hardware device with all software conversions'),
        findsOneWidget,
      );
      // The detail is set smaller than the name it sits under.
      final name = tester.widget<Text>(
        find.text('bcm2835 Headphones, bcm2835 Headphones').first,
      );
      final detail = tester.widget<Text>(
        find.text('Direct hardware device without any conversions'),
      );
      expect(detail.style!.fontSize, lessThan(name.style!.fontSize!));
    });

    Future<void> choose(
      WidgetTester tester,
      String current,
      String next,
    ) async {
      await tester.tap(find.text(current));
      await tester.pumpAndSettle();
      await tester.tap(find.text(next));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'auditioning FIR writes only the profile and preserves staged edits',
      (tester) async {
        final api = _FakeApi(payload: _firPayload());
        await tester.pumpWidget(wrap(api));
        await tester.pumpAndSettle();
        expect(find.text('FIR Convolution'), findsNothing);
        await choose(tester, 'Automatic', 'Software');
        await openSection(tester, 'Room EQ');
        expect(find.text('FIR Convolution'), findsOneWidget);
        expect(
          find.textContaining('selected impulse at its sample rate'),
          findsNothing,
        );
        await tester.tap(find.byTooltip('About FIR Convolution'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
            'selected impulse at its sample rate',
            findRichText: true,
          ),
          findsWidgets,
        );
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(api.writes, isEmpty);

        // Each read after a write reports the active profile on the renderer.
        api.payload = _firPayload(value: 'test.wav');
        await choose(tester, 'Off', 'Test filter');
        expect(find.text('Test filter'), findsOneWidget);
        expect(find.byTooltip('Apply 1 change'), findsOneWidget);

        api.payload = _firPayload();
        await choose(tester, 'Test filter', 'Off');
        expect(find.text('Off'), findsOneWidget);
        await tester.tap(_apply);
        await tester.pumpAndSettle();
        expect(api.writes, [
          {'output.rew_fir_profile': 'test.wav'},
          {'output.rew_fir_profile': 'off'},
          {'output.volume_mode': 'software'},
        ]);
      },
    );

    testWidgets(
      'a refused live FIR selection displays the active profile and error',
      (tester) async {
        final api = _FakeApi(
          payload: _firPayload(),
          outcomes: [
            {
              'path': 'output.rew_fir_profile',
              'applied': false,
              'value': 'off',
              'error': 'Filter file missing',
            },
          ],
        );
        await tester.pumpWidget(wrap(api));
        await tester.pumpAndSettle();
        await openSection(tester, 'Room EQ');
        await choose(tester, 'Off', 'Test filter');
        expect(find.text('Off'), findsOneWidget);
        expect(find.textContaining('Filter file missing'), findsOneWidget);
        expect(find.byTooltip('Apply 1 change'), findsNothing);
      },
    );

    testWidgets(
      'an active FIR profile remains editable while parametric EQ is off',
      (tester) async {
        final config =
            jsonDecode(_firPayload(value: 'test.wav')) as Map<String, dynamic>;
        (config['sections'] as List).add({
          'path': 'dsp',
          'title': 'Room correction',
          'fields': [
            {
              'path': 'dsp.profile',
              'title': 'Room profile',
              'type': 'enum',
              'value': 'none',
              'options': [
                {'value': 'none', 'label': 'None'},
              ],
            },
            {
              'path': 'dsp.enabled',
              'title': 'Room correction',
              'type': 'bool',
              'value': 'false',
            },
          ],
        });
        final api = _FakeApi(payload: jsonEncode(config));
        await tester.pumpWidget(wrap(api));
        await tester.pumpAndSettle();
        await openSection(tester, 'Room EQ');
        expect(find.text('FIR Convolution'), findsOneWidget);
        expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
        expect(find.text('Test filter').hitTestable(), findsOneWidget);
        Rect cardBounds(String heading) => tester.getRect(
          find
              .ancestor(of: find.text(heading), matching: find.byType(Material))
              .first,
        );
        final fir = cardBounds('FIR Convolution');
        final presets = cardBounds('EQ preset');
        final firTitle = tester.getRect(find.text('FIR Convolution'));
        expect(
          firTitle.top - fir.top,
          firTitle.height <= 36
              ? closeTo((48 - firTitle.height) / 2, 1)
              : inInclusiveRange(0, 6),
        );
        final presetTitle = tester.getRect(find.text('EQ preset'));
        expect(presetTitle.top - presets.top, greaterThanOrEqualTo(12));
        expect(presetTitle.left - presets.left, 16);
        expect(presets.left, fir.left);
        expect(presets.width, fir.width);
        expect(presets.top - fir.bottom, greaterThanOrEqualTo(12));
        expect(api.writes, isEmpty);
        await tester.tap(find.text('Test filter'));
        await tester.pumpAndSettle();
        final pending = api.holdWrite = Completer<void>();
        await tester.tap(find.text('Off').hitTestable());
        await tester.pump();
        expect(api.writes.single, {'output.rew_fir_profile': 'off'});
        expect(tester.getSize(find.byType(LinearProgressIndicator)).height, 1);
        expect(cardBounds('FIR Convolution'), fir);
        expect(cardBounds('EQ preset'), presets);
        pending.complete();
        await tester.pumpAndSettle();
        expect(find.byType(LinearProgressIndicator), findsNothing);
      },
    );

    testWidgets('direct output leaves Room EQ shut and says why', (
      tester,
    ) async {
      final api = _FakeApi(payload: _firPayload(direct: true));
      await tester.pumpWidget(wrap(api));
      await tester.pumpAndSettle();
      expect(find.text('Off while Direct output is on'), findsOneWidget);
      await tester.tap(find.text('Room EQ'));
      await tester.pumpAndSettle();
      expect(find.text('FIR Convolution'), findsNothing);
    });

    testWidgets('demo mode blocks live FIR writes', (tester) async {
      final api = _FakeApi(payload: _firPayload());
      await tester.pumpWidget(wrap(api, demo: true));
      await tester.pumpAndSettle();
      await openSection(tester, 'Room EQ');
      await choose(tester, 'Off', 'Test filter');
      expect(find.byType(DemoReadOnlyDialog), findsOneWidget);
      expect(api.writes, isEmpty);
    });

    testWidgets('a renderer that interrupts playback keeps FIR staged', (
      tester,
    ) async {
      final api = _FakeApi(payload: _firPayload(cost: 'interrupts_playback'));
      await tester.pumpWidget(wrap(api));
      await tester.pumpAndSettle();
      await openSection(tester, 'Room EQ');
      await choose(tester, 'Off', 'Test filter');
      expect(api.writes, isEmpty);
      expect(
        find.byTooltip('Apply 1 change, playback will stop'),
        findsOneWidget,
      );
    });

    testWidgets(
      'ReplayGain belongs with output volume and keeps its Core setting path',
      (tester) async {
        final config = jsonDecode(_firPayload()) as Map<String, dynamic>;
        final sections = config['sections'] as List;
        sections.insert(0, {
          'path': 'core.output',
          'title': 'Connected device',
          'fields': [
            {
              'path': 'core.output.device_module',
              'title': 'Volume and power',
              'type': 'string',
              'value': 'This renderer',
              'read_only': true,
            },
            {
              'path': 'core.output.replaygain',
              'title': 'ReplayGain',
              'type': 'enum',
              'apply': 'instant',
              'value': 'disabled',
              'options': [
                {'value': 'disabled', 'label': 'Disabled'},
                {'value': 'track', 'label': 'Track level'},
              ],
            },
          ],
        });
        final api = _FakeApi(payload: jsonEncode(config));
        await tester.pumpWidget(wrap(api));
        await tester.pumpAndSettle();
        expect(find.text('Volume and power'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('CONNECTED DEVICE')).dy,
          greaterThan(tester.getTopLeft(find.text('ReplayGain')).dy),
        );
        expect(
          tester.getTopLeft(find.text('ReplayGain')).dy,
          greaterThan(tester.getTopLeft(find.text('Volume control')).dy),
        );
        await choose(tester, 'Disabled', 'Track level');
        await tester.tap(_apply);
        await tester.pumpAndSettle();
        expect(api.writes, [
          {'core.output.replaygain': 'track'},
        ]);

        // Outputs without native settings (for example a delegated output) still expose ReplayGain.
        sections.removeLast();
        final view = adaptRendererConfig(_snapshot(jsonEncode(config)));
        expect(
          view.sections.singleWhere((s) => s.id == 'output').fields.single.path,
          'core.output.replaygain',
        );
      },
    );

    testWidgets('choosing a device stages it and names the cost', (
      tester,
    ) async {
      final api = _FakeApi();
      await tester.pumpWidget(wrap(api));
      await tester.pumpAndSettle();

      // The dropdown trigger shows the current option's label.
      await tester.tap(find.text('default (not present)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('HiFiBerry Digi+ Pro'));
      await tester.pumpAndSettle();

      expect(
        find.byTooltip('Apply 1 change, playback will stop'),
        findsOneWidget,
      );

      await tester.tap(_apply);
      await tester.pumpAndSettle();

      expect(api.writes, [
        {'output.device': 'hw:CARD=sndrpihifiberry,DEV=0'},
      ]);
    });

    testWidgets('leaving with a staged change asks, listing it', (
      tester,
    ) async {
      final api = _FakeApi();
      var closed = 0;
      await tester.pumpWidget(wrap(api, onClose: () => closed++));
      await tester.pumpAndSettle();
      expect(_apply, findsNothing);
      await tester.tap(find.text('default (not present)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('HiFiBerry Digi+ Pro'));
      await tester.pumpAndSettle();
      expect(_apply, findsOneWidget);
      expect(
        find.byKey(const ValueKey('pending-changes-revert')),
        findsOneWidget,
      );

      Future<void> leave() async {
        await tester.tap(find.byKey(const ValueKey('settings-back')));
        await tester.pumpAndSettle();
        expect(find.text('Apply your changes?'), findsOneWidget);
        expect(
          find.text('Applying them stops playback on this output.'),
          findsOneWidget,
        );
      }

      final list = find.byKey(const ValueKey('pending-changes-list'));
      await leave();
      expect(
        find.descendant(of: list, matching: find.textContaining('Device')),
        findsOneWidget,
      );
      // Dismissed, the page stays with its edit.
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(closed, 0);
      expect(_apply, findsOneWidget);

      await leave();
      await tester.tap(
        find.byKey(const ValueKey('pending-changes-dialog-apply')),
      );
      await tester.pumpAndSettle();
      expect(api.writes, [
        {'output.device': 'hw:CARD=sndrpihifiberry,DEV=0'},
      ]);
      expect(closed, 1);
    });

    testWidgets('Back waits for Apply and a failed refresh allows retry', (
      tester,
    ) async {
      final api = _FakeApi();
      var closed = false;
      await tester.pumpWidget(wrap(api, onClose: () => closed = true));
      await tester.pumpAndSettle();
      await tester.tap(find.text('default (not present)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('HiFiBerry Digi+ Pro'));
      await tester.pumpAndSettle();

      final write = api.holdWrite = Completer<void>();
      final refresh = api.holdLoad = Completer<void>();
      final back = find.byKey(const ValueKey('settings-back'));
      await tester.tap(_apply);
      await tester.pump();
      expect(api.writes, hasLength(1));
      await tester.tap(back);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(closed, isFalse);

      write.complete();
      await tester.pump();
      refresh.completeError(
        const RendererConfigException('Output went offline'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Output went offline'), findsOneWidget);

      api.holdLoad = null;
      await tester.tap(back);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('pending-changes-dialog-apply')),
      );
      await tester.pumpAndSettle();
      expect(api.writes, hasLength(2));
      expect(closed, isTrue);
    });

    testWidgets('the speaker test plays both channels on this renderer', (
      tester,
    ) async {
      final api = _FakeApi();
      await tester.pumpWidget(wrap(api));
      await tester.pumpAndSettle();

      // The card sits below the fold in an 800x600 test window.
      await tester.ensureVisible(find.text('Test'));
      await tester.tap(find.text('Test'));
      await tester.pump();

      expect(find.text('Testing Living Room'), findsOneWidget);
      expect(api.tones, ['left']);
      expect(api.toneRendererId, rendererId);

      // The right channel follows three seconds later.
      await tester.pump(const Duration(seconds: 3));
      expect(api.tones, ['left', 'right']);

      // Never pumpAndSettle here: the dialog's speaker pulse repeats forever.
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Play again'), findsOneWidget, reason: 'run finished');
      await tester.tap(find.text('Close'));
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('the test is held back while changes are staged', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(_FakeApi()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('auto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('software'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Apply your changes first'), findsOneWidget);
      expect(
        tester.widget<KalinkaButton>(find.byType(KalinkaButton)).enabled,
        isFalse,
      );
    });

    testWidgets('a renderer that cannot be reached offers a retry', (
      tester,
    ) async {
      final api = _FakeApi(
        loadError: const RendererConfigException('That output didn’t respond'),
      );
      await tester.pumpWidget(wrap(api));
      await tester.pumpAndSettle();

      expect(find.text('Couldn’t load settings'), findsOneWidget);
      expect(find.text('That output didn’t respond'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(api.loadCalls, 2);
    });

    testWidgets('the renderer section carries host and version on its label', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapWithList(_FakeApi(payload: _readonlyNamePayload), [
          const RendererInfo(
            rendererId: rendererId,
            friendlyName: 'Living Room',
            status: 'connected',
            hostname: 'pi-living',
            softwareVersion: '1.2.3',
          ),
        ]),
      );
      await tester.pumpAndSettle();
      await openSection(tester, 'Renderer');

      final badge = find.text('pi-living · v1.2.3');
      expect(badge, findsOneWidget);
      // Under the section label, above the field card.
      final badgeTop = tester.getRect(badge).top;
      expect(badgeTop, greaterThan(tester.getRect(find.text('Renderer')).top));
      expect(badgeTop, lessThan(tester.getRect(find.text('Name')).top));
    });

    testWidgets('a read-only name is grey, with no input to mistake it for', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapWithList(_FakeApi(payload: _readonlyNamePayload), const []),
      );
      await tester.pumpAndSettle();
      await openSection(tester, 'Renderer');

      expect(find.byType(SettingsTextInput), findsNothing);
      expect(find.byType(SettingsReadonlyCard), findsNothing);
      final value = tester.widget<Text>(find.text('Living Room').last);
      expect(value.data, 'Living Room');
      expect(value.style!.color, KalinkaColors.textSecondary);
    });
  });
}
