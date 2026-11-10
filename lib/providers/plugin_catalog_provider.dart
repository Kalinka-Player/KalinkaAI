import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/plugin_catalog.dart';
import 'kalinka_player_api_provider.dart';
import 'modules_state_provider.dart';
import 'restart_provider.dart';
import 'server_info_provider.dart';
import 'settings_provider.dart';

class PluginCatalogException implements Exception {
  final String message;
  const PluginCatalogException(this.message);
  @override
  String toString() => message;
}

enum PluginOperation { install, uninstall, update }

/// How the server took an operation: it restarts to carry it out, carries
/// it out while it runs, or had nothing left to do.
enum PluginAccepted { restarting, applying, done }

/// The server's record of an install, removal or update — the one under way
/// or the last one — as `GET /server/plugins/operation` reports it, step by
/// step, and `GET /server/plugins` as `last_operation`.
class PluginOperationRecord {
  final String? id;
  final String pluginId;
  final PluginOperation? operation;
  final String status;
  final String? step;
  final int stepIndex;
  final int stepCount;
  final String? error;

  const PluginOperationRecord({
    required this.pluginId,
    required this.status,
    this.id,
    this.operation,
    this.step,
    this.stepIndex = 0,
    this.stepCount = 0,
    this.error,
  });

  bool get failed => status == 'failed';
  bool get running => status == 'running';
  bool get restarting => status == 'restarting';

  /// How far it has got, 0 to 1, by the step it has reached.
  double get progress =>
      stepCount <= 0 ? 0 : (stepIndex / stepCount).clamp(0.0, 1.0);

  factory PluginOperationRecord.fromJson(Map<String, dynamic> json) =>
      PluginOperationRecord(
        id: json['id']?.toString(),
        pluginId: json['plugin_id'] as String? ?? '',
        operation: PluginOperation.values
            .where((o) => o.name == json['action'])
            .firstOrNull,
        status: json['status'] as String? ?? '',
        step: json['step'] as String?,
        stepIndex: (json['step_index'] as num?)?.toInt() ?? 0,
        stepCount: (json['step_count'] as num?)?.toInt() ?? 0,
        error: json['error'] as String?,
      );
}

abstract class PluginCatalogApi {
  Future<PluginCatalog> read();

  /// Newer releases of installed plugins, as the server reports them.
  Future<List<PluginUpdate>> updates();

  /// How the server took the operation. A refusal throws, in the server's
  /// words.
  Future<PluginAccepted> run(String pluginId, PluginOperation operation);

  /// The operation under way or the last one, or null where none ever ran
  /// or the server keeps no such record. A server that cannot be reached
  /// throws, as the follow needs to know.
  Future<PluginOperationRecord?> operation();

