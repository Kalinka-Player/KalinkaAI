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

  const ServerInfo({
    required this.version,
    required this.latencyMs,
    this.pluginCatalogEnabled = false,
    this.pluginInstallation = false,
    this.pluginUpdateChecks = false,
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
  return ServerInfo(
    version: version,
    latencyMs: stopwatch.elapsedMilliseconds,
    pluginCatalogEnabled: browsing,
    pluginInstallation: browsing && can('installation'),
    pluginUpdateChecks: browsing && can('update_checks'),
  );
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
