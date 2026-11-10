# Kalinka's virtual_keypad patch

Runtime sources from [virtual_keypad 1.11.0](https://pub.dev/packages/virtual_keypad/versions/1.11.0).
The original MIT license is in `LICENSE`.

The accent-picker modification adds `VirtualKeypad.accentPicker`, an optional
callback in `lib/src/widgets/keyboard.dart` with its typedef in
`lib/src/models.dart`. It receives the resolved, correctly cased alternatives
and the global long-press position, and returns a selected character or null.
The default remains the upstream vertical menu. The package still owns insertion,
single-use Shift reset, callbacks and focus handling.

`enableLanguageKey` adds an outlined globe immediately before Space, borrowing
one flex unit from the space bar. `languagePicker` is an optional callback taking
the available codes, selected code and global key position, and returning a code
or null. Both the globe and long-press Space use it. Kalinka displays all layouts
in a responsive grid through `lib/widgets/keyboard/keyboard_language_picker.dart`;
the upstream menu remains the default for consumers without the callback.

Text on action keys, key previews and picker menus also uses the supplied
`keyTextStyle`, matching character keys. Kalinka supplies its existing IBM Plex
Sans style. The unused upstream Noto Emoji font and its pubspec registration
are omitted: this package bundles no fonts. Emoji UI and the upstream emoji-font
fallback helpers are not used by Kalinka.

Kalinka supplies a horizontal, wrapping picker from
`lib/widgets/keyboard/keyboard_accent_picker.dart`. This local dependency makes
the extension reproducible without editing the pub cache. When updating upstream,
reapply these hooks or use equivalent public APIs, then run
`flutter test test/on_screen_keyboard_test.dart` from the application root.
