import 'dart:async';

import 'package:dio/dio.dart' show DioException;
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

const _askAgainAfter = Duration(seconds: 10);

/// The connected server's answer to who it is. Loading while not connected,
/// and an error while the server does not answer, asked again every
/// [_askAgainAfter]. Either way it keeps the last answer.
///
/// Not retried by Riverpod, whose retries would hold [serverIdentityProvider]
/// loading instead of null.
final serverAnswerProvider = FutureProvider<ServerAnswer>((ref) async {
  final server = ref.watch(connectionSettingsProvider.select((s) => s.baseUrl));
  if (ref.watch(connectionStateProvider) != ConnectionStatus.connected) {
    return Completer<ServerAnswer>().future;
  }
  try {
    final data = (await ref.watch(httpClientProvider).get('/renderer/sessions'))
        .data;
    final id = data is Map ? data['server_id'] : null;
    return (server: server, id: id is String && id.isNotEmpty ? id : null);
  } on DioException catch (e) {
    // A server from before the route answers it as missing.
    if (e.response?.statusCode case 404 || 405) {
      return (server: server, id: null);
    }
    // Disposed if the connection changed while asking.
    if (ref.mounted) {
      final again = Timer(_askAgainAfter, ref.invalidateSelf);
      ref.onDispose(again.cancel);
    }
    rethrow;
  }
}, retry: (_, _) => null);

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
  final String scope;

  const ServerStorageKey._(this.scope);

  ServerStorageKey.ofServer(String id) : this._('id:$id');

  /// The scope pins were kept under before servers were told apart by id.
  ServerStorageKey.ofAddress(Uri baseUrl) : this._('$baseUrl');

  bool get isServerId => scope.startsWith('id:');

  String get pinnedCatalogs => 'Kalinka.pinnedCatalogs.v1:$scope';

  String get catalogFilters => 'Kalinka.catalogFilters:$scope';

  /// [pageId]'s entry in the map of folders pages were left on.
  String folderPath(String pageId) => '$scope $pageId';

  @override
  bool operator ==(Object other) =>
      other is ServerStorageKey && other.scope == scope;

  @override
  int get hashCode => scope.hashCode;

  @override
  String toString() => 'ServerStorageKey($scope)';
}

/// The string kept under [from], moved to [to]; null when there is none.
String? moveStoredString(
  SharedPreferences prefs, {
  required String from,
  required String to,
}) {
  final value = prefs.getString(from);
  if (value == null) return null;
  prefs.setString(to, value).then((saved) {
    if (saved) prefs.remove(from);
  }, onError: (Object _) {});
  return value;
}

/// The connected server's [ServerStorageKey]; null until the server at this
/// address has answered. Kept through a reconnect to the same address, so
/// Home does not blank each time the server is away.
final serverStorageKeyProvider = Provider<ServerStorageKey?>((ref) {
  final server = ref.watch(connectionSettingsProvider.select((s) => s.baseUrl));
  final answer = ref.watch(serverAnswerProvider).value;
  if (answer == null || answer.server != server) return null;
  final id = answer.id;
  return id == null
      ? ServerStorageKey.ofAddress(server)
      : ServerStorageKey.ofServer(id);
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
