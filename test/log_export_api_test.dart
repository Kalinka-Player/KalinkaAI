import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/log_export.dart';
import 'package:kalinka/providers/log_export_api.dart';

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
        reason: 'no route to host',
      );
    }
    return response;
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

const _preparing = {
  'state': 'preparing',
  'available_sources': ['server'],
  'requested_range': {
    'since': '2026-09-22T10:00:00Z',
    'until': '2026-09-23T10:00:00Z',
  },
  'download': null,
  'warnings': [],
  'error': null,
};

(DioLogExportApi, _Adapter) _api(ResponseBody? Function(RequestOptions) reply) {
  final adapter = _Adapter(reply);
  final dio = Dio(BaseOptions(baseUrl: 'http://kalinka.local:8000'))
    ..httpClientAdapter = adapter;
  return (DioLogExportApi(dio), adapter);
}

void main() {
  test('starting sends the lookback and the renderer choice as JSON', () async {
    final (api, adapter) = _api((_) => _json(202, _preparing));

    final status = await api.start(
      lookback: const Duration(days: 1),
      includeLocalRenderer: true,
    );

    expect(status.state, LogExportState.preparing);
    final sent = adapter.requests.single;
    expect(sent.method, 'POST');
    expect(sent.path, '/server/logs/export');
    expect(sent.data, {
      'lookback_seconds': 86400,
      'include_local_renderer': true,
    });
  });

  test('a start refused as in progress returns the running export', () async {
    final (api, _) = _api(
      (_) => _json(409, {
        'code': 'export_in_progress',
        'message': 'Logs are already being collected.',
        'export': _preparing,
      }),
    );

    final status = await api.start(
      lookback: const Duration(hours: 1),
      includeLocalRenderer: false,
    );

    expect(status.state, LogExportState.preparing);
  });

  test('a refusal carries the server\'s own words', () async {
    final (api, _) = _api(
      (_) => _json(503, {
        'code': 'log_source_unavailable',
        'message': 'This server cannot read its logs.',
      }),
    );

    await expectLater(
      api.start(
        lookback: const Duration(hours: 1),
        includeLocalRenderer: false,
      ),
      throwsA(
        isA<LogExportException>()
            .having((e) => e.code, 'code', 'log_source_unavailable')
            .having(
              (e) => e.message,
              'message',
              'This server cannot read its logs.',
            ),
      ),
    );
  });

  test('no answer at all is told apart from a refusal', () async {
    final (api, _) = _api((_) => null);

    await expectLater(
      api.status(),
      throwsA(isA<LogExportUnreachableException>()),
    );
  });

  test('a server without the endpoint is reported as too old', () async {
    final (api, _) = _api((_) => ResponseBody.fromString('Not Found', 404));

    await expectLater(
      api.status(),
      throwsA(isA<LogExportUnsupportedException>()),
    );
  });

  test('an older server\'s web-player page is reported as too old', () async {
    final (api, _) = _api(
      (_) => ResponseBody.fromString(
        '<html>Install kalinka-web</html>',
        200,
        headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8'],
        },
      ),
    );

    await expectLater(
      api.status(),
      throwsA(isA<LogExportUnsupportedException>()),
    );
  });

  test('downloading streams the archive with its length', () async {
    final (api, _) = _api(
      (_) => ResponseBody.fromBytes(
        [1, 2, 3, 4],
        200,
        headers: {
          'content-length': ['4'],
        },
      ),
    );

    final download = await api.download();

    expect(download.length, 4);
    expect(await download.bytes.expand((b) => b).toList(), [1, 2, 3, 4]);
  });

  test(
    'downloading an archive that is gone says it is no longer available',
    () async {
      final (api, _) = _api(
        (_) => _json(409, {
          'code': 'export_not_ready',
          'message': 'No log archive is ready.',
        }),
      );

      await expectLater(
        api.download(),
        throwsA(
          isA<LogExportException>().having(
            (e) => e.code,
            'code',
            LogExportException.notReady.code,
          ),
        ),
      );
    },
  );

  test('a browser downloads from the connected server', () {
    final (api, _) = _api((_) => null);

    expect(
      api.downloadUrl.toString(),
      'http://kalinka.local:8000/server/logs/export/download',
    );
  });

  test('a ready status reads its archive, notes and expiry', () {
    final status = LogExportStatus.fromJson({
      'state': 'ready',
      'available_sources': ['server', 'local_renderer'],
      'download': {
        'filename': 'kalinka-logs-20260923T100000Z.zip',
        'size_bytes': 96412,
        'expires_at': '2026-09-23T10:30:02Z',
      },
      'warnings': [
        {
          'source': 'server',
          'code': 'history_shorter',
          'message': 'The server\'s logs only go back to 2026-09-23T08:00:00Z.',
        },
      ],
      'error': null,
    });

    expect(status.state, LogExportState.ready);
    expect(status.offersLocalRenderer, isTrue);
    expect(status.download!.sizeBytes, 96412);
    expect(status.download!.expiresAt, DateTime.utc(2026, 9, 23, 10, 30, 2));
    expect(status.warnings.single.code, 'history_shorter');
  });

  test('a failed status carries its error', () {
    final status = LogExportStatus.fromJson({
      'state': 'failed',
      'available_sources': ['server'],
      'download': null,
      'warnings': [],
      'error': {
        'code': 'collection_timeout',
        'message': 'Collecting the logs took too long.',
      },
    });

    expect(status.errorCode, 'collection_timeout');
    expect(status.errorMessage, 'Collecting the logs took too long.');
  });
}
