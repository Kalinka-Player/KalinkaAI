import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/presentation_schema.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/settings_provider.dart';
import 'package:kalinka/providers/websocket_provider.dart';
import 'package:kalinka/widgets/server_chip.dart';

const _name = 'base_config.server.service_name';

class _Api implements KalinkaPlayerProxy {
  Map<String, dynamic> values = {_name: 'Living room'};
  Completer<Map<String, dynamic>>? pending;
  bool fail = false;

  @override
  Future<PresentationSchema> getSettingsSchema() async =>
      const PresentationSchema(schemaVersion: 'v1', pages: []);

  @override
  Future<Map<String, dynamic>> getSettings() async {
    if (fail) throw StateError('Server unavailable');
    return pending == null ? {'values': values} : pending!.future;
  }

  @override
  Future<List<ConfigIssue>> validateSettings({
    required String schemaVersion,
    required Map<String, dynamic> changes,
  }) async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Connected extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

ProviderContainer _container(SharedPreferences prefs, _Api api) {
  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      kalinkaProxyProvider.overrideWithValue(api),
      connectionStateProvider.overrideWith(_Connected.new),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'Kalinka.name': 'Discovered name',
      'Kalinka.host': 'kalinka.local',
      'Kalinka.port': 443,
      'Kalinka.scheme': 'https',
    });
    prefs = await SharedPreferences.getInstance();
  });

  testWidgets(
    'settings reload refreshes the indicator and remembered name, not drafts',
    (tester) async {
      final api = _Api();
      final container = _container(prefs, api);
      final address = container.read(connectionSettingsProvider).address;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: ServerChip())),
        ),
      );
      expect(find.text('Discovered name'), findsOneWidget);
      final settings = container.read(settingsProvider.notifier);
      await settings.loadConfig();
      await tester.pumpAndSettle();
      expect(find.text('Living room'), findsOneWidget);
      expect(prefs.getString('Kalinka.name'), 'Living room');
      expect(container.read(connectionSettingsProvider).address, address);
      expect(container.read(settingsProvider).values[_name], 'Living room');

      settings.stageChange(_name, 'Unsaved draft');
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Living room'), findsOneWidget);
      expect(prefs.getString('Kalinka.name'), 'Living room');

      // A later read reflects a rename made by this or another client.
      api.values = {_name: 'Kitchen'};
      await settings.loadConfig();
      await tester.pumpAndSettle();
      expect(find.text('Kitchen'), findsOneWidget);
      expect(prefs.getString('Kalinka.name'), 'Kitchen');
      final restored = _container(prefs, api);
      expect(restored.read(connectionSettingsProvider).name, 'Kitchen');
    },
  );

  test('even an unchanged options refresh updates the name and keeps pending edits', () async {
    final api = _Api();
    final container = _container(prefs, api);
    final settings = container.read(settingsProvider.notifier);
    await settings.loadConfig();
    settings.stageChange(_name, 'Unsaved draft');
    api.values = {_name: 'Renamed elsewhere'};
    await settings.refreshOptions();
    expect(
      container.read(connectionSettingsProvider).name,
      'Renamed elsewhere',
    );
    expect(container.read(settingsProvider).stagedChanges, {
      _name: 'Unsaved draft',
    });
    expect(prefs.getString('Kalinka.name'), 'Renamed elsewhere');
  });

  for (final value in [null, '', '   ', 42]) {
    test(
      'missing or invalid server name preserves the saved label: $value',
      () async {
        final api = _Api()..values = {_name: ?value};
        final container = _container(prefs, api);
        await container.read(settingsProvider.notifier).loadConfig();
        expect(
          container.read(connectionSettingsProvider).name,
          'Discovered name',
        );
        expect(prefs.getString('Kalinka.name'), 'Discovered name');
      },
    );
  }

  test('failed settings reads leave the name alone', () async {
    final container = _container(prefs, _Api()..fail = true);
    await container.read(settingsProvider.notifier).loadConfig();
    expect(container.read(connectionSettingsProvider).name, 'Discovered name');
    expect(prefs.getString('Kalinka.name'), 'Discovered name');
  });

  for (final optionsOnly in [false, true]) {
    test(
      'an old server response cannot rename the new connection: options $optionsOnly',
      () async {
        final pending = Completer<Map<String, dynamic>>();
        final container = _container(prefs, _Api()..pending = pending);
        final settings = container.read(settingsProvider.notifier);
        final reading = optionsOnly
            ? settings.refreshOptions()
            : settings.loadConfig();
        await container
            .read(connectionSettingsProvider.notifier)
            .setDevice('Other server', 'other.local', 8000);
        pending.complete({
          'values': {_name: 'Old server response'},
        });
        await reading;
        expect(container.read(connectionSettingsProvider).name, 'Other server');
        expect(prefs.getString('Kalinka.name'), 'Other server');
      },
    );
  }

  test('onboarding refreshes its label without overwriting the remembered connection', () async {
    final container = _container(prefs, _Api());
    final connection = container.read(connectionSettingsProvider.notifier);
    // Even an ephemeral visit to the same address must remain uncommitted.
    connection.setDeviceEphemeral(
      'Temporary',
      'kalinka.local',
      443,
      scheme: 'https',
    );
    await container.read(settingsProvider.notifier).loadConfig();
    expect(container.read(connectionSettingsProvider).name, 'Living room');
    expect(prefs.getString('Kalinka.name'), 'Discovered name');
    await connection.persist();
    expect(prefs.getString('Kalinka.name'), 'Living room');
  });

  test(
    'reloading the same name does not notify connection consumers again',
    () async {
      final container = _container(prefs, _Api());
      var changes = 0;
      final subscription = container.listen(
        connectionSettingsProvider,
        (_, _) => changes++,
      );
      addTearDown(subscription.close);
      final settings = container.read(settingsProvider.notifier);
      await settings.loadConfig();
      expect(changes, 1);
      await settings.loadConfig();
      expect(changes, 1);
    },
  );

  test(
    'a refreshed name retains the HTTP client and healthy event socket',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <WebSocket>[];
      final requests = server.listen((request) async {
        sockets.add(await WebSocketTransformer.upgrade(request));
      });
      final container = _container(prefs, _Api());
      addTearDown(() async {
        container.invalidate(queueWebSocketProvider);
        await Future.wait(sockets.map((socket) => socket.close()));
        await requests.cancel();
        await server.close(force: true);
      });
      await container
          .read(connectionSettingsProvider.notifier)
          .setDevice('Discovered name', server.address.address, server.port);
      final http = container.read(httpClientProvider);
      final socket = await container.read(queueWebSocketProvider.future);
      await container.read(settingsProvider.notifier).loadConfig();
      expect(container.read(connectionSettingsProvider).name, 'Living room');
      expect(container.read(httpClientProvider), same(http));
      expect(await container.read(queueWebSocketProvider.future), same(socket));
      expect(sockets, hasLength(1));
    },
  );
}
