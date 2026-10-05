import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'kalinka_player_api_provider.dart';
import 'server_address.dart';
import 'settings_provider.dart';

const demoServerName = 'Kalinka demo';
const demoServerUnavailable =
    'The demo server isn’t available right now. Try again later.';

/// Overrides the public demo server, e.g. `http://127.0.0.1:8000` to try a
/// demo server running locally.
const _demoServerDefine = String.fromEnvironment('KALINKA_DEMO_SERVER');

/// The public demo server the "Try demo server" button connects to.
ServerAddress demoServer() =>
    parseServerAddress(_demoServerDefine) ??
    (scheme: 'https', host: 'demo.kalinkaplayer.com', port: 443);

const demoModeFlagPath = 'base_config.server.demo_mode';

/// Whether a server's settings values mark it a read-only demo. A server
/// older than demo mode has no such value, and is not one.
bool isDemoServer(Map<dynamic, dynamic> values) =>
    values[demoModeFlagPath] == true;

/// Asks the server behind [api] whether it is a read-only demo.
Future<bool> saysItIsADemo(KalinkaPlayerProxy api) async {
  final values = (await api.getSettings())['values'];
  return values is Map && isDemoServer(values);
}

/// Whether the connected server is a read-only demo: it plays and queues,
/// and refuses every other change. Known once the settings have loaded,
/// which happens on every connect.
final demoModeProvider = Provider<bool>(
  (ref) => ref.watch(settingsProvider.select((s) => isDemoServer(s.values))),
);
