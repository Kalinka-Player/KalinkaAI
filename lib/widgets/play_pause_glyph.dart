import 'package:flutter/material.dart';
import '../data_model/data_model.dart';
import '../theme/app_theme.dart';

/// Shared inner glyph for the white play/pause discs (mini player + now
/// playing): a spinner while buffering, the play/pause icon otherwise.
///
/// A failed track keeps the play glyph — the disc says what pressing it does,
/// and pressing it retries. The failure is reported where status belongs: the
/// queue's CAN'T PLAY label and the Now Playing metadata.
///
/// Sizes are parameterised because the mini player disc (46dp) and the
/// now-playing disc (68dp) render the same glyph at different scales.
class PlayPauseGlyph extends StatelessWidget {
  final PlayerStateType? playerState;

  /// Size of the play/pause icon.
  final double iconSize;

  /// Diameter of the buffering spinner.
  final double spinnerSize;

  /// Stroke width of the buffering spinner.
  final double spinnerStrokeWidth;

  /// Glyph and spinner colour — dark, for the white discs.
  final Color color;

  const PlayPauseGlyph({
    super.key,
    required this.playerState,
    required this.iconSize,
    required this.spinnerSize,
    this.spinnerStrokeWidth = 2.5,
    this.color = KalinkaColors.background,
  });

  @override
  Widget build(BuildContext context) {
    if (playerState == PlayerStateType.buffering) {
      return SizedBox(
        width: spinnerSize,
        height: spinnerSize,
        child: CircularProgressIndicator(
          strokeWidth: spinnerStrokeWidth,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      );
    }
    return Icon(
      playerState == PlayerStateType.playing
          ? Icons.pause_rounded
          : Icons.play_arrow_rounded,
      size: iconSize,
      color: color,
    );
  }
}
