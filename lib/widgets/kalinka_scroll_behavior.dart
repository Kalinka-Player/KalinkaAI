import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/app_theme.dart';

/// Adds a page button at the overflowing edge of each content viewport.
class KalinkaScrollBehavior extends MaterialScrollBehavior {
  const KalinkaScrollBehavior({
    this.bottomClearance = 0,
    this.controlScale = 1,
  });

  /// Space occupied by a fixed control over the foot of a vertical list.
  final double bottomClearance;

  /// Kiosk controls grow together for viewing a large display at a distance.
  final double controlScale;

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    final native = super.buildScrollbar(context, child, details);
    final view = context.widget;
    // Text editors manage scrolling and accessibility as part of editing.
    if (view is! Scrollable || view.excludeFromSemantics) return native;
    // Primary controllers can serve several panes. Page just this viewport.
    final position = details.controller?.positions
        .where((p) => p.context.storageContext == context)
        .firstOrNull;
    if (position == null || !position.physics.allowUserScrolling) return native;
    return _ScrollPageIndicator(
      position: position,
      bottomClearance: bottomClearance,
      controlScale: controlScale,
      child: native,
    );
  }

  @override
  bool shouldNotify(KalinkaScrollBehavior oldDelegate) =>
      bottomClearance != oldDelegate.bottomClearance ||
      controlScale != oldDelegate.controlScale;
}

class _ScrollPageIndicator extends StatefulWidget {
  const _ScrollPageIndicator({
    required this.position,
    required this.bottomClearance,
    required this.controlScale,
    required this.child,
  });

  final ScrollPosition position;
  final double bottomClearance;
  final double controlScale;
  final Widget child;

  @override
  State<_ScrollPageIndicator> createState() => _ScrollPageIndicatorState();
}

class _ScrollPageIndicatorState extends State<_ScrollPageIndicator> {
  Timer? _idle;
  bool _scrolling = false;
  bool _visible = false;
  bool _refreshQueued = false;
  _PageButton? _button;

  double get _pageExtent =>
      widget.position.viewportDimension -
      (widget.position.axis == Axis.vertical ? widget.bottomClearance : 0);

  bool get _more {
    final p = widget.position;
    if (!p.hasContentDimensions || !p.hasViewportDimension) return false;
    final remaining = p.axisDirection == AxisDirection.up
        ? p.extentBefore
        : p.extentAfter;
    return _pageExtent > 0 &&
        p.maxScrollExtent > p.minScrollExtent &&
        remaining > precisionErrorTolerance;
  }

  void _refresh({bool? scrolling}) {
    final visible = _more;
    final moving = scrolling ?? _scrolling;
    final changed = _visible != visible || (visible && _scrolling != moving);
    _visible = visible;
    _scrolling = moving;
    // Offset corrections can arrive during layout. Coalesce those with the
    // metrics notification sent after layout, including the very first one.
    if (!changed || _refreshQueued) return;
    _refreshQueued = true;
    scheduleMicrotask(() {
      _refreshQueued = false;
      if (mounted) setState(() {});
    });
  }

  void _page() {
    if (!_more) return;
    final p = widget.position;
    final page = _pageExtent;
    final target =
        (p.pixels + (p.axisDirection == AxisDirection.up ? -page : page)).clamp(
          p.minScrollExtent,
          p.maxScrollExtent,
        );
    if (MediaQuery.disableAnimationsOf(context)) {
      p.jumpTo(target);
    } else {
      p.animateTo(
        target,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _idle?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) {
        if (n.depth == 0) _refresh();
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.depth != 0) return false;
          if (n is ScrollStartNotification) {
            _idle?.cancel();
            _refresh(scrolling: true);
          } else if (n is ScrollEndNotification) {
            // Wheel events can start and finish in one frame. Keep the cue
            // quiet across a burst, as it is through a drag or a fling.
            _idle?.cancel();
            _idle = Timer(
              const Duration(milliseconds: 180),
              () => _refresh(scrolling: false),
            );
          } else {
            _refresh();
          }
          return false;
        },
        child: _PageIndicatorStack(
          children: [widget.child, if (_visible) _pageButton()],
        ),
      ),
    );
  }

  Widget _pageButton() {
    final appearance = (
      direction: widget.position.axisDirection,
      bottomClearance: widget.bottomClearance,
      scale: widget.controlScale,
      scrolling: _scrolling,
    );
    // Scrollable rebuilds its chrome as the window changes size. Let layout
    // reposition the existing button until its appearance actually changes.
    if (_button?.appearance != appearance) {
      _button = _PageButton(appearance: appearance, onPressed: _page);
    }
    return _button!;
  }
}

