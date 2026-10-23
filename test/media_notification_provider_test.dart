import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/media_notification_provider.dart';

class _Connection extends ConnectionStateNotifier {
  _Connection(this.initial);
  final ConnectionStatus initial;

  @override
  ConnectionStatus build() => initial;

  void setStatus(ConnectionStatus value) => state = value;
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
    Map<String, Object> server = const {
      'Kalinka.host': 'server.test',
      'Kalinka.port': 8000,
    },
  }) async {
    SharedPreferences.setMockInitialValues(server);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        connectionStateProvider.overrideWith(() => _Connection(status)),
      ],
    );
    containers.add(container);
    container.read(mediaNotificationProvider);
    await pumpEventQueue();
    return container;
  }

  List<String> methods() => calls.map((call) => call.method).toList();
  int enables() => methods().where((m) => m == 'enableNotification').length;

  void setStatus(ProviderContainer container, ConnectionStatus status) =>
      (container.read(connectionStateProvider.notifier) as _Connection)
          .setStatus(status);

  test('reaching the server turns the notification on', () async {
    final container = await create(status: ConnectionStatus.connecting);
    expect(enables(), 0);
    setStatus(container, ConnectionStatus.connected);
    await pumpEventQueue();
    expect(methods().last, 'enableNotification');
    expect(calls.last.arguments, {
      'host': 'server.test',
      'port': 8000,
      'scheme': 'http',
    });
  });

  test('a server behind TLS is handed over with its scheme', () async {
    await create(
      server: {
        'Kalinka.host': 'demo.test',
        'Kalinka.port': 443,
        'Kalinka.scheme': 'https',
      },
    );
    expect(calls.last.arguments, {
      'host': 'demo.test',
      'port': 443,
      'scheme': 'https',
    });
  });

  test('nothing is enabled without a server', () async {
    await create(server: const {});
    expect(enables(), 0);
  });

  test('the app losing its connection leaves it to the notification\'s, '
      'and each reconnection turns it on again', () async {
    final container = await create();
    calls.clear();
    for (final status in [
      ConnectionStatus.reconnecting,
      ConnectionStatus.offline,
    ]) {
      setStatus(container, status);
    }
    await pumpEventQueue();
    expect(calls, isEmpty);
    setStatus(container, ConnectionStatus.connected);
    await pumpEventQueue();
    expect(methods(), ['enableNotification']);
  });

  test('disconnecting from the server turns the notification off', () async {
    final container = await create();
    await container.read(connectionSettingsProvider.notifier).clearDevice();
    await pumpEventQueue();
    expect(methods().last, 'disableNotification');
  });

  test('another server chosen while connected waits for the app', () async {
    final container = await create();
    await container
        .read(connectionSettingsProvider.notifier)
        .setDevice('Other', 'other.test', 8001);
    await pumpEventQueue();
    expect(methods().last, 'disableNotification');
  });

  test('another server is followed once the app reaches it', () async {
    final container = await create();
    setStatus(container, ConnectionStatus.connecting);
    await container
        .read(connectionSettingsProvider.notifier)
        .setDevice('Other', 'other.test', 8001);
    await pumpEventQueue();
    expect(methods().last, 'disableNotification');
    setStatus(container, ConnectionStatus.connected);
    await pumpEventQueue();
    expect(methods().last, 'enableNotification');
    expect(calls.last.arguments, {
      'host': 'other.test',
      'port': 8001,
      'scheme': 'http',
    });
  });
}
