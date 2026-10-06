import 'dart:async';
import 'dart:convert';

import 'package:nsd/nsd.dart' as nsd;

import 'discovery_grouping.dart';
import 'discovery_probe.dart';
import 'discovery_types.dart';

/// Apple's Bonjour API requires Local Network permission, but no raw
/// multicast entitlement. Used for normal discovery as well as BLE handoff.
class BonjourDiscoveryNotifier extends DiscoveryNotifier {
  final Future<nsd.Discovery> Function(String, {nsd.IpLookupType ipLookupType})
  startDiscovery;
  final Future<void> Function(nsd.Discovery) stopDiscovery;
  final Future<int> Function(String, int) probe;
  nsd.Discovery? _discovery;
  void Function()? _listener;
  Timer? _timer;
  int _generation = 0;
  int _revision = 0;

  BonjourDiscoveryNotifier({
    this.startDiscovery = nsd.startDiscovery,
    this.stopDiscovery = nsd.stopDiscovery,
    this.probe = probeServerEndpoint,
  });

  bool _current(int generation) => ref.mounted && generation == _generation;

  nsd.Discovery? _detach() {
    _timer?.cancel();
    _timer = null;
    final discovery = _discovery;
    if (_listener != null) discovery?.removeListener(_listener!);
    _listener = null;
    _discovery = null;
    return discovery;
  }

  @override
  DiscoveryState build() {
    ref.onDispose(() {
      ++_generation;
      final discovery = _detach();
      if (discovery != null) {
        unawaited(stopDiscovery(discovery).catchError((_) {}));
      }
    });
    return const DiscoveryState();
  }

  @override
  Future<void> startScan() async {
    final generation = ++_generation;
    final previous = _detach();
    state = const DiscoveryState(isScanning: true);
    try {
      if (previous != null) {
        await stopDiscovery(previous).catchError((_) {});
      }
      if (!_current(generation)) return;
      final discovery = await startDiscovery(
        '_kalinkaplayer._tcp',
        ipLookupType: nsd.IpLookupType.any,
      );
      if (!_current(generation)) {
        await stopDiscovery(discovery);
        return;
      }
      _discovery = discovery;
      _listener = () => unawaited(_update(discovery, generation));
      discovery.addListener(_listener!);
      unawaited(_update(discovery, generation));
      _timer = Timer(const Duration(seconds: 7), stopScan);
    } catch (_) {
      if (_current(generation)) {
        state = const DiscoveryState(
          error:
              'Could not discover players. Allow Local Network access in Settings and check your Wi-Fi.',
        );
      }
    }
  }

  Future<void> _update(nsd.Discovery discovery, int generation) async {
    if (!_current(generation)) return;
    final revision = ++_revision;
    final probes = <(String, int), Future<int>>{};
    final instances = await Future.wait([
      for (final service in discovery.services)
        if (service.port != null && service.port! > 0)
          () async {
            final endpoints = await Future.wait([
              for (final address in service.addresses ?? [])
                () async {
                  final host = address.address;
                  final port = service.port!;
                  final latency = await probes.putIfAbsent((
                    host,
                    port,
                  ), () => _latency(host, port));
                  return ServerEndpoint(
                    host: host,
                    port: port,
                    latencyMs: latency,
                  );
                }(),
            ]);
            return ResolvedInstance(
              instanceName: service.name ?? service.host ?? '',
              label: service.name ?? 'Kalinka box',
              endpoints: endpoints,
              serverId: _txt(service, 'server_id'),
              displayName: _txt(service, 'display_name'),
              version: _txt(service, 'server_version'),
            );
          }(),
    ]);
    if (!_current(generation) || revision != _revision) return;
    state = state.copyWith(servers: groupResolvedInstances(instances));
  }

  Future<int> _latency(String host, int port) async {
    try {
      return await probe(host, port);
    } catch (_) {
      return unreachableLatencyMs;
    }
  }

  String? _txt(nsd.Service service, String name) {
    final value = service.txt?[name];
    return value == null ? null : utf8.decode(value, allowMalformed: true);
  }

  @override
  Future<void> stopScan() async {
    ++_generation;
    final discovery = _detach();
    if (ref.mounted) state = state.copyWith(isScanning: false);
    if (discovery != null) {
      await stopDiscovery(discovery).catchError((_) {});
    }
  }

  @override
  Future<void> rescan() => startScan();
}
