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

  test('preserves server checks and never infers them from raw catalog declarations', () {
    final json = _fixture();
    expect(
      PluginCatalog.fromJson(json).plugins
          .every((p) => p.compatibility == null),
      true,
    );
    final blocked = {
      'version': '6.0',
      'channel': 'stable',
      'status': 'blocked',
      'reasons': [
        {'code': 'incompatible_server', 'installed': '5.5', 'required': '>=6'},
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
    final result = PluginCatalog.fromJson(json).plugins
        .singleWhere((p) => p.id == 'qobuz')
        .compatibility!;
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
  });

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
      expect(musiccast.models, isEmpty);
      expect(musiccast.deviceNotes.join(' '), contains('volume'));
      final spotify = catalog.plugins.singleWhere((p) => p.id == 'spotify');
      expect(spotify.isDevice, false);
      expect(spotify.unofficial, true);
      expect(spotify.maturityLabel, 'Experimental');
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

  test('a row line names the streamer and falls back to the description', () {
    final plugins = {
      for (final plugin in PluginCatalog.fromJson(_fixture()).plugins)
        plugin.id: plugin,
    };
    expect(
      plugins['upnp']!.blurb('Living room'),
      'Send music to Living room from compatible apps.',
    );
    expect(
      plugins['musiccast']!.blurb('Living room'),
      plugins['musiccast']!.description,
    );
    expect(plugins['localfiles']!.name, 'Folders & NAS');
  });

  test('what a plugin lets people do comes from the catalog alone', () {
    final json = _fixture();
    final plugins = {
      for (final plugin in PluginCatalog.fromJson(json).plugins)
        plugin.id: plugin,
    };
    expect(plugins['qobuz']!.uses, [
      'Browse in Kalinka',
      'Play from another app',
    ]);
    expect(plugins['spotify']!.uses, ['Play from another app']);
    expect(plugins['musiccast']!.uses, isEmpty);
    // A name the app does not know says nothing rather than guessing.
    (json['plugins'] as List).singleWhere(
      (p) => p['id'] == 'musiccast',
    )['provides'] = [
      'teleport',
    ];
    expect(
      PluginCatalog.fromJson(json).plugins
          .singleWhere((p) => p.id == 'musiccast')
          .uses,
      isEmpty,
    );
  });

  test('official and stable plugins rank before the rest', () {
    final plugins = {
      for (final plugin in PluginCatalog.fromJson(_fixture()).plugins)
        plugin.id: plugin.rank,
    };
    expect(plugins['localfiles'], 0);
    expect(plugins['upnp'], 1);
    expect(plugins['qobuz'], 2);
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

  test('updates come only from an available server check', () async {
    final (api, adapter) = _api(
      _json(200, {
        'status': 'available',
        'updates': [
          {
            'plugin_id': 'qobuz',
            'version': '5.1.0',
            'installed_version': '5.0.1',
          },
        ],
      }),
    );
    final updates = await api.updates();
    expect(adapter.requests.single.method, 'GET');
    expect(
      adapter.requests.single.uri.toString(),
      'http://kalinka.local:8000/server/plugins/updates',
    );
    expect(updates.single.pluginId, 'qobuz');
    expect(updates.single.version, '5.1.0');
    expect(updates.single.installedVersion, '5.0.1');

    // Today's servers answer with no verified updates at all.
    final (unavailable, _) = _api(
      _json(200, {
        'status': 'unavailable',
        'reason': 'signature_verification_not_configured',
        'updates': [
          {'plugin_id': 'qobuz', 'version': '5.1.0'},
        ],
      }),
    );
    expect(await unavailable.updates(), isEmpty);
  });

  for (final operation in PluginOperation.values) {
    test('${operation.name} is a POST to the plugin\'s own route', () async {
      final (api, adapter) = _api(_json(200, {}));
      expect(await api.run('qobuz', operation), isFalse);
      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(
        request.uri.toString(),
        'http://kalinka.local:8000/server/plugins/qobuz/${operation.name}',
      );
    });
  }

  test(
    'an accepted operation says whether the server restarts for it',
    () async {
      final (api, _) = _api(
        _json(202, {
          'status': 'restarting',
          'operation': 'install',
          'plugin_id': 'qobuz',
          'version': '5.0.1',
        }),
      );
      expect(await api.run('qobuz', PluginOperation.install), isTrue);
    },
  );

  test(
    'the last operation comes from the inventory, in the helper\'s words',
    () async {
      final (api, adapter) = _api(
        _json(200, {
          'plugins': [],
          'last_operation': {
            'status': 'failed',
            'action': 'install',
            'plugin_id': 'qobuz',
            'error':
                'apt-get did not complete; see the restart service\'s log.',
          },
        }),
      );
      final record = (await api.lastOperation())!;
      expect(adapter.requests.single.method, 'GET');
      expect(
        adapter.requests.single.uri.toString(),
        'http://kalinka.local:8000/server/plugins',
      );
      expect(record.pluginId, 'qobuz');
      expect(record.operation, PluginOperation.install);
      expect(record.failed, isTrue);
      expect(record.error, contains('apt-get did not complete'));

      final (none, _) = _api(
        _json(200, {'plugins': [], 'last_operation': null}),
      );
      expect(await none.lastOperation(), isNull);
      final (disabled, _) = _api(_json(403, {}));
      expect(await disabled.lastOperation(), isNull);
      final (unknownAction, _) = _api(
        _json(200, {
          'last_operation': {
            'status': 'ok',
            'action': 'purge',
            'plugin_id': 'x',
          },
        }),
      );
      final ok = (await unknownAction.lastOperation())!;
      expect(ok.operation, isNull);
      expect(ok.failed, isFalse);
    },
  );

  test('a refused operation carries the server\'s words', () async {
    final (api, _) = _api(
      _json(409, {
        'detail': {
          'code': 'plugin_in_use',
          'message': 'Qobuz is playing. Stop playback first.',
        },
      }),
    );
    await expectLater(
      api.run('qobuz', PluginOperation.uninstall),
      throwsA(
        isA<PluginCatalogException>().having(
          (e) => e.message,
          'message',
          'Qobuz is playing. Stop playback first.',
        ),
      ),
    );
    final (old, _) = _api(_json(405, {'detail': 'Method Not Allowed'}));
    await expectLater(
      old.run('qobuz', PluginOperation.install),
      throwsA(
        isA<PluginCatalogException>().having(
          (e) => e.message,
          'message',
          'This server cannot manage plugins yet.',
        ),
      ),
    );
  });
}
