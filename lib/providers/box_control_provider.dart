import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart' show Dio, DioException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'connection_settings_provider.dart';
import 'connection_state_provider.dart';
import 'demo_mode.dart';
import 'kalinka_player_api_provider.dart' show httpClientProvider;
import 'supervisor_api.dart';

/// The connected server's box, confirmed to be that server's own.
class BoxControl {
  final SupervisorInfo info;

  /// The server the box belongs to, which every action names.
  final String serverId;

  const BoxControl(this.info, this.serverId);

  bool offers(BoxAction action) => info.offers(action);
}

/// What the server at [server] said it is: its [id], or null from a server too
/// old to report one.
typedef ServerAnswer = ({Uri server, String? id});

/// The pause before a server that did not answer is asked again for the
/// [attempt]th time: doubling from two seconds to a minute.
Duration _pauseBefore(int attempt) =>
    Duration(seconds: attempt < 5 ? 2 << attempt : 60);

/// Whether [status] says the route is missing, as on a server older than it.
/// Any other refusal, such as 401 or 403, says nothing about the server.
bool _routeMissing(int? status) => status == 404 || status == 405;

Future<ServerAnswer> _askWhoItIs(Dio client, Uri server) async {
  try {
    final data = (await client.get('/renderer/sessions')).data;
    final id = data is Map ? data['server_id'] : null;
    return (server: server, id: id is String && id.isNotEmpty ? id : null);
  } on DioException catch (e) {
    if (_routeMissing(e.response?.statusCode)) {
      return (server: server, id: null);
    }
    rethrow;
  }
}

/// The connected server's answer to who it is, asked once per connection.
/// Loading while not connected; an error while the server does not answer,
/// asked again with a growing pause. Only an answer changes it, so asking
/// again rebuilds nothing that watches it.
class ServerAnswerNotifier extends AsyncNotifier<ServerAnswer> {
  @override
  Future<ServerAnswer> build() async {
    final server = ref.watch(
      connectionSettingsProvider.select((s) => s.baseUrl),
    );
    final prefs = ref.read(sharedPrefsProvider);
    // The server last recorded here owns what was kept under the address.
    // Read before this connection's answer is recorded over it.
    final recorded = prefs.getString(
      _knownServerKey(ref.read(connectionSettingsProvider)),
    );
    if (recorded != null) {
      _claimAddressState(prefs, server, ServerStorageKey.ofServer(recorded));
    }
    if (ref.watch(connectionStateProvider) != ConnectionStatus.connected) {
      return Completer<ServerAnswer>().future;
    }
    final client = ref.watch(httpClientProvider);
    var current = true;
    Timer? again;
    ref.onDispose(() {
      current = false;
      again?.cancel();
    });

    Future<ServerAnswer> ask() async {
      final answer = await _askWhoItIs(client, server);
      if (recorded == null) {
        _claimAddressState(prefs, server, ServerStorageKey.of(answer));
      }
      return answer;
    }

    void askAgain(int attempt) {
      again = Timer(_pauseBefore(attempt), () async {
        try {
          final answer = await ask();
          if (current) state = AsyncData(answer);
        } on DioException {
          if (current) askAgain(attempt + 1);
        }
      });
    }

    try {
      return await ask();
    } on DioException {
      if (current) askAgain(0);
      rethrow;
    }
  }
}

final serverAnswerProvider =
    AsyncNotifierProvider<ServerAnswerNotifier, ServerAnswer>(
      ServerAnswerNotifier.new,
      // Riverpod's own retries would hold serverIdentityProvider loading.
      retry: (_, _) => null,
    );

/// The connected server's identity, as the server itself reports it; null
/// whenever it is not connected.
final serverIdentityProvider = FutureProvider<String?>((ref) async {
  if (ref.watch(connectionStateProvider) != ConnectionStatus.connected) {
    return null;
  }
  try {
    return (await ref.watch(serverAnswerProvider.future)).id;
  } on DioException {
    return null;
  }
});

/// Where the app keeps what belongs to one server: under its id, or its
/// address for a server too old to report one. Every per-server key is here.
class ServerStorageKey {
  /// The folder each page of folders was left on, by server and page.
  static const folderPaths = 'Kalinka.folderPaths';

