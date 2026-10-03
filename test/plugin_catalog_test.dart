import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/plugin_catalog.dart';
import 'package:kalinka/data_model/plugin_compatibility.dart';
import 'package:kalinka/providers/plugin_catalog_provider.dart';

Map<String, dynamic> _fixture() =>
    jsonDecode(File('test/fixtures/plugin_catalog.json').readAsStringSync())
        as Map<String, dynamic>;

class _Adapter implements HttpClientAdapter {
  final ResponseBody? response;
  final requests = <RequestOptions>[];
  _Adapter(this.response);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (response == null) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    return response!;
  }

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

(DioPluginCatalogApi, _Adapter) _api(ResponseBody? body) {
  final adapter = _Adapter(body);
  final client = Dio(BaseOptions(baseUrl: 'http://kalinka.local:8000'))
    ..httpClientAdapter = adapter;
  addTearDown(client.close);
  return (DioPluginCatalogApi(client), adapter);
}

void main() {
  test('catalog fixture uses the full product name in display metadata', () {
    final catalog = PluginCatalog.fromJson(_fixture());
    for (final plugin in catalog.plugins) {
      final displayText = [
        plugin.name,
        plugin.description,
        ...plugin.models,
        ...plugin.families,
        ...plugin.deviceNotes,
        for (final release in plugin.releases) ...release.notes,
      ];
      for (final text in displayText) {
        expect(
          RegExp(r'\bKalinka\b(?! Player\b)').hasMatch(text),
          isFalse,
          reason: '${plugin.id}: $text',
        );
      }
    }
  });

  test(
    'preserves server checks and never infers them from raw catalog declarations',
    () {
      final json = _fixture();
      expect(
        PluginCatalog.fromJson(
          json,
        ).plugins.every((p) => p.compatibility == null),
        true,
      );
      final blocked = {
        'version': '6.0',
        'channel': 'stable',
        'status': 'blocked',
        'reasons': [
          {
            'code': 'incompatible_server',
            'installed': '5.5',
            'required': '>=6',
          },
        ],
      };
      final qobuz = (json['plugins'] as List).singleWhere(
        (p) => p['id'] == 'qobuz',
      );
      qobuz['compatibility'] = {
        'status': 'metadata_compatible',
        'channel': 'stable',
        'latest_available_version': '6.0',
        'latest_compatible_version': '5.0.1',
        'newer_blocked_release': blocked,
        'releases': [
          blocked,
          {
            'version': '5.0.1',
            'channel': 'stable',
            'status': 'metadata_compatible',
            'reasons': [],
            'artifacts': [
              {
                'filename': 'qobuz.deb',
                'status': 'metadata_compatible',
                'reasons': [],
              },
              {
                'filename': 'other-platform.rpm',
                'status': 'blocked',
                'reasons': [
                  {'code': 'unsupported_package_format', 'format': 'rpm'},
                ],
              },
            ],
          },
        ],
        'installation_allowed': false,
      };
      final result = PluginCatalog.fromJson(
        json,
      ).plugins.singleWhere((p) => p.id == 'qobuz').compatibility!;
      expect(result.status, 'metadata_compatible');
      expect(result.latestAvailableVersion, '6.0');
      expect(result.latestCompatibleVersion, '5.0.1');
      expect(result.newerBlockedRelease!.explanations, [
        'Server 5.5 does not meet >=6.',
      ]);
      expect(result.release('5.0.1', 'stable')!.explanations, isEmpty);
      expect(result.release('5.0.1', 'beta'), isNull);
      expect(result.release('unknown', 'stable'), isNull);
      expect(
        result.release('5.0.1', 'stable')!.artifacts.first.filename,
        'qobuz.deb',
      );
    },
  );

  for (final component in ['server', 'sdk', 'python', 'renderer']) {
    test('explains $component versions and unknown versions', () {
      final mismatch = PluginCompatibilityReason.fromJson({
        'code': 'incompatible_$component',
        'required': '>=2',
        'installed': '1.0',
      });
      final unknown = PluginCompatibilityReason.fromJson({
        'code': '${component}_version_unknown',
        'required': '>=2',
      });
      expect(mismatch.message, contains('1.0 does not meet >=2.'));
      expect(unknown.message, contains('version is unknown; requires >=2.'));
    });
  }

  for (final (code, expected) in [
    ('release_withdrawn', 'withdrawn'),
    ('channel_not_selected', 'outside the selected channel'),
    ('release_not_yet_published', 'not yet published'),
    ('platform_unknown', 'Server platform is unknown'),
    ('architecture_unknown', 'Server architecture is unknown'),
    ('unsupported_platform', 'Server platform linux is not supported'),
    ('unsupported_architecture', 'Server architecture linux is not supported'),
    ('missing_capability', 'Missing server capability: test'),
    ('renderer_unavailable', 'Renderer is not connected'),
    ('renderer_protocol_incompatible', 'Renderer protocol is incompatible'),
    ('no_compatible_artifact', 'No package matches this server'),
    ('unsupported_package_format', 'Package format rpm is not supported'),
    ('invalid_package_metadata', 'Package metadata is inconsistent'),
    ('distribution_unknown', 'Server distribution or version is unknown'),
    (
      'unsupported_distribution',
      'Server distribution debian 12 is not supported',
    ),
    ('new_future_reason', 'cannot describe (new_future_reason)'),
  ]) {
    test('readable compatibility reason: $code', () {
      final reason = PluginCompatibilityReason.fromJson({
        'code': code,
        'required': ['aarch64', 'x86_64'],
        'actual': 'linux',
        'capability': 'test',
        'format': 'rpm',
        'id': 'debian',
        'version': '12',
      });
      expect(reason.message, contains(expected));
      if (code == 'unsupported_architecture') {
        expect(reason.message, contains('requires aarch64, x86_64'));
      }
    });
  }

  test(
    'real feed preserves types, publisher tiers and native requirements',
    () {
      final catalog = PluginCatalog.fromJson(_fixture());
      expect(catalog.plugins.length, 7);
      expect(
        catalog.plugins
            .where((p) => p.tier == 'official')
            .map((p) => p.id)
            .toSet(),
        {'jamendo', 'localfiles'},
      );
      final musiccast = catalog.plugins.singleWhere((p) => p.id == 'musiccast');
      expect(musiccast.isDevice, true);
      expect(musiccast.matches('yamaha extended'), true);
      expect(musiccast.models, isEmpty);
      expect(musiccast.deviceNotes.join(' '), contains('volume'));
      final spotify = catalog.plugins.singleWhere((p) => p.id == 'spotify');
      expect(spotify.isDevice, false);
      expect(spotify.section, 'Experimental');
      expect(spotify.releases.single.versions['renderer'], '>=0.5,<1');
      expect(spotify.releases.single.architectures.toSet(), {
        'x86_64',
        'aarch64',
      });
      final qobuz = catalog.plugins.singleWhere((p) => p.id == 'qobuz');
      expect(qobuz.releases.single.architectures, ['all']);
      expect(qobuz.releases.single.platforms, ['linux']);
      expect(qobuz.releases.single.packages.single, contains('debian 13'));
      expect(qobuz.releases.single.releaseNotes?.scheme, 'https');
    },
  );

  test('supported models and families participate in search', () {
    final json = _fixture();
    final musiccast = (json['plugins'] as List).singleWhere(
      (p) => p['id'] == 'musiccast',
    );
    musiccast['device_support']['models'] = ['Example AVR 100'];
    final plugin = PluginCatalog.fromJson(
      json,
    ).plugins.singleWhere((p) => p.id == 'musiccast');
    expect(plugin.matches('avr 100'), true);
    expect(plugin.matches('absent model'), false);
  });

  for (final url in [
    'http://example.org',
    'javascript:alert(1)',
    'https://user:password@example.org/',
  ]) {
    test('unsafe source link is not actionable: $url', () {
      final data = _fixture();
      data['plugins'][0]['source']['repository'] = url;
      expect(PluginCatalog.fromJson(data).plugins.first.source, isNull);
      final qobuz = (data['plugins'] as List).singleWhere(
        (p) => p['id'] == 'qobuz',
      );
      qobuz['releases'][0]['release_notes'] = url;
      expect(
        PluginCatalog.fromJson(data).plugins
            .singleWhere((p) => p.id == 'qobuz')
            .releases
            .single
            .releaseNotes,
        isNull,
      );
    });
  }

  test('browsing calls only the server cache with GET', () async {
    final (api, adapter) = _api(_json(200, _fixture()));
    expect((await api.read()).plugins.length, 7);
    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(
      request.uri.toString(),
      'http://kalinka.local:8000/server/plugins/catalog',
    );
  });

  test('503 is a catalog availability state, not an empty success', () async {
    final (api, _) = _api(_json(503, {'status': 'unavailable', 'plugins': []}));
    expect((await api.read()).status, 'unavailable');
  });

  test('stale metadata stays explicitly stale', () async {
    final (api, _) = _api(
      _json(200, {..._fixture(), 'status': 'stale', 'error': 'timeout'}),
    );
    final result = await api.read();
    expect(result.status, 'stale');
    expect(result.plugins.length, 7);
  });

  for (final status in [403, 404]) {
    test('$status becomes a readable refusal', () async {
      final (api, _) = _api(_json(status, {}));
      await expectLater(api.read(), throwsA(isA<PluginCatalogException>()));
    });
  }

  test('old server HTML and malformed metadata fail safely', () async {
    for (final body in [
      ResponseBody.fromString('<html>install page</html>', 200),
      _json(200, {
        'status': 'available',
        'plugins': ['wrong'],
      }),
      _json(200, {'status': 'unknown'}),
    ]) {
      final (api, _) = _api(body);
      await expectLater(api.read(), throwsA(isA<PluginCatalogException>()));
    }
  });

  test('connection failure has no raw network details', () async {
    final (api, _) = _api(null);
    await expectLater(
      api.read(),
      throwsA(
        isA<PluginCatalogException>().having(
          (e) => e.message,
          'message',
          contains('Check the server connection'),
        ),
      ),
    );
  });
}
