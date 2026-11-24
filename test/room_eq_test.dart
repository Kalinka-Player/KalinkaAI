import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/renderer_config.dart';
import 'package:kalinka/data_model/data_model.dart'
    show PlaybackState, AudioInfo, OutputInfo;
import 'package:kalinka/data_model/playqueue_events.dart' show PlayQueueEvent;
import 'package:kalinka/data_model/room_eq.dart';
import 'package:kalinka/generated/kalinka/renderer/v1/renderer.pb.dart' as wire;
import 'package:kalinka/providers/wire_event_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/renderer_settings_provider.dart';
import 'package:kalinka/screens/renderer_settings_screen.dart';
import 'package:kalinka/screens/room_eq_screen.dart';
import 'package:kalinka/widgets/slide_in_panel.dart';
import 'package:kalinka/widgets/kalinka_button.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/room_eq/response_graph.dart';
import 'package:kalinka/widgets/room_eq/filter_shape_icon.dart';
import 'package:kalinka/widgets/room_eq/eq_card.dart';
import 'package:kalinka/widgets/browse_filters/browse_filter_form.dart'
    show FilterPill;

import 'support/focus.dart';

class _Online extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

class _Api implements KalinkaPlayerProxy {
  _Api(this.curve);
  EqCurve curve;
  bool firImport = false;
  Map<String, dynamic>? response;
  wire.FirProfile? importedImpulse;
  @override
  Future<String> importFirProfile(Uint8List payload) async {
    importedImpulse = wire.FirProfile.fromBuffer(payload);
    return 'fir-id';
  }

  Map<String, String>? published;
  final values = {
    'dsp.profile': 'original',
    'dsp.enabled': 'true',
    'dsp.bypass': 'true',
    'dsp.preamp': 'auto',
    'dsp.preamp_db': '-2.5',
    'output.name': 'Test output',
  };
  final writes = <Map<String, String>>[];
  final edits = <Map<String, String>>[];
  bool reject = false;
  Completer<void>? pendingWrite;
  @override
  Future<RendererConfigResult> editEqCurve(
    String id,
    Map<String, String> curve,
  ) async {
    edits.add(curve);
    if (!reject) values['dsp.profile'] = 'working';
    return RendererConfigResult(
      outcomes: [
        RendererConfigOutcome(
          path: 'dsp.profile',
          applied: !reject,
          error: reject ? 'Output offline' : '',
        ),
      ],
    );
  }

  @override
  Future<EqCurve> getEqCurve(String id) async =>
      id == 'saved' ? EqCurve(published!['name']!, curve.channels) : curve;
  @override
  Future<String> importEqCurve(Map<String, String> payload) async {
    published = payload;
    return 'saved';
  }

  @override
  Future<RendererConfigResult> updateRendererConfig(
    String id,
    Map<String, String> changes,
  ) async {
    writes.add(changes);
    await pendingWrite?.future;
    if (!reject) values.addAll(changes);
    return RendererConfigResult(
      outcomes: [
        for (final k in changes.keys)
          RendererConfigOutcome(
            path: k,
            applied: !reject,
            error: reject ? 'Output offline' : '',
          ),
      ],
    );
  }

