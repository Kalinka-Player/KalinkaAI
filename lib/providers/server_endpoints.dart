import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'connection_settings_provider.dart';
import 'server_address.dart';

/// Where the server last seen at [host]:[port] is recorded, so it is still
/// known while that server is down.
String serverIdAtKey(String host, int port) => 'Kalinka.serverIdAt.$host:$port';

/// An address a server was chosen, connected or found at, and when.
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

  static const _prefix = 'Kalinka.servers.v1:';

  /// A cable, Wi-Fi and a few leases; the longest unseen go first.
  static const maxEndpoints = 8;

  static String keyOf(String serverId) => '$_prefix$serverId';

  /// [serverId]'s addresses, the most recently seen first.
  List<SavedEndpoint> endpointsOf(String serverId) {
    final json = _prefs.getString(keyOf(serverId));
    return json == null ? _savedAddressOf(serverId) : _decode(json);
  }

  /// Before addresses were kept per server only the connection's own was
  /// saved, under the address.
  List<SavedEndpoint> _savedAddressOf(String serverId) {
    final host = _prefs.getString(ConnectionSettingsNotifier.sharedPrefHost);
    final port = _prefs.getInt(ConnectionSettingsNotifier.sharedPrefPort);
    final scheme = _prefs.getString(
      ConnectionSettingsNotifier.sharedPrefScheme,
    );
    if (host == null || host.isEmpty || port == null || port <= 0) {
      return const [];
    }
    if ((scheme ?? 'http') != 'http' ||
        _prefs.getString(serverIdAtKey(host, port)) != serverId) {
      return const [];
    }
    return [
      SavedEndpoint(
        host: host,
        port: port,
        lastSeen: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    ];
  }

  /// Saves that [serverId] is at [addresses] now. Only a server on the local
  /// network, reached over plain HTTP, moves between addresses.
  Future<void> remember(
    String serverId,
    Iterable<ServerAddress> addresses,
  ) async {
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
    final kept = [
      ...fresh,
      for (final endpoint in endpointsOf(serverId))
        if (!fresh.any((e) => e.address == endpoint.address)) endpoint,
    ].take(maxEndpoints);
    await _prefs.setString(
      keyOf(serverId),
      jsonEncode([
        for (final e in kept)
          {
            'host': e.host,
            'port': e.port,
            'last_seen': e.lastSeen.millisecondsSinceEpoch,
          },
      ]),
    );
  }

  /// Records that the server at [address] said it is [serverId].
  void confirmedAt(String serverId, ServerAddress address) {
    final key = serverIdAtKey(address.host, address.port);
    if (_prefs.getString(key) != serverId) _prefs.setString(key, serverId);
    remember(serverId, [address]).ignore();
  }

  /// The server last seen at [address]: the one that said so there, failing
  /// that the one most recently chosen there.
  String? serverIdAt(ServerAddress address) {
    final said = _prefs.getString(serverIdAtKey(address.host, address.port));
    if (said != null) return said;
    String? newest;
    DateTime? newestSeen;
    for (final key in _prefs.getKeys()) {
      if (!key.startsWith(_prefix)) continue;
      for (final endpoint in _decode(_prefs.getString(key))) {
        if (endpoint.address != address) continue;
        if (newestSeen == null || endpoint.lastSeen.isAfter(newestSeen)) {
          newest = key.substring(_prefix.length);
          newestSeen = endpoint.lastSeen;
        }
      }
    }
    return newest;
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
  (ref) => ServerEndpointStore(ref.watch(sharedPrefsProvider)),
);
