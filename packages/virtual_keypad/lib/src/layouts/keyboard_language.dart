import '../models.dart';

/// A complete set of keyboard layouts for a specific input type.
///
/// Contains primary (letters), secondary (numbers/symbols), and
/// tertiary (more symbols) layouts that the keyboard cycles through.
class KeyboardLayoutSet {
  /// Creates a layout set with required primary and optional secondary/tertiary.
  const KeyboardLayoutSet({
    required this.primary,
    this.secondary,
    this.tertiary,
  });

  /// Creates a simple layout set with only a primary layout (e.g., number pad).
  const KeyboardLayoutSet.single(this.primary)
      : secondary = null,
        tertiary = null;

  /// The primary layout (usually letters or main input).
  final KeyboardLayout primary;

  /// The secondary layout (usually numbers and common symbols).
  final KeyboardLayout? secondary;

  /// The tertiary layout (usually additional symbols).
  final KeyboardLayout? tertiary;

  /// Whether this set has multiple layouts to cycle through.
  bool get hasMultipleLayouts => secondary != null;
}

/// Defines all keyboard layouts for a specific language.
///
/// Each language provides layouts for different input types (text, email, etc.).
/// This allows the keyboard to switch layouts based on both the active input type
/// and the selected language.
///
/// Example:
/// ```dart
/// final english = KeyboardLanguage(
///   code: 'en',
///   name: 'English',
///   nativeName: 'English',
///   textLayouts: KeyboardLayoutSet(
///     primary: qwertyLayout,
///     secondary: numbersLayout,
///     tertiary: symbolsLayout,
///   ),
///   emailLayouts: KeyboardLayoutSet(
///     primary: emailQwertyLayout, // with @ on first page
///     secondary: numbersLayout,
///     tertiary: symbolsLayout,
///   ),
/// );
/// ```
class KeyboardLanguage {
  /// Creates a keyboard language definition.
  const KeyboardLanguage({
    required this.code,
    required this.name,
    required this.nativeName,
    required this.textLayouts,
    this.emailLayouts,
    this.urlLayouts,
    this.numberLayouts,
    this.numberSignedLayouts,
    this.numberDecimalLayouts,
    this.phoneLayouts,
    this.isRTL = false,
  });

  /// ISO 639-1 language code (e.g., 'en', 'bn', 'ar').
  final String code;

  /// English name of the language (e.g., 'Bengali').
  final String name;

  /// Native name of the language (e.g., 'বাংলা').
  final String nativeName;

  /// Whether the language is right-to-left (RTL), such as Arabic.
  final bool isRTL;

  /// Layouts for general text input.
  final KeyboardLayoutSet textLayouts;

  /// Layouts for email input (with @ accessible). Falls back to [textLayouts].
  final KeyboardLayoutSet? emailLayouts;

  /// Layouts for URL input (with /, :, . accessible). Falls back to [textLayouts].
  final KeyboardLayoutSet? urlLayouts;

  /// Layouts for number input. Falls back to a standard number pad.
  final KeyboardLayoutSet? numberLayouts;

  /// Layouts for signed number input (with - key). Falls back to [numberLayouts].
  final KeyboardLayoutSet? numberSignedLayouts;

  /// Layouts for decimal number input (with . key). Falls back to [numberLayouts].
  final KeyboardLayoutSet? numberDecimalLayouts;

  /// Layouts for phone input. Falls back to a standard phone dialer.
  final KeyboardLayoutSet? phoneLayouts;

  /// Gets the appropriate layout set for the given input type.
  ///
  /// Falls back to [textLayouts] if no specific layout is defined.
  KeyboardLayoutSet getLayoutsForType(KeyboardInputType inputType) {
    switch (inputType) {
      case KeyboardInputType.email:
        return emailLayouts ?? textLayouts;
      case KeyboardInputType.url:
        return urlLayouts ?? textLayouts;
      case KeyboardInputType.number:
        return numberLayouts ?? textLayouts;
      case KeyboardInputType.numberSigned:
        return numberSignedLayouts ?? numberLayouts ?? textLayouts;
      case KeyboardInputType.numberDecimal:
        return numberDecimalLayouts ?? numberLayouts ?? textLayouts;
      case KeyboardInputType.phone:
        return phoneLayouts ?? textLayouts;
      case KeyboardInputType.text:
        return textLayouts;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KeyboardLanguage &&
          runtimeType == other.runtimeType &&
          code == other.code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'KeyboardLanguage($code: $name)';
}

/// Simplified input type categories for layout selection.
///
/// This is separate from [KeyboardType] which has many variants.
/// Multiple [KeyboardType] values map to the same [KeyboardInputType].
enum KeyboardInputType {
  /// General text input (text, multiline, password, name, address, etc.).
  text,

  /// Email address input.
  email,

  /// URL input.
  url,

  /// Numeric input (0-9 and .).
  number,

  /// Signed numeric input (0-9, -, .).
  numberSigned,

  /// Decimal numeric input (0-9, .).
  numberDecimal,

  /// Phone number input.
  phone,
}
