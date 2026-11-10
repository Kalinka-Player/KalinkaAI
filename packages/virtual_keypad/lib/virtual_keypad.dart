/// A Flutter package for creating customizable virtual on-screen keyboards,
/// keypads, and PIN pads.
///
/// This package provides a complete solution for custom keyboard input on
/// touchscreen, desktop, kiosk, POS, and embedded devices where the system
/// software keyboard is unavailable or too limited. It includes text fields
/// that integrate seamlessly with virtual keyboards, theming support, and
/// multiple keyboard layouts that adapt to input type.
///
/// ## Getting Started
///
/// ### Standalone Mode (simplest)
///
/// Use `VirtualKeypad(standalone: true)` with any standard Flutter [TextField]:
///
/// ```dart
/// Column(
///   children: [
///     TextField(controller: myController),
///     VirtualKeypad(standalone: true),
///   ],
/// )
/// ```
///
/// ### Scope Mode (full control)
///
/// Wrap your widget tree with [VirtualKeypadScope], then use
/// [VirtualKeypadTextField] and [VirtualKeypad] together:
///
/// ```dart
/// VirtualKeypadScope(
///   child: Column(
///     children: [
///       VirtualKeypadTextField(controller: controller),
///       VirtualKeypad(),
///     ],
///   ),
/// )
/// ```
///
/// ## Input-Aware Layouts
///
/// The keyboard automatically adapts based on the text field's input type.
/// In standalone mode, it reads the [TextInputType] from the focused field.
/// In scope mode, set [KeyboardType] on [VirtualKeypadTextField].
///
/// ## Key Components
///
/// - [VirtualKeypad] - Customizable on-screen keyboard widget
/// - [VirtualKeypadFloating] - Floating host for draggable keyboard overlays
/// - [VirtualKeypadScope] - Manages keyboard-to-textfield connections (scope mode)
/// - [VirtualKeypadStandaloneScope] - Restricts standalone keyboard to a widget subtree
/// - [VirtualKeypadTextField] - Text field optimized for virtual keyboard input (scope mode)
/// - [VirtualKeypadController] - Controller with text manipulation methods
/// - [VirtualKeypadTheme] - Theming for keyboard appearance
/// - [KeyboardType] - Input types that determine keyboard layout
/// - [StandaloneInputControl] - Text input interceptor for standalone mode
///
/// ## Additional Libraries
///
/// The package also exposes focused entrypoints for pub.dev documentation and
/// more selective imports:
///
/// - `package:virtual_keypad/widgets.dart` for widget-first scoped usage
/// - `package:virtual_keypad/standalone.dart` for standalone TextField usage
/// - `package:virtual_keypad/layouts.dart` for languages, layouts, and setup
library;

export 'src/controller.dart';
export 'src/emoji_font.dart';
export 'src/enums.dart';
export 'src/models.dart';
export 'src/scope.dart';
export 'src/standalone_input_control.dart';
export 'src/standalone_scope.dart';
export 'src/theme.dart';
export 'src/widgets/keyboard.dart';
export 'src/widgets/floating_keyboard.dart';
export 'src/widgets/text_field.dart';
export 'src/layouts/accents.dart';
export 'src/layouts/layouts.dart';
