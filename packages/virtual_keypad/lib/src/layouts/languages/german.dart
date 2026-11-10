import '../../enums.dart';
import '../../models.dart';
import '../keyboard_language.dart';

/// German QWERTZ text layout - primary (letters).
/// Z and Y swapped from QWERTY, with ü after p, ö and ä after l, ß on row 3.
final KeyboardLayout _textLayoutPrimary = [
  [
    VirtualKey.character(text: 'q'),
    VirtualKey.character(text: 'w'),
    VirtualKey.character(text: 'e'),
    VirtualKey.character(text: 'r'),
    VirtualKey.character(text: 't'),
    VirtualKey.character(text: 'z'),
    VirtualKey.character(text: 'u'),
    VirtualKey.character(text: 'i'),
    VirtualKey.character(text: 'o'),
    VirtualKey.character(text: 'p'),
    VirtualKey.character(text: 'ü'),
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
    VirtualKey.character(text: 'ö'),
    VirtualKey.character(text: 'ä'),
  ],
  [
    VirtualKey.action(action: KeyAction.shift, flex: 1.5),
    VirtualKey.character(text: 'y'),
    VirtualKey.character(text: 'x'),
    VirtualKey.character(text: 'c'),
    VirtualKey.character(text: 'v'),
    VirtualKey.character(text: 'b'),
    VirtualKey.character(text: 'n'),
    VirtualKey.character(text: 'm'),
    VirtualKey.character(text: 'ß', capsText: 'ẞ'),
    VirtualKey.action(action: KeyAction.backSpace, flex: 1.5),
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
    VirtualKey.character(text: '€'),
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

/// Text layout - tertiary (more symbols).
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
    VirtualKey.character(text: '\$'),
    VirtualKey.character(text: '£'),
    VirtualKey.character(text: '¥'),
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

/// Email keyboard - primary layout.
final KeyboardLayout _emailLayoutPrimary = [
  [
    VirtualKey.character(text: 'q'),
    VirtualKey.character(text: 'w'),
    VirtualKey.character(text: 'e'),
    VirtualKey.character(text: 'r'),
    VirtualKey.character(text: 't'),
    VirtualKey.character(text: 'z'),
    VirtualKey.character(text: 'u'),
    VirtualKey.character(text: 'i'),
    VirtualKey.character(text: 'o'),
    VirtualKey.character(text: 'p'),
    VirtualKey.character(text: 'ü'),
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
    VirtualKey.character(text: 'ö'),
    VirtualKey.character(text: 'ä'),
  ],
  [
    VirtualKey.action(action: KeyAction.shift, flex: 1.5),
    VirtualKey.character(text: 'y'),
    VirtualKey.character(text: 'x'),
    VirtualKey.character(text: 'c'),
    VirtualKey.character(text: 'v'),
    VirtualKey.character(text: 'b'),
    VirtualKey.character(text: 'n'),
    VirtualKey.character(text: 'm'),
    VirtualKey.character(text: 'ß', capsText: 'ẞ'),
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
final KeyboardLayout _emailLayoutTertiary = _textLayoutTertiary;

/// URL keyboard - primary layout.
final KeyboardLayout _urlLayoutPrimary = [
  [
    VirtualKey.character(text: 'q'),
    VirtualKey.character(text: 'w'),
    VirtualKey.character(text: 'e'),
    VirtualKey.character(text: 'r'),
    VirtualKey.character(text: 't'),
    VirtualKey.character(text: 'z'),
    VirtualKey.character(text: 'u'),
    VirtualKey.character(text: 'i'),
    VirtualKey.character(text: 'o'),
    VirtualKey.character(text: 'p'),
    VirtualKey.character(text: 'ü'),
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
    VirtualKey.character(text: 'ö'),
    VirtualKey.character(text: 'ä'),
  ],
  [
    VirtualKey.action(action: KeyAction.shift, flex: 1.5),
    VirtualKey.character(text: 'y'),
    VirtualKey.character(text: 'x'),
    VirtualKey.character(text: 'c'),
    VirtualKey.character(text: 'v'),
    VirtualKey.character(text: 'b'),
    VirtualKey.character(text: 'n'),
    VirtualKey.character(text: 'm'),
    VirtualKey.character(text: 'ß', capsText: 'ẞ'),
    VirtualKey.action(action: KeyAction.backSpace, flex: 1.5),
  ],
  [
    VirtualKey.action(action: KeyAction.symbols, flex: 1.5),
    VirtualKey.character(text: '/'),
    VirtualKey.character(text: '.'),
    VirtualKey.action(action: KeyAction.space, flex: 4),
    VirtualKey.character(text: '-'),
    VirtualKey.character(text: ':'),
    VirtualKey.action(action: KeyAction.go, flex: 1.5),
  ],
];

final KeyboardLayout _urlLayoutSecondary = _textLayoutSecondary;
final KeyboardLayout _urlLayoutTertiary = _textLayoutTertiary;

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
    VirtualKey.character(text: ','),
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
    VirtualKey.character(text: ','),
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

/// German (QWERTZ) keyboard language.
final KeyboardLanguage germanLanguage = KeyboardLanguage(
  code: 'de',
  name: 'German',
  nativeName: 'Deutsch',
  textLayouts: KeyboardLayoutSet(
    primary: _textLayoutPrimary,
    secondary: _textLayoutSecondary,
    tertiary: _textLayoutTertiary,
  ),
  emailLayouts: KeyboardLayoutSet(
    primary: _emailLayoutPrimary,
    secondary: _emailLayoutSecondary,
    tertiary: _emailLayoutTertiary,
  ),
  urlLayouts: KeyboardLayoutSet(
    primary: _urlLayoutPrimary,
    secondary: _urlLayoutSecondary,
    tertiary: _urlLayoutTertiary,
  ),
  numberLayouts: KeyboardLayoutSet.single(_numberLayout),
  numberSignedLayouts: KeyboardLayoutSet.single(_signedNumberLayout),
  numberDecimalLayouts: KeyboardLayoutSet.single(_numberLayout),
  phoneLayouts: KeyboardLayoutSet.single(_phoneLayout),
);
