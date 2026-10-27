import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A scroll controller whose list can be told to hold off loading images, as
/// it does while flung fast: while it jumps past rows nobody will see.
class DeferringScrollController extends ScrollController {
  DeferringScrollController({super.initialScrollOffset});

  bool deferLoading = false;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _DeferringPosition(
    this,
    physics: physics,
    context: context,
    initialPixels: initialScrollOffset,
    keepScrollOffset: keepScrollOffset,
    oldPosition: oldPosition,
    debugLabel: debugLabel,
  );
}

class _DeferringPosition extends ScrollPositionWithSingleContext {
  final DeferringScrollController _owner;

  _DeferringPosition(
    this._owner, {
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  @override
  bool recommendDeferredLoading(BuildContext context) =>
      _owner.deferLoading || super.recommendDeferredLoading(context);
}

/// A thumb at a long list's trailing edge that drags it through everything
/// it holds, loaded yet or not. It shows while the list scrolls and fades a
/// moment after; held, it names where it is when [labelAt] can.
class FastScroller extends StatefulWidget {
  final DeferringScrollController controller;

  /// How many items have loaded, and how many the list holds (negative while
  /// unknown). The thumb spans them all.
  final int loaded;
  final int total;

  /// Asks for the first [count] items, the thumb having gone past those
  /// loaded; 0 once it is back among them.
  final ValueChanged<int> onReach;

  /// What the held thumb says about the item at an index, if anything.
  final String? Function(int index)? labelAt;

  /// Keeps the thumb's track clear of what is pinned over the list.
  final EdgeInsets padding;
  final Widget child;

  const FastScroller({
    super.key,
    required this.controller,
    required this.loaded,
    required this.total,
    required this.onReach,
    required this.child,
    this.labelAt,
    this.padding = EdgeInsets.zero,
  });

  /// Whether lists here get one: Android's have no scrollbar to drag.
  static bool wanted(BuildContext context) =>
      Theme.of(context).platform == TargetPlatform.android;

  @override
  State<FastScroller> createState() => _FastScrollerState();
}

class _FastScrollerState extends State<FastScroller>
    with SingleTickerProviderStateMixin {
  static const _thumbHeight = 48.0;
  static const _touchWidth = 48.0;
  static const _bubbleSize = 56.0;
  static const _restAfter = Duration(milliseconds: 1500);

  late final _shown = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
    reverseDuration: const Duration(milliseconds: 300),
  );
  Timer? _rest;
  bool _held = false;
  bool _reduceMotion = false;

  /// Where on the thumb it was taken, from its top.
  double _grab = 0;

  /// The thumb's place, 0 to 1, while held and until the list has caught up
  /// with it; null while it follows the list.
  double? _fraction;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(FastScroller old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
    // Once what the thumb asked for is laid out, take the list on to it.
    if (_fraction != null && widget.loaded != old.loaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _follow();
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    widget.controller.deferLoading = false;
    _rest?.cancel();
    _shown.dispose();
    super.dispose();
  }

  ScrollPosition? get _position {
    final controller = widget.controller;
    if (controller.positions.length != 1) return null;
    final position = controller.position;
    return position.hasContentDimensions && position.hasViewportDimension
        ? position
        : null;
  }

  double _perItem(ScrollPosition position) =>
      (position.maxScrollExtent + position.viewportDimension) / widget.loaded;

  /// How far the whole list would scroll: what has loaded as laid out, the
  /// rest at the same height per item.
  double _extent(ScrollPosition position) {
    final loaded = widget.loaded;
    if (loaded <= 0 || widget.total <= loaded) return position.maxScrollExtent;
    return position.maxScrollExtent +
        (widget.total - loaded) * _perItem(position);
  }

  /// Only a list several screens long has a thumb.
  bool _long(ScrollPosition position) =>
      _extent(position) >= 3 * position.viewportDimension;

  double _fractionOf(ScrollPosition position) {
    final extent = _extent(position);
    return extent <= 0 ? 0 : (position.pixels / extent).clamp(0.0, 1.0);
  }

  void _onScroll() {
    final position = _position;
    if (position == null || !_long(position)) return;
    _show();
    if (!_held) _restSoon();
  }

  void _show() {
    _rest?.cancel();
    if (_reduceMotion) {
      _shown.value = 1;
    } else {
      _shown.forward();
    }
  }

  void _restSoon() {
    _rest?.cancel();
    _rest = Timer(_restAfter, () {
      if (!mounted || _held) return;
      if (_reduceMotion) {
        _shown.value = 0;
      } else {
        _shown.reverse();
      }
    });
  }

  void _hold(DragStartDetails details) {
    final position = _position;
    if (position == null) return;
    _grab = details.localPosition.dy;
    widget.controller.deferLoading = true;
    setState(() {
      _held = true;
      _fraction = _fractionOf(position);
    });
    _show();
  }

  void _drag(DragUpdateDetails details, double travel) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !_held) return;
    final top =
        box.globalToLocal(details.globalPosition).dy -
        widget.padding.top -
        _grab;
    setState(() {
      _fraction = travel <= 0 ? 0 : (top / travel).clamp(0.0, 1.0);
    });
    _follow();
  }

