import 'local_platform_io.dart'
    if (dart.library.js_interop) 'local_platform_web.dart'
    as impl;

/// A process environment variable, or null — always null in the browser.
String? environmentValue(String name) => impl.environmentValue(name);

/// This machine's hostname, or null in the browser.
String? localHostname() => impl.localHostname();

/// Whether [error], the cause of a failed connection, says nothing listens
/// at the port. The browser hides why a connection failed, so there every
/// failure counts as a refusal.
bool connectionRefused(Object? error) => impl.connectionRefused(error);
