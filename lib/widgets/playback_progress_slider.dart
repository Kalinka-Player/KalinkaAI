import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/kalinka_ws_api.dart';
import '../providers/app_state_provider.dart';
import '../providers/kalinka_ws_api_provider.dart';
import '../providers/playback_time_provider.dart';
import '../theme/app_theme.dart';
import '../utils/haptics.dart';
import '../utils/playback_utils.dart';

/// Playback progress slider with optimistic seeking while dragging.
class PlaybackProgressSlider extends ConsumerStatefulWidget {
  final int durationMs;

  /// When false (no track loaded), the slider is inactive — faded and not
  /// draggable.
  final bool enabled;

  const PlaybackProgressSlider({
    super.key,
    required this.durationMs,
    this.enabled = true,
  });

  @override
  ConsumerState<PlaybackProgressSlider> createState() =>
      _PlaybackProgressSliderState();
}

/// Drag-to-seek state shared by the progress bars. The thumb follows the
/// finger, then holds the target until the server's next event confirms the
/// seek, so it never snaps back to the old position first.
mixin OptimisticSeek<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool _isSeeking = false;
  double _seekProgress = 0.0;
  int? _seekBeforeSeq;
  double _lastHapticSeekPosition = -1.0;
  ProviderSubscription? _seqSubscription;

  int get seekDurationMs;

  bool get isSeeking => _isSeeking;

  /// Where the bar stands, 0–1: the drag target while seeking, playback
  /// otherwise.
  double seekAwareProgress(int playbackTimeMs) {
    if (_isSeeking) return _seekProgress;
    final durationMs = seekDurationMs;
    return durationMs > 0 ? (playbackTimeMs / durationMs).clamp(0.0, 1.0) : 0.0;
  }

  int seekAwarePositionMs(int playbackTimeMs) =>
      _isSeeking ? (_seekProgress * seekDurationMs).toInt() : playbackTimeMs;

  @override
  void initState() {
    super.initState();
    _seqSubscription = ref.listenManual<int>(
      playQueueStateStoreProvider.select((s) => s.seq),
      (prev, next) {
        if (_isSeeking && next != _seekBeforeSeq) {
          setState(() {
            _isSeeking = false;
            _seekBeforeSeq = null;
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _seqSubscription?.close();
    super.dispose();
  }

  void seekTo(double progress) {
    if (!_isSeeking) {
      KalinkaHaptics.mediumImpact();
      _lastHapticSeekPosition = progress;
    } else if ((progress - _lastHapticSeekPosition).abs() >= 0.05) {
      KalinkaHaptics.selectionClick();
      _lastHapticSeekPosition = progress;
    }
    setState(() {
      _isSeeking = true;
      _seekProgress = progress;
    });
  }

  void commitSeek(double progress) {
    KalinkaHaptics.lightImpact();
    setState(() {
      _seekProgress = progress;
      _seekBeforeSeq = ref.read(playQueueStateStoreProvider).seq;
    });
    ref
        .read(kalinkaWsApiProvider)
        .sendQueueCommand(
          QueueCommand.seek(positionMs: (progress * seekDurationMs).toInt()),
        );
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

    return RepaintBoundary(
      child: Opacity(
        opacity: widget.enabled ? 1.0 : 0.4,
        child: IgnorePointer(
          ignoring: !widget.enabled,
          child: Column(
            children: [
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14,
                  ),
                  activeTrackColor: KalinkaColors.accent,
                  inactiveTrackColor: KalinkaColors.borderDefault,
                  thumbColor: Colors.white,
                  overlayColor: KalinkaColors.accent.withValues(alpha: 0.25),
                ),
                // Disabled via the IgnorePointer above, never a null onChanged:
                // that restructures the Slider's semantics, which asserts in
                // flushSemantics if a dialog pops the same frame (Clear all).
                child: Slider(
                  value: progress,
                  onChanged: (value) {
                    if (widget.enabled) seekTo(value);
                  },
                  onChangeEnd: (value) {
                    if (widget.enabled) commitSeek(value);
                  },
                ),
              ),
              // SizedBox gives tight constraints (tight width from Column + fixed
              // height here), making the Row a Flutter relayout boundary. This
              // prevents RenderParagraph.markNeedsLayout() from propagating up
              // through the RepaintBoundary and causing a full-screen relayout on
              // every playback-time tick.
              SizedBox(
                width: double
                    .infinity, // combined with height → tight on both axes → relayout boundary
                height: 20,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        formatClock(Duration(milliseconds: positionMs)),
                        style: KalinkaTextStyles.timeLabel,
                      ),
                      Text(
                        formatClock(Duration(milliseconds: widget.durationMs)),
                        style: KalinkaTextStyles.timeLabel,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
