import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/data_model.dart' show ModulesAndDevices;
import 'package:kalinka/providers/box_control_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/discovery_types.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/server_address.dart';
import 'package:kalinka/providers/server_connect.dart';
import 'package:kalinka/providers/server_endpoints.dart';

import 'support/server_answer.dart';

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

      store.remember('core-1', [_at('10.0.0.3'), _at('10.0.0.4')]);
      now = now.add(const Duration(hours: 1));
      store.remember('core-1', [_at('10.0.0.20')]);

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
      store.remember('core-1', [_at('10.0.0.3'), _at('10.0.0.4')]);

      now = now.add(const Duration(minutes: 5));
      store.remember('core-1', [_at('10.0.0.4'), _at('10.0.0.4')]);

      final endpoints = store.endpointsOf('core-1');
      expect(_hosts(endpoints), ['10.0.0.4:8000', '10.0.0.3:8000']);
      expect(endpoints.first.lastSeen, now);
    });

    test('keeps the most recently seen eight', () async {
      var now = DateTime(2026, 10, 24);
      final (store, _) = await _store({}, now: () => now);
      for (var i = 1; i <= 10; i++) {
        now = now.add(const Duration(days: 1));
        store.remember('core-1', [_at('10.0.0.$i')]);
      }

      final endpoints = store.endpointsOf('core-1');
      expect(endpoints, hasLength(ServerEndpointStore.maxEndpoints));
      expect(endpoints.first.host, '10.0.0.10');
      expect(endpoints.last.host, '10.0.0.3');
    });

    test('an address behind TLS is not kept', () async {
      final (store, prefs) = await _store({});
      store.remember('core-1', [
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

      test('it becomes the first of the server last seen there', () async {
        final (store, _) = await _store(saved);
        store.migrateSavedAddress();
        expect(_hosts(store.endpointsOf('core-1')), ['10.0.0.3:8000']);
        expect(store.endpointsOf('core-2'), isEmpty);
        expect(store.serverIdAt(_at('10.0.0.3')), 'core-1');
      });

      test('it is kept once the server is seen elsewhere', () async {
        final (store, prefs) = await _store(saved);
        store.migrateSavedAddress();
        store.remember('core-1', [_at('10.0.0.4')]);

        await prefs.remove('Kalinka.host');
        expect(_hosts(store.endpointsOf('core-1')), [
          '10.0.0.4:8000',
          '10.0.0.3:8000',
        ]);
      });

      test('a server that has addresses already keeps them', () async {
        final (store, _) = await _store(saved);
        store.remember('core-1', [_at('10.0.0.4')]);
        store.migrateSavedAddress();
        expect(_hosts(store.endpointsOf('core-1')), ['10.0.0.4:8000']);
      });

      test('no server seen there, or one behind TLS, gives none', () async {
        final (unseen, _) = await _store({
          'Kalinka.host': '10.0.0.3',
          'Kalinka.port': 8000,
        });
        unseen.migrateSavedAddress();
        expect(unseen.endpointsOf('core-1'), isEmpty);

        final (tls, _) = await _store({...saved, 'Kalinka.scheme': 'https'});
        tls.migrateSavedAddress();
        expect(tls.endpointsOf('core-1'), isEmpty);
      });
    });

    group('serverIdAt', () {
      test('names the server last to say so at one of its addresses', () async {
        final (store, _) = await _store({});
        store.confirmedAt('core-1', _at('10.0.0.3'));
        expect(store.serverIdAt(_at('10.0.0.3')), 'core-1');
        expect(store.serverIdAt(_at('10.0.0.3', 8001)), isNull);
        expect(store.serverIdAt(_at('10.0.0.9')), isNull);
      });

      test('an address discovery only listed names no server', () async {
        final (store, _) = await _store({});
        store.remember('core-1', [_at('10.0.0.3')]);
        expect(store.serverIdAt(_at('10.0.0.3')), isNull);
      });

      test('a server without an id answering there names none, until the '
          'other says so there again', () async {
        final (store, prefs) = await _store({});
        store.confirmedAt('core-1', _at('10.0.0.3'));
        store.confirmedAt('core-1', _at('10.0.0.4'));

        store.unidentifiedAt(_at('10.0.0.3'));
        expect(store.serverIdAt(_at('10.0.0.3')), isNull);
        expect(_hosts(store.endpointsOf('core-1')), ['10.0.0.4:8000']);
        // Pins and box controls still go by the record.
        expect(prefs.getString('Kalinka.serverIdAt.10.0.0.3:8000'), 'core-1');

        store.confirmedAt('core-1', _at('10.0.0.3'));
        expect(store.serverIdAt(_at('10.0.0.3')), 'core-1');
      });

      test(
        'a saved address a server without an id answers at names none',
        () async {
          final (store, _) = await _store({
            'Kalinka.host': '10.0.0.3',
            'Kalinka.port': 8000,
            'Kalinka.serverIdAt.10.0.0.3:8000': 'core-1',
          });
          store.migrateSavedAddress();
          store.unidentifiedAt(_at('10.0.0.3'));
          store.migrateSavedAddress();
          expect(store.serverIdAt(_at('10.0.0.3')), isNull);
        },
      );

      test('another server saying so there takes the address', () async {
        final (store, _) = await _store({});
        store.confirmedAt('core-1', _at('10.0.0.3'));
        store.confirmedAt('core-2', _at('10.0.0.3'));
        expect(store.serverIdAt(_at('10.0.0.3')), 'core-2');
        expect(store.endpointsOf('core-1'), isEmpty);
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

    group('a server chosen from discovery', () {
      final announced = [_at('10.0.0.3'), _at('10.0.0.4')];

      test('has what it announced kept once it says it is that one', () async {
        final (store, _) = await _store({});
        store.chose('core-1', at: _at('10.0.0.3'), addresses: announced);
        expect(store.endpointsOf('core-1'), isEmpty);

        store.confirmedAt('core-1', _at('10.0.0.3'));
        expect(_hosts(store.endpointsOf('core-1')), [
          '10.0.0.3:8000',
          '10.0.0.4:8000',
        ]);
      });

      for (final other in ['core-2', null]) {
        test('keeps nothing it announced when '
            '${other ?? 'a server without an id'} answers there', () async {
          final (store, _) = await _store({});
          store.chose('core-1', at: _at('10.0.0.3'), addresses: announced);
          if (other == null) {
            store.unidentifiedAt(_at('10.0.0.3'));
          } else {
            store.confirmedAt(other, _at('10.0.0.3'));
          }

          store.confirmedAt('core-1', _at('10.0.0.9'));
          store.confirmedAt('core-1', _at('10.0.0.3'));
          expect(_hosts(store.endpointsOf('core-1')), [
            '10.0.0.3:8000',
            '10.0.0.9:8000',
          ]);
        });
      }
    });
  });

  group('choosing a discovered server', () {
    late ServersByHost servers;

    setUp(() => servers = ServersByHost());

    Future<SharedPreferences> choose(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      late WidgetRef ref;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPrefsProvider.overrideWithValue(prefs),
            kalinkaProxyProvider.overrideWithValue(_Server()),
            servers.client,
          ],
          child: Consumer(
            builder: (_, widgetRef, _) {
              ref = widgetRef;
              widgetRef.watch(rememberServerIdentityProvider);
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
      await tester.pump(const Duration(milliseconds: 1));
      return prefs;
    }

    testWidgets('keeps every address it announced once it says who it is', (
      tester,
    ) async {
      servers.ids['10.0.0.3'] = 'core-1';
      final prefs = await choose(tester);

      expect(servers.asked, 1);
      expect(_hosts(ServerEndpointStore(prefs).endpointsOf('core-1')), [
        '10.0.0.3:8000',
        '10.0.0.4:8000',
      ]);
    });

    testWidgets('keeps nothing it announced when another server answers', (
      tester,
    ) async {
      servers.ids['10.0.0.3'] = 'core-9';
      final prefs = await choose(tester);

      final store = ServerEndpointStore(prefs);
      expect(store.endpointsOf('core-1'), isEmpty);
      expect(_hosts(store.endpointsOf('core-9')), ['10.0.0.3:8000']);
    });

    testWidgets('keeps nothing when a server without an id answers', (
      tester,
    ) async {
      final prefs = await choose(tester);

      expect(servers.asked, 1);
      expect(ServerEndpointStore(prefs).endpointsOf('core-1'), isEmpty);
      expect(prefs.getString('Kalinka.serverIdAt.10.0.0.3:8000'), isNull);
    });
  });
}
