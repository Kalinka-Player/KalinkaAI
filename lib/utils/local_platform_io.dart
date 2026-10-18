import 'dart:io' show Platform, SocketException;

String? environmentValue(String name) => Platform.environment[name];

String? localHostname() {
  try {
    return Platform.localHostname;
  } catch (_) {
    return null;
  }
}

/// ECONNREFUSED on Linux and Android, macOS, and Windows.
const _refused = {111, 61, 10061};

bool connectionRefused(Object? error) =>
    error is SocketException && _refused.contains(error.osError?.errorCode);
