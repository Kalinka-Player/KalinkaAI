import 'dart:io'
    show
        FileSystemException,
        Link,
        Platform,
        Process,
        ProcessException,
        ProcessResult;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';

import '../data_model/windows_zones.dart';

const _native = MethodChannel('org.kalinka.kalinka/media_session');

typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

Future<String?> localTimezone() async {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      try {
        return await _native.invokeMethod<String>('timeZone');
      } catch (_) {
        return null;
      }
    case TargetPlatform.linux || TargetPlatform.macOS:
      // glibc reads TZ before /etc/localtime. A TZ such as :/etc/localtime
      // names a file, which may itself be a link into zoneinfo.
      final tz = Platform.environment['TZ'] ?? '';
      final file = tz.startsWith(':/') ? tz.substring(1) : null;
      if (tz.isNotEmpty && file == null) return tz;
      try {
        return Link(file ?? '/etc/localtime').targetSync();
      } on FileSystemException {
        return file;
      }
    case TargetPlatform.windows:
      return windowsTimezone();
    default:
      return null;
  }
}

/// The zone Windows is on, by its tzdata name. [run] stands in for
/// [Process.run] in tests.
Future<String?> windowsTimezone({ProcessRunner run = Process.run}) async {
  // tzutil prints the zone's ID, which stays the same in every language;
  // DateTime.timeZoneName is a display name in the user's own.
  final ProcessResult result;
  try {
    result = await run('tzutil', const ['/g']);
  } on ProcessException {
    return null;
  }
  final id = result.stdout;
  if (result.exitCode != 0 || id is! String) return null;
  final country =
      ServicesBinding.instance.platformDispatcher.locale.countryCode;
  // tzutil appends _dstoff when daylight saving is turned off.
  final zone = id.trim().replaceFirst(RegExp(r'_dstoff$'), '');
  return tzdataZoneFor(zone, territory: country);
}
