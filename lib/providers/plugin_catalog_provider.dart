import 'dart:async';

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
/// it out while it runs, queues it behind another, or had nothing left to do.
enum PluginAccepted { restarting, applying, queued, done }

/// How the server took an operation, and the id its records carry, where it
/// gives one (API 0.23).
class PluginAcceptance {
  final PluginAccepted status;
  final String? id;
  const PluginAcceptance(this.status, {this.id});

  factory PluginAcceptance.fromJson(Object? data) {
    final json = data is Map ? data : const {};
    return PluginAcceptance(switch (json['status']) {
      'restarting' => PluginAccepted.restarting,
      'applying' => PluginAccepted.applying,
      'queued' => PluginAccepted.queued,
      _ => PluginAccepted.done,
    }, id: json['id']?.toString());
  }
}

/// What the server made of updating several plugins at once: each accepted
/// as one operation would be, or refused in its own words.
class PluginUpdatesAccepted {
  final Map<String, PluginAcceptance> accepted;
  final Map<String, String> refused;
  const PluginUpdatesAccepted({
    this.accepted = const {},
    this.refused = const {},
  });
}

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

  /// When it last moved, by the server's clock.
  final num? updatedAt;

  const PluginOperationRecord({
    required this.pluginId,
    required this.status,
    this.id,
    this.operation,
    this.step,
    this.stepIndex = 0,
    this.stepCount = 0,
    this.error,
    this.updatedAt,
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
        updatedAt: json['updated_at'] as num?,
      );
}

/// An operation waiting its turn on the server.
class PluginQueuedOperation {
  final String id;
  final String pluginId;
  final PluginOperation? operation;
  const PluginQueuedOperation({
    required this.id,
    required this.pluginId,
    this.operation,
  });

  factory PluginQueuedOperation.fromJson(Map<String, dynamic> json) =>
      PluginQueuedOperation(
        id: json['id']?.toString() ?? '',
        pluginId: json['plugin_id'] as String? ?? '',
        operation: PluginOperation.values
            .where((o) => o.name == json['action'])
            .firstOrNull,
      );
}

/// `GET /server/plugins/operation` whole: the operation under way or the
/// last one, and, where the server queues them, what waits its turn and how
/// the latest ended.
class PluginOperationsReport {
  final PluginOperationRecord? current;

  /// Next first.
  final List<PluginQueuedOperation> queued;

  /// Oldest first.
  final List<PluginOperationRecord> results;

  /// The server queues operations and keeps how each ended (API 0.23).
  final bool queues;

  const PluginOperationsReport({
    this.current,
    this.queued = const [],
    this.results = const [],
    this.queues = false,
  });

  factory PluginOperationsReport.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> maps(Object? list) => [
      for (final item in list is List ? list : const [])
        if (item is Map) item.cast<String, dynamic>(),
    ];
    return PluginOperationsReport(
      current: json['status'] == 'idle'
          ? null
          : PluginOperationRecord.fromJson(json),
      queued: [
        for (final entry in maps(json['queue']))
          PluginQueuedOperation.fromJson(entry),
      ],
      results: [
        for (final record in maps(json['results']))
          PluginOperationRecord.fromJson(record),
      ],
      queues: json['queue'] is List,
    );
  }
}

abstract class PluginCatalogApi {
  Future<PluginCatalog> read();

  /// Newer releases of installed plugins, as the server reports them.
  Future<List<PluginUpdate>> updates();

  /// How the server took the operation. A refusal throws, in the server's
  /// words.
  Future<PluginAcceptance> run(String pluginId, PluginOperation operation);

  /// Updates [pluginIds] at once: the server starts one and queues the rest.
  /// A refusal of them all throws, in the server's words.
  Future<PluginUpdatesAccepted> updateAll(List<String> pluginIds);

  /// The operation under way or the last one, or null where none ever ran
  /// or the server keeps no such record. A server that cannot be reached
  /// throws, as the follow needs to know.
  Future<PluginOperationRecord?> operation();

  /// [operation] with the queue and the latest outcomes beside it; empty
  /// where the server has no such route. A server that cannot be reached
  /// throws.
  Future<PluginOperationsReport> operations();

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
  Future<PluginAcceptance> run(
    String pluginId,
    PluginOperation operation,
  ) async {
    try {
      final response = await client.post(
        '/server/plugins/${Uri.encodeComponent(pluginId)}/${operation.name}',
      );
      return PluginAcceptance.fromJson(response.data);
    } on DioException catch (error) {
      throw PluginCatalogException(_refusal(error));
    }
  }

