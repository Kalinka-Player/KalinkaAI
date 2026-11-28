import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'connection_settings_provider.dart';
import 'server_address.dart';

/// Where the server last seen at [host]:[port] is recorded, so it is still
/// known while that server is down.
String serverIdAtKey(String host, int port) => 'Kalinka.serverIdAt.$host:$port';

/// An address a server was reached or announced at, and when.
class SavedEndpoint {
  final String host;
  final int port;
  final DateTime lastSeen;

  const SavedEndpoint({
    required this.host,
    required this.port,
    required this.lastSeen,
  });

  ServerAddress get address => (scheme: 'http', host: host, port: port);

  @override
  bool operator ==(Object other) =>
      other is SavedEndpoint &&
      other.host == host &&
      other.port == port &&
      other.lastSeen == lastSeen;

  @override
  int get hashCode => Object.hash(host, port, lastSeen);

  @override
  String toString() => 'SavedEndpoint($host:$port, $lastSeen)';
}

/// The addresses each server has been reached at, kept under its id, so the
/// app can follow a server that moved to another of them.
class ServerEndpointStore {
  ServerEndpointStore(this._prefs, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final SharedPreferences _prefs;
  final DateTime Function() _now;

  /// The server last chosen from discovery, with every address it announced,
  /// until it says at the chosen one which server it is.
  ({String serverId, ServerAddress at, List<ServerAddress> addresses})? _chosen;

  static const _prefix = 'Kalinka.servers.v1:';

  /// A cable, Wi-Fi and a few leases; the longest unseen go first.
  static const maxEndpoints = 8;

  static String keyOf(String serverId) => '$_prefix$serverId';

  /// [serverId]'s addresses, the most recently seen first.
  List<SavedEndpoint> endpointsOf(String serverId) =>
      _decode(_prefs.getString(keyOf(serverId)));

  /// Before addresses were kept per server only the connection's own was
  /// saved, under the address; it becomes the first of the server last seen
  /// there.
  void migrateSavedAddress() {
    final host = _prefs.getString(ConnectionSettingsNotifier.sharedPrefHost);
    final port = _prefs.getInt(ConnectionSettingsNotifier.sharedPrefPort);
    final scheme = _prefs.getString(
      ConnectionSettingsNotifier.sharedPrefScheme,
    );
    if (host == null || host.isEmpty || port == null || port <= 0) return;
    final serverId = _prefs.getString(serverIdAtKey(host, port));
    if ((scheme ?? 'http') != 'http' || serverId == null) return;
    if (_prefs.getString(keyOf(serverId)) != null) return;
    _save(serverId, [
      SavedEndpoint(
        host: host,
        port: port,
        lastSeen: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    ]);
  }

  /// Saves that [serverId] is at [addresses] now. Only a server on the local
  /// network, reached over plain HTTP, moves between addresses.
  void remember(String serverId, Iterable<ServerAddress> addresses) {
    final seen = _now();
    final fresh = <SavedEndpoint>[];
    for (final address in addresses) {
      if (address.scheme != 'http' || fresh.any((e) => e.address == address)) {
        continue;
      }
      fresh.add(
        SavedEndpoint(host: address.host, port: address.port, lastSeen: seen),
      );
    }
    if (fresh.isEmpty) return;
    _save(serverId, [
      ...fresh,
      for (final endpoint in endpointsOf(serverId))
        if (!fresh.any((e) => e.address == endpoint.address)) endpoint,
    ]);
  }

  /// [serverId] was chosen from discovery at [at]. What it announced is kept
  /// once it says there that it is that server: another may answer there.
  void chose(
    String serverId, {
    required ServerAddress at,
    required Iterable<ServerAddress> addresses,
  }) {
    _chosen = (serverId: serverId, at: at, addresses: [...addresses]);
  }

  /// Records that the server at [address] said it is [serverId]. The address
  /// is no other server's any more.
  void confirmedAt(String serverId, ServerAddress address) {
    final key = serverIdAtKey(address.host, address.port);
    if (_prefs.getString(key) != serverId) _prefs.setString(key, serverId);
    _leave(address, toServer: serverId);
    final chosen = _chosen;
    if (chosen != null && chosen.at == address) {
      _chosen = null;
      if (chosen.serverId == serverId) {
        remember(serverId, [address, ...chosen.addresses]);
        return;
      }
    }
    remember(serverId, [address]);
  }

  /// A server too old to have an id answered at [address], so no server with
  /// one is followed from there. The address keeps its record: what was kept
  /// there for the server last seen with an id stays that server's.
  void unidentifiedAt(ServerAddress address) {
    if (_chosen?.at == address) _chosen = null;
    _leave(address);
  }

  /// The server to follow from [address]: the last to say there which it is,
  /// unless a server too old to say has answered there since.
  String? serverIdAt(ServerAddress address) {
    final serverId = _prefs.getString(
      serverIdAtKey(address.host, address.port),
    );
    if (serverId == null) return null;
    return endpointsOf(serverId).any((e) => e.address == address)
        ? serverId
        : null;
  }

  /// Takes [address] off every server's addresses but [toServer]'s.
  void _leave(ServerAddress address, {String? toServer}) {
    for (final key in _prefs.getKeys()) {
      if (!key.startsWith(_prefix)) continue;
      final serverId = key.substring(_prefix.length);
      if (serverId == toServer) continue;
      final endpoints = endpointsOf(serverId);
      if (!endpoints.any((e) => e.address == address)) continue;
      _save(serverId, [
        for (final e in endpoints)
          if (e.address != address) e,
      ]);
    }
  }

  void _save(String serverId, Iterable<SavedEndpoint> endpoints) {
    _prefs
        .setString(
          keyOf(serverId),
          jsonEncode([
            for (final e in endpoints.take(maxEndpoints))
              {
                'host': e.host,
                'port': e.port,
                'last_seen': e.lastSeen.millisecondsSinceEpoch,
              },
          ]),
        )
        .ignore();
  }

  static List<SavedEndpoint> _decode(String? json) {
    if (json == null) return const [];
    try {
      return [
        for (final entry in jsonDecode(json) as List)
          if (entry case {
            'host': final String host,
            'port': final int port,
            'last_seen': final int lastSeen,
          })
            SavedEndpoint(
              host: host,
              port: port,
              lastSeen: DateTime.fromMillisecondsSinceEpoch(lastSeen),
            ),
      ];
    } catch (_) {
      return const [];
    }
  }
}

final serverEndpointStoreProvider = Provider<ServerEndpointStore>(
  (ref) =>
      ServerEndpointStore(ref.watch(sharedPrefsProvider))
        ..migrateSavedAddress(),
);
