import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:virtual_keypad/virtual_keypad.dart';

/// Routes the keypad through Flutter's normal editing pipeline, including
/// formatters, onChanged, selection, password masking and submit actions.
///
/// Own this small adapter instead of the package's standalone input control:
/// deletion must respect graphemes, and both signed and decimal input options
/// must survive. The package remains responsible for keys, shift and symbols.
class OnScreenInputControl with TextInputControl {
  OnScreenInputControl({required this.onChanged});

  final VoidCallback onChanged;
  TextInputClient? _client;
  TextInputConfiguration configuration = const TextInputConfiguration();
  bool visible = false;

  TextEditingValue get _value =>
      _client?.currentTextEditingValue ?? TextEditingValue.empty;

  bool get _editable =>
      _client != null &&
      !configuration.readOnly &&
      configuration.inputType != TextInputType.none;

  @override
  void attach(TextInputClient client, TextInputConfiguration configuration) {
    _client = client;
    updateConfig(configuration);
  }

  @override
  void detach(TextInputClient client) {
    if (!identical(client, _client)) return;
    _client = null;
    hide();
  }

  @override
  void updateConfig(TextInputConfiguration configuration) {
    this.configuration = configuration;
    if (!_editable) visible = false;
    onChanged();
  }

  @override
  void show() {
    visible = _editable;
    onChanged();
  }

  @override
  void hide() {
    visible = false;
    onChanged();
  }

  /// Leaving the field commits settings that stage on blur as well as hiding.
  void dismiss() {
    FocusManager.instance.primaryFocus?.unfocus();
    hide();
  }

  TextInputAction get action => switch (configuration.inputAction) {
    TextInputAction.unspecified || TextInputAction.none => TextInputAction.done,
    final action => action,
  };

  /// The toolbar always offers a way to finish, including multiline/numbers.
  void submit() => _client?.performAction(
    action == TextInputAction.newline ? TextInputAction.done : action,
  );

  void onKey(VirtualKey key, String? text) {
    if (!_editable) return;
    if (text != null) {
      _replaceSelection(text);
      return;
    }
    switch (key.action) {
      case KeyAction.backSpace:
        _backspace();
      case KeyAction.space:
        _replaceSelection(' ');
      case KeyAction.enter:
        if (action == TextInputAction.newline) {
          _replaceSelection('\n');
        } else {
          submit();
        }
      case KeyAction.done:
      case KeyAction.go:
      case KeyAction.search:
      case KeyAction.send:
      case KeyAction.call:
      case KeyAction.next:
      case KeyAction.previous:
        submit();
      default:
        // Shift, symbols and language are handled by virtual_keypad.
        break;
    }
  }

  TextSelection _selection(TextEditingValue value) {
    final selection = value.selection;
    if (!selection.isValid || selection.end > value.text.length) {
      return TextSelection.collapsed(offset: value.text.length);
    }
    return selection;
  }

  void _replaceSelection(String text) {
    final value = _value;
    final selection = _selection(value);
    _replace(value, selection.start, selection.end, text);
  }

  void _backspace() {
    final value = _value;
    final selection = _selection(value);
    if (!selection.isCollapsed) {
      _replace(value, selection.start, selection.end, '');
      return;
    }
    if (selection.start == 0) return;
    var start = 0;
    for (final character in value.text.characters) {
      final end = start + character.length;
      if (end >= selection.start) {
        _replace(value, start, end, '');
        return;
      }
      start = end;
    }
  }

  void _replace(TextEditingValue value, int start, int end, String text) {
    TextInput.updateEditingValue(
      TextEditingValue(
        text: value.text.replaceRange(start, end, text),
        selection: TextSelection.collapsed(offset: start + text.length),
      ),
    );
    // Read the client's accepted value on the next key: a formatter may have
    // rejected or transformed this edit, including maxLength enforcement.
  }
}
