import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'server_address.dart';

final sharedPrefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('override in main()');
});

/// Model class to hold connection settings state
class ConnectionSettings {
  final String name;
  final String host;
  final int port;

  /// `http`, or `https` for a server behind TLS.
  final String scheme;

  const ConnectionSettings({
    required this.name,
    required this.host,
    required this.port,
    this.scheme = 'http',
  });

  /// Check if connection settings are properly configured
  bool get isSet => host.isNotEmpty && port > 0;
  // Uri() (not Uri.parse of an interpolated string) so IPv6 hosts like `::1`
  // are bracketed correctly instead of throwing a FormatException.
  Uri get baseUrl => Uri(scheme: scheme, host: host, port: port);

  String get wsScheme => scheme == 'https' ? 'wss' : 'ws';

  ServerAddress get address => (scheme: scheme, host: host, port: port);

  /// The address as the user would type it: `host:port` on a local network,
  /// the bare host for a server on the default HTTPS port.
  String get displayAddress =>
      scheme == 'http' ? '$host:$port' : baseUrl.authority;

  ConnectionSettings copyWith({
    String? name,
    String? host,
    int? port,
    String? scheme,
  }) {
    return ConnectionSettings(
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      scheme: scheme ?? this.scheme,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ConnectionSettings &&
        other.name == name &&
        other.host == host &&
        other.port == port &&
        other.scheme == scheme;
  }

  @override
  int get hashCode {
    return Object.hash(name, host, port, scheme);
  }

  @override
  String toString() {
    return 'ConnectionSettings(name: $name, host: $host, port: $port, '
        'scheme: $scheme)';
  }
}

/// StateNotifier for managing connection settings
class ConnectionSettingsNotifier extends Notifier<ConnectionSettings> {
  static const String sharedPrefName = 'Kalinka.name';
  static const String sharedPrefHost = 'Kalinka.host';
  static const String sharedPrefPort = 'Kalinka.port';
  static const String sharedPrefScheme = 'Kalinka.scheme';

  late SharedPreferences _sharedPrefs;

  /// Initialize settings from SharedPreferences
  ConnectionSettings _load() {
    final name = _sharedPrefs.getString(sharedPrefName) ?? 'Unknown';
    final host = _sharedPrefs.getString(sharedPrefHost) ?? '';
    final port = _sharedPrefs.getInt(sharedPrefPort) ?? 0;
    // Stored before servers could be reached over TLS: plain HTTP.
    final scheme = _sharedPrefs.getString(sharedPrefScheme) ?? 'http';

    return ConnectionSettings(
      name: name,
      host: host,
      port: port,
      scheme: scheme,
    );
  }

  /// Set device connection settings
  Future<void> setDevice(
    String name,
    String host,
    int port, {
    String scheme = 'http',
  }) async {
    await _sharedPrefs.setString(sharedPrefName, name);
    await _sharedPrefs.setString(sharedPrefHost, host);
    await _sharedPrefs.setInt(sharedPrefPort, port);
    await _sharedPrefs.setString(sharedPrefScheme, scheme);

    state = ConnectionSettings(
      name: name,
      host: host,
      port: port,
      scheme: scheme,
    );
  }

  /// Set device for this session only — nothing written to SharedPreferences.
  /// Used during onboarding so that an interrupted run leaves no stored
  /// server behind and the wizard restarts from the beginning. Call
  /// [persist] (or [setDevice]) once setup is committed.
  void setDeviceEphemeral(
    String name,
    String host,
    int port, {
    String scheme = 'http',
  }) {
    state = ConnectionSettings(
      name: name,
      host: host,
      port: port,
      scheme: scheme,
    );
  }

  /// Persist the current in-memory connection (after an ephemeral connect).
  Future<void> persist() async {
    if (!state.isSet) return;
    await setDevice(state.name, state.host, state.port, scheme: state.scheme);
  }

  /// Reset connection settings
  void reset() {
    state = ConnectionSettings(name: '', host: '', port: 0);
  }

  /// Clear stored device and reset to unconfigured state.
  Future<void> clearDevice() async {
    await _sharedPrefs.remove(sharedPrefName);
    await _sharedPrefs.remove(sharedPrefHost);
    await _sharedPrefs.remove(sharedPrefPort);
    await _sharedPrefs.remove(sharedPrefScheme);
    state = const ConnectionSettings(name: '', host: '', port: 0);
  }

  @override
  ConnectionSettings build() {
    // Get SharedPreferences from the provider
    _sharedPrefs = ref.read(sharedPrefsProvider);
    return _load();
  }
}

/// Provider for connection settings
final connectionSettingsProvider =
    NotifierProvider<ConnectionSettingsNotifier, ConnectionSettings>(
      ConnectionSettingsNotifier.new,
    );