  /// Every server's catalog filters, as kept before they were kept per server.
  static const everyServersCatalogFilters = 'Kalinka.catalogFilters';

  final String scope;

  /// Said by the server on this connection. Nothing is saved under a key that
  /// is not: the server now at the address may be another.
  final bool confirmed;

  const ServerStorageKey._(this.scope, {this.confirmed = false});

  ServerStorageKey.ofServer(String id, {bool confirmed = false})
    : this._('id:$id', confirmed: confirmed);

  /// The scope pins were kept under before servers were told apart by id.
  ServerStorageKey.ofAddress(Uri baseUrl, {bool confirmed = false})
    : this._('$baseUrl', confirmed: confirmed);

  factory ServerStorageKey.of(ServerAnswer answer, {bool confirmed = false}) {
    final id = answer.id;
    return id == null
        ? ServerStorageKey.ofAddress(answer.server, confirmed: confirmed)
        : ServerStorageKey.ofServer(id, confirmed: confirmed);
  }

  String get pinnedCatalogs => 'Kalinka.pinnedCatalogs.v1:$scope';

  String get catalogFilters => 'Kalinka.catalogFilters:$scope';

  /// [pageId]'s entry in [folderPaths].
  String folderPath(String pageId) => '$scope $pageId';

  @override
  bool operator ==(Object other) =>
      other is ServerStorageKey &&
      other.scope == scope &&
      other.confirmed == confirmed;

  @override
  int get hashCode => Object.hash(scope, confirmed);

  @override
  String toString() =>
      'ServerStorageKey($scope${confirmed ? '' : ', unconfirmed'})';
}

/// Moves what was kept under [address] before servers were told apart by id
/// to [owner], with the catalog filters once kept for every server. Nothing
/// [owner] has already is replaced.
void _claimAddressState(
  SharedPreferences prefs,
  Uri address,
  ServerStorageKey owner,
) {
  final from = ServerStorageKey.ofAddress(address);
  if (owner.scope != from.scope) {
    if (prefs.getString(owner.pinnedCatalogs) == null) {
      _moveString(prefs, from: from.pinnedCatalogs, to: owner.pinnedCatalogs);
    }
    _moveFolderPaths(prefs, from: from.scope, to: owner.scope);
  }
  if (prefs.getString(owner.catalogFilters) == null) {
    _moveString(
      prefs,
      from: ServerStorageKey.everyServersCatalogFilters,
      to: owner.catalogFilters,
    );
  }
}

void _moveString(
  SharedPreferences prefs, {
  required String from,
  required String to,
}) {
  final value = prefs.getString(from);
  if (value == null) return;
  prefs.setString(to, value).then((saved) {
    if (saved) prefs.remove(from);
  }, onError: (Object _) {});
}

void _moveFolderPaths(
  SharedPreferences prefs, {
  required String from,
  required String to,
}) {
  final json = prefs.getString(ServerStorageKey.folderPaths);
  // Most connections have nothing to move, and need not decode the map.
  if (json == null || !json.contains('"$from ')) return;
  final Map<String, dynamic> paths;
  try {
    paths = Map<String, dynamic>.from(jsonDecode(json) as Map);
  } catch (_) {
    return;
  }
  for (final key in [...paths.keys]) {
    if (!key.startsWith('$from ')) continue;
    final path = paths.remove(key);
    paths.putIfAbsent('$to ${key.substring(from.length + 1)}', () => path);
  }
  prefs.setString(ServerStorageKey.folderPaths, jsonEncode(paths)).ignore();
}

