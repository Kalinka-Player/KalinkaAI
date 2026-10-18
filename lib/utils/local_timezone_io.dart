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
      // glibc reads TZ before /etc/localtime.
      final tz = Platform.environment['TZ'];
      if (tz != null && tz.isNotEmpty) return tz;
      try {
        return Link('/etc/localtime').targetSync();
      } on FileSystemException {
        return null;
      }
    default:
      return null;
  }
}
