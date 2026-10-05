// The demo server: where the app finds it, how it knows it is on one, and
// what a refused change looks like to the user.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:kalinka/data_model/presentation_schema.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/demo_mode.dart';
import 'package:kalinka/providers/demo_refusal.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/log_export_api.dart';
import 'package:kalinka/providers/renderer_host_provider.dart';
import 'package:kalinka/providers/settings_provider.dart';
import 'package:kalinka/providers/websocket_provider.dart';
import 'package:kalinka/renderer/renderer_backend.dart';
import 'package:kalinka/renderer/renderer_engine.dart';
import 'package:kalinka/renderer/renderer_identity.dart';

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
    ..interceptors.add(DemoRefusalInterceptor());
  return dio;
}

final _refusal = {
  'detail': {'code': 'demo_read_only', 'message': _reason},
};

class _Settings implements KalinkaPlayerProxy {
  _Settings(this.values, {this.held});

  final Map<String, dynamic> values;

  /// Holds the answer back until it completes.
  final Future<void>? held;

  @override
  Future<Map<String, dynamic>> getSettings() async {
    await held;
    return {'schema_version': 'v1', 'values': values, 'enum_options': const {}};
  }

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

Future<ProviderContainer> _connected(_Settings api) async {
  SharedPreferences.setMockInitialValues({
    ConnectionSettingsNotifier.sharedPrefHost: 'demo.test',
    ConnectionSettingsNotifier.sharedPrefPort: 443,
    ConnectionSettingsNotifier.sharedPrefScheme: 'https',
  });
  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(
        await SharedPreferences.getInstance(),
      ),
      kalinkaProxyProvider.overrideWithValue(api),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<bool> _demoModeOf(Map<String, dynamic> values) async {
  final container = await _connected(_Settings(values));
  await container.read(settingsProvider.notifier).loadConfig();
  return container.read(demoModeProvider);
}

Future<void> _moveToAnotherServer(ProviderContainer container) => container
    .read(connectionSettingsProvider.notifier)
    .setDevice('Home', 'nas.local', 8000);

class _SilentBackend implements RendererAudioBackend {
  @override
  Stream<BackendEvent> get events => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// How many times a browser hosting a renderer dials `/renderer/ws`.
Future<int> _rendererDials({required bool demo}) async {
  SharedPreferences.setMockInitialValues({});
  var dials = 0;
  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(
        await SharedPreferences.getInstance(),
      ),
      rendererEngineProvider.overrideWithValue(
        RendererEngine(_SilentBackend()),
      ),
      rendererIdentityProvider.overrideWith(
        (ref) async => const RendererIdentity(
          rendererId: 'r-1',
          instanceId: 'i-1',
          friendlyName: 'Chrome on Linux',
          softwareVersion: '1.2.3',
          os: 'web',
        ),
      ),
      demoModeProvider.overrideWithValue(demo),
      webSocketProvider.overrideWith((ref, path) {
        if (path == '/renderer/ws') dials++;
        return Completer<WebSocketChannel>().future;
      }),
    ],
  );
  addTearDown(container.dispose);
  await container.read(rendererIdentityProvider.future);
  container.read(rendererHostProvider);
  return dials;
}

void main() {
  test('the demo server is the public one unless a build names another', () {
    expect(demoServer(), (
      scheme: 'https',
      host: 'demo.kalinkaplayer.com',
      port: 443,
    ));
  });

  test('only a server that says so is taken for the demo', () async {
    expect(await saysItIsADemo(_Settings({demoModeFlagPath: true})), isTrue);
    expect(await saysItIsADemo(_Settings({demoModeFlagPath: false})), isFalse);
    expect(await saysItIsADemo(_Settings({})), isFalse);
  });

  test('the server says whether it is a demo', () async {
    expect(await _demoModeOf({demoModeFlagPath: true}), isTrue);
    expect(await _demoModeOf({demoModeFlagPath: false}), isFalse);
    expect(await _demoModeOf({}), isFalse);
  });

  test('a demo flag stays with the server that sent it', () async {
    final container = await _connected(_Settings({demoModeFlagPath: true}));
    await container.read(settingsProvider.notifier).loadConfig();
    expect(container.read(demoModeProvider), isTrue);

    await _moveToAnotherServer(container);
    expect(container.read(demoModeProvider), isFalse);
  });

  test(
    'settings still on their way from the last server are dropped',
    () async {
      final answer = Completer<void>();
      final container = await _connected(
        _Settings({demoModeFlagPath: true}, held: answer.future),
      );
      container.listen(settingsProvider, (_, _) {});
      final loading = container.read(settingsProvider.notifier).loadConfig();

      await _moveToAnotherServer(container);
      answer.complete();
      await loading;
      expect(container.read(settingsProvider).values, isEmpty);
      expect(container.read(demoModeProvider), isFalse);
    },
  );

  test('on the demo server the app hosts no renderer', () async {
    expect(await _rendererDials(demo: false), 1);
    expect(await _rendererDials(demo: true), 0);
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
      contains(isA<DemoRefusalInterceptor>()),
    );
  });

  group('a refusal', () {
    test('reads as the server worded it', () async {
      await expectLater(
        _answering(403, _refusal).put('/collections'),
        throwsA(
          isA<DemoRefusalException>()
              .having((e) => e.code, 'code', 'demo_read_only')
              .having((e) => e.reason, 'reason', _reason)
              .having((e) => '$e', 'text', _reason)
              .having((e) => e.response?.statusCode, 'status', 403),
        ),
      );
    });

    test('covers a full queue and a visitor slowed down', () async {
      for (final (status, code) in [
        (409, 'demo_queue_full'),
        (429, 'demo_rate_limited'),
      ]) {
        final body = {
          'detail': {'code': code, 'message': _reason},
        };
        await expectLater(
          _answering(status, body).post('/queue/add'),
          throwsA(
            isA<DemoRefusalException>()
                .having((e) => e.code, 'code', code)
                .having((e) => '$e', 'text', _reason),
          ),
        );
      }
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
              (e) => e is DemoRefusalException,
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
