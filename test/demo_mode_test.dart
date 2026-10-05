// The demo server: where the app finds it, how it knows it is on one, and
// what a refused change looks like to the user.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/presentation_schema.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/demo_mode.dart';
import 'package:kalinka/providers/demo_refusal.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/log_export_api.dart';
import 'package:kalinka/providers/settings_provider.dart';

const _reason = 'This is a read-only demo server.';

class _Answer implements HttpClientAdapter {
  _Answer(this.status, this.body);

  final int status;
  final Object body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

Dio _answering(int status, Object body) {
  final dio = Dio(BaseOptions(baseUrl: 'http://server.test'))
    ..httpClientAdapter = _Answer(status, body)
    ..interceptors.add(DemoReadOnlyInterceptor());
  return dio;
}

final _refusal = {
  'detail': {'code': 'demo_read_only', 'message': _reason},
};

class _Settings implements KalinkaPlayerProxy {
  _Settings(this.values);

  final Map<String, dynamic> values;

  @override
  Future<Map<String, dynamic>> getSettings() async => {
    'schema_version': 'v1',
    'values': values,
    'enum_options': const {},
  };

  @override
  Future<PresentationSchema> getSettingsSchema() async =>
      const PresentationSchema(
        schemaVersion: 'v1',
        pages: [],
        expertFields: [],
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Future<bool> _demoModeOf(Map<String, dynamic> values) async {
  final container = ProviderContainer(
    overrides: [kalinkaProxyProvider.overrideWithValue(_Settings(values))],
  );
  addTearDown(container.dispose);
  await container.read(settingsProvider.notifier).loadConfig();
  return container.read(demoModeProvider);
}

void main() {
  test('the demo server is the public one unless a build names another', () {
    expect(demoServer(), (
      scheme: 'https',
      host: 'demo.kalinkaplayer.com',
      port: 443,
    ));
  });

  test('the server says whether it is a demo', () async {
    expect(await _demoModeOf({demoModeFlagPath: true}), isTrue);
    expect(await _demoModeOf({demoModeFlagPath: false}), isFalse);
    expect(await _demoModeOf({}), isFalse);
  });

  test('every request the app makes can be refused as a demo', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    expect(
      container.read(httpClientProvider).interceptors,
      contains(isA<DemoReadOnlyInterceptor>()),
    );
  });

  group('a refusal', () {
    test('reads as the server worded it', () async {
      await expectLater(
        _answering(403, _refusal).put('/collections'),
        throwsA(
          isA<DemoReadOnlyException>()
              .having((e) => e.reason, 'reason', _reason)
              .having((e) => '$e', 'text', _reason)
              .having((e) => e.response?.statusCode, 'status', 403),
        ),
      );
    });

    test('is told apart from any other 403 or error', () async {
      final other = {
        'detail': {'code': 'plugin_catalog_disabled', 'message': 'Off'},
      };
      for (final (status, body) in [(403, other), (500, _refusal)]) {
        await expectLater(
          _answering(status, body).put('/collections'),
          throwsA(
            isA<DioException>().having(
              (e) => e is DemoReadOnlyException,
              'is a demo refusal',
              isFalse,
            ),
          ),
        );
      }
    });

    test(
      'keeps its words through calls that name their own failures',
      () async {
        final api = KalinkaPlayerProxyImpl(client: _answering(403, _refusal));
        await expectLater(
          api.setActiveRenderer('demo-output'),
          throwsA(
            isA<RendererSwitchException>().having(
              (e) => e.message,
              'message',
              _reason,
            ),
          ),
        );
        await expectLater(
          api.updateRendererConfig('demo-output', {'output.device': 'hw:0'}),
          throwsA(
            isA<RendererConfigException>().having(
              (e) => e.message,
              'message',
              _reason,
            ),
          ),
        );
        await expectLater(
          DioLogExportApi(_answering(403, _refusal)).start(
            lookback: const Duration(hours: 1),
            includeLocalRenderer: false,
          ),
          throwsA(
            isA<LogExportException>().having(
              (e) => e.message,
              'message',
              _reason,
            ),
          ),
        );
      },
    );
  });
}