typedef _PageAppearance = ({
  AxisDirection direction,
  double bottomClearance,
  double scale,
  bool scrolling,
});

class _PageButton extends StatelessWidget {
  const _PageButton({required this.appearance, required this.onPressed});

  final _PageAppearance appearance;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final (alignment, icon, label) = switch (appearance.direction) {
      AxisDirection.left => (
        Alignment.centerLeft,
        Icons.chevron_left_rounded,
        'Scroll left one page',
      ),
      AxisDirection.right => (
        Alignment.centerRight,
        Icons.chevron_right_rounded,
        'Scroll right one page',
      ),
      _ => (
        Alignment.bottomCenter,
        Icons.keyboard_arrow_down_rounded,
        'Scroll down one page',
      ),
    };
    final scale = appearance.scale;
    final size = Size.square(34 * scale);
    final button = IconButton(
      tooltip: label,
      onPressed: onPressed,
      icon: Icon(icon, size: 24 * scale),
      style:
          IconButton.styleFrom(
            fixedSize: size,
            minimumSize: size,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.standard,
            tapTargetSize: MaterialTapTargetSize.padded,
            enabledMouseCursor: SystemMouseCursors.click,
            foregroundColor: KalinkaColors.textPrimary.withValues(
              alpha: appearance.scrolling ? 0.6 : 0.92,
            ),
            backgroundColor: KalinkaColors.surfaceOverlay.withValues(
              alpha: appearance.scrolling ? 0.45 : 0.84,
            ),
            animationDuration: Duration.zero,
          ).copyWith(
            side: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.focused)) {
                return BorderSide(
                  color: KalinkaColors.textPrimary,
                  width: 2 * scale,
                );
              }
              return BorderSide(
                color: KalinkaColors.textMuted.withValues(
                  alpha: appearance.scrolling ? 0.35 : 0.7,
                ),
              );
            }),
          ),
    );
    return Positioned.fill(
      child: Padding(
        padding: axisDirectionToAxis(appearance.direction) == Axis.vertical
            ? EdgeInsets.only(
                bottom:
                    4 +
                    math.max(
                      appearance.bottomClearance,
                      MediaQuery.paddingOf(context).bottom,
                    ),
              )
            : const EdgeInsets.symmetric(horizontal: 8),
        child: Align(alignment: alignment, child: button),
      ),
    );
  }
}

/// A gesture over the button can scroll its viewport. A row underneath must
/// never receive the same pointer, including mouse modifiers and long presses.
class _PageIndicatorStack extends Stack {
  const _PageIndicatorStack({required super.children})
    : super(fit: StackFit.passthrough);

  @override
  RenderStack createRenderObject(BuildContext context) =>
      _PageIndicatorRenderStack(textDirection: Directionality.maybeOf(context));
}

class _PageIndicatorRenderStack extends RenderStack {
  _PageIndicatorRenderStack({required super.textDirection})
    : super(fit: StackFit.passthrough);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    // The scrollable sizes the stack and the positioned overlay fills it.
    final content = firstChild!;
    final overlay = lastChild!;
    if (overlay == content || !overlay.hitTest(result, position: position)) {
      return content.hitTest(result, position: position);
    }

    // Scrollable installs its drag and wheel handlers above its viewport.
    // Keep those hit entries, with their transforms, even over nested lists.
    final hits = BoxHitTestResult();
    content.hitTest(hits, position: position);
    final path = hits.path.toList(growable: false);
    final viewport = path.lastIndexWhere(
      (e) => e.target is RenderAbstractViewport,
    );
    for (final entry in path.skip(viewport + 1).whereType<BoxHitTestEntry>()) {
      result.addWithRawTransform(
        transform: entry.transform,
        position: position,
        hitTest: (result, localPosition) {
          result.add(BoxHitTestEntry(entry.target, localPosition));
          return true;
        },
      );
    }
    return true;
  }
}
