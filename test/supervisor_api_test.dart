import 'dart:convert';
import 'dart:io' show OSError, SocketException;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/supervisor_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answers each request from [reply], or fails to connect when it is null.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.reply);

  final ResponseBody? Function(RequestOptions options) reply;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final response = reply(options);
    if (response == null) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'connection refused',
      );
    }
    return response;
  }

  @override
  void close({bool force = false}) {}
}

/// Fails each request with what [fail] makes of it.
class _Failing implements HttpClientAdapter {
  _Failing(this.fail);

  final DioException Function(RequestOptions options) fail;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => throw fail(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

ResponseBody _refusal(int status, String code) => _json(status, {
  'detail': {'code': code, 'message': 'developer wording'},
});

const _info = {
  'name': 'kalinka-supervisor',
  'version': '0.2.0',
  'protocol': 1,
  'min_protocol': 1,
  'server_id': 'box-1',
  'actions': ['restart_core', 'reboot', 'poweroff', 'reinstall'],
};

(DioSupervisorApi, _Adapter) _api(
  ResponseBody? Function(RequestOptions) reply,
) {
  final adapter = _Adapter(reply);
  final dio = Dio(BaseOptions(baseUrl: 'http://kalinka.local:8001'))
    ..httpClientAdapter = adapter;
  return (DioSupervisorApi(dio), adapter);
}

void main() {
  group('sleep timer', () {
    test('reads capability, status and rounded minutes', () async {
      final (api, adapter) = _api(
        (request) => request.path == '/info'
            ? _json(200, {..._info, 'poweroff_schedule': true})
            : _json(200, {
                'server_id': 'box-1',
                'state': 'scheduled',
                'remaining_seconds': 61,
              }),
      );
      expect((await api.info())!.supportsPowerOffSchedule, isTrue);
      final status = (await api.powerStatus())!;
      expect(status.remainingMinutes, 2);
      expect(status.countdownLabel, 'Power off in 2 minutes');
      expect(adapter.requests.last.path, '/v1/power-off');
      expect(
        const BoxPowerStatus(
          serverId: 'box-1',
          state: 'scheduled',
          remainingSeconds: 1,
        ).countdownLabel,
        'Power off in 1 minute',
      );
    });

    test('schedules and cancels with identity and numeric delay', () async {
      final (api, adapter) = _api((_) => _json(200, {}));
      await api.schedulePowerOff(60, serverId: 'box-1');
      await api.cancelPowerOff(serverId: 'box-1');
      expect(adapter.requests[0].method, 'POST');
      expect(adapter.requests[0].path, '/v1/actions/schedule_poweroff');
      expect(adapter.requests[0].data, {'server_id': 'box-1', 'minutes': 60});
      expect(adapter.requests[1].path, '/v1/actions/cancel_poweroff');
      expect(adapter.requests[1].data, {'server_id': 'box-1'});
    });

    test('refusals surface for scheduling and cancellation', () async {
      final (api, _) = _api((_) => _refusal(409, 'shutting_down'));
      final refusal = isA<BoxActionException>().having(
        (e) => e.code,
        'code',
        'shutting_down',
      );
      await expectLater(
        api.schedulePowerOff(30, serverId: 'box-1'),
        throwsA(refusal),
      );
      await expectLater(
        api.cancelPowerOff(serverId: 'box-1'),
        throwsA(refusal),
      );
    });

    test('unreachable or malformed status never invents a countdown', () async {
      final (api, _) = _api((_) => null);
      expect(await api.powerStatus(), isNull);
      for (final value in [
        null,
        {},
        {'server_id': 'box-1', 'state': 'scheduled'},
        {'server_id': 'box-1', 'state': 'scheduled', 'remaining_seconds': -1},
        {'server_id': 'box-1', 'state': 'scheduled', 'remaining_seconds': '60'},
        {'server_id': 'box-1', 'state': 'unknown'},
      ]) {
        expect(BoxPowerStatus.fromJson(value), isNull);
      }
      for (final state in ['on', 'powering_off', 'restarting']) {
        expect(
          BoxPowerStatus.fromJson({'server_id': 'box-1', 'state': state})!
              .remainingMinutes,
          isNull,
        );
      }
    });
  });

  group('info', () {
    test('reads the supervisor and what it offers', () async {
      final (api, adapter) = _api((_) => _json(200, _info));

      final info = (await api.info())!;

      expect(adapter.requests.single.path, '/info');
      expect(info.version, '0.2.0');
      expect(info.serverId, 'box-1');
      expect(info.compatible, isTrue);
      expect(info.offers(BoxAction.powerOff), isTrue);
      expect(info.offers(BoxAction.restartServer), isTrue);
      expect(info.supportsPowerOffTimer, isFalse);
    });

    test('reads inactivity timer support when advertised', () async {
      final (api, _) = _api(
        (_) => _json(200, {..._info, 'poweroff_timer': true}),
      );
      expect((await api.info())!.supportsPowerOffTimer, isTrue);
    });

    test('is absent when nothing answers', () async {
      final (api, _) = _api((_) => null);
      expect(await api.info(), isNull);
    });

    test('is absent when something else holds the port', () async {
      final (api, _) = _api(
        (_) => _json(200, {'name': 'other', 'protocol': 1}),
      );
      expect(await api.info(), isNull);
    });

    test('is absent when the port answers 404', () async {
      final (api, _) = _api((_) => _json(404, {'detail': 'Not Found'}));
      expect(await api.info(), isNull);
    });

    test('a supervisor without an action offers none of it', () async {
      final (api, _) = _api(
        (_) => _json(200, {
          ..._info,
          'actions': ['restart_core'],
        }),
      );
      expect((await api.info())!.offers(BoxAction.powerOff), isFalse);
    });

    test('a box whose server never ran has no identity', () async {
      final (api, _) = _api((_) => _json(200, {..._info, 'server_id': null}));
      expect((await api.info())!.serverId, isNull);
    });
  });

  group('probe', () {
    DioSupervisorApi failing(DioException Function(RequestOptions) fail) =>
        DioSupervisorApi(
          Dio(BaseOptions(baseUrl: 'http://kalinka.local:8001'))
            ..httpClientAdapter = _Failing(fail),
        );

    DioException socket(RequestOptions options, String message, int errno) =>
        DioException.connectionError(
          requestOptions: options,
          reason: message,
          error: SocketException(message, osError: OSError(message, errno)),
        );

    test('a supervisor answers', () async {
      final (api, _) = _api((_) => _json(200, _info));
      final (:reach, :info) = await api.probe();
      expect(reach, SupervisorReach.answered);
      expect(info!.serverId, 'box-1');
    });

    test('a refused connection means no supervisor listens', () async {
      final api = failing((o) => socket(o, 'Connection refused', 111));
      final (:reach, :info) = await api.probe();
      expect(reach, SupervisorReach.absent);
      expect(info, isNull);
    });

    test('something else on the port is no supervisor', () async {
      for (final reply in [
        _json(404, {'detail': 'Not Found'}),
        _json(200, {'name': 'other', 'protocol': 1}),
      ]) {
        final (api, _) = _api((_) => reply);
        expect((await api.probe()).reach, SupervisorReach.absent);
      }
    });

    test('a supervisor that fails did not answer', () async {
      final (api, _) = _api((_) => _json(503, {'detail': 'busy'}));
      expect((await api.probe()).reach, SupervisorReach.silent);
    });

    test('a timeout or a lost route is a box that did not answer', () async {
      for (final api in [
        failing(
          (o) => DioException.connectionTimeout(
            requestOptions: o,
            timeout: const Duration(seconds: 5),
          ),
        ),
        failing((o) => socket(o, 'No route to host', 113)),
      ]) {
        expect((await api.probe()).reach, SupervisorReach.silent);
      }
    });
  });

  test('protocol compatibility follows the supervisor range', () {
    SupervisorInfo info(int protocol, int min) => SupervisorInfo(
      version: '',
      protocol: protocol,
      minProtocol: min,
      serverId: 'box-1',
      actions: const {},
    );
    expect(info(1, 1).compatible, isTrue);
    expect(info(3, 1).compatible, isTrue, reason: 'a newer box keeps v1');
    expect(info(3, 2).compatible, isFalse, reason: 'v1 dropped');
  });

  group('run', () {
    test('posts the action with the server it is meant for', () async {
      final (api, adapter) = _api((_) => _json(202, {'action': 'poweroff'}));

      await api.run(BoxAction.powerOff, serverId: 'box-1');

      final sent = adapter.requests.single;
      expect(sent.method, 'POST');
      expect(sent.path, '/v1/actions/poweroff');
      expect(sent.data, {'server_id': 'box-1'});
      expect(sent.contentType, startsWith('application/json'));
    });

    test('names each action as the API does', () {
      expect(BoxAction.restartServer.wire, 'restart_core');
      expect(BoxAction.reboot.wire, 'reboot');
      expect(BoxAction.powerOff.wire, 'poweroff');
    });

    test('words a refusal for the person who asked', () async {
      final (api, _) = _api((_) => _refusal(409, 'upgrade_in_progress'));

      await expectLater(
        api.run(BoxAction.reboot, serverId: 'box-1'),
        throwsA(
          isA<BoxActionException>()
              .having((e) => e.code, 'code', 'upgrade_in_progress')
              .having((e) => e.message, 'message', contains('being updated')),
        ),
      );
    });

    test('an unknown refusal still reads as one', () async {
      final (api, _) = _api((_) => _refusal(503, 'unavailable'));

      await expectLater(
        api.run(BoxAction.reboot, serverId: 'box-1'),
        throwsA(
          isA<BoxActionException>()
              .having((e) => e.code, 'code', 'unavailable')
              .having(
                (e) => e.message,
                'message',
                'The streamer could not do that.',
              ),
        ),
      );
    });

    test('silence is reported as the box not answering', () async {
      final (api, _) = _api((_) => null);

      await expectLater(
        api.run(BoxAction.reboot, serverId: 'box-1'),
        throwsA(
          isA<BoxActionException>().having(
            (e) => e.code,
            'code',
            'unreachable',
          ),
        ),
      );
    });
  });

  group('serverState', () {
    test('reads the server state from the status', () async {
      final (api, adapter) = _api(
        (_) => _json(200, {'core': 'activating', 'upgrading': false}),
      );
      expect(await api.serverState(), 'activating');
      expect(adapter.requests.single.path, '/v1/status');
    });

    test('is unknown when the box does not answer', () async {
      final (api, _) = _api((_) => null);
      expect(await api.serverState(), isNull);
    });
  });

  group('time zone', () {
    test('a box offers it once its supervisor lists the action', () async {
      final (older, _) = _api((_) => _json(200, _info));
      final (newer, _) = _api(
        (_) => _json(200, {
          ..._info,
          'actions': [..._info['actions'] as List, 'set_timezone'],
        }),
      );
      expect((await older.info())!.setsTimezone, isFalse);
      expect((await newer.info())!.setsTimezone, isTrue);
    });

    test('reads the zone the box is on from its status', () async {
      final (api, adapter) = _api(
        (_) => _json(200, {'core': 'active', 'timezone': 'Europe/London'}),
      );
      expect(await api.timezone(), 'Europe/London');
      expect(adapter.requests.single.path, '/v1/status');
    });

    test('is unknown when the box names no zone or does not answer', () async {
      final (unnamed, _) = _api(
        (_) => _json(200, {'core': 'active', 'timezone': null}),
      );
      final (silent, _) = _api((_) => null);
      expect(await unnamed.timezone(), isNull);
      expect(await silent.timezone(), isNull);
    });

    test('lists the zones the box offers', () async {
      final (api, adapter) = _api(
        (_) => _json(200, {
          'timezones': ['Europe/London', 5, 'UTC'],
        }),
      );
      expect(await api.timezones(), ['Europe/London', 'UTC']);
      expect(adapter.requests.single.path, '/v1/timezones');
    });

    test('sets a zone, naming the box, and returns the one it set', () async {
      final (api, adapter) = _api(
        (_) =>
            _json(202, {'action': 'set_timezone', 'timezone': 'Asia/Kolkata'}),
      );

      final set = await api.setTimezone(
        'Asia/Calcutta',
        const BoxIdentity(serverId: 'box-1'),
      );

      expect(set, 'Asia/Kolkata');
      final sent = adapter.requests.single;
      expect(sent.method, 'POST');
      expect(sent.path, '/v1/actions/set_timezone');
      expect(sent.data, {'server_id': 'box-1', 'timezone': 'Asia/Calcutta'});
      expect(sent.receiveTimeout, greaterThan(const Duration(seconds: 30)));
    });

    test('words a zone the box does not have', () async {
      final (api, _) = _api((_) => _refusal(400, 'unknown_timezone'));

      await expectLater(
        api.setTimezone('Mars/Olympus', const BoxIdentity(serverId: 'box-1')),
        throwsA(
          isA<BoxActionException>().having(
            (e) => e.message,
            'message',
            'The streamer does not have that time zone. Choose one from its '
                'list.',
          ),
        ),
      );
    });
  });

  group('supervisorApiProvider', () {
    Future<SupervisorApi?> read(Map<String, Object> stored) async {
      SharedPreferences.setMockInitialValues(stored);
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      return container.read(supervisorApiProvider);
    }

    test('points at the supervisor port on the server host', () async {
      final api = await read({
        'Kalinka.host': '192.168.1.50',
        'Kalinka.port': 8000,
      });
      expect(api!.page, Uri.parse('http://192.168.1.50:8001/'));
    });

    test('brackets an IPv6 host', () async {
      final api = await read({'Kalinka.host': 'fe80::1', 'Kalinka.port': 8000});
      expect(api!.page.toString(), 'http://[fe80::1]:8001/');
    });

    test('is absent for a server behind TLS', () async {
      expect(
        await read({
          'Kalinka.host': 'demo.kalinkaplayer.com',
          'Kalinka.port': 443,
          'Kalinka.scheme': 'https',
        }),
        isNull,
      );
    });

    test('is absent with no server chosen', () async {
      expect(await read({}), isNull);
    });
  });
}
