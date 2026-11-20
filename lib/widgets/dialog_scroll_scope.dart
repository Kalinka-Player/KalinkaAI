import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'keyboard/ink_focus_outline.dart';
import 'tap_highlight.dart';

/// Gives lists inside a popup their own scroll controls. Material captures
/// inherited themes when an options button opens a separate popup menu route.
class DialogScrollScope extends InheritedTheme {
  DialogScrollScope({super.key, required Widget child})
    : super(
        child: ScrollConfiguration(
          behavior: const _DialogScrollBehavior(),
          child: child,
        ),
      );

  @override
  Widget wrap(BuildContext context, Widget child) =>
      DialogScrollScope(child: child);

  @override
  bool updateShouldNotify(DialogScrollScope oldWidget) => false;
}

class _DialogScrollBehavior extends MaterialScrollBehavior {
  const _DialogScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    final native = super.buildScrollbar(context, child, details);
    final view = context.widget;
    if (view is! Scrollable || view.excludeFromSemantics) return native;
    // A primary controller can serve more than one list in a dialog.
    final position = details.controller?.positions
        .where((p) => p.context.storageContext == context)
        .firstOrNull;
    if (position == null || !position.physics.allowUserScrolling) return native;
    return _ListEdges(
      position: position,
      direction: details.direction,
      child: native,
    );
  }
}

class _ListEdges extends StatefulWidget {
  const _ListEdges({
    required this.position,
    required this.direction,
    required this.child,
  });
  final ScrollPosition position;
  final AxisDirection direction;
  final Widget child;

  @override
  State<_ListEdges> createState() => _ListEdgesState();
}

class _ListEdgesState extends State<_ListEdges> {
  static const _strip = 16.0;
  static const _empty = (
    before: false,
    after: false,
    band: 0.0,
    moving: false,
    direction: AxisDirection.down,
  );
  var _edges = _empty;
  var _pending = _empty;
  double _appliedBand = 0;
  List<Widget> _buttons = const [];
  bool _queued = false;

  late FocusNode _contentFocus;
  final _beforeFocus = FocusNode();
  final _afterFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _beforeFocus.dispose();
    _afterFocus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_ListEdges oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.position != oldWidget.position ||
        widget.direction != oldWidget.direction) {
      _refresh();
    }
  }

  void _refresh() {
    final p = widget.position;
    if (!p.hasContentDimensions || !p.hasViewportDimension || !p.hasPixels) {
      return;
    }
    // Compare to the space the list would have with both controls removed.
    // Their own footprint must never manufacture overflow on resize.
    // If a sudden resize leaves no viewport at all, release both bands
    // first so the next layout measures the new space without them.
    final available = p.viewportDimension == 0
        ? 0.0
        : p.viewportDimension + 2 * _appliedBand;
    final overflow =
        available > 0 && p.extentTotal - available > precisionErrorTolerance;
    // The bands stay the same size from the first to the last page. This
    // keeps a page forward followed by a page back at the original row.
    final next = (
      direction: widget.direction,
      before: overflow && p.extentBefore > precisionErrorTolerance,
      after: overflow && p.extentAfter > precisionErrorTolerance,
      band: overflow ? math.min(_strip, available / 4) : 0.0,
      moving: overflow && p.isScrollingNotifier.value,
    );
    if (next == _pending) return;
    _pending = next;
    if (_queued) return;
    _queued = true;
    // Offset corrections can arrive during layout. Apply only the final
    // state, and schedule nothing while the same edges stay visible.
    scheduleMicrotask(() {
      _queued = false;
      final edges = _pending;
      if (!mounted || edges == _edges) return;
      final forward = edges.direction;
      if (_afterFocus.hasPrimaryFocus && !edges.after) {
        _focusBoundary(forward, edges.before ? _beforeFocus : null);
      } else if (_beforeFocus.hasPrimaryFocus && !edges.before) {
        _focusBoundary(
          flipAxisDirection(forward),
          edges.after ? _afterFocus : null,
        );
      }
      setState(() {
        _edges = edges;
        // An ordinary window resize can re-layout these same controls.
        _buttons = [
          for (final edge in [
            if (edges.before) flipAxisDirection(forward),
            if (edges.after) forward,
          ])
            _EdgeButton(
              key: ValueKey(edge),
              edge: edge,
              band: edges.band,
              focus: edge == forward ? _afterFocus : _beforeFocus,
              moving: edges.moving,
              onPressed: () => _page(edge == forward),
            ),
        ];
      });
    });
  }

  // A focused page button can disappear at either end. Keep the remote in
  // the list and let the next activation select the newly reached item.
  void _focusBoundary(AxisDirection edge, FocusNode? fallback) {
    // A jump with reduced motion can report the new offset before the rows
    // on that page have been laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final viewport = _contentFocus.rect;
      FocusNode? nearest;
      var distance = double.infinity;
      for (final node in _contentFocus.traversalDescendants) {
        if (node is FocusScopeNode) continue;
        final rect = node.rect;
        if (!rect.overlaps(viewport)) continue;
        final gap = switch (edge) {
          AxisDirection.up => rect.center.dy - viewport.top,
          AxisDirection.down => viewport.bottom - rect.center.dy,
          AxisDirection.left => rect.center.dx - viewport.left,
          AxisDirection.right => viewport.right - rect.center.dx,
        };
        if (gap < distance) {
          nearest = node;
          distance = gap;
        }
      }
      (nearest ?? fallback)?.requestFocus();
    });
  }

  void _page(bool forward) {
    final p = widget.position;
    final distance = forward ? p.viewportDimension : -p.viewportDimension;
    final target = (p.pixels + distance).clamp(
      p.minScrollExtent,
      p.maxScrollExtent,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      p.jumpTo(target);
    } else {
      p.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _appliedBand = _edges.band;
    final vertical = widget.position.axis == Axis.vertical;
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) {
        if (n.depth == 0) _refresh();
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.depth == 0) _refresh();
          return false;
        },
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                vertical: vertical ? _appliedBand : 0,
                horizontal: vertical ? 0 : _appliedBand,
              ),
              child: FocusTraversalGroup(
                policy: FocusTraversalGroup.maybeOf(context),
                onFocusNodeCreated: (node) => _contentFocus = node,
                child: widget.child,
              ),
            ),
            // Keep paging reachable by Tab even as row traversal reveals
            // more rows. The content keeps the popup's own arrow-key policy.
            Positioned.fill(
              child: FocusTraversalGroup(child: Stack(children: _buttons)),
            ),
          ],
        ),
      ),
    );
  }
}

