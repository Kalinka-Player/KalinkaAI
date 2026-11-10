import '../../enums.dart';
import '../../models.dart';
import '../keyboard_language.dart';

/// Thai Kedmanee text layout - primary (consonants and common vowels).
/// Based on the standard Thai Kedmanee keyboard layout (TIS 820-2538).
/// Row 1: common consonants
/// Row 2: more consonants
/// Row 3: common vowels and tone marks (+ shift/backspace)
/// Row 4: symbols/space/enter
final KeyboardLayout _textLayoutPrimary = [
  [
    VirtualKey.character(text: 'ก'),
    VirtualKey.character(text: 'ข'),
    VirtualKey.character(text: 'ค'),
    VirtualKey.character(text: 'ง'),
    VirtualKey.character(text: 'จ'),
    VirtualKey.character(text: 'ช'),
    VirtualKey.character(text: 'ซ'),
    VirtualKey.character(text: 'ด'),
    VirtualKey.character(text: 'ต'),
    VirtualKey.character(text: 'ถ'),
  ],
  [
    VirtualKey.character(text: 'ท'),
    VirtualKey.character(text: 'น'),
    VirtualKey.character(text: 'บ'),
    VirtualKey.character(text: 'ป'),
    VirtualKey.character(text: 'พ'),
    VirtualKey.character(text: 'ม'),
    VirtualKey.character(text: 'ย'),
    VirtualKey.character(text: 'ร'),
    VirtualKey.character(text: 'ล'),
    VirtualKey.character(text: 'ว'),
  ],
  [
    VirtualKey.action(action: KeyAction.shift, flex: 1.5),
    VirtualKey.character(text: 'ส'),
    VirtualKey.character(text: 'ห'),
    VirtualKey.character(text: 'อ'),
    VirtualKey.character(text: 'ะ'),
    VirtualKey.character(text: 'า'),
    VirtualKey.character(text: 'ิ'),
    VirtualKey.character(text: 'ี'),
    VirtualKey.action(action: KeyAction.backSpace, flex: 1.5),
  ],
  [
    VirtualKey.action(
      action: KeyAction.symbols,
      label: '๑๒๓',
      altLabel: 'กขค',
      flex: 1.5,
    ),
    VirtualKey.character(text: 'ุ'),
    VirtualKey.character(text: 'ู'),
    VirtualKey.action(action: KeyAction.space, flex: 3),
    VirtualKey.character(text: '่'),
    VirtualKey.character(text: '้'),
    VirtualKey.action(action: KeyAction.enter, flex: 1.5),
  ],
];

/// Thai text layout - secondary (remaining consonants, vowels, tone marks,
/// and Thai numerals).
final KeyboardLayout _textLayoutSecondary = [
  [
    VirtualKey.character(text: '๑', capsText: '1'),
    VirtualKey.character(text: '๒', capsText: '2'),
    VirtualKey.character(text: '๓', capsText: '3'),
    VirtualKey.character(text: '๔', capsText: '4'),
    VirtualKey.character(text: '๕', capsText: '5'),
    VirtualKey.character(text: '๖', capsText: '6'),
    VirtualKey.character(text: '๗', capsText: '7'),
    VirtualKey.character(text: '๘', capsText: '8'),
    VirtualKey.character(text: '๙', capsText: '9'),
    VirtualKey.character(text: '๐', capsText: '0'),
  ],
  [
    VirtualKey.character(text: 'ฉ'),
    VirtualKey.character(text: 'ญ'),
    VirtualKey.character(text: 'ฐ'),
    VirtualKey.character(text: 'ธ'),
    VirtualKey.character(text: 'ฝ'),
    VirtualKey.character(text: 'ฟ'),
    VirtualKey.character(text: 'ภ'),
    VirtualKey.character(text: 'ศ'),
    VirtualKey.character(text: 'ษ'),
    VirtualKey.character(text: 'ฬ'),
  ],
  [
    VirtualKey.action(
      action: KeyAction.symbolsAlt,
      label: '#+=',
      altLabel: '๑๒๓',
      flex: 1.5,
    ),
    VirtualKey.character(text: 'เ'),
    VirtualKey.character(text: 'แ'),
    VirtualKey.character(text: 'โ'),
    VirtualKey.character(text: 'ไ'),
    VirtualKey.character(text: 'ใ'),
    VirtualKey.character(text: '็'),
    VirtualKey.character(text: '์'),
    VirtualKey.action(action: KeyAction.backSpace, flex: 1.5),
  ],
  [
    VirtualKey.action(
      action: KeyAction.symbols,
      label: '๑๒๓',
      altLabel: 'กขค',
      flex: 1.5,
    ),
    VirtualKey.character(text: ','),
    VirtualKey.character(text: '๊'),
    VirtualKey.action(action: KeyAction.space, flex: 3),
    VirtualKey.character(text: '๋'),
    VirtualKey.character(text: 'ๆ'),
    VirtualKey.action(action: KeyAction.enter, flex: 1.5),
  ],
];

