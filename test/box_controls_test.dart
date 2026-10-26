import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/providers/box_control_provider.dart';
import 'package:kalinka/providers/box_power_off_timer_provider.dart';
import 'package:kalinka/providers/settings_provider.dart';
import 'package:kalinka/data_model/presentation_schema.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/demo_mode.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/pinned_catalogs_provider.dart';
import 'package:kalinka/providers/supervisor_api.dart';
import 'package:kalinka/providers/timezone_provider.dart';
import 'package:kalinka/providers/toast_provider.dart';
import 'package:kalinka/widgets/box_section.dart';
import 'package:kalinka/widgets/expert_settings_screen.dart';
import 'package:kalinka/widgets/configuration_appearance.dart';
import 'package:kalinka/widgets/settings_controls/settings_action_row.dart';
import 'package:kalinka/widgets/escalation_card.dart';
import 'package:kalinka/widgets/kalinka_dialog.dart';
import 'package:kalinka/widgets/timezone_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/server_answer.dart';

class _FakeBox implements SupervisorApi {
  _FakeBox({
    this.answer,
    this.state = 'active',
    this.noAnswer = SupervisorReach.absent,
  });

  SupervisorInfo? answer;
  final SupervisorReach noAnswer;
  String? state;
  BoxActionException? refusal;
  final runs = <(BoxAction, String)>[];
  int probes = 0;

  @override
  Future<SupervisorInfo?> info() async => answer;

  @override
  Future<({SupervisorReach reach, SupervisorInfo? info})> probe() async {
    probes++;
    return (
      reach: answer == null ? noAnswer : SupervisorReach.answered,
      info: answer,
    );
  }

  @override
  Future<String?> serverState() async => state;

  @override
  Future<void> run(BoxAction action, {required String serverId}) async {
    runs.add((action, serverId));
    if (refusal != null) throw refusal!;
  }

  @override
  Future<SoundcardReport?> soundcard() async => null;

  @override
  Future<bool> setSoundcard(String card, BoxIdentity identity) async => false;

  @override
  Future<String?> timezone() async => 'UTC';

  @override
  Future<List<String>?> timezones() async => const ['UTC'];

  @override
  Future<String> setTimezone(String zone, BoxIdentity identity) async => zone;

  @override
  Uri get page => Uri.parse('http://kalinka.local:8001/');
}

SupervisorInfo _info({
  String? serverId = 'box-1',
  int protocol = 1,
  int minProtocol = 1,
  Set<String> actions = const {'restart_core', 'reboot', 'poweroff'},
  bool timer = false,
}) => SupervisorInfo(
  version: '0.2.0',
  protocol: protocol,
  minProtocol: minProtocol,
  serverId: serverId,
  actions: actions,
  supportsPowerOffTimer: timer,
);

class _Settings extends SettingsNotifier {
  _Settings(this.seed);
  final SettingsState seed;
  @override
  SettingsState build() => seed;
}

const _timerSettings = SettingsState(
  schema: PresentationSchema(
    schemaVersion: 'timer',
    pages: [],
    expertFields: [
      FieldSpec(
        path: boxPowerOffEnabledPath,
        label: 'Power-off timer',
        help: 'Power off the streamer after playback stays paused or stopped for the set time.',
        widget: WidgetKind.toggle,
        type: 'bool',
        defaultValue: false,
        importance: Importance.expert,
      ),
      FieldSpec(
        path: boxPowerOffMinutesPath,
        label: 'Power off after',
        widget: WidgetKind.numberInput,
        type: 'int',
        defaultValue: 30,
        importance: Importance.expert,
        constraints: Constraints(ge: 1, le: 1440, step: 1, unit: 'min'),
      ),
    ],
  ),
  values: {boxPowerOffEnabledPath: false, boxPowerOffMinutesPath: 30},
);

/// Connection held at [initial], escalated, counting manual retries.
class _Connection extends ConnectionStateNotifier {
  _Connection(this.initial);

  final ConnectionStatus initial;
  int retries = 0;

  @override
  ConnectionStatus build() => initial;

  @override
  bool get escalationReached => true;

  @override
  void retryNow() => retries++;
}

const _address = {'Kalinka.host': 'kalinka.local', 'Kalinka.port': 8000};
const _knownKey = 'Kalinka.serverIdAt.kalinka.local:8000';

