import 'package:flutter/material.dart';

/// A controller for [VirtualKeypadTextField] that provides text manipulation methods.
///
/// Extends [TextEditingController] with methods for inserting text, deleting
/// characters, and managing cursor position. Works seamlessly with the virtual
/// keyboard input system.
///
/// ```dart
/// final controller = VirtualKeypadController();
/// controller.insertText('Hello');
/// print(controller.text); // 'Hello'
/// print(controller.cursorPosition); // 5
/// ```
class VirtualKeypadController extends TextEditingController {
  /// Creates a controller with optional initial text.
  VirtualKeypadController({super.text});

  /// The current cursor position (caret offset).
  ///
  /// Returns the selection base offset if the selection is collapsed,
  /// otherwise returns the text length.
  int get cursorPosition {
    if (selection.isValid && selection.isCollapsed) {
      return selection.baseOffset;
    }
    return text.length;
  }

  /// Sets the cursor position.
  ///
  /// The position is clamped to valid bounds `[0, text.length]`.
  set cursorPosition(int position) {
    final clampedPos = position.clamp(0, text.length);
    selection = TextSelection.collapsed(offset: clampedPos);
  }

  /// Inserts text at the current cursor position.
  ///
  /// If text is selected, replaces the selection with the new text.
  /// The cursor moves to the end of the inserted text.
  void insertText(String newText) {
    final sel = selection;

    // If there's a valid selection, replace it
    if (sel.isValid && !sel.isCollapsed) {
      replaceRange(sel.start, sel.end, newText);
      return;
    }

    final pos = cursorPosition;
    final before = text.substring(0, pos);
    final after = text.substring(pos);
    final newCursorPos = pos + newText.length;

    value = TextEditingValue(
      text: before + newText + after,
      selection: TextSelection.collapsed(offset: newCursorPos),
    );
  }

  /// Deletes the character before the cursor (backspace).
  ///
  /// If text is selected, deletes the entire selection.
  /// Otherwise, deletes the character before the cursor.
  /// Does nothing if the cursor is at position 0 and no selection.
  void deleteBackward() {
    final sel = selection;

    // If there's a valid selection, delete it
    if (sel.isValid && !sel.isCollapsed) {
      deleteRange(sel.start, sel.end);
      return;
    }

    final pos = cursorPosition;
    if (pos > 0 && text.isNotEmpty) {
      final before = text.substring(0, pos - 1);
      final after = text.substring(pos);
      final newCursorPos = pos - 1;

      value = TextEditingValue(
        text: before + after,
        selection: TextSelection.collapsed(offset: newCursorPos),
      );
    }
  }

  /// Deletes the character after the cursor (delete).
  ///
  /// Does nothing if the cursor is at the end of the text.
  void deleteForward() {
    final pos = cursorPosition;
    if (pos < text.length && text.isNotEmpty) {
      final before = text.substring(0, pos);
      final after = text.substring(pos + 1);

      value = TextEditingValue(
        text: before + after,
        selection: TextSelection.collapsed(offset: pos),
      );
    }
  }

  /// Clears all text and resets the cursor to position 0.
  @override
  void clear() {
    value = const TextEditingValue(
      text: '',
      selection: TextSelection.collapsed(offset: 0),
    );
  }

  /// Moves the cursor one position to the left.
  void moveCursorLeft() {
    final pos = cursorPosition;
    if (pos > 0) {
      selection = TextSelection.collapsed(offset: pos - 1);
    }
  }

  /// Moves the cursor one position to the right.
  void moveCursorRight() {
    final pos = cursorPosition;
    if (pos < text.length) {
      selection = TextSelection.collapsed(offset: pos + 1);
    }
  }

  /// Moves the cursor to the end of the text.
  void moveCursorToEnd() {
    selection = TextSelection.collapsed(offset: text.length);
  }

  /// Moves the cursor to the beginning of the text.
  void moveCursorToStart() {
    selection = const TextSelection.collapsed(offset: 0);
  }

  /// Selects all text in the field.
  ///
  /// Does nothing if the text is empty.
  void selectAll() {
    if (text.isNotEmpty) {
      selection = TextSelection(baseOffset: 0, extentOffset: text.length);
    }
  }

  /// Deletes text in the specified range [start, end).
  ///
  /// The cursor is placed at the start position after deletion.
  void deleteRange(int start, int end) {
    if (start < 0 || end > text.length || start >= end) return;

    final before = text.substring(0, start);
    final after = text.substring(end);

    value = TextEditingValue(
      text: before + after,
      selection: TextSelection.collapsed(offset: start),
    );
  }

  /// Replaces text in the range [start, end) with [replacement].
  ///
  /// The cursor is placed at the end of the replacement text.
  void replaceRange(int start, int end, String replacement) {
    if (start < 0 || end > text.length || start > end) return;

    final before = text.substring(0, start);
    final after = text.substring(end);
    final newCursorPos = start + replacement.length;

    value = TextEditingValue(
      text: before + replacement + after,
      selection: TextSelection.collapsed(offset: newCursorPos),
    );
  }
}
