/// Layout, language, and initialization APIs for `virtual_keypad`.
///
/// Import this library when you want to work directly with built-in layouts,
/// register custom languages, or switch a multilingual keyboard between
/// languages at runtime, including RTL scripts such as Arabic, without
/// pulling in the full widget surface.
///
/// ## Common Tasks
///
/// - Call [initializeKeyboardLayouts] during app startup.
/// - Use [KeyboardLayoutProvider] to read or change the active language.
/// - Define [KeyboardLanguage] and [KeyboardLayoutSet] for custom languages.
/// - Build custom layouts with [VirtualKey], [KeyRow], and [KeyboardLayout].

library;

export 'src/enums.dart';
export 'src/layouts/shuffle.dart';
export 'src/models.dart';
export 'src/layouts/accents.dart';
export 'src/layouts/layouts.dart';
