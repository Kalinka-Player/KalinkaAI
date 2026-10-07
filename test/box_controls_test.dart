import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/providers/box_control_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/demo_mode.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/supervisor_api.dart';
import 'package:kalinka/providers/toast_provider.dart';
import 'package:kalinka/widgets/box_section.dart';
import 'package:kalinka/widgets/escalation_card.dart';
import 'package:kalinka/widgets/kalinka_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeBox implements SupervisorApi {
  _FakeBox({this.answer, this.state = 'active'});

  SupervisorInfo? answer;
  String? state;
  BoxActionException? refusal;
  final runs = <(BoxAction, String)>[];

  @override
  Future<SupervisorInfo?> info() async => answer;

  @override
  Future<String?> serverState() async => state;

  @override
  Future<void> run(BoxAction action, {required String serverId}) async {
    runs.add((action, serverId));
    if (refusal != null) throw refusal!;
  }

  @override
  Uri get page => Uri.parse('http://kalinka.local:8001/');
}

SupervisorInfo _info({
  String? serverId = 'box-1',
  int protocol = 1,
  int minProtocol = 1,
  Set<String> actions = const {'restart_core', 'reboot', 'poweroff'},
}) => SupervisorInfo(
  version: '0.2.0',
  protocol: protocol,
  minProtocol: minProtocol,
  serverId: serverId,
  actions: actions,
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
  });

  group('BoxSection', () {
    Future<(ProviderContainer, _FakeBox)> pump(
      WidgetTester tester, {
      SupervisorInfo? answer,
    }) async {
      final box = _FakeBox(answer: answer);
      final container = await _container(box: box, identity: 'box-1');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: BoxSection())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (container, box);
    }

    testWidgets('offers the dashboard and the box actions', (tester) async {
      await pump(tester, answer: _info());

      expect(find.text('BOX'), findsOneWidget);
      expect(find.text('Box dashboard'), findsOneWidget);
      expect(find.text('Restart the box'), findsOneWidget);
      expect(find.text('Power off'), findsOneWidget);
    });

    testWidgets('is absent without a supervisor', (tester) async {
      await pump(tester);
      expect(find.text('BOX'), findsNothing);
    });

    testWidgets('leaves out what the box does not offer', (tester) async {
      await pump(tester, answer: _info(actions: {'poweroff'}));
      expect(find.text('Restart the box'), findsNothing);
      expect(find.text('Power off'), findsOneWidget);
    });

    testWidgets('powers off only once confirmed', (tester) async {
      final (_, box) = await pump(tester, answer: _info());

      await tester.tap(find.text('Power off'));
      await tester.pumpAndSettle();
      expect(find.text('Power off the box?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(box.runs, isEmpty);

      await tester.tap(find.text('Power off'));
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

      await tester.tap(find.text('Restart the box'));
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
