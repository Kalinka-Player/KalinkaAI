import 'dart:js_interop';

@JS('Intl.DateTimeFormat')
extension type _DateTimeFormat._(JSObject _) implements JSObject {
  external _DateTimeFormat();

  external _ResolvedOptions resolvedOptions();
}

extension type _ResolvedOptions._(JSObject _) implements JSObject {
  external String? get timeZone;
}

Future<String?> localTimezone() async {
  try {
    return _DateTimeFormat().resolvedOptions().timeZone;
  } catch (_) {
    return null;
  }
}
