import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart' show RendererInfo;
import 'package:kalinka/data_model/renderer_config.dart';
import 'package:kalinka/providers/box_control_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/demo_mode.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/soundcard_provider.dart';
import 'package:kalinka/providers/supervisor_api.dart';
import 'package:kalinka/providers/toast_provider.dart';
import 'package:kalinka/widgets/box_section.dart';
import 'package:kalinka/widgets/soundcard_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _options = [
  SoundcardOption(
    name: 'hifiberry-digi-pro',
    label: 'HiFiBerry Digi+ Pro or Digi2 Pro',
    vendor: 'HiFiBerry',
    kind: 'digital',
  ),
  SoundcardOption(
    name: 'justboom-dac',
    label: 'JustBoom DAC HAT',
    vendor: 'JustBoom',
    kind: 'dac',
  ),
  SoundcardOption(
    name: 'rpi-bcm2835-hdmi',
    label: 'Raspberry Pi HDMI',
    vendor: 'Raspberry Pi',
    kind: 'onboard',
  ),
  SoundcardOption(name: 'none', label: 'No HAT', kind: 'none'),
];

SoundcardReport _report({
  String? name,
  String? configured,
  String? pcm,
  List<String> suggested = const [],
}) => SoundcardReport(
  name: name,
  configured: configured,
  activePcm: pcm,
  suggested: suggested,
  options: _options,
);

SupervisorInfo _info({String? serverId = 'box-1', String? rendererId}) =>
    SupervisorInfo(
      version: '0.3.0',
      protocol: 1,
      minProtocol: 1,
      serverId: serverId,
      rendererId: rendererId,
      actions: const {'reboot', 'poweroff', setSoundcardAction},
    );

/// A box that answers [answers] to `/info` in turn, the last one for good, and
/// [reports] to `/v1/soundcard` likewise.
class _Box implements SupervisorApi {
  _Box({
    List<SupervisorInfo?>? answers,
    List<SoundcardReport?>? reports,
    this.restarts = false,
  }) : answers = answers ?? [_info(rendererId: 'r-local')],
       reports = reports ?? [_report()];

  final List<SupervisorInfo?> answers;
  final List<SoundcardReport?> reports;
  final bool restarts;
  BoxActionException? refusal;
  final applied = <(String, BoxIdentity)>[];

  T _next<T>(List<T> list) => list.length > 1 ? list.removeAt(0) : list.first;

  @override
  Future<SupervisorInfo?> info() async => _next(answers);

  @override
  Future<SoundcardReport?> soundcard() async => _next(reports);

  @override
  Future<bool> setSoundcard(String card, BoxIdentity identity) async {
    applied.add((card, identity));
    if (refusal != null) throw refusal!;
    return restarts;
  }

  @override
  Future<String?> serverState() async => 'active';

  @override
  Future<void> run(BoxAction action, {required String serverId}) async {}

  @override
  Uri get page => Uri.parse('http://kalinka.local:8001/');
}

class _Proxy implements KalinkaPlayerProxy {
  _Proxy(this.renderers);

  List<RendererInfo> renderers;
  final updates = <(String, Map<String, String>)>[];

  @override
  Future<List<RendererInfo>> listRenderers() async => renderers;

