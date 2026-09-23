import 'dart:async' show Timer, unawaited;

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/log_export.dart';
import '../utils/log_export_saver.dart';
import 'log_export_api.dart';
import 'playback_time_provider.dart' show appLifecycleProvider;

/// A native save under way: bytes received, and how many to expect.
class LogTransfer {
  final int received;
  final int? total;

  const LogTransfer(this.received, this.total);

  double? get fraction =>
      (total == null || total == 0) ? null : (received / total!).clamp(0, 1);
}

/// What the Download server logs screen shows.
class LogExportView {
  /// The server's export as last read; null until the first answer.
  final LogExportStatus? status;

  /// The last request got no answer; shown as waiting, not as a failure.
  final bool waitingForServer;

  /// The connected server predates log export.
  final bool unsupported;

  /// An export seen preparing is gone: the server restarted meanwhile.
  final bool interrupted;

  /// Why the last action was refused, in words fit to show.
  final String? actionError;

  /// A request the user made is in flight.
  final bool busy;

  final LogTransfer? transfer;

  const LogExportView({
    this.status,
    this.waitingForServer = false,
    this.unsupported = false,
    this.interrupted = false,
    this.actionError,
    this.busy = false,
    this.transfer,
  });

  LogExportView copyWith({
    LogExportStatus? status,
    bool? waitingForServer,
    bool? unsupported,
    bool? interrupted,
    String? actionError,
    bool? busy,
    LogTransfer? transfer,
  }) => LogExportView(
    status: status ?? this.status,
    waitingForServer: waitingForServer ?? this.waitingForServer,
    unsupported: unsupported ?? this.unsupported,
    interrupted: interrupted ?? this.interrupted,
    actionError: actionError,
    busy: busy ?? this.busy,
    transfer: transfer,
  );

  bool get preparing => status?.state == LogExportState.preparing;
}

/// The connected server's log export, kept current while the screen that
/// watches it is up.
///
/// Reads the export when built and on every return to the foreground, and
/// polls once a second only while it is being prepared or the server is not
/// answering. Rebuilt on a server switch, so it always shows the connected
/// server's export. Leaving the screen never cancels the export itself.
class LogExportController extends Notifier<LogExportView> {
  Timer? _poll;
  bool _foreground = true;
  // Bumped by every action and server switch, so a read begun before one
  // cannot land after it.
  int _generation = 0;

  LogExportApi get _api => ref.read(logExportApiProvider);

  bool _stale(int generation) => !ref.mounted || generation != _generation;

  @override
  LogExportView build() {
    ref.watch(logExportApiProvider);
    _generation++;
    _foreground = ref.read(appLifecycleProvider) == AppLifecycleState.resumed;
    ref.listen<AppLifecycleState>(appLifecycleProvider, (_, next) {
      _foreground = next == AppLifecycleState.resumed;
      if (_foreground) {
        unawaited(refresh());
      } else {
        _poll?.cancel();
      }
    });
    ref.onDispose(() => _poll?.cancel());
    Future.microtask(refresh);
    return const LogExportView();
  }

  /// Read the server's export now.
  Future<void> refresh() async {
    if (!ref.mounted) return;
    _poll?.cancel();
    final generation = _generation;
    try {
      final status = await _api.status();
      if (_stale(generation)) return;
      _show(status);
    } on LogExportUnreachableException {
      if (_stale(generation)) return;
      state = state.copyWith(waitingForServer: true, transfer: state.transfer);
    } on LogExportUnsupportedException {
      if (_stale(generation)) return;
      state = state.copyWith(
        unsupported: true,
        waitingForServer: false,
        transfer: state.transfer,
      );
    } on LogExportException catch (e) {
      if (_stale(generation)) return;
      state = state.copyWith(
        actionError: e.message,
        waitingForServer: false,
        transfer: state.transfer,
      );
    } catch (_) {
      if (_stale(generation)) return;
      state = state.copyWith(
        actionError: 'The server could not handle the request.',
        waitingForServer: false,
        transfer: state.transfer,
      );
    }
    _schedule();
  }

  /// Start preparing the last [lookback] of logs.
  Future<void> prepare({
    required Duration lookback,
    required bool includeLocalRenderer,
  }) => _act(() async {
    final status = await _api.start(
      lookback: lookback,
      includeLocalRenderer: includeLocalRenderer,
    );
    if (ref.mounted) _show(status);
  });

  /// Cancel preparation, or discard the ready archive.
  Future<void> withdraw() => _act(() async {
    await _api.withdraw();
    if (!ref.mounted) return;
    state = LogExportView(
      status: LogExportStatus(
        state: LogExportState.none,
        availableSources: state.status?.availableSources ?? const [],
      ),
    );
  });

  /// Save the ready archive through [saver], or send it with [share].
  ///
  /// Reads the export first, so an archive that expired meanwhile turns back
  /// into Prepare logs rather than a failed download. Returns null when there
  /// was nothing to save.
  Future<SaveOutcome?> save(LogExportSaver saver, {bool share = false}) async {
    if (state.busy) return null;
    await refresh();
    if (!ref.mounted) return null;
    final download = state.status?.download;
    if (download == null) return null;
    final archive = LogArchive(
      filename: download.filename,
      url: _api.downloadUrl,
      open: _api.download,
    );
    SaveOutcome? outcome;
    await _act(() async {
      // The screen may close mid-transfer; the save carries on without it.
      void progress(int received, int? total) {
        if (!ref.mounted) return;
        state = state.copyWith(
          busy: true,
          transfer: LogTransfer(received, total),
        );
      }

      outcome = share
          ? await saver.share(archive, onProgress: progress)
          : await saver.save(archive, onProgress: progress);
    }, failure: 'The logs could not be saved.');
    return outcome;
  }

  Future<void> _act(
    Future<void> Function() action, {
    String failure = 'The server could not handle the request.',
  }) async {
    if (state.busy) return;
    _poll?.cancel();
    _generation++;
    state = state.copyWith(busy: true, interrupted: false);
    try {
      await action();
      if (!ref.mounted) return;
      state = state.copyWith(busy: false);
    } on LogExportUnreachableException {
      if (!ref.mounted) return;
      state = state.copyWith(busy: false, waitingForServer: true);
    } on LogExportException catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(busy: false, actionError: e.message);
      if (e.code == LogExportException.notReady.code) {
        await refresh();
        return;
      }
    } catch (_) {
      if (!ref.mounted) return;
      state = state.copyWith(busy: false, actionError: failure);
    }
    _schedule();
  }

  void _show(LogExportStatus status) {
    final wasPreparing = state.preparing;
    state = state.copyWith(
      status: status,
      waitingForServer: false,
      unsupported: false,
      interrupted:
          state.interrupted ||
          (wasPreparing && status.state == LogExportState.none),
      actionError: state.actionError,
      transfer: state.transfer,
    );
  }

  void _schedule() {
    _poll?.cancel();
    if (!_foreground || state.busy) return;
    if (state.preparing || state.waitingForServer) {
      _poll = Timer(const Duration(seconds: 1), refresh);
    }
  }
}

final logExportProvider =
    NotifierProvider.autoDispose<LogExportController, LogExportView>(
      LogExportController.new,
    );
