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
import 'package:kalinka/data_model/room_eq.dart';
import 'package:kalinka/generated/kalinka/renderer/v1/renderer.pb.dart' as wire;
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/renderer_settings_provider.dart';
import 'package:kalinka/screens/renderer_settings_screen.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/room_eq/response_graph.dart';

class _Online extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

class _Api implements KalinkaPlayerProxy {
  _Api(this.curve);
  EqCurve curve;
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
  bool reject = false;
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
  }) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = size;
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
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
                disableAnimations: true,
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
    await t.tap(find.text('Room EQ'));
    await t.pumpAndSettle();
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
      for (final shape in FilterShape.values) {
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
    'tablet separates stages, graph and presets; changes target only EQ',
    (t) async {
      final api = _Api(
        profile == null
            ? sample()
            : EqCurve.fromBytes(File(profile).readAsBytesSync()),
      );
      await open(t, api, const Size(1024, 768));
      final graph = find.byType(ResponseGraph);
      expect(
        t.getTopLeft(graph).dx,
        greaterThan(t.getTopRight(find.text('Signal stages'.toUpperCase())).dx),
      );
      expect(
        t.getTopLeft(find.text('ROOM PRESET')).dy,
        greaterThan(t.getBottomLeft(graph).dy),
      );
      await screenshot(t, 'room-eq-tablet');
      final container = ProviderScope.containerOf(t.element(graph));
      container
          .read(rendererSettingsProvider('out').notifier)
          .stage('output.name', 'Pending');
      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      expect(api.writes.single, {'dsp.enabled': 'true', 'dsp.bypass': 'false'});
      expect(container.read(rendererSettingsProvider('out')).staged, {
        'output.name': 'Pending',
      });
      await t.tap(find.text('Preamp').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Manual'));
      await t.pumpAndSettle();
      expect(api.writes.last, {'dsp.preamp': 'manual'});
      await t.tap(find.text('Manual preamp'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '-3.5');
      await t.tap(find.text('Set'));
      await t.pumpAndSettle();
      expect(api.writes.last, {'dsp.preamp_db': '-3.5'});
      api.reject = true;
      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      expect(find.text('Output offline'), findsOneWidget);
      expect(t.widget<Switch>(find.byType(Switch)).value, isTrue);
    },
  );

  testWidgets(
    'phone graph is a separate page that shares filter edits and saves a new preset',
    (t) async {
      final api = _Api(
        profile == null
            ? sample()
            : EqCurve.fromBytes(File(profile).readAsBytesSync()),
      );
      await open(t, api, const Size(375, 812));
      expect(find.byType(ResponseGraph), findsNothing);
      await screenshot(t, 'room-eq-phone');
      await t.tap(find.text('Open frequency response'));
      await t.pumpAndSettle();
      expect(find.byType(ResponseGraph), findsOneWidget);
      await screenshot(t, 'room-eq-phone-graph');
      await t.tap(find.text('Add band'));
      await t.pumpAndSettle();
      await t.tap(find.text('High shelf'));
      await t.pumpAndSettle();
      final graph = t.widget<ResponseGraph>(find.byType(ResponseGraph));
      expect(graph.bands.last.shape, FilterShape.highShelf);
      expect(api.writes, isEmpty);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.byType(ResponseGraph), findsNothing);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('Discard filter edits?'), findsOneWidget);
      await t.tap(find.text('Keep editing'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Save preset'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'My room');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(api.published?['shared'], contains('ON HSQ Fc 1000.0'));
      expect(api.writes.single, {'dsp.profile': 'saved'});
      expect(find.text('My room'), findsOneWidget);
    },
  );

  testWidgets(
    'large text on a short viewport can reach the preset and import controls',
    (t) async {
      final api = _Api(sample());
      await open(t, api, const Size(812, 375), scale: 2);
      await t.scrollUntilVisible(
        find.byTooltip('Import REW'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.byTooltip('Import REW'));
      await t.pumpAndSettle();
      expect(find.text('Choose REW file'), findsOneWidget);
      final switcher = find.text('Separate left and right files');
      await t.ensureVisible(switcher);
      await t.pumpAndSettle();
      await t.tap(switcher);
      await t.pumpAndSettle();
      expect(find.text('Choose left file'), findsOneWidget);
      expect(find.text('Choose right file'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'drag a band to adjust its frequency and gain without publishing',
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
      await finger.up();
      await t.pumpAndSettle();
      expect(t.widget<ResponseGraph>(graph).bands.first.hz, greaterThan(1000));
      expect(t.widget<ResponseGraph>(graph).bands.first.gain, greaterThan(0));
      await t.tap(find.text('Right channel'));
      await t.pumpAndSettle();
      expect(t.widget<ResponseGraph>(graph).bands.first.hz, 100);
      expect(api.writes, isEmpty);
    },
  );

  testWidgets(
    'choosing None clears the renderer and opens a flat editable curve',
    (t) async {
      final api = _Api(sample());
      await open(t, api, const Size(390, 844));
      await t.tap(find.text('ROOM PRESET'));
      await t.pumpAndSettle();
      await t.tap(find.text('None'));
      await t.pumpAndSettle();
      expect(api.writes, [
        {'dsp.profile': 'none'},
      ]);
      await t.tap(find.text('Open frequency response'));
      await t.pumpAndSettle();
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
    await t.tap(find.text('Use flat EQ'));
    await t.pumpAndSettle();
    expect(api.published, isNull);
    expect(api.writes.single, {'dsp.profile': 'none'});
  });

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
      var next = 0;
      const channel = MethodChannel('plugins.flutter.io/file_selector');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => [files[next++].path],
      );
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final api = _Api(sample());
      await open(t, api, const Size(1024, 768));
      await t.tap(find.text('Import REW'));
      await t.pumpAndSettle();
      await t.tap(find.text('Separate left and right files'));
      await t.pumpAndSettle();
      for (final side in ['left', 'right']) {
        await t.tap(find.text('Choose $side file'));
        await t.pumpAndSettle();
      }
      await t.enterText(find.byType(TextField), 'Stereo import');
      await t.runAsync(() async {
        await t.tap(find.text('Import'));
        // File reads run on the platform I/O loop.
        await t.idle();
        for (var i = 0; i < 100 && api.published == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          await t.pump();
        }
      });
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
