import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/app_theme.dart';
import 'kalinka_button.dart';

/// How far the cutout sits outside its target.
const double _kHoleInset = 6;
const double _kRingGrowth = 22;
const double _kGlowBlur = 10;

/// How far past the target the pulse reaches, glow included.
const double _kPulseReach = _kHoleInset + _kRingGrowth + _kGlowBlur;

const double _kCardMaxWidth = 420;

/// A side narrower than this is passed over: Skip and Next would crowd the
/// body. A window narrower than this still has the rows above and below.
const double _kCardMinWidth = 240;

/// Frames a stop's target gets to lay out before the card gives up on it.
const int _kMeasureRetries = 5;

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
/// scrim with a pulsing cutout around each target and the tip card beside
/// it, clear of the pulse where the window allows, or centred when there is
/// no target, sliding there from stop to stop. Tapping anywhere, or the Next
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
    with TickerProviderStateMixin {
  int _index = 0;
  Rect? _targetRect;

  /// What the card is placed against. It keeps the last stop's target while
  /// the next one is measured, so the card doesn't head for the centre.
  Rect? _cardTarget;

  /// The target of the stop the card was last placed for; null until the
  /// first stop is measured, so the card appears in place rather than
  /// sliding there. A key, not an index: the list can change under the index.
  GlobalKey? _placedKey;
  int _misses = 0;
  bool _resolvePending = false;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();
  late final AnimationController _move = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    _scheduleResolve();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _move.dispose();
    super.dispose();
  }

  /// The stops are derived from live state — the output switcher only exists
  /// once a server with /renderer/* support has served a list — so the list
  /// can shrink mid-tour and strand the index past its end.
  @override
  void didUpdateWidget(covariant CoachMarksOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldStops = oldWidget.stops;
    final wasKey = _index < oldStops.length ? oldStops[_index].targetKey : null;
    if (_index >= widget.stops.length && widget.stops.isNotEmpty) {
      _index = widget.stops.length - 1;
    }
    if (widget.stops.isNotEmpty && widget.stops[_index].targetKey != wasKey) {
      _targetRect = null;
      _misses = 0;
    }
    _scheduleResolve();
  }

  void _scheduleResolve() {
    if (_resolvePending) return;
    _resolvePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resolvePending = false;
      _resolveRect();
    });
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

    // A target mounted a frame or two after the tour isn't absent yet.
    if (rect == null && _misses < _kMeasureRetries) {
      _misses++;
      _scheduleResolve();
      WidgetsBinding.instance.scheduleFrame();
      return;
    }
    if (rect != null) _misses = 0;

    final key = widget.stops[_index].targetKey;
    final newStop = _placedKey != key;
    if (!newStop && rect == _targetRect && rect == _cardTarget) return;
    // A target that moves mid-slide restarts the slide from where it is.
    if ((newStop && _placedKey != null) || _move.isAnimating) {
      _move.duration = MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220);
      _move.forward(from: 0);
    }
    setState(() {
      _targetRect = rect;
      _cardTarget = rect;
      _placedKey = key;
    });
  }

  void _next() {
    if (_index >= widget.stops.length - 1) {
      widget.onDismiss();
      return;
    }
    setState(() {
      _index++;
      _targetRect = null;
      _misses = 0;
    });
    _scheduleResolve();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.stops.isEmpty) return const SizedBox.shrink();
    final stop = widget.stops[_index.clamp(0, widget.stops.length - 1)];
    final isLast = _index >= widget.stops.length - 1;
    final safeArea = MediaQuery.paddingOf(context);

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
              if (_placedKey != null)
                Positioned.fill(
                  child: _CardPlacement(
                    target: _cardTarget,
                    padding: safeArea + const EdgeInsets.all(24),
                    move: _move,
                    child: _buildTipCard(stop, isLast),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTipCard(CoachMarkStop stop, bool isLast) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      constraints: const BoxConstraints(maxWidth: _kCardMaxWidth),
      decoration: BoxDecoration(
        color: KalinkaColors.surfaceDialog,
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
          // In a short window the body scrolls; the title and buttons stay.
          Flexible(
            child: _CollapsibleBody(
              child: SingleChildScrollView(
                child: Text(
                  stop.body,
                  style: KalinkaTextStyles.trayRowSublabel.copyWith(
                    fontSize: KalinkaTypography.baseSize + 2,
                    height: 1.5,
                  ),
                ),
              ),
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

/// Reports no minimum height, so the card's minimum is its title and buttons.
class _CollapsibleBody extends SingleChildRenderObjectWidget {
  const _CollapsibleBody({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCollapsibleBody();
}

class _RenderCollapsibleBody extends RenderProxyBox {
  @override
  double computeMinIntrinsicHeight(double width) => 0;
}

/// Places the card beside [target], below or above before left or right:
/// clear of the whole pulse if it fits, else of the cutout; whole, else with
/// its body scrolling. With no room anywhere it is pinned to the far edge.
/// A new target slides the card there along [move].
class _CardPlacement extends SingleChildRenderObjectWidget {
  final Rect? target;
  final EdgeInsets padding;
  final Animation<double> move;

  const _CardPlacement({
    required this.target,
    required this.padding,
    required this.move,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCardPlacement(target: target, padding: padding, move: move);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCardPlacement renderObject,
  ) {
    renderObject
      ..target = target
      ..padding = padding
      ..move = move;
  }
}

class _RenderCardPlacement extends RenderShiftedBox {
  _RenderCardPlacement({
    required this._target,
    required this._padding,
    required this._move,
  }) : super(null);

  Rect? _target;
  set target(Rect? value) {
    if (value == _target) return;
    _target = value;
    _from = _shown;
    markNeedsLayout();
  }

  EdgeInsets _padding;
  set padding(EdgeInsets value) {
    if (value == _padding) return;
    _padding = value;
    markNeedsLayout();
  }

  Animation<double> _move;
  set move(Animation<double> value) {
    if (value == _move) return;
    if (attached) _move.removeListener(markNeedsLayout);
    _move = value;
    if (attached) _move.addListener(markNeedsLayout);
    markNeedsLayout();
  }

  Offset? _from;
  Offset? _shown;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _move.addListener(markNeedsLayout);
  }

  @override
  void detach() {
    _move.removeListener(markNeedsLayout);
    super.detach();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    size = constraints.biggest;
    final card = child;
    if (card == null) return;
    var area = _padding.deflateRect(Offset.zero & size);
    if (area.width <= 0 || area.height <= 0) area = Offset.zero & size;
    final (region, alignment) = _place(area, card);
    card.layout(
      BoxConstraints.loose(
        Size(math.max(0, region.width), math.max(0, region.height)),
      ),
      parentUsesSize: true,
    );
    final to =
        region.topLeft +
        alignment.alongOffset(region.size - card.size as Offset);
    final from = _from;
    final shown = from == null
        ? to
        : Offset.lerp(from, to, Curves.easeInOut.transform(_move.value))!;
    _shown = shown;
    // Done sliding: a later slide with no new target has nowhere to come from.
    if (_move.isCompleted) _from = null;
    (card.parentData! as BoxParentData).offset = shown;
  }

  (Rect, Alignment) _place(Rect area, RenderBox card) {
    final target = _target;
    if (target == null) return (area, Alignment.center);
    final sides = [
      for (final reach in const [_kPulseReach, _kHoleInset])
        ..._sidesAround(area, target.inflate(reach)),
    ];
    final minWidth = math.min(_kCardMinWidth, area.width);
    for (final heightAt in [
      card.getMaxIntrinsicHeight,
      card.getMinIntrinsicHeight,
    ]) {
      for (final (region, alignment) in sides) {
        final width = math.min(region.width, _kCardMaxWidth);
        if (width >= minWidth && heightAt(width) <= region.height) {
          return (region, alignment);
        }
      }
    }
    return (area, sides.first.$2);
  }

  static List<(Rect, Alignment)> _sidesAround(Rect area, Rect clear) {
    final above = Rect.fromLTRB(
      area.left,
      area.top,
      area.right,
      math.min(area.bottom, clear.top),
    );
    final below = Rect.fromLTRB(
      area.left,
      math.max(area.top, clear.bottom),
      area.right,
      area.bottom,
    );
    final left = Rect.fromLTRB(
      area.left,
      area.top,
      math.min(area.right, clear.left),
      area.bottom,
    );
    final right = Rect.fromLTRB(
      math.max(area.left, clear.right),
      area.top,
      area.right,
      area.bottom,
    );
    final vertical = [
      (below, Alignment.bottomCenter),
      (above, Alignment.topCenter),
    ];
    final horizontal = [(right, Alignment.center), (left, Alignment.center)];
    return [
      ...below.height >= above.height ? vertical : vertical.reversed,
      ...right.width >= left.width ? horizontal : horizontal.reversed,
    ];
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
      rect.inflate(_kHoleInset),
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
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, _kGlowBlur)
        ..color = KalinkaColors.accent.withValues(alpha: 0.25 + 0.5 * fade),
    );
    canvas.drawRRect(
      hole.inflate(_kRingGrowth * beat),
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