/// The connected server's [ServerStorageKey]. While connected, only this
/// connection's answer gives one, as another server may have taken the
/// address. While away, the last server confirmed at the address keeps its
/// key, unconfirmed; failing that, once a connection has failed, the one last
/// recorded there.
final serverStorageKeyProvider = Provider<ServerStorageKey?>((ref) {
  final server = ref.watch(connectionSettingsProvider.select((s) => s.baseUrl));
  final connection = ref.watch(connectionStateProvider);
  final answer = ref.watch(serverAnswerProvider);
  switch (connection) {
    case ConnectionStatus.none:
      return null;
    case ConnectionStatus.connected:
      return switch (answer) {
        AsyncData(:final value) when value.server == server =>
          ServerStorageKey.of(value, confirmed: true),
        _ => null,
      };
    case _:
      final last = answer.value;
      if (last != null && last.server == server) {
        return ServerStorageKey.of(last);
      }
      // Not while a first connection is under way: its answer is usually
      // moments off, and the pins would blink out as it connects.
      if (connection == ConnectionStatus.connecting) return null;
      final recorded = ref
          .read(sharedPrefsProvider)
          .getString(_knownServerKey(ref.read(connectionSettingsProvider)));
      return recorded == null ? null : ServerStorageKey.ofServer(recorded);
  }
});

/// The server last seen at [settings]' address, so its box is still known
/// while that server is down.
String _knownServerKey(ConnectionSettings settings) =>
    'Kalinka.serverIdAt.${settings.host}:${settings.port}';

/// Records each connected server's identity under its address. Watched from
/// the app root, so the record exists before the server can go down, whether
/// or not the box controls were ever shown.
final rememberServerIdentityProvider = Provider<void>((ref) {
  ref.listen(serverIdentityProvider, (_, next) {
    final id = next.value;
    if (id == null) return;
    final key = _knownServerKey(ref.read(connectionSettingsProvider));
    final prefs = ref.read(sharedPrefsProvider);
    if (prefs.getString(key) != id) prefs.setString(key, id);
  });
});

/// The connected server's identity, or while it is down the one last seen at
/// its address.
final knownServerIdentityProvider = FutureProvider<String?>((ref) async {
  final prefs = ref.watch(sharedPrefsProvider);
  ref.watch(connectionSettingsProvider.select((s) => s.address));
  final key = _knownServerKey(ref.read(connectionSettingsProvider));
  return await ref.watch(serverIdentityProvider.future) ?? prefs.getString(key);
});

/// Why the connected server has no box controls.
enum NoBoxControl {
  /// No supervisor answers on the server's host: none is installed, its
  /// control page is turned off, or the server is a demo or behind TLS.
  noSupervisor,

  /// The supervisor did not answer, or the server it would have to match is
  /// not known yet.
  notAnswering,

  /// The supervisor answers for another server, such as one that took over
  /// the address.
  otherServer,

  /// The supervisor speaks no protocol this app does.
  incompatible,
}

/// The connected server's box controls, or why there are none.
class BoxProbe {
  final BoxControl? control;
  final NoBoxControl? missing;

  const BoxProbe.found(BoxControl this.control) : missing = null;

  const BoxProbe.missing(NoBoxControl this.missing) : control = null;
}

/// Looks for the connected server's box. Invalidate it to look again.
///
/// While the server is down the box is matched against the server last seen
/// at this address, which is what lets the app restart a server that stopped
/// answering.
final boxProbeProvider = FutureProvider<BoxProbe>((ref) async {
  final api = ref.watch(supervisorApiProvider);
  if (api == null || ref.watch(demoModeProvider)) {
    return const BoxProbe.missing(NoBoxControl.noSupervisor);
  }
  final known = await ref.watch(knownServerIdentityProvider.future);
  if (known == null) return const BoxProbe.missing(NoBoxControl.notAnswering);
  final (:reach, :info) = await api.probe();
  if (info == null) {
    return BoxProbe.missing(
      reach == SupervisorReach.silent
          ? NoBoxControl.notAnswering
          : NoBoxControl.noSupervisor,
    );
  }
  if (!info.compatible) {
    return const BoxProbe.missing(NoBoxControl.incompatible);
  }
  if (info.serverId != known) {
    return const BoxProbe.missing(NoBoxControl.otherServer);
  }
  return BoxProbe.found(BoxControl(info, known));
});

/// The box controls the app may offer for the connected server: null when
/// [boxProbeProvider] found none.
final boxControlProvider = FutureProvider<BoxControl?>(
  (ref) async => (await ref.watch(boxProbeProvider.future)).control,
);
