import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'kalinka_player_api_provider.dart';
import 'connection_state_provider.dart';
import 'settings_provider.dart';

const pluginCatalogSettingPath = 'base_config.server.plugin_catalog_enabled';

class ServerInfo {
  final String version;
  final int latencyMs;
  final bool pluginCatalogEnabled;

  /// The server installs, removes and updates catalog plugins itself.
  final bool pluginInstallation;

  /// The server checks installed plugins for newer catalog releases.
  final bool pluginUpdateChecks;

  /// The server lists its volumes and the folders on them (API 0.21).
  final bool storage;

  /// The server lists the drives and shares it could mount (API 0.22).
  final bool storageDevices;

  const ServerInfo({
    required this.version,
    required this.latencyMs,
    this.pluginCatalogEnabled = false,
    this.pluginInstallation = false,
    this.pluginUpdateChecks = false,
    this.storage = false,
    this.storageDevices = false,
  });
}

/// Fetches server version and measures latency via a round-trip GET.
final serverInfoProvider = FutureProvider.autoDispose<ServerInfo>((ref) async {
  final api = ref.watch(kalinkaProxyProvider);
  ref.watch(connectionStateProvider);
  // Only saved values invalidate capabilities; staging an edit is not opt-in.
  ref.watch(settingsProvider.select((s) => s.values[pluginCatalogSettingPath]));
  final stopwatch = Stopwatch()..start();
  final info = await api.getServerVersion();
  stopwatch.stop();

  final version = info['server_version']?.toString() ?? 'Unknown';
  final capabilities = info['plugin_management'];
  bool can(String capability) =>
      capabilities is Map && capabilities[capability] == true;
  final browsing = can('enabled') && can('catalog_browsing');
  final storage = info['storage'];
  return ServerInfo(
    version: version,
    latencyMs: stopwatch.elapsedMilliseconds,
    pluginCatalogEnabled: browsing,
    pluginInstallation: browsing && can('installation'),
    pluginUpdateChecks: browsing && can('update_checks'),
    storage: storage is Map && storage['folders'] == true,
    storageDevices: storage is Map && storage['devices'] == true,
  );
});

/// Whether the server's folders can be browsed to pick one, rather than typed.
/// Fails closed while the server is asked again, as the last one's answer
/// still shows then.
final storageSupportedProvider = Provider<bool>((ref) {
  final info = ref.watch(serverInfoProvider);
  return !info.isLoading && !info.hasError && info.value?.storage == true;
});

/// Whether Drives & shares can be offered on this server.
final storageDevicesSupportedProvider = Provider<bool>((ref) {
  final info = ref.watch(serverInfoProvider);
  return !info.isLoading &&
      !info.hasError &&
      info.value?.storageDevices == true;
});

/// Fail closed during connection changes, errors and on older servers.
final pluginCatalogEnabledProvider = Provider<bool>((ref) {
  if (ref.watch(connectionStateProvider) != ConnectionStatus.connected) {
    return false;
  }
  final info = ref.watch(serverInfoProvider);
  return !info.isLoading &&
      !info.hasError &&
      info.value?.pluginCatalogEnabled == true;
});

/// Whether Install, Uninstall and Update can be offered on this server.
final pluginInstallationProvider = Provider<bool>(
  (ref) =>
      ref.watch(pluginCatalogEnabledProvider) &&
      ref.watch(serverInfoProvider).value?.pluginInstallation == true,
);

/// Whether this server reports newer releases of installed plugins.
final pluginUpdateChecksProvider = Provider<bool>(
  (ref) =>
      ref.watch(pluginCatalogEnabledProvider) &&
      ref.watch(serverInfoProvider).value?.pluginUpdateChecks == true,
);
