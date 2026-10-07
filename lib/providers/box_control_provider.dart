import 'package:dio/dio.dart' show DioException;
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// The connected server's identity, as the server itself reports it; null
/// whenever it is not connected.
final serverIdentityProvider = FutureProvider<String?>((ref) async {
  if (ref.watch(connectionStateProvider) != ConnectionStatus.connected) {
    return null;
  }
  try {
    final data =
        (await ref.watch(httpClientProvider).get('/renderer/sessions')).data;
    final id = data is Map ? data['server_id'] : null;
    return id is String && id.isNotEmpty ? id : null;
  } on DioException {
    return null;
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

/// The box controls the app may offer for the connected server: null when
/// its box has no supervisor, or one that does not belong to this server.
///
/// While the server is down the box is matched against the server last seen
/// at this address, which is what lets the app restart a server that stopped
/// answering.
final boxControlProvider = FutureProvider<BoxControl?>((ref) async {
  final api = ref.watch(supervisorApiProvider);
  if (api == null || ref.watch(demoModeProvider)) return null;
  final prefs = ref.watch(sharedPrefsProvider);
  final key = _knownServerKey(ref.watch(connectionSettingsProvider));
  final current = await ref.watch(serverIdentityProvider.future);
  final known = current ?? prefs.getString(key);
  if (known == null) return null;
  final info = await api.info();
  if (info == null || !info.compatible || info.serverId != known) return null;
  return BoxControl(info, known);
});
