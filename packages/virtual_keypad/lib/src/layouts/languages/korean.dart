import '../../enums.dart';
import '../../models.dart';
import '../keyboard_language.dart';

/// Korean Dubeolsik (두벌식) text layout - primary.
/// Standard 2-set Korean keyboard: consonants on the left, vowels on the right.
/// Shift produces double consonants (ㅃ ㅉ ㄸ ㄲ ㅆ) and compound vowels (ㅒ ㅖ).
/// The OS/IME auto-composes jamo into syllable blocks.
final KeyboardLayout _textLayoutPrimary = [
  [
    VirtualKey.character(text: 'ㅂ', capsText: 'ㅃ'),
    VirtualKey.character(text: 'ㅈ', capsText: 'ㅉ'),
    VirtualKey.character(text: 'ㄷ', capsText: 'ㄸ'),
    VirtualKey.character(text: 'ㄱ', capsText: 'ㄲ'),
    VirtualKey.character(text: 'ㅅ', capsText: 'ㅆ'),
    VirtualKey.character(text: 'ㅛ'),
    VirtualKey.character(text: 'ㅕ'),
    VirtualKey.character(text: 'ㅑ'),
    VirtualKey.character(text: 'ㅐ', capsText: 'ㅒ'),
    VirtualKey.character(text: 'ㅔ', capsText: 'ㅖ'),
  ],
  [
    VirtualKey.character(text: 'ㅁ'),
    VirtualKey.character(text: 'ㄴ'),
    VirtualKey.character(text: 'ㅇ'),
    VirtualKey.character(text: 'ㄹ'),
    VirtualKey.character(text: 'ㅎ'),
    VirtualKey.character(text: 'ㅗ'),
    VirtualKey.character(text: 'ㅓ'),
    VirtualKey.character(text: 'ㅏ'),
    VirtualKey.character(text: 'ㅣ'),
  ],
  [
    VirtualKey.action(action: KeyAction.shift, flex: 1.5),
    VirtualKey.character(text: 'ㅋ'),
    VirtualKey.character(text: 'ㅌ'),
    VirtualKey.character(text: 'ㅊ'),
    VirtualKey.character(text: 'ㅍ'),
    VirtualKey.character(text: 'ㅠ'),
    VirtualKey.character(text: 'ㅜ'),
    VirtualKey.character(text: 'ㅡ'),
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

/// Korean text layout - secondary (numbers & common symbols).
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
    VirtualKey.character(text: '₩'),
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

/// Korean text layout - tertiary (extra symbols).
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

/// Korean email keyboard - primary layout (Latin QWERTY for email addresses).
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

/// Korean URL keyboard - primary layout (Latin QWERTY for URL entry).
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

/// Korean (한국어) keyboard language, Dubeolsik (두벌식) layout.
final KeyboardLanguage koreanLanguage = KeyboardLanguage(
  code: 'ko',
  name: 'Korean',
  nativeName: '한국어',
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
