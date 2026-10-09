import 'package:dio/dio.dart';

/// Every refusal a demo server gives starts with this.
const _demoPrefix = 'demo_';

/// Any server's refusal of an add past its queue limit.
const _queueFull = 'queue_full';

/// A queue replacement whose ids came to no tracks.
const _noTracks = 'no_tracks';

/// A request the server refused in words meant for the user: an add past its
/// queue limit, a replacement with no tracks, or on a demo server a change it
/// never allows or too many changes at once. [toString] is the server's own
/// sentence, so a call site that reports `'Could not …: $e'` reads correctly
/// unchanged.
class ServerRefusalException extends DioException {
  ServerRefusalException(DioException cause, this.code, this.reason)
    : super(
        requestOptions: cause.requestOptions,
        response: cause.response,
        type: cause.type,
        error: cause.error,
        stackTrace: cause.stackTrace,
        message: reason,
      );

  /// The server's `detail.code`, such as `queue_full` or `demo_read_only`.
  final String code;

  final String reason;

  @override
  String toString() => reason;
}

/// Turns a server's refusal, a 4xx answer with
/// `{"detail": {"code": …, "message": …}}` whose code is one of the above,
/// into a [ServerRefusalException]; every other error passes through
/// untouched.
class ServerRefusalInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final refusal = _refusalOf(err.response);
    handler.next(
      refusal == null
          ? err
          : ServerRefusalException(err, refusal.code, refusal.reason),
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
    if (code is! String ||
        !(code.startsWith(_demoPrefix) ||
            code == _queueFull ||
            code == _noTracks)) {
      return null;
    }
    final message = detail['message'];
    return (
      code: code,
      reason: message is String && message.isNotEmpty
          ? message
          : 'The server refused that.',
    );
  }
}
