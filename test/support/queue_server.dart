import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/server_refusal.dart';

/// A server that answers `/queue/replace` with [replaceStatus] and
/// [replaceBody], and every other request with success. It records each
/// request as `METHOD /path` and keeps the body sent with it.
class QueueServer implements HttpClientAdapter {
  QueueServer(this.replaceStatus, this.replaceBody);

  final int replaceStatus;
  final Object replaceBody;

  /// What any other request reports having acted on.
  static const count = 7;

  final List<String> requests = [];
  final Map<String, Object?> bodies = {};

  /// The HTTP client the app would use, talking to this server.
  KalinkaPlayerProxyImpl api() => KalinkaPlayerProxyImpl(
    client: Dio(BaseOptions(baseUrl: 'http://server.test'))
      ..httpClientAdapter = this
      ..interceptors.add(ServerRefusalInterceptor()),
  );

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final request = '${options.method} ${options.path}';
    requests.add(request);
    bodies[request] = options.data;
    final replacing = options.path == '/queue/replace';
    return ResponseBody.fromString(
      jsonEncode(replacing ? replaceBody : {'message': 'Ok', 'count': count}),
      replacing ? replaceStatus : 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// How a server before API 0.12 answers `/queue/replace`, with and without
/// the browser-player mount at "/".
const olderServers = [
  (404, {'detail': 'Not Found'}, 'without a browser player'),
  (405, {'detail': 'Method Not Allowed'}, 'with a browser player'),
];
