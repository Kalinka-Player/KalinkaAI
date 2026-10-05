import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connection_settings_provider.dart';
import 'connection_state_provider.dart';
import 'kalinka_player_api_provider.dart';
import 'server_address.dart';

/// Point the app at [address] and check that it answers.
///
/// [persist] stores the server for the next launch; without it the choice
/// lasts this session only, as the setup wizard wants until it commits. On
/// failure the reconnect loop takes over and the error is rethrown.
Future<void> connectToServer(
  WidgetRef ref, {
  required String name,
  required ServerAddress address,
  required bool persist,
}) async {
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
