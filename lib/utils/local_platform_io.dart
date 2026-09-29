import 'dart:io' show Platform;

String? environmentValue(String name) => Platform.environment[name];

String? localHostname() {
  try {
    return Platform.localHostname;
  } catch (_) {
    return null;
  }
}
