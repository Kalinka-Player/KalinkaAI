import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart' show PlaybackControl, PlayerStateType;
import '../data_model/kalinka_ws_api.dart';
import '../data_model/playqueue_events.dart' show PlayQueueState;
import '../providers/app_state_provider.dart';
import '../providers/connection_state_provider.dart';
import '../providers/kalinka_ws_api_provider.dart';
import '../providers/monotonic_clock_provider.dart';
import '../providers/playback_time_provider.dart';
import '../theme/app_theme.dart';
import '../utils/haptics.dart';
import '../utils/playback_utils.dart';
import 'gradient_progress_line.dart';

const _trackHeight = 3.0;
const _overlayRadius = 14.0;

/// Playback progress slider with optimistic seeking while dragging. While the
/// playback cannot seek, the bar is drawn grey and without a thumb, and the
/// times stay readable. While the server is away, the mini-player's
/// reconnecting line stands in for the bar.
class PlaybackProgressSlider extends ConsumerStatefulWidget {
  final int durationMs;

  /// When false (no track loaded), the slider is inactive — faded and not
  /// draggable.
  final bool enabled;

  /// Times either side of the bar on one line, for the wide mini-player,
  /// rather than under it.
  final bool inline;

  const PlaybackProgressSlider({
    super.key,
    required this.durationMs,
    this.enabled = true,
    this.inline = false,
  });

  @override
  ConsumerState<PlaybackProgressSlider> createState() =>
      _PlaybackProgressSliderState();
}

typedef _SeekContext = ({
  String? trackId,
  String? rendererId,
  PlaybackControl control,
});

_SeekContext _seekContext(PlayQueueState state) => (
  trackId: state.playbackState.currentTrack?.id,
  rendererId: state.currentRendererId,
  control: state.playbackControl,
);

/// The finger owns the thumb during a drag. After release, only a fresh
/// playback position near the requested target confirms the seek; a queue
/// edit, renderer-list update, or tick at the old position is not an ack.
mixin OptimisticSeek<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool _dragging = false;
  double _seekProgress = 0.0;
  int? _pendingTargetMs;
  int? _seekBeforeSeq;
  int _seekSentAtMs = 0;
  int _seekGeneration = 0;
  _SeekContext? _context;
  Timer? _seekTimeout;
  double _lastHapticSeekPosition = -1.0;
  ProviderSubscription? _queueSubscription;
  ProviderSubscription? _connectionSubscription;

  int get seekDurationMs;

  bool get isSeeking => _dragging || _pendingTargetMs != null;

  /// Where the bar stands, 0–1: the drag target while seeking, playback
  /// otherwise.
  double seekAwareProgress(int playbackTimeMs) {
    if (_dragging) return _seekProgress;
    final durationMs = seekDurationMs;
    return durationMs > 0
        ? (seekAwarePositionMs(playbackTimeMs) / durationMs).clamp(0.0, 1.0)
        : 0.0;
  }

  int seekAwarePositionMs(int playbackTimeMs) => _dragging
      ? (_seekProgress * seekDurationMs).toInt()
      : _pendingTargetMs ?? playbackTimeMs;

  @override
  void initState() {
    super.initState();
    _queueSubscription = ref.listenManual<PlayQueueState>(
      playQueueStateStoreProvider,
      (prev, next) {
        if (!isSeeking) return;
        final playback = next.playbackState;
        if (_seekContext(next) != _context ||
            playback.state == PlayerStateType.stopped ||
            playback.state == PlayerStateType.error) {
          cancelSeek();
          return;
        }
        final target = _pendingTargetMs;
        if (_dragging || target == null || next.seq <= _seekBeforeSeq!) return;
        if (identical(prev?.playbackState, playback)) return;
        final position = playback.position;
        if (position == null) return;

        // Allow coarse renderer timestamps and playback that advanced while
        // the command travelled. Interpolated UI ticks cannot confirm a seek.
        final elapsed = playback.state == PlayerStateType.playing
            ? (ref.read(monotonicClockProvider).elapsedMilliseconds -
                      _seekSentAtMs)
                  .clamp(0, 5000)
            : 0;
        if (position >= target - 1000 && position <= target + elapsed + 1000) {
          cancelSeek();
        }
      },
    );
    _connectionSubscription = ref.listenManual<bool>(
      connectionStateProvider.select((s) => s.isInterrupted),
      (_, interrupted) {
        if (interrupted && isSeeking) cancelSeek();
      },
    );
  }

  @override
  void dispose() {
    _seekTimeout?.cancel();
    _queueSubscription?.close();
    _connectionSubscription?.close();
    super.dispose();
  }

  void beginSeek(double progress) {
    if (seekDurationMs <= 0 ||
        !ref.read(playbackControlProvider).seekable ||
        ref.read(connectionStateProvider).isInterrupted) {
      return;
    }
    _seekTimeout?.cancel();
    _seekGeneration++;
    _context = _seekContext(ref.read(playQueueStateStoreProvider));
    _pendingTargetMs = null;
    _seekBeforeSeq = null;
    _dragging = true;
    _lastHapticSeekPosition = progress;
    seekTo(progress);
  }

  void seekTo(double progress) {
    // A track/output change cancels the current gesture. Its remaining move
    // and release callbacks must not seek the new track.
    if (!_dragging) return;
    if ((progress - _lastHapticSeekPosition).abs() >= 0.05) {
      KalinkaHaptics.selectionClick();
      _lastHapticSeekPosition = progress;
    }
    setState(() {
      _seekProgress = progress.clamp(0.0, 1.0);
    });
  }

  void commitSeek(double progress) {
    if (!_dragging) return;
    final target = (progress.clamp(0.0, 1.0) * seekDurationMs).toInt();
    KalinkaHaptics.lightImpact();
    setState(() {
      _dragging = false;
      _pendingTargetMs = target;
      _seekBeforeSeq = ref.read(playQueueStateStoreProvider).seq;
      _seekSentAtMs = ref.read(monotonicClockProvider).elapsedMilliseconds;
    });
    // WS sends have no seek acknowledgement or rejection response. A refused
    // or lost command must eventually return the UI to the reported position.
    _seekTimeout = Timer(const Duration(seconds: 5), cancelSeek);
    unawaited(_sendSeek(target, _seekGeneration));
  }

  Future<void> _sendSeek(int target, int generation) async {
    try {
      await ref
          .read(kalinkaWsApiProvider)
          .sendQueueCommand(QueueCommand.seek(positionMs: target));
    } catch (_) {
      if (mounted && generation == _seekGeneration) cancelSeek();
    }
  }

  void cancelSeek() {
    _seekTimeout?.cancel();
    _seekGeneration++;
    setState(() {
      _dragging = false;
      _pendingTargetMs = null;
      _seekBeforeSeq = null;
      _context = null;
    });
  }
}

