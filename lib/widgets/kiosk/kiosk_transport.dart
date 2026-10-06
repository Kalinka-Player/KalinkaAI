import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/kalinka_ws_api.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/kalinka_ws_api_provider.dart';
import '../../providers/now_playing_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/playback_utils.dart';
import '../play_pause_glyph.dart';
import '../transport_button.dart';

/// Shuffle, previous, play/pause, next and repeat, sized for a room: a
/// fingertip at arm's length. Play/pause is a lit ring rather than the
/// full player's white disc, so it sits on the cover's colours without
/// outshining them.
class KioskTransport extends ConsumerWidget {
  final double scale;

  /// Skips a track, +1 next or -1 previous.
  final ValueChanged<int> onSkip;

  /// How far the row spreads; never narrower than its buttons.
  final double? width;

  const KioskTransport({
    super.key,
    required this.scale,
    required this.onSkip,
    this.width,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    double s(double v) => v * scale;
    final transport = ref.watch(transportStateProvider);
    final mode = ref.watch(playbackModeProvider);
    final api = ref.read(kalinkaWsApiProvider);

    Widget skip(bool enabled, IconData icon, int direction) => Opacity(
      opacity: enabled ? 1.0 : 0.35,
      child: TransportButton(
        hitDiameter: s(68),
        onTapDown: null,
        onTap: enabled ? () => onSkip(direction) : null,
        child: Icon(icon, size: s(52), color: KalinkaColors.textPrimary),
      ),
    );

    // Switches for whatever the queue plays next, so only while the queue
    // plays: a plugin's playback takes neither. Their places stay held, so
    // the row keeps its shape.
    Widget toggle(IconData icon, bool on, QueueCommand command) =>
        transport.exclusive
        ? SizedBox.square(dimension: s(56))
        : TransportButton(
            hitDiameter: s(56),
            onTapDown: null,
            onTap: () => api.sendQueueCommand(command),
            child: Icon(
              icon,
              size: s(32),
              color: on
                  ? KalinkaColors.accentTint
                  : KalinkaColors.textPrimary.withValues(alpha: 0.86),
            ),
          );

    final ring = s(96);
    final glow = s(14);
    return SizedBox(
      width: math.max(width ?? s(440), s(372)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          toggle(
            Icons.shuffle_rounded,
            mode.shuffle,
            QueueCommand.setPlaybackMode(
              shuffle: !mode.shuffle,
              repeatAll: mode.repeatAll,
              repeatSingle: mode.repeatSingle,
            ),
          ),
          skip(transport.canPrev, Icons.skip_previous_rounded, -1),
          Opacity(
            opacity: transport.hasTrack ? 1.0 : 0.35,
            // The glow spills past the ring, so the button is drawn larger
            // than the ring itself.
            child: TransportButton(
              hitDiameter: ring + 2 * glow,
              onTapDown: null,
              onTap: transport.playPauseDisabled
                  ? null
                  : () => sendPlayPauseCommand(
                      ref,
                      transport.playerState,
                      exclusive: transport.exclusive,
                    ),
              child: CustomPaint(
                size: Size.square(ring + 2 * glow),
                painter: _RingPainter(
                  radius: ring / 2,
                  stroke: s(2.5),
                  glow: glow,
                ),
                child: SizedBox.square(
                  dimension: ring + 2 * glow,
                  child: Center(
                    child: PlayPauseGlyph(
                      playerState: transport.playerState,
                      iconSize: s(56),
                      spinnerSize: s(40),
                      spinnerStrokeWidth: s(3.5),
                      color: KalinkaColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          skip(transport.canNext, Icons.skip_next_rounded, 1),
          toggle(
            mode.repeatSingle ? Icons.repeat_one_rounded : Icons.repeat_rounded,
            mode.repeatAll || mode.repeatSingle,
            // Off, all, one, off.
            QueueCommand.setPlaybackMode(
              shuffle: mode.shuffle,
              repeatAll: !mode.repeatAll && !mode.repeatSingle,
              repeatSingle: mode.repeatAll,
            ),
          ),
        ],
      ),
    );
  }
}

/// A thin ring in the accent, its glow drawn from the stroke so the inside
/// stays dark.
class _RingPainter extends CustomPainter {
  final double radius;
  final double stroke;
  final double glow;

  _RingPainter({
    required this.radius,
    required this.stroke,
    required this.glow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    canvas.drawCircle(
      centre,
      radius,
      Paint()..color = Colors.black.withValues(alpha: 0.22),
    );
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 2.5
        ..color = KalinkaColors.accent.withValues(alpha: 0.7)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, glow / 2.5),
    );
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = KalinkaColors.accentTint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.radius != radius || old.stroke != stroke || old.glow != glow;
}
