/// Keyboard layout system with multi-language support.
///
/// This library provides:
/// - [KeyboardLanguage]: Defines all layouts for a specific language
/// - [KeyboardLayoutSet]: Groups primary/secondary/tertiary layouts
/// - [KeyboardLayoutProvider]: Manages and provides layouts by language
/// - Built-in languages in the `languages/` folder
///
/// ## Adding a new language
///
/// 1. Create a file in `layouts/languages/` (e.g., `bengali.dart`)
/// 2. Define your layouts following `english.dart` pattern
/// 3. Export from `languages/languages.dart`
/// 4. Register at app startup:
///    ```dart
///    KeyboardLayoutProvider.instance.registerLanguage(bengaliLanguage);
///    ```
///
/// ## Using layouts
///
/// ```dart
/// // Initialize default languages
/// initializeKeyboardLayouts();
///
/// // Get current language's layouts for email input
/// final layouts = KeyboardLayoutProvider.instance.getLayouts(KeyboardInputType.email);
///
/// // Switch language
/// KeyboardLayoutProvider.instance.setLanguage('bn');
/// ```
library;

export 'keyboard_language.dart';
export 'keyboard_layout_provider.dart';
export 'languages/languages.dart';
export 'text_layouts.dart';
export 'number_layouts.dart';
export 'email_layouts.dart';
export 'url_layouts.dart';
export 'phone_layouts.dart';
