import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/data_model.dart' show ModulesAndDevices;
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/discovery_types.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/server_address.dart';
import 'package:kalinka/providers/server_connect.dart';
import 'package:kalinka/providers/server_endpoints.dart';

ServerAddress _at(String host, [int port = 8000]) =>
    (scheme: 'http', host: host, port: port);

Future<(ServerEndpointStore, SharedPreferences)> _store(
  Map<String, Object> stored, {
  DateTime Function()? now,
}) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  return (ServerEndpointStore(prefs, now: now), prefs);
}

List<String> _hosts(List<SavedEndpoint> endpoints) => [
  for (final e in endpoints) '${e.host}:${e.port}',
];

class _Server implements KalinkaPlayerProxy {
  @override
  Future<ModulesAndDevices> listModules() async =>
      ModulesAndDevices(inputModules: const [], devices: const []);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  group('ServerEndpointStore', () {
    test('keeps a server\'s addresses under its id, latest first', () async {
      var now = DateTime(2026, 10, 24, 19);
      final (store, prefs) = await _store({}, now: () => now);

      await store.remember('core-1', [_at('10.0.0.3'), _at('10.0.0.4')]);
      now = now.add(const Duration(hours: 1));
      await store.remember('core-1', [_at('10.0.0.20')]);

      final endpoints = store.endpointsOf('core-1');
      expect(_hosts(endpoints), [
        '10.0.0.20:8000',
        '10.0.0.3:8000',
        '10.0.0.4:8000',
      ]);
      expect(endpoints.first.lastSeen, now);
      expect(prefs.getString('Kalinka.servers.v1:core-1'), isNotNull);
      expect(store.endpointsOf('core-2'), isEmpty);
    });

    test('an address seen again moves to the front, once', () async {
      var now = DateTime(2026, 10, 24);
      final (store, _) = await _store({}, now: () => now);
      await store.remember('core-1', [_at('10.0.0.3'), _at('10.0.0.4')]);

      now = now.add(const Duration(minutes: 5));
      await store.remember('core-1', [_at('10.0.0.4'), _at('10.0.0.4')]);

      final endpoints = store.endpointsOf('core-1');
      expect(_hosts(endpoints), ['10.0.0.4:8000', '10.0.0.3:8000']);
      expect(endpoints.first.lastSeen, now);
    });

    test('keeps the most recently seen eight', () async {
      var now = DateTime(2026, 10, 24);
      final (store, _) = await _store({}, now: () => now);
      for (var i = 1; i <= 10; i++) {
        now = now.add(const Duration(days: 1));
        await store.remember('core-1', [_at('10.0.0.$i')]);
      }

      final endpoints = store.endpointsOf('core-1');
      expect(endpoints, hasLength(ServerEndpointStore.maxEndpoints));
      expect(endpoints.first.host, '10.0.0.10');
      expect(endpoints.last.host, '10.0.0.3');
    });

    test('an address behind TLS is not kept', () async {
      final (store, prefs) = await _store({});
      await store.remember('core-1', [
        (scheme: 'https', host: 'kalinka.example', port: 443),
      ]);
      expect(store.endpointsOf('core-1'), isEmpty);
      expect(prefs.getString('Kalinka.servers.v1:core-1'), isNull);
    });

    test('an entry it cannot read is none', () async {
      final (store, _) = await _store({
        'Kalinka.servers.v1:core-1': '{"host": "10.0.0.3"',
        'Kalinka.servers.v1:core-2': '[{"host": "10.0.0.4"}]',
      });
      expect(store.endpointsOf('core-1'), isEmpty);
      expect(store.endpointsOf('core-2'), isEmpty);
    });

    group('from the address saved before', () {
      const saved = {
        'Kalinka.host': '10.0.0.3',
        'Kalinka.port': 8000,
        'Kalinka.serverIdAt.10.0.0.3:8000': 'core-1',
      };

      test('it belongs to the server last seen there', () async {
        final (store, _) = await _store(saved);
        expect(_hosts(store.endpointsOf('core-1')), ['10.0.0.3:8000']);
        expect(store.endpointsOf('core-2'), isEmpty);
      });

      test('it is kept once the server is seen elsewhere', () async {
        final (store, prefs) = await _store(saved);
        await store.remember('core-1', [_at('10.0.0.4')]);

        await prefs.remove('Kalinka.host');
        expect(_hosts(store.endpointsOf('core-1')), [
          '10.0.0.4:8000',
          '10.0.0.3:8000',
        ]);
      });

      test('no server seen there, or one behind TLS, gives none', () async {
        final (unseen, _) = await _store({
          'Kalinka.host': '10.0.0.3',
          'Kalinka.port': 8000,
        });
        expect(unseen.endpointsOf('core-1'), isEmpty);

        final (tls, _) = await _store({...saved, 'Kalinka.scheme': 'https'});
        expect(tls.endpointsOf('core-1'), isEmpty);
      });
    });

    group('serverIdAt', () {
      test('the server that said so at the address wins', () async {
        final (store, _) = await _store({
          'Kalinka.serverIdAt.10.0.0.3:8000': 'core-1',
        });
        await store.remember('core-2', [_at('10.0.0.3')]);
        expect(store.serverIdAt(_at('10.0.0.3')), 'core-1');
      });

      test('failing that, the one most recently chosen there', () async {
        var now = DateTime(2026, 10, 24);
        final (store, _) = await _store({}, now: () => now);
        await store.remember('core-1', [_at('10.0.0.3')]);
        now = now.add(const Duration(days: 1));
        await store.remember('core-2', [_at('10.0.0.3')]);

        expect(store.serverIdAt(_at('10.0.0.3')), 'core-2');
        expect(store.serverIdAt(_at('10.0.0.3', 8001)), isNull);
        expect(store.serverIdAt(_at('10.0.0.9')), isNull);
      });
    });

    test('a server confirming an address records it both ways', () async {
      final (store, prefs) = await _store({
        'Kalinka.serverIdAt.10.0.0.4:8000': 'core-old',
      });
      store.confirmedAt('core-1', _at('10.0.0.4'));
      await pumpEventQueue();

      expect(prefs.getString('Kalinka.serverIdAt.10.0.0.4:8000'), 'core-1');
      expect(_hosts(store.endpointsOf('core-1')), ['10.0.0.4:8000']);
    });
  });

  testWidgets('choosing a discovered server keeps every address it '
      'announced', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    late WidgetRef ref;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          kalinkaProxyProvider.overrideWithValue(_Server()),
        ],
        child: Consumer(
          builder: (_, widgetRef, _) {
            ref = widgetRef;
            return const SizedBox();
          },
        ),
      ),
    );

    await connectToServer(
      ref,
      name: 'Living room',
      address: _at('10.0.0.3'),
      persist: true,
      found: const DiscoveredServer(
        name: 'Living room',
        host: '10.0.0.3',
        port: 8000,
        serverId: 'core-1',
        endpoints: [
          ServerEndpoint(host: '10.0.0.3', port: 8000, latencyMs: 4),
          ServerEndpoint(host: '10.0.0.4', port: 8000, latencyMs: 9999),
        ],
      ),
    );
    await tester.pump();

    expect(_hosts(ServerEndpointStore(prefs).endpointsOf('core-1')), [
      '10.0.0.3:8000',
      '10.0.0.4:8000',
    ]);
  });
}
