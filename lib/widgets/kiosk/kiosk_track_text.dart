import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../bit_perfect_badge.dart';
import '../source_badge.dart' show SourceTile;

// Brighter than the app's secondary greys: these lines sit on the cover's
// colours, not on near-black.
final _artist = KalinkaColors.textPrimary.withValues(alpha: 0.78);
final _album = KalinkaColors.textPrimary.withValues(alpha: 0.7);
final _stream = KalinkaColors.textPrimary.withValues(alpha: 0.82);

/// The only shadow text laid over a cover wears: a hairline of shade, as
/// polish. The contrast itself comes from the shade over the cover.
const kioskTextPolish = [
  Shadow(color: Color(0x59000000), offset: Offset(0, 1), blurRadius: 3),
];

/// What the display says about a track.
@immutable
class KioskTrackLines {
  final String trackId;
  final String title;
  final String artist;
  final String? album;

  /// Where the stream comes from and what it is, as the player says it:
  /// `Qobuz · FLAC 24-bit • 96 kHz`.
  final String? stream;

  /// The source whose tile leads [stream], where the player shows its badge.
  final String? source;

  const KioskTrackLines({
    required this.trackId,
    required this.title,
    required this.artist,
    this.album,
    this.stream,
    this.source,
  });

  @override
  bool operator ==(Object other) =>
      other is KioskTrackLines &&
      other.trackId == trackId &&
      other.title == title &&
      other.artist == artist &&
      other.album == album &&
      other.stream == stream &&
      other.source == source;

  @override
  int get hashCode =>
      Object.hash(trackId, title, artist, album, stream, source);
}

/// The display's eyebrow over the track: `NOW PLAYING`, spaced out in the
/// accent.
class KioskEyebrow extends StatelessWidget {
  final double scale;

  const KioskEyebrow({super.key, required this.scale});

  @override
  Widget build(BuildContext context) {
    return Text(
      'NOW PLAYING',
      style: KalinkaFonts.mono(
        fontSize: 14 * scale,
        fontWeight: FontWeight.w600,
        letterSpacing: 4.5 * scale,
        color: KalinkaColors.accentTint,
        height: 1.2,
      ),
    );
  }
}

/// Title, artist, album and stream, changing over line by line: the old
/// lines lift away, then the new ones rise in one after another. A change
/// within the same track (the stream's format arriving) just updates.
class KioskTrackText extends StatefulWidget {
  final KioskTrackLines lines;
  final double scale;
  final bool centred;

  /// Laid over the cover on a small screen: the artist and album keep
  /// nearer the title's size, and the title keeps to a line.
  final bool compact;

  const KioskTrackText({
    super.key,
    required this.lines,
    required this.scale,
    this.centred = false,
    this.compact = false,
  });

  @override
  State<KioskTrackText> createState() => _KioskTrackTextState();
}

