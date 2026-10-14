import 'dart:math';

import 'package:dio/dio.dart';

/// The supervisor's network setup transport, shared by native and web clients.
class NetworkSetupApi {
  final Dio client;
  final Uri base;
  final String session;

  NetworkSetupApi(this.base, {Dio? client})
    : client =
          client ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 4),
              receiveTimeout: const Duration(seconds: 6),
            ),
          ),
      session = List.generate(
        16,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();

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
