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
  Shadow(color: Color(0x59000000), offset: Offset(0, 1)),
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

  /// In landscape, share the available height evenly between the visible
  /// rows. The parent bounds this area between Now Playing and the progress bar.
  final bool spreadVertically;

  /// Move the incoming block as one opaque layer on a local display.
  final bool slideTogether;

  const KioskTrackText({
    super.key,
    required this.lines,
    required this.scale,
    this.centred = false,
    this.compact = false,
    this.spreadVertically = false,
    this.slideTogether = false,
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
    _leaving = widget.slideTogether ? null : old.lines;
    _controller.duration = Duration(
      milliseconds: widget.slideTogether ? 300 : 1100,
    );
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.slideTogether) {
      return RepaintBoundary(
        child: ClipRect(
          child: AnimatedBuilder(
            animation: _controller,
            child: RepaintBoundary(child: _block(widget.lines, leaving: false)),
            builder: (context, child) => Transform.translate(
              offset: Offset(
                0,
                (1 - Curves.easeOutCubic.transform(_controller.value)) *
                    12 *
                    widget.scale,
              ),
              child: child,
            ),
          ),
        ),
      );
    }
    final leaving = _leaving;
    // Only the arriving lines size the block. Each row keeps its text and
    // badges mounted while its opacity and position change.
    return Stack(
      clipBehavior: Clip.none,
      alignment: widget.centred ? Alignment.topCenter : Alignment.topLeft,
      children: [
        if (leaving != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            bottom: widget.spreadVertically ? 0 : null,
            child: _block(leaving, leaving: true),
          ),
        _block(widget.lines, leaving: false),
      ],
    );
  }

  Widget _block(KioskTrackLines lines, {required bool leaving}) {
    double s(double v) => v * widget.scale;
    final compact = widget.compact;
    final spread = widget.spreadVertically;
    final minimumGap = spread ? s(8) : 0.0;
    final lineGap = compact || spread ? 0.0 : s(6);
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
        padding: EdgeInsets.only(top: lineGap),
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
          padding: EdgeInsets.only(top: lineGap),
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
          padding: EdgeInsets.only(top: spread ? 0 : s(compact ? 8 : 10)),
          child: _StreamRow(
            lines: lines,
            // Kept legible however small the title gets.
            scale: compact ? math.max(widget.scale * 0.46, 0.72) : widget.scale,
            shadows: shadows,
            showBitPerfect: !leaving,
          ),
        ),
    ];

    final column = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: spread
          ? MainAxisAlignment.spaceEvenly
          : MainAxisAlignment.start,
      spacing: minimumGap,
      crossAxisAlignment: widget.centred
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: widget.slideTogether
          ? rows
          : [
              for (final (i, row) in rows.indexed)
                _Staged(
                  animation: _controller,
                  interval: leaving
                      ? const Interval(0, 0.3, curve: Curves.easeInCubic)
                      : Interval(
                          0.22 + i * 0.09,
                          0.64 + i * 0.09,
                          curve: Curves.easeOutCubic,
                        ),
                  leaving: leaving,
                  rise: s(18),
                  child: row,
                ),
            ],
    );
    if (!spread) return column;

    // The same minimum gap goes before, between and after visible rows.
    // If a wrapped title or large text exhausts the space, fit the text
    // independently of the controls and of the other track during a switch.
    return LayoutBuilder(
      builder: (context, box) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topLeft,
        child: Container(
          width: box.maxWidth,
          constraints: BoxConstraints(minHeight: box.maxHeight),
          padding: EdgeInsets.symmetric(vertical: minimumGap),
          child: column,
        ),
      ),
    );
  }
}

class _Staged extends AnimatedWidget {
  final Interval interval;
  final bool leaving;
  final double rise;
  final Widget child;

  const _Staged({
    required Animation<double> animation,
    required this.interval,
    required this.leaving,
    required this.rise,
    required this.child,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    final progress = interval.transform(
      (listenable as Animation<double>).value,
    );
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
