import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connection_settings_provider.dart';
import 'connection_state_provider.dart';
import 'demo_mode.dart';
import 'kalinka_player_api_provider.dart';
import 'server_address.dart';
import 'settings_provider.dart';

/// Asks the server at an address whether it is a read-only demo, without
/// connecting the app to it.
final demoCheckProvider = Provider<Future<bool> Function(ServerAddress)>(
  (ref) => (address) async {
    final client = kalinkaHttpClient(
      Uri(
        scheme: address.scheme,
        host: address.host,
        port: address.port,
      ).toString(),
    );
    try {
      return await saysItIsADemo(KalinkaPlayerProxyImpl(client: client));
    } finally {
      client.close();
    }
  },
);

/// The demo address answered as an ordinary server, which a visitor could
/// change: older than demo mode, or deployed without it.
class NotADemoServerException implements Exception {
  const NotADemoServerException();

  @override
  String toString() => demoServerUnavailable;
}

/// Point the app at [address] and check that it answers.
///
/// [persist] stores the server for the next launch; without it the choice
/// lasts this session only, as the setup wizard wants until it commits. On
/// failure the reconnect loop takes over and the error is rethrown. The demo
/// address is connected to only once it says it is a demo; until then
/// nothing about the connection changes.
Future<void> connectToServer(
  WidgetRef ref, {
  required String name,
  required ServerAddress address,
  required bool persist,
}) async {
  if (address == demoServer() && !await ref.read(demoCheckProvider)(address)) {
    throw const NotADemoServerException();
  }
  final settings = ref.read(connectionSettingsProvider.notifier);
  final connection = ref.read(connectionStateProvider.notifier);
  try {
    if (persist) {
      await settings.setDevice(
        name,
        address.host,
        address.port,
        scheme: address.scheme,
      );
    } else {
      settings.setDeviceEphemeral(
        name,
        address.host,
        address.port,
        scheme: address.scheme,
      );
    }

    // Recreate the API client against the newly selected server.
    ref.invalidate(httpClientProvider);
    ref.invalidate(kalinkaProxyProvider);
    final api = ref.read(kalinkaProxyProvider);

    connection.connecting();
    // Fetching modules is the health check.
    await api.listModules();
    connection.connected();
  } catch (_) {
    connection.startReconnecting();
    rethrow;
  }
}

/// Leaves the server at the demo address when its loaded settings show it is
/// not a demo. A stored connection reconnects without asking first, so this
/// is the check for it. True when the app left.
Future<bool> leaveDemoAddressIfNotADemo(WidgetRef ref) async {
  final connection = ref.read(connectionSettingsProvider);
  final settings = ref.read(settingsProvider);
  final loaded = settings.schema != null && settings.error == null;
  if (connection.address != demoServer() ||
      !loaded ||
      isDemoServer(settings.values)) {
    return false;
  }
  await ref.read(connectionSettingsProvider.notifier).clearDevice();
  return true;
}
