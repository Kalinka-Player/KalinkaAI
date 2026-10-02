import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/plugin_catalog.dart';
import 'kalinka_player_api_provider.dart';
import 'server_info_provider.dart';

class PluginCatalogException implements Exception {
  final String message;
  const PluginCatalogException(this.message);
  @override
  String toString() => message;
}

abstract class PluginCatalogApi {
  Future<PluginCatalog> read();
}

/// Read the connected server's cache, never GitHub or package URLs directly.
class DioPluginCatalogApi implements PluginCatalogApi {
  final Dio client;
  DioPluginCatalogApi(this.client);

  @override
  Future<PluginCatalog> read() async {
    try {
      final response = await client.get(
        '/server/plugins/catalog',
        options: Options(validateStatus: (code) => code == 200 || code == 503),
      );
      if (response.data is! Map) {
        throw const PluginCatalogException(
          'This server does not support plugin browsing.',
        );
      }
      return PluginCatalog.fromJson(
        (response.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (error) {
      throw PluginCatalogException(switch (error.response?.statusCode) {
        403 => 'Plugin catalog preview is disabled on this server.',
        404 => 'This server does not support plugin browsing.',
        _ =>
          'Could not read the plugin catalog. Check the server connection and try again.',
      });
    } on FormatException {
      throw const PluginCatalogException(
        'The server returned an unsupported plugin catalog.',
      );
    } on TypeError {
      throw const PluginCatalogException(
        'The server returned an invalid plugin catalog.',
      );
    }
  }
}

final pluginCatalogApiProvider = Provider<PluginCatalogApi>(
  (ref) => DioPluginCatalogApi(ref.watch(httpClientProvider)),
);

final pluginCatalogProvider = FutureProvider.autoDispose<PluginCatalog>(
  (ref) async {
    if (!ref.watch(pluginCatalogEnabledProvider)) {
      return const PluginCatalog(status: 'disabled');
    }
    final api = ref.watch(pluginCatalogApiProvider);
    return api.read();
  },
  // Errors remain visible until the user retries; never loop on a disabled API.
  retry: (_, _) => null,
);
