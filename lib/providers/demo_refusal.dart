import 'package:dio/dio.dart';

const _refusalPrefix = 'demo_';

/// A request the demo server refused: a change it never allows, an add past
/// its queue limit, or too many changes at once. [toString] is the server's
/// own sentence, so a call site that reports `'Could not …: $e'` reads
/// correctly unchanged.
class DemoRefusalException extends DioException {
  DemoRefusalException(DioException cause, this.code, this.reason)
    : super(
        requestOptions: cause.requestOptions,
        response: cause.response,
        type: cause.type,
        error: cause.error,
        stackTrace: cause.stackTrace,
        message: reason,
      );

  /// The server's `detail.code`, such as `demo_read_only` or `demo_queue_full`.
  final String code;

  final String reason;

  @override
  String toString() => reason;
}

/// Turns a demo server's refusal, a 4xx answer with
/// `{"detail": {"code": "demo_…", "message": …}}`, into a
/// [DemoRefusalException]; every other error passes through untouched.
class DemoRefusalInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final refusal = _refusalOf(err.response);
    handler.next(
      refusal == null
          ? err
          : DemoRefusalException(err, refusal.code, refusal.reason),
    );
  }

  static ({String code, String reason})? _refusalOf(
    Response<dynamic>? response,
  ) {
    final status = response?.statusCode ?? 0;
    if (status < 400 || status >= 500) return null;
    final body = response?.data;
    final detail = body is Map ? body['detail'] : null;
    if (detail is! Map) return null;
    final code = detail['code'];
    if (code is! String || !code.startsWith(_refusalPrefix)) return null;
    final message = detail['message'];
    return (
      code: code,
      reason: message is String && message.isNotEmpty
          ? message
          : 'The demo server refused that.',
    );
  }
}
