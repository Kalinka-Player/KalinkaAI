import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart' show Logger;

import '../utils/version_order.dart';
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

  /// The server refused the request for now, so nothing is installing yet
  /// and sending it again can succeed; see [ServerUpgradeException.transient].
  final bool canRetry;
  final bool isDone;

  /// Done without installing: the server had nothing left to install, so
  /// [targetVersion] is the version it already runs.
  final bool upToDate;
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
    this.upToDate = false,
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
      upToDate: upToDate,
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

    // Null when the check failed, which leaves the update the user confirmed.
    final current = await _readUpdate();
    if (_upToDate(current)) return;
    var update = current != null && current.canUpgrade ? current : confirmed;
    _begin(update, confirmed);

    try {
      try {
        await api.upgradeServer(update.latestVersion!);
      } on ServerUpgradeException catch (e) {
        if (!e.versionMoved) rethrow;
        final moved = await _readUpdate();
        if (_upToDate(moved)) return;
        if (moved == null ||
            !moved.canUpgrade ||
            moved.latestVersion == update.latestVersion) {
          rethrow;
        }
        update = moved;
        _begin(update, confirmed);
        await api.upgradeServer(update.latestVersion!);
      }
    } catch (e) {
      _logger.e('Upgrade request rejected', error: e);
      state = state.copyWith(
        error: e is ServerUpgradeException
            ? e.message
            : 'The server rejected the upgrade request.',
        canRetry: e is ServerUpgradeException && e.transient,
      );
      return;
    }

    final error = update.packagesOnly
        ? await _awaitPackages(update)
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
      note: _note(update, confirmed),
    );
  }

  static String? _note(ServerUpdateInfo update, ServerUpdateInfo confirmed) {
    final version = update.latestVersion;
    final listed = confirmed.latestVersion;
    if (version == null || listed == null || version == listed) return null;
    // A release can also be pulled, taking the update back to an earlier one.
    return isNewerVersion(version, listed)
        ? 'Version $version came out after the update was listed.'
        : 'The server now offers version $version instead of $listed.';
  }

  /// Read through the banner's provider, so the banner shows the same answer.
  Future<ServerUpdateInfo?> _readUpdate() async {
    ref.invalidate(serverUpdateProvider);
    return ref.read(serverUpdateProvider.future);
  }

  /// Ends the run when [update] shows nothing left to install, as after
  /// another device ran the upgrade first.
  bool _upToDate(ServerUpdateInfo? update) {
    // No latest version means the server has not read the releases yet.
    if (update == null ||
        update.updateAvailable ||
        update.latestVersion == null) {
      return false;
    }
    state = UpgradeState(
      isUpgrading: true,
      isDone: true,
      upToDate: true,
      targetVersion: update.currentVersion,
    );
    return true;
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
  Future<String?> _awaitPackages(ServerUpdateInfo started) async {
    final deadline = _now().add(_deadline);
    while (_now().isBefore(deadline)) {
      await Future.delayed(_pollInterval);
      final update = await _readUpdate();
      // update_available covers the whole install, including a package the
      // server sends no flag for, as before 5.14.0 for the web player.
      if (update != null &&
          update.latestVersion != null &&
          !update.packagesBehind &&
          !(update.packagesOnly && update.updateAvailable) &&
          _installed(started, update)) {
        return null;
      }
    }
    return 'The packages did not finish updating — check the server manually.';
  }

  // dpkg reports a package it is still unpacking as not installed, and so
  // not behind either.
  static bool _installed(ServerUpdateInfo started, ServerUpdateInfo now) =>
      (!started.rendererUpdateAvailable ||
          now.rendererCurrentVersion != null) &&
      (!started.supervisorUpdateAvailable ||
          now.supervisorCurrentVersion != null) &&
      (!started.webUpdateAvailable || now.webCurrentVersion != null);
}
