import 'package:dio/dio.dart';

const unreachableLatencyMs = 9999;
const _probeTimeout = Duration(seconds: 1);

/// Rank advertised addresses by HTTP reachability, retaining failures as alternates.
Future<int> probeServerEndpoint(String host, int port) async {
  final dio = Dio(
    BaseOptions(
      baseUrl: Uri(scheme: 'http', host: host, port: port).toString(),
      connectTimeout: _probeTimeout,
      receiveTimeout: _probeTimeout,
    ),
  );
  try {
    final stopwatch = Stopwatch()..start();
    await dio.get('/server/modules').timeout(_probeTimeout);
    return stopwatch.elapsedMilliseconds;
  } catch (_) {
    return unreachableLatencyMs;
  } finally {
    dio.close(force: true);
  }
}