class _KioskTrackTextState extends State<KioskTrackText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
    value: 1,
  )..addStatusListener(_onStatus);
  KioskTrackLines? _leaving;

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _leaving != null) {
      setState(() => _leaving = null);
    }
  }

  @override
  void didUpdateWidget(KioskTrackText old) {
    super.didUpdateWidget(old);
    if (old.lines.trackId == widget.lines.trackId) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _leaving = null;
      _controller.value = 1;
      return;
    }
    _leaving = old.lines;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final leaving = _leaving;
    return AnimatedBuilder(
      animation: _controller,
      // The leaving lines are positioned so only the arriving ones size the
      // block — its height settles at the switch, not when they vanish.
      builder: (context, _) => Stack(
        clipBehavior: Clip.none,
        alignment: widget.centred ? Alignment.topCenter : Alignment.topLeft,
        children: [
          if (leaving != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _block(leaving, leaving: true),
            ),
          _block(widget.lines, leaving: false),
        ],
      ),
    );
  }

  Widget _block(KioskTrackLines lines, {required bool leaving}) {
    double s(double v) => v * widget.scale;
    final compact = widget.compact;
    final align = widget.centred ? TextAlign.center : TextAlign.start;
    // Over a cover that fills the screen.
    final shadows = compact ? kioskTextPolish : null;
    final rows = <Widget>[
      Text(
        lines.title,
        style: KalinkaFonts.display(
          fontSize: s(compact ? 26 : 54),
          fontWeight: FontWeight.w500,
          color: KalinkaColors.frost,
          height: compact ? 1.05 : 1.1,
        ).copyWith(shadows: shadows),
        textAlign: align,
        maxLines: compact ? 1 : 2,
        overflow: TextOverflow.ellipsis,
      ),
      Padding(
        padding: EdgeInsets.only(top: compact ? 0 : s(6)),
        child: Text(
          lines.artist,
          style: KalinkaFonts.sans(
            fontSize: s(compact ? 19 : 30),
            fontWeight: FontWeight.w500,
            color: _artist,
            height: 1.2,
          ).copyWith(shadows: shadows),
          textAlign: align,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      if (lines.album != null)
        Padding(
          padding: EdgeInsets.only(top: compact ? 0 : s(6)),
          child: Text(
            lines.album!,
            style: KalinkaFonts.sans(
              fontSize: s(compact ? 15 : 21),
              color: _album,
              height: 1.25,
            ).copyWith(shadows: shadows),
            textAlign: align,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      if (lines.stream != null)
        Padding(
          padding: EdgeInsets.only(top: s(compact ? 8 : 10)),
          child: _StreamRow(
            lines: lines,
            // Kept legible however small the title gets.
            scale: compact ? math.max(widget.scale * 0.46, 0.72) : widget.scale,
            shadows: shadows,
            showBitPerfect: !leaving,
          ),
        ),
    ];

    final t = _controller.value;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: widget.centred
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        for (final (i, row) in rows.indexed)
          _Staged(
            progress: leaving
                ? Curves.easeInCubic.transform(
                    const Interval(0, 0.3).transform(t),
                  )
                : Curves.easeOutCubic.transform(
                    Interval(0.22 + i * 0.09, 0.64 + i * 0.09).transform(t),
                  ),
            leaving: leaving,
            rise: s(18),
            child: row,
          ),
      ],
    );
  }
}

class _Staged extends StatelessWidget {
  final double progress;
  final bool leaving;
  final double rise;
  final Widget child;

  const _Staged({
    required this.progress,
    required this.leaving,
    required this.rise,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!leaving && progress == 1) return child;
    return Opacity(
      opacity: leaving ? 1 - progress : progress,
      child: Transform.translate(
        offset: Offset(
          0,
          leaving ? -progress * rise * 0.7 : (1 - progress) * rise,
        ),
        child: child,
      ),
    );
  }
}

/// The player's stream line: the source's tile, `Qobuz · FLAC 24-bit • 96
/// kHz`, and the bit-perfect badge after it.
class _StreamRow extends StatelessWidget {
  final KioskTrackLines lines;
  final double scale;
  final List<Shadow>? shadows;

  /// Off for the lines on their way out: the badge watches live state, which
  /// already describes the newcomer.
  final bool showBitPerfect;

  const _StreamRow({
    required this.lines,
    required this.scale,
    required this.shadows,
    required this.showBitPerfect,
  });

  @override
  Widget build(BuildContext context) {
    double s(double v) => v * scale;
    final source = lines.source;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (source != null) ...[
          SourceTile(source: source, size: s(20)),
          SizedBox(width: s(6)),
        ],
        Flexible(
          child: Text(
            lines.stream!,
            style: KalinkaFonts.mono(
              fontSize: s(14),
              letterSpacing: s(0.3),
              color: _stream,
              height: 1.2,
            ).copyWith(shadows: shadows),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (showBitPerfect) BitPerfectBadge(scale: scale),
      ],
    );
  }
}
