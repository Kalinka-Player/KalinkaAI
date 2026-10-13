import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart' show Logger;

import 'kalinka_player_api_provider.dart';

final _logger = Logger();

/// What the server reports about an available release update.
class ServerUpdateInfo {
  final String currentVersion;
  final String? latestVersion;
  final bool updateAvailable;
  final bool upgradeSupported;
  final String? rendererCurrentVersion;
  final String? rendererLatestVersion;
  final bool rendererUpdateAvailable;
  final String? supervisorCurrentVersion;
  final String? supervisorLatestVersion;
  final bool supervisorUpdateAvailable;

  const ServerUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.updateAvailable,
    required this.upgradeSupported,
    this.rendererCurrentVersion,
    this.rendererLatestVersion,
    this.rendererUpdateAvailable = false,
    this.supervisorCurrentVersion,
    this.supervisorLatestVersion,
    this.supervisorUpdateAvailable = false,
  });

  /// True when the app should offer the upgrade.
  bool get canUpgrade =>
      updateAvailable &&
      upgradeSupported &&
      latestVersion != null &&
      latestVersion!.trim().isNotEmpty;

  /// Describe the versions the installer will change. Availability remains
  /// the backend's decision; the bundle target is also the upgrade API token.
  List<String> get changes => !updateAvailable
      ? const []
      : [
          if (latestVersion != null &&
              latestVersion!.isNotEmpty &&
              latestVersion != currentVersion)
            _change('Server', currentVersion, latestVersion),
          if (rendererUpdateAvailable)
            _change('Renderer', rendererCurrentVersion, rendererLatestVersion),
          if (supervisorUpdateAvailable)
            _change(
              'Supervisor',
              supervisorCurrentVersion,
              supervisorLatestVersion,
            ),
        ];

  static String _change(String name, String? current, String? latest) {
    if (latest == null || latest.isEmpty) return '$name update';
    if (current == null || current.isEmpty) return '$name: $latest';
    return '$name: $current → $latest';
  }
}

/// Re-fetched on every server switch: the `watch` below ties this to the proxy,
/// which is rebuilt from the connection settings. A `read` would instead pin the
/// first server's answer for the container's lifetime. Resolves to null when the
/// server predates the endpoint or the request fails — both mean "show nothing".
/// Between switches the answer is cached for the session, so SettingsScreen
/// invalidates it on open; the banner would otherwise keep showing a verdict
/// taken before the release it is meant to announce.
final serverUpdateProvider = FutureProvider<ServerUpdateInfo?>((ref) async {
  try {
    final info = await ref.watch(kalinkaProxyProvider).getServerUpdateInfo();
    if (info == null) return null;
    return ServerUpdateInfo(
      currentVersion: (info['current_version'] ?? '') as String,
      latestVersion: info['latest_version'] as String?,
      updateAvailable: (info['update_available'] ?? false) as bool,
      upgradeSupported: (info['upgrade_supported'] ?? false) as bool,
      rendererCurrentVersion: info['renderer_current_version'] as String?,
      rendererLatestVersion: info['renderer_latest_version'] as String?,
      rendererUpdateAvailable:
          (info['renderer_update_available'] ?? false) as bool,
      supervisorCurrentVersion: info['supervisor_current_version'] as String?,
      supervisorLatestVersion: info['supervisor_latest_version'] as String?,
      supervisorUpdateAvailable:
          (info['supervisor_update_available'] ?? false) as bool,
    );
  } catch (e) {
    _logger.w('Server update check failed', error: e);
    return null;
  }
});