Future<ProviderContainer> _container({
  required SupervisorApi? box,
  String? identity,
  Map<String, Object> stored = const {},
  bool demo = false,
  List overrides = const [],
}) async {
  SharedPreferences.setMockInitialValues({..._address, ...stored});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      supervisorApiProvider.overrideWithValue(box),
      serverIdentityProvider.overrideWith((ref) async => identity),
      demoModeProvider.overrideWithValue(demo),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode({'server_id': 'box-1', 'sessions': []}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('boxControlProvider', () {
    test('offers the box of the connected server', () async {
      final container = await _container(
        box: _FakeBox(answer: _info()),
        identity: 'box-1',
      );

      final control = await container.read(boxControlProvider.future);

      expect(control!.serverId, 'box-1');
      expect(control.offers(BoxAction.powerOff), isTrue);
    });

    test('a box answering for another server is not offered', () async {
      final container = await _container(
        box: _FakeBox(answer: _info(serverId: 'box-2')),
        identity: 'box-1',
      );
      expect(await container.read(boxControlProvider.future), isNull);
    });

    test(
      'with the server down, the box of the server last seen here is',
      () async {
        final container = await _container(
          box: _FakeBox(answer: _info()),
          stored: {_knownKey: 'box-1'},
        );
        expect(
          (await container.read(boxControlProvider.future))!.serverId,
          'box-1',
        );
      },
    );

    test('with the server down and never seen here, no box is', () async {
      final container = await _container(box: _FakeBox(answer: _info()));
      expect(await container.read(boxControlProvider.future), isNull);
    });

    test(
      'a server seen at another address does not vouch for this one',
      () async {
        final container = await _container(
          box: _FakeBox(answer: _info()),
          stored: {'Kalinka.serverIdAt.10.0.0.9:8000': 'box-1'},
        );
        expect(await container.read(boxControlProvider.future), isNull);
      },
    );

    test('a supervisor speaking another protocol is not offered', () async {
      final container = await _container(
        box: _FakeBox(answer: _info(protocol: 2, minProtocol: 2)),
        identity: 'box-1',
      );
      expect(await container.read(boxControlProvider.future), isNull);
    });

    test('a demo server has no box', () async {
      final container = await _container(
        box: _FakeBox(answer: _info()),
        identity: 'box-1',
        demo: true,
      );
      expect(await container.read(boxControlProvider.future), isNull);
    });

    test('a box without a supervisor offers nothing', () async {
      final container = await _container(box: _FakeBox(), identity: 'box-1');
      expect(await container.read(boxControlProvider.future), isNull);
    });
  });

  group('boxProbeProvider', () {
    Future<NoBoxControl?> missing(
      _FakeBox box, {
      String? identity = 'box-1',
      bool demo = false,
    }) async {
      final container = await _container(
        box: box,
        identity: identity,
        demo: demo,
      );
      return (await container.read(boxProbeProvider.future)).missing;
    }

    test('finds the box of the connected server', () async {
      expect(await missing(_FakeBox(answer: _info())), isNull);
    });

    test('nothing listening is no supervisor', () async {
      expect(await missing(_FakeBox()), NoBoxControl.noSupervisor);
      expect(
        await missing(_FakeBox(answer: _info()), demo: true),
        NoBoxControl.noSupervisor,
      );
    });

    test('a supervisor that does not answer is told apart', () async {
      expect(
        await missing(_FakeBox(noAnswer: SupervisorReach.silent)),
        NoBoxControl.notAnswering,
      );
    });

    test('a server not known yet cannot be matched', () async {
      expect(
        await missing(_FakeBox(answer: _info()), identity: null),
        NoBoxControl.notAnswering,
      );
    });

    test('a supervisor of another server says so', () async {
      expect(
        await missing(_FakeBox(answer: _info(serverId: 'box-2'))),
        NoBoxControl.otherServer,
      );
    });

    test('a supervisor on another protocol says so', () async {
      expect(
        await missing(_FakeBox(answer: _info(protocol: 2, minProtocol: 2))),
        NoBoxControl.incompatible,
      );
    });

    test('looks again once invalidated', () async {
      final box = _FakeBox(noAnswer: SupervisorReach.silent);
      final container = await _container(box: box, identity: 'box-1');
      expect(await container.read(boxControlProvider.future), isNull);

      box.answer = _info();
      container.invalidate(boxProbeProvider);

      expect(
        (await container.read(boxControlProvider.future))!.serverId,
        'box-1',
      );
    });
  });

  group('rememberServerIdentityProvider', () {
    test('remembers the connected server under its address', () async {
      final container = await _container(box: null, identity: 'box-1');

      container.read(rememberServerIdentityProvider);
      await container.read(serverIdentityProvider.future);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(sharedPrefsProvider).getString(_knownKey), 'box-1');
    });

    test('a server not connected leaves the record alone', () async {
      final container = await _container(
        box: null,
        stored: {_knownKey: 'box-1'},
      );

      container.read(rememberServerIdentityProvider);
      await container.read(serverIdentityProvider.future);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(sharedPrefsProvider).getString(_knownKey), 'box-1');
    });
  });

  group('serverIdentityProvider', () {
    Future<(ProviderContainer, _Adapter)> make(ConnectionStatus status) async {
      SharedPreferences.setMockInitialValues(_address);
      final prefs = await SharedPreferences.getInstance();
      final adapter = _Adapter();
      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          httpClientProvider.overrideWithValue(
            Dio(BaseOptions(baseUrl: 'http://kalinka.local:8000'))
              ..httpClientAdapter = adapter,
          ),
          connectionStateProvider.overrideWith(() => _Connection(status)),
        ],
      );
      addTearDown(container.dispose);
      return (container, adapter);
    }

    test('asks the connected server who it is', () async {
      final (container, adapter) = await make(ConnectionStatus.connected);
      expect(await container.read(serverIdentityProvider.future), 'box-1');
      expect(adapter.requests.single.path, '/renderer/sessions');
    });

    test('does not ask a server that is not connected', () async {
      final (container, adapter) = await make(ConnectionStatus.offline);
      expect(await container.read(serverIdentityProvider.future), isNull);
      expect(adapter.requests, isEmpty);
    });

    test('asking a silent server again does not look for its box again', () {
      fakeAsync((async) {
        // Known here before, so its box is looked for while it is silent.
        SharedPreferences.setMockInitialValues({
          ..._address,
          _knownKey: 'box-1',
        });
        late SharedPreferences prefs;
        SharedPreferences.getInstance().then((value) => prefs = value);
        async.flushMicrotasks();
        final servers = ServersByHost()..silent.add('kalinka.local');
        final box = _FakeBox(answer: _info());
        final container = ProviderContainer(
          overrides: [
            sharedPrefsProvider.overrideWithValue(prefs),
            supervisorApiProvider.overrideWithValue(box),
            demoModeProvider.overrideWithValue(false),
            connectionStateProvider.overrideWith(
              () => _Connection(ConnectionStatus.connected),
            ),
            servers.client,
          ],
        )..listen(boxProbeProvider, (_, _) {});
        async.elapse(const Duration(seconds: 30));
        expect(servers.asked, 5);
        expect(box.probes, 1);

        servers.ids['kalinka.local'] = 'box-1';
        servers.silent.clear();
        async.elapse(const Duration(seconds: 40));
        expect(servers.asked, 6);
        expect(box.probes, 2);
        expect(
          container.read(boxProbeProvider).value?.control?.serverId,
          'box-1',
        );
        container.dispose();
      });
    });
  });

  group('the time zone row, looking for a box that did not answer', () {
    const missing = BoxProbe.missing(NoBoxControl.notAnswering);

    Future<(ProviderContainer, ServersByHost)> pump(
      WidgetTester tester, {
      required bool answered,
    }) async {
      SharedPreferences.setMockInitialValues(_address);
      final prefs = await SharedPreferences.getInstance();
      final servers = ServersByHost();
      if (answered) {
        servers.ids['kalinka.local'] = 'box-1';
      } else {
        servers.silent.add('kalinka.local');
      }
      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          connectionStateProvider.overrideWith(
            () => _Connection(ConnectionStatus.connected),
          ),
          servers.client,
          boxProbeProvider.overrideWith((ref) async => missing),
        ],
      );
      addTearDown(container.dispose);
      container.listen(pinnedCatalogsProvider, (_, _) {});
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: TimezoneRow(box: BoxTimezone(missing))),
          ),
        ),
      );
      // Dio's request needs the clock to move, not only a frame.
      await tester.pump(const Duration(milliseconds: 1));
      expect(servers.asked, 1);
      return (container, servers);
    }

    Future<void> tapRetry(WidgetTester tester) async {
      await tester.tap(find.text('Time zone'));
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 1));
    }

    testWidgets('does not ask a server that has answered who it is again', (
      tester,
    ) async {
      final (container, servers) = await pump(tester, answered: true);
      expect(container.read(pinnedCatalogsProvider), isEmpty);

      servers.silent.add('kalinka.local');
      await tapRetry(tester);
      expect(servers.asked, 1);
      expect(container.read(pinnedCatalogsProvider), isEmpty);
    });

    testWidgets('asks a server that has not answered at once', (tester) async {
      final (container, servers) = await pump(tester, answered: false);
      expect(container.read(pinnedCatalogsProvider), isNull);

      servers
        ..silent.clear()
        ..ids['kalinka.local'] = 'box-1';
      await tapRetry(tester);
      expect(servers.asked, 2);
      expect(container.read(pinnedCatalogsProvider), isEmpty);
    });
  });

  group('BoxSection', () {
    Future<(ProviderContainer, _FakeBox)> pump(
      WidgetTester tester, {
      SupervisorInfo? answer,
      bool configuration = false,
      SettingsState settings = const SettingsState(),
      bool expert = false,
      double textScale = 1,
    }) async {
      final box = _FakeBox(answer: answer);
      final container = await _container(
        box: box,
        identity: 'box-1',
        overrides: [settingsProvider.overrideWith(() => _Settings(settings))],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: Scaffold(
              body: expert
                  ? const ExpertSettingsScreen()
                  : SingleChildScrollView(
                      child: configuration
                          ? const ConfigurationAppearance(child: BoxSection())
                          : const BoxSection(),
                    ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (container, box);
    }

    testWidgets('offers the dashboard and the box actions', (tester) async {
      await pump(tester, answer: _info(), configuration: true);

      expect(find.text('STREAMER'), findsOneWidget);
      expect(find.text('Streamer dashboard'), findsOneWidget);
      expect(find.text('Restart streamer'), findsOneWidget);
      expect(find.text('Power off streamer'), findsOneWidget);
      for (final (label, icon) in [
        ('Streamer dashboard', Icons.dashboard_outlined),
        ('Restart streamer', Icons.autorenew),
        ('Power off streamer', Icons.power_settings_new),
      ]) {
        final text = find.text(label);
        final row = find.ancestor(
          of: text,
          matching: find.byType(SettingsActionRow),
        );
        final leading = find.descendant(of: row, matching: find.byIcon(icon));
        expect(
          tester.getRect(leading).right,
          lessThan(tester.getRect(text).left),
        );
        expect(
          find.descendant(of: row, matching: find.byIcon(Icons.chevron_right)),
          findsNothing,
        );
      }
      expect(
        tester.getRect(find.byIcon(Icons.open_in_new)).left,
        greaterThan(tester.getRect(find.text('Streamer dashboard')).right),
      );
    });

    testWidgets('is absent without a supervisor', (tester) async {
      await pump(tester);
      expect(find.text('STREAMER'), findsNothing);
    });

    testWidgets('stages the timer and minutes beside power off', (
      tester,
    ) async {
      final (container, box) = await pump(
        tester,
        answer: _info(timer: true),
        settings: _timerSettings,
        configuration: true,
      );
      expect(find.text('Power-off timer'), findsOneWidget);
      expect(find.text('Power off after'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Power-off timer')).dy,
        greaterThan(tester.getTopLeft(find.text('Power off streamer')).dy),
      );
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('Power off after'), findsOneWidget);
      expect(find.text('min'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '45');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).stagedChanges, {
        boxPowerOffEnabledPath: true,
        boxPowerOffMinutesPath: 45,
      });
      await tester.enterText(find.byType(TextField), '60');
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Power off after'), findsNothing);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('60'), findsOneWidget);
      container.read(settingsProvider.notifier).discardAll();
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(box.runs, isEmpty);
    });

    for (final (name, info, settings) in [
      ('absent supervisor', null, _timerSettings),
      ('older supervisor', _info(), _timerSettings),
      ('older Core', _info(timer: true), const SettingsState()),
      ('wrong box', _info(serverId: 'box-2', timer: true), _timerSettings),
      (
        'no power-off action',
        _info(timer: true, actions: {'reboot'}),
        _timerSettings,
      ),
    ]) {
      testWidgets('hides timer for $name', (tester) async {
        await pump(tester, answer: info, settings: settings);
        expect(find.text('Power-off timer'), findsNothing);
        expect(find.byType(Switch), findsNothing);
      });
    }

    testWidgets('advanced settings also hide an unsupported timer', (
      tester,
    ) async {
      await pump(tester, settings: _timerSettings, expert: true);
      expect(find.text('Power-off timer'), findsNothing);
      expect(find.text('Power off after'), findsNothing);
    });

    for (final size in [const Size(375, 812), const Size(812, 375)]) {
      testWidgets('timer fits $size with large text', (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await pump(
          tester,
          answer: _info(timer: true),
          settings: _timerSettings.copyWith(
            values: {boxPowerOffEnabledPath: true, boxPowerOffMinutesPath: 30},
          ),
          configuration: true,
          textScale: 2,
        );
        await tester.ensureVisible(find.byType(TextField));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Power off after'), findsOneWidget);
      });
    }

    testWidgets('leaves out what the box does not offer', (tester) async {
      await pump(tester, answer: _info(actions: {'poweroff'}));
      expect(find.text('Restart streamer'), findsNothing);
      expect(find.text('Power off streamer'), findsOneWidget);
    });

    testWidgets('powers off only once confirmed', (tester) async {
      final (_, box) = await pump(tester, answer: _info(), configuration: true);

      await tester.tap(find.text('Power off streamer'));
      await tester.pumpAndSettle();
      expect(find.text('Power off streamer?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(box.runs, isEmpty);

      await tester.tap(find.text('Power off streamer'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(KalinkaDialog),
          matching: find.text('Power off'),
        ),
      );
      await tester.pumpAndSettle();
      expect(box.runs, [(BoxAction.powerOff, 'box-1')]);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('reports a refusal in the box’s place', (tester) async {
      final (container, box) = await pump(tester, answer: _info());
      box.refusal = const BoxActionException('busy', 'The box is busy.');

      await tester.tap(find.text('Restart streamer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restart'));
      await tester.pumpAndSettle();

      expect(box.runs, [(BoxAction.reboot, 'box-1')]);
      final toast = container.read(toastProvider).single;
      expect(toast.message, 'The box is busy.');
      expect(toast.isError, isTrue);
      await tester.pump(const Duration(seconds: 6));
    });
  });

  group('EscalationCard', () {
    Future<(_FakeBox, _Connection)> pump(
      WidgetTester tester, {
      SupervisorInfo? answer,
      String state = 'active',
    }) async {
      final box = _FakeBox(answer: answer, state: state);
      final connection = _Connection(ConnectionStatus.offline);
      final container = await _container(
        box: box,
        stored: {_knownKey: 'box-1'},
        overrides: [connectionStateProvider.overrideWith(() => connection)],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(body: EscalationCard(onScanForServers: () {})),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (box, connection);
    }

    testWidgets('offers a scan when the box does not answer', (tester) async {
      await pump(tester);
      expect(find.text('Scan for servers'), findsOneWidget);
      expect(find.text('Restart server'), findsNothing);
    });

    testWidgets('restarts the server through its box', (tester) async {
      final (box, connection) = await pump(tester, answer: _info());

      expect(find.text('Scan for servers'), findsNothing);
      await tester.tap(find.text('Restart server'));
      await tester.pumpAndSettle();
      expect(find.text('Restart the server?'), findsOneWidget);
      await tester.tap(find.text('Restart'));
      await tester.pumpAndSettle();

      expect(box.runs, [(BoxAction.restartServer, 'box-1')]);
      expect(connection.retries, 1);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('does not restart a server that is still starting', (
      tester,
    ) async {
      final (box, connection) = await pump(
        tester,
        answer: _info(),
        state: 'activating',
      );

      await tester.tap(find.text('Restart server'));
      await tester.pumpAndSettle();

      expect(find.text('Restart the server?'), findsNothing);
      expect(box.runs, isEmpty);
      expect(connection.retries, 1);
      await tester.pump(const Duration(seconds: 3));
    });
  });
}
