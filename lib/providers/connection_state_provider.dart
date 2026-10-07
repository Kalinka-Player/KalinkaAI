import 'dart:async' show Timer;

import 'package:dio/dio.dart' show DioException;
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart' show Logger;
import 'connection_settings_provider.dart';
import 'kalinka_player_api_provider.dart';
import 'kiosk_provider.dart' show kioskActiveProvider;
import 'monotonic_clock_provider.dart' show monotonicClockProvider;
import 'playback_time_provider.dart' show appLifecycleProvider;

final _logger = Logger();

enum ConnectionStatus { none, connecting, connected, reconnecting, offline }

final connectionStateProvider =
    NotifierProvider<ConnectionStateNotifier, ConnectionStatus>(
      ConnectionStateNotifier.new,
    );

/// Incremented each time a reconnect attempt fires. `webSocketProvider` watches
/// this so that only timer-driven ticks (or a manual retry) trigger new socket
/// connection attempts — preventing Riverpod's autoDispose rebuild loop.
final retryEpochProvider = NotifierProvider<_RetryEpochNotifier, int>(
  _RetryEpochNotifier.new,
);

/// Explicit retries are also user intent to restore Android media controls.
/// Automatic reachability probes must not carry that intent.
final manualReconnectEpochProvider = NotifierProvider<_RetryEpochNotifier, int>(
  _RetryEpochNotifier.new,
);

class _RetryEpochNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void increment() => state++;
}

