import 'package:flutter/foundation.dart';

import 'keyboard_language.dart';
import '../models.dart';
import 'languages/arabic.dart';
import 'languages/bengali.dart';
import 'languages/english.dart';
import 'languages/french.dart';
import 'languages/german.dart';
import 'languages/hebrew.dart';
import 'languages/hindi.dart';
import 'languages/italian.dart';
import 'languages/korean.dart';
import 'languages/polish.dart';
import 'languages/portuguese.dart';
import 'languages/russian.dart';
import 'languages/spanish.dart';
import 'languages/thai.dart';
import 'languages/turkish.dart';
import 'languages/ukrainian.dart';

/// Manages keyboard languages and provides access to layouts.
///
/// This is the central registry for all available keyboard languages.
/// Use [KeyboardLayoutProvider.instance] to access the singleton.
///
/// Example:
/// ```dart
/// // Get the current language
/// final language = KeyboardLayoutProvider.instance.currentLanguage;
///
/// // Change language
/// KeyboardLayoutProvider.instance.setLanguage('bn');
///
/// // Get layouts for email input in current language
/// final layouts = KeyboardLayoutProvider.instance.getLayouts(KeyboardInputType.email);
/// ```
class KeyboardLayoutProvider {
  KeyboardLayoutProvider._();

  /// The shared singleton registry used by every keyboard in the app.
  ///
  /// Read or change the active language here to drive a multilingual keypad at
  /// runtime, including right-to-left (RTL) languages such as Arabic.
  static final KeyboardLayoutProvider instance = KeyboardLayoutProvider._();

  final Map<String, KeyboardLanguage> _languages = {};
  final List<VoidCallback> _listeners = [];
  String _currentLanguageCode = 'en';
  bool _hasExplicitLanguageSelection = false;

  /// All registered languages.
  Iterable<KeyboardLanguage> get languages => _languages.values;

  /// Available language codes.
  Iterable<String> get languageCodes => _languages.keys;

  /// The currently selected language.
  KeyboardLanguage get currentLanguage {
    return _languages[_currentLanguageCode] ?? englishLanguage;
  }

  /// The current language code.
  String get currentLanguageCode => _currentLanguageCode;

  /// Whether the current language was explicitly selected during this app run.
  bool get hasExplicitLanguageSelection => _hasExplicitLanguageSelection;

  /// Adds a listener that is called when the selected language changes.
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  /// Removes a language selection listener.
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  /// Registers a new keyboard language.
  ///
  /// If a language with the same code already exists, it will be replaced.
  void registerLanguage(KeyboardLanguage language) {
    _validateLanguage(language);
    _languages[language.code] = language;
  }

  /// Unregisters a keyboard language by code.
  ///
  /// Cannot unregister English ('en') as it's the fallback language.
  bool unregisterLanguage(String code) {
    if (code == 'en') return false;
    return _languages.remove(code) != null;
  }

  /// Sets the current language by code.
  ///
  /// Returns true if the language was found and set, false otherwise.
  bool setLanguage(String code, {bool userInitiated = true}) {
    if (!_languages.containsKey(code)) return false;

    final changed = _currentLanguageCode != code;
    _currentLanguageCode = code;
    if (userInitiated) {
      _hasExplicitLanguageSelection = true;
    }

    if (changed) {
      _notifyListeners();
    }

    return true;
  }

  /// Gets a language by code, or null if not found.
  KeyboardLanguage? getLanguage(String code) => _languages[code];

  /// Gets the layout set for the given input type in the current language.
  KeyboardLayoutSet getLayouts(KeyboardInputType inputType) {
    return currentLanguage.getLayoutsForType(inputType);
  }

  /// Gets the layout set for the given input type in a specific language.
  KeyboardLayoutSet getLayoutsForLanguage(
    String languageCode,
    KeyboardInputType inputType,
  ) {
    final language = _languages[languageCode] ?? currentLanguage;
    return language.getLayoutsForType(inputType);
  }

  /// Checks if a language is registered.
  bool hasLanguage(String code) => _languages.containsKey(code);

  /// Resets to default state (English only).
  void reset() {
    _languages.clear();
    _languages['en'] = englishLanguage;
    _currentLanguageCode = 'en';
    _hasExplicitLanguageSelection = false;
    _notifyListeners();
  }

