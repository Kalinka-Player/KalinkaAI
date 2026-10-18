import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/utils/local_timezone.dart';

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

    test('names none for a phone set to a bare offset', () async {
      messenger.setMockMethodCallHandler(_native, (_) async => 'GMT+05:30');
      expect(await localTimezone(), isNull);
    });

    test('names none when the app cannot say', () async {
      expect(await localTimezone(), isNull);
    });
  });

  test('Windows names no tzdata zone', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(await localTimezone(), isNull);
  });
}
