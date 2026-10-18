import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data_model/data_model.dart' show PlayerStateType;
import '../providers/app_state_provider.dart' show playerStateProvider;
import '../providers/connection_state_provider.dart'
    show connectionStateProvider;
import '../providers/monotonic_clock_provider.dart' show monotonicClockProvider;

/// Expose app lifecycle as a provider.
final appLifecycleProvider =
    NotifierProvider<AppLifecycleNotifier, AppLifecycleState>(
      AppLifecycleNotifier.new,
    );

class AppLifecycleNotifier extends Notifier<AppLifecycleState> {
  AppLifecycleListener? _listener;

  @override
  AppLifecycleState build() {
    // Assume resumed initially (Flutter may deliver the real state soon after)
    state = AppLifecycleState.resumed;

    _listener = AppLifecycleListener(onStateChange: (s) => state = s);

    ref.onDispose(() => _listener?.dispose());
    return state;
  }
}

/// Public provider you watch in widgets.
/// - Uses `Stopwatch` (monotonic) to advance between accurate updates.
/// - Emits once per second only when app is RESUMED.
/// - On resume, emits immediately (catch-up) and restarts the 1s tick.
/// - While the connection is interrupted, holds still until the server
///   reports again.
final playbackTimeMsProvider = NotifierProvider<PlaybackTimeMsNotifier, int>(
  PlaybackTimeMsNotifier.new,
);

typedef _ServerTiming = ({
  PlayerStateType? playerState,
  int positionMs,
  int timestampMs,
});

typedef _PlaybackTimingSnapshot = ({_ServerTiming server, bool interrupted});

final _playbackTimingSnapshotProvider = Provider<_PlaybackTimingSnapshot>((
  ref,
) {
  // Keep this snapshot primitive-only so unrelated object identity churn
  // (e.g. currentTrack instances) does not retrigger the playback ticker.
  final server = ref.watch(
    playerStateProvider.select(
      (s) => (
        playerState: s.state,
        positionMs: s.position ?? 0,
        timestampMs: s.timestampNs,
      ),
    ),
  );
  final interrupted = ref.watch(
    connectionStateProvider.select((s) => s.isInterrupted),
  );
  return (server: server, interrupted: interrupted);
});

class PlaybackTimeMsNotifier extends Notifier<int> {
  Timer? _tick;
  int _tickGeneration = 0;

  // Where playback stood when the connection dropped. Kept until the server
  // reports again, even once reconnected: extrapolating the old state would
  // count the outage as played.
  ({_ServerTiming server, int ms})? _held;
  bool _wasInterrupted = false;

  int _extrapolate(_ServerTiming server) {
    if (server.playerState == PlayerStateType.playing) {
      final deltaMs =
          ref.read(monotonicClockProvider).elapsedMilliseconds -
          server.timestampMs;
      return server.positionMs + (deltaMs > 0 ? deltaMs : 0);
    }
    return server.positionMs;
  }

  int _computeTimeMs(_PlaybackTimingSnapshot snapshot) =>
      _held?.ms ?? _extrapolate(snapshot.server);

  void _cancelTick() {
    _tick?.cancel();
    _tick = null;
    _tickGeneration++;
  }

  void _emitCurrentTime() {
    state = _computeTimeMs(ref.read(_playbackTimingSnapshotProvider));
  }

  void _restartTicking({
    required AppLifecycleState lifecycle,
    required _PlaybackTimingSnapshot snapshot,
  }) {
    _cancelTick();

    if (_held != null ||
        lifecycle != AppLifecycleState.resumed ||
        snapshot.server.playerState != PlayerStateType.playing) {
      return;
    }

    final currentMs = _computeTimeMs(snapshot);
    final msUntilNextSecond = 1000 - (currentMs % 1000);
    final gen = _tickGeneration;

    _tick = Timer(Duration(milliseconds: msUntilNextSecond), () {
      if (_tickGeneration != gen) return;
      _tick = null;

      if (ref.read(appLifecycleProvider) != AppLifecycleState.resumed) {
        return;
      }

      _emitCurrentTime();
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_tickGeneration != gen) {
          _cancelTick();
          return;
        }
        if (ref.read(appLifecycleProvider) != AppLifecycleState.resumed) {
          _cancelTick();
          return;
        }
        _emitCurrentTime();
      });
    });
  }

  @override
  int build() {
    final snapshot = ref.watch(_playbackTimingSnapshotProvider);
    final lifecycle = ref.watch(appLifecycleProvider);

    // Riverpod disposes the previous build's callbacks when these watched
    // values change. Register cleanup for every newly created ticker.
    ref.onDispose(_cancelTick);

    if (_held?.server != snapshot.server) _held = null;
    // Only on the drop itself: a report arriving while still interrupted
    // (e.g. the replay) is fresh and must not be held past reconnecting.
    // A hold still in place is kept: re-extrapolating would count the
    // earlier outage as played.
    if (snapshot.interrupted && !_wasInterrupted && _held == null) {
      _held = (server: snapshot.server, ms: _extrapolate(snapshot.server));
    }
    _wasInterrupted = snapshot.interrupted;

    _restartTicking(lifecycle: lifecycle, snapshot: snapshot);
    return _computeTimeMs(snapshot);
  }
}
