import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A mouse's Ctrl- or ⌘-click does what a long press does on touch, on
/// desktop and web alike. It is claimed as the button goes down, so a plain
/// click is never held back: no double-click to wait out before a row opens.
/// Controls inside that act on their own click wrap themselves in
/// [ClickAtOnce], so a modified click on them is theirs.
class ModifierClick extends StatefulWidget {
  /// Null where a long press does nothing either.
  final VoidCallback? onModifiedClick;
  final Widget child;

  const ModifierClick({
    super.key,
    required this.onModifiedClick,
    required this.child,
  });

  @override
  State<ModifierClick> createState() => _ModifierClickState();
}

class _ModifierClickState extends State<ModifierClick> {
  final _atOnce = <int>{};

  @override
  Widget build(BuildContext context) {
    // Kept while disabled, so toggling never remounts the child; without a
    // handler the recognizer takes no pointer.
    return _ModifierClickScope(
      atOnce: _atOnce,
      child: RawGestureDetector(
        gestures: {
          _ModifiedClick: GestureRecognizerFactoryWithHandlers<_ModifiedClick>(
            () => _ModifiedClick(_atOnce),
            (recognizer) => recognizer.onClick = widget.onModifiedClick,
          ),
        },
        child: widget.child,
      ),
    );
  }
}

/// A primary click with Ctrl or ⌘ held, won as it goes down so the row's own
/// tap never fires for it.
class _ModifiedClick extends OneSequenceGestureRecognizer {
  final Set<int> atOnce;
  VoidCallback? onClick;
  Offset? _down;

  _ModifiedClick(this.atOnce)
    : super(supportedDevices: const {PointerDeviceKind.mouse});

  static bool get _modified =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      !atOnce.remove(event.pointer) &&
      onClick != null &&
      event.buttons == kPrimaryMouseButton &&
      _modified &&
      super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _down = event.position;
    resolve(GestureDisposition.accepted);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent) {
      stopTrackingPointer(event.pointer);
      invokeCallback<void>('onClick', () => onClick?.call());
    } else if (event is PointerCancelEvent ||
        (event is PointerMoveEvent &&
            (event.position - _down!).distance > kTouchSlop)) {
      // Dragged off: no click.
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'modified click';
}

class _ModifierClickScope extends InheritedWidget {
  final Set<int> atOnce;

  const _ModifierClickScope({required this.atOnce, required super.child});

  @override
  bool updateShouldNotify(_ModifierClickScope oldWidget) =>
      atOnce != oldWidget.atOnce;
}

/// A control inside a [ModifierClick] region that keeps its own click, a
/// modified one included, rather than giving it to the region.
class ClickAtOnce extends StatelessWidget {
  final Widget child;

  const ClickAtOnce({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final atOnce = context
        .getInheritedWidgetOfExactType<_ModifierClickScope>()
        ?.atOnce;
    if (atOnce == null) return child;
    // Pointer-down reaches this before the region's own recognizer, which
    // then lets the pointer pass.
    return Listener(
      onPointerDown: (event) => atOnce.add(event.pointer),
      child: child,
    );
  }
}
