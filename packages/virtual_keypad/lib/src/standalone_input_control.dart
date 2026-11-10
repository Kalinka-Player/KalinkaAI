import 'package:flutter/services.dart';
import 'enums.dart';

/// A [TextInputControl] that intercepts Flutter's text input system,
/// allowing [VirtualKeypad] to work with any standard [TextField] or
/// [TextFormField] without requiring [VirtualKeypadScope].
///
/// Used internally when `VirtualKeypad(standalone: true)`.
class StandaloneInputControl with TextInputControl {
  /// Called when a text field requests the keyboard to show.
  final VoidCallback? onShow;

  /// Called when a text field requests the keyboard to hide.
  final VoidCallback? onHide;

  /// Creates a text input control that routes system keyboard show and hide
  /// requests to a [VirtualKeypad] instead of the platform software keyboard.
  StandaloneInputControl({this.onShow, this.onHide});

  TextEditingValue _currentValue = TextEditingValue.empty;
  TextInputConfiguration? _configuration;
  TextInputClient? _client;
  bool _attached = false;

  /// The current text editing value of the focused field.
  TextEditingValue get currentValue => _currentValue;

  /// The input configuration of the focused field.
  TextInputConfiguration? get configuration => _configuration;

  /// Whether a text input client is currently attached.
  bool get isAttached => _attached;

  /// Derives a [KeyboardType] from the attached field's [TextInputType].
  KeyboardType get keyboardType => _toKeyboardType(_configuration?.inputType);

  /// The input action from the attached field's configuration.
  TextInputAction get inputAction =>
      _configuration?.inputAction ?? TextInputAction.done;

  /// Performs an input action (e.g. done, go, search) on the active client.
  void performAction(TextInputAction action) => _client?.performAction(action);

  @override
  void attach(TextInputClient client, TextInputConfiguration configuration) {
    if (configuration.readOnly) return;
    _client = client;
    _currentValue = client.currentTextEditingValue ?? TextEditingValue.empty;
    _configuration = configuration;
    _attached = true;
  }

  @override
  void detach(TextInputClient client) {
    _client = null;
    _configuration = null;
    _attached = false;
  }

  @override
  void show() {
    if (!_attached) return;
    onShow?.call();
  }

  @override
  void hide() {
    onHide?.call();
  }

  @override
  void setEditingState(TextEditingValue value) {
    _currentValue = value;
  }

  /// Inserts [text] at the current cursor/selection position.
  void insertText(String text) {
    final sel = _currentValue.selection;
    final start = sel.start.clamp(0, _currentValue.text.length);
    final end = sel.end.clamp(0, _currentValue.text.length);

    final newText = _currentValue.text.replaceRange(start, end, text);
    final newOffset = start + text.length;

    _updateEditingValue(newText, newOffset);
  }

  /// Deletes the character before the cursor, or deletes the selection.
  void deleteBackward() {
    final sel = _currentValue.selection;

    if (sel.isCollapsed && sel.start > 0) {
      final start = sel.start - 1;
      final newText = _currentValue.text.replaceRange(start, sel.end, '');
      _updateEditingValue(newText, start);
    } else if (!sel.isCollapsed) {
      final newText = _currentValue.text.replaceRange(sel.start, sel.end, '');
      _updateEditingValue(newText, sel.start);
    }
  }

  /// Submits the current input (triggers the input action).
  void submit() {
    performAction(inputAction);
  }

  void _updateEditingValue(String newText, int offset) {
    final newValue = _currentValue.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: offset),
      composing: TextRange.collapsed(offset),
    );
    _currentValue = newValue;
    TextInput.updateEditingValue(newValue);
  }

  static KeyboardType _toKeyboardType(TextInputType? type) {
    if (type == TextInputType.text) return KeyboardType.text;
    if (type == TextInputType.multiline) return KeyboardType.multiline;
    if (type == TextInputType.number) return KeyboardType.number;
    if (type == const TextInputType.numberWithOptions(signed: true)) {
      return KeyboardType.numberSigned;
    }
    if (type == const TextInputType.numberWithOptions(decimal: true)) {
      return KeyboardType.numberDecimal;
    }
    if (type == TextInputType.phone) return KeyboardType.phone;
    if (type == TextInputType.datetime) return KeyboardType.datetime;
    if (type == TextInputType.emailAddress) return KeyboardType.emailAddress;
    if (type == TextInputType.url) return KeyboardType.url;
    if (type == TextInputType.visiblePassword) {
      return KeyboardType.visiblePassword;
    }
    if (type == TextInputType.name) return KeyboardType.name;
    if (type == TextInputType.streetAddress) return KeyboardType.streetAddress;
    if (type == TextInputType.none) return KeyboardType.none;
    return KeyboardType.text;
  }
}
