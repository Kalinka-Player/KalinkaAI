/// Where a Kalinka server answers: `http` on a local network, `https` behind
/// a TLS proxy such as the public demo server.
typedef ServerAddress = ({String scheme, String host, int port});

const _schemes = {'http', 'https'};

/// `host:port` (plain HTTP), `scheme://host` or `scheme://host:port`, for
/// http and https only; null for anything else.
ServerAddress? parseServerAddress(String value) {
  final text = value.trim();
  if (text.contains('://')) {
    final uri = Uri.tryParse(text);
    if (uri == null || !_schemes.contains(uri.scheme) || uri.host.isEmpty) {
      return null;
    }
    // Uri.port is the scheme's default when the text names none.
    if (uri.port <= 0 || uri.port > 65535) return null;
    return (scheme: uri.scheme, host: uri.host, port: uri.port);
  }
  final sep = text.lastIndexOf(':');
  if (sep <= 0) return null;
  final port = int.tryParse(text.substring(sep + 1));
  if (port == null || port <= 0 || port > 65535) return null;
  return (scheme: 'http', host: text.substring(0, sep).trim(), port: port);
}
