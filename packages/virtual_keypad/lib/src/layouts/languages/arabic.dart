import '../../enums.dart';
import '../../models.dart';
import '../keyboard_language.dart';

/// Arabic text layout - primary (letters).
/// Based on the standard Arabic IBM PC keyboard layout.
/// Row 1: ض ص ث ق ف غ ع ه خ ح ج
/// Row 2: ش س ي ب ل ا ت ن م ك
/// Row 3: ئ ء ؤ ر لا ى ة و ز (+ shift/backspace)
final KeyboardLayout _textLayoutPrimary = [
  [
    VirtualKey.character(text: 'ض'),
    VirtualKey.character(text: 'ص'),
    VirtualKey.character(text: 'ث'),
    VirtualKey.character(text: 'ق'),
    VirtualKey.character(text: 'ف'),
    VirtualKey.character(text: 'غ'),
    VirtualKey.character(text: 'ع'),
    VirtualKey.character(text: 'ه'),
    VirtualKey.character(text: 'خ'),
    VirtualKey.character(text: 'ح'),
    VirtualKey.character(text: 'ج'),
  ],
  [
    VirtualKey.character(text: 'ش'),
    VirtualKey.character(text: 'س'),
    VirtualKey.character(text: 'ي'),
    VirtualKey.character(text: 'ب'),
    VirtualKey.character(text: 'ل'),
    VirtualKey.character(text: 'ا'),
    VirtualKey.character(text: 'ت'),
    VirtualKey.character(text: 'ن'),
    VirtualKey.character(text: 'م'),
    VirtualKey.character(text: 'ك'),
  ],
  [
    VirtualKey.action(action: KeyAction.shift, flex: 1),
    VirtualKey.character(text: 'ئ'),
    VirtualKey.character(text: 'ء'),
    VirtualKey.character(text: 'ؤ'),
    VirtualKey.character(text: 'ر'),
    VirtualKey.character(text: 'ى'),
    VirtualKey.character(text: 'ة'),
    VirtualKey.character(text: 'و'),
    VirtualKey.character(text: 'ز'),
    VirtualKey.character(text: 'د'),
    VirtualKey.action(action: KeyAction.backSpace, flex: 1),
  ],
  [
    VirtualKey.action(
      action: KeyAction.symbols,
      label: '١٢٣',
      altLabel: 'أبج',
      flex: 2,
    ),
    VirtualKey.character(text: '،'),
    VirtualKey.action(action: KeyAction.space, flex: 5),
    VirtualKey.character(text: '.'),
    VirtualKey.action(action: KeyAction.enter, flex: 2),
  ],
];

/// Arabic text layout - secondary (diacritics, Arabic-Indic numerals, extras).
final KeyboardLayout _textLayoutSecondary = [
  [
    VirtualKey.character(text: '١', capsText: '1'),
    VirtualKey.character(text: '٢', capsText: '2'),
    VirtualKey.character(text: '٣', capsText: '3'),
    VirtualKey.character(text: '٤', capsText: '4'),
    VirtualKey.character(text: '٥', capsText: '5'),
    VirtualKey.character(text: '٦', capsText: '6'),
    VirtualKey.character(text: '٧', capsText: '7'),
    VirtualKey.character(text: '٨', capsText: '8'),
    VirtualKey.character(text: '٩', capsText: '9'),
    VirtualKey.character(text: '٠', capsText: '0'),
  ],
  [
    VirtualKey.character(text: 'َ'),
    VirtualKey.character(text: 'ً'),
    VirtualKey.character(text: 'ُ'),
    VirtualKey.character(text: 'ٌ'),
    VirtualKey.character(text: 'ِ'),
    VirtualKey.character(text: 'ٍ'),
    VirtualKey.character(text: 'ّ'),
    VirtualKey.character(text: 'ْ'),
    VirtualKey.character(text: 'ـ'),
    VirtualKey.character(text: 'آ'),
  ],
  [
    VirtualKey.action(
      action: KeyAction.symbolsAlt,
      label: '#+=',
      altLabel: '١٢٣',
      flex: 1.5,
    ),
    VirtualKey.character(text: '-'),
    VirtualKey.character(text: '/'),
    VirtualKey.character(text: ':'),
    VirtualKey.character(text: '؟'),
    VirtualKey.character(text: '!'),
    VirtualKey.character(text: '"'),
    VirtualKey.character(text: "'"),
    VirtualKey.action(action: KeyAction.backSpace, flex: 1.5),
  ],
  [
    VirtualKey.action(
      action: KeyAction.symbols,
      label: '١٢٣',
      altLabel: 'أبج',
      flex: 2,
    ),
    VirtualKey.character(text: '،'),
    VirtualKey.action(action: KeyAction.space, flex: 4),
    VirtualKey.character(text: '؛'),
    VirtualKey.action(action: KeyAction.enter, flex: 2),
  ],
];

