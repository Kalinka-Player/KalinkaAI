import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart' show DeviceVolume;
import '../data_model/kalinka_ws_api.dart';
import '../providers/app_state_provider.dart';
import '../providers/kalinka_ws_api_provider.dart';
import '../providers/volume_activity_provider.dart';
import '../theme/app_theme.dart';
import '../utils/haptics.dart';

class NowPlayingVolumeControl extends ConsumerStatefulWidget {
  const NowPlayingVolumeControl({super.key});

  @override
  ConsumerState<NowPlayingVolumeControl> createState() =>
      _NowPlayingVolumeControlState();
}

/// Volume-drag state shared by the volume controls. Mirrors the device's
/// volume and sends the dragged level as it moves. After release it holds the
/// level until the device reports it and the echoes of the drag's intermediate
/// levels stop arriving, so the control never replays them on its way back.
mixin OptimisticVolume<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  static const _settleQuiet = Duration(milliseconds: 300);
  static const _settleCap = Duration(seconds: 5);

  bool _isAdjustingVolume = false;
  double _localVolumeProgress = 0.0;
  double _lastHapticVolumePosition = -1.0;
  int? _settleTarget;
  Timer? _settleQuietTimer;
  Timer? _settleCapTimer;

  // Mirrored provider state. Populated via post-frame subscriptions rather than
  // read in build: this widget mounts inside a parent's build, where reading the
  // device-state graph cold-flushes it and schedules a provider refresh mid-build
  // (setState-during-build crash). A post-frame flush runs between frames safely.
  DeviceVolume _volumeState = DeviceVolume.empty;
  bool _volumeAvailable = false;
  ProviderSubscription? _volumeSub;
  ProviderSubscription? _availableSub;
  ProviderSubscription? _keySub;

  DeviceVolume get volume => _volumeState;

  /// Whether there is a volume to control at all; see [volumeAvailableProvider].
  bool get volumeAvailable => _volumeAvailable;

  bool get isAdjustingVolume => _isAdjustingVolume;

  /// Where the control stands, 0–1: the dragged level while adjusting.
  double get volumeProgress {
    if (_isAdjustingVolume) return _localVolumeProgress;
    final v = _volumeState;
    return v.maxVolume > 0
        ? (v.currentVolume / v.maxVolume).clamp(0.0, 1.0)
        : 0.0;
  }

  /// The device's volume moved, by this control or anyone else's.
  void onVolumeChanged(DeviceVolume previous, DeviceVolume next) {}

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _volumeSub = ref.listenManual(volumeStateProvider, (prev, next) {
        final previous = _volumeState;
        setState(() => _volumeState = next);
        if (_settleTarget != null) _checkSettled();
        if (prev != null) onVolumeChanged(previous, next);
      }, fireImmediately: true);
      _availableSub = ref.listenManual(
        volumeAvailableProvider,
        (_, next) => setState(() => _volumeAvailable = next),
        fireImmediately: true,
      );
      // Hardware keys are sent natively; show their level without waiting
      // for the server's echo. A drag in progress keeps the thumb.
      _keySub = ref.listenManual(volumeActivityProvider, (_, next) {
        final level = next?.level, max = next?.max;
        if (level == null || max == null || max <= 0) return;
        if (_isAdjustingVolume && _settleTarget == null) return;
        _holdVolume(level, level / max);
      });
    });
  }

  @override
  void dispose() {
    _settleQuietTimer?.cancel();
    _settleCapTimer?.cancel();
    _volumeSub?.close();
    _availableSub?.close();
    _keySub?.close();
    super.dispose();
  }

  /// Hardware mixers quantize, so the reported level can miss by a step.
  bool _nearTarget(int reported) {
    final tolerance = math.max(1, (_volumeState.maxVolume * 0.02).round());
    return (reported - _settleTarget!).abs() <= tolerance;
  }

  // Releases once the level has been at the target for [_settleQuiet]; any
  // echo from the backlog away from it restarts the wait.
  void _checkSettled() {
    _settleQuietTimer?.cancel();
    if (_nearTarget(_volumeState.currentVolume)) {
      _settleQuietTimer = Timer(_settleQuiet, _releaseVolume);
    }
  }

  void _releaseVolume() {
    _settleQuietTimer?.cancel();
    _settleCapTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _isAdjustingVolume = false;
      _settleTarget = null;
    });
  }

  void _sendVolume(int volume) {
    ref
        .read(kalinkaWsApiProvider)
        .sendDeviceCommand(DeviceCommand.setVolume(volume: volume));
  }

  void adjustVolume(double value) {
    if (!_isAdjustingVolume || _settleTarget != null) {
      _lastHapticVolumePosition = value;
    } else if ((value - _lastHapticVolumePosition).abs() >= 0.10) {
      KalinkaHaptics.selectionClick();
      _lastHapticVolumePosition = value;
    }

    _settleQuietTimer?.cancel();
    _settleCapTimer?.cancel();
    setState(() {
      _isAdjustingVolume = true;
      _settleTarget = null;
      _localVolumeProgress = value;
    });
    _sendVolume((value * _volumeState.maxVolume).round());
  }

  void commitVolume(double value) {
    final target = (value * _volumeState.maxVolume).round();
    _sendVolume(target);
    _lastHapticVolumePosition = -1.0;
    _holdVolume(target, value);
  }

  void _holdVolume(int target, double progress) {
    setState(() {
      _isAdjustingVolume = true;
      _localVolumeProgress = progress.clamp(0.0, 1.0);
      _settleTarget = target;
    });
    // A level the device never reaches (clamped, or refused) must not hold
    // the control forever.
    _settleCapTimer?.cancel();
    _settleCapTimer = Timer(_settleCap, _releaseVolume);
    // Only an exact match needs no echo; the tolerance is for echoes, else a
    // one-step key press would release before its echo and snap back.
    _settleQuietTimer?.cancel();
    if (_volumeState.currentVolume == target) {
      _settleQuietTimer = Timer(_settleQuiet, _releaseVolume);
    }
  }
}

class _NowPlayingVolumeControlState
    extends ConsumerState<NowPlayingVolumeControl>
    with OptimisticVolume {
  @override
  Widget build(BuildContext context) {
    if (!volumeAvailable) return const SizedBox.shrink();

    return RepaintBoundary(
      child: Row(
        children: [
          const Icon(
            Icons.volume_down,
            size: 20,
            color: KalinkaColors.textSecondary,
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: KalinkaColors.textPrimary,
                inactiveTrackColor: KalinkaColors.borderDefault,
                thumbColor: KalinkaColors.textPrimary,
                overlayColor: KalinkaColors.textPrimary.withValues(alpha: 0.1),
              ),
              child: Slider(
                value: volumeProgress,
                onChanged: adjustVolume,
                onChangeEnd: commitVolume,
              ),
            ),
          ),
          const Icon(
            Icons.volume_up,
            size: 20,
            color: KalinkaColors.textSecondary,
          ),
        ],
      ),
    );
  }
}