  @override
  Future<RendererConfigResult> updateRendererConfig(
    String rendererId,
    Map<String, String> changes,
  ) async {
    updates.add((rendererId, changes));
    return const RendererConfigResult();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

RendererInfo _renderer(
  String id, {
  String? address,
  String status = 'connected',
}) => RendererInfo(
  rendererId: id,
  friendlyName: id,
  status: status,
  address: address,
);

Future<ProviderContainer> _container({
  required _Box box,
  _Proxy? proxy,
  Map<String, SupervisorApi> others = const {},
}) async {
  SharedPreferences.setMockInitialValues({
    'Kalinka.host': 'kalinka.local',
    'Kalinka.port': 8000,
  });
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      supervisorApiProvider.overrideWithValue(box),
      supervisorAtProvider.overrideWith((ref, host) => others[host]!),
      serverIdentityProvider.overrideWith((ref) async => 'box-1'),
      demoModeProvider.overrideWithValue(false),
      kalinkaProxyProvider.overrideWithValue(proxy ?? _Proxy([])),
      soundcardPollProvider.overrideWithValue(Duration.zero),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, this.body);

  final int status;
  final Object body;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

(DioSupervisorApi, _Adapter) _api(int status, Object body) {
  final adapter = _Adapter(status, body);
  final dio = Dio(BaseOptions(baseUrl: 'http://192.168.1.30:8001'))
    ..httpClientAdapter = adapter;
  return (DioSupervisorApi(dio), adapter);
}

void main() {
  group('wire types', () {
    test('info names the renderer on the box', () {
      final info = SupervisorInfo.fromJson({
        'name': 'kalinka-supervisor',
        'protocol': 1,
        'min_protocol': 1,
        'server_id': null,
        'renderer_id': 'r-1',
        'actions': ['reboot', 'set_soundcard'],
      })!;
      expect(info.rendererId, 'r-1');
      expect(info.serverId, isNull);
      expect(info.setsSoundcard, isTrue);
    });

    test('a report reads the DAC, the card that came up and the choices', () {
      final report = SoundcardReport.fromJson({
        'supported': true,
        'name': 'HiFiBerry Digi2 Pro',
        'hat': {'vendor': 'HiFiBerry', 'product': 'Digi2 Pro'},
        'configured': 'hifiberry-digi-pro',
        'active': {
          'id': 'sndrpihifiberry',
          'pcm': 'hw:CARD=sndrpihifiberry,DEV=0',
        },
        'suggested': ['hifiberry-digi-pro'],
        'options': [
          {
            'name': 'hifiberry-digi-pro',
            'label': 'HiFiBerry Digi+ Pro',
            'vendor': 'HiFiBerry',
            'kind': 'digital',
          },
          {'name': 5},
        ],
      })!;
      expect(report.name, 'HiFiBerry Digi2 Pro');
      expect(report.activePcm, 'hw:CARD=sndrpihifiberry,DEV=0');
      expect(report.options.single.label, 'HiFiBerry Digi+ Pro');
      expect(report.option('hifiberry-digi-pro')!.kind, 'digital');
    });

    test('a box that is no Pi has no report', () {
      expect(
        SoundcardReport.fromJson({'supported': false, 'options': []}),
        isNull,
      );
      expect(SoundcardReport.fromJson('nonsense'), isNull);
    });

    test('an identity leaves out what the box does not have', () {
      expect(const BoxIdentity(rendererId: 'r-1').toJson(), {
        'renderer_id': 'r-1',
      });
    });
  });

  group('DioSupervisorApi', () {
    test(
      'sets a card up, naming the box, and says whether it restarts',
      () async {
        final (api, adapter) = _api(202, {
          'action': 'set_soundcard',
          'reboot': true,
        });

        final restarts = await api.setSoundcard(
          'hifiberry-digi-pro',
          const BoxIdentity(serverId: 'box-1', rendererId: 'r-1'),
        );

        expect(restarts, isTrue);
        final request = adapter.requests.single;
        expect(request.path, '/v1/actions/set_soundcard');
        expect(request.data, {
          'server_id': 'box-1',
          'renderer_id': 'r-1',
          'soundcard': 'hifiberry-digi-pro',
        });
        expect(
          request.receiveTimeout,
          greaterThan(const Duration(seconds: 90)),
        );
      },
    );

    test('reports a card the box does not offer in words', () async {
      final (api, _) = _api(422, {
        'detail': {'code': 'unknown_soundcard', 'message': 'no'},
      });
      expect(
        () => api.setSoundcard('x', const BoxIdentity(serverId: 'box-1')),
        throwsA(
          isA<BoxActionException>().having(
            (e) => e.message,
            'message',
            'This box cannot be set up for that sound card.',
          ),
        ),
      );
    });

    test('reads the report', () async {
      final (api, adapter) = _api(200, {
        'supported': true,
        'name': null,
        'options': [
          {'name': 'none', 'label': 'No HAT', 'vendor': '', 'kind': 'none'},
        ],
      });
      expect((await api.soundcard())!.options.single.name, 'none');
      expect(adapter.requests.single.path, '/v1/soundcard');
    });
  });

  group('which box', () {
    test(
      'the server’s own box, with the renderer its supervisor names',
      () async {
        final container = await _container(box: _Box());
        final box = (await container.read(serverSoundcardBoxProvider.future))!;
        expect(box.identity, const BoxIdentity(serverId: 'box-1'));
        expect(box.rendererId, 'r-local');
      },
    );

    test('a supervisor that cannot set a card up offers no box', () async {
      final box = _Box(
        answers: [
          const SupervisorInfo(
            version: '0.2.0',
            protocol: 1,
            minProtocol: 1,
            serverId: 'box-1',
            actions: {'reboot'},
          ),
        ],
      );
      final container = await _container(box: box);
      expect(await container.read(serverSoundcardBoxProvider.future), isNull);
    });

    test('the local renderer plays on the server’s box', () async {
      final container = await _container(box: _Box());
      final box = await container.read(
        rendererSoundcardBoxProvider('r-local').future,
      );
      expect(box!.identity.serverId, 'box-1');
    });

    test('a renderer elsewhere plays on the box it connected from', () async {
      final remote = _Box(
        answers: [_info(serverId: null, rendererId: 'r-far')],
      );
      final container = await _container(
        box: _Box(),
        proxy: _Proxy([_renderer('r-far', address: '192.168.1.40')]),
        others: {'192.168.1.40': remote},
      );
      final box = (await container.read(
        rendererSoundcardBoxProvider('r-far').future,
      ))!;
      expect(identical(box.api, remote), isTrue);
      expect(box.identity, const BoxIdentity(rendererId: 'r-far'));
    });

    test(
      'a box at that address that names another renderer is not it',
      () async {
        final container = await _container(
          box: _Box(),
          proxy: _Proxy([_renderer('r-far', address: '192.168.1.40')]),
          others: {
            '192.168.1.40': _Box(answers: [_info(rendererId: 'r-other')]),
          },
        );
        expect(
          await container.read(rendererSoundcardBoxProvider('r-far').future),
          isNull,
        );
      },
    );

    test('a renderer without an address has no box', () async {
      final container = await _container(
        box: _Box(),
        proxy: _Proxy([_renderer('r-far')]),
      );
      expect(
        await container.read(rendererSoundcardBoxProvider('r-far').future),
        isNull,
      );
    });
  });

  group('SoundcardChange', () {
    const card = SoundcardOption(
      name: 'justboom-dac',
      label: 'JustBoom DAC HAT',
      kind: 'dac',
    );

    Future<(ProviderContainer, SoundcardBox, _Proxy)> start(_Box box) async {
      final proxy = _Proxy([_renderer('r-local')]);
      final container = await _container(box: box, proxy: proxy);
      final soundcardBox = SoundcardBox(
        api: box,
        identity: const BoxIdentity(serverId: 'box-1'),
        rendererId: 'r-local',
      );
      return (container, soundcardBox, proxy);
    }

    List<String> toasts(ProviderContainer c) => [
      for (final t in c.read(toastProvider)) t.message,
    ];

    test('a card that needs no restart is reported at once', () async {
      final box = _Box();
      final (container, target, proxy) = await start(box);

      await container
          .read(soundcardChangeProvider(target).notifier)
          .apply(card);

      expect(box.applied.single.$1, 'justboom-dac');
      expect(
        container.read(soundcardChangeProvider(target)),
        SoundcardStep.idle,
      );
      expect(proxy.updates, isEmpty);
      expect(toasts(container).last, contains('Nothing needed a restart'));
    });

    test('follows the restart and plays through the new card', () async {
      final box = _Box(
        restarts: true,
        answers: [_info(), null, null, _info()],
        reports: [
          _report(),
          _report(name: 'JustBoom DAC', pcm: 'hw:CARD=sndrpijustboomd,DEV=0'),
        ],
      );
      final (container, target, proxy) = await start(box);

      await container
          .read(soundcardChangeProvider(target).notifier)
          .apply(card);

      final (renderer, changes) = proxy.updates.single;
      expect(renderer, 'r-local');
      expect(changes, {'output.device': 'hw:CARD=sndrpijustboomd,DEV=0'});
      expect(
        toasts(container).last,
        'The box is back, playing through JustBoom DAC.',
      );
      expect(
        container.read(soundcardChangeProvider(target)),
        SoundcardStep.idle,
      );
    });

    test('a card that does not come up is reported as such', () async {
      final box = _Box(
        restarts: true,
        answers: [null, _info()],
        reports: [_report()],
      );
      final (container, target, proxy) = await start(box);

      await container
          .read(soundcardChangeProvider(target).notifier)
          .apply(card);

      expect(proxy.updates, isEmpty);
      final toast = container.read(toastProvider).last;
      expect(toast.message, contains('did not come up'));
      expect(toast.isError, isTrue);
    });

    test('a box that never comes back is reported as such', () async {
      final box = _Box(restarts: true, answers: [null]);
      final (container, target, _) = await start(box);

      await container
          .read(soundcardChangeProvider(target).notifier)
          .apply(card);

      expect(toasts(container).last, contains('has not come back'));
    });

    test('no HAT needs no card to come up', () async {
      final box = _Box(
        restarts: true,
        answers: [null, _info()],
        reports: [_report()],
      );
      final (container, target, proxy) = await start(box);

      await container
          .read(soundcardChangeProvider(target).notifier)
          .apply(
            const SoundcardOption(name: 'none', label: 'No HAT', kind: 'none'),
          );

      expect(proxy.updates, isEmpty);
      expect(toasts(container).last, 'The box is back, set up without a HAT.');
    });

    test('a refusal leaves nothing in progress', () async {
      final box = _Box()..refusal = const BoxActionException('busy', 'Busy.');
      final (container, target, _) = await start(box);

      await expectLater(
        container.read(soundcardChangeProvider(target).notifier).apply(card),
        throwsA(isA<BoxActionException>()),
      );
      expect(
        container.read(soundcardChangeProvider(target)),
        SoundcardStep.idle,
      );
    });
  });

  group('soundcardSummary', () {
    test('names the DAC that plays', () {
      expect(
        soundcardSummary(_report(name: 'HiFiBerry Digi2 Pro', pcm: 'hw:0')),
        'HiFiBerry Digi2 Pro',
      );
    });

    test('says what was found and not yet switched on', () {
      expect(
        soundcardSummary(_report(suggested: ['hifiberry-digi-pro'])),
        'HiFiBerry Digi+ Pro or Digi2 Pro found. Choose it to switch it on',
      );
      expect(
        soundcardSummary(
          _report(suggested: ['hifiberry-digi-pro', 'justboom-dac']),
        ),
        'A DAC HAT found. Choose your board',
      );
    });

    test('says when the card set up did not come up', () {
      expect(
        soundcardSummary(_report(configured: 'justboom-dac')),
        'JustBoom DAC HAT, not detected',
      );
      expect(soundcardSummary(_report()), 'No DAC HAT found');
    });
  });

  group('in settings', () {
    Future<_Box> pump(WidgetTester tester, Widget child, {_Box? box}) async {
      box ??= _Box(
        reports: [
          _report(
            name: 'HiFiBerry Digi2 Pro',
            suggested: ['hifiberry-digi-pro'],
          ),
        ],
      );
      final container = await _container(box: box);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: child)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return box;
    }

    testWidgets('the box shows its DAC and sets up the card chosen', (
      tester,
    ) async {
      final box = await pump(tester, const BoxSection());

      expect(find.text('Sound card'), findsOneWidget);
      expect(
        find.text('HiFiBerry Digi2 Pro found. Choose it to switch it on'),
        findsOneWidget,
      );

      await tester.tap(find.text('Sound card'));
      await tester.pumpAndSettle();
      final found = tester.getTopLeft(find.text('FOUND ON THIS BOX'));
      expect(found.dy, lessThan(tester.getTopLeft(find.text('JUSTBOOM')).dy));
      expect(find.text('THE PI’S OWN OUTPUTS'), findsOneWidget);
      expect(find.text('NO HAT'), findsOneWidget);

      await tester.tap(find.text('HiFiBerry Digi+ Pro or Digi2 Pro').first);
      await tester.pumpAndSettle();
      expect(find.text('Change the sound card?'), findsOneWidget);
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(box.applied, [
        ('hifiberry-digi-pro', const BoxIdentity(serverId: 'box-1')),
      ]);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('cancelling changes nothing', (tester) async {
      final box = await pump(tester, const BoxSection());

      await tester.tap(find.text('Sound card'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('JustBoom DAC HAT'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(box.applied, isEmpty);
    });

    testWidgets('an output on a box that cannot set a card up has no section', (
      tester,
    ) async {
      await pump(
        tester,
        const RendererSoundcardSection(rendererId: 'r-elsewhere'),
      );
      expect(find.text('SOUND CARD'), findsNothing);
    });

    testWidgets('setup points at the gear while the HAT is silent', (
      tester,
    ) async {
      await pump(tester, const SoundcardHint(rendererIds: ['r-local']));
      expect(find.textContaining('Using a DAC HAT?'), findsOneWidget);
    });

    testWidgets('setup says nothing once a card plays', (tester) async {
      await pump(
        tester,
        const SoundcardHint(rendererIds: ['r-local', 'r-elsewhere']),
        box: _Box(
          reports: [_report(name: 'DAC', pcm: 'hw:CARD=DAC,DEV=0')],
        ),
      );
      expect(find.textContaining('Using a DAC HAT?'), findsNothing);
    });

    testWidgets('the local output shows its box’s sound card', (tester) async {
      await pump(tester, const RendererSoundcardSection(rendererId: 'r-local'));
      expect(find.text('SOUND CARD'), findsOneWidget);
      expect(find.text('Sound card'), findsOneWidget);
    });
  });
}
