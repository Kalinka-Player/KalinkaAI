import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart' show RendererInfo;
import 'package:kalinka/data_model/renderer_config.dart';
import 'package:kalinka/providers/box_control_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/demo_mode.dart';
import 'package:kalinka/providers/renderer_settings_provider.dart';
import 'package:kalinka/providers/renderer_settings_route_provider.dart';
import 'package:kalinka/providers/soundcard_provider.dart';
import 'package:kalinka/providers/supervisor_api.dart';
import 'package:kalinka/providers/toast_provider.dart';
import 'package:kalinka/screens/renderer_settings_screen.dart';
import 'package:kalinka/widgets/box_section.dart';
import 'package:kalinka/widgets/mini_player.dart';
import 'package:kalinka/widgets/settings_controls/option_picker.dart';
import 'package:kalinka/widgets/soundcard_row.dart';

import 'support/home_shell.dart';
import 'support/soundcard_fakes.dart';

Future<ProviderContainer> _container({
  required FakeBox box,
  FakeProxy? proxy,
  Map<String, SupervisorApi> others = const {},
}) async {
  final container = ProviderContainer(
    overrides: soundcardOverrides(
      await boxPrefs(),
      box: box,
      proxy: proxy,
      others: others,
    ),
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

const _hifiberryPcm = 'hw:CARD=sndrpihifiberry,DEV=0';

/// The output's settings with the device set to the HiFiBerry, listed as
/// [label].
RendererConfigSnapshot _deviceConfig(String label) => RendererConfigSnapshot(
  sections: [
    RendererConfigSection(
      path: 'output',
      title: 'Output',
      fields: [
        RendererConfigField(
          path: outputDevicePath,
          title: 'Device',
          type: RendererFieldType.enumeration,
          value: _hifiberryPcm,
          options: [
            const RendererConfigOption(
              value: 'default',
              label: 'System default',
            ),
            RendererConfigOption(value: _hifiberryPcm, label: label),
          ],
        ),
      ],
    ),
  ],
);

/// The output's settings: its device, and a switch at each of [switches].
RendererConfigSnapshot _outputConfig(
  String device, [
  List<String> switches = const [],
]) => RendererConfigSnapshot(
  sections: [
    RendererConfigSection(
      path: 'output',
      title: 'Output',
      fields: [
        RendererConfigField(
          path: outputDevicePath,
          title: 'Device',
          type: RendererFieldType.string,
          value: device,
        ),
        for (final path in switches)
          RendererConfigField(
            path: path,
            title: path,
            type: RendererFieldType.boolean,
            value: 'false',
          ),
      ],
    ),
  ],
);

class _Connected extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

/// A server whose local output has settings, behind the main screen.
class _ShellApi extends HomeApi {
  @override
  Future<List<RendererInfo>> listRenderers() async => [rendererRow('r-local')];

  @override
  Future<RendererConfigSnapshot> getRendererConfig(String rendererId) async =>
      _outputConfig('default');
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
        'usb': [
          {'id': 'D50s', 'name': 'Topping D50s', 'pcm': 'hw:CARD=D50s,DEV=0'},
          {'id': 'broken'},
        ],
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
      expect(report.usb, ['Topping D50s']);
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
        final container = await _container(box: FakeBox());
        final box = (await container.read(serverSoundcardBoxProvider.future))!;
        expect(box.identity, const BoxIdentity(serverId: 'box-1'));
        expect(box.rendererId, 'r-local');
      },
    );

    test('a supervisor that cannot set a card up offers no box', () async {
      final box = FakeBox(
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
      final container = await _container(box: FakeBox());
      final box = await container.read(
        rendererSoundcardBoxProvider('r-local').future,
      );
      expect(box!.identity.serverId, 'box-1');
    });

    test('a renderer elsewhere plays on the box it connected from', () async {
      final remote = FakeBox(
        answers: [supervisorInfo(serverId: null, rendererId: 'r-far')],
      );
      final container = await _container(
        box: FakeBox(),
        proxy: FakeProxy([rendererRow('r-far', address: '192.168.1.40')]),
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
          box: FakeBox(),
          proxy: FakeProxy([rendererRow('r-far', address: '192.168.1.40')]),
          others: {
            '192.168.1.40': FakeBox(
              answers: [supervisorInfo(rendererId: 'r-other')],
            ),
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
        box: FakeBox(),
        proxy: FakeProxy([rendererRow('r-far')]),
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

    Future<(ProviderContainer, SoundcardBox, FakeProxy)> start(
      FakeBox box,
    ) async {
      final proxy = FakeProxy([rendererRow('r-local')]);
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

    test('a card that needs no restart plays at once', () async {
      final box = FakeBox(
        reports: [
          soundcardReport(name: 'JustBoom DAC', pcm: 'hw:CARD=Boom,DEV=0'),
        ],
      );
      final (container, target, proxy) = await start(box);

      final outcome = await container
          .read(soundcardChangeProvider(target).notifier)
          .apply(card);

      expect(outcome, SoundcardOutcome.playing);
      expect(
        container.read(soundcardChangeProvider(target).notifier).restarted,
        isFalse,
      );
      expect(box.applied.single.$1, 'justboom-dac');
      expect(proxy.updates.single.$2, {'output.device': 'hw:CARD=Boom,DEV=0'});
      expect(
        container.read(soundcardChangeProvider(target)),
        SoundcardStep.idle,
      );
      expect(toasts(container).last, 'Playing through JustBoom DAC.');
    });

    test('a card set up without a restart that is not up says so', () async {
      final (container, target, proxy) = await start(FakeBox());

      final outcome = await container
          .read(soundcardChangeProvider(target).notifier)
          .apply(card);

      expect(outcome, SoundcardOutcome.silent);
      expect(proxy.updates, isEmpty);
      expect(toasts(container).last, contains('did not come up'));
    });

    test('follows the restart and plays through the new card', () async {
      final box = FakeBox(
        restarts: true,
        answers: [supervisorInfo(), null, null, supervisorInfo()],
        reports: [
          soundcardReport(),
          soundcardReport(
            name: 'JustBoom DAC',
            pcm: 'hw:CARD=sndrpijustboomd,DEV=0',
          ),
        ],
      );
      final (container, target, proxy) = await start(box);
      final steps = <SoundcardStep>[];
      container.listen(
        soundcardChangeProvider(target),
        (_, step) => steps.add(step),
      );

      final outcome = await container
          .read(soundcardChangeProvider(target).notifier)
          .apply(card);

      expect(outcome, SoundcardOutcome.playing);
      expect(
        container.read(soundcardChangeProvider(target).notifier).restarted,
        isTrue,
      );
      expect(steps, [
        SoundcardStep.applying,
        SoundcardStep.restarting,
        SoundcardStep.switching,
        SoundcardStep.idle,
      ]);
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

    test('holds the app only until the box answers', () async {
      final box = FakeBox(
        restarts: true,
        answers: [null, supervisorInfo()],
        reports: [
          soundcardReport(name: 'JustBoom DAC', pcm: 'hw:CARD=Boom,DEV=0'),
        ],
      );
      final (container, target, proxy) = await start(box);
      final down = box.holdInfo = Completer<void>();
      final write = proxy.holdUpdate = Completer<void>();

      final outcome = container
          .read(soundcardChangeProvider(target).notifier)
          .apply(card);
      await pumpEventQueue();
      expect(container.read(restartingBoxesProvider), {target});

      down.complete();
      await pumpEventQueue();
      expect(proxy.updates, hasLength(1));
      expect(
        container.read(soundcardChangeProvider(target)),
        SoundcardStep.switching,
      );
      expect(container.read(restartingBoxesProvider), isEmpty);

      write.complete();
      expect(await outcome, SoundcardOutcome.playing);
    });

    test('a card that does not come up is reported as such', () async {
      final box = FakeBox(
        restarts: true,
        answers: [null, supervisorInfo()],
        reports: [soundcardReport()],
      );
      final (container, target, proxy) = await start(box);

      final outcome = await container
          .read(soundcardChangeProvider(target).notifier)
          .apply(card);

      expect(outcome, SoundcardOutcome.silent);
      expect(proxy.updates, isEmpty);
      final toast = container.read(toastProvider).last;
      expect(toast.message, contains('did not come up'));
      expect(toast.isError, isTrue);
    });

    test('waits a short while for a card the box came back without', () async {
      final box = FakeBox(
        restarts: true,
        answers: [null, supervisorInfo()],
        reports: [soundcardReport()],
      );
      final (container, target, _) = await start(box);

      final outcome = await container
          .read(soundcardChangeProvider(target).notifier)
          .apply(card);

      expect(outcome, SoundcardOutcome.silent);
      expect(box.reportReads, 10);
    });

    test(
      'an onboard output that does not come up is not blamed on a HAT',
      () async {
        const hdmi = SoundcardOption(
          name: 'rpi-bcm2835-hdmi',
          label: 'Raspberry Pi HDMI',
          kind: 'onboard',
        );
        final restarted = FakeBox(
          restarts: true,
          answers: [null, supervisorInfo()],
          reports: [soundcardReport()],
        );
        final (container, target, _) = await start(restarted);
        final (inPlace, inPlaceTarget, _) = await start(FakeBox());

        expect(
          await container
              .read(soundcardChangeProvider(target).notifier)
              .apply(hdmi),
          SoundcardOutcome.silent,
        );
        expect(
          await inPlace
              .read(soundcardChangeProvider(inPlaceTarget).notifier)
              .apply(hdmi),
          SoundcardOutcome.silent,
        );

        expect(
          toasts(container).last,
          'The box is back, but the sound card did not come up. Choose another '
          'card.',
        );
        expect(
          toasts(inPlace).last,
          'Raspberry Pi HDMI is set up, but did not come up. Choose another '
          'card.',
        );
      },
    );

    test('a box that never comes back is reported as such', () async {
      final box = FakeBox(restarts: true, answers: [null]);
      final (container, target, _) = await start(box);

      final outcome = await container
          .read(soundcardChangeProvider(target).notifier)
          .apply(card);

      expect(outcome, SoundcardOutcome.notBack);
      expect(box.infoReads, 100);
      expect(toasts(container).last, contains('has not come back'));
    });

    test('a box that is not back holds the app until the change stops '
        'waiting', () async {
      final (container, target, _) = await start(
        FakeBox(restarts: true, answers: [null]),
      );
      final change = container.read(soundcardChangeProvider(target).notifier);

      expect(await change.apply(card), SoundcardOutcome.notBack);
      expect(container.read(restartingBoxesProvider), {target});

      change.stopWaiting();
      expect(
        container.read(soundcardChangeProvider(target)),
        SoundcardStep.idle,
      );
      expect(container.read(restartingBoxesProvider), isEmpty);
    });

    test('waiting on for a late box plays through its card', () async {
      final box = FakeBox(
        restarts: true,
        answers: [...List.filled(100, null), supervisorInfo()],
        reports: [
          soundcardReport(name: 'JustBoom DAC', pcm: 'hw:CARD=Boom,DEV=0'),
        ],
      );
      final (container, target, proxy) = await start(box);
      final change = container.read(soundcardChangeProvider(target).notifier);

      expect(await change.apply(card), SoundcardOutcome.notBack);
      expect(await change.keepWaiting(card), SoundcardOutcome.playing);
      expect(proxy.updates.single.$2, {'output.device': 'hw:CARD=Boom,DEV=0'});
    });

    test('no HAT needs no card to come up', () async {
      final box = FakeBox(
        restarts: true,
        answers: [null, supervisorInfo()],
        reports: [soundcardReport()],
      );
      final (container, target, proxy) = await start(box);

      final outcome = await container
          .read(soundcardChangeProvider(target).notifier)
          .apply(
            const SoundcardOption(name: 'none', label: 'No HAT', kind: 'none'),
          );

      expect(outcome, SoundcardOutcome.noHat);
      expect(proxy.updates, isEmpty);
      expect(toasts(container).last, 'The box is back, set up without a HAT.');
    });

    /// The output's settings as an open settings page holds them.
    Future<RendererSettingsNotifier> openSettings(ProviderContainer c) async {
      c.listen(rendererSettingsProvider('r-local'), (_, _) {});
      final settings = c.read(rendererSettingsProvider('r-local').notifier);
      await settings.load();
      return settings;
    }

    FakeBox restartsPlaying() => FakeBox(
      restarts: true,
      answers: [null, supervisorInfo()],
      reports: [
        soundcardReport(name: 'JustBoom DAC', pcm: 'hw:CARD=Boom,DEV=0'),
      ],
    );

    test(
      'reloads the settings of the renderer it pointed at the card',
      () async {
        final (container, target, proxy) = await start(restartsPlaying());
        await openSettings(container);

        final outcome = await container
            .read(soundcardChangeProvider(target).notifier)
            .apply(card);

        await Future<void>.delayed(Duration.zero);

        expect(outcome, SoundcardOutcome.playing);
        expect(proxy.configReads, ['r-local', 'r-local']);
      },
    );

    test('reloads the settings only once the renderer is back', () async {
      final box = FakeBox(
        restarts: true,
        answers: [null, supervisorInfo()],
        reports: [soundcardReport()],
      );
      final (container, target, proxy) = await start(box);
      await openSettings(container);
      proxy.renderers = [];

      final outcome = await container
          .read(soundcardChangeProvider(target).notifier)
          .apply(card);
      await Future<void>.delayed(Duration.zero);

      expect(outcome, SoundcardOutcome.silent);
      expect(proxy.configReads, ['r-local']);

      proxy.renderers = [rendererRow('r-local')];
      await pumpEventQueue();

      expect(proxy.configReads, ['r-local', 'r-local']);
    });

    test('reads no settings a page has not loaded', () async {
      final (container, target, proxy) = await start(restartsPlaying());

      await container
          .read(soundcardChangeProvider(target).notifier)
          .apply(card);

      expect(proxy.configReads, isEmpty);
    });

    test('reads no settings of a page since closed', () async {
      final (container, target, proxy) = await start(restartsPlaying());
      final page = container.listen(
        rendererSettingsProvider('r-local'),
        (_, _) {},
      );
      await container.read(rendererSettingsProvider('r-local').notifier).load();
      page.close();
      await Future<void>.delayed(Duration.zero);

      await container
          .read(soundcardChangeProvider(target).notifier)
          .apply(card);
      await pumpEventQueue();

      expect(proxy.configReads, ['r-local']);
    });

    test('keeps what the page staged through the reload', () async {
      final (container, target, proxy) = await start(restartsPlaying());
      proxy.rendererConfig = _outputConfig('default', [
        'output.exclusive',
        'output.dither',
      ]);
      (await openSettings(container))
        ..stage('output.exclusive', true)
        ..stage('output.dither', true)
        ..stage(outputDevicePath, 'hw:CARD=Boom,DEV=0');
      proxy.rendererConfig = _outputConfig('hw:CARD=Boom,DEV=0', [
        'output.exclusive',
      ]);

      await container
          .read(soundcardChangeProvider(target).notifier)
          .apply(card);
      await pumpEventQueue();

      final page = container.read(rendererSettingsProvider('r-local'));
      expect(proxy.configReads, hasLength(2));
      expect(page.values[outputDevicePath], 'hw:CARD=Boom,DEV=0');
      expect(page.staged, {'output.exclusive': true});
    });

    test('drops a staged device the change has since replaced', () async {
      final (container, target, proxy) = await start(restartsPlaying());
      proxy.rendererConfig = _outputConfig('default');
      (await openSettings(container)).stage(outputDevicePath, 'hw:CARD=Old');
      proxy.rendererConfig = _outputConfig('hw:CARD=Boom,DEV=0');

      await container
          .read(soundcardChangeProvider(target).notifier)
          .apply(card);
      await pumpEventQueue();

      final page = container.read(rendererSettingsProvider('r-local'));
      expect(page.values[outputDevicePath], 'hw:CARD=Boom,DEV=0');
      expect(page.staged, isEmpty);
    });

    test('leaves the reload to a save under way', () async {
      final box = FakeBox(
        restarts: true,
        answers: [null, supervisorInfo()],
        reports: [soundcardReport()],
      );
      final (container, target, proxy) = await start(box);
      final settings = await openSettings(container)
        ..stage('output.exclusive', true);
      final write = proxy.holdUpdate = Completer<void>();
      final save = settings.save();

      final outcome = await container
          .read(soundcardChangeProvider(target).notifier)
          .apply(card);
      await pumpEventQueue();

      expect(outcome, SoundcardOutcome.silent);
      expect(proxy.configReads, ['r-local']);
      expect(
        container.read(rendererSettingsProvider('r-local')).saving,
        isTrue,
      );

      write.complete();
      await save;
      expect(proxy.configReads, ['r-local', 'r-local']);
    });

    test('keeps staged settings when neither the box nor the output '
        'changed', () async {
      final (container, target, proxy) = await start(FakeBox());
      final settings = await openSettings(container);
      settings.stage('output.exclusive', true);

      final outcome = await container
          .read(soundcardChangeProvider(target).notifier)
          .apply(card);

      expect(outcome, SoundcardOutcome.silent);
      expect(proxy.configReads, ['r-local']);
      expect(container.read(rendererSettingsProvider('r-local')).staged, {
        'output.exclusive': true,
      });
    });

    test('a refusal leaves nothing in progress', () async {
      final box = FakeBox()
        ..refusal = const BoxActionException('busy', 'Busy.');
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
        soundcardSummary(
          soundcardReport(name: 'HiFiBerry Digi2 Pro', pcm: 'hw:0'),
        ),
        'HiFiBerry Digi2 Pro',
      );
    });

    test('says what was found and not yet switched on', () {
      expect(
        soundcardSummary(soundcardReport(suggested: ['hifiberry-digi-pro'])),
        'HiFiBerry Digi+ Pro or Digi2 Pro found. Choose it to switch it on',
      );
      expect(
        soundcardSummary(
          soundcardReport(suggested: ['hifiberry-digi-pro', 'justboom-dac']),
        ),
        'A DAC HAT found. Choose your board',
      );
    });

    test('says when the card set up did not come up', () {
      expect(
        soundcardSummary(soundcardReport(configured: 'justboom-dac')),
        'JustBoom DAC HAT, not detected',
      );
      expect(soundcardSummary(soundcardReport()), 'No DAC HAT found');
    });

    test('names a USB DAC on a box without a HAT', () {
      expect(
        soundcardSummary(soundcardReport(usb: ['Topping D50s'])),
        'No DAC HAT. USB DAC: Topping D50s',
      );
      expect(
        soundcardSummary(
          soundcardReport(
            usb: ['Topping D50s'],
            suggested: ['hifiberry-digi-pro'],
          ),
        ),
        'HiFiBerry Digi+ Pro or Digi2 Pro found. Choose it to switch it on',
      );
    });
  });

  group('soundcardTrouble', () {
    test('has nothing to say while a card plays or none was found', () {
      expect(
        soundcardTrouble(soundcardReport(name: 'DAC', pcm: 'hw:0')),
        isNull,
      );
      expect(soundcardTrouble(soundcardReport()), isNull);
      expect(soundcardTrouble(soundcardReport(usb: ['Topping D50s'])), isNull);
    });

    test('names a card found and not set up', () {
      expect(
        soundcardTrouble(
          soundcardReport(
            name: 'HiFiBerry Digi2 Pro',
            suggested: ['hifiberry-digi-pro'],
          ),
        ),
        'HiFiBerry Digi2 Pro was found but is not set up, so nothing plays '
        'through it yet.',
      );
      expect(
        soundcardTrouble(
          soundcardReport(suggested: ['hifiberry-digi-pro', 'justboom-dac']),
        ),
        startsWith('A DAC HAT was found'),
      );
    });

    test('says a card set up that did not come up', () {
      expect(
        soundcardTrouble(soundcardReport(configured: 'justboom-dac')),
        startsWith('JustBoom DAC HAT is set up but did not come up'),
      );
    });

    test('does not blame an onboard output on a HAT', () {
      expect(
        soundcardTrouble(soundcardReport(configured: 'rpi-bcm2835-hdmi')),
        'Raspberry Pi HDMI is set up but did not come up. Choose another '
        'card.',
      );
    });  });

  group('in settings', () {
    Future<FakeBox> pump(
      WidgetTester tester,
      Widget child, {
      FakeBox? box,
    }) async {
      box ??= FakeBox(
        reports: [
          soundcardReport(
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

    testWidgets('Streamer has no sound card controls', (tester) async {
      await pump(tester, const BoxSection());
      expect(find.text('Streamer dashboard'), findsOneWidget);
      expect(find.text('Sound card'), findsNothing);
    });

    testWidgets('the renderer shows its DAC and sets up the card chosen', (
      tester,
    ) async {
      final box = await pump(
        tester,
        const RendererSoundcardSection(rendererId: 'r-local'),
      );

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
        (
          'hifiberry-digi-pro',
          const BoxIdentity(serverId: 'box-1'),
        ),
      ]);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('cancelling changes nothing', (tester) async {
      final box = await pump(
        tester,
        const RendererSoundcardSection(rendererId: 'r-local'),
      );

      await tester.tap(find.text('Sound card'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('JustBoom DAC HAT'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(box.applied, isEmpty);
    });

    testWidgets(
      'the card the HAT set up is chosen, and choosing it is no change',
      (tester) async {
        final box = await pump(
          tester,
          const RendererSoundcardSection(rendererId: 'r-local'),
          box: FakeBox(
            reports: [
              soundcardReport(
                name: 'HiFiBerry Digi2 Pro',
                configured: 'hifiberry-digi-pro',
                pcm: 'hw:CARD=sndrpihifiberry,DEV=0',
              ),
            ],
          ),
        );
        expect(find.text('HiFiBerry Digi2 Pro'), findsOneWidget);

        await tester.tap(find.text('Sound card'));
        await tester.pumpAndSettle();
        final chosen = tester
            .widgetList<OptionRow>(find.byType(OptionRow))
            .where((row) => row.selected);
        expect(chosen.single.option.value, 'hifiberry-digi-pro');

        await tester.tap(find.text('HiFiBerry Digi+ Pro or Digi2 Pro'));
        await tester.pumpAndSettle();
        expect(find.text('Change the sound card?'), findsNothing);
        expect(box.applied, isEmpty);
      },
    );

    testWidgets('an output on a box that cannot set a card up has no section', (
      tester,
    ) async {
      await pump(
        tester,
        const RendererSoundcardSection(rendererId: 'r-elsewhere'),
      );
      expect(find.text('SOUND CARD'), findsNothing);
    });

    testWidgets('the local output shows its box’s sound card', (tester) async {
      await pump(tester, const RendererSoundcardSection(rendererId: 'r-local'));
      expect(find.text('SOUND CARD'), findsOneWidget);
      expect(find.text('Sound card'), findsOneWidget);
    });

    testWidgets('the output’s device is named again once its card is back', (
      tester,
    ) async {
      final box = FakeBox(
        restarts: true,
        reports: [soundcardReport(configured: 'justboom-dac')],
      )..answersAfterApply = [null, supervisorInfo(rendererId: 'r-local')];
      final proxy = FakeProxy([rendererRow('r-local')])
        ..rendererConfig = _deviceConfig('$_hifiberryPcm (not detected)');
      final container = ProviderContainer(
        overrides: [
          ...soundcardOverrides(await boxPrefs(), box: box, proxy: proxy),
          connectionStateProvider.overrideWith(_Connected.new),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: RendererSettingsScreen(
                rendererId: 'r-local',
                rendererName: 'Living room',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('$_hifiberryPcm (not detected)'), findsOneWidget);

      box.reports
        ..clear()
        ..add(
          soundcardReport(
            name: 'HiFiBerry Digi2 Pro',
            configured: 'hifiberry-digi-pro',
            pcm: _hifiberryPcm,
          ),
        );
      proxy.rendererConfig = _deviceConfig('HiFiBerry Digi+ Pro');
      await tester.tap(find.text('Sound card'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('HiFiBerry Digi+ Pro or Digi2 Pro'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(proxy.updates.single.$2, {outputDevicePath: _hifiberryPcm});
      expect(find.text('HiFiBerry Digi+ Pro'), findsOneWidget);
      expect(find.textContaining('not detected'), findsNothing);
      await tester.pump(const Duration(seconds: 6));
    });

    Future<void> chooseJustBoom(WidgetTester tester) async {
      await tester.tap(find.text('Sound card'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('JustBoom DAC HAT'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
    }

    testWidgets('Back keeps the output’s settings while the box is down, and '
        'closes them once it answers', (tester) async {
      final box = FakeBox(restarts: true)
        ..answersAfterApply = [null, supervisorInfo(rendererId: 'r-local')];
      final proxy = FakeProxy([rendererRow('r-local')])
        ..rendererConfig = _outputConfig('default');
      final container = ProviderContainer(
        overrides: [
          ...soundcardOverrides(await boxPrefs(), box: box, proxy: proxy),
          connectionStateProvider.overrideWith(_Connected.new),
        ],
      );
      addTearDown(container.dispose);
      var open = true;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => open
                    ? RendererSettingsScreen(
                        rendererId: 'r-local',
                        rendererName: 'Living room',
                        onClose: () => setState(() => open = false),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final down = box.holdInfo = Completer<void>();

      await chooseJustBoom(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(RendererSettingsScreen), findsOneWidget);
      expect(find.text('Restarting the Pi'), findsWidgets);

      final write = proxy.holdUpdate = Completer<void>();
      box.reports
        ..clear()
        ..add(soundcardReport(name: 'JustBoom DAC', pcm: 'hw:CARD=Boom,DEV=0'));
      down.complete();
      await tester.pumpAndSettle();
      expect(find.text('Restarting the Pi'), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(RendererSettingsScreen), findsNothing);

      write.complete();
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('a box not back in time offers the way on, and Continue lets '
        'the app go on', (tester) async {
      final box = FakeBox(restarts: true)..answersAfterApply = [null];
      final container = await pumpHomeShell(
        tester,
        queue: SettableQueue(queueOf(2)),
        api: _ShellApi(),
        overrides: [
          supervisorApiProvider.overrideWithValue(box),
          serverIdentityProvider.overrideWith((ref) async => 'box-1'),
          demoModeProvider.overrideWithValue(false),
          soundcardPollProvider.overrideWithValue(Duration.zero),
        ],
      );
      container
          .read(rendererSettingsRouteProvider.notifier)
          .open('r-local', 'Living room');
      await tester.pumpAndSettle();

      await chooseJustBoom(tester);

      expect(find.text('The Pi is not back yet'), findsOneWidget);
      expect(find.text('Keep waiting'), findsOneWidget);
      expect(find.byType(MiniPlayer), findsNothing);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('The Pi is not back yet'), findsNothing);
      expect(find.byType(RendererSettingsScreen), findsOneWidget);
      expect(find.byType(MiniPlayer), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });
  });
}
