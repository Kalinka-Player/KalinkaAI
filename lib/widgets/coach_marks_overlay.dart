import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'kalinka_button.dart';

/// One spotlight stop of the first-run tour.
class CoachMarkStop {
  /// Key of the widget to spotlight. When the key can't be resolved
  /// (widget not mounted), the tip card shows over an unbroken scrim.
  final GlobalKey targetKey;
  final String title;
  final String body;

  const CoachMarkStop({
    required this.targetKey,
    required this.title,
    required this.body,
  });
}

/// One-time UI tour shown the first time the play queue appears: a dimmed
/// scrim with a pulsing cutout around each target and the tip card centred
/// on screen, where it stays from stop to stop. Tapping anywhere, or the Next
/// button, advances; Skip ends the tour.
class CoachMarksOverlay extends StatefulWidget {
  final List<CoachMarkStop> stops;
  final VoidCallback onDismiss;

  const CoachMarksOverlay({
    super.key,
    required this.stops,
    required this.onDismiss,
  });

  @override
  State<CoachMarksOverlay> createState() => _CoachMarksOverlayState();
}

class _CoachMarksOverlayState extends State<CoachMarksOverlay>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  Rect? _targetRect;
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void initState() {
    super.initState();
    _scheduleResolve();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// The stops are derived from live state — the output switcher only exists
  /// once a server with /renderer/* support has served a list — so the list
  /// can shrink mid-tour and strand the index past its end.
  @override
  void didUpdateWidget(covariant CoachMarksOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_index >= widget.stops.length && widget.stops.isNotEmpty) {
      _index = widget.stops.length - 1;
      _targetRect = null;
    }
    _scheduleResolve();
  }

  void _scheduleResolve() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveRect());
  }

  void _resolveRect() {
    if (!mounted || _index >= widget.stops.length) return;
    final targetContext = widget.stops[_index].targetKey.currentContext;
    final targetBox = targetContext?.findRenderObject() as RenderBox?;
    final overlayBox = context.findRenderObject() as RenderBox?;
    Rect? rect;
    if (targetBox != null &&
        overlayBox != null &&
        targetBox.hasSize &&
        targetBox.attached) {
      final topLeft = targetBox.localToGlobal(
        Offset.zero,
        ancestor: overlayBox,
      );
      rect = topLeft & targetBox.size;
    }
    // A target that renders nothing resolves to a zero-size box; spotlighting
    // that would ring an empty patch of screen, so treat it as absent. Stops
    // whose control is genuinely gone are better left out of the list — the
    // card would still describe a missing control.
    if (rect != null && (rect.width < 4 || rect.height < 4)) rect = null;

    if (rect == _targetRect) return;
    setState(() => _targetRect = rect);
  }

  void _next() {
    if (_index >= widget.stops.length - 1) {
      widget.onDismiss();
      return;
    }
    setState(() {
      _index++;
      _targetRect = null;
    });
    _scheduleResolve();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.stops.isEmpty) return const SizedBox.shrink();
    final stop = widget.stops[_index.clamp(0, widget.stops.length - 1)];
    final isLast = _index >= widget.stops.length - 1;

    // The spotlight is a screen-space rectangle, so anything that moves the
    // target invalidates it. Resizing across the tablet breakpoint moves this
    // tour's targets furthest — the output switcher changes which widget it
    // even is — so re-measure whenever our own size changes, after the frame
    // that laid the new tree out.
    return LayoutBuilder(
      builder: (context, constraints) {
        _scheduleResolve();
        return GestureDetector(
          onTap: _next,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _SpotlightPainter(
                      cutout: _targetRect,
                      pulse: _pulse,
                    ),
                  ),
                ),
              ),
              Center(child: _buildTipCard(stop, isLast)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTipCard(CoachMarkStop stop, bool isLast) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      constraints: const BoxConstraints(maxWidth: 420),
      decoration: BoxDecoration(
        color: KalinkaColors.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KalinkaColors.borderDefault),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 40,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_index + 1} / ${widget.stops.length}',
            style: KalinkaTextStyles.sectionHeaderMuted,
          ),
          const SizedBox(height: 8),
          Text(stop.title, style: KalinkaTextStyles.cardTitle),
          const SizedBox(height: 6),
          Text(
            stop.body,
            style: KalinkaTextStyles.trayRowSublabel.copyWith(
              fontSize: KalinkaTypography.baseSize + 2,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              GestureDetector(
                onTap: widget.onDismiss,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  child: Text('Skip', style: KalinkaTextStyles.cancelButton),
                ),
              ),
              const Spacer(),
              KalinkaButton(
                label: isLast ? 'Done' : 'Next',
                variant: KalinkaButtonVariant.accent,
                size: KalinkaButtonSize.compact,
                onTap: _next,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect? cutout;
  final Animation<double> pulse;

  _SpotlightPainter({required this.cutout, required this.pulse})
    : super(repaint: pulse);

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Path()..addRect(Offset.zero & size);
    final scrimPaint = Paint()..color = Colors.black.withValues(alpha: 0.72);
    final rect = cutout;
    if (rect == null) {
      canvas.drawPath(scrim, scrimPaint);
      return;
    }
    final hole = RRect.fromRectAndRadius(
      rect.inflate(6),
      const Radius.circular(14),
    );
    final outside = Path.combine(
      PathOperation.difference,
      scrim,
      Path()..addRRect(hole),
    );
    canvas.drawPath(outside, scrimPaint);

    final beat = Curves.easeOut.transform(pulse.value);
    final fade = 1 - beat;
    canvas.save();
    // Glow and ring stay on the scrim so the control itself is never tinted.
    canvas.clipPath(outside);
    canvas.drawRRect(
      hole,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10)
        ..color = KalinkaColors.accent.withValues(alpha: 0.25 + 0.5 * fade),
    );
    canvas.drawRRect(
      hole.inflate(22 * beat),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = KalinkaColors.accent.withValues(alpha: 0.8 * fade * fade),
    );
    canvas.restore();
    canvas.drawRRect(
      hole,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = KalinkaColors.accent.withValues(alpha: 0.55 + 0.45 * fade),
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) =>
      oldDelegate.cutout != cutout || oldDelegate.pulse != pulse;
}
