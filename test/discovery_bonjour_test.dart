import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/providers/discovery_notifier_bonjour.dart';
import 'package:kalinka/providers/discovery_probe.dart';
import 'package:kalinka/providers/discovery_types.dart';
import 'package:nsd/nsd.dart' as nsd;

class _Discovery extends nsd.Discovery {
  _Discovery(super.id);
  bool get hasDiscoveryListeners => hasListeners;
}

nsd.Service _service(String name, List<String> addresses, {String? serverId}) =>
    nsd.Service(
      name: name,
      port: 8000,
      addresses: addresses.map(InternetAddress.new).toList(),
      txt: serverId == null
          ? null
          : {
              'server_id': Uint8List.fromList(utf8.encode(serverId)),
              'display_name': Uint8List.fromList(utf8.encode('Living room')),
            },
    );

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  late ProviderContainer container;
  late NotifierProvider<BonjourDiscoveryNotifier, DiscoveryState> provider;
  late List<_Discovery> discoveries;
  late List<nsd.Discovery> stopped;
  late List<nsd.IpLookupType> lookups;
  late Future<int> Function(String, int) probe;
  late Future<void> Function(nsd.Discovery) stop;

  setUp(() {
    discoveries = [];
    stopped = [];
    lookups = [];
    probe = (_, _) async => 5;
    stop = (_) async {};
    provider = NotifierProvider<BonjourDiscoveryNotifier, DiscoveryState>(
      () => BonjourDiscoveryNotifier(
        startDiscovery: (type, {ipLookupType = nsd.IpLookupType.none}) async {
          expect(type, '_kalinkaplayer._tcp');
          lookups.add(ipLookupType);
          final discovery = _Discovery('scan-${discoveries.length}');
          discoveries.add(discovery);
          return discovery;
        },
        stopDiscovery: (discovery) async {
          stopped.add(discovery);
          await stop(discovery);
        },
        probe: (host, port) => probe(host, port),
      ),
    );
    container = ProviderContainer();
  });
  tearDown(() => container.dispose());

  test(
    'Bonjour resolves both families and retains an IPv6-only player',
    () async {
      await container.read(provider.notifier).startScan();
      discoveries.single.add(_service('IPv6 player', ['2001:db8::8']));
      await _flush();
      expect(lookups, [nsd.IpLookupType.any]);
      expect(container.read(provider).servers.single.host, '2001:db8::8');
    },
  );

  test(
    'reachable interface wins and failed endpoints remain as alternates',
    () async {
      final pending = <String, Completer<int>>{};
      probe = (host, port) {
        expect(port, 8000);
        return pending.putIfAbsent(host, Completer<int>.new).future;
      };
      await container.read(provider.notifier).startScan();
      discoveries.single.add(
        _service('Box Ethernet', ['192.0.2.8'], serverId: 'box'),
      );
      discoveries.single.add(
        _service('Box Wi-Fi', ['2001:db8::8', '192.0.2.9'], serverId: 'box'),
      );
      expect(
        pending.keys,
        containsAll(['192.0.2.8', '2001:db8::8', '192.0.2.9']),
      );
      pending['192.0.2.8']!.complete(unreachableLatencyMs);
      pending['2001:db8::8']!.complete(30);
      pending['192.0.2.9']!.complete(12);
      await _flush();
      final server = container.read(provider).servers.single;
      expect(server.name, 'Living room');
      expect(server.host, '192.0.2.9');
      expect(server.endpoints.map((e) => e.host), [
        '192.0.2.9',
        '2001:db8::8',
        '192.0.2.8',
      ]);
      expect(server.endpoints.last.latencyMs, unreachableLatencyMs);
    },
  );

  test(
    'late results from a stopped scan cannot overwrite a new scan',
    () async {
      final pending = Completer<int>();
      probe = (host, _) =>
          host == '192.0.2.1' ? pending.future : Future.value(5);
      final notifier = container.read(provider.notifier);
      await notifier.startScan();
      discoveries.first.add(_service('Old box', ['192.0.2.1']));
      await notifier.rescan();
      discoveries.last.add(_service('New box', ['192.0.2.2']));
      await _flush();
      pending.complete(1);
      await _flush();
      expect(container.read(provider).servers.single.name, 'New box');
      expect(stopped, [discoveries.first]);
    },
  );

  test(
    'late results cannot restore a service removed during the same scan',
    () async {
      final pending = Completer<int>();
      probe = (host, _) =>
          host == '192.0.2.1' ? pending.future : Future.value(5);
      await container.read(provider.notifier).startScan();
      final old = _service('Old box', ['192.0.2.1']);
      discoveries.single.add(old);
      discoveries.single.remove(old);
      discoveries.single.add(_service('New box', ['192.0.2.2']));
      await _flush();
      pending.complete(1);
      await _flush();
      expect(container.read(provider).servers.single.name, 'New box');
    },
  );

  test(
    'a slow stop cannot end a newer scan or revive an older rescan',
    () async {
      final pending = Completer<void>();
      final notifier = container.read(provider.notifier);
      await notifier.startScan();
      stop = (_) => pending.future;
      final obsolete = notifier.rescan();
      await notifier.rescan();
      pending.complete();
      await obsolete;
      expect(discoveries, hasLength(2));
      expect(container.read(provider).isScanning, isTrue);
    },
  );

  test('probe failure keeps the endpoint available for manual retry', () async {
    probe = (_, _) async => throw StateError('unreachable');
    await container.read(provider.notifier).startScan();
    discoveries.single.add(_service('Box', ['192.0.2.1']));
    await _flush();
    expect(
      container.read(provider).servers.single.latencyMs,
      unreachableLatencyMs,
    );
  });

  test(
    'disposing while probes are pending does not publish or retain listeners',
    () async {
      final pending = Completer<int>();
      probe = (_, _) => pending.future;
      await container.read(provider.notifier).startScan();
      final discovery = discoveries.single;
      discovery.add(_service('Box', ['192.0.2.1']));
      container.dispose();
      pending.complete(5);
      await _flush();
      expect(discovery.hasDiscoveryListeners, isFalse);
      expect(stopped, [discovery]);
    },
  );

  test(
    'shared HTTP probe distinguishes reachable and closed endpoints',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      server.listen((request) {
        expect(request.uri.path, '/server/modules');
        request.response.write('{}');
        unawaited(request.response.close());
      });
      try {
        expect(
          await probeServerEndpoint('127.0.0.1', port),
          lessThan(unreachableLatencyMs),
        );
      } finally {
        await server.close(force: true);
      }
      expect(
        await probeServerEndpoint('127.0.0.1', port),
        unreachableLatencyMs,
      );
    },
  );
}
