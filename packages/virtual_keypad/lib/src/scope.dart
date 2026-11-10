import 'package:flutter/material.dart';
import 'controller.dart';
import 'enums.dart';

/// Manages the connection between [VirtualKeypadTextField] widgets and [VirtualKeypad].
///
/// Wrap your widget tree with [VirtualKeypadScope] to enable automatic
/// keyboard-to-textfield routing. The keyboard automatically detects which
/// text field is focused and sends input to it.
///
/// ```dart
/// VirtualKeypadScope(
///   child: Column(
///     children: [
///       VirtualKeypadTextField(controller: controller1),
///       VirtualKeypadTextField(controller: controller2),
///       VirtualKeypad(),
///     ],
///   ),
/// )
/// ```
class VirtualKeypadScope extends StatefulWidget {
  /// Creates a scope for managing keyboard-textfield connections.
  const VirtualKeypadScope({super.key, required this.child});

  /// The child widget tree containing text fields and keyboard.
  final Widget child;

  /// Gets the [VirtualKeypadScopeState] from the given context.
  ///
  /// Returns null if no [VirtualKeypadScope] is found in the ancestor tree.
  static VirtualKeypadScopeState? of(BuildContext context) {
    return context.findAncestorStateOfType<VirtualKeypadScopeState>();
  }

  @override
  State<VirtualKeypadScope> createState() => VirtualKeypadScopeState();
}

/// State for [VirtualKeypadScope].
///
/// Provides methods for text input routing, selection handling, and
/// active controller management.
class VirtualKeypadScopeState extends State<VirtualKeypadScope> {
  /// Creates the state that routes virtual keyboard input to focused fields.
  VirtualKeypadScopeState();

  VirtualKeypadController? _activeController;
  int? _activeMaxLength;
  KeyboardType _activeKeyboardType = KeyboardType.text;
  TextInputAction _activeInputAction = TextInputAction.done;
  bool _allowPhysicalKeyboard = false;
  final List<VoidCallback> _listeners = [];

  bool Function()? _deleteSelectionCallback;
  (int, int)? Function()? _getSelectionCallback;
  VoidCallback? _clearSelectionCallback;
  ValueChanged<KeyAction>? _onSubmitCallback;

  /// The currently active (focused) text field's controller.
  VirtualKeypadController? get activeController => _activeController;

  /// The max length constraint of the active text field, if any.
  int? get activeMaxLength => _activeMaxLength;

  /// The keyboard type requested by the active text field.
  KeyboardType get activeKeyboardType => _activeKeyboardType;

  /// The input action for the active text field (done, next, search, etc.).
  TextInputAction get activeInputAction => _activeInputAction;

  /// Whether the active text field allows physical keyboard input.
  /// When true, the virtual keyboard should be hidden.
  bool get allowPhysicalKeyboard => _allowPhysicalKeyboard;

  /// Whether a text field is currently focused.
  bool get hasActiveController => _activeController != null;

  /// Adds a listener that's called when the active controller changes.
  void addActiveControllerListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  /// Removes an active controller change listener.
  void removeActiveControllerListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  /// Sets the callback for deleting selected text.
  void setDeleteSelectionCallback(bool Function()? callback) {
    _deleteSelectionCallback = callback;
  }

  /// Sets the callback for getting the current selection range.
  void setGetSelectionCallback((int, int)? Function()? callback) {
    _getSelectionCallback = callback;
  }

  /// Sets the callback for clearing the selection after text replacement.
  void setClearSelectionCallback(VoidCallback? callback) {
    _clearSelectionCallback = callback;
  }

  /// Sets the callback for when the submit/done action is triggered.
  void setOnSubmitCallback(ValueChanged<KeyAction>? callback) {
    _onSubmitCallback = callback;
  }

  void _notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  /// Sets the active controller when a text field gains focus.
  void setActiveController(
    VirtualKeypadController? controller, {
    int? maxLength,
    KeyboardType keyboardType = KeyboardType.text,
    TextInputAction inputAction = TextInputAction.done,
    bool allowPhysicalKeyboard = false,
  }) {
    final changed = _activeController != controller ||
        _activeKeyboardType != keyboardType ||
        _activeInputAction != inputAction ||
        _allowPhysicalKeyboard != allowPhysicalKeyboard;

    if (changed) {
      setState(() {
        _activeController = controller;
        _activeMaxLength = maxLength;
        _activeKeyboardType = keyboardType;
        _activeInputAction = inputAction;
        _allowPhysicalKeyboard = allowPhysicalKeyboard;
      });
      _notifyListeners();
    }
  }

  /// Clears the active controller when focus is lost.
  void clearActiveController() {
    if (_activeController != null) {
      setState(() {
        _activeController = null;
        _activeMaxLength = null;
        _activeKeyboardType = KeyboardType.text;
        _activeInputAction = TextInputAction.done;
        _allowPhysicalKeyboard = false;
      });
      _notifyListeners();
    }
  }

  /// Inserts text into the active text field.
  ///
  /// If there's a selection, replaces the selected text.
  /// Respects maxLength constraints.
  void insertText(String text) {
    if (_activeController != null) {
      final maxLen = _activeMaxLength;

      final selection = _getSelectionCallback?.call();
      if (selection != null) {
        final (start, end) = selection;
        final newLength =
            _activeController!.text.length - (end - start) + text.length;
        if (maxLen != null && newLength > maxLen) return;
        _activeController!.replaceRange(start, end, text);
        _clearSelectionCallback?.call();
        return;
      }

      if (maxLen != null && _activeController!.text.length >= maxLen) return;
      _activeController!.insertText(text);
    }
  }

  /// Deletes the character before the cursor or the selected text.
  void deleteBackward() {
    if (_deleteSelectionCallback != null && _deleteSelectionCallback!()) return;
    _activeController?.deleteBackward();
  }

  /// Clears all text in the active text field.
  void clear() {
    _activeController?.clear();
  }

  /// Triggers the submit/done action for the active text field.
  void submit([KeyAction? action]) {
    _onSubmitCallback?.call(
      action ?? _keyActionForInputAction(_activeInputAction),
    );
  }

  KeyAction _keyActionForInputAction(TextInputAction inputAction) {
    switch (inputAction) {
      case TextInputAction.go:
        return KeyAction.go;
      case TextInputAction.search:
        return KeyAction.search;
      case TextInputAction.send:
        return KeyAction.send;
      case TextInputAction.next:
        return KeyAction.next;
      case TextInputAction.previous:
        return KeyAction.previous;
      default:
        return KeyAction.done;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _VirtualKeypadScopeInherited(state: this, child: widget.child);
  }
}

class _VirtualKeypadScopeInherited extends InheritedWidget {
  const _VirtualKeypadScopeInherited({
    required this.state,
    required super.child,
  });

  final VirtualKeypadScopeState state;

  @override
  bool updateShouldNotify(_VirtualKeypadScopeInherited oldWidget) {
    return state.activeController != oldWidget.state.activeController ||
        state.activeKeyboardType != oldWidget.state.activeKeyboardType ||
        state.activeInputAction != oldWidget.state.activeInputAction ||
        state.allowPhysicalKeyboard != oldWidget.state.allowPhysicalKeyboard;
  }
}
