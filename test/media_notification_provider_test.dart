import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/media_notification_provider.dart';
import 'package:kalinka/providers/playback_time_provider.dart';

class _Connection extends ConnectionStateNotifier {
  _Connection(this.initial);
  final ConnectionStatus initial;

  @override
  ConnectionStatus build() => initial;

  void setStatus(ConnectionStatus value) => state = value;
}

class _Lifecycle extends AppLifecycleNotifier {
  @override
  AppLifecycleState build() => AppLifecycleState.resumed;

  void setLifecycle(AppLifecycleState value) => state = value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.kalinka.kalinka/media_session');
  final calls = <MethodCall>[];
  final containers = <ProviderContainer>[];

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    for (final container in containers) {
      container.dispose();
    }
    containers.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  Future<ProviderContainer> create({
    ConnectionStatus status = ConnectionStatus.connected,
  }) async {
    SharedPreferences.setMockInitialValues({
      'Kalinka.host': 'server.test',
      'Kalinka.port': 8000,
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        connectionStateProvider.overrideWith(() => _Connection(status)),
        appLifecycleProvider.overrideWith(_Lifecycle.new),
      ],
    );
    containers.add(container);
    container.read(mediaNotificationProvider);
    await pumpEventQueue();
    return container;
  }

  List<String> methods() => calls.map((call) => call.method).toList();

  test('first healthy connection enables native media controls', () async {
    final container = await create(status: ConnectionStatus.connecting);
    expect(calls, isEmpty);
    (container.read(connectionStateProvider.notifier) as _Connection).setStatus(
      ConnectionStatus.connected,
    );
    await pumpEventQueue();
    expect(methods(), ['enableNotification']);
    expect(calls.single.arguments, {'host': 'server.test', 'port': 8000});
  });

  test(
    'loss dismisses immediately and automatic reconnect stays hidden',
    () async {
      final container = await create();
      final connection =
          container.read(connectionStateProvider.notifier) as _Connection;
      connection.setStatus(ConnectionStatus.reconnecting);
      await pumpEventQueue();
      expect(methods(), ['enableNotification', 'disableNotification']);
      connection.setStatus(ConnectionStatus.connected);
      await pumpEventQueue();
      expect(methods(), ['enableNotification', 'disableNotification']);
    },
  );

  test(
    'returning to the app restores controls after background reconnect',
    () async {
      final container = await create();
      final connection =
          container.read(connectionStateProvider.notifier) as _Connection;
      final lifecycle =
          container.read(appLifecycleProvider.notifier) as _Lifecycle;
      lifecycle.setLifecycle(AppLifecycleState.paused);
      connection.setStatus(ConnectionStatus.reconnecting);
      connection.setStatus(ConnectionStatus.connected);
      await pumpEventQueue();
      expect(methods(), ['enableNotification', 'disableNotification']);
      lifecycle.setLifecycle(AppLifecycleState.hidden);
      lifecycle.setLifecycle(AppLifecycleState.inactive);
      lifecycle.setLifecycle(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(methods().last, 'enableNotification');
      expect(
        methods().where((method) => method == 'enableNotification').length,
        2,
      );
    },
  );

  test(
    'closing the notification shade cannot restore dismissed controls',
    () async {
      final container = await create();
      final connection =
          container.read(connectionStateProvider.notifier) as _Connection;
      final lifecycle =
          container.read(appLifecycleProvider.notifier) as _Lifecycle;
      connection.setStatus(ConnectionStatus.reconnecting);
      lifecycle.setLifecycle(AppLifecycleState.inactive);
      lifecycle.setLifecycle(AppLifecycleState.resumed);
      connection.setStatus(ConnectionStatus.connected);
      await pumpEventQueue();
      expect(methods(), ['enableNotification', 'disableNotification']);
    },
  );

  test('returning while offline waits for a healthy connection', () async {
    final container = await create();
    final connection =
        container.read(connectionStateProvider.notifier) as _Connection;
    final lifecycle =
        container.read(appLifecycleProvider.notifier) as _Lifecycle;
    connection.setStatus(ConnectionStatus.reconnecting);
    connection.setStatus(ConnectionStatus.offline);
    lifecycle.setLifecycle(AppLifecycleState.paused);
    lifecycle.setLifecycle(AppLifecycleState.resumed);
    connection.setStatus(ConnectionStatus.reconnecting);
    await pumpEventQueue();
    expect(
      methods().where((method) => method == 'enableNotification').length,
      1,
    );
    connection.setStatus(ConnectionStatus.connected);
    await pumpEventQueue();
    expect(
      methods().where((method) => method == 'enableNotification').length,
      2,
    );
  });

  test('an explicit retry can restore controls after reconnect', () async {
    final container = await create();
    final connection =
        container.read(connectionStateProvider.notifier) as _Connection;
    connection.setStatus(ConnectionStatus.reconnecting);
    connection.setStatus(ConnectionStatus.offline);
    container.read(manualReconnectEpochProvider.notifier).increment();
    connection.setStatus(ConnectionStatus.reconnecting);
    await pumpEventQueue();
    expect(
      methods().where((method) => method == 'enableNotification').length,
      1,
    );
    connection.setStatus(ConnectionStatus.connected);
    await pumpEventQueue();
    expect(
      methods().where((method) => method == 'enableNotification').length,
      2,
    );
  });

  test(
    'returning to the app re-enables after a native-only socket failure',
    () async {
      final container = await create();
      final lifecycle =
          container.read(appLifecycleProvider.notifier) as _Lifecycle;
      // The native socket can drop while Flutter still believes it is connected.
      lifecycle.setLifecycle(AppLifecycleState.paused);
      lifecycle.setLifecycle(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(methods(), ['enableNotification', 'enableNotification']);
    },
  );
}
