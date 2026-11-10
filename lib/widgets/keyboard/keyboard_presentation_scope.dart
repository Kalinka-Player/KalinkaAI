import 'package:flutter/widgets.dart';

/// Lets the shell clear its mini-player before the keyboard starts rising.
/// This is transient presentation state, separate from the saved preference.
class KeyboardPresentationController {
  bool _active = false;
  bool get active => _active;
  Future<void> Function(bool)? _onVisibilityChanged;

  void attach(Future<void> Function(bool) onVisibilityChanged) {
    _onVisibilityChanged = onVisibilityChanged;
  }

  void detach(Future<void> Function(bool) onVisibilityChanged) {
    if (_onVisibilityChanged == onVisibilityChanged) {
      _onVisibilityChanged = null;
    }
  }

  Future<void> setActive(bool active) async {
    if (_active == active) return;
    _active = active;
    await _onVisibilityChanged?.call(active);
  }
}

class KeyboardPresentationScope extends InheritedWidget {
  const KeyboardPresentationScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final KeyboardPresentationController controller;

  static KeyboardPresentationController? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<KeyboardPresentationScope>()
          ?.controller;

  @override
  bool updateShouldNotify(KeyboardPresentationScope oldWidget) =>
      controller != oldWidget.controller;
}
