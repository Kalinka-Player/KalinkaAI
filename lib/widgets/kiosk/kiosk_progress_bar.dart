import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/playback_time_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/playback_utils.dart';
import '../playback_progress_slider.dart' show OptimisticSeek;

/// Full-width progress for a screen read from across the room: a thick bar,
/// elapsed and remaining time large above it, and a touch zone taller than
/// the bar so a fingertip finds it. Tap or drag anywhere along it to seek.
class KioskProgressBar extends ConsumerStatefulWidget {
  final int durationMs;
  final double scale;

  /// False while the display rests: the bar is still shown but takes no
  /// touches, so the tap that wakes the screen cannot seek.
  final bool interactive;

  const KioskProgressBar({
    super.key,
    required this.durationMs,
    required this.scale,
    this.interactive = true,
  });

  @override
  ConsumerState<KioskProgressBar> createState() => _KioskProgressBarState();
}

class _KioskProgressBarState extends ConsumerState<KioskProgressBar>
    with OptimisticSeek {
  double _dragFraction = 0;

  @override
  int get seekDurationMs => widget.durationMs;

  double _fractionAt(Offset local, double width) =>
      width > 0 ? (local.dx / width).clamp(0.0, 1.0) : 0.0;

  @override
  Widget build(BuildContext context) {
    double s(double v) => v * widget.scale;
    final playbackTimeMs = ref.watch(playbackTimeMsProvider);
    final positionMs = seekAwarePositionMs(playbackTimeMs);
    final progress = seekAwareProgress(playbackTimeMs);
    final durationMs = widget.durationMs;
    final canSeek = widget.interactive && durationMs > 0;
    final remainingMs = durationMs > 0 ? durationMs - positionMs : 0;

    final timeStyle = KalinkaFonts.mono(
      fontSize: s(17),
      fontWeight: FontWeight.w500,
      color: KalinkaColors.textPrimary,
    );

    final labels = SizedBox(
      // Fixed height keeps the per-second label change from relaying out
      // anything above.
      height: s(26),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            formatClock(Duration(milliseconds: positionMs)),
            style: isSeeking
                ? timeStyle.copyWith(color: KalinkaColors.accentTint)
                : timeStyle,
          ),
          Text(
            durationMs > 0
                ? '\u2212${formatClock(Duration(milliseconds: remainingMs))}'
                : '',
            style: timeStyle.copyWith(color: _remaining),
          ),
        ],
      ),
    );

    return RepaintBoundary(
      child: Semantics(
        label: 'Playback position',
        value:
            '${formatClock(Duration(milliseconds: positionMs))} of '
            '${formatClock(Duration(milliseconds: durationMs))}',
        slider: canSeek,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            // The labels are part of the touch zone: the bar is drawn thin
            // but is reached anywhere in the block.
            return IgnorePointer(
              ignoring: !canSeek,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) {
                  final f = _fractionAt(d.localPosition, width);
                  seekTo(f);
                  commitSeek(f);
                },
                onHorizontalDragStart: (d) {
                  _dragFraction = _fractionAt(d.localPosition, width);
                  seekTo(_dragFraction);
                },
                onHorizontalDragUpdate: (d) {
                  _dragFraction = _fractionAt(d.localPosition, width);
                  seekTo(_dragFraction);
                },
                onHorizontalDragEnd: (_) => commitSeek(_dragFraction),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    labels,
                    // Glides to each new second instead of stepping — a bar
                    // this long moves a visible distance per tick.
                    TweenAnimationBuilder<double>(
                      tween: Tween(end: progress),
                      duration: isSeeking
                          ? Duration.zero
                          : const Duration(milliseconds: 380),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, _) => CustomPaint(
                        size: Size(width, s(44)),
                        painter: _BarPainter(
                          progress: value,
                          thickness: s(isSeeking ? 10 : 6),
                          knobRadius: canSeek ? s(isSeeking ? 13 : 8) : 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

final _remaining = KalinkaColors.textPrimary.withValues(alpha: 0.74);

class _BarPainter extends CustomPainter {
  final double progress;
  final double thickness;
  final double knobRadius;

  _BarPainter({
    required this.progress,
    required this.thickness,
    required this.knobRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final radius = Radius.circular(thickness / 2);
    final track = Rect.fromLTWH(0, cy - thickness / 2, size.width, thickness);
    canvas.drawRRect(
      RRect.fromRectAndRadius(track, radius),
      Paint()..color = Colors.white.withValues(alpha: 0.14),
    );

    final head = size.width * progress;
    if (head > 0) {
      final fill = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, track.top, head, thickness),
        radius,
      );
      // Spans the whole track, so a colour marks a place in the song.
      final shader = KalinkaColors.progressGradient.createShader(track);
      canvas.drawRRect(
        fill,
        Paint()
          ..shader = shader
          ..color = Colors.white.withValues(alpha: 0.55)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, thickness),
      );
      canvas.drawRRect(fill, Paint()..shader = shader);
    }

    if (knobRadius > 0) {
      final inset = knobRadius.clamp(0.0, size.width / 2);
      final centre = Offset(head.clamp(inset, size.width - inset), cy);
      canvas.drawCircle(
        centre,
        knobRadius + 2,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(centre, knobRadius, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.progress != progress ||
      old.thickness != thickness ||
      old.knobRadius != knobRadius;
}
