import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart';
import 'connection_settings_provider.dart';
import 'kalinka_player_api_provider.dart';

/// Library-pipeline stages surfaced to the user, in pipeline order. The
/// server's `indexing` is [findingMusic]; `clap_audio`, `clap_text` and any
/// later embedding stage fold into [smartSearch], which is all they feed.
enum IndexerDisplayStage {
  findingMusic('Finding music'),
  enrichment('Adding artwork & details'),
  smartSearch('Preparing smart search');

  final String label;
  const IndexerDisplayStage(this.label);
}

/// One reported stage, summed across the modules that report it.
class IndexerStageProgress {
  final IndexerDisplayStage stage;

  /// Outstanding work, or a scan still looking; a stage without either is
  /// done for now.
  final bool active;

  /// Progress (0-100) while [active], monotonically non-decreasing while it
  /// stays active: raw numbers can dip when new work is queued mid-run. Null
  /// while unknown, as while a scan is still listing folders.
  final double? progressPct;

  const IndexerStageProgress(
    this.stage, {
    this.active = false,
    this.progressPct,
  });

  @override
  bool operator ==(Object other) =>
      other is IndexerStageProgress &&
      other.stage == stage &&
      other.active == active &&
      other.progressPct == progressPct;

  @override
  int get hashCode => Object.hash(stage, active, progressPct);
}

/// Pipeline progress published as its own provider so the 5s poll loop does
/// not churn the wider search state. Widgets that render the progress banner
/// watch this provider directly; everything else is unaffected by ticks.
class IndexerStatusState {
  /// Every stage the server reports, in pipeline order.
  final List<IndexerStageProgress> stages;

  final StageStatus? scan;
  final bool requesting;
  final String? requestError;
  final int libraryRevision;

  const IndexerStatusState({
    this.stages = const [],
    this.scan,
    this.requesting = false,
    this.requestError,
    this.libraryRevision = 0,
  });

  /// Earliest stage with work under way — the one a one-line caption names.
  /// Stages overlap on the server (enrichment starts while the scan is still
  /// finding files), but naming the earliest keeps the label from jumping
  /// back and forth. Null when the whole pipeline is idle.
  IndexerStageProgress? get current {
    for (final stage in stages) {
      if (stage.active) return stage;
    }
    return null;
  }

  IndexerDisplayStage? get stage => current?.stage;
  double? get progressPct => current?.progressPct;

  bool get scanBusy =>
      requesting || scan?.scanPending == true || scan?.scanning == true;

  IndexerStatusState withRequest({required bool requesting, String? error}) =>
      IndexerStatusState(
        stages: stages,
        scan: scan,
        requesting: requesting,
        requestError: error,
        libraryRevision: libraryRevision,
      );

  /// Shared caption for progress surfaces: "Finding music · 45%", or
  /// "Finding music…" while the percentage is unknown. Null when the pipeline
  /// is idle.
  String? get caption {
    final stage = this.stage;
    if (stage == null) return null;
    final pct = progressPct;
    if (pct == null) return '${stage.label}…';
    return '${stage.label} · ${pct.toStringAsFixed(0)}%';
  }
}

class IndexerStatusNotifier extends Notifier<IndexerStatusState> {
  Timer? _pollTimer;
  int _serverGeneration = 0;
  bool _posting = false;
  bool _awaitingScan = false;

  /// Surfaces that want the poll running (search banner, empty-queue status)
  /// pair [acquire] with [release]. A count, not a flag: screen transitions
  /// briefly mount both surfaces.
  int _holders = 0;

  /// Bumped by [release] so a refresh whose request is in flight when the
  /// last surface closes cannot re-arm the timer afterwards.
  int _generation = 0;
  static const _activePollInterval = Duration(seconds: 5);

  /// Idle cadence: keeps the banner able to appear if pipeline work starts
  /// while the search surface stays open (a scheduled rescan, a manual
  /// re-index) at negligible request cost.
  static const _idlePollInterval = Duration(seconds: 30);

  @override
  IndexerStatusState build() {
    ref.onDispose(() {
      _generation++;
      _pollTimer?.cancel();
    });
    ref.listen(connectionSettingsProvider, (previous, next) {
      if (previous?.baseUrl == next.baseUrl) return;
      _generation++;
      _serverGeneration++;
      _posting = _awaitingScan = false;
      _pollTimer?.cancel();
      state = const IndexerStatusState();
      if (_holders > 0) unawaited(refresh());
    });
    return const IndexerStatusState();
  }

  void acquire() {
    _holders++;
    if (_holders > 1) return; // poll already running
    unawaited(refresh());
  }

