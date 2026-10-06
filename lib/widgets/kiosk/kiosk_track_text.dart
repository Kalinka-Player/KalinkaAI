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

  /// The stream's format and resolution — `FLAC 24-bit 96 kHz`.
  final String? format;

  /// The source the track comes from, and the name it goes by.
  final String? source;
  final String? sourceTitle;

  const KioskTrackLines({
    required this.trackId,
    required this.title,
    required this.artist,
    this.album,
    this.format,
    this.source,
    this.sourceTitle,
  });

  @override
  bool operator ==(Object other) =>
      other is KioskTrackLines &&
      other.trackId == trackId &&
      other.title == title &&
      other.artist == artist &&
      other.album == album &&
      other.format == format &&
      other.source == source &&
      other.sourceTitle == sourceTitle;

  @override
  int get hashCode =>
      Object.hash(trackId, title, artist, album, format, source, sourceTitle);
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
          style: KalinkaFonts.display(
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
      if (lines.format != null || lines.sourceTitle != null)
        Padding(
          padding: EdgeInsets.only(top: s(compact ? 8 : 20)),
          child: _StreamRow(
            lines: lines,
            // Kept legible however small the title gets.
            scale: compact ? math.max(widget.scale * 0.46, 0.72) : widget.scale,
            centred: widget.centred,
            sourceFirst: compact,
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

/// The stream's format in an outlined tag, and where it comes from: the
/// source's tile and name. Short of width, the second moves to a line of its
/// own.
class _StreamRow extends StatelessWidget {
  final KioskTrackLines lines;
  final double scale;
  final bool centred;

  /// The source first, its tile and name in one tag of their own, as over a
  /// cover that fills the screen.
  final bool sourceFirst;

  /// Off for the lines on their way out: the badge watches live state, which
  /// already describes the newcomer.
  final bool showBitPerfect;

  const _StreamRow({
    required this.lines,
    required this.scale,
    required this.centred,
    required this.sourceFirst,
    required this.showBitPerfect,
  });

  @override
  Widget build(BuildContext context) {
    double s(double v) => v * scale;
    final style = KalinkaFonts.mono(
      fontSize: s(14),
      letterSpacing: s(0.3),
      color: _stream,
      height: 1.2,
    );
    final tag = BoxDecoration(
      color: Colors.black.withValues(alpha: 0.18),
      border: Border.all(
        color: KalinkaColors.textPrimary.withValues(alpha: 0.32),
      ),
      borderRadius: BorderRadius.circular(s(6)),
    );
    final format = lines.format;
    final source = lines.source;
    final sourceTitle = lines.sourceTitle;
    final formatTag = format == null
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: s(9),
                    vertical: s(5),
                  ),
                  decoration: tag,
                  child: Text(
                    format,
                    style: style,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (showBitPerfect) BitPerfectBadge(scale: scale * 1.265),
            ],
          );
    final name = sourceTitle == null
        ? null
        : Text(
            sourceTitle,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
    final Widget? where = source == null || name == null
        ? null
        : sourceFirst
        ? Container(
            decoration: tag,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SourceTile(source: source, size: s(28)),
                Flexible(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: s(10)),
                    child: name,
                  ),
                ),
              ],
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SourceTile(source: source, size: s(28)),
              SizedBox(width: s(10)),
              Flexible(child: name),
            ],
          );
    return Wrap(
      alignment: centred ? WrapAlignment.center : WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: s(sourceFirst ? 10 : 16),
      runSpacing: s(8),
      children: sourceFirst ? [?where, ?formatTag] : [?formatTag, ?where],
    );
  }
}
