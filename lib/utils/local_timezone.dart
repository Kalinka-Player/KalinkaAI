import 'local_timezone_io.dart'
    if (dart.library.js_interop) 'local_timezone_web.dart'
    as impl;

/// This device's time zone as tzdata names it, such as `Europe/London`; null
/// where the platform names none.
Future<String?> localTimezone() async {
  final value = await impl.localTimezone();
  return value == null ? null : zoneNamed(value);
}

final _zoneName = RegExp(r'^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)*$');

/// The tzdata name in [value], which may also be a path into a zoneinfo
/// directory, as `/etc/localtime` links to, or start with the `:` glibc
/// allows in `TZ`. Null for a POSIX rule or a bare offset, which the box
/// would refuse.
String? zoneNamed(String value) {
  var name = value.startsWith(':') ? value.substring(1) : value;
  const directory = 'zoneinfo/';
  final at = name.lastIndexOf(directory);
  if (at >= 0) name = name.substring(at + directory.length);
  // Some distributions link /etc/localtime into zoneinfo/posix/ or right/.
  for (final prefix in const ['posix/', 'right/']) {
    if (name.startsWith(prefix)) name = name.substring(prefix.length);
  }
  return name.length <= 64 && _zoneName.hasMatch(name) ? name : null;
}