  void _notifyListeners() {
    for (final listener in List<VoidCallback>.from(_listeners)) {
      listener();
    }
  }

  void _validateLanguage(KeyboardLanguage language) {
    if (language.code.trim().isEmpty) {
      throw ArgumentError.value(
        language.code,
        'language.code',
        'Language code cannot be empty.',
      );
    }

    if (language.name.trim().isEmpty) {
      throw ArgumentError.value(
        language.name,
        'language.name',
        'Language name cannot be empty.',
      );
    }

    if (language.nativeName.trim().isEmpty) {
      throw ArgumentError.value(
        language.nativeName,
        'language.nativeName',
        'Language nativeName cannot be empty.',
      );
    }

    _validateLayoutSet(language.textLayouts, '${language.code}.textLayouts');

    final optionalSets = <String, KeyboardLayoutSet?>{
      'emailLayouts': language.emailLayouts,
      'urlLayouts': language.urlLayouts,
      'numberLayouts': language.numberLayouts,
      'numberSignedLayouts': language.numberSignedLayouts,
      'numberDecimalLayouts': language.numberDecimalLayouts,
      'phoneLayouts': language.phoneLayouts,
    };

    for (final entry in optionalSets.entries) {
      final layoutSet = entry.value;
      if (layoutSet != null) {
        _validateLayoutSet(layoutSet, '${language.code}.${entry.key}');
      }
    }
  }

  void _validateLayoutSet(KeyboardLayoutSet layoutSet, String name) {
    _validateLayout(layoutSet.primary, '$name.primary');

    if (layoutSet.secondary != null) {
      _validateLayout(layoutSet.secondary!, '$name.secondary');
    }

    if (layoutSet.tertiary != null) {
      _validateLayout(layoutSet.tertiary!, '$name.tertiary');
    }
  }

  void _validateLayout(KeyboardLayout layout, String name) {
    if (layout.isEmpty) {
      throw ArgumentError.value(
        layout,
        name,
        'Layout must contain at least one row.',
      );
    }

    for (var rowIndex = 0; rowIndex < layout.length; rowIndex++) {
      final row = layout[rowIndex];
      if (row.isEmpty) {
        throw ArgumentError.value(
          row,
          '$name[$rowIndex]',
          'Layout rows cannot be empty.',
        );
      }

      for (var keyIndex = 0; keyIndex < row.length; keyIndex++) {
        final key = row[keyIndex];
        if (key.flex <= 0) {
          throw ArgumentError.value(
            key.flex,
            '$name[$rowIndex][$keyIndex].flex',
            'Key flex must be greater than zero.',
          );
        }

        if (key.isCharacter && (key.text == null || key.text!.isEmpty)) {
          throw ArgumentError.value(
            key.text,
            '$name[$rowIndex][$keyIndex].text',
            'Character keys must provide non-empty text.',
          );
        }
      }
    }
  }
}

/// Initialize the provider with default languages.
///
/// Call this at app startup to register built-in languages.
/// Registers English ('en'), Arabic ('ar'), Bengali ('bn'), French ('fr'),
/// German ('de'), Hebrew ('he'), Hindi ('hi'), Italian ('it'), Korean ('ko'),
/// Polish ('pl'), Portuguese ('pt'), Russian ('ru'), Spanish ('es'),
/// Thai ('th'), Turkish ('tr'), and Ukrainian ('uk').
void initializeKeyboardLayouts() {
  final provider = KeyboardLayoutProvider.instance;
  provider.registerLanguage(englishLanguage);
  provider.registerLanguage(arabicLanguage);
  provider.registerLanguage(bengaliLanguage);
  provider.registerLanguage(frenchLanguage);
  provider.registerLanguage(germanLanguage);
  provider.registerLanguage(hebrewLanguage);
  provider.registerLanguage(hindiLanguage);
  provider.registerLanguage(italianLanguage);
  provider.registerLanguage(koreanLanguage);
  provider.registerLanguage(polishLanguage);
  provider.registerLanguage(portugueseLanguage);
  provider.registerLanguage(russianLanguage);
  provider.registerLanguage(spanishLanguage);
  provider.registerLanguage(thaiLanguage);
  provider.registerLanguage(turkishLanguage);
  provider.registerLanguage(ukrainianLanguage);
}
