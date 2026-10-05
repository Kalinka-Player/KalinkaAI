import 'package:web/web.dart' as web;

import 'server_address.dart';

/// Derive the serving address from `window.location`. An empty port means
/// the protocol default (443 for https, else 80).
ServerAddress? webServingOrigin() {
  final loc = web.window.location;
  final host = loc.hostname;
  if (host.isEmpty) return null;
  final scheme = loc.protocol == 'https:' ? 'https' : 'http';
  final portStr = loc.port;
  final port = portStr.isNotEmpty
      ? (int.tryParse(portStr) ?? 0)
      : (scheme == 'https' ? 443 : 80);
  if (port <= 0) return null;
  return (scheme: scheme, host: host, port: port);
}