class ConnectionStateNotifier extends Notifier<ConnectionStatus> {
  ConnectionStateNotifier({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  Timer? _retryTimer;
  int _retryCount = 0;
  int _probesInFlight = 0;
  // NTP can adjust a Pi's wall clock while it is waiting for the server.
  Duration? _reconnectStartedAt;

  /// When the app was last backgrounded (null while foregrounded).
  DateTime? _backgroundedAt;

  /// A background longer than this forces a fresh event socket on resume —
  /// the old one may have silently died while suspended without ever firing
  /// a close event, leaving a half-open connection the heartbeat hasn't yet
  /// caught.
  static const _staleSocketThreshold = Duration(seconds: 20);

  /// When the connection was last known to be healthy.
  DateTime? lastConnectedAt;

  /// Whether the user dismissed the 30-second escalation card this session.
  bool escalationDismissed = false;

  /// True when reconnecting has been going for >= 30 seconds.
  bool get escalationReached =>
      _reconnectStartedAt != null &&
      _monotonicNow - _reconnectStartedAt! >= const Duration(seconds: 30);

  Duration get _monotonicNow => ref.read(monotonicClockProvider).elapsed;

  @override
  ConnectionStatus build() {
    final settings = ref.read(connectionSettingsProvider);
    ref.onDispose(_cancelRetryTimer);

    ref.listen<AppLifecycleState>(appLifecycleProvider, (_, next) {
      _onLifecycleChange(next);
    });

    // A display opened after the app gave up has no Retry button to press.
    // Not retryNow(): that would also bring back the Android media controls.
    ref.listen<bool>(kioskActiveProvider, (_, active) {
      if (!active || state != ConnectionStatus.offline) return;
      _leaveOffline();
      // While backgrounded, resuming starts the timer.
      if (ref.read(appLifecycleProvider) != AppLifecycleState.resumed) return;
      _startRetryTimer();
      _attemptReconnect();
    });

    return settings.isSet ? ConnectionStatus.connecting : ConnectionStatus.none;
  }

  void _onLifecycleChange(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) {
      final backgroundedFor = _backgroundedAt == null
          ? Duration.zero
          : _now().difference(_backgroundedAt!);
      _backgroundedAt = null;

      // Foregrounded: restart reconnection immediately if it was paused.
      if (state == ConnectionStatus.reconnecting ||
          state == ConnectionStatus.offline) {
        // If we'd escalated to `offline`, drop back into the active reconnect
        // cycle with a fresh escalation window before retrying. The event
        // socket hangs while `offline` (see websocket_provider), so it must see
        // a non-offline status to actually rebuild and connect — mirrors
        // retryNow().
        if (state == ConnectionStatus.offline) _leaveOffline();
        _startRetryTimer();
        _attemptReconnect();
      } else if (state == ConnectionStatus.connected &&
          backgroundedFor >= _staleSocketThreshold) {
        // Still "connected" after a long background, but the event socket may
        // have died silently while suspended (no close event ever fired).
        // Bump the retry epoch to rebuild the socket from scratch: if the
        // server is still reachable the new socket connects and we stay
        // connected, otherwise its failure drops us into the reconnect cycle.
        ref.read(retryEpochProvider.notifier).increment();
      }
    } else {
      // Backgrounded: pause reconnection attempts to save battery and record
      // when we went down so resume can tell a quick app-switch from a long
      // suspend.
      _backgroundedAt ??= _now();
      _cancelRetryTimer();
    }
  }

  void connecting() {
    _cancelRetryTimer();
    state = ConnectionStatus.connecting;
  }

  void connected() {
    _cancelRetryTimer();
    _retryCount = 0;
    _reconnectStartedAt = null;
    lastConnectedAt = _now();
    state = ConnectionStatus.connected;
  }

  void disconnected() {
    _cancelRetryTimer();
    state = ConnectionStatus.none;
  }

  /// Begin automatic reconnect attempts every 5 seconds.
  void startReconnecting() {
    if (state == ConnectionStatus.reconnecting ||
        state == ConnectionStatus.offline) {
      return;
    }
    _retryCount = 0;
    _reconnectStartedAt = _monotonicNow;
    state = ConnectionStatus.reconnecting;
    _startRetryTimer();
  }

  void _startRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      // A slow server would otherwise pile up one probe per tick.
      if (_probesInFlight == 0) _attemptReconnect();
    });
  }

  void markEscalationDismissed() {
    escalationDismissed = true;
  }

  /// Manually trigger a single reconnect attempt (e.g. from Retry button).
  void retryNow() {
    ref.read(manualReconnectEpochProvider.notifier).increment();
    if (state == ConnectionStatus.offline) {
      _leaveOffline();
      escalationDismissed = false;
      _startRetryTimer();
    }
    _attemptReconnect();
  }

  void _leaveOffline() {
    _retryCount = 0;
    _reconnectStartedAt = _monotonicNow;
    state = ConnectionStatus.reconnecting;
  }

  Future<void> _attemptReconnect() async {
    if (ref.read(appLifecycleProvider) != AppLifecycleState.resumed) return;
    _retryCount++;
    _logger.d('Reconnect attempt #$_retryCount');

    // Cheap, timeout-bounded reachability probe over HTTP first (a bare
    // WebSocket.connect can hang on a dead network). Only when the server
    // answers do we rebuild the event socket.
    _probesInFlight++;
    try {
      final proxy = ref.read(kalinkaProxyProvider);
      await proxy.listModules();
    } on DioException {
      _checkEscalation();
      return;
    } on Exception {
      _checkEscalation();
      return;
    } finally {
      _probesInFlight--;
    }

    // Server reachable — rebuild the event socket. Reaching `connected` is
    // deliberately left to the socket itself (see websocket_provider): only
    // once the queue socket is actually open — and the server has replayed the
    // current play queue onto it — do we report connected. Declaring connected
    // here on the HTTP probe alone would leave the UI "connected" while the
    // event stream is still dead, showing an empty queue (issue #21).
    ref.read(retryEpochProvider.notifier).increment();
  }

  void _checkEscalation() {
    // A failed probe may finish after a new connection attempt or disconnect.
    if (state != ConnectionStatus.reconnecting || !escalationReached) return;
    // The display has no Retry button and often starts before the server
    // listens, so it keeps probing until the server answers.
    if (ref.read(kioskActiveProvider)) return;
    _cancelRetryTimer();
    state = ConnectionStatus.offline;
  }

  void _cancelRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }
}
