import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/data_model.dart' show RendererInfo;
import 'package:kalinka/data_model/presentation_schema.dart';
import 'package:kalinka/data_model/renderer_config.dart';
import 'package:kalinka/data_model/renderer_config_adapter.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/renderer_provider.dart';
import 'package:kalinka/providers/renderer_settings_provider.dart';
import 'package:kalinka/screens/renderer_settings_screen.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/kalinka_button.dart';
import 'package:kalinka/widgets/settings_controls/settings_readonly_card.dart';
import 'package:kalinka/widgets/settings_controls/settings_text_input.dart';

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

/// Serves the captured config and records writes; everything else throws.
class _FakeApi implements KalinkaPlayerProxy {
  _FakeApi({this.loadError, this.outcomes, this.payload = _configPayload});

  /// Thrown by [getRendererConfig] when set.
  final Object? loadError;

  /// Served by [getRendererConfig].
  final String payload;

  /// Returned by [updateRendererConfig] when set; defaults to "all applied".
  final List<Map<String, dynamic>>? outcomes;

  int loadCalls = 0;
  final List<Map<String, String>> writes = [];
  final List<String> tones = [];
  String? toneRendererId;

  @override
  Future<RendererConfigSnapshot> getRendererConfig(String rendererId) async {
    loadCalls++;
    if (loadError != null) throw loadError!;
    return _snapshot(payload);
  }

  @override
  Future<RendererConfigResult> updateRendererConfig(
    String rendererId,
    Map<String, String> changes,
  ) async {
    writes.add(changes);
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

/// The speaker-test card sits past the fold of an 800x600 test window, and how
/// far past moves with the pending-changes banner — so scroll to it rather
/// than assuming it is built.
Future<void> scrollToSpeakerTest(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Test settings'),
    200,
    scrollable: find.byType(Scrollable).first,
  );
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
    sharedPrefsProvider.overrideWithValue(prefs),
    kalinkaProxyProvider.overrideWithValue(api),
    connectionStateProvider.overrideWith(_FakeConnectionNotifier.new),
  ];

  ProviderContainer makeContainer(KalinkaPlayerProxy api) {
    final container = ProviderContainer(overrides: overrides(api));
    addTearDown(container.dispose);
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
    Widget wrap(KalinkaPlayerProxy api, {double? maxContentWidth}) =>
        ProviderScope(
          overrides: overrides(api),
          child: MaterialApp(
            home: Scaffold(
              body: RendererSettingsScreen(
                rendererId: rendererId,
                rendererName: 'Living Room',
                maxContentWidth: maxContentWidth,
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

      expect(find.text('Living Room'), findsOneWidget);
      expect(find.text('OUTPUT SETTINGS'), findsOneWidget);
      // Section label, then the fields the renderer declared.
      expect(find.text('OUTPUT'), findsOneWidget);
      expect(find.text('Device'), findsOneWidget);
      expect(find.text('Volume control'), findsOneWidget);
      // Trigger field dropped, per the adapter.
      expect(find.text('Reset'), findsNothing);
      expect(find.text('SPEAKER TEST'), findsOneWidget);
      expect(find.text('Test settings'), findsOneWidget);
    });

    testWidgets('a capped panel centres its column on a wide window', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(_FakeApi()));
      await tester.pumpAndSettle();
      // Uncapped (the player): the panel fills what it is given.
      expect(tester.getRect(find.byIcon(Icons.arrow_back)).left, lessThan(50));
      expect(tester.getRect(find.text('EXPERT')).right, greaterThan(1000));

      await tester.pumpWidget(wrap(_FakeApi(), maxContentWidth: 600));
      await tester.pumpAndSettle();
      final back = tester.getRect(find.byIcon(Icons.arrow_back));
      final expert = tester.getRect(find.text('EXPERT'));
      expect(back.left, greaterThan(300));
      expect(back.left, lessThan(350));
      expect(expert.right, greaterThan(780));
      expect(expert.right, lessThan(900));
    });

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

      await tester.tap(find.text('EXPERT'));
      await tester.pumpAndSettle();

      // Paths, not section cards — sorted, so the expert-only section leads.
      expect(find.text('clock.resync_ms'), findsOneWidget);
      expect(find.text('output.device'), findsOneWidget);
      expect(find.text('OUTPUT'), findsNothing, reason: 'flat list, no cards');
      // The speaker test belongs to the page, not the flat list.
      expect(find.text('Test settings'), findsNothing);

      // The rest are below the fold of an 800x600 window.
      await tester.scrollUntilVisible(
        find.text('output.latency_ms'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('output.latency_ms'), findsOneWidget);
    });

    testWidgets('an expert row stages against the same renderer', (
      tester,
    ) async {
      final api = _FakeApi();
      await tester.pumpWidget(wrap(api));
      await tester.pumpAndSettle();

      await tester.tap(find.text('EXPERT'));
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

      expect(find.text('1 change staged'), findsOneWidget);

      await tester.tap(find.text('APPLY'));
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

      await tester.tap(find.text('EXPERT'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'buffer');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      // Below the renderer's minimum, which it would refuse on apply.
      await tester.enterText(find.byType(TextField).last, '10');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.tap(find.text('APPLY'));
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

      await tester.tap(find.text('EXPERT'));
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

      expect(find.text('1 change staged · playback will stop'), findsOneWidget);

      await tester.tap(find.text('APPLY'));
      await tester.pumpAndSettle();

      expect(api.writes, [
        {'output.device': 'hw:CARD=sndrpihifiberry,DEV=0'},
      ]);
    });

    testWidgets('the speaker test plays both channels on this renderer', (
      tester,
    ) async {
      final api = _FakeApi();
      await tester.pumpWidget(wrap(api));
      await tester.pumpAndSettle();

      // The card sits below the fold in an 800x600 test window.
      await scrollToSpeakerTest(tester);
      await tester.tap(find.text('Test settings'));
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

      await scrollToSpeakerTest(tester);
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

      final badge = find.text('pi-living · v1.2.3');
      expect(badge, findsOneWidget);
      // Under the section label, above the field card.
      final badgeTop = tester.getRect(badge).top;
      expect(badgeTop, greaterThan(tester.getRect(find.text('RENDERER')).top));
      expect(badgeTop, lessThan(tester.getRect(find.text('Name')).top));
    });

    testWidgets('a read-only name is grey, with no input to mistake it for', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapWithList(_FakeApi(payload: _readonlyNamePayload), const []),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SettingsTextInput), findsNothing);
      expect(find.byType(SettingsReadonlyCard), findsNothing);
      final value = tester.widget<Text>(find.text('Living Room').last);
      expect(value.data, 'Living Room');
      expect(value.style!.color, KalinkaColors.textSecondary);
    });
  });
}