  /// The record of the last operation, or null where the server keeps none
  /// or cannot be read.
  Future<PluginOperationRecord?> lastOperation();
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
  Future<PluginAccepted> run(String pluginId, PluginOperation operation) async {
    try {
      final response = await client.post(
        '/server/plugins/${Uri.encodeComponent(pluginId)}/${operation.name}',
      );
      final data = response.data;
      return switch (data is Map ? data['status'] : null) {
        'restarting' => PluginAccepted.restarting,
        'applying' => PluginAccepted.applying,
        _ => PluginAccepted.done,
      };
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

  @override
  Future<PluginOperationRecord?> operation() async {
    try {
      final data = (await client.get('/server/plugins/operation')).data;
      if (data is! Map || data['status'] == 'idle') return null;
      return PluginOperationRecord.fromJson(data.cast<String, dynamic>());
    } on DioException catch (error) {
      // A server before 0.22 has no such route: its operations restart it.
      if (error.response != null) return null;
      rethrow;
    }
  }

  @override
  Future<PluginOperationRecord?> lastOperation() async {
    try {
      final data = (await client.get('/server/plugins')).data;
      final record = data is Map ? data['last_operation'] : null;
      return record is Map
          ? PluginOperationRecord.fromJson(record.cast<String, dynamic>())
          : null;
    } on DioException {
      return null;
    }
  }
}

final pluginCatalogApiProvider = Provider<PluginCatalogApi>(
  (ref) => DioPluginCatalogApi(ref.watch(httpClientProvider)),
);

final pluginCatalogProvider = FutureProvider.autoDispose<PluginCatalog>(
  (ref) async {
    if (!ref.watch(pluginCatalogAvailableProvider)) {
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

/// How an install, removal or update ended: done, failed where the failure
/// is kept with the plugin, or unknown when the wait for the server's
/// restart was given up.
enum PluginOutcome { done, failed, unknown }

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

/// An install, removal or update under way on one plugin, as far as it has
/// got: 0 until the server has said, 1 as it ends.
class PluginProgress {
  final PluginOperation operation;
  final String? step;
  final double progress;
  const PluginProgress(this.operation, {this.step, this.progress = 0});
}

/// Installs, removals and updates in flight, by plugin id.
class PluginOperationsNotifier extends Notifier<Map<String, PluginProgress>> {
  /// How often the server's record is read while it carries an operation
  /// out, and how long that is given before it is taken for lost.
  static Duration pollInterval = const Duration(seconds: 1);
  static Duration followLimit = const Duration(minutes: 15);

  @override
  Map<String, PluginProgress> build() => const {};

  /// Runs the operation to its end: following the server's record where it
  /// carries the operation out as it runs, or its restart where it restarts
  /// to. [name] is the plugin's, for the restart's subtitle.
  Future<PluginOutcome> run(
    String pluginId,
    PluginOperation operation, {
    String? name,
  }) async {
    if (state.containsKey(pluginId)) return PluginOutcome.unknown;
    ref.read(pluginFailuresProvider.notifier).dismiss(pluginId);
    _progress(pluginId, PluginProgress(operation));
    try {
      final PluginAccepted accepted;
      try {
        accepted = await ref
            .read(pluginCatalogApiProvider)
            .run(pluginId, operation);
      } on PluginCatalogException catch (error) {
        return _fail(pluginId, operation, error.message);
      }
      if (!ref.mounted) return PluginOutcome.unknown;
      final outcome = switch (accepted) {
        PluginAccepted.restarting => await _followRestart(
          pluginId,
          operation,
          name,
        ),
        PluginAccepted.applying => await _followOperation(
          pluginId,
          operation,
          name,
        ),
        PluginAccepted.done => PluginOutcome.done,
      };
      if (!ref.mounted) return PluginOutcome.unknown;
      if (outcome != PluginOutcome.done) return outcome;
      return await _settle();
    } finally {
      if (ref.mounted) state = {...state}..remove(pluginId);
    }
  }

  /// Picks an operation up that the server is still carrying out — begun on
  /// an earlier visit to the page, or before the app was closed.
  Future<void> reattach() async {
    final PluginOperationRecord? record;
    try {
      record = await ref.read(pluginCatalogApiProvider).operation();
    } on DioException {
      return;
    }
    if (!ref.mounted || record == null || !record.running) return;
    final operation = record.operation;
    if (operation == null || state.containsKey(record.pluginId)) return;
    _progress(
      record.pluginId,
      PluginProgress(operation, step: record.step, progress: record.progress),
    );
    try {
      final outcome = await _followOperation(record.pluginId, operation, null);
      if (ref.mounted && outcome == PluginOutcome.done) await _settle();
    } finally {
      if (ref.mounted) state = {...state}..remove(record.pluginId);
    }
  }

  void _progress(String pluginId, PluginProgress progress) {
    state = {...state, pluginId: progress};
  }

  /// The server carries the operation out while it runs: its record says
  /// how far it has got and how it ended. A server that stops answering is
  /// restarting to finish the job, and is followed through that instead.
  Future<PluginOutcome> _followOperation(
    String pluginId,
    PluginOperation operation,
    String? name,
  ) async {
    final api = ref.read(pluginCatalogApiProvider);
    final deadline = DateTime.now().add(followLimit);
    while (true) {
      await Future<void>.delayed(pollInterval);
      if (!ref.mounted) return PluginOutcome.unknown;
      final PluginOperationRecord? record;
      try {
        record = await api.operation();
      } on DioException {
        return await _followRestart(pluginId, operation, name);
      }
      if (!ref.mounted) return PluginOutcome.unknown;
      if (record != null && record.pluginId == pluginId) {
        _progress(
          pluginId,
          PluginProgress(
            operation,
            step: record.step,
            progress: record.progress,
          ),
        );
        if (record.restarting) return _followRestart(pluginId, operation, name);
        if (record.failed) {
          return _fail(
            pluginId,
            operation,
            record.error ?? 'The server could not finish.',
          );
        }
        if (!record.running) return PluginOutcome.done;
      }
      if (DateTime.now().isAfter(deadline)) {
        return _fail(pluginId, operation, 'The server did not finish.');
      }
    }
  }

  /// Once the server has the result, so does the app: the module and update
  /// lists, and the settings the plugin brought or took away.
  Future<PluginOutcome> _settle() async {
    ref.invalidate(modulesStateProvider);
    ref.invalidate(pluginCatalogProvider);
    ref.invalidate(pluginUpdatesProvider);
    // Stay busy until the module and update lists show the result, so the
    // row never offers the same action again in between. Listened to, so
    // the update check is not dropped while it is waited on.
    final updates = ref.listen(pluginUpdatesProvider.future, (_, _) {});
    try {
      await Future.wait([
        ref.read(modulesStateProvider.future),
        updates.read(),
      ]);
    } catch (_) {
    } finally {
      updates.close();
    }
    if (!ref.mounted) return PluginOutcome.unknown;
    // A plugin brings settings of its own, or takes them away. Reading them
    // again drops staged edits, so leave those to the next apply.
    if (!ref.read(settingsProvider).hasPendingChanges) {
      await ref.read(settingsProvider.notifier).loadConfig();
    }
    return PluginOutcome.done;
  }

  /// The server carries the operation out while it restarts; its helper
  /// records how that went, for reading once the server is back.
  Future<PluginOutcome> _followRestart(
    String pluginId,
    PluginOperation operation,
    String? name,
  ) async {
    final what = name ?? 'the plugin';
    await ref
        .read(restartProvider.notifier)
        .followRestart(
          subtitle: switch (operation) {
            PluginOperation.install => 'Installing $what\u2026',
            PluginOperation.update => 'Updating $what\u2026',
            PluginOperation.uninstall => 'Uninstalling $what\u2026',
          },
        );
    if (!ref.mounted) return PluginOutcome.unknown;
    final restart = ref.read(restartProvider);
    if (restart.error != null) {
      return _fail(
        pluginId,
        operation,
        'The server did not come back after its restart, so how this ended '
        'is not known.',
      );
    }
    // The wait was given up; the server finishes on its own.
    if (!restart.isDone) return PluginOutcome.unknown;
    final record = await ref.read(pluginCatalogApiProvider).lastOperation();
    if (!ref.mounted) return PluginOutcome.unknown;
    if (record != null && record.pluginId == pluginId && record.failed) {
      return _fail(
        pluginId,
        operation,
        record.error ?? 'The server could not finish.',
      );
    }
    return PluginOutcome.done;
  }

  /// Keeps why the operation failed with the plugin, where it was asked for.
  PluginOutcome _fail(
    String pluginId,
    PluginOperation operation,
    String message,
  ) {
    ref
        .read(pluginFailuresProvider.notifier)
        .record(pluginId, PluginFailure(operation, message));
    return PluginOutcome.failed;
  }
}

final pluginOperationsProvider =
    NotifierProvider<PluginOperationsNotifier, Map<String, PluginProgress>>(
      PluginOperationsNotifier.new,
    );
