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

  /// Changes each time the app is pointed at another address, but not when
  /// it follows the same server to another of its own, so what belongs to
  /// the server rather than its address is dropped on this, not the address.
  final int serverChoice;

  const ConnectionSettings({
    required this.name,
    required this.host,
    required this.port,
    this.scheme = 'http',
    this.serverChoice = 0,
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
      serverChoice: serverChoice,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ConnectionSettings &&
        other.name == name &&
        other.host == host &&
        other.port == port &&
        other.scheme == scheme &&
        other.serverChoice == serverChoice;
  }

  @override
  int get hashCode {
    return Object.hash(name, host, port, scheme, serverChoice);
  }

  @override
  String toString() {
    return 'ConnectionSettings(name: $name, host: $host, port: $port, '
        'scheme: $scheme, serverChoice: $serverChoice)';
  }
}

/// StateNotifier for managing connection settings
class ConnectionSettingsNotifier extends Notifier<ConnectionSettings> {
  static const String sharedPrefName = 'Kalinka.name';
  static const String sharedPrefHost = 'Kalinka.host';
  static const String sharedPrefPort = 'Kalinka.port';
  static const String sharedPrefScheme = 'Kalinka.scheme';

  late SharedPreferences _sharedPrefs;

  /// Whether changes to the connection in [state] are saved with it.
  bool _persisted = true;

  /// Whether [setDevice] is saving a connection, which replaces [state] once
  /// saved.
  bool _settingDevice = false;

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
    // Settings from the outgoing connection may finish while these writes
    // are in flight; they must not replace the incoming device's saved name.
    _persisted = false;
    _settingDevice = true;
    try {
      await _sharedPrefs.setString(sharedPrefName, name);
      await _sharedPrefs.setString(sharedPrefHost, host);
      await _sharedPrefs.setInt(sharedPrefPort, port);
      await _sharedPrefs.setString(sharedPrefScheme, scheme);
    } finally {
      _persisted = true;
      _settingDevice = false;
    }
    state = _pointedAt(name, host, port, scheme);
  }

  /// A connection to [host]:[port], another server's choice unless that is
  /// the address in use.
  ConnectionSettings _pointedAt(
    String name,
    String host,
    int port,
    String scheme,
  ) {
    final same = (scheme: scheme, host: host, port: port) == state.address;
    return ConnectionSettings(
      name: name,
      host: host,
      port: port,
      scheme: scheme,
      serverChoice: same ? state.serverChoice : state.serverChoice + 1,
    );
  }

  /// Refresh the label from this server's saved settings without reconnecting.
  /// An onboarding connection remains session-only until it is committed.
  Future<void> updateName(String name) async {
    if (!state.isSet || name.trim().isEmpty || name == state.name) return;
    state = state.copyWith(name: name);
    if (_persisted) await _sharedPrefs.setString(sharedPrefName, name);
  }

  /// Follow the same server to [host]:[port], saved for the next launch
  /// unless the connection is for this session only. Its
  /// [ConnectionSettings.serverChoice] stays. Dropped while [setDevice]
  /// saves a connection, which would put back the address moved from as
  /// another server's choice.
  Future<void> moveTo(String host, int port) async {
    if (!state.isSet ||
        _settingDevice ||
        (host == state.host && port == state.port)) {
      return;
    }
    state = state.copyWith(host: host, port: port);
    if (!_persisted) return;
    await _sharedPrefs.setString(sharedPrefHost, host);
    await _sharedPrefs.setInt(sharedPrefPort, port);
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
    _persisted = false;
    state = _pointedAt(name, host, port, scheme);
  }

  /// Persist the current in-memory connection (after an ephemeral connect).
  Future<void> persist() async {
    if (!state.isSet) return;
    await setDevice(state.name, state.host, state.port, scheme: state.scheme);
  }

  /// Reset connection settings
  void reset() {
    _persisted = false;
    state = _pointedAt('', '', 0, 'http');
  }

  /// Clear stored device and reset to unconfigured state.
  Future<void> clearDevice() async {
    _persisted = false;
    await _sharedPrefs.remove(sharedPrefName);
    await _sharedPrefs.remove(sharedPrefHost);
    await _sharedPrefs.remove(sharedPrefPort);
    await _sharedPrefs.remove(sharedPrefScheme);
    state = _pointedAt('', '', 0, 'http');
  }

  @override
  ConnectionSettings build() {
    // Get SharedPreferences from the provider
    _sharedPrefs = ref.read(sharedPrefsProvider);
    _persisted = true;
    return _load();
  }
}

/// Provider for connection settings
final connectionSettingsProvider =
    NotifierProvider<ConnectionSettingsNotifier, ConnectionSettings>(
      ConnectionSettingsNotifier.new,
    );