/// Thai text layout - tertiary (symbols and punctuation).
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
    VirtualKey.character(text: '฿'),
    VirtualKey.character(text: '\$'),
    VirtualKey.character(text: '€'),
    VirtualKey.character(text: '•'),
  ],
  [
    VirtualKey.action(
      action: KeyAction.symbolsAlt,
      label: '#+=',
      altLabel: '๑๒๓',
      flex: 1.5,
    ),
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
    VirtualKey.action(
      action: KeyAction.symbols,
      label: '๑๒๓',
      altLabel: 'กขค',
      flex: 2,
    ),
    VirtualKey.character(text: ','),
    VirtualKey.action(action: KeyAction.space, flex: 4),
    VirtualKey.character(text: '.'),
    VirtualKey.action(action: KeyAction.enter, flex: 2),
  ],
];

/// Thai email keyboard - primary layout (Latin QWERTY for email addresses).
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

/// Thai URL keyboard - primary layout (Latin QWERTY for URL entry).
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

/// Thai number pad layout.
final KeyboardLayout _numberLayout = [
  [
    VirtualKey.character(text: '๑', capsText: '1'),
    VirtualKey.character(text: '๒', capsText: '2'),
    VirtualKey.character(text: '๓', capsText: '3'),
  ],
  [
    VirtualKey.character(text: '๔', capsText: '4'),
    VirtualKey.character(text: '๕', capsText: '5'),
    VirtualKey.character(text: '๖', capsText: '6'),
  ],
  [
    VirtualKey.character(text: '๗', capsText: '7'),
    VirtualKey.character(text: '๘', capsText: '8'),
    VirtualKey.character(text: '๙', capsText: '9'),
  ],
  [
    VirtualKey.character(text: '.'),
    VirtualKey.character(text: '๐', capsText: '0'),
    VirtualKey.action(action: KeyAction.backSpace),
  ],
];

/// Thai signed number pad layout.
final KeyboardLayout _signedNumberLayout = [
  [
    VirtualKey.character(text: '๑', capsText: '1'),
    VirtualKey.character(text: '๒', capsText: '2'),
    VirtualKey.character(text: '๓', capsText: '3'),
  ],
  [
    VirtualKey.character(text: '๔', capsText: '4'),
    VirtualKey.character(text: '๕', capsText: '5'),
    VirtualKey.character(text: '๖', capsText: '6'),
  ],
  [
    VirtualKey.character(text: '๗', capsText: '7'),
    VirtualKey.character(text: '๘', capsText: '8'),
    VirtualKey.character(text: '๙', capsText: '9'),
  ],
  [
    VirtualKey.character(text: '-'),
    VirtualKey.character(text: '๐', capsText: '0'),
    VirtualKey.character(text: '.'),
  ],
  [
    VirtualKey.action(action: KeyAction.backSpace, flex: 2),
    VirtualKey.action(action: KeyAction.done),
  ],
];

/// Thai phone dialer layout.
final KeyboardLayout _phoneLayout = [
  [
    VirtualKey.character(text: '๑', capsText: '1'),
    VirtualKey.character(text: '๒', capsText: '2'),
    VirtualKey.character(text: '๓', capsText: '3'),
  ],
  [
    VirtualKey.character(text: '๔', capsText: '4'),
    VirtualKey.character(text: '๕', capsText: '5'),
    VirtualKey.character(text: '๖', capsText: '6'),
  ],
  [
    VirtualKey.character(text: '๗', capsText: '7'),
    VirtualKey.character(text: '๘', capsText: '8'),
    VirtualKey.character(text: '๙', capsText: '9'),
  ],
  [
    VirtualKey.character(text: '*'),
    VirtualKey.character(text: '๐', capsText: '0'),
    VirtualKey.character(text: '#'),
  ],
  [
    VirtualKey.character(text: '+'),
    VirtualKey.action(action: KeyAction.backSpace),
    VirtualKey.action(action: KeyAction.call),
  ],
];

/// Thai (ไทย) keyboard language, Kedmanee layout.
final KeyboardLanguage thaiLanguage = KeyboardLanguage(
  code: 'th',
  name: 'Thai',
  nativeName: 'ไทย',
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
