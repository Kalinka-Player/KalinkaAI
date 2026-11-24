import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/server_refusal.dart';

/// A server that answers [route] with [status] and [body], and every other
/// request with success. It records each request as `METHOD /path` and keeps
/// the body sent with it.
class QueueServer implements HttpClientAdapter {
  QueueServer(this.status, this.body, {this.route = '/queue/replace'});

  final int status;
  final Object body;
  final String route;

  /// What any other request reports having acted on.
  static const count = 7;

  final List<String> requests = [];
  final Map<String, Object?> bodies = {};
  final Map<String, Map<String, dynamic>> queries = {};

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
    queries[request] = options.queryParameters;
    final answering = options.path == route;
    return ResponseBody.fromString(
      jsonEncode(answering ? body : {'message': 'Ok', 'count': count}),
      answering ? status : 200,
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