  @override
  Future<RendererConfigSnapshot> getRendererConfig(String id) async =>
      RendererConfigSnapshot.fromJson({
        'sections': [
          {
            'path': 'output',
            'title': 'Output',
            'fields': [
              {
                'path': 'output.name',
                'title': 'Output name',
                'type': 'string',
                'value': values['output.name'],
              },
            ],
          },
          {
            'path': 'dsp',
            'title': 'Room correction',
            'fields': [
              if (firImport)
                {
                  'path': RendererConfigField.rewFirProfile,
                  'title': 'FIR Convolution',
                  'supports_fir_import': true,
                  if (response != null) ...{
                    'matches_fir_rates': true,
                    'fir_response': response,
                  },
                  'type': 'enum',
                  'apply': 'instant',
                  'value': values[RendererConfigField.rewFirProfile] ?? 'off',
                  'options': [
                    {'value': 'off', 'label': 'Off'},
                    if (importedImpulse != null)
                      {'value': 'fir-id', 'label': importedImpulse!.name},
                  ],
                },
              for (final e in values.entries.where(
                (e) => e.key.startsWith('dsp.'),
              ))
                {
                  'path': e.key,
                  'title': e.key == 'dsp.preamp_db' ? 'Manual preamp' : e.key,
                  'value': e.value,
                  'apply': 'instant',
                  'type': switch (e.key) {
                    'dsp.enabled' || 'dsp.bypass' => 'bool',
                    'dsp.preamp_db' => 'decimal',
                    _ => 'enum',
                  },
                  'options': switch (e.key) {
                    'dsp.profile' => [
                      {'value': 'none', 'label': 'None'},
                      {'value': 'original', 'label': curve.name},
                      if (values['dsp.profile'] == 'working')
                        {'value': 'working', 'label': 'Current EQ'},
                      if (published != null)
                        {'value': 'saved', 'label': published!['name']},
                    ],
                    'dsp.preamp' => [
                      {'value': 'auto', 'label': 'Automatic'},
                      {'value': 'manual', 'label': 'Manual'},
                    ],
                    _ => [],
                  },
                  if (e.key == 'dsp.preamp_db')
                    'range': {'min': -30, 'max': 0, 'step': 0.1},
                },
            ],
          },
        ],
      });
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final capture = Platform.environment['KALINKA_REVIEW_DIR'];
  final profile = Platform.environment['KALINKA_REVIEW_PROFILE'];
  final boundary = GlobalKey();
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'Kalinka.host': 'localhost',
      'Kalinka.port': 8000,
      'Kalinka.name': 'Listening room',
    });
    prefs = await SharedPreferences.getInstance();
  });
  setUpAll(() async {
    if (capture == null) return;
    for (final (family, file) in [
      ('IBM Plex Sans', 'IBMPlexSans-Regular.ttf'),
      ('IBM Plex Mono', 'IBMPlexMono-Regular.ttf'),
      ('Playfair Display', 'PlayfairDisplay-Regular.ttf'),
    ]) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$file'))).load();
    }
    await (FontLoader('MaterialIcons')..addFont(
          Future.value(
            ByteData.sublistView(
              File(
                '${Platform.environment["FLUTTER_ROOT"]}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
              ).readAsBytesSync(),
            ),
          ),
        ))
        .load();
  });

  void mockFilePicker(List<File> files, {bool multiple = false}) {
    var next = 0;
    const channel = MethodChannel('plugins.flutter.io/file_selector');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => multiple
          ? files.map((file) => file.path).toList()
          : [files[next++].path],
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  }

  Future<void> chooseFile(WidgetTester t, String label, String result) async {
    final row = find.text(label);
    await t.ensureVisible(row);
    await t.runAsync(() async {
      await t.tap(row);
      for (var i = 0; i < 100 && find.text(result).evaluate().isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await t.pump();
      }
    });
    await t.pumpAndSettle();
    expect(find.text(result), findsOneWidget);
  }

  Future<void> screenshot(WidgetTester t, String name) async {
    if (capture == null) return;
    await t.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await File('$capture/$name.png').writeAsBytes(data.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> open(
    WidgetTester t,
    _Api api,
    Size size, {
    double scale = 1,
    bool animateEntry = false,
    Stream<PlayQueueEvent>? events,
  }) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = size;
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          playQueueEventBusProvider.overrideWith(
            (ref) => events ?? const Stream.empty(),
          ),
          kalinkaProxyProvider.overrideWithValue(api),
          sharedPrefsProvider.overrideWithValue(prefs),
          connectionStateProvider.overrideWith(_Online.new),
        ],
        child: RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                disableAnimations: !animateEntry,
              ),
              child: child!,
            ),
            home: const Scaffold(
              body: RendererSettingsScreen(
                rendererId: 'out',
                rendererName: 'Listening room',
              ),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Room EQ'));
    await t.tap(find.text('Room EQ'));
    if (animateEntry) {
      await t.pump();
    } else {
      await t.pumpAndSettle();
    }
  }

  EqCurve sample() => EqCurve('Studio stereo', {
    EqChannel.shared: [
      const EqBand(hz: 250, gain: -4, q: 1.4),
      const EqBand(shape: FilterShape.highShelf, hz: 7000, gain: 2),
    ],
  });
  test(
    'peak and shelf response matches analytic centre and endpoint gains',
    () {
      for (final shape in FilterShape.values.where((s) => s.hasGain)) {
        final f = EqBand(
          shape: shape,
          hz: 1000,
          gain: 6,
          q: .8,
        ).response(48000);
        expect(
          f(2 * math.pi / 48),
          closeTo(shape == FilterShape.peak ? 6 : 3, 1e-9),
        );
        expect(f(0), closeTo(shape == FilterShape.lowShelf ? 6 : 0, 1e-8));
        expect(
          f(math.pi),
          closeTo(shape == FilterShape.highShelf ? 6 : 0, 1e-8),
        );
      }
    },
  );
  test('pass filters decode, export to REW and match their cutoff and slope', () {
    for (final (shape, type) in [
      (FilterShape.lowPass, wire.DspProfile_Band_Type.LOW_PASS),
      (FilterShape.highPass, wire.DspProfile_Band_Type.HIGH_PASS),
      (
        FilterShape.firstOrderLowPass,
        wire.DspProfile_Band_Type.FIRST_ORDER_LOW_PASS,
      ),
      (
        FilterShape.firstOrderHighPass,
        wire.DspProfile_Band_Type.FIRST_ORDER_HIGH_PASS,
      ),
    ]) {
      const hz = 1000.0, rate = 48000.0;
      final profile = wire.DspProfile(
        version: 1,
        shared: [
          wire.DspProfile_Band(
            type: type,
            frequencyHz: hz,
            q: shape.hasQ ? 2 : 0,
          ),
        ],
      );
      final curve = EqCurve.fromBytes(profile.writeToBuffer());
      final band = curve.channels[EqChannel.shared]!.single;
      expect(band.shape, shape);
      expect(band.active, isTrue);
      final cutoff = 2 * math.pi * hz / rate;
      final response = band.response(rate);
      expect(
        response(cutoff),
        closeTo(shape.hasQ ? 6.0205999 : -3.01029996, 1e-6),
      );
      expect(band.handleGain, closeTo(response(cutoff), 1e-8));
      // Bilinear-prewarped test frequencies lie one decade apart on the stop side.
      double stopAt(double decades) => response(
        2 *
            math.atan(
              math.tan(cutoff / 2) *
                  math.pow(10, shape.isLowPass ? decades : -decades),
            ),
      );
      expect(stopAt(2) - stopAt(1), closeTo(shape.hasQ ? -40 : -20, 0.15));
      final exported = curve.toRew('Test')['shared'];
      expect(
        exported,
        'Equaliser: Generic\nFilter 1: ON ${shape.rew} Fc 1000.0 Hz${shape.hasQ ? ' Q 2.0' : ''}',
      );
      profile.shared.single.gainDb = 1;
      expect(
        () => EqCurve.fromBytes(profile.writeToBuffer()),
        throwsFormatException,
      );
      profile.shared.single.gainDb = 0;
      profile.shared.single.q = shape.hasQ ? 0 : 1;
      expect(
        () => EqCurve.fromBytes(profile.writeToBuffer()),
        throwsFormatException,
      );
    }
  });

  testWidgets(
    'a pass-only curve stays active and exposes its editable controls',
    (t) async {
      final api = _Api(EqCurve.empty());
      await open(t, api, const Size(1024, 900));
      await t.tap(find.byTooltip('Add band'));
      await t.pumpAndSettle();
      await t.tap(
        find.widgetWithText(
          PopupMenuItem<FilterShape>,
          FilterShape.firstOrderHighPass.label,
        ),
      );
      await t.pumpAndSettle();
      expect(api.edits.single['shared'], endsWith('ON HP1 Fc 1000.0 Hz'));
      expect(find.byKey(const ValueKey('eq-slider-Frequency')), findsOneWidget);
      expect(find.byKey(const ValueKey('eq-slider-Gain')), findsNothing);
      expect(find.byKey(const ValueKey('eq-slider-Q')), findsNothing);
      final selector = find.byType(DropdownButton<FilterShape>);
      await t.ensureVisible(selector);
      await t.tap(selector);
      await t.pumpAndSettle();
      await t.tap(find.text(FilterShape.lowPass.label).hitTestable().last);
      await t.pumpAndSettle();
      expect(api.edits.last['shared'], contains('ON LPQ Fc 1000.0 Hz Q 0.707'));
      expect(find.byKey(const ValueKey('eq-slider-Gain')), findsNothing);
      expect(find.byKey(const ValueKey('eq-slider-Q')), findsOneWidget);
      expect(
        t
            .widget<KalinkaButton>(
              find.widgetWithText(KalinkaButton, 'Save preset'),
            )
            .enabled,
        isTrue,
      );
      expect(api.writes, isEmpty);
    },
  );

  test('stereo protobuf and REW export retain the other channel and an empty channel', () {
    final p = wire.DspProfile(
      version: 1,
      name: 'Stereo',
      left: [
        wire.DspProfile_Band(
          type: wire.DspProfile_Band_Type.LOW_SHELF,
          frequencyHz: 77,
          gainDb: 1,
          q: .7,
        ),
      ],
    );
    final curve = EqCurve.fromBytes(p.writeToBuffer());
    expect(curve.toRew('First')['right'], contains('OFF None'));
    final edit = curve.withBands(EqChannel.right, [
      const EqBand(hz: 125, gain: -2),
    ]);
    expect(
      edit.toRew('Second')['left'],
      contains('ON LSQ Fc 77.0 Hz Gain 1.0 dB Q 0.7'),
    );
    expect(edit.toRew('Second')['right'], contains('ON PK Fc 125.0 Hz'));
    expect(curve.channels[EqChannel.right], isEmpty);
  });
  testWidgets(
    'Room EQ slides over renderer settings and back to the same list',
    (t) async {
      await open(t, _Api(sample()), const Size(1024, 768), animateEntry: true);
      final pane = t.getRect(find.byType(RendererSettingsScreen));
      final eq = find.byType(RoomEqScreen);
      final listItem = find.text('Speaker test');
      expect(t.getTopLeft(eq).dx, closeTo(pane.right, 1));
      expect(listItem, findsOneWidget);

      await t.pump(kSlideInPanelDuration ~/ 2);
      expect(t.getTopLeft(eq).dx, inExclusiveRange(pane.left, pane.right));
      await t.pumpAndSettle();
      expect(t.getRect(eq), pane);
      expect(listItem, findsNothing);

      await t.tap(find.byKey(const ValueKey('settings-back')));
      await t.pump();
      await t.pump(kSlideInPanelDuration ~/ 2);
      expect(t.getTopLeft(eq).dx, inExclusiveRange(pane.left, pane.right));
      expect(listItem, findsOneWidget);
      await t.pumpAndSettle();
      expect(eq, findsNothing);
      expect(listItem, findsOneWidget);
    },
  );

  testWidgets(
    'preamp and EQ bands stay visible together and share a playback switch',
    (t) async {
      final api = _Api(
        profile == null
            ? sample()
            : EqCurve.fromBytes(File(profile).readAsBytesSync()),
      );
      await open(t, api, const Size(1024, 768));
      final graph = find.byType(ResponseGraph);
      for (final label in [
        'Preamp',
        'EQ preset',
        'Filter response',
        'Parametric bands (${api.curve.channels.values.first.length})',
      ]) {
        final title = find.text(label);
        final card = find.ancestor(of: title, matching: find.byType(EqCard));
        expect(
          t.getCenter(title).dy - t.getTopLeft(card).dy,
          closeTo(24, 1),
          reason: label,
        );
      }

      expect(
        t.getTopRight(graph).dx,
        lessThan(t.getTopLeft(find.text('Manual')).dx),
      );
      expect(
        t.getTopLeft(find.text('EQ preset')).dy,
        greaterThan(t.getBottomLeft(find.text('Manual')).dy),
      );
      expect(
        find.byKey(const ValueKey('eq-band-1')).hitTestable(),
        findsOneWidget,
      );
      expect(find.text('DSP bypassed'), findsOneWidget);
      expect(
        t.widget<ResponseGraph>(graph).responseColor,
        KalinkaColors.textSecondary,
      );
      expect(find.byIcon(Icons.radio_button_checked), findsNothing);
      expect(api.writes, isEmpty);
      await screenshot(t, 'room-eq-tablet');
      expect(
        find.ancestor(of: graph, matching: find.byType(RendererSettingsScreen)),
        findsOneWidget,
      );
      final container = ProviderScope.containerOf(t.element(graph));
      container
          .read(rendererSettingsProvider('out').notifier)
          .stage('output.name', 'Pending');
      await t.tap(find.text('Enable PEQ'));
      await t.pumpAndSettle();
      expect(api.writes.single, {'dsp.enabled': 'false'});
      expect(find.text('DSP bypassed'), findsOneWidget);
      final bypass = find.text('Bypass DSP');
      expect(
        t.getTopRight(bypass).dx,
        greaterThan(t.getTopRight(graph).dx - 150),
      );
      expect(t.getBottomLeft(bypass).dy, lessThan(t.getTopLeft(graph).dy));
      await t.tap(bypass);
      await t.pumpAndSettle();
      expect(api.writes.last, {'dsp.bypass': 'false'});
      expect(find.text('PEQ is off'), findsOneWidget);
      await t.tap(find.text('Enable PEQ'));
      await t.pumpAndSettle();
      expect(api.writes.last, {'dsp.enabled': 'true'});
      expect(
        t.widget<ResponseGraph>(graph).responseColor,
        KalinkaColors.accent,
      );
      expect(container.read(rendererSettingsProvider('out')).staged, {
        'output.name': 'Pending',
      });
      expect(find.text('Active with PEQ'), findsOneWidget);
      final manual = find.widgetWithText(FilterPill, 'Manual');
      final automatic = find.widgetWithText(FilterPill, 'Automatic');
      expect(t.widget<FilterPill>(automatic).selected, isTrue);
      expect(t.widget<FilterPill>(manual).selected, isFalse);
      final before = api.writes.length;
      await t.tap(automatic);
      await t.pumpAndSettle();
      expect(api.writes, hasLength(before));
      await t.tap(manual);
      await t.pumpAndSettle();
      expect(api.writes.last, {'dsp.preamp': 'manual'});
      expect(t.widget<FilterPill>(manual).selected, isTrue);
      expect(t.widget<FilterPill>(automatic).selected, isFalse);
      for (final chip in [automatic, manual]) {
        expect(
          find.descendant(of: chip, matching: find.byType(Icon)),
          findsNothing,
        );
      }
      await t.tap(find.text('Preamp gain'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '-3.5');
      await t.tap(find.text('Set'));
      await t.pumpAndSettle();
      expect(api.writes.last, {'dsp.preamp_db': '-3.5'});
      await t.tap(automatic);
      await t.pumpAndSettle();
      expect(api.writes.last, {'dsp.preamp': 'auto'});
      expect(find.text('Preamp gain'), findsNothing);
      final caption = t.widget<Text>(find.textContaining('automatically'));
      expect(caption.style, KalinkaTextStyles.trayRowSublabel);
      expect(
        caption.style!.fontSize,
        lessThan(t.widget<Text>(find.text('Automatic')).style!.fontSize!),
      );
      await t.tap(manual);
      await t.pumpAndSettle();
      expect(api.writes.last, {'dsp.preamp': 'manual'});
      expect(find.text('-3.5 dB'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('eq-band-1')).hitTestable(),
        findsOneWidget,
      );
      expect(
        t.widget<ResponseGraph>(graph).bands,
        same(api.curve.channels.values.first),
      );
      expect(api.edits, isEmpty);
      api.reject = true;
      await t.tap(find.text('Enable PEQ'));
      await t.pumpAndSettle();
      expect(find.text('Output offline'), findsOneWidget);
      expect(find.text('Active with PEQ'), findsOneWidget);
    },
  );

  testWidgets('saving a PEQ setting leaves the workspace in place', (t) async {
    final api = _Api(sample());
    await open(t, api, const Size(1024, 900));
    final graph = find.byType(ResponseGraph);
    final manual = find.widgetWithText(FilterPill, 'Manual');
    final preset = find.text('EQ preset');
    final peq = find.text('Enable PEQ');
    final indicator = find.byType(LinearProgressIndicator);
    List<Rect> bounds() => [
      for (final f in [graph, manual, peq, preset]) t.getRect(f),
    ];
    final initial = bounds();
    expect(indicator, findsNothing);
    for (final toggle in [peq, find.text('Bypass DSP'), manual]) {
      final pending = api.pendingWrite = Completer<void>();
      await t.tap(toggle);
      await t.pump();
      expect(indicator, findsOneWidget);
      expect(t.getSize(indicator).height, 1);
      expect(bounds(), initial);
      pending.complete();
      await t.pumpAndSettle();
      expect(indicator, findsNothing);
      expect(bounds(), initial);
    }
    expect(api.writes, [
      {'dsp.enabled': 'false'},
      {'dsp.bypass': 'false'},
      {'dsp.preamp': 'manual'},
    ]);
    expect(t.widget<FilterPill>(manual).selected, isTrue);
    expect(find.text('PEQ is off'), findsOneWidget);
  });

  testWidgets(
    'phone puts Add band after the chips and stacks the sliders in the editor',
    (t) async {
      final api = _Api(sample());
      await open(t, api, const Size(375, 812));
      expect(find.byType(ResponseGraph).hitTestable(), findsOneWidget);
      expect(
        t.getTopLeft(find.byTooltip('Add band')).dy,
        greaterThan(t.getBottomLeft(find.byType(ResponseGraph)).dy),
      );
      final frequencySlider = find.byKey(const ValueKey('eq-slider-Frequency'));
      final gainSlider = find.byKey(const ValueKey('eq-slider-Gain'));
      final qSlider = find.byKey(const ValueKey('eq-slider-Q'));
      expect(
        t.getTopLeft(gainSlider).dy,
        greaterThan(t.getBottomLeft(frequencySlider).dy),
      );
      expect(
        t.getTopLeft(qSlider).dy,
        greaterThan(t.getBottomLeft(gainSlider).dy),
      );
      expect(t.getTopLeft(frequencySlider).dx, t.getTopLeft(qSlider).dx);
      expect(
        t.getTopLeft(find.text('Enable PEQ')).dx,
        greaterThan(t.getTopLeft(find.text('Filter response')).dx),
      );
      expect(find.text('Add band'), findsNothing);
      await screenshot(t, 'room-eq-phone');
      await t.ensureVisible(find.byTooltip('Add band'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Add band'));
      await t.pumpAndSettle();
      expect(api.edits, isEmpty);
      await t.tap(
        find.widgetWithText(PopupMenuItem<FilterShape>, 'High shelf'),
      );
      await t.pumpAndSettle();
      final graph = t.widget<ResponseGraph>(find.byType(ResponseGraph));
      expect(graph.selected, 2);
      expect(graph.bands.last.shape, FilterShape.highShelf);
      expect(api.edits, hasLength(1));
      expect(find.byTooltip('Remove band 3').hitTestable(), findsOneWidget);
      expect(find.text('Enable PEQ').hitTestable(), findsNothing);
      await t.tap(find.text('Frequency').hitTestable());
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '3200');
      await t.tap(find.text('Set'));
      await t.pumpAndSettle();
      expect(api.edits, hasLength(2));
      expect(api.edits.last['shared'], contains('ON HSQ Fc 3200.0'));
      expect(api.writes, isEmpty);
      await screenshot(t, 'room-eq-phone-band');
      expect(api.published, isNull);
      await t.ensureVisible(find.text('Save preset'));
      await t.tap(find.text('Save preset'));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.save_outlined), findsOneWidget);
      final nameField = find.byType(TextField);
      final save = find.widgetWithText(KalinkaButton, 'Save');
      final decoration = t.widget<TextField>(nameField).decoration!;
      expect(decoration.fillColor, KalinkaColors.surfaceElevated);
      expect(decoration.focusedBorder, isA<OutlineInputBorder>());
      await t.enterText(nameField, '   ');
      await t.pump();
      expect(t.widget<KalinkaButton>(save).enabled, isFalse);
      expect(find.text('Enter a preset name.'), findsOneWidget);
      await t.enterText(nameField, 'My room');
      await t.pump();
      expect(find.text('Preset name'), findsOneWidget);
      expect(find.text('Enter a preset name.'), findsNothing);
      expect(t.widget<KalinkaButton>(save).enabled, isTrue);
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(api.published?['shared'], contains('ON HSQ Fc 3200.0'));
      expect(api.writes.single, {'dsp.profile': 'saved'});
      expect(find.text('My room'), findsOneWidget);
    },
  );

  testWidgets(
    'desktop Add band highlights on hover and outlines keyboard focus',
    (t) async {
      await open(t, _Api(sample()), const Size(1024, 900));
      final add = find.byType(PopupMenuButton<FilterShape>);
      final ring = focusOutlineIn(add, KalinkaColors.textPrimary);
      final face = find.descendant(of: add, matching: find.byType(Material));
      final bounds = t.getRect(face);
      expect(bounds.size, const Size.square(48));
      expect(t.widget<Material>(face).color, Colors.transparent);
      expect(ring, findsNothing);

      final mouse = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
      await mouse.addPointer(location: bounds.center);
      await t.pumpAndSettle();
      final ink = t.widget<InkWell>(
        find.descendant(of: add, matching: find.byType(InkWell)),
      );
      expect(ink.statesController!.value, contains(WidgetState.hovered));
      expect(
        ink.overlayColor!.resolve({WidgetState.hovered})?.a,
        greaterThan(0),
      );
      expect(ring, findsNothing);
      await mouse.removePointer();
      expect(await tabTo(t, add), isTrue);
      await t.pumpAndSettle();
      expect(t.getRect(ring), bounds);
      expect(
        ink.overlayColor!.resolve({WidgetState.focused})?.a,
        greaterThan(0),
      );
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(
        find.byType(PopupMenuItem<FilterShape>),
        findsNWidgets(FilterShape.values.length),
      );
    },
  );

  testWidgets('short desktops collapse band cards and retain the selection', (
    t,
  ) async {
    final api = _Api(sample())..values['dsp.bypass'] = 'false';
    await open(t, api, const Size(1200, 960));
    final band = find.byKey(const ValueKey('eq-band-2'));
    final shape = find.descendant(
      of: band,
      matching: find.byType(FilterShapeIcon),
    );
    expect(shape, findsOneWidget);
    final tall = t.getSize(band).height;
    await t.tap(band);
    await t.pumpAndSettle();
    t.view.physicalSize = const Size(1200, 600);
    await t.pumpAndSettle();
    expect(t.getSize(band).height, lessThan(tall));
    expect(
      find.descendant(of: band, matching: find.text('7 kHz')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: band, matching: find.text('+2 dB')),
      findsOneWidget,
    );
    expect(shape, findsNothing);
    expect(t.widget<ResponseGraph>(find.byType(ResponseGraph)).selected, 1);
    await screenshot(t, 'room-eq-short');
    t.view.physicalSize = const Size(1200, 960);
    await t.pumpAndSettle();
    expect(shape, findsOneWidget);
    expect(t.getSize(band).height, tall);
    await screenshot(t, 'room-eq-wide');
  });

  testWidgets('band shape icons follow the menu, type selector and card', (
    t,
  ) async {
    await open(t, _Api(sample()), const Size(1024, 900));
    Finder icon(FilterShape shape) =>
        find.byWidgetPredicate((w) => w is FilterShapeIcon && w.shape == shape);
    final card = find.byKey(const ValueKey('eq-band-1'));
    expect(
      find.descendant(of: card, matching: icon(FilterShape.peak)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('Peak')),
      findsNothing,
    );
    await t.tap(find.byTooltip('Add band'));
    await t.pumpAndSettle();
    for (final shape in FilterShape.values) {
      final item = find.widgetWithText(PopupMenuItem<FilterShape>, shape.label);
      expect(find.descendant(of: item, matching: icon(shape)), findsOneWidget);
    }
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    final selector = find.byType(DropdownButton<FilterShape>);
    await t.ensureVisible(selector);
    await t.tap(selector);
    await t.pumpAndSettle();
    for (final shape in FilterShape.values) {
      final option = find
          .widgetWithText(DropdownMenuItem<FilterShape>, shape.label)
          .last;
      expect(
        find.descendant(of: option, matching: icon(shape)),
        findsOneWidget,
      );
    }
    await t.tap(find.text('Low shelf').hitTestable().last);
    await t.pumpAndSettle();
    expect(
      find.descendant(of: card, matching: icon(FilterShape.lowShelf)),
      findsOneWidget,
    );
  });

  testWidgets(
    'Escape and outside clicks dismiss Add band without changing playback',
    (t) async {
      final api = _Api(sample());
      await open(t, api, const Size(1024, 768));
      await t.tap(find.byTooltip('Add band'));
      await t.pumpAndSettle();
      expect(
        find.byType(PopupMenuItem<FilterShape>),
        findsNWidgets(FilterShape.values.length),
      );
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.byType(PopupMenuItem<FilterShape>), findsNothing);
      expect(find.byType(ResponseGraph), findsOneWidget);
      await t.tap(find.byTooltip('Add band'));
      await t.pumpAndSettle();
      await t.tapAt(t.getCenter(find.text('Enable PEQ')));
      await t.pumpAndSettle();
      expect(find.byType(PopupMenuItem<FilterShape>), findsNothing);
      expect(api.writes, isEmpty);
      expect(api.edits, isEmpty);
    },
  );

  testWidgets(
    'band rows, graph points and fine adjustments edit the same band',
    (t) async {
      final api = _Api(sample());
      await open(t, api, const Size(1080, 840));
      final graph = find.byType(ResponseGraph);
      await t.tap(find.byKey(const ValueKey('eq-band-2')));
      await t.pumpAndSettle();
      expect(t.widget<ResponseGraph>(graph).selected, 1);
      expect(api.edits, isEmpty);
      final gainSlider = find.byKey(const ValueKey('eq-slider-Gain'));
      await t.ensureVisible(gainSlider);
      await t.pumpAndSettle();
      final rect = t.getRect(gainSlider);
      final drag = await t.startGesture(rect.center);
      await drag.moveTo(rect.centerRight - const Offset(22, 0));
      await t.pump();
      expect(t.widget<ResponseGraph>(graph).bands[1].gain, greaterThan(2));
      expect(api.edits, isEmpty);
      await drag.up();
      await t.pumpAndSettle();
      expect(api.edits.single['shared'], contains('HSQ Fc 7000.0'));
      expect(t.widget<ResponseGraph>(graph).bands.first.gain, -4);
      final qSlider = find.byKey(const ValueKey('eq-slider-Q'));
      expect(
        t.getTopLeft(qSlider).dx,
        greaterThan(t.getTopLeft(gainSlider).dx),
      );
      await t.tap(qSlider);
      await t.pumpAndSettle();
      expect(t.widget<ResponseGraph>(graph).bands[1].q, closeTo(1.41, .01));
      expect(api.edits, hasLength(2));
      final selector = find.byType(DropdownButton<FilterShape>);
      await t.ensureVisible(selector);
      await t.tap(selector);
      await t.pumpAndSettle();
      await t.tap(find.text('Low shelf').hitTestable().last);
      await t.pumpAndSettle();
      expect(
        t.widget<ResponseGraph>(graph).bands[1].shape,
        FilterShape.lowShelf,
      );
      expect(api.published, isNull);
    },
  );

  testWidgets(
    'cancelling a slider drag restores the curve without a renderer edit',
    (t) async {
      final api = _Api(sample());
      await open(t, api, const Size(1024, 900));
      final slider = find.byKey(const ValueKey('eq-slider-Gain'));
      await t.ensureVisible(slider);
      final rect = t.getRect(slider);
      final finger = await t.startGesture(rect.center);
      await finger.moveTo(rect.centerRight - const Offset(18, 0));
      await t.pump();
      final graph = find.byType(ResponseGraph);
      expect(t.widget<ResponseGraph>(graph).bands.first.gain, greaterThan(0));
      await finger.cancel();
      await t.pumpAndSettle();
      expect(api.edits, isEmpty);
      expect(t.widget<ResponseGraph>(graph).bands.first.gain, -4);
    },
  );

  testWidgets(
    'sliders retain the full range of imported bands and precise entry',
    (t) async {
      final api = _Api(
        EqCurve('Extended', {
          EqChannel.shared: [const EqBand(hz: 30000, gain: -2, q: 45)],
        }),
      );
      await open(t, api, const Size(1100, 900));
      final frequency = find.byKey(const ValueKey('eq-slider-Frequency'));
      final quality = find.byKey(const ValueKey('eq-slider-Q'));
      expect(t.widget<Slider>(frequency).value, 1);
      expect(t.widget<Slider>(quality).value, 1);
      expect(find.textContaining('at or above 24 kHz'), findsOneWidget);
      await t.ensureVisible(frequency);
      final rect = t.getRect(frequency);
      final finger = await t.startGesture(rect.center);
      await finger.moveTo(rect.centerLeft);
      await t.pump();
      await finger.up();
      await t.pumpAndSettle();
      final bands = t.widget<ResponseGraph>(find.byType(ResponseGraph)).bands;
      expect(bands.single.hz, 20);
      expect(bands.single.q, 45);
      expect(api.edits, hasLength(1));
    },
  );

  testWidgets(
    'graph selection reveals its horizontal card without moving the graph',
    (t) async {
      final api = _Api(
        EqCurve('Long strip', {
          EqChannel.shared: List.generate(
            12,
            (i) => EqBand(hz: 30 * math.pow(1.7, i).toDouble(), gain: 1),
          ),
        }),
      );
      await open(t, api, const Size(1024, 900));
      final graph = find.byType(ResponseGraph);
      final graphRect = t.getRect(graph);
      final last = find.byKey(const ValueKey('eq-band-12'));
      expect(last.hitTestable(), findsNothing);
      final plus = find.byTooltip('Add band');
      final first = find.byKey(const ValueKey('eq-band-1'));
      expect(t.getCenter(plus).dy, closeTo(t.getCenter(first).dy, 1));
      t.widget<ResponseGraph>(graph).onSelect(11);
      await t.pumpAndSettle();
      expect(last.hitTestable(), findsOneWidget);
      expect(find.byTooltip('Remove band 12'), findsOneWidget);
      expect(t.getRect(graph), graphRect);
      expect(api.edits, isEmpty);
    },
  );

  testWidgets(
    'double-tapping empty graph space adds one peak at that frequency and gain',
    (t) async {
      final api = _Api(EqCurve.empty());
      await open(t, api, const Size(1024, 768));
      final graph = find.byType(ResponseGraph);
      final rect = t.getRect(graph);
      final point =
          rect.topLeft +
          Offset(38 + (rect.width - 53) * 2 / 3, 18 + (rect.height - 48) * .25);
      await t.tapAt(point);
      await t.pump(const Duration(milliseconds: 60));
      await t.tapAt(point);
      await t.pumpAndSettle();
      final band = t.widget<ResponseGraph>(graph).bands.single;
      expect(band.hz, 2000);
      expect(band.gain, 2);
      expect(band.shape, FilterShape.peak);
      expect(api.edits, hasLength(1));
      expect(find.byTooltip('Remove band 1'), findsOneWidget);
    },
  );

  testWidgets('band limit disables both ways to add while preserving editing', (
    t,
  ) async {
    final api = _Api(
      EqCurve('Full', {EqChannel.shared: List.filled(20, const EqBand())}),
    );
    await open(t, api, const Size(1024, 768));
    final add = t.widget<PopupMenuButton<FilterShape>>(
      find.byType(PopupMenuButton<FilterShape>),
    );
    expect(add.enabled, isFalse);
    expect(t.widget<ResponseGraph>(find.byType(ResponseGraph)).onAdd, isNull);
    await t.tap(find.byTooltip('Remove band 1'));
    await t.pumpAndSettle();
    expect(
      t.widget<ResponseGraph>(find.byType(ResponseGraph)).onAdd,
      isNotNull,
    );
    expect(api.edits, hasLength(1));
  });

  testWidgets(
    'large text on a short viewport can reach the preset and import controls',
    (t) async {
      final api = _Api(sample());
      await open(t, api, const Size(812, 375), scale: 2);
      await t.scrollUntilVisible(
        find.text('Import REW'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.text('Import REW'));
      await t.pumpAndSettle();
      expect(find.text('Both channels'), findsOneWidget);
      final switcher = find.text('Separate channel files');
      await t.ensureVisible(switcher);
      await t.pumpAndSettle();
      await t.tap(switcher);
      await t.pumpAndSettle();
      expect(find.text('Left channel'), findsOneWidget);
      expect(find.text('Right channel'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'releasing the dot applies one edit and preserves the other channel and bypass',
    (t) async {
      final api = _Api(
        EqCurve('Two channels', {
          EqChannel.left: [const EqBand(hz: 1000, gain: 0)],
          EqChannel.right: [const EqBand(hz: 100, gain: -2)],
        }),
      );
      await open(t, api, const Size(768, 1024));
      final graph = find.byType(ResponseGraph);
      final rect = t.getRect(graph);
      final handle =
          rect.topLeft +
          Offset(
            38 + (rect.width - 53) * math.log(1000 / 20) / math.log(1000),
            18 + (rect.height - 48) / 2,
          );
      final finger = await t.startGesture(handle);
      await finger.moveBy(const Offset(32, -20));
      await t.pump();
      await finger.moveBy(const Offset(40, -20));
      await t.pump();
      expect(api.edits, isEmpty);
      await finger.up();
      await t.pumpAndSettle();
      expect(t.widget<ResponseGraph>(graph).bands.first.hz, greaterThan(1000));
      expect(t.widget<ResponseGraph>(graph).bands.first.gain, greaterThan(0));
      await t.tap(find.text('Right channel'));
      await t.pumpAndSettle();
      expect(t.widget<ResponseGraph>(graph).bands.first.hz, 100);
      expect(api.edits.single['right'], contains('100.0 Hz Gain -2.0'));
      expect(api.edits.single['left'], isNot(contains('1000.0 Hz Gain 0.0')));
      expect(api.published, isNull);
      expect(api.values['dsp.bypass'], 'true');
      expect(api.writes, isEmpty);
    },
  );

  testWidgets('a refused edit can be retried without adding a preset', (
    t,
  ) async {
    final api = _Api(sample())..reject = true;
    await open(t, api, const Size(1024, 768));
    await t.tap(find.byTooltip('Add band'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(PopupMenuItem<FilterShape>, 'Peak'));
    await t.pumpAndSettle();
    expect(find.text('Output offline'), findsOneWidget);
    expect(api.values['dsp.profile'], 'original');
    api.reject = false;
    await t.tap(find.text('Retry'));
    await t.pumpAndSettle();
    expect(api.edits, hasLength(2));
    expect(api.edits.first, api.edits.last);
    expect(api.values['dsp.profile'], 'working');
    expect(api.published, isNull);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.byType(ResponseGraph), findsNothing);
    expect(find.text('Room EQ'), findsOneWidget);
  });

  testWidgets(
    'choosing None clears the renderer and opens a flat editable curve',
    (t) async {
      final api = _Api(sample());
      await open(t, api, const Size(390, 844));
      await t.ensureVisible(find.text('EQ preset'));
      await t.tap(find.text('EQ preset'));
      await t.pumpAndSettle();
      await t.tap(find.text('None'));
      await t.pumpAndSettle();
      expect(api.writes, [
        {'dsp.profile': 'none'},
      ]);
      expect(
        t.widget<ResponseGraph>(find.byType(ResponseGraph)).bands,
        isEmpty,
      );
    },
  );

  testWidgets('removing the last filter can apply a flat response', (t) async {
    final api = _Api(
      EqCurve('One band', {
        EqChannel.shared: [const EqBand()],
      }),
    );
    await open(t, api, const Size(1024, 768));
    await t.tap(find.byTooltip('Remove band 1'));
    await t.pumpAndSettle();

    expect(api.published, isNull);
    expect(api.writes.single, {'dsp.profile': 'none'});
  });

  testWidgets(
    'shows the renderer FIR channels and preview rate independently of PEQ',
    (t) async {
      final events = StreamController<PlayQueueEvent>();
      addTearDown(events.close);
      final api = _Api(EqCurve.empty())
        ..firImport = true
        ..response = {
          'sample_rate': 96000,
          'source_rate': 48000,
          'left_db': [0, -9, 0],
          'right_db': [-3, -4, -3],
        };
      api.values.addAll({
        RendererConfigField.rewFirProfile: 'test.wav',
        'dsp.enabled': 'false',
        'dsp.bypass': 'false',
      });
      await open(t, api, const Size(1024, 768), events: events.stream);
      ResponseGraph graph() =>
          t.widget<ResponseGraph>(find.byType(ResponseGraph));
      expect(graph().fir.map((trace) => trace.db), [
        [0, -9, 0],
        [-3, -4, -3],
      ]);
      expect(find.text('FIR L'), findsOneWidget);
      expect(find.text('FIR R'), findsOneWidget);
      expect(find.text('Preview · 96 kHz'), findsOneWidget);
      expect(find.text('PEQ (off)'), findsOneWidget);
      api.response!['sample_rate'] = 44100;
      events.add(
        const PlayQueueEvent.currentRendererChanged(rendererId: 'out', seq: 1),
      );
      events.add(
        PlayQueueEvent.playbackStateChanged(
          seq: 2,
          state: PlaybackState(
            audioInfo: AudioInfo(
              output: const OutputInfo(
                sampleFormat: 'S32_LE',
                sampleRate: 44100,
                channels: 2,
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Preview · 44.1 kHz'), findsOneWidget);
      await t.tap(find.text('Bypass DSP'));
      await t.pumpAndSettle();
      expect(find.text('FIR L (bypassed)'), findsOneWidget);
      api.response!.remove('right_db');
      final notifier = ProviderScope.containerOf(
        t.element(find.byType(ResponseGraph)),
      ).read(rendererSettingsProvider('out').notifier);
      await notifier.load();
      await t.pumpAndSettle();
      expect(find.text('FIR (bypassed)'), findsOneWidget);
      api.values[RendererConfigField.rewFirProfile] = 'off';
      await notifier.load();
      await t.pumpAndSettle();
      expect(graph().fir, isEmpty);
    },
  );

  testWidgets('imports two impulse WAVs as one named FIR selection', (t) async {
    final dir = Directory.systemTemp.createTempSync('kalinka-fir-import-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final files = [
      File('${dir.path}/studio48.wav')..writeAsBytesSync([1, 2]),
      File('${dir.path}/studio192.wav')..writeAsBytesSync([3, 4]),
    ];
    mockFilePicker(files, multiple: true);
    final api = _Api(sample())..firImport = true;
    await open(t, api, const Size(1420, 950));
    await t.ensureVisible(find.text('Import impulse WAV'));
    await t.tap(find.text('Import impulse WAV'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 350));
    expect(find.textContaining('studio192.wav'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'Studio');
    await t.runAsync(() async {
      await t.tap(find.widgetWithText(KalinkaButton, 'Import'));
      for (var i = 0; i < 100 && api.writes.isEmpty; ++i) {
        await t.pump();
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    await t.pumpAndSettle();
    expect(api.importedImpulse?.name, 'Studio');
    expect(api.importedImpulse?.impulseWav, [
      [1, 2],
      [3, 4],
    ]);
    expect(api.writes.single, {RendererConfigField.rewFirProfile: 'fir-id'});
  });

  testWidgets(
    'phone REW import preserves the draft and identifies a bad file',
    (t) async {
      final dir = Directory.systemTemp.createTempSync('kalinka-rew-phone-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const preset = 'Filter 1: ON PK Fc 100 Hz Gain -2 dB Q 1';
      mockFilePicker([
        File('${dir.path}/empty.txt')..writeAsStringSync(''),
        File('${dir.path}/room.txt')..writeAsStringSync(preset),
      ]);
      final api = _Api(sample());
      await open(t, api, const Size(375, 812));
      await t.ensureVisible(find.text('Import REW'));
      await t.tap(find.text('Import REW'));
      await t.pumpAndSettle();
      final import = find.widgetWithText(KalinkaButton, 'Import');
      expect(t.widget<KalinkaButton>(import).enabled, isFalse);
      await screenshot(t, 'room-eq-import-phone');
      await chooseFile(
        t,
        'Both channels',
        'This file is empty. Choose a REW text export.',
      );
      expect(t.widget<KalinkaButton>(import).enabled, isFalse);
      await chooseFile(t, 'Both channels', 'room.txt');
      final field = find.byType(TextField);
      expect(t.widget<TextField>(field).controller!.text, 'room');
      expect(find.textContaining('This file is empty'), findsNothing);
      await t.enterText(field, ' ');
      await t.pumpAndSettle();
      expect(find.text('Enter a preset name.'), findsOneWidget);
      expect(t.widget<KalinkaButton>(import).enabled, isFalse);
      await t.enterText(field, 'My speakers');
      final mode = find.text('Separate channel files');
      await t.ensureVisible(mode);
      await t.tap(mode);
      await t.pumpAndSettle();
      expect(t.widget<KalinkaButton>(import).enabled, isFalse);
      await t.tap(mode);
      await t.pumpAndSettle();
      expect(find.text('room.txt'), findsOneWidget);
      expect(t.widget<TextField>(field).controller!.text, 'My speakers');
      expect(t.widget<KalinkaButton>(import).enabled, isTrue);
      await t.ensureVisible(import);
      await t.tap(import);
      await t.pumpAndSettle();
      expect(api.published, {'name': 'My speakers', 'shared': preset});
    },
  );

  testWidgets(
    'imports both REW channel files and selects the published preset',
    (t) async {
      final dir = Directory.systemTemp.createTempSync('kalinka-rew-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final files = [
        for (final (channel, hz) in [('Left', 125), ('Right', 250)])
          File('${dir.path}/$channel.txt')
            ..writeAsStringSync('Filter 1: ON PK Fc $hz Hz Gain -3 dB Q 1'),
      ];
      mockFilePicker(files);
      final api = _Api(sample());
      await open(t, api, const Size(1024, 768));
      await t.ensureVisible(find.text('Import REW'));
      await t.tap(find.text('Import REW'));
      await t.pumpAndSettle();
      await t.tap(find.text('Separate channel files'));
      await t.pumpAndSettle();
      final import = find.widgetWithText(KalinkaButton, 'Import');
      await chooseFile(t, 'Left channel', 'Left.txt');
      expect(t.widget<KalinkaButton>(import).enabled, isFalse);
      await chooseFile(t, 'Right channel', 'Right.txt');
      expect(t.widget<KalinkaButton>(import).enabled, isTrue);
      await t.enterText(find.byType(TextField), 'Stereo import');
      await t.pumpAndSettle();
      await screenshot(t, 'room-eq-import-stereo');
      await t.tap(find.text('Import'));
      await t.pumpAndSettle();
      expect(api.published, {
        'name': 'Stereo import',
        'left': files.first.readAsStringSync(),
        'right': files.last.readAsStringSync(),
      });
      expect(api.writes.single, {'dsp.profile': 'saved'});
    },
  );
}
