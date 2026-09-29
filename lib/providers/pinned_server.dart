import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;

import '../utils/local_platform.dart';
import 'web_origin.dart';

typedef HostPort = ({String host, int port});

/// Dev-only (web): `host:port` of a CORS-enabled proxy to use instead of the
/// serving origin. See scripts/run_web_dev.sh.
const _webBackendOverride = String.fromEnvironment('KALINKA_WEB_BACKEND');

const _serverDefine = String.fromEnvironment('KALINKA_SERVER');

/// The server this run is tied to, or null to let the user find one. On the
/// web, the origin that served the app. Elsewhere `KALINKA_SERVER=host:port`,
/// as a dart-define or an environment variable — the display on the server's
/// own screen is started with it.
HostPort? pinnedServer() {
  if (kIsWeb) return parseHostPort(_webBackendOverride) ?? webServingOrigin();
  return parseHostPort(_serverDefine) ??
      parseHostPort(environmentValue('KALINKA_SERVER') ?? '');
}

@visibleForTesting
HostPort? parseHostPort(String value) {
  final sep = value.lastIndexOf(':');
  if (sep <= 0) return null;
  final port = int.tryParse(value.substring(sep + 1));
  if (port == null || port <= 0 || port > 65535) return null;
  return (host: value.substring(0, sep).trim(), port: port);
}
