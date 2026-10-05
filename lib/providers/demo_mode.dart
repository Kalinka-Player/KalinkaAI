import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'server_address.dart';
import 'settings_provider.dart';

const demoServerName = 'Kalinka demo';
const demoServerUnreachable =
    'Could not reach the demo server. Try again in a moment.';

/// Overrides the public demo server, e.g. `http://127.0.0.1:8000` to try a
/// demo server running locally.
const _demoServerDefine = String.fromEnvironment('KALINKA_DEMO_SERVER');

/// The public demo server the "Try demo server" button connects to.
ServerAddress demoServer() =>
    parseServerAddress(_demoServerDefine) ??
    (scheme: 'https', host: 'demo.kalinkaplayer.com', port: 443);

const demoModeFlagPath = 'base_config.server.demo_mode';

/// Whether the connected server is a read-only demo: it plays and queues,
/// and refuses every other change. Known once the settings have loaded,
/// which happens on every connect.
final demoModeProvider = Provider<bool>(
  (ref) => ref.watch(
    settingsProvider.select((s) => s.values[demoModeFlagPath] == true),
  ),
);
