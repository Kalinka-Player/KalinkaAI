import 'dart:async';
import 'dart:convert';

import 'package:nsd/nsd.dart' as nsd;

import 'discovery_grouping.dart';
import 'discovery_types.dart';

/// Apple's Bonjour API requires Local Network permission, but no raw
/// multicast entitlement. Used for normal discovery as well as BLE handoff.
class BonjourDiscoveryNotifier extends DiscoveryNotifier {
  nsd.Discovery? _discovery;
  Timer? _timer;
  int _generation = 0;

  @override
  DiscoveryState build() {
    ref.onDispose(() {
      ++_generation;
      _timer?.cancel();
      final discovery = _discovery;
      _discovery = null;
      if (discovery != null) {
        unawaited(nsd.stopDiscovery(discovery).catchError((_) {}));
      }
    });
    return const DiscoveryState();
  }

  @override
  Future<void> startScan() async {
    await stopScan();
    if (!ref.mounted) return;
    final generation = ++_generation;
    state = const DiscoveryState(isScanning: true);
    try {
      final discovery = await nsd.startDiscovery(
        '_kalinkaplayer._tcp',
        ipLookupType: nsd.IpLookupType.v4,
      );
      if (generation != _generation) {
        await nsd.stopDiscovery(discovery);
        return;
      }
      _discovery = discovery;
      void update() {
        if (generation != _generation) return;
        state = state.copyWith(
          servers: groupResolvedInstances([
            for (final service in discovery.services)
              if (service.port != null)
                ResolvedInstance(
                  instanceName: service.name ?? service.host ?? '',
                  label: service.name ?? 'Kalinka',
                  endpoints: [
                    for (final address in service.addresses ?? [])
                      ServerEndpoint(
                        host: address.address,
                        port: service.port!,
                        latencyMs: 0,
                      ),
                  ],
                  serverId: _txt(service, 'server_id'),
                  displayName: _txt(service, 'display_name'),
                  version: _txt(service, 'server_version'),
                ),
          ]),
        );
      }

      discovery.addListener(update);
      update();
      _timer = Timer(const Duration(seconds: 7), stopScan);
    } catch (_) {
      if (generation == _generation) {
        state = const DiscoveryState(
          error:
              'Could not discover players. Allow Local Network access in Settings and check your Wi-Fi.',
        );
      }
    }
  }

  String? _txt(nsd.Service service, String name) {
    final value = service.txt?[name];
    return value == null ? null : utf8.decode(value, allowMalformed: true);
  }

  @override
  Future<void> stopScan() async {
    ++_generation;
    _timer?.cancel();
    final discovery = _discovery;
    _discovery = null;
    if (discovery != null) {
      try {
        await nsd.stopDiscovery(discovery);
      } catch (_) {}
    }
    if (ref.mounted) state = state.copyWith(isScanning: false);
  }

  @override
  Future<void> rescan() => startScan();
}
