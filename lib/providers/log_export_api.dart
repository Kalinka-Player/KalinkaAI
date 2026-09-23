import 'package:dio/dio.dart'
    show Dio, DioException, Options, ResponseBody, ResponseType;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/log_export.dart';
import 'kalinka_player_api_provider.dart' show httpClientProvider;

const _exportPath = '/server/logs/export';
const _downloadPath = '$_exportPath/download';

/// The server refused a log-export request; [message] is fit to show.
class LogExportException implements Exception {
  final String code;
  final String message;

  const LogExportException(this.code, this.message);

  static const notReady = LogExportException(
    'export_not_ready',
    'The log archive is no longer available.',
  );

  @override
  String toString() => message;
}

/// The server could not be reached at all — not an answer, just silence.
class LogExportUnreachableException implements Exception {
  const LogExportUnreachableException();
}

/// The connected server predates log export.
class LogExportUnsupportedException implements Exception {
  const LogExportUnsupportedException();
}

/// A ready archive being received.
class LogArchiveDownload {
  /// Bytes to expect, when the server said.
  final int? length;
  final Stream<List<int>> bytes;

  const LogArchiveDownload({required this.length, required this.bytes});
}

/// `/server/logs/export` on the connected server.
///
/// Every call throws [LogExportUnreachableException] when no answer came
/// back, so a caller can tell a dropped connection from a refusal.
abstract class LogExportApi {
  Future<LogExportStatus> status();

  /// Start preparing an export of the last [lookback].
  ///
  /// Returns the export now being prepared: the one this started, or the one
  /// already running, which the server keeps rather than start another.
  Future<LogExportStatus> start({
    required Duration lookback,
    required bool includeLocalRenderer,
  });

  /// Cancel preparation or delete the archive.
  Future<void> withdraw();

  /// Open the ready archive.
  ///
  /// Throws [LogExportException.notReady] when it expired or was replaced.
  Future<LogArchiveDownload> download();

  /// Where a browser can fetch the ready archive itself.
  Uri get downloadUrl;
}

class DioLogExportApi implements LogExportApi {
  DioLogExportApi(this._client);

  final Dio _client;

  @override
  Uri get downloadUrl =>
      Uri.parse(_client.options.baseUrl).resolve(_downloadPath);

  @override
  Future<LogExportStatus> status() => _call(() async {
    final response = await _client.get(_exportPath);
    final data = response.data;
    // An older server's web-player mount answers an unknown path with its
    // install page, not a 404.
    if (data is! Map) throw const LogExportUnsupportedException();
    return _parse(data);
  }, unsupportedOn404: true);

  @override
  Future<LogExportStatus> start({
    required Duration lookback,
    required bool includeLocalRenderer,
  }) => _call(() async {
    final response = await _client.post(
      _exportPath,
      data: {
        'lookback_seconds': lookback.inSeconds,
        'include_local_renderer': includeLocalRenderer,
      },
      options: Options(validateStatus: (s) => s == 202 || s == 409),
    );
    final body = (response.data as Map).cast<String, dynamic>();
    return _parse(response.statusCode == 409 ? body['export'] : body);
  });

  @override
  Future<void> withdraw() => _call(() => _client.delete(_exportPath));

  @override
  Future<LogArchiveDownload> download() => _call(() async {
    final response = await _client.get<ResponseBody>(
      _downloadPath,
      options: Options(
        responseType: ResponseType.stream,
        validateStatus: (s) => s == 200 || s == 409,
      ),
    );
    final body = response.data!;
    if (response.statusCode == 409) {
      await body.stream.drain<void>();
      throw LogExportException.notReady;
    }
    final length = int.tryParse(response.headers.value('content-length') ?? '');
    return LogArchiveDownload(length: length, bytes: body.stream);
  });

  static LogExportStatus _parse(Object? data) =>
      LogExportStatus.fromJson((data as Map).cast<String, dynamic>());

  static Future<T> _call<T>(
    Future<T> Function() request, {
    bool unsupportedOn404 = false,
  }) async {
    try {
      return await request();
    } on DioException catch (e) {
      final response = e.response;
      if (response == null) throw const LogExportUnreachableException();
      if (unsupportedOn404 && response.statusCode == 404) {
        throw const LogExportUnsupportedException();
      }
      final body = response.data;
      if (body is Map && body['message'] is String) {
        throw LogExportException(
          body['code'] as String? ?? 'error',
          body['message'] as String,
        );
      }
      throw const LogExportException(
        'error',
        'The server could not handle the request.',
      );
    }
  }
}

/// Follows the connected server: a switch reads the new server's export.
final logExportApiProvider = Provider<LogExportApi>(
  (ref) => DioLogExportApi(ref.watch(httpClientProvider)),
);
