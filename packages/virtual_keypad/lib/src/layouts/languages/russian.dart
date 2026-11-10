import '../../enums.dart';
import '../../models.dart';
import '../keyboard_language.dart';

/// Russian ЙЦУКЕН (JCUKEN) text layout - primary (Cyrillic letters).
/// Standard Russian keyboard layout used on Windows/Android/iOS.
/// Row 1: й ц у к е н г ш щ з х
/// Row 2: ф ы в а п р о л д ж э
/// Row 3: я ч с м и т ь б ю (+ shift/backspace)
/// Extra letters ъ and ё accessible via long-press in real keyboards;
/// here ё is placed in tertiary layout.
final KeyboardLayout _textLayoutPrimary = [
  [
    VirtualKey.character(text: 'й'),
    VirtualKey.character(text: 'ц'),
    VirtualKey.character(text: 'у'),
    VirtualKey.character(text: 'к'),
    VirtualKey.character(text: 'е'),
    VirtualKey.character(text: 'н'),
    VirtualKey.character(text: 'г'),
    VirtualKey.character(text: 'ш'),
    VirtualKey.character(text: 'щ'),
    VirtualKey.character(text: 'з'),
    VirtualKey.character(text: 'х'),
  ],
  [
    VirtualKey.character(text: 'ф'),
    VirtualKey.character(text: 'ы'),
    VirtualKey.character(text: 'в'),
    VirtualKey.character(text: 'а'),
    VirtualKey.character(text: 'п'),
    VirtualKey.character(text: 'р'),
    VirtualKey.character(text: 'о'),
    VirtualKey.character(text: 'л'),
    VirtualKey.character(text: 'д'),
    VirtualKey.character(text: 'ж'),
    VirtualKey.character(text: 'э'),
  ],
  [
    VirtualKey.action(action: KeyAction.shift, flex: 1),
    VirtualKey.character(text: 'я'),
    VirtualKey.character(text: 'ч'),
    VirtualKey.character(text: 'с'),
    VirtualKey.character(text: 'м'),
    VirtualKey.character(text: 'и'),
    VirtualKey.character(text: 'т'),
    VirtualKey.character(text: 'ь'),
    VirtualKey.character(text: 'б'),
    VirtualKey.character(text: 'ю'),
    VirtualKey.action(action: KeyAction.backSpace, flex: 1),
  ],
  [
    VirtualKey.action(action: KeyAction.symbols, flex: 2),
    VirtualKey.character(text: ','),
    VirtualKey.action(action: KeyAction.space, flex: 5),
    VirtualKey.character(text: '.'),
    VirtualKey.action(action: KeyAction.enter, flex: 2),
  ],
];

/// Text layout - secondary (numbers & common symbols).
final KeyboardLayout _textLayoutSecondary = [
  [
    VirtualKey.character(text: '1'),
    VirtualKey.character(text: '2'),
    VirtualKey.character(text: '3'),
    VirtualKey.character(text: '4'),
    VirtualKey.character(text: '5'),
    VirtualKey.character(text: '6'),
    VirtualKey.character(text: '7'),
    VirtualKey.character(text: '8'),
    VirtualKey.character(text: '9'),
    VirtualKey.character(text: '0'),
  ],
  [
    VirtualKey.character(text: '-'),
    VirtualKey.character(text: '/'),
    VirtualKey.character(text: ':'),
    VirtualKey.character(text: ';'),
    VirtualKey.character(text: '('),
    VirtualKey.character(text: ')'),
    VirtualKey.character(text: '₽'),
    VirtualKey.character(text: '&'),
    VirtualKey.character(text: '@'),
    VirtualKey.character(text: '"'),
  ],
  [
    VirtualKey.action(action: KeyAction.symbolsAlt, flex: 1.5),
    VirtualKey.character(text: '.'),
    VirtualKey.character(text: ','),
    VirtualKey.character(text: '?'),
    VirtualKey.character(text: '!'),
    VirtualKey.character(text: "'"),
    VirtualKey.character(text: '#'),
    VirtualKey.character(text: '%'),
    VirtualKey.action(action: KeyAction.backSpace, flex: 1.5),
  ],
  [
    VirtualKey.action(action: KeyAction.symbols, flex: 2),
    VirtualKey.character(text: ','),
    VirtualKey.action(action: KeyAction.space, flex: 4),
    VirtualKey.character(text: '.'),
    VirtualKey.action(action: KeyAction.enter, flex: 2),
  ],
];

