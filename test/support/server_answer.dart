import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:kalinka/providers/box_control_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';

/// The server answering as [id] at whichever address it is reached; a null
/// [id] is a server too old to report one. Moves nothing kept under the
/// address: use [ServersByHost] for that.
Override serverAnswering(String? id) =>
    serverAnswerProvider.overrideWith(() => _Answering(id));

class _Answering extends ServerAnswerNotifier {
  _Answering(this.id);

  final String? id;

  @override
  Future<ServerAnswer> build() async => (
    server: ref.watch(connectionSettingsProvider.select((s) => s.baseUrl)),
    id: id,
  );
}

/// Answers `/renderer/sessions` as the server at each host would.
class ServersByHost implements HttpClientAdapter {
  /// The id each host's server reports. A host left out answers without one,
  /// as a server too old to have an id does.
  final ids = <String, String>{};

  /// Hosts whose server does not answer.
  final silent = <String>{};

  /// The status a host's server answers the route with instead, such as 404
  /// from one older than it.
  final statuses = <String, int>{};

  int asked = 0;

  /// The HTTP client of whichever server the app is set to, answered here.
  Override get client => httpClientProvider.overrideWith(
    (ref) => Dio(
      BaseOptions(
        baseUrl: ref
            .watch(connectionSettingsProvider.select((s) => s.baseUrl))
            .toString(),
      ),
    )..httpClientAdapter = this,
  );

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    asked++;
    final host = options.uri.host;
    if (silent.contains(host)) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: '$host does not answer',
      );
    }
    final status = statuses[host];
    return ResponseBody.fromString(
      jsonEncode(
        status != null
            ? {'detail': 'Refused'}
            : {'server_id': ?ids[host], 'sessions': []},
      ),
      status ?? 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
