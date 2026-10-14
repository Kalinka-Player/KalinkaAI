import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart';
import '../providers/app_state_provider.dart';
import '../theme/app_theme.dart';

/// Three bars beside a row's duration: the sign that this row is the track
/// in the player. They move while it plays and stand still while it does
/// not, so the row says what the player is doing, not only which track it
/// holds.
///
/// Stepped at ten frames a second on a timer rather than run off a ticker:
/// Flutter rasterises the whole window for every frame it produces, and a
/// ticker asks for one at every refresh — a third of a desktop core for
/// twelve pixels. Only the current row carries it, so one timer runs, and it
/// repaints inside its own boundary.
class NowPlayingBars extends ConsumerStatefulWidget {
  final double size;

  const NowPlayingBars({super.key, this.size = 12});

  @override
  ConsumerState<NowPlayingBars> createState() => _NowPlayingBarsState();
}

class _NowPlayingBarsState extends ConsumerState<NowPlayingBars> {
  static const _frame = Duration(milliseconds: 100);

  /// Which frame of the loop is showing; the painter listens to it.
  final _step = ValueNotifier<int>(0);
  Timer? _timer;

  void _run(bool moving) {
    if (moving && _timer == null) {
      _timer = Timer.periodic(_frame, (_) => _step.value++);
    } else if (!moving && _timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _step.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playing = ref.watch(
      playerStateProvider.select((s) => s.state == PlayerStateType.playing),
    );
    final moving = playing && !MediaQuery.disableAnimationsOf(context);
    _run(moving);
    return Semantics(
      label: playing ? 'Now playing' : 'Now playing, paused',
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: NowPlayingBarsPainter(
            step: _step,
            moving: moving,
            color: KalinkaColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Three bottom-aligned bars, each on its own pace and phase so they never
/// move in step; whole cycles per loop, so it wraps cleanly. Still, they
/// rest at unequal heights.
@visibleForTesting
class NowPlayingBarsPainter extends CustomPainter {
  /// Frames per loop: 1.4 s at ten a second.
  static const framesPerLoop = 14;

  final ValueListenable<int> step;
  final bool moving;
  final Color color;

  NowPlayingBarsPainter({
    required this.step,
    required this.moving,
    required this.color,
  }) : super(repaint: step);

  static const _still = [0.4, 0.7, 0.5];
  static const _cycles = [2, 3, 2];
  static const _phase = [0.0, 0.3, 0.65];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final barWidth = size.width / 5;
    final radius = Radius.circular(barWidth / 2);
    final t = (step.value % framesPerLoop) / framesPerLoop;
    for (var i = 0; i < 3; i++) {
      final double fraction;
      if (moving) {
        final wave = math.sin(2 * math.pi * (_cycles[i] * t + _phase[i]));
        fraction = 0.25 + 0.75 * (0.5 + 0.5 * wave);
      } else {
        fraction = _still[i];
      }
      final height = math.max(barWidth, size.height * fraction);
      final left = i * 2 * barWidth;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, size.height - height, barWidth, height),
          radius,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(NowPlayingBarsPainter old) =>
      old.moving != moving || old.color != color || old.step != step;
}