class _EdgeButton extends StatelessWidget {
  const _EdgeButton({
    super.key,
    required this.edge,
    required this.band,
    required this.focus,
    required this.moving,
    required this.onPressed,
  });
  static final _style = ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size.zero),
    padding: const WidgetStatePropertyAll(EdgeInsets.zero),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: const WidgetStatePropertyAll(StadiumBorder()),
    overlayColor: kalinkaOverlay,
    backgroundBuilder: (_, _, child) =>
        InkFocusOutline(shape: const StadiumBorder(), child: child!),
    animationDuration: Duration.zero,
  );

  final FocusNode focus;
  final AxisDirection edge;
  final double band;
  final bool moving;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (edge) {
      AxisDirection.up => (
        Icons.keyboard_arrow_up_rounded,
        'Scroll up one page',
      ),
      AxisDirection.down => (
        Icons.keyboard_arrow_down_rounded,
        'Scroll down one page',
      ),
      AxisDirection.left => (
        Icons.chevron_left_rounded,
        'Scroll left one page',
      ),
      AxisDirection.right => (
        Icons.chevron_right_rounded,
        'Scroll right one page',
      ),
    };
    final vertical = axisDirectionToAxis(edge) == Axis.vertical;
    return Positioned(
      top: edge == AxisDirection.down ? null : 0,
      bottom: edge == AxisDirection.up ? null : 0,
      left: edge == AxisDirection.right ? null : 0,
      right: edge == AxisDirection.left ? null : 0,
      height: vertical ? band : null,
      width: vertical ? null : band,
      child: Center(
        child: SizedBox(
          width: vertical ? 64 : band,
          height: vertical ? band : 64,
          child: IconButton(
            key: ValueKey('dialog-overflow-${edge.name}'),
            focusNode: focus,
            tooltip: label,
            onPressed: onPressed,
            style: _style,
            iconSize: band,
            icon: Icon(
              icon,
              applyTextScaling: false,
              textDirection: TextDirection.ltr,
              color: moving
                  ? KalinkaColors.textMuted
                  : KalinkaColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
