import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart' show Logger;

import 'kalinka_player_api_provider.dart';
import 'server_update_provider.dart';

final _logger = Logger();

const _pollInterval = Duration(seconds: 3);
const _deadline = Duration(minutes: 15);

enum UpgradeStep { installing, reconnecting, updatingPackages }

class UpgradeState {
  final bool isUpgrading;
  final UpgradeStep? currentStep;
  final Set<UpgradeStep> completedSteps;
  final String? error;

  /// The server refused the request, so nothing is installing yet.
  final bool canRetry;
  final bool isDone;
  final String? targetVersion;

  /// See [ServerUpdateInfo.packagesOnly].
  final bool packagesOnly;

  /// Set when the server's update moved on from the one the user confirmed.
  final String? note;

  const UpgradeState({
    this.isUpgrading = false,
    this.currentStep,
    this.completedSteps = const {},
    this.error,
    this.canRetry = false,
    this.isDone = false,
    this.targetVersion,
    this.packagesOnly = false,
    this.note,
  });

  UpgradeState copyWith({
    bool? isUpgrading,
    UpgradeStep? currentStep,
    Set<UpgradeStep>? completedSteps,
    String? error,
    bool canRetry = false,
    bool? isDone,
  }) {
    return UpgradeState(
      isUpgrading: isUpgrading ?? this.isUpgrading,
      currentStep: currentStep ?? this.currentStep,
      completedSteps: completedSteps ?? this.completedSteps,
      error: error,
      canRetry: canRetry,
      isDone: isDone ?? this.isDone,
      targetVersion: targetVersion,
      packagesOnly: packagesOnly,
      note: note,
    );
  }
}

final upgradeProvider = NotifierProvider<UpgradeNotifier, UpgradeState>(
  UpgradeNotifier.new,
);

class UpgradeNotifier extends Notifier<UpgradeState> {
  UpgradeNotifier({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  ServerUpdateInfo? _confirmed;

  @override
  UpgradeState build() => const UpgradeState();

  /// Execute the upgrade sequence:
  /// 1. Re-read the server's update and request that version: the server
  ///    refuses any other, and its own check may have moved on since
  ///    [confirmed] was read
  /// 2. A server upgrade is "Installing" until the server goes down (the
  ///    server keeps answering until the new package restarts it), then
  ///    "Reconnecting" until it answers on the new version
  /// 3. A packages-only upgrade is "Updating packages" until the server
  ///    reports none of them behind
  Future<void> executeUpgrade(ServerUpdateInfo confirmed) async {
    _confirmed = confirmed;
    final api = ref.read(kalinkaProxyProvider);
    _begin(confirmed, confirmed);

    var update = await _currentOffer() ?? confirmed;
    _begin(update, confirmed);

    try {
      try {
        await api.upgradeServer(update.latestVersion!);
      } on ServerUpgradeException catch (e) {
        if (e.statusCode != 409) rethrow;
        final current = await _currentOffer();
        if (current == null || current.latestVersion == update.latestVersion) {
          rethrow;
        }
        update = current;
        _begin(update, confirmed);
        await api.upgradeServer(update.latestVersion!);
      }
    } catch (e) {
      _logger.e('Upgrade request rejected', error: e);
      state = state.copyWith(
        error: e is ServerUpgradeException
            ? e.message
            : 'The server rejected the upgrade request.',
        canRetry: true,
      );
      return;
    }

    final error = update.packagesOnly
        ? await _awaitPackages()
        : await _awaitVersion(api, update.latestVersion!);
    if (error != null) {
      state = state.copyWith(error: error);
      return;
    }

    state = UpgradeState(
      isUpgrading: true,
      isDone: true,
      completedSteps: update.packagesOnly
          ? const {UpgradeStep.updatingPackages}
          : const {UpgradeStep.installing, UpgradeStep.reconnecting},
      targetVersion: update.latestVersion,
      packagesOnly: update.packagesOnly,
      note: state.note,
    );
    // The new server re-checks for updates itself; refetch so the banner
    // disappears instead of advertising the version we just installed. The
    // packages wait already left the last answer in place.
    if (!update.packagesOnly) ref.invalidate(serverUpdateProvider);
  }

  Future<void> retry() async {
    final confirmed = _confirmed;
    if (!state.canRetry || confirmed == null) return;
    await executeUpgrade(confirmed);
  }

  void dismiss() {
    state = const UpgradeState();
  }

  void _begin(ServerUpdateInfo update, ServerUpdateInfo confirmed) {
    state = UpgradeState(
      isUpgrading: true,
      currentStep: update.packagesOnly
          ? UpgradeStep.updatingPackages
          : UpgradeStep.installing,
      targetVersion: update.latestVersion,
      packagesOnly: update.packagesOnly,
      note: update.latestVersion == confirmed.latestVersion
          ? null
          : 'Version ${update.latestVersion} came out after the update '
                'was listed.',
    );
  }

  /// Read through the banner's provider, so the banner shows the same answer.
  Future<ServerUpdateInfo?> _readUpdate() async {
    ref.invalidate(serverUpdateProvider);
    return ref.read(serverUpdateProvider.future);
  }

  Future<ServerUpdateInfo?> _currentOffer() async {
    final update = await _readUpdate();
    return update != null && update.canUpgrade ? update : null;
  }

  Future<String?> _awaitVersion(KalinkaPlayerProxy api, String version) async {
    // Poll until the server answers with the target version. The old
    // version answering just means apt hasn't restarted it yet, so it is
    // never treated as failure before the deadline — only the deadline
    // decides that (a connection blip mid-install must not be misread as
    // "came back on the old version"). One generous deadline covers the
    // whole install: download + apt time dominates and varies wildly
    // between a Pi and a PC.
    final deadline = _now().add(_deadline);
    var wentDown = false;
    String? lastSeen;
    while (_now().isBefore(deadline)) {
      await Future.delayed(_pollInterval);
      try {
        final v = await api.getServerVersion();
        lastSeen = v['server_version'] as String?;
        if (lastSeen == version) return null;
      } catch (_) {
        if (!wentDown) {
          wentDown = true;
          state = state.copyWith(
            currentStep: UpgradeStep.reconnecting,
            completedSteps: const {UpgradeStep.installing},
          );
        }
      }
    }
    return wentDown
        ? 'Server did not come back on the new version — check it manually.'
        : 'Server is still on version ${lastSeen ?? 'unknown'} — '
              'the upgrade did not start.';
  }

  /// The server's version never changes here, so only its update check can
  /// tell when the installer has finished.
  Future<String?> _awaitPackages() async {
    final deadline = _now().add(_deadline);
    while (_now().isBefore(deadline)) {
      await Future.delayed(_pollInterval);
      final update = await _readUpdate();
      if (update != null && !update.packagesBehind) return null;
    }
    return 'The packages did not finish updating — check the server manually.';
  }
}