  void release() {
    if (_holders > 0) _holders--;
    if (_holders > 0) return;
    _generation++;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// One poll cycle; re-arms itself until the last [release]: every 5s while
  /// the pipeline works, every 30s while it is idle, unreachable, or awaiting
  /// connection settings. A failed poll keeps the last state — the pipeline
  /// is likely still running, and the retry self-heals.
  Future<void> refresh() async {
    _pollTimer?.cancel();
    final generation = ++_generation;
    final settings = ref.read(connectionSettingsProvider);
    if (!settings.isSet) {
      // No server yet (fresh install mid-OOBE): keep the chain alive so the
      // poll starts once settings appear, without touching the network.
      if (_holders > 0) _pollTimer = Timer(_idlePollInterval, refresh);
      return;
    }
    var polled = false;
    try {
      final api = ref.read(kalinkaProxyProvider);
      final status = await api.getIndexerStatus();
      if (!ref.mounted || generation != _generation) return;
      _apply(status);
      polled = true;
    } catch (_) {
      if (!ref.mounted || generation != _generation) return;
      // Non-critical (server briefly unreachable) — keep the last state
      // rather than flashing "done", and let the next poll correct it.
    }
    if (_holders > 0) {
      _pollTimer = Timer(
        polled && (state.stage != null || state.scanBusy)
            ? _activePollInterval
            : _idlePollInterval,
        refresh,
      );
    }
  }

  Future<void> rescan() async {
    if (state.scanBusy || state.scan?.indexerAvailable != true) return;
    final serverGeneration = _serverGeneration;
    _generation++;
    _pollTimer?.cancel();
    _posting = _awaitingScan = true;
    final api = ref.read(kalinkaProxyProvider);
    state = state.withRequest(requesting: true);
    try {
      await api.rescanLibrary();
    } catch (_) {
      if (!ref.mounted || serverGeneration != _serverGeneration) return;
      _posting = _awaitingScan = false;
      state = state.withRequest(
        requesting: false,
        error: 'Couldn’t request a scan. Please try again.',
      );
      if (_holders > 0) _pollTimer = Timer(_idlePollInterval, refresh);
      return;
    }
    if (!ref.mounted || serverGeneration != _serverGeneration) return;
    _posting = false;
    // The server queues the request before acknowledging it, so the next
    // status may already be idle after a short successful or failed check.
    await refresh();
  }

  void _apply(IndexerStatus status) {
    final scan = status.modules['localfiles']?['indexing'];
    final previousScan = state.scan;
    if (!_posting) {
      _awaitingScan = false;
    }
    final completed =
        scan?.lastScanAt != null &&
        scan!.lastScanAt != previousScan?.lastScanAt &&
        (previousScan != null || state.requesting);
    final revision = state.libraryRevision + (completed ? 1 : 0);
    final stages = <IndexerStageProgress>[];
    for (final stage in IndexerDisplayStage.values) {
      var reported = false;
      var looking = false;
      var total = 0;
      var outstanding = 0;
      for (final module in status.modules.values) {
        for (final entry in module.entries) {
          if (_displayStageFor(entry.key) != stage) continue;
          reported = true;
          // Checking unchanged folders creates no work, but is a scan.
          looking |= entry.value.scanning;
          total += entry.value.total;
          outstanding += entry.value.pending + entry.value.inProgress;
        }
      }
      if (!reported) continue;
      if (outstanding == 0) {
        stages.add(IndexerStageProgress(stage, active: looking));
        continue;
      }
      final raw = total == 0
          ? 0.0
          : (100.0 * (total - outstanding) / total).clamp(0.0, 99.0).toDouble();
      final prev = completed
          ? null
          : state.stages
                .where((s) => s.stage == stage && s.active)
                .firstOrNull
                ?.progressPct;
      stages.add(
        IndexerStageProgress(
          stage,
          active: true,
          progressPct: prev == null ? raw : math.max(prev, raw),
        ),
      );
    }
    state = IndexerStatusState(
      // Unchanged stages keep their identity, so selects on them stay quiet.
      stages: listEquals(stages, state.stages) ? state.stages : stages,
      scan: scan,
      libraryRevision: revision,
      requestError: state.requestError,
      requesting: _awaitingScan,
    );
  }

  IndexerDisplayStage _displayStageFor(String serverStage) {
    switch (serverStage) {
      case 'indexing':
        return IndexerDisplayStage.findingMusic;
      case 'enrichment':
        return IndexerDisplayStage.enrichment;
      default: // clap_audio, clap_text and any future embedding stage
        return IndexerDisplayStage.smartSearch;
    }
  }
}

final indexerStatusProvider =
    NotifierProvider<IndexerStatusNotifier, IndexerStatusState>(
      IndexerStatusNotifier.new,
    );

/// Holds the indexer poll for this State's lifetime. The microtask defers
/// past the mounting build; the flag keeps dispose from releasing a hold the
/// microtask never took.
mixin IndexerPollHolder<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  late final IndexerStatusNotifier _pollNotifier;
  bool _pollAcquired = false;

  @override
  void initState() {
    super.initState();
    _pollNotifier = ref.read(indexerStatusProvider.notifier);
    Future.microtask(() {
      if (!mounted) return;
      _pollAcquired = true;
      _pollNotifier.acquire();
    });
  }

  @override
  void dispose() {
    if (_pollAcquired) _pollNotifier.release();
    super.dispose();
  }
}
