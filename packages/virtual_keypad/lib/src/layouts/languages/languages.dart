/// Language-specific keyboard layouts.
///
/// Each language file exports a [KeyboardLanguage] instance that can be
/// registered with [KeyboardLayoutProvider].
///
/// To add a new language:
/// 1. Create a new file in this folder (e.g., `hindi.dart`)
/// 2. Define your layouts following the pattern in `english.dart`
/// 3. Export your language file here
/// 4. Register it with `KeyboardLayoutProvider.instance.registerLanguage()`
library;

export 'arabic.dart';
export 'bengali.dart';
export 'english.dart';
export 'french.dart';
export 'german.dart';
export 'hebrew.dart';
export 'hindi.dart';
export 'italian.dart';
export 'korean.dart';
export 'polish.dart';
export 'portuguese.dart';
export 'russian.dart';
export 'spanish.dart';
export 'thai.dart';
export 'turkish.dart';
export 'ukrainian.dart';
