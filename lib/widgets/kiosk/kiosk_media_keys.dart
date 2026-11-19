import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/kalinka_ws_api.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/connection_settings_provider.dart';
import '../../providers/connection_state_provider.dart';
import '../../providers/kalinka_ws_api_provider.dart';
import '../../providers/now_playing_provider.dart';
import '../../providers/renderer_provider.dart';
import '../../providers/volume_activity_provider.dart';
import '../../utils/flutter_pi_keyboard.dart';
import '../../utils/playback_utils.dart';
import 'kiosk_seek_keys.dart';

/// Handles dedicated media buttons before focus or a hidden control can
/// consume them. flutter-pi can give Play and Play/Pause the same XKB symbol,
/// but preserves the distinct physical Play/Pause key.
class KioskMediaKeys {
  KioskMediaKeys(this.ref);
  final WidgetRef ref;
  KioskSeekKeys? _seek;

  void cancelSeek() => _seek?.reset();

  bool handle(KeyEvent event) {
    final key = event.physicalKey == PhysicalKeyboardKey.mediaPlayPause
        ? LogicalKeyboardKey.mediaPlayPause
        : event.logicalKey;
    if (!kioskMediaKeys.containsValue(key)) return false;
    if (key == LogicalKeyboardKey.mediaRewind ||
        key == LogicalKeyboardKey.mediaFastForward) {
      (_seek ??= KioskSeekKeys(
        ref,
      )).handle(event, forward: key == LogicalKeyboardKey.mediaFastForward);
      return true;
    }
    if (ref.read(connectionStateProvider) != ConnectionStatus.connected) {
      return true;
    }
    if (key == LogicalKeyboardKey.audioVolumeUp ||
        key == LogicalKeyboardKey.audioVolumeDown) {
      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        ref
            .read(_volumeKeys.notifier)
            .step(key == LogicalKeyboardKey.audioVolumeUp ? 1 : -1);
      }
      return true;
    }
    if (event is! KeyDownEvent) return true;
    final transport = ref.read(transportStateProvider);
    final command = switch (key) {
      LogicalKeyboardKey.mediaTrackNext =>
        transport.canNext ? const QueueCommand.next() : null,
      LogicalKeyboardKey.mediaTrackPrevious =>
        transport.canPrev ? const QueueCommand.prev() : null,
      _ when transport.playPauseDisabled => null,
      _ => playPauseCommand(
        transport.playerState,
        exclusive: transport.exclusive,
        play: switch (key) {
          LogicalKeyboardKey.mediaPlay => true,
          LogicalKeyboardKey.mediaPause => false,
          _ => null,
        },
      ),
    };
    if (command != null) {
      ref.read(kalinkaWsApiProvider).sendQueueCommand(command);
    }
    return true;
  }
}

/// Relative keys need the last requested step while the renderer is still
/// echoing earlier commands. A different output or range starts from its own level.
final _volumeKeys = NotifierProvider<_VolumeKeys, int?>(_VolumeKeys.new);

class _VolumeKeys extends Notifier<int?> {
  Timer? _expiry;

  @override
  int? build() {
    ref.watch(connectionSettingsProvider.select((s) => s.baseUrl));
    ref.watch(connectionStateProvider);
    ref.watch(rendererListProvider.select((s) => s.active?.rendererId));
    ref.watch(volumeAvailableProvider);
    ref.watch(volumeStateProvider.select((v) => v.maxVolume));
    ref.listen(volumeStateProvider.select((v) => v.currentVolume), (_, level) {
      if (level == state) state = null;
    });
    ref.onDispose(() => _expiry?.cancel());
    return null;
  }

  void step(int delta) {
    if (!ref.read(volumeAvailableProvider)) return;
    final volume = ref.read(volumeStateProvider);
    final base = state ?? volume.currentVolume;
    final target = (base + delta).clamp(0, volume.maxVolume);
    ref
        .read(volumeActivityProvider.notifier)
        .showLevel(target, volume.maxVolume);
    if (target == base) return;
    state = target;
    _expiry?.cancel();
    final expiry = _expiry = Timer(
      const Duration(seconds: 1),
      () => state = null,
    );
    unawaited(
      ref
          .read(kalinkaWsApiProvider)
          .sendDeviceCommand(DeviceCommand.setVolume(volume: target))
          .catchError((Object error) {
            debugPrint('Kiosk volume request failed: $error');
            if (expiry.isActive && identical(expiry, _expiry)) {
              expiry.cancel();
              state = null;
            }
          }),
    );
  }
}
