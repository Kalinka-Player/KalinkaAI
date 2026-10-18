import 'dart:math';

import 'package:dio/dio.dart';

import 'network_setup_session.dart'
    if (dart.library.js_interop) 'network_setup_session_web.dart';

/// The box's own address on the Wi-Fi hotspot it raises for setup.
const hotspotAddress = '192.168.4.1';

/// The supervisor's network setup transport, shared by native and web clients.
class NetworkSetupApi {
  final Dio client;
  final Uri base;
  static final _session = restoreSetupSession(
    List.generate(
      16,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join(),
  );
  final String session = _session;

  NetworkSetupApi(this.base, {Dio? client})
    : client =
          client ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 4),
              receiveTimeout: const Duration(seconds: 6),
            ),
          );

  Future<Map<String, dynamic>> status() async {
    final response = await client.getUri(
      base.replace(path: '/v1/setup', query: null),
    );
    if (response.data is! Map) {
      throw const FormatException('Invalid setup response');
    }
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> command(
    String operation, [
    Map<String, Object> fields = const {},
  ]) async {
    await client.postUri(
      base.replace(path: '/v1/setup', query: null),
      data: {'v': 1, 'op': operation, ...fields},
      options: Options(
        contentType: Headers.jsonContentType,
        headers: {'X-Kalinka-Setup-Client': session},
      ),
    );
  }

  void dispose() => client.close(force: true);
}
