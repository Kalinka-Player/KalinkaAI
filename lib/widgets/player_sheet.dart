import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'player_queue_view.dart';

/// The phone player: a full-height sheet whose content slides while the
/// queue's mini-player stays put over its foot, where Home's own sits, so
/// closing the queue leaves the bar in place.
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
                  child: FractionalTranslation(
                    translation: Offset(0, 1 - t),
                    child: child,
                  ),
                ),
                if (_controller.isCompleted && topInset > 0)
                  Positioned(
                    top: 0,
                    left: 0,
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
              child: SafeArea(top: false, bottom: false, child: widget.child),
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