class _PlaybackProgressSliderState extends ConsumerState<PlaybackProgressSlider>
    with OptimisticSeek {
  @override
  int get seekDurationMs => widget.durationMs;

  @override
  Widget build(BuildContext context) {
    final playbackTimeMs = ref.watch(playbackTimeMsProvider);
    final positionMs = seekAwarePositionMs(playbackTimeMs);
    final progress = seekAwareProgress(playbackTimeMs);
    final seekable = ref.watch(
      playbackControlProvider.select((c) => c.seekable),
    );
    final lineMode = ref.watch(
      connectionStateProvider.select(progressLineModeFor),
    );
    final away = lineMode != GradientProgressLineMode.normal;
    final interactive = widget.enabled && seekable && !away;

    return RepaintBoundary(
      child: Opacity(
        opacity: widget.enabled ? 1.0 : 0.4,
        child: IgnorePointer(
          ignoring: !interactive,
          child: _layout(
            bar: Stack(
              alignment: Alignment.center,
              children: [
                // Hidden, not removed, so the row keeps its height and the
                // slider's semantics their shape.
                Visibility.maintain(
                  visible: !away,
                  child: ExcludeFocus(
                    excluding: away,
                    child: SliderTheme(
                      data: SliderThemeData(
                        mouseCursor: WidgetStateMouseCursor.clickable,
                        trackHeight: _trackHeight,
                        thumbShape: seekable
                            ? const RoundSliderThumbShape(enabledThumbRadius: 6)
                            : SliderComponentShape.noThumb,
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: _overlayRadius,
                        ),
                        activeTrackColor: seekable
                            ? KalinkaColors.accent
                            : KalinkaColors.textMuted,
                        inactiveTrackColor: KalinkaColors.borderDefault,
                        thumbColor: Colors.white,
                        overlayColor: KalinkaColors.accent.withValues(
                          alpha: 0.25,
                        ),
                      ),
                      // Disabled via the IgnorePointer above, never a null
                      // onChanged: that restructures the Slider's semantics,
                      // which asserts in flushSemantics if a dialog pops the
                      // same frame (Clear all).
                      child: Slider(
                        value: progress,
                        onChangeStart: (value) {
                          if (interactive) beginSeek(value);
                        },
                        onChanged: (value) {
                          if (interactive) seekTo(value);
                        },
                        onChangeEnd: (value) {
                          if (interactive) commitSeek(value);
                        },
                      ),
                    ),
                  ),
                ),
                // The slider insets its track by the overlay radius.
                if (away)
                  Positioned(
                    left: _overlayRadius,
                    right: _overlayRadius,
                    child: GradientProgressLine(
                      progress: progress,
                      mode: lineMode,
                      height: _trackHeight,
                    ),
                  ),
              ],
            ),
            position: Text(
              formatClock(Duration(milliseconds: positionMs)),
              style: KalinkaTextStyles.timeLabel,
            ),
            duration: Text(
              formatClock(Duration(milliseconds: widget.durationMs)),
              style: KalinkaTextStyles.timeLabel,
            ),
          ),
        ),
      ),
    );
  }

  Widget _layout({
    required Widget bar,
    required Widget position,
    required Widget duration,
  }) {
    if (widget.inline) {
      return Row(
        children: [
          SizedBox(
            width: 44,
            child: Align(alignment: Alignment.centerRight, child: position),
          ),
          Expanded(child: bar),
          SizedBox(width: 44, child: duration),
        ],
      );
    }
    return Column(
      children: [
        bar,
        // SizedBox gives tight constraints (tight width from Column + fixed
        // height for the current text scale), making the Row a Flutter relayout
        // boundary. This prevents RenderParagraph.markNeedsLayout() from propagating up
        // through the RepaintBoundary and causing a full-screen relayout on
        // every playback-time tick.
        SizedBox(
          width: double.infinity,
          height:
              (MediaQuery.textScalerOf(context)
                          .scale(KalinkaTextStyles.timeLabel.fontSize!) *
                      1.5)
                  .clamp(20.0, double.infinity),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [position, duration],
            ),
          ),
        ),
      ],
    );
  }
}
