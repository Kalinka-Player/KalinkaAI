import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'player_queue_view.dart';

/// The phone player: a full-height sheet whose content slides while the
/// queue's mini-player stays put over its foot, where Home's own sits, so
/// closing the queue leaves the bar in place. Beside a navigation rail it
/// leaves the rail in view and in reach, all but the foot the bar spans.
class PlayerSheetRoute extends PopupRoute<void> {
  PlayerSheetRoute({required this.builder, required this.themes});

  final WidgetBuilder builder;

  /// Themes from where the sheet was opened, as showModalBottomSheet keeps.
  final CapturedThemes themes;

  AnimationController get _controller => controller!;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  @override
  Widget buildModalBarrier() => Builder(
    builder: (context) => Padding(
      padding: EdgeInsets.only(left: _railWidth(context)),
      child: super.buildModalBarrier(),
    ),
  );

  @override
  Duration get transitionDuration => const Duration(milliseconds: 250);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 200);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return themes.wrap(
      _PlayerSheetPage(
        route: this,
        child: Builder(builder: builder),
      ),
    );
  }
}

/// The window's navigation rail, which the sheet opens beside.
double _railWidth(BuildContext context) => kalinkaRailEdge(context);

class _PlayerSheetPage extends StatefulWidget {
  final PlayerSheetRoute route;
  final Widget child;

  const _PlayerSheetPage({required this.route, required this.child});

  @override
  State<_PlayerSheetPage> createState() => _PlayerSheetPageState();
}

class _PlayerSheetPageState extends State<_PlayerSheetPage> {
  static const _curve = Curves.easeOutCubic;
  static const _flingVelocity = 700.0;

  /// The sheet follows the finger 1:1 from a drag until it settles.
  bool _linear = false;

