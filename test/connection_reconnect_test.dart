import 'dart:io' show HttpRequest, HttpServer, WebSocket, WebSocketTransformer;

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:dio/dio.dart' show DioException, RequestOptions;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/data_model.dart' show ModulesAndDevices;
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/kiosk_provider.dart';
import 'package:kalinka/providers/playback_time_provider.dart';
import 'package:kalinka/providers/websocket_provider.dart';

/// Regression coverage for issue #21: after a background→resume where the event
/// socket silently died, a successful HTTP reachability probe must NOT by
/// itself report the app as `connected`. Only the play-queue WebSocket actually
/// opening (and being replayed) may do that — otherwise the UI shows a green
/// "connected" indicator over an empty, never-repopulated queue.

/// Fake proxy exposing only [listModules]; its result is controlled per-test.
class _FakeApi implements KalinkaPlayerProxy {
  _FakeApi({this.shouldSucceed = true});

  bool shouldSucceed;
  int listModulesCalls = 0;

  @override
  Future<ModulesAndDevices> listModules() async {
    listModulesCalls++;
    if (!shouldSucceed) {
      throw DioException(requestOptions: RequestOptions(path: '/server/modules'));
    }
    return ModulesAndDevices(inputModules: const [], devices: const []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Lifecycle stuck at `resumed` so the reconnect path runs without a real
/// AppLifecycleListener (which would need a full widget binding).
class _ResumedLifecycle extends AppLifecycleNotifier {
  @override
  AppLifecycleState build() => AppLifecycleState.resumed;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> makeContainer(_FakeApi api) async {
    SharedPreferences.setMockInitialValues({
      'Kalinka.host': 'localhost',
      'Kalinka.port': 8080,
      'Kalinka.name': 'Test',
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        kalinkaProxyProvider.overrideWithValue(api),
        appLifecycleProvider.overrideWith(_ResumedLifecycle.new),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test(
    'a successful HTTP probe alone does not report connected (issue #21)',
    () async {
      final api = _FakeApi(shouldSucceed: true);
      final container = await makeContainer(api);

      final notifier = container.read(connectionStateProvider.notifier);
      final epochBefore = container.read(retryEpochProvider);
      final manualEpochBefore = container.read(manualReconnectEpochProvider);

      notifier.startReconnecting();
      expect(container.read(connectionStateProvider), ConnectionStatus.reconnecting);
      expect(container.read(manualReconnectEpochProvider), manualEpochBefore);

      notifier.retryNow();
      expect(container.read(manualReconnectEpochProvider), manualEpochBefore + 1);
      await pumpEventQueue();

      // The probe reached the server (so the socket rebuild is triggered)...
      expect(api.listModulesCalls, greaterThan(0));
      expect(container.read(retryEpochProvider), greaterThan(epochBefore));

      // ...but connectivity is still owned by the (absent) event socket, so we
      // stay reconnecting rather than falsely flipping to connected.
      expect(
        container.read(connectionStateProvider),
        ConnectionStatus.reconnecting,
      );
    },
  );

  test('a failed HTTP probe does not report connected', () async {
    final api = _FakeApi(shouldSucceed: false);
    final container = await makeContainer(api);

    final notifier = container.read(connectionStateProvider.notifier);
    notifier.startReconnecting();
    notifier.retryNow();
    await pumpEventQueue();

    expect(
      container.read(connectionStateProvider),
      isNot(ConnectionStatus.connected),
    );
  });

  group('escalation to offline (issue #67)', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'Kalinka.host': 'localhost',
        'Kalinka.port': 8080,
        'Kalinka.name': 'Test',
      });
      prefs = await SharedPreferences.getInstance();
    });

    // DateTime.now() ignores fakeAsync, so the notifier gets the fake clock.
    ProviderContainer fakeClockContainer(
      FakeAsync async,
      _FakeApi api, {
      required bool kiosk,
    }) {
      final start = DateTime(2026, 10, 3);
      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          kalinkaProxyProvider.overrideWithValue(api),
          appLifecycleProvider.overrideWith(_ResumedLifecycle.new),
          kioskLaunchProvider.overrideWithValue(kiosk),
          connectionStateProvider.overrideWith(
            () => ConnectionStateNotifier(now: () => start.add(async.elapsed)),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('the display keeps probing until the server answers', () {
      fakeAsync((async) {
        final api = _FakeApi(shouldSucceed: false);
        final container = fakeClockContainer(async, api, kiosk: true);
        final epochBefore = container.read(retryEpochProvider);

        container.read(connectionStateProvider.notifier).startReconnecting();
        async.elapse(const Duration(seconds: 60));

        expect(
          container.read(connectionStateProvider),
          ConnectionStatus.reconnecting,
        );
        final calls = api.listModulesCalls;
        expect(calls, greaterThanOrEqualTo(12));
        async.elapse(const Duration(seconds: 10));
        expect(api.listModulesCalls, greaterThan(calls));
        expect(container.read(retryEpochProvider), epochBefore);

        api.shouldSucceed = true;
        async.elapse(const Duration(seconds: 5));
        expect(container.read(retryEpochProvider), greaterThan(epochBefore));
      });
    });

    test('off the display, failures past 30s go offline and stop probing', () {
      fakeAsync((async) {
        final api = _FakeApi(shouldSucceed: false);
        final container = fakeClockContainer(async, api, kiosk: false);

        container.read(connectionStateProvider.notifier).startReconnecting();
        async.elapse(const Duration(seconds: 35));

        expect(
          container.read(connectionStateProvider),
          ConnectionStatus.offline,
        );
        final calls = api.listModulesCalls;
        async.elapse(const Duration(seconds: 30));
        expect(api.listModulesCalls, calls);
      });
    });

    test('opening the display while offline starts probing again', () {
      fakeAsync((async) {
        final api = _FakeApi(shouldSucceed: false);
        final container = fakeClockContainer(async, api, kiosk: false);

        container.read(connectionStateProvider.notifier).startReconnecting();
        async.elapse(const Duration(seconds: 35));
        expect(
          container.read(connectionStateProvider),
          ConnectionStatus.offline,
        );
        final calls = api.listModulesCalls;
        final manualEpochBefore = container.read(manualReconnectEpochProvider);

        container.read(kioskProvider.notifier).enter();
        async.flushMicrotasks();

        expect(
          container.read(connectionStateProvider),
          ConnectionStatus.reconnecting,
        );
        expect(api.listModulesCalls, calls + 1);
        expect(container.read(manualReconnectEpochProvider), manualEpochBefore);

        async.elapse(const Duration(seconds: 60));
        expect(
          container.read(connectionStateProvider),
          ConnectionStatus.reconnecting,
        );
        expect(api.listModulesCalls, greaterThan(calls + 1));
      });
    });
  });

  // Issue #21, second failure mode (Copilot review): the play-queue socket is
  // the single source of truth for `connected`. An auxiliary socket (e.g.
  // /device/ws, opened lazily on first now-playing) accepting a connection must
  // NOT flip the global state to `connected`, or the app shows a green
  // indicator over a queue the device socket never carries.
  group('only the queue socket owns the connected state', () {
    late HttpServer server;
    final open = <WebSocket>[];

    setUp(() async {
      server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((HttpRequest req) async {
        if (WebSocketTransformer.isUpgradeRequest(req)) {
          open.add(await WebSocketTransformer.upgrade(req)); // accept, stay open
        } else {
          req.response.statusCode = 404;
          await req.response.close();
        }
      });
    });

    tearDown(() async {
      for (final ws in open) {
        await ws.close();
      }
      await server.close(force: true);
    });

    Future<ProviderContainer> connectedContainer() async {
      SharedPreferences.setMockInitialValues({
        'Kalinka.host': '127.0.0.1',
        'Kalinka.port': server.port,
        'Kalinka.name': 'Test',
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          appLifecycleProvider.overrideWith(_ResumedLifecycle.new),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('device socket connecting does not report connected', () async {
      final container = await connectedContainer();

      await container.read(deviceWebSocketProvider.future);
      await pumpEventQueue();

      expect(
        container.read(connectionStateProvider),
        isNot(ConnectionStatus.connected),
      );
    });

    test('queue socket connecting does report connected', () async {
      final container = await connectedContainer();

      await container.read(queueWebSocketProvider.future);
      await pumpEventQueue();

      expect(
        container.read(connectionStateProvider),
        ConnectionStatus.connected,
      );
    });
  });
}
