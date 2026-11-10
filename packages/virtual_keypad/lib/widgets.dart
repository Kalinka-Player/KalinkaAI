/// Widget-focused APIs for `virtual_keypad`.
///
/// Import this library when you want the scoped widget workflow:
/// [VirtualKeypadScope], [VirtualKeypadTextField], [VirtualKeypadController],
/// [VirtualKeypad], and [VirtualKeypadFloating].
///
/// This library is useful when you want tighter focus routing, input-action
/// callbacks, system keyboard blocking, and widget-level customization without
/// importing every layout symbol from the main package entrypoint.

library;

export 'src/controller.dart';
export 'src/emoji_font.dart';
export 'src/enums.dart';
export 'src/models.dart';
export 'src/scope.dart';
export 'src/standalone_scope.dart';
export 'src/theme.dart';
export 'src/widgets/widgets.dart';
