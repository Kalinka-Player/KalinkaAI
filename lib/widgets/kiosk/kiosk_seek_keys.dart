import 'dart:async';
import 'dart:ui' show AppLifecycleState;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../data_model/kalinka_ws_api.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/connection_settings_provider.dart';
import '../../providers/connection_state_provider.dart';
import '../../providers/kalinka_ws_api_provider.dart';
import '../../providers/monotonic_clock_provider.dart';
import '../../providers/now_playing_provider.dart';
import '../../providers/playback_time_provider.dart';

/// Changing any of these ends a held seek before it can affect a new track.
final _seekContext = Provider((ref) {
  if (ref.watch(connectionStateProvider) != ConnectionStatus.connected ||
      ref.watch(appLifecycleProvider) != AppLifecycleState.resumed) {
    return null;
  }
  final control = ref.watch(playbackControlProvider);
  final active = ref.watch(
    playerStateProvider.select(
      (s) =>
          s.state == PlayerStateType.playing ||
          s.state == PlayerStateType.paused ||
          s.state == PlayerStateType.buffering,
    ),
  );
  final duration = ref.watch(nowPlayingDurationMsProvider);
  if (!control.seekable || !active || duration <= 0) return null;
  return (
    server: ref.watch(connectionSettingsProvider.select((s) => s.baseUrl)),
    renderer: ref.watch(
      playQueueStateStoreProvider.select((s) => s.currentRendererId),
    ),
    index: ref.watch(playerStateProvider.select((s) => s.index)),
    track: ref.watch(nowPlayingTrackProvider.select((t) => t?.id)),
    plugin: control.pluginId,
    duration: duration,
  );
});

/// libinput supplies press and release. Owning the repeat cadence also keeps
/// keyboards that send native repeat events from issuing duplicate seeks.
class KioskSeekKeys {
  KioskSeekKeys(this.ref) {
    ref.listenManual(_seekContext, (_, _) => reset());
  }
  final WidgetRef ref;
  Timer? _repeat;
  PhysicalKeyboardKey? _held;
  int _steps = 0;
  int? _target;
  int _sentAtMs = 0;

  void handle(KeyEvent event, {required bool forward}) {
    if (event is KeyUpEvent) {
      if (event.physicalKey == _held) _release();
      return;
    }
    if (event is! KeyDownEvent) return;
    _release();
    if (ref.read(_seekContext) == null) return;
    _held = event.physicalKey;
    _step(forward);
    if (_held == null) return;
    _repeat = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!HardwareKeyboard.instance.physicalKeysPressed.contains(_held)) {
        _release();
        return;
      }
      _step(forward);
    });
  }

  void _step(bool forward) {
    final context = ref.read(_seekContext);
    if (context == null || _held == null) {
      reset();
      return;
    }
    final now = ref.read(monotonicClockProvider).elapsedMilliseconds;
    final reported = ref
        .read(playbackTimeMsProvider)
        .clamp(0, context.duration);
    // Rapid taps and direction changes must accumulate even if the renderer
    // still reports the position before the last command.
    final pending = _target;
    final base =
        pending != null &&
            now - _sentAtMs < 2000 &&
            (reported - pending).abs() > 1000
        ? pending
        : reported;
    final seconds = switch (++_steps) {
      <= 3 => 5,
      <= 6 => 10,
      _ => 30,
    };
    final target = (base + (forward ? seconds : -seconds) * 1000).clamp(
      0,
      context.duration,
    );
    if (target != base) {
      _target = target;
      _sentAtMs = now;
      unawaited(
        ref
            .read(kalinkaWsApiProvider)
            .sendQueueCommand(QueueCommand.seek(positionMs: target))
            .catchError((Object error) {
              if (_target == target && _sentAtMs == now) reset();
            }),
      );
    }
    if (target == (forward ? context.duration : 0)) _release();
  }

  void _release() {
    _repeat?.cancel();
    _repeat = null;
    _held = null;
    _steps = 0;
  }

  void reset() {
    _release();
    _target = null;
  }
}
