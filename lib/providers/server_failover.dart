/// Finds a server again at another of its addresses once the one in use
/// stops answering: a Core that moved from cable to Wi-Fi, or got a new lease.
library;

import 'dart:async';

import 'package:dio/dio.dart' show BaseOptions, Dio, DioException;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'discovery_provider.dart';
import 'server_address.dart';
import 'server_endpoints.dart';

/// Whether [status] says the route is missing, as on a server older than it.
/// Any other refusal, such as 401 or 403, says nothing about the server.
bool _routeMissing(int? status) => status == 404 || status == 405;

/// The id the server behind [client] reports, or null from a server too old
/// to report one.
Future<String?> askServerId(Dio client) async {
  try {
    final data = (await client.get('/renderer/sessions')).data;
    final id = data is Map ? data['server_id'] : null;
    return id is String && id.isNotEmpty ? id : null;
  } on DioException catch (e) {
    if (_routeMissing(e.response?.statusCode)) return null;
    rethrow;
  }
}

/// Asks the server at an address which server it is; fails when nothing
/// answers there.
typedef ServerIdProbe = Future<String?> Function(ServerAddress address);

/// About what ARP takes to give up on an address that left the network.
const _probeTimeout = Duration(seconds: 3);

final serverIdProbeProvider = Provider<ServerIdProbe>(
  (ref) => (address) async {
    final client = Dio(
      BaseOptions(
        baseUrl: Uri(
          scheme: address.scheme,
          host: address.host,
          port: address.port,
        ).toString(),
        connectTimeout: _probeTimeout,
        receiveTimeout: _probeTimeout,
      ),
    );
    try {
      return await askServerId(client);
    } finally {
      client.close(force: true);
    }
  },
);

/// A browse that never finishes must not hold the search.
const _searchTimeout = Duration(seconds: 10);

/// Looks for the server [serverId] away from [from]: at its other saved
/// addresses, and at any a fresh mDNS browse finds it announcing, all asked at
/// once. Completes with the first that answers as that server, or null.
Future<ServerAddress?> findServerElsewhere(
  Ref ref, {
  required String serverId,
  required ServerAddress from,
}) {
  final askId = ref.read(serverIdProbeProvider);
  final found = Completer<ServerAddress?>();
  final asked = <ServerAddress>{from};
  var asking = 0;
  var browsing = true;

  void endIfNothingLeft() {
    if (!browsing && asking == 0 && !found.isCompleted) found.complete(null);
  }

  Future<void> ask(String host, int port) async {
    final address = (scheme: 'http', host: host, port: port);
    if (!asked.add(address)) return;
    asking++;
    try {
      // Another server may have the address now, or one too old to say.
      if (await askId(address) == serverId && !found.isCompleted) {
        found.complete(address);
      }
    } catch (_) {
      // Nothing answers there.
    } finally {
      asking--;
      endIfNothingLeft();
    }
  }

  for (final endpoint
      in ref.read(serverEndpointStoreProvider).endpointsOf(serverId)) {
    unawaited(ask(endpoint.host, endpoint.port));
  }
  final browse = ref.listen<DiscoveryState>(discoveryProvider, (_, next) {
    for (final server in next.servers) {
      if (server.serverId != serverId) continue;
      unawaited(ask(server.host, server.port));
      for (final endpoint in server.endpoints) {
        unawaited(ask(endpoint.host, endpoint.port));
      }
    }
    if (!next.isScanning) {
      browsing = false;
      endIfNothingLeft();
    }
  });
  unawaited(ref.read(discoveryProvider.notifier).startScan());
  return found.future
      .timeout(_searchTimeout, onTimeout: () => null)
      .whenComplete(browse.close);
}