  @override
  Future<PluginUpdatesAccepted> updateAll(List<String> pluginIds) async {
    try {
      final data = (await client.post(
        '/server/plugins/updates',
        data: {'plugin_ids': pluginIds},
      )).data;
      final json = data is Map ? data : const {};
      List<Object?> list(Object? value) => value is List ? value : const [];
      return PluginUpdatesAccepted(
        accepted: {
          for (final accepted in list(json['operations']))
            if (accepted is Map && accepted['plugin_id'] is String)
              accepted['plugin_id'] as String: PluginAcceptance.fromJson(
                accepted,
              ),
        },
        refused: {
          for (final refused in list(json['refused']))
            if (refused is Map && refused['plugin_id'] is String)
              refused['plugin_id'] as String: switch (refused['message']) {
                final String message when message.isNotEmpty => message,
                _ => 'The server could not finish. Try again.',
              },
        },
      );
    } on DioException catch (error) {
      throw PluginCatalogException(_refusal(error));
    }
  }

  static String _refusal(DioException error) {
    final detail = error.response?.data is Map
        ? (error.response!.data as Map)['detail']
        : null;
    final message = detail is Map ? detail['message'] : null;
    return message is String && message.isNotEmpty
        ? message
        : switch (error.response?.statusCode) {
            404 || 405 => 'This server cannot manage plugins yet.',
            _ => 'The server could not finish. Try again.',
          };
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
  Future<PluginOperationsReport> operations() async {
    try {
      final data = (await client.get('/server/plugins/operation')).data;
      return data is Map
          ? PluginOperationsReport.fromJson(data.cast<String, dynamic>())
          : const PluginOperationsReport();
    } on DioException catch (error) {
      // A server before 0.22 has no such route, and one with its catalog off
      // refuses it. A 5xx, as the web UI's proxy answers while the server
      // restarts, is the server not answering.
      final status = error.response?.statusCode;
      if (status != null && status < 500) return const PluginOperationsReport();
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
/// got: 0 until the server has said, 1 as it ends; or [queued] behind
/// another.
class PluginProgress {
  final PluginOperation operation;
  final String? step;
  final double progress;
  final bool queued;
  const PluginProgress(
    this.operation, {
    this.step,
    this.progress = 0,
    this.queued = false,
  });
}

/// An operation the server follows by id, and whoever waits for its end.
class _Waiter {
  final PluginOperation operation;
  final String id;
  final String? name;
  final done = Completer<PluginOutcome>();

  /// Polls in a row that found it neither under way, queued nor ended.
  int unseen = 0;

  _Waiter(this.operation, this.id, this.name);
}

/// Installs, removals and updates in flight, by plugin id.
class PluginOperationsNotifier extends Notifier<Map<String, PluginProgress>> {
  /// How often the server's record is read while it carries an operation
  /// out, and how long that is given before it is taken for lost.
  static Duration pollInterval = const Duration(seconds: 1);
  static Duration followLimit = const Duration(minutes: 15);

  /// Operations the server follows by id, by plugin, until each has ended.
  final _waiting = <String, _Waiter>{};
  bool _following = false;

  @override
  Map<String, PluginProgress> build() => const {};

  /// Runs the operation to its end: following the server's record where it
  /// carries the operation out as it runs, through its queue where it waits
  /// its turn, or its restart where it restarts to. [name] is the plugin's,
  /// for the restart's subtitle.
  Future<PluginOutcome> run(
    String pluginId,
    PluginOperation operation, {
    String? name,
  }) async {
    if (state.containsKey(pluginId)) return PluginOutcome.unknown;
    ref.read(pluginFailuresProvider.notifier).dismiss(pluginId);
    _progress(pluginId, PluginProgress(operation));
    final PluginAcceptance accepted;
    try {
      accepted = await ref
          .read(pluginCatalogApiProvider)
          .run(pluginId, operation);
    } on PluginCatalogException catch (error) {
      _drop(pluginId);
      return _fail(pluginId, operation, error.message);
    } catch (_) {
      _drop(pluginId);
      rethrow;
    }
    if (!ref.mounted) return PluginOutcome.unknown;
    if (accepted.id case final id?
        when accepted.status != PluginAccepted.done) {
      return _track(
        pluginId,
        operation,
        id,
        name: name,
        queued: accepted.status == PluginAccepted.queued,
      );
    }
    // A server before 0.23 runs one at a time, and names none by id.
    try {
      final outcome = switch (accepted.status) {
        PluginAccepted.restarting => await _followRestart(
          pluginId,
          operation,
          name,
        ),
        PluginAccepted.applying || PluginAccepted.queued =>
          await _followOperation(pluginId, operation, name),
        PluginAccepted.done => PluginOutcome.done,
      };
      if (!ref.mounted) return PluginOutcome.unknown;
      if (outcome != PluginOutcome.done) return outcome;
      return await _settle();
    } finally {
      _drop(pluginId);
    }
  }

  /// Updates several plugins at once, by id with their names: the server
  /// starts one and works through the rest in turn, each followed as its own.
  Future<void> updateAll(Map<String, String> plugins) async {
    final ids = [
      for (final id in plugins.keys)
        if (!state.containsKey(id)) id,
    ];
    if (ids.isEmpty) return;
    for (final id in ids) {
      ref.read(pluginFailuresProvider.notifier).dismiss(id);
      _progress(id, const PluginProgress(PluginOperation.update));
    }
    final PluginUpdatesAccepted answer;
    try {
      answer = await ref.read(pluginCatalogApiProvider).updateAll(ids);
    } on PluginCatalogException catch (error) {
      for (final id in ids) {
        _drop(id);
        _fail(id, PluginOperation.update, error.message);
      }
      return;
    } catch (_) {
      ids.forEach(_drop);
      rethrow;
    }
    if (!ref.mounted) return;
    final followed = <Future<PluginOutcome>>[];
    var settle = false;
    for (final id in ids) {
      final accepted = answer.accepted[id];
      if (accepted?.id case final operationId?) {
        followed.add(
          _track(
            id,
            PluginOperation.update,
            operationId,
            name: plugins[id],
            queued: accepted!.status == PluginAccepted.queued,
          ),
        );
        continue;
      }
      if (answer.refused[id] case final message?) {
        _drop(id);
        _fail(id, PluginOperation.update, message);
        continue;
      }
      // Nothing left to do for it: the lists say so once read again.
      settle = settle || accepted != null;
      if (!settle) _drop(id);
    }
    if (settle) {
      await _settle();
      for (final id in ids) {
        if (!_waiting.containsKey(id)) _drop(id);
      }
    }
    await Future.wait(followed);
  }

  /// Picks up what the server is still carrying out, or has queued — begun
  /// on an earlier visit to the page, before the app was closed, or by
  /// another app.
  Future<void> reattach() async {
    final PluginOperationsReport report;
    try {
      report = await ref.read(pluginCatalogApiProvider).operations();
    } on DioException {
      return;
    }
    if (!ref.mounted) return;
    final record = report.current;
    if (report.queues) {
      final followed = <Future<PluginOutcome>>[];
      // One restarting may already be back; the next poll says.
      if (record != null &&
          (record.running || record.restarting) &&
          !state.containsKey(record.pluginId)) {
        if ((record.id, record.operation) case (final id?, final operation?)) {
          followed.add(
            _track(
              record.pluginId,
              operation,
              id,
              progress: PluginProgress(
                operation,
                step: record.step,
                progress: record.progress,
              ),
            ),
          );
        }
      }
      for (final entry in report.queued) {
        final operation = entry.operation;
        if (operation == null || state.containsKey(entry.pluginId)) continue;
        followed.add(_track(entry.pluginId, operation, entry.id, queued: true));
      }
      await Future.wait(followed);
      return;
    }
    if (record == null || !record.running) return;
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

  void _drop(String pluginId) {
    if (ref.mounted && state.containsKey(pluginId)) {
      state = {...state}..remove(pluginId);
    }
  }

  /// Waits for the operation [id] on [pluginId] to end, followed with every
  /// other the server has accepted by id.
  Future<PluginOutcome> _track(
    String pluginId,
    PluginOperation operation,
    String id, {
    String? name,
    bool queued = false,
    PluginProgress? progress,
  }) {
    final waiter = _Waiter(operation, id, name);
    _waiting[pluginId] = waiter;
    _progress(pluginId, progress ?? PluginProgress(operation, queued: queued));
    if (!_following) unawaited(_followQueue());
    return waiter.done.future;
  }

  /// One poll for every operation followed by id: how far the one under way
  /// has got, which still wait their turn, and how each ended. A restart is
  /// followed once for the operation it carries out, and the queue after it.
  /// Given up once nothing has moved for [followLimit].
  Future<void> _followQueue() async {
    _following = true;
    final api = ref.read(pluginCatalogApiProvider);
    var moved = DateTime.now();
    String? seen;
    PluginOperationRecord? last;
    final restarted = <String>{};
    try {
      while (_waiting.isNotEmpty) {
        await Future<void>.delayed(pollInterval);
        if (!ref.mounted) return;
        final PluginOperationsReport report;
        try {
          report = await api.operations();
        } on DioException {
          if (last?.id case final id?) restarted.add(id);
          if (!await _restarted(last)) return;
          moved = DateTime.now();
          continue;
        }
        if (!ref.mounted) return;
        final current = last = report.current;
        final signature = [
          current?.id,
          current?.status,
          current?.step,
          current?.stepIndex,
          current?.updatedAt,
          for (final entry in report.queued) entry.id,
          for (final result in report.results) result.id,
        ].join('|');
        if (signature != seen) {
          seen = signature;
          moved = DateTime.now();
        }
        PluginOperationRecord? restarting;
        for (final MapEntry(key: pluginId, value: waiter)
            in _waiting.entries.toList()) {
          if (current != null && current.id == waiter.id) {
            waiter.unseen = 0;
            if (current.running || current.restarting) {
              _progress(
                pluginId,
                PluginProgress(
                  waiter.operation,
                  step: current.step,
                  progress: current.progress,
                ),
              );
              if (current.restarting && restarted.add(waiter.id)) {
                restarting = current;
              }
            } else {
              _end(pluginId, waiter, current);
            }
          } else if (report.queued.any((entry) => entry.id == waiter.id)) {
            waiter.unseen = 0;
            _progress(pluginId, PluginProgress(waiter.operation, queued: true));
          } else if (report.results.where((r) => r.id == waiter.id).lastOrNull
              case final result?) {
            _end(pluginId, waiter, result);
          } else if (report.queues && ++waiter.unseen >= 3) {
            // Gone without a trace, as with its record lost to a restart.
            _end(pluginId, waiter, null);
          }
        }
        if (restarting != null && !await _restarted(restarting)) return;
        if (DateTime.now().difference(moved) > followLimit) {
          _giveUp('The server did not finish.');
          return;
        }
      }
    } finally {
      _following = false;
      _giveUp(null);
    }
  }

  /// [waiter]'s operation ended as [record] says, or unknown without one;
  /// a row stays busy until the lists show what came of it.
  void _end(String pluginId, _Waiter waiter, PluginOperationRecord? record) {
    _waiting.remove(pluginId);
    if (record != null && record.failed) {
      _drop(pluginId);
      waiter.done.complete(
        _fail(
          pluginId,
          waiter.operation,
          record.error ?? 'The server could not finish.',
        ),
      );
      return;
    }
    unawaited(() async {
      await _settle();
      _drop(pluginId);
      waiter.done.complete(
        record == null ? PluginOutcome.unknown : PluginOutcome.done,
      );
    }());
  }

  /// Stops following what is left: failed with [message], or, without one,
  /// claiming nothing either way.
  void _giveUp(String? message) {
    for (final MapEntry(key: pluginId, value: waiter)
        in _waiting.entries.toList()) {
      _waiting.remove(pluginId);
      _drop(pluginId);
      waiter.done.complete(
        message == null
            ? PluginOutcome.unknown
            : _fail(pluginId, waiter.operation, message),
      );
    }
  }

  /// Follows the restart that carries [record]'s operation out, or whichever
  /// the server went down for; whether to follow the queue on after it.
  Future<bool> _restarted(PluginOperationRecord? record) async {
    final pluginId = _waiting.containsKey(record?.pluginId)
        ? record!.pluginId
        : _waiting.keys.firstOrNull;
    final waiter = _waiting[pluginId];
    await ref
        .read(restartProvider.notifier)
        .followRestart(
          subtitle: _subtitle(
            waiter?.operation ?? record?.operation ?? PluginOperation.update,
            waiter?.name ?? _nameOf(pluginId),
          ),
        );
    if (!ref.mounted) return false;
    final restart = ref.read(restartProvider);
    if (restart.error != null) {
      _giveUp(_lostInRestart);
      return false;
    }
    // The wait was given up; the server finishes on its own.
    if (!restart.isDone) {
      _giveUp(null);
      return false;
    }
    return true;
  }

  static const _lostInRestart =
      'The server did not come back after its restart, so how this ended '
      'is not known.';

  /// The plugin's name as the catalog on screen has it; one picked up
  /// rather than asked for here comes without.
  String? _nameOf(String? pluginId) {
    if (pluginId == null || !ref.read(pluginCatalogProvider.exists)) {
      return null;
    }
    return ref
        .read(pluginCatalogProvider)
        .value
        ?.plugins
        .where((plugin) => plugin.id == pluginId)
        .firstOrNull
        ?.name;
  }

  static String _subtitle(PluginOperation operation, String? name) {
    final what = name ?? 'the plugin';
    return switch (operation) {
      PluginOperation.install => 'Installing $what\u2026',
      PluginOperation.update => 'Updating $what\u2026',
      PluginOperation.uninstall => 'Uninstalling $what\u2026',
    };
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
    await ref
        .read(restartProvider.notifier)
        .followRestart(subtitle: _subtitle(operation, name));
    if (!ref.mounted) return PluginOutcome.unknown;
    final restart = ref.read(restartProvider);
    if (restart.error != null) {
      return _fail(pluginId, operation, _lostInRestart);
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
