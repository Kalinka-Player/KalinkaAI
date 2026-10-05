import 'package:dio/dio.dart';

const _refusalCode = 'demo_read_only';

/// A change the demo server refused. [toString] is the server's own sentence,
/// so a call site that reports `'Could not …: $e'` reads correctly unchanged.
class DemoReadOnlyException extends DioException {
  DemoReadOnlyException(DioException cause, this.reason)
    : super(
        requestOptions: cause.requestOptions,
        response: cause.response,
        type: cause.type,
        error: cause.error,
        stackTrace: cause.stackTrace,
        message: reason,
      );

  final String reason;

  @override
  String toString() => reason;
}

/// Turns the demo server's `403 {"detail": {"code": "demo_read_only"}}` into
/// a [DemoReadOnlyException]; every other error passes through untouched.
class DemoReadOnlyInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final reason = _refusalReason(err.response);
    handler.next(reason == null ? err : DemoReadOnlyException(err, reason));
  }

  static String? _refusalReason(Response<dynamic>? response) {
    if (response?.statusCode != 403) return null;
    final body = response?.data;
    final detail = body is Map ? body['detail'] : null;
    if (detail is! Map || detail['code'] != _refusalCode) return null;
    final message = detail['message'];
    return message is String && message.isNotEmpty
        ? message
        : 'This demo server can’t be changed.';
  }
}
