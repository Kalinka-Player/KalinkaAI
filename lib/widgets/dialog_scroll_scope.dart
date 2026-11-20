import 'dart:async';

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shows passive overflow hints on lists inside a popup. Material captures
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
  var _edges = (
    before: false,
    after: false,
    moving: false,
    direction: AxisDirection.down,
  );
  List<Widget> _hints = const [];
  bool _queued = false;

  @override
  void initState() {
    super.initState();
    _refresh();
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
    final overflow =
        p.hasContentDimensions &&
        p.hasViewportDimension &&
        p.hasPixels &&
        p.viewportDimension > 0 &&
        p.maxScrollExtent > p.minScrollExtent;
    final edges = (
      before: overflow && p.extentBefore > precisionErrorTolerance,
      after: overflow && p.extentAfter > precisionErrorTolerance,
      moving: overflow && p.isScrollingNotifier.value,
      direction: widget.direction,
    );
    if (edges == _edges) return;
    _edges = edges;
    // Resizes that leave the same edges visible only reposition the marks.
    _hints = [
      if (edges.before)
        _EdgeHint(
          edge: flipAxisDirection(edges.direction),
          moving: edges.moving,
        ),
      if (edges.after) _EdgeHint(edge: edges.direction, moving: edges.moving),
    ];
    // Offset corrections can arrive during layout. Coalesce them with the
    // final metrics before updating the decoration.
    if (_queued) return;
    _queued = true;
    scheduleMicrotask(() {
      _queued = false;
      if (mounted) setState(() {});
    });
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
          if (n.depth == 0) _refresh();
          return false;
        },
        child: Stack(
          fit: StackFit.passthrough,
          children: [widget.child, ..._hints],
        ),
      ),
    );
  }
}

class _EdgeHint extends StatelessWidget {
  const _EdgeHint({required this.edge, required this.moving});
  final AxisDirection edge;
  final bool moving;

  @override
  Widget build(BuildContext context) {
    final (alignment, icon) = switch (edge) {
      AxisDirection.up => (
        Alignment.topCenter,
        Icons.keyboard_arrow_up_rounded,
      ),
      AxisDirection.down => (
        Alignment.bottomCenter,
        Icons.keyboard_arrow_down_rounded,
      ),
      AxisDirection.left => (Alignment.centerLeft, Icons.chevron_left_rounded),
      AxisDirection.right => (
        Alignment.centerRight,
        Icons.chevron_right_rounded,
      ),
    };
    final vertical = axisDirectionToAxis(edge) == Axis.vertical;
    return Positioned.fill(
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: Align(
            alignment: alignment,
            child: SizedBox(
              key: ValueKey('dialog-overflow-${edge.name}'),
              width: vertical ? 56 : 14,
              height: vertical ? 14 : 56,
              child: FittedBox(
                fit: BoxFit.fill,
                child: Icon(
                  icon,
                  size: 24,
                  applyTextScaling: false,
                  textDirection: TextDirection.ltr,
                  color: moving
                      ? KalinkaColors.textMuted
                      : KalinkaColors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