  AnimationController get _controller => widget.route._controller;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener(_onStatus);
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onStatus);
    super.dispose();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _linear) {
      setState(() => _linear = false);
    }
  }

  void _onDragStart(DragStartDetails _) {
    if (_linear) return;
    // Keep the sheet where the eased animation has it.
    _controller.value = _curve.transform(_controller.value);
    setState(() => _linear = true);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final height =
        (context.size?.height ?? 0) - MediaQuery.paddingOf(context).top;
    if (height <= 0) return;
    _controller.value -= details.primaryDelta! / height;
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final close = velocity > _flingVelocity
        ? true
        : velocity < -_flingVelocity
        ? false
        : _controller.value < 0.5;
    if (close) {
      Navigator.of(context).pop();
    } else {
      _controller.forward();
    }
  }

  void _onDragCancel() => _controller.forward();

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final rail = _railWidth(context);
    return _SheetDragScope(
      onStart: _onDragStart,
      onUpdate: _onDragUpdate,
      onEnd: _onDragEnd,
      onCancel: _onDragCancel,
      // Text outside the sliding sheet needs a Material too.
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final t = _linear
                ? _controller.value
                : _curve.transform(_controller.value);
            return Stack(
              fit: StackFit.expand,
              children: [
                // Keep the status inset outside the moving surface, so no
                // empty strip travels ahead of the drag handle.
                Positioned.fill(
                  top: topInset,
                  left: rail,
                  child: FractionalTranslation(
                    translation: Offset(0, 1 - t),
                    child: child,
                  ),
                ),
                if (_controller.isCompleted && topInset > 0)
                  Positioned(
                    top: 0,
                    left: rail,
                    right: 0,
                    height: topInset,
                    child: const AnnotatedRegion<SystemUiOverlayStyle>(
                      value: SystemUiOverlayStyle(
                        statusBarColor: Colors.transparent,
                        statusBarIconBrightness: Brightness.light,
                        statusBarBrightness: Brightness.dark,
                        systemStatusBarContrastEnforced: false,
                      ),
                      child: ColoredBox(color: KalinkaColors.background),
                    ),
                  ),
                // Exactly where Home's sits, under the rail too.
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: QueueMiniPlayer(),
                ),
              ],
            );
          },
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: Material(
              color: KalinkaColors.background,
              // Beside the rail it is already past the left inset.
              child: SafeArea(
                top: false,
                bottom: false,
                left: rail == 0,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetDragScope extends InheritedWidget {
  final GestureDragStartCallback onStart;
  final GestureDragUpdateCallback onUpdate;
  final GestureDragEndCallback onEnd;
  final GestureDragCancelCallback onCancel;

  const _SheetDragScope({
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
    required super.child,
  });

  @override
  bool updateShouldNotify(_SheetDragScope old) => false;
}

/// Lets its child drag the phone player's sheet. Only what opts in drags it,
/// so the queue's list scrolls; outside the sheet it is the bare child.
class SheetDragArea extends StatelessWidget {
  final Widget child;

  const SheetDragArea({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_SheetDragScope>();
    if (scope == null) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onVerticalDragStart: scope.onStart,
      onVerticalDragUpdate: scope.onUpdate,
      onVerticalDragEnd: scope.onEnd,
      onVerticalDragCancel: scope.onCancel,
      child: child,
    );
  }
}

/// Builds a scrollable that, on the phone sheet, hands a pull down from its
/// top to the sheet, so the sheet still closes from content that scrolls.
/// Pushing back up returns the sheet before the content scrolls. Outside the
/// sheet the physics are plain clamping.
class SheetScrollArea extends StatefulWidget {
  final Widget Function(BuildContext context, ScrollPhysics physics) builder;

  const SheetScrollArea({super.key, required this.builder});

  @override
  State<SheetScrollArea> createState() => _SheetScrollAreaState();
}

class _SheetScrollAreaState extends State<SheetScrollArea> {
  _SheetDragScope? _scope;
  late final _physics = _SheetHandoffPhysics(this);

  /// How far this drag has moved the sheet down.
  double _pulled = 0;
  bool _dragging = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope = context.dependOnInheritedWidgetOfExactType<_SheetDragScope>();
  }

  /// Takes what of [offset] (positive as the finger moves down) belongs to
  /// the sheet, returning what is left for the content.
  double _take(double offset, ScrollMetrics position) {
    final scope = _scope;
    if (scope == null) return offset;
    final double toSheet;
    if (_pulled > 0) {
      // Back up to fully open at most; the rest scrolls the content.
      toSheet = math.max(offset, -_pulled);
    } else if (offset > 0) {
      // What the content cannot take above its top.
      toSheet = math.max(
        0.0,
        offset - (position.pixels - position.minScrollExtent),
      );
    } else {
      return offset;
    }
    if (toSheet == 0) return offset;
    if (!_dragging) {
      _dragging = true;
      scope.onStart(DragStartDetails());
    }
    _pulled += toSheet;
    scope.onUpdate(
      DragUpdateDetails(
        globalPosition: Offset.zero,
        delta: Offset(0, toSheet),
        primaryDelta: toSheet,
      ),
    );
    return offset - toSheet;
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 ||
        notification is! ScrollEndNotification ||
        !_dragging) {
      return false;
    }
    _dragging = false;
    _pulled = 0;
    final velocity = notification.dragDetails?.primaryVelocity ?? 0;
    _scope?.onEnd(
      DragEndDetails(
        velocity: Velocity(pixelsPerSecond: Offset(0, velocity)),
        primaryVelocity: velocity,
      ),
    );
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: widget.builder(
          context,
          _scope == null ? const ClampingScrollPhysics() : _physics,
        ),
      );
}

class _SheetHandoffPhysics extends ClampingScrollPhysics {
  final _SheetScrollAreaState _area;

  const _SheetHandoffPhysics(this._area, {super.parent});

  @override
  _SheetHandoffPhysics applyTo(ScrollPhysics? ancestor) =>
      _SheetHandoffPhysics(_area, parent: buildParent(ancestor));

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) =>
      super.applyPhysicsToUserOffset(position, _area._take(offset, position));

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) => _area._dragging
      ? null
      : super.createBallisticSimulation(position, velocity);
}