/// Arabic text layout - tertiary (symbols and punctuation).
final KeyboardLayout _textLayoutTertiary = [
  [
    VirtualKey.character(text: '['),
    VirtualKey.character(text: ']'),
    VirtualKey.character(text: '{'),
    VirtualKey.character(text: '}'),
    VirtualKey.character(text: '#'),
    VirtualKey.character(text: '%'),
    VirtualKey.character(text: '^'),
    VirtualKey.character(text: '*'),
    VirtualKey.character(text: '+'),
    VirtualKey.character(text: '='),
  ],
  [
    VirtualKey.character(text: '_'),
    VirtualKey.character(text: '\\'),
    VirtualKey.character(text: '|'),
    VirtualKey.character(text: '~'),
    VirtualKey.character(text: '<'),
    VirtualKey.character(text: '>'),
    VirtualKey.character(text: '﷼'),
    VirtualKey.character(text: '\$'),
    VirtualKey.character(text: '€'),
    VirtualKey.character(text: '•'),
  ],
  [
    VirtualKey.action(
      action: KeyAction.symbolsAlt,
      label: '#+=',
      altLabel: '١٢٣',
      flex: 1.5,
    ),
    VirtualKey.character(text: '.'),
    VirtualKey.character(text: '،'),
    VirtualKey.character(text: '؟'),
    VirtualKey.character(text: '!'),
    VirtualKey.character(text: "'"),
    VirtualKey.character(text: '`'),
    VirtualKey.character(text: '°'),
    VirtualKey.action(action: KeyAction.backSpace, flex: 1.5),
  ],
  [
    VirtualKey.action(
      action: KeyAction.symbols,
      label: '١٢٣',
      altLabel: 'أبج',
      flex: 2,
    ),
    VirtualKey.character(text: '،'),
    VirtualKey.action(action: KeyAction.space, flex: 4),
    VirtualKey.character(text: '.'),
    VirtualKey.action(action: KeyAction.enter, flex: 2),
  ],
];

/// Arabic email keyboard - primary layout (Latin QWERTY for email addresses).
final KeyboardLayout _emailLayoutPrimary = [
  [
    VirtualKey.character(text: 'q'),
    VirtualKey.character(text: 'w'),
    VirtualKey.character(text: 'e'),
    VirtualKey.character(text: 'r'),
    VirtualKey.character(text: 't'),
    VirtualKey.character(text: 'y'),
    VirtualKey.character(text: 'u'),
    VirtualKey.character(text: 'i'),
    VirtualKey.character(text: 'o'),
    VirtualKey.character(text: 'p'),
  ],
  [
    VirtualKey.character(text: 'a'),
    VirtualKey.character(text: 's'),
    VirtualKey.character(text: 'd'),
    VirtualKey.character(text: 'f'),
    VirtualKey.character(text: 'g'),
    VirtualKey.character(text: 'h'),
    VirtualKey.character(text: 'j'),
    VirtualKey.character(text: 'k'),
    VirtualKey.character(text: 'l'),
  ],
  [
    VirtualKey.action(action: KeyAction.shift, flex: 1.5),
    VirtualKey.character(text: 'z'),
    VirtualKey.character(text: 'x'),
    VirtualKey.character(text: 'c'),
    VirtualKey.character(text: 'v'),
    VirtualKey.character(text: 'b'),
    VirtualKey.character(text: 'n'),
    VirtualKey.character(text: 'm'),
    VirtualKey.action(action: KeyAction.backSpace, flex: 1.5),
  ],
  [
    VirtualKey.action(action: KeyAction.symbols, flex: 1.5),
    VirtualKey.character(text: '@'),
    VirtualKey.action(action: KeyAction.space, flex: 3),
    VirtualKey.character(text: '.'),
    VirtualKey.character(text: '_'),
    VirtualKey.character(text: '-'),
    VirtualKey.action(action: KeyAction.done, flex: 1.5),
  ],
];

final KeyboardLayout _emailLayoutSecondary = _textLayoutSecondary;

/// Arabic URL keyboard - primary layout (Latin QWERTY for URL entry).
final KeyboardLayout _urlLayoutPrimary = [
  [
    VirtualKey.character(text: 'q'),
    VirtualKey.character(text: 'w'),
    VirtualKey.character(text: 'e'),
    VirtualKey.character(text: 'r'),
    VirtualKey.character(text: 't'),
    VirtualKey.character(text: 'y'),
    VirtualKey.character(text: 'u'),
    VirtualKey.character(text: 'i'),
    VirtualKey.character(text: 'o'),
    VirtualKey.character(text: 'p'),
  ],
  [
    VirtualKey.character(text: 'a'),
    VirtualKey.character(text: 's'),
    VirtualKey.character(text: 'd'),
    VirtualKey.character(text: 'f'),
    VirtualKey.character(text: 'g'),
    VirtualKey.character(text: 'h'),
    VirtualKey.character(text: 'j'),
    VirtualKey.character(text: 'k'),
    VirtualKey.character(text: 'l'),
  ],
  [
    VirtualKey.action(action: KeyAction.shift, flex: 1.5),
    VirtualKey.character(text: 'z'),
    VirtualKey.character(text: 'x'),
    VirtualKey.character(text: 'c'),
    VirtualKey.character(text: 'v'),
    VirtualKey.character(text: 'b'),
    VirtualKey.character(text: 'n'),
    VirtualKey.character(text: 'm'),
    VirtualKey.action(action: KeyAction.backSpace, flex: 1.5),
  ],
  [
    VirtualKey.action(action: KeyAction.symbols, flex: 1.5),
    VirtualKey.character(text: '/'),
    VirtualKey.character(text: '.'),
    VirtualKey.action(action: KeyAction.space, flex: 3),
    VirtualKey.character(text: '-'),
    VirtualKey.character(text: ':'),
    VirtualKey.action(action: KeyAction.go, flex: 1.5),
  ],
];

