import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shared width cap for sheets and the dialogs they become on larger windows.
const double kKalinkaPopupMaxWidth = 640;

/// Match the shell's phone layout, including phones turned on their side.
bool kalinkaUsesPopovers(BuildContext context) {
  final media = MediaQuery.of(context);
  final width = media.size.width - media.padding.horizontal;
  return width >= 720 &&
      width > kKalinkaPopupMaxWidth &&
      media.size.height - media.padding.vertical >= kKalinkaRailMinHeight;
}

/// The control that opened a popup. Follow it while mounted; retain its last
/// bounds when a menu closes before opening another picker.
class KalinkaPopupOrigin {
  static final _actionKey = Object();
  final BuildContext context;
  final KalinkaPopupOrigin? _parent;
  Rect? _lastRect;

  KalinkaPopupOrigin.capture(this.context)
    : _parent = context
          .getInheritedWidgetOfExactType<KalinkaPopupOriginScope>()
          ?.origin {
    resolve();
  }

  /// Shared controls carry their own bounds through synchronous and async
  /// actions, even when the screen's handler supplies its page context.
  static T run<T>(BuildContext context, T Function() action) => runZoned(
    action,
    zoneValues: {_actionKey: KalinkaPopupOrigin.capture(context)},
  );

  static KalinkaPopupOrigin forContext(BuildContext context) =>
      Zone.current[_actionKey] as KalinkaPopupOrigin? ??
      KalinkaPopupOrigin.capture(context);

  Rect? resolve() {
    var active = context.mounted;
    assert(() {
      active = active && (context as Element).debugIsActive;
      return true;
    }());
    if (active) {
      final box = context.findRenderObject();
      if (box is RenderBox && box.attached && box.hasSize) {
        final rect = box.localToGlobal(Offset.zero) & box.size;
        if (rect.isFinite && !rect.isEmpty) _lastRect = rect;
      }
    }
    return active ? _lastRect : _parent?.resolve() ?? _lastRect;
  }
}

/// Carries the launching control through a dialog route, whose builder is
/// outside the original widget tree.
class KalinkaPopupOriginScope extends InheritedWidget {
  final KalinkaPopupOrigin origin;

  const KalinkaPopupOriginScope({
    super.key,
    required this.origin,
    required super.child,
  });

  static KalinkaPopupOrigin? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<KalinkaPopupOriginScope>()
      ?.origin;

  @override
  bool updateShouldNotify(KalinkaPopupOriginScope oldWidget) =>
      origin != oldWidget.origin;
}

/// A screen-sized positioning layer with a bounded, pointed dialog inside.
/// The route or host owns dismissal and its scrim. Content must handle its
/// own scrolling, as it does inside a bottom sheet.
class KalinkaAnchoredSurface extends StatefulWidget {
  final KalinkaPopupOrigin origin;
  final Widget child;
  final double maxWidth;

  const KalinkaAnchoredSurface({
    super.key,
    required this.origin,
    required this.child,
    this.maxWidth = kKalinkaPopupMaxWidth,
  });

  static const surfaceKey = ValueKey('kalinka-popover-surface');

  @override
  State<KalinkaAnchoredSurface> createState() => _KalinkaAnchoredSurfaceState();
}

