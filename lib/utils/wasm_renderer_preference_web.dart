import 'package:web/web.dart' as web;

/// Read by web/index.html's bootstrap script before `_flutter.loader.load`
/// — keep the key in sync with the one there.
const _storageKey = 'kalinka.useWasm';

bool get useWasmPreference =>
    web.window.localStorage.getItem(_storageKey) == '1';

void setUseWasmPreference(bool value) {
  if (value) {
    web.window.localStorage.setItem(_storageKey, '1');
  } else {
    web.window.localStorage.removeItem(_storageKey);
  }
  web.window.location.reload();
}