  void _release() {
    if (!_held) return;
    widget.controller.deferLoading = false;
    setState(() => _held = false);
    _follow();
    _restSoon();
  }

  /// Takes the list to the thumb, as far as it has loaded, asking for the
  /// items up to the thumb when it is past them.
  void _follow() {
    final position = _position;
    final fraction = _fraction;
    if (position == null || fraction == null) return;
    final target = fraction * _extent(position);
    final short =
        target > position.maxScrollExtent && widget.loaded < widget.total;
    // Asked first, so the load the jump sets off is already the whole way.
    widget.onReach(
      short
          ? ((target + position.viewportDimension) / _perItem(position)).ceil()
          : 0,
    );
    position.jumpTo(math.min(target, position.maxScrollExtent));
    if (!short && !_held) {
      setState(() => _fraction = null);
    }
  }

  /// What the held thumb says: the item at the list's top once it is there.
  String? _label(ScrollPosition position, double fraction) {
    final labelAt = widget.labelAt;
    final count = widget.total >= 0 ? widget.total : widget.loaded;
    if (labelAt == null || count <= 0) return null;
    final extent = _extent(position);
    final perItem = (extent + position.viewportDimension) / count;
    return labelAt((fraction * extent / perItem).floor().clamp(0, count - 1));
  }

  @override
  Widget build(BuildContext context) {
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    return NotificationListener<ScrollStartNotification>(
      // Scrolled by hand, the list no longer heads where the thumb was left.
      onNotification: (notification) {
        if (notification.depth == 0 &&
            notification.dragDetails != null &&
            !_held &&
            _fraction != null) {
          _fraction = null;
          widget.onReach(0);
        }
        return false;
      },
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          Positioned.fill(
            child: Padding(
              padding: widget.padding,
              child: LayoutBuilder(
                builder: (context, constraints) => ListenableBuilder(
                  listenable: Listenable.merge([widget.controller, _shown]),
                  builder: (context, _) => _thumb(constraints.maxHeight),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumb(double trackHeight) {
    final position = _position;
    // Kept while held, so the drag is never dropped under the finger.
    if (position == null ||
        (!_held && (_shown.value == 0 || !_long(position)))) {
      return const SizedBox.shrink();
    }
    final travel = math.max(0.0, trackHeight - _thumbHeight);
    final fraction = _fraction ?? _fractionOf(position);
    final top = fraction * travel;
    final label = _held ? _label(position, fraction) : null;
    return ExcludeSemantics(
      child: Opacity(
        opacity: _shown.value,
        child: Stack(
          children: [
            Positioned(
              right: 0,
              top: top,
              width: _touchWidth,
              height: _thumbHeight,
              child: GestureDetector(
                key: const ValueKey('fast-scroll-thumb'),
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: _hold,
                onVerticalDragUpdate: (details) => _drag(details, travel),
                onVerticalDragEnd: (_) => _release(),
                onVerticalDragCancel: _release,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: _held ? 8 : 5,
                    height: _thumbHeight,
                    margin: const EdgeInsets.only(right: 3),
                    decoration: BoxDecoration(
                      color: _held
                          ? KalinkaColors.textSecondary
                          : KalinkaColors.textMuted,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
            if (label != null)
              Positioned(
                right: _touchWidth + 8,
                top: (top + (_thumbHeight - _bubbleSize) / 2).clamp(
                  0.0,
                  math.max(0.0, trackHeight - _bubbleSize),
                ),
                child: IgnorePointer(child: _Bubble(label)),
              ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final String label;

  const _Bubble(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _FastScrollerState._bubbleSize,
      height: _FastScrollerState._bubbleSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: KalinkaColors.surfaceOverlay,
        shape: BoxShape.circle,
        border: Border.all(color: KalinkaColors.borderDefault),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: KalinkaFonts.sans(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: KalinkaColors.textPrimary,
        ),
      ),
    );
  }
}
