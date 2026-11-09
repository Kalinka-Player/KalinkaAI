/// Whether this build's Dart code was compiled to WebAssembly (dart2wasm)
/// rather than JavaScript (dart2js). In the current Flutter web build the two
/// compile targets are paired 1:1 with a renderer — dart2wasm always runs
/// with skwasm, dart2js with CanvasKit — so this one constant also tells us
/// the renderer that's active. `false` on every non-web platform.
const compiledToWasm = bool.fromEnvironment('dart.tool.dart2wasm');

/// [value] for `Image.network`'s cacheWidth/cacheHeight, or null on a wasm
/// build. skwasm_heavy (Firefox's variant) corrupts that decode-at-reduced-
/// size path entirely — same machinery as ResizeImage — so every call site
/// that sizes a network image down at decode time routes the value through
/// this instead of passing it directly, and decodes at native size on wasm,
/// relying on the widget's own fit/BoxFit to scale it down after.
int? wasmSafeCacheSize(int? value) => compiledToWasm ? null : value;
