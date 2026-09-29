import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../bit_perfect_badge.dart';

// Brighter than the app's secondary greys: these lines sit on the cover's
// colours, not on near-black.
final _album = KalinkaColors.textPrimary.withValues(alpha: 0.84);
final _stream = KalinkaColors.textPrimary.withValues(alpha: 0.74);

/// What the display says about a track.
@immutable
class KioskTrackLines {
  final String trackId;
  final String title;
  final String artist;
  final String? album;

  /// Source and stream resolution — `Qobuz · FLAC · 16-bit / 44.1 kHz`.
  final String? stream;

  const KioskTrackLines({
    required this.trackId,
    required this.title,
    required this.artist,
    this.album,
    this.stream,
  });

  @override
  bool operator ==(Object other) =>
      other is KioskTrackLines &&
      other.trackId == trackId &&
      other.title == title &&
      other.artist == artist &&
      other.album == album &&
      other.stream == stream;

  @override
  int get hashCode => Object.hash(trackId, title, artist, album, stream);
}

/// Title, artist, album and stream, changing over line by line: the old
/// lines lift away, then the new ones rise in one after another. A change
/// within the same track (the stream's format arriving) just updates.
class KioskTrackText extends StatefulWidget {
  final KioskTrackLines lines;
  final double scale;
  final bool centred;

  const KioskTrackText({
    super.key,
    required this.lines,
    required this.scale,
    this.centred = false,
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
    final align = widget.centred ? TextAlign.center : TextAlign.start;
    final rows = <Widget>[
      Text(
        lines.title,
        style: KalinkaFonts.display(
          fontSize: s(40),
          fontWeight: FontWeight.w500,
          color: KalinkaColors.frost,
          height: 1.12,
        ),
        textAlign: align,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      Padding(
        padding: EdgeInsets.only(top: s(12)),
        child: Text(
          lines.artist,
          style: KalinkaFonts.sans(
            fontSize: s(22),
            fontWeight: FontWeight.w500,
            color: KalinkaColors.textPrimary,
          ),
          textAlign: align,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      if (lines.album != null)
        Padding(
          padding: EdgeInsets.only(top: s(6)),
          child: Text(
            lines.album!,
            style: KalinkaFonts.sans(fontSize: s(17), color: _album),
            textAlign: align,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      if (lines.stream != null)
        Padding(
          padding: EdgeInsets.only(top: s(16)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  lines.stream!,
                  style: KalinkaFonts.mono(
                    fontSize: s(14),
                    letterSpacing: s(0.4),
                    color: _stream,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!leaving) BitPerfectBadge(scale: widget.scale * 1.265),
            ],
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
