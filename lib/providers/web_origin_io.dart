import 'server_address.dart';

/// Native platforms are not served from a web origin.
ServerAddress? webServingOrigin() => null;