final KeyboardLayout _urlLayoutSecondary = _textLayoutSecondary;

/// Arabic-Indic number pad layout.
final KeyboardLayout _numberLayout = [
  [
    VirtualKey.character(text: '١', capsText: '1'),
    VirtualKey.character(text: '٢', capsText: '2'),
    VirtualKey.character(text: '٣', capsText: '3'),
  ],
  [
    VirtualKey.character(text: '٤', capsText: '4'),
    VirtualKey.character(text: '٥', capsText: '5'),
    VirtualKey.character(text: '٦', capsText: '6'),
  ],
  [
    VirtualKey.character(text: '٧', capsText: '7'),
    VirtualKey.character(text: '٨', capsText: '8'),
    VirtualKey.character(text: '٩', capsText: '9'),
  ],
  [
    VirtualKey.character(text: '.'),
    VirtualKey.character(text: '٠', capsText: '0'),
    VirtualKey.action(action: KeyAction.backSpace),
  ],
];

/// Arabic signed number pad layout.
final KeyboardLayout _signedNumberLayout = [
  [
    VirtualKey.character(text: '١', capsText: '1'),
    VirtualKey.character(text: '٢', capsText: '2'),
    VirtualKey.character(text: '٣', capsText: '3'),
  ],
  [
    VirtualKey.character(text: '٤', capsText: '4'),
    VirtualKey.character(text: '٥', capsText: '5'),
    VirtualKey.character(text: '٦', capsText: '6'),
  ],
  [
    VirtualKey.character(text: '٧', capsText: '7'),
    VirtualKey.character(text: '٨', capsText: '8'),
    VirtualKey.character(text: '٩', capsText: '9'),
  ],
  [
    VirtualKey.character(text: '-'),
    VirtualKey.character(text: '٠', capsText: '0'),
    VirtualKey.character(text: '.'),
  ],
  [
    VirtualKey.action(action: KeyAction.backSpace, flex: 2),
    VirtualKey.action(action: KeyAction.done),
  ],
];

/// Arabic phone dialer layout.
final KeyboardLayout _phoneLayout = [
  [
    VirtualKey.character(text: '١', capsText: '1'),
    VirtualKey.character(text: '٢', capsText: '2'),
    VirtualKey.character(text: '٣', capsText: '3'),
  ],
  [
    VirtualKey.character(text: '٤', capsText: '4'),
    VirtualKey.character(text: '٥', capsText: '5'),
    VirtualKey.character(text: '٦', capsText: '6'),
  ],
  [
    VirtualKey.character(text: '٧', capsText: '7'),
    VirtualKey.character(text: '٨', capsText: '8'),
    VirtualKey.character(text: '٩', capsText: '9'),
  ],
  [
    VirtualKey.character(text: '*'),
    VirtualKey.character(text: '٠', capsText: '0'),
    VirtualKey.character(text: '#'),
  ],
  [
    VirtualKey.character(text: '+'),
    VirtualKey.action(action: KeyAction.backSpace),
    VirtualKey.action(action: KeyAction.call),
  ],
];

/// Arabic (العربية) keyboard language.
final KeyboardLanguage arabicLanguage = KeyboardLanguage(
  code: 'ar',
  name: 'Arabic',
  nativeName: 'العربية',
  isRTL: true,
  textLayouts: KeyboardLayoutSet(
    primary: _textLayoutPrimary,
    secondary: _textLayoutSecondary,
    tertiary: _textLayoutTertiary,
  ),
  emailLayouts: KeyboardLayoutSet(
    primary: _emailLayoutPrimary,
    secondary: _emailLayoutSecondary,
  ),
  urlLayouts: KeyboardLayoutSet(
    primary: _urlLayoutPrimary,
    secondary: _urlLayoutSecondary,
  ),
  numberLayouts: KeyboardLayoutSet.single(_numberLayout),
  numberSignedLayouts: KeyboardLayoutSet.single(_signedNumberLayout),
  numberDecimalLayouts: KeyboardLayoutSet.single(_numberLayout),
  phoneLayouts: KeyboardLayoutSet.single(_phoneLayout),
);