class _KalinkaAnchoredSurfaceState extends State<KalinkaAnchoredSurface> {
  late Rect? _anchor = widget.origin._lastRect;
  Offset _offset = Offset.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_measure);
  }

  void _measure(Duration _) {
    if (!mounted) return;
    // Transforms can depend on ancestor sizes. Read only after layout, never
    // while a sibling route is being laid out. Observe existing frames without
    // requesting another unless the trigger or the host actually moved.
    final anchor = widget.origin.resolve();
    final box = context.findRenderObject();
    final offset = box is RenderBox && box.attached && box.hasSize
        ? box.localToGlobal(Offset.zero)
        : _offset;
    if (anchor != _anchor || offset != _offset) {
      setState(() {
        _anchor = anchor;
        _offset = offset;
      });
    }
    WidgetsBinding.instance.addPostFrameCallback(_measure);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final media = MediaQuery.of(context);
      final bounds = Rect.fromLTRB(
        media.padding.left + 12,
        media.padding.top + 12,
        math.max(
          media.padding.left + 12,
          constraints.maxWidth - media.padding.right - 12,
        ),
        math.max(
          media.padding.top + 12,
          constraints.maxHeight -
              math.max(media.padding.bottom, media.viewInsets.bottom) -
              12,
        ),
      );
      final layout = _PopoverLayout(
        anchor: _anchor?.shift(-_offset),
        bounds: bounds,
        maxWidth: widget.maxWidth,
      );
      return CustomSingleChildLayout(
        delegate: layout,
        child: Material(
          key: KalinkaAnchoredSurface.surfaceKey,
          color: KalinkaColors.surfaceDialog,
          surfaceTintColor: Colors.transparent,
          elevation: 12,
          shadowColor: Colors.black,
          shape: KalinkaPopoverBorder._(layout),
          animationDuration: Duration.zero,
          clipBehavior: Clip.antiAlias,
          // Constraints are resolved before this builder, including the edge
          // with the pointer. Reserve its space without a seam across its base.
          child: LayoutBuilder(
            builder: (_, _) => KalinkaPopoverContentScope(
              child: Padding(
                padding: layout.pointerPadding,
                child: widget.child,
              ),
            ),
          ),
        ),
      );
    },
  );
}

enum _PointerEdge { top, bottom, left, right, none }

/// Inner cards reuse their dialog's chrome instead of drawing a second border.
class KalinkaPopoverContentScope extends InheritedWidget {
  const KalinkaPopoverContentScope({super.key, required super.child});

  static bool contains(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<KalinkaPopoverContentScope>() !=
      null;

  @override
  bool updateShouldNotify(KalinkaPopoverContentScope oldWidget) => false;
}

const _pointerDepth = 8.0;
const _pointerHalfWidth = 7.0;
const _cornerRadius = 16.0;
const _triggerGap = 4.0;

class _PopoverLayout extends SingleChildLayoutDelegate {
  final Rect? anchor;
  final Rect bounds;
  final double maxWidth;
  _PointerEdge edge = _PointerEdge.none;

  _PopoverLayout({
    required this.anchor,
    required this.bounds,
    required this.maxWidth,
  });

  EdgeInsets get pointerPadding => switch (edge) {
    _PointerEdge.top => const EdgeInsets.only(top: _pointerDepth),
    _PointerEdge.bottom => const EdgeInsets.only(bottom: _pointerDepth),
    _PointerEdge.left => const EdgeInsets.only(left: _pointerDepth),
    _PointerEdge.right => const EdgeInsets.only(right: _pointerDepth),
    _PointerEdge.none => EdgeInsets.zero,
  };

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final anchor = this.anchor;
    // An automatic notice has no calling control. A page-sized context is
    // not a meaningful pointer target either; centre those dialogs.
    if (anchor == null ||
        !bounds.overlaps(anchor) ||
        (anchor.width > bounds.width * 0.9 &&
            anchor.height > bounds.height * 0.6)) {
      edge = _PointerEdge.none;
      return BoxConstraints(
        minWidth: math.min(maxWidth, bounds.width),
        maxWidth: math.min(maxWidth, bounds.width),
        maxHeight: bounds.height,
      );
    }
    final below = math.max(0.0, bounds.bottom - anchor.bottom - _triggerGap);
    final above = math.max(0.0, anchor.top - bounds.top - _triggerGap);
    final right = math.max(0.0, bounds.right - anchor.right - _triggerGap);
    final left = math.max(0.0, anchor.left - bounds.left - _triggerGap);
    final minHeight = math.min(320.0, bounds.height * 0.5);
    // Controls at a side (rail entries, for example) open into the window.
    // Otherwise prefer below/above, leaving the calling control uncovered.
    if (anchor.center.dx < bounds.left + 100 && right >= 320) {
      edge = _PointerEdge.left;
    } else if (anchor.center.dx > bounds.right - 100 && left >= 320) {
      edge = _PointerEdge.right;
    } else if (below >= minHeight) {
      edge = _PointerEdge.top;
    } else if (above >= minHeight) {
      edge = _PointerEdge.bottom;
    } else if (math.max(left, right) >= 320) {
      edge = right >= left ? _PointerEdge.left : _PointerEdge.right;
    } else {
      edge = below >= above ? _PointerEdge.top : _PointerEdge.bottom;
    }
    final width = math.min(maxWidth + pointerPadding.horizontal, switch (edge) {
      _PointerEdge.left => right,
      _PointerEdge.right => left,
      _ => bounds.width,
    });
    final height = switch (edge) {
      _PointerEdge.top => below,
      _PointerEdge.bottom => above,
      _ => bounds.height,
    };
    return BoxConstraints(minWidth: width, maxWidth: width, maxHeight: height);
  }