/// Text layout - tertiary (extra Cyrillic letters & more symbols).
final KeyboardLayout _textLayoutTertiary = [
  [
    VirtualKey.character(text: 'ё'),
    VirtualKey.character(text: 'ъ'),
    VirtualKey.character(text: '['),
    VirtualKey.character(text: ']'),
    VirtualKey.character(text: '{'),
    VirtualKey.character(text: '}'),
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
    VirtualKey.character(text: '€'),
    VirtualKey.character(text: '\$'),
    VirtualKey.character(text: '£'),
    VirtualKey.character(text: '•'),
  ],
  [
    VirtualKey.action(action: KeyAction.symbolsAlt, flex: 1.5),
    VirtualKey.character(text: '.'),
    VirtualKey.character(text: ','),
    VirtualKey.character(text: '?'),
    VirtualKey.character(text: '!'),
    VirtualKey.character(text: "'"),
    VirtualKey.character(text: '`'),
    VirtualKey.character(text: '°'),
    VirtualKey.action(action: KeyAction.backSpace, flex: 1.5),
  ],
  [
    VirtualKey.action(action: KeyAction.symbols, flex: 2),
    VirtualKey.character(text: ','),
    VirtualKey.action(action: KeyAction.space, flex: 4),
    VirtualKey.character(text: '.'),
    VirtualKey.action(action: KeyAction.enter, flex: 2),
  ],
];

/// Email keyboard - primary layout (Latin QWERTY for email addresses).
/// Email addresses use Latin characters, so we provide a Latin layout.
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

/// URL keyboard - primary layout (Latin QWERTY for URL entry).
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

/// Number pad layout.
final KeyboardLayout _numberLayout = [
  [
    VirtualKey.character(text: '1'),
    VirtualKey.character(text: '2'),
    VirtualKey.character(text: '3'),
  ],
  [
    VirtualKey.character(text: '4'),
    VirtualKey.character(text: '5'),
    VirtualKey.character(text: '6'),
  ],
  [
    VirtualKey.character(text: '7'),
    VirtualKey.character(text: '8'),
    VirtualKey.character(text: '9'),
  ],
  [
    VirtualKey.character(text: '.'),
    VirtualKey.character(text: '0'),
    VirtualKey.action(action: KeyAction.backSpace),
  ],
];

final KeyboardLayout _signedNumberLayout = [
  [
    VirtualKey.character(text: '1'),
    VirtualKey.character(text: '2'),
    VirtualKey.character(text: '3'),
  ],
  [
    VirtualKey.character(text: '4'),
    VirtualKey.character(text: '5'),
    VirtualKey.character(text: '6'),
  ],
  [
    VirtualKey.character(text: '7'),
    VirtualKey.character(text: '8'),
    VirtualKey.character(text: '9'),
  ],
  [
    VirtualKey.character(text: '-'),
    VirtualKey.character(text: '0'),
    VirtualKey.character(text: '.'),
  ],
  [
    VirtualKey.action(action: KeyAction.backSpace, flex: 2),
    VirtualKey.action(action: KeyAction.done),
  ],
];

final KeyboardLayout _phoneLayout = [
  [
    VirtualKey.character(text: '1'),
    VirtualKey.character(text: '2'),
    VirtualKey.character(text: '3'),
  ],
  [
    VirtualKey.character(text: '4'),
    VirtualKey.character(text: '5'),
    VirtualKey.character(text: '6'),
  ],
  [
    VirtualKey.character(text: '7'),
    VirtualKey.character(text: '8'),
    VirtualKey.character(text: '9'),
  ],
  [
    VirtualKey.character(text: '*'),
    VirtualKey.character(text: '0'),
    VirtualKey.character(text: '#'),
  ],
  [
    VirtualKey.character(text: '+'),
    VirtualKey.action(action: KeyAction.backSpace),
    VirtualKey.action(action: KeyAction.call),
  ],
];

/// Russian (ЙЦУКЕН/JCUKEN) keyboard language.
final KeyboardLanguage russianLanguage = KeyboardLanguage(
  code: 'ru',
  name: 'Russian',
  nativeName: 'Русский',
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
