import 'wasm_renderer_preference_io.dart'
    if (dart.library.js_interop) 'wasm_renderer_preference_web.dart'
    as impl;

/// Whether the web app is set to try the WebAssembly (skwasm) renderer.
/// web/index.html reads the same storage key before the Flutter engine
/// starts, since the renderer is fixed for the lifetime of a page load —
/// this only reports what was chosen for the load in progress. Always
/// false off web.
bool get useWasmPreference => impl.useWasmPreference;

/// Persists [value] for the next load and reloads the page to apply it.
/// No-op off web.
void setUseWasmPreference(bool value) => impl.setUseWasmPreference(value);
