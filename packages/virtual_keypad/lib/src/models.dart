import 'package:flutter/widgets.dart';

import 'theme.dart';
import 'enums.dart';

/// Represents a single key on the virtual keyboard or keypad.
///
/// Use [VirtualKey.character] for keys that insert text, or [VirtualKey.action]
/// for special function keys like backspace, enter, and shift.
class VirtualKey {
  /// Creates a character key that inserts text.
  ///
  /// - [text]: The character to insert (and display in lowercase mode).
  /// - [capsText]: Optional uppercase variant. Defaults to `text.toUpperCase()`.
  /// - [flex]: Relative width of the key. Default is 1.
  VirtualKey.character({required this.text, String? capsText, this.flex = 1.0})
      : capsText = capsText ?? text?.toUpperCase(),
        keyType = KeyType.character,
        action = null,
        label = null,
        altLabel = null;

  /// Creates an action key that performs a keyboard function.
  ///
  /// - [action]: The action this key performs.
  /// - [text]: Optional display text for the key.
  /// - [label]: Label shown when on primary layout (e.g., "123" for symbols).
  /// - [altLabel]: Label shown when on secondary layout (e.g., "কখ" for Bengali).
  /// - [flex]: Relative width of the key. Default is 1.
  VirtualKey.action({
    required KeyAction this.action,
    this.text,
    this.label,
    this.altLabel,
    this.flex = 1.0,
  })  : capsText = null,
        keyType = KeyType.action;

  /// The primary text character for this key.
  final String? text;

  /// The uppercase/shifted text for this key.
  final String? capsText;

  /// Whether this is a character or action key.
  final KeyType keyType;

  /// The action for action keys, null for character keys.
  final KeyAction? action;

  /// Label for action keys when on primary layout.
  /// For example, "123" on the symbols button.
  final String? label;

  /// Alternate label for action keys when on non-primary layout.
  /// For example, "কখ" for Bengali, "ABC" for English.
  final String? altLabel;

  /// Relative width multiplier for the key. A flex of 2 means twice the width.
  /// Supports fractional values like 1.5 for fine-grained sizing.
  final double flex;

  /// Returns true if this is a character key.
  bool get isCharacter => keyType == KeyType.character;

  /// Returns true if this is an action key.
  bool get isAction => keyType == KeyType.action;

  /// Gets the text to display on the key.
  String getDisplayText({bool shift = false, bool capsLock = false}) {
    if (keyType == KeyType.action) return '';
    if (shift || capsLock) return capsText ?? text?.toUpperCase() ?? '';
    return text ?? '';
  }

  /// Gets the text to insert when this key is pressed.
  String getInsertText({bool shift = false, bool capsLock = false}) {
    if (keyType == KeyType.action) {
      switch (action) {
        case KeyAction.space:
          return ' ';
        case KeyAction.enter:
          return '\n';
        default:
          return '';
      }
    }
    if (shift || capsLock) return capsText ?? text?.toUpperCase() ?? '';
    return text ?? '';
  }

  @override
  String toString() =>
      'VirtualKey(type: $keyType, text: $text, action: $action)';
}

/// A row of keys in a keyboard layout.
typedef KeyRow = List<VirtualKey>;

/// A complete keyboard layout consisting of multiple rows.
typedef KeyboardLayout = List<KeyRow>;

/// What a [VirtualKeypadKeyBuilder] is told about the key it is drawing.
///
/// {@category Theming}
class VirtualKeyContext {
  /// Creates the context handed to a key builder.
  const VirtualKeyContext({
    required this.key,
    required this.label,
    required this.shift,
    required this.capsLock,
    required this.isFocused,
    required this.theme,
  });

  /// The key being drawn, including its [VirtualKey.text] and
  /// [VirtualKey.action].
  final VirtualKey key;

  /// The text this key would show, with shift and caps lock already applied.
  ///
  /// `null` for a key the package draws as an icon, such as backspace or enter.
  final String? label;

  /// Whether shift is currently held.
  final bool shift;

  /// Whether caps lock is currently on.
  final bool capsLock;

  /// Whether this key is the current D-pad target and is being highlighted.
  final bool isFocused;

  /// The theme in force, so a builder can follow it instead of hard-coding.
  final VirtualKeypadTheme theme;
}

/// Draws the content of a single key.
///
/// Return `null` to let the package draw that key normally, which is what makes
/// it practical to override one key and leave the rest alone.
///
/// This controls the key's *content* only. Its background, size, tap handling,
/// repeat, D-pad focus and accessibility stay with the package, so a builder
/// cannot accidentally break the keyboard's behaviour.
///
/// {@category Theming}
typedef VirtualKeypadKeyBuilder = Widget? Function(
    BuildContext context, VirtualKeyContext info);

/// Presents the resolved accent options and returns the selected character.
/// The position is in global coordinates. Return null to cancel.
typedef VirtualKeypadAccentPicker = Future<String?> Function(
    BuildContext context, List<String> options, Offset position);

/// Presents language codes and returns a chosen code, or null to cancel.
typedef VirtualKeypadLanguagePicker = Future<String?> Function(
    BuildContext context,
    List<String> codes,
    String selectedCode,
    Offset position);
