import 'package:flutter/foundation.dart' show kIsWeb;

import '../utils/local_platform.dart';
import 'server_address.dart';
import 'web_origin.dart';

/// Dev-only (web): `host:port` of a CORS-enabled proxy to use instead of the
/// serving origin. See scripts/run_web_dev.sh.
const _webBackendOverride = String.fromEnvironment('KALINKA_WEB_BACKEND');

const _serverDefine = String.fromEnvironment('KALINKA_SERVER');

/// The server this run is tied to, or null to let the user find one. On the
/// web, the origin that served the app. Elsewhere `KALINKA_SERVER`, as a
/// dart-define or an environment variable, in any form [parseServerAddress]
/// reads — the display on the server's own screen is started with it.
ServerAddress? pinnedServer() {
  if (kIsWeb) {
    return parseServerAddress(_webBackendOverride) ?? webServingOrigin();
  }
  return parseServerAddress(_serverDefine) ??
      parseServerAddress(environmentValue('KALINKA_SERVER') ?? '');
}
