import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/plugin_catalog.dart';
import 'kalinka_player_api_provider.dart';
import 'modules_state_provider.dart';
import 'server_info_provider.dart';
import 'settings_provider.dart';

class PluginCatalogException implements Exception {
  final String message;
  const PluginCatalogException(this.message);
  @override
  String toString() => message;
}

enum PluginOperation { install, uninstall, update }

abstract class PluginCatalogApi {
  Future<PluginCatalog> read();

  /// Newer releases of installed plugins, as the server reports them.
  Future<List<PluginUpdate>> updates();

  Future<void> run(String pluginId, PluginOperation operation);
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
        _ => 'Could not read the plugin catalog. Check the server connection and try again.',
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

  @override
  Future<List<PluginUpdate>> updates() async {
    final response = await client.get('/server/plugins/updates');
    final data = response.data;
    if (data is! Map || data['status'] != 'available') return const [];
    return [
      for (final update in data['updates'] as List? ?? const [])
        PluginUpdate.fromJson((update as Map).cast<String, dynamic>()),
    ];
  }

  @override
  Future<void> run(String pluginId, PluginOperation operation) async {
    try {
      await client.post(
        '/server/plugins/${Uri.encodeComponent(pluginId)}/${operation.name}',
      );
    } on DioException catch (error) {
      final detail = error.response?.data is Map
          ? (error.response!.data as Map)['detail']
          : null;
      final message = detail is Map ? detail['message'] : null;
      throw PluginCatalogException(
        message is String && message.isNotEmpty
            ? message
            : switch (error.response?.statusCode) {
                404 || 405 => 'This server cannot manage plugins yet.',
                _ => 'The server could not finish. Try again.',
              },
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

/// Updates by plugin id. Empty where the server does not check, and when the
/// check fails: an update the app cannot show is not one it can offer.
final pluginUpdatesProvider =
    FutureProvider.autoDispose<Map<String, PluginUpdate>>((ref) async {
      if (!ref.watch(pluginUpdateChecksProvider)) return const {};
      try {
        final updates = await ref.watch(pluginCatalogApiProvider).updates();
        return {for (final update in updates) update.pluginId: update};
      } catch (_) {
        return const {};
      }
    }, retry: (_, _) => null);

/// How an install, removal or update went wrong, in the server's words.
class PluginFailure {
  final PluginOperation operation;
  final String message;
  const PluginFailure(this.operation, this.message);

  String get title => switch (operation) {
    PluginOperation.install => 'Install failed',
    PluginOperation.uninstall => 'Uninstall failed',
    PluginOperation.update => 'Update failed',
  };
}

/// The last failure of each plugin's install, removal or update, kept where
/// it happened until it is tried again or put away.
class PluginFailuresNotifier extends Notifier<Map<String, PluginFailure>> {
  @override
  Map<String, PluginFailure> build() => const {};

  void record(String pluginId, PluginFailure failure) =>
      state = {...state, pluginId: failure};

  void dismiss(String pluginId) {
    if (state.containsKey(pluginId)) state = {...state}..remove(pluginId);
  }

  void clear() => state = const {};
}

final pluginFailuresProvider =
    NotifierProvider<PluginFailuresNotifier, Map<String, PluginFailure>>(
      PluginFailuresNotifier.new,
    );

/// Installs, removals and updates in flight, by plugin id.
class PluginOperationsNotifier extends Notifier<Map<String, PluginOperation>> {
  @override
  Map<String, PluginOperation> build() => const {};

  /// Null once done, else why it failed.
  Future<String?> run(String pluginId, PluginOperation operation) async {
    if (state.containsKey(pluginId)) return null;
    final failures = ref.read(pluginFailuresProvider.notifier)
      ..dismiss(pluginId);
    state = {...state, pluginId: operation};
    try {
      try {
        await ref.read(pluginCatalogApiProvider).run(pluginId, operation);
      } on PluginCatalogException catch (error) {
        failures.record(pluginId, PluginFailure(operation, error.message));
        return error.message;
      }
      if (!ref.mounted) return null;
      ref.invalidate(modulesStateProvider);
      ref.invalidate(pluginCatalogProvider);
      ref.invalidate(pluginUpdatesProvider);
      // Stay busy until the module list shows the result, so the row never
      // offers the same action again in between.
      try {
        await ref.read(modulesStateProvider.future);
      } catch (_) {}
      if (!ref.mounted) return null;
      // A plugin brings settings of its own, or takes them away. Reading them
      // again drops staged edits, so leave those to the next restart.
      if (!ref.read(settingsProvider).hasPendingChanges) {
        await ref.read(settingsProvider.notifier).loadConfig();
      }
      return null;
    } finally {
      if (ref.mounted) state = {...state}..remove(pluginId);
    }
  }
}

final pluginOperationsProvider =
    NotifierProvider<PluginOperationsNotifier, Map<String, PluginOperation>>(
      PluginOperationsNotifier.new,
    );
