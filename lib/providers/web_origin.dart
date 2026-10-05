import 'server_address.dart';
import 'web_origin_io.dart'
    if (dart.library.js_interop) 'web_origin_web.dart'
    as impl;

/// The address the web app was served from, or `null` on native platforms.
ServerAddress? webServingOrigin() => impl.webServingOrigin();
