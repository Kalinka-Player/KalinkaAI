import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart';
import 'connection_settings_provider.dart';
import 'kalinka_player_api_provider.dart';

/// Library-pipeline stages surfaced to the user, in pipeline order. The
/// server's `clap_audio` maps to [analyzingAudio]; `clap_text` and any later
/// embedding stage fold into [preparingAi].
enum IndexerDisplayStage {
  indexing('Indexing'),
  analyzingAudio('Analyzing audio'),
  enrichment('Enrichment'),
  preparingAi('Preparing AI search');

  final String label;
  const IndexerDisplayStage(this.label);
}

/// Pipeline progress published as its own provider so the 5s poll loop does
/// not churn the wider search state. Widgets that render the progress banner
/// watch this provider directly; everything else is unaffected by ticks.
class IndexerStatusState {
  /// Earliest pipeline stage that still has outstanding work — the one the
  /// banner names. Stages overlap on the server (enrichment starts while the
  /// scan is still finding files), but showing the earliest keeps the label
  /// from jumping back and forth. Null when the whole pipeline is idle.
  final IndexerDisplayStage? stage;

  /// Progress (0-100) of [stage], monotonically non-decreasing while the
  /// stage is displayed: raw numbers can dip when new work is queued
  /// mid-run. Resets when the displayed stage changes.
  final double? progressPct;

  final StageStatus? scan;
  final bool requesting;
  final String? requestError;
  final int libraryRevision;

  const IndexerStatusState({
    this.stage,
    this.progressPct,
    this.scan,
    this.requesting = false,
    this.requestError,
    this.libraryRevision = 0,
  });

  bool get scanBusy =>
      requesting || scan?.scanPending == true || scan?.scanning == true;

  IndexerStatusState withRequest({required bool requesting, String? error}) =>
      IndexerStatusState(
        stage: stage,
        progressPct: progressPct,
        scan: scan,
        requesting: requesting,
        requestError: error,
        libraryRevision: libraryRevision,
      );

  /// Shared caption for progress surfaces: "Indexing · 45%", or "Indexing…"
  /// while the percentage is unknown. Null when the pipeline is idle.
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
    IndexerDisplayStage? displayedStage;
    double? progress;
    for (final stage in IndexerDisplayStage.values) {
      var total = 0;
      var outstanding = 0;
      for (final stages in status.modules.values) {
        for (final entry in stages.entries) {
          if (_displayStageFor(entry.key) != stage) continue;
          total += entry.value.total;
          outstanding += entry.value.pending + entry.value.inProgress;
        }
      }
      if (outstanding == 0) continue;
      final raw = total == 0
          ? 0.0
          : (100.0 * (total - outstanding) / total).clamp(0.0, 99.0).toDouble();
      final prev = !completed && state.stage == stage
          ? state.progressPct
          : null;
      displayedStage = stage;
      progress = prev == null ? raw : math.max(prev, raw);
      break;
    }
    state = IndexerStatusState(
      stage: displayedStage,
      progressPct: progress,
      scan: scan,
      libraryRevision: revision,
      requestError: state.requestError,
      requesting: _awaitingScan,
    );
  }

  IndexerDisplayStage _displayStageFor(String serverStage) {
    switch (serverStage) {
      case 'indexing':
        return IndexerDisplayStage.indexing;
      case 'clap_audio':
        return IndexerDisplayStage.analyzingAudio;
      case 'enrichment':
        return IndexerDisplayStage.enrichment;
      default: // clap_text and any future enrichment-dependent stage
        return IndexerDisplayStage.preparingAi;
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
