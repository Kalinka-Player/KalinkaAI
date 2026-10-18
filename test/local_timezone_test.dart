import 'dart:io' show ProcessException, ProcessResult;
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/utils/local_timezone.dart';
import 'package:kalinka/utils/local_timezone_io.dart'
    show ProcessRunner, windowsTimezone;

const _native = MethodChannel('org.kalinka.kalinka/media_session');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('zoneNamed', () {
    test('keeps a tzdata name', () {
      for (final zone in [
        'Europe/London',
        'America/Argentina/Buenos_Aires',
        'Etc/GMT+5',
        'UTC',
      ]) {
        expect(zoneNamed(zone), zone);
      }
    });

    test('reads the zone a localtime link or a TZ path points into', () {
      expect(zoneNamed('/usr/share/zoneinfo/Europe/Berlin'), 'Europe/Berlin');
      expect(zoneNamed('../usr/share/zoneinfo/Asia/Tokyo'), 'Asia/Tokyo');
      expect(
        zoneNamed('/var/db/timezone/zoneinfo/America/New_York'),
        'America/New_York',
      );
      expect(zoneNamed(':Europe/Paris'), 'Europe/Paris');
      expect(
        zoneNamed('/usr/share/zoneinfo/posix/Europe/London'),
        'Europe/London',
      );
      expect(
        zoneNamed('/usr/share/zoneinfo/right/Europe/London'),
        'Europe/London',
      );
    });

    test('names no zone for a rule, an offset or another path', () {
      for (final value in [
        'CET-1CEST,M3.5.0,M10.5.0/3',
        'GMT+05:30',
        '/etc/localtime',
        '../Europe/London',
        '',
      ]) {
        expect(zoneNamed(value), isNull, reason: value);
      }
    });
  });

  group('on Android', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(_native, null);
    });

    test('asks the app for the phone’s zone', () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(_native, (call) async {
        calls.add(call.method);
        return 'Asia/Kolkata';
      });
      expect(await localTimezone(), 'Asia/Kolkata');
      expect(calls, ['timeZone']);
    });

    test('names an old zone by the name the box knows', () async {
      messenger.setMockMethodCallHandler(_native, (_) async => 'Asia/Calcutta');
      expect(await localTimezone(), 'Asia/Kolkata');
    });

    test('names none for a phone set to a bare offset', () async {
      messenger.setMockMethodCallHandler(_native, (_) async => 'GMT+05:30');
      expect(await localTimezone(), isNull);
    });

    test('names none when the app cannot say', () async {
      expect(await localTimezone(), isNull);
    });
  });

  group('on Windows', () {
    final calls = <List<String>>[];
    ProcessRunner tzutil(String output, {int exitCode = 0}) =>
        (executable, arguments) async {
          calls.add([executable, ...arguments]);
          return ProcessResult(0, exitCode, output, '');
        };

    setUp(calls.clear);

    test('maps the zone tzutil prints to its tzdata name', () async {
      final zone = await windowsTimezone(
        run: tzutil('W. Europe Standard Time\r\n'),
      );
      expect(zone, 'Europe/Berlin');
      expect(calls, [
        ['tzutil', '/g'],
      ]);
    });

    test('picks the zone of the country the locale names', () async {
      final dispatcher = TestWidgetsFlutterBinding.instance.platformDispatcher;
      dispatcher.localeTestValue = const Locale('de', 'CH');
      addTearDown(dispatcher.clearLocaleTestValue);
      expect(
        await windowsTimezone(run: tzutil('W. Europe Standard Time\r\n')),
        'Europe/Zurich',
      );
    });

    test('names none when tzutil fails or is missing', () async {
      expect(await windowsTimezone(run: tzutil('', exitCode: 1)), isNull);
      expect(
        await windowsTimezone(
          run: (executable, arguments) async =>
              throw ProcessException(executable, arguments),
        ),
        isNull,
      );
    });

    test('names none for a zone the table does not know', () async {
      expect(
        await windowsTimezone(run: tzutil('Mars Standard Time\r\n')),
        isNull,
      );
    });
  });
}
