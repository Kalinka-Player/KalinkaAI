import 'package:web/web.dart' as web;

/// A reload must retain ownership of the connection attempt in this tab.
String restoreSetupSession(String fallback) {
  const key = 'kalinka.setup.client';
  try {
    final previous = web.window.sessionStorage.getItem(key);
    if (previous != null && RegExp(r'^[a-f0-9]{32}$').hasMatch(previous)) {
      return previous;
    }
    web.window.sessionStorage.setItem(key, fallback);
  } catch (_) {
    // Storage can be unavailable in a captive browser or private mode.
  }
  return fallback;
}
