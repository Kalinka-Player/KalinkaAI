import 'dart:io' show FileSystemException, Link, Platform;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';

const _native = MethodChannel('org.kalinka.kalinka/media_session');

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
    default:
      return null;
  }
}
