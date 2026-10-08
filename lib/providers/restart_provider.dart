import 'dart:async' show Timer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart' show Logger;
import 'box_control_provider.dart';
import 'connection_settings_provider.dart';
import 'kalinka_player_api_provider.dart';
import 'settings_provider.dart';

final _logger = Logger();

enum RestartStep { saving, stopping, starting, reconnecting }

class RestartState {
  final bool isRestarting;
  final RestartStep? currentStep;
  final Set<RestartStep> completedSteps;
  final String? error;
  final bool isDone;

  const RestartState({
    this.isRestarting = false,
    this.currentStep,
    this.completedSteps = const {},
    this.error,
    this.isDone = false,
  });

  RestartState copyWith({
    bool? isRestarting,
    RestartStep? currentStep,
    Set<RestartStep>? completedSteps,
    String? error,
    bool? isDone,
  }) {
    return RestartState(
      isRestarting: isRestarting ?? this.isRestarting,
      currentStep: currentStep ?? this.currentStep,
      completedSteps: completedSteps ?? this.completedSteps,
      error: error,
      isDone: isDone ?? this.isDone,
    );
  }
}

final restartProvider = NotifierProvider<RestartNotifier, RestartState>(
  RestartNotifier.new,
);

class RestartNotifier extends Notifier<RestartState> {
  Timer? _dismissTimer;
  int _generation = 0;

  @override
  RestartState build() {
    ref.watch(
      connectionSettingsProvider.select((settings) => settings.address),
    );
    ref.onDispose(() {
      _generation++;
      _dismissTimer?.cancel();
    });
    return const RestartState();
  }

  /// Execute the full restart sequence:
  /// 1. Save config
  /// 2. Trigger restart
  /// 3. Wait for server to go down
  /// 4. Poll until server comes back
  Future<void> executeRestart() async {
    final generation = ++_generation;
    bool current() => ref.mounted && generation == _generation;
    _dismissTimer?.cancel();
    final completed = <RestartStep>{};

    try {
      // Step 1: Save config
      state = RestartState(
        isRestarting: true,
        currentStep: RestartStep.saving,
        completedSteps: Set.from(completed),
      );

      await ref.read(settingsProvider.notifier).applyChanges();
      if (!current()) return;
      completed.add(RestartStep.saving);

      // Step 2: Trigger restart
      state = state.copyWith(
        currentStep: RestartStep.stopping,
        completedSteps: Set.from(completed),
      );

      final api = ref.read(kalinkaProxyProvider);
      try {
        await api.restartServer();
      } catch (_) {
        // Server may close the connection during restart — that's expected
      }
      if (!current()) return;
      completed.add(RestartStep.stopping);

      // Step 3: Wait for server to go down
      state = state.copyWith(
        currentStep: RestartStep.starting,
        completedSteps: Set.from(completed),
      );
      await Future.delayed(const Duration(seconds: 2));
      if (!current()) return;
      completed.add(RestartStep.starting);

      // Step 4: Poll health check until server comes back
      state = state.copyWith(
        currentStep: RestartStep.reconnecting,
        completedSteps: Set.from(completed),
      );

      bool connected = false;
      // Applying settings can install system packages or optional Python
      // dependencies. Keep waiting while that work runs with Core stopped.
      const maxAttempts = 450;
      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        await Future.delayed(const Duration(seconds: 2));
        if (!current()) return;
        try {
          await ref.read(kalinkaProxyProvider).listModules();
          if (!current()) return;
          connected = true;
          break;
        } catch (_) {
          if (!current()) return;
          _logger.d('Restart reconnect attempt ${attempt + 1}/$maxAttempts');
        }
      }

      completed.add(RestartStep.reconnecting);

      if (!connected) {
        state = state.copyWith(
          completedSteps: Set.from(completed),
          error: 'Server did not come back after restart.',
        );
        return;
      }

      // A requested setting is not proof that its package operation worked.
      // Read the actual result and discover newly installed/removed controls.
      await ref.read(settingsProvider.notifier).loadConfig();
      if (!current()) return;
      ref.invalidate(boxControlProvider);

      // All done
      state = RestartState(
        isRestarting: true,
        isDone: true,
        completedSteps: Set.from(completed),
        currentStep: null,
      );

      // Auto-dismiss after 2.2 seconds
      _dismissTimer = Timer(const Duration(milliseconds: 2200), () {
        state = const RestartState();
      });
    } catch (e) {
      if (!current()) return;
      _logger.e('Restart failed', error: e);
      state = state.copyWith(
        error: e.toString(),
        completedSteps: Set.from(completed),
      );
    }
  }

  void dismiss() {
    // The server keeps doing the requested work; only stop this UI's wait.
    _generation++;
    _dismissTimer?.cancel();
    state = const RestartState();
  }
}
