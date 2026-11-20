import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../bit_perfect_badge.dart';
import '../fitted_title.dart';
import '../source_badge.dart' show SourceTile;

// Brighter than the app's secondary greys: these lines sit on the cover's
// colours, not on near-black.
final _primaryCredit = KalinkaColors.textPrimary.withValues(alpha: 0.78);
final _secondaryCredit = KalinkaColors.textPrimary.withValues(alpha: 0.7);
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
  final String? artist;
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

// Keep the small mono label and stream attribution legible across the room.
double _captionScale(double scale) => math.min(scale, 2.0);

/// The display's eyebrow over the track: `NOW PLAYING`, spaced out in the
/// accent.
class KioskEyebrow extends StatelessWidget {
  final double scale;

  const KioskEyebrow({super.key, required this.scale});

  @override
  Widget build(BuildContext context) {
    final textScale = _captionScale(scale);
    return Text(
      'NOW PLAYING',
      style: KalinkaFonts.mono(
        fontSize: 14 * textScale,
        fontWeight: FontWeight.w600,
        letterSpacing: 4.5 * textScale,
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

  /// Group the credits under the title in the bounded column beside the cover.
  final double? landscapeWidth;

  /// Move the incoming block as one opaque layer on a local display.
  final bool slideTogether;

  const KioskTrackText({
    super.key,
    required this.lines,
    required this.scale,
    this.centred = false,
    this.compact = false,
    this.landscapeWidth,
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
            bottom: widget.landscapeWidth != null ? 0 : null,
            child: _block(leaving, leaving: true),
          ),
        _block(widget.lines, leaving: false),
      ],
    );
  }

  Widget _block(KioskTrackLines lines, {required bool leaving}) {
    double s(double v) => v * widget.scale;
    final compact = widget.compact;
    final landscape = widget.landscapeWidth != null;
    // Beyond the reference panel, give type half the additional layout
    // scale. System text scaling is applied separately.
    final typeScale = landscape && widget.scale > 1
        ? 1 + (widget.scale - 1) / 2
        : widget.scale;
    double font(double value) => value * typeScale;
    final align = widget.centred ? TextAlign.center : TextAlign.start;
    final crossAxis = widget.centred
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;
    final shadows = compact ? kioskTextPolish : null;
    final primaryCredit = landscape ? lines.album : (lines.artist ?? '—');
    final secondaryCredit = landscape ? lines.artist : lines.album;
    final titleStyle = KalinkaFonts.display(
      fontSize: font(compact ? 26 : 54),
      fontWeight: FontWeight.w500,
      color: KalinkaColors.frost,
      height: compact ? 1.05 : 1.1,
    ).copyWith(shadows: shadows);
    final primaryStyle = KalinkaFonts.sans(
      fontSize: font(compact ? 19 : 30),
      fontWeight: FontWeight.w500,
      color: _primaryCredit,
      height: 1.2,
    ).copyWith(shadows: shadows);
    Widget name(
      String text,
      TextStyle style, {
      required double minSize,
      required int linesWhenStacked,
      bool preferSingleLine = false,
    }) {
      final width = widget.landscapeWidth;
      if (width != null) {
        return FittedTitle(
          text,
          style: style,
          minFontSize: font(minSize),
          preferSingleLine: preferSingleLine,
          availableWidth: width,
        );
      }
      return Text(
        text,
        style: style,
        textAlign: align,
        maxLines: linesWhenStacked,
        overflow: TextOverflow.ellipsis,
      );
    }

    final title = name(
      lines.title,
      titleStyle,
      minSize: 40,
      linesWhenStacked: compact ? 1 : 2,
    );
    final credits = [
      if (primaryCredit != null)
        name(
          primaryCredit,
          primaryStyle,
          minSize: 24,
          linesWhenStacked: 1,
          preferSingleLine: true,
        ),
      if (secondaryCredit != null)
        Text(
          secondaryCredit,
          style: KalinkaFonts.sans(
            fontSize: font(compact ? 15 : 21),
            color: _secondaryCredit,
            height: 1.25,
          ).copyWith(shadows: shadows),
          textAlign: align,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
    ];

    Widget stage(Widget row, int index) {
      if (widget.slideTogether) return row;
      return _Staged(
        animation: _controller,
        interval: leaving
            ? const Interval(0, 0.3, curve: Curves.easeInCubic)
            : Interval(
                0.22 + index * 0.09,
                0.64 + index * 0.09,
                curve: Curves.easeOutCubic,
              ),
        leaving: leaving,
        rise: s(18),
        child: row,
      );
    }

    final stackedGap = compact ? 0.0 : s(6);
    final streamScale = compact
        ? math.max(widget.scale * 0.46, 0.72)
        : _captionScale(widget.scale);
    final streamGap = s(landscape ? 20 : (compact ? 8 : 10));
    Widget column({double extraCreditGap = 0}) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxis,
      children: [
        if (landscape) const Spacer(flex: 2),
        stage(title, 0),
        if (credits.isNotEmpty) ...[
          if (landscape) const Spacer(),
          SizedBox(height: landscape ? s(12) : stackedGap),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: crossAxis,
            spacing: landscape ? s(4) + extraCreditGap : stackedGap,
            children: [
              for (final (i, row) in credits.indexed) stage(row, i + 1),
            ],
          ),
        ],
        if (lines.stream != null) ...[
          if (landscape) const Spacer(flex: 5),
          SizedBox(height: streamGap - extraCreditGap),
          stage(
            _StreamRow(
              lines: lines,
              scale: streamScale,
              color: landscape ? KalinkaColors.textSecondary : _stream,
              shadows: shadows,
              showBitPerfect: !leaving,
            ),
            credits.length + 1,
          ),
        ],
        if (landscape) Spacer(flex: lines.stream == null ? 5 : 1),
      ],
    );
    if (!landscape) return column();

    // Fit each track independently when a wrapping title or large text needs
    // more height than the space above the controls.
    return LayoutBuilder(
      builder: (context, box) {
        // Open the album–artist gap as height allows. Take the extra from
        // below the artist so the other rows stay put.
        final artistSize = font(21);
        final textScale =
            MediaQuery.textScalerOf(context).scale(artistSize) / artistSize;
        final gap = (box.maxHeight * 0.03 / textScale).clamp(s(4), s(8));
        final extra = credits.length == 2 ? gap - s(4) : 0.0;
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topLeft,
          child: Container(
            width: box.maxWidth,
            constraints: BoxConstraints(minHeight: box.maxHeight),
            padding: EdgeInsets.only(
              top: s(12),
              bottom: s(6) - (lines.stream == null ? extra : 0),
            ),
            child: IntrinsicHeight(child: column(extraCreditGap: extra)),
          ),
        );
      },
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
  final Color color;
  final List<Shadow>? shadows;

  /// Off for the lines on their way out: the badge watches live state, which
  /// already describes the newcomer.
  final bool showBitPerfect;

  const _StreamRow({
    required this.lines,
    required this.scale,
    required this.color,
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
              color: color,
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