  Offset position(Size childSize) {
    final anchor = this.anchor;
    if (edge == _PointerEdge.none || anchor == null) {
      return bounds.center - childSize.center(Offset.zero);
    }
    final x = switch (edge) {
      _PointerEdge.left => anchor.right + _triggerGap,
      _PointerEdge.right => anchor.left - childSize.width - _triggerGap,
      _ => anchor.center.dx - childSize.width / 2,
    };
    final y = switch (edge) {
      _PointerEdge.top => anchor.bottom + _triggerGap,
      _PointerEdge.bottom => anchor.top - childSize.height - _triggerGap,
      _ => anchor.center.dy - 28,
    };
    return Offset(
      x.clamp(
        bounds.left,
        math.max(bounds.left, bounds.right - childSize.width),
      ),
      y.clamp(
        bounds.top,
        math.max(bounds.top, bounds.bottom - childSize.height),
      ),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) => position(childSize);

  @override
  bool shouldRelayout(_PopoverLayout oldDelegate) => true;
}

/// Continuous rounded outline, including the beak, with no line at its base.
class KalinkaPopoverBorder extends OutlinedBorder {
  final _PopoverLayout _layout;

  const KalinkaPopoverBorder._(
    this._layout, {
    super.side = const BorderSide(color: KalinkaColors.borderDefault),
  });

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final body = _layout.pointerPadding.deflateRect(rect);
    final rounded = Path()
      ..addRRect(
        RRect.fromRectAndRadius(body, const Radius.circular(_cornerRadius)),
      );
    if (_layout.edge == _PointerEdge.none) return rounded;
    final local = _layout.anchor!.center - _layout.position(rect.size);
    const clearance = _cornerRadius + _pointerHalfWidth;
    final vertical =
        _layout.edge == _PointerEdge.top || _layout.edge == _PointerEdge.bottom;
    final along = vertical
        ? local.dx.clamp(
            body.left + clearance,
            math.max(body.left + clearance, body.right - clearance),
          )
        : local.dy.clamp(
            body.top + clearance,
            math.max(body.top + clearance, body.bottom - clearance),
          );
    final edge = switch (_layout.edge) {
      _PointerEdge.top => body.top,
      _PointerEdge.bottom => body.bottom,
      _PointerEdge.left => body.left,
      _PointerEdge.right => body.right,
      _PointerEdge.none => 0.0,
    };
    final tip = switch (_layout.edge) {
      _PointerEdge.top => rect.top,
      _PointerEdge.bottom => rect.bottom,
      _PointerEdge.left => rect.left,
      _PointerEdge.right => rect.right,
      _PointerEdge.none => 0.0,
    };
    final pointer = Path();
    if (vertical) {
      pointer
        ..moveTo(along - _pointerHalfWidth, edge)
        ..lineTo(along.toDouble(), tip)
        ..lineTo(along + _pointerHalfWidth, edge);
    } else {
      pointer
        ..moveTo(edge, along - _pointerHalfWidth)
        ..lineTo(tip, along.toDouble())
        ..lineTo(edge, along + _pointerHalfWidth);
    }
    pointer.close();
    return Path.combine(PathOperation.union, rounded, pointer);
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect.deflate(side.width), textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) =>
      canvas.drawPath(
        getOuterPath(
          rect.deflate(side.width / 2),
          textDirection: textDirection,
        ),
        side.toPaint(),
      );

  @override
  KalinkaPopoverBorder copyWith({BorderSide? side}) =>
      KalinkaPopoverBorder._(_layout, side: side ?? this.side);

  @override
  ShapeBorder scale(double t) => copyWith(side: side.scale(t));
}
