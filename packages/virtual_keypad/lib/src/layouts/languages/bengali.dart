import '../../enums.dart';
import '../../models.dart';
import '../keyboard_language.dart';

/// Bengali text layout - primary (common letters).
final KeyboardLayout _textLayoutPrimary = [
  [
    VirtualKey.character(text: 'অ'),
    VirtualKey.character(text: 'আ', capsText: 'া'),
    VirtualKey.character(text: 'ই', capsText: 'ি'),
    VirtualKey.character(text: 'ঈ', capsText: 'ী'),
    VirtualKey.character(text: 'উ', capsText: 'ু'),
    VirtualKey.character(text: 'ঊ', capsText: 'ূ'),
    VirtualKey.character(text: 'এ', capsText: 'ে'),
    VirtualKey.character(text: 'ঐ', capsText: 'ৈ'),
    VirtualKey.character(text: 'ও', capsText: 'ো'),
    VirtualKey.character(text: 'ঔ', capsText: 'ৌ'),
  ],
  [
    VirtualKey.character(text: 'ক'),
    VirtualKey.character(text: 'খ'),
    VirtualKey.character(text: 'গ'),
    VirtualKey.character(text: 'ঘ'),
    VirtualKey.character(text: 'চ'),
    VirtualKey.character(text: 'ছ'),
    VirtualKey.character(text: 'জ'),
    VirtualKey.character(text: 'ঝ'),
    VirtualKey.character(text: 'ট'),
    VirtualKey.character(text: 'ঠ'),
  ],
  [
    VirtualKey.character(text: 'ড'),
    VirtualKey.character(text: 'ঢ'),
    VirtualKey.character(text: 'ণ'),
    VirtualKey.character(text: 'ত'),
    VirtualKey.character(text: 'থ'),
    VirtualKey.character(text: 'দ'),
    VirtualKey.character(text: 'ধ'),
    VirtualKey.character(text: 'ন'),
    VirtualKey.character(text: 'প'),
    VirtualKey.character(text: 'ফ'),
  ],
  [
    VirtualKey.action(action: KeyAction.shift, flex: 1.5),
    VirtualKey.character(text: 'ব'),
    VirtualKey.character(text: 'ভ'),
    VirtualKey.character(text: 'ম'),
    VirtualKey.character(text: 'য'),
    VirtualKey.character(text: 'র'),
    VirtualKey.character(text: 'ল'),
    VirtualKey.character(text: 'শ'),
    VirtualKey.action(action: KeyAction.backSpace, flex: 1.5),
  ],
  [
    VirtualKey.action(
      action: KeyAction.symbols,
      label: '১২৩',
      altLabel: 'কখগ',
      flex: 1,
    ),
    VirtualKey.character(text: 'স'),
    VirtualKey.character(text: 'হ'),
    VirtualKey.character(text: '্'),
    VirtualKey.action(action: KeyAction.space, flex: 3),
    VirtualKey.character(text: 'ং'),
    VirtualKey.character(text: '।'),
    VirtualKey.action(action: KeyAction.enter, flex: 1),
  ],
];

/// Bengali text layout - secondary (numbers, conjuncts).
final KeyboardLayout _textLayoutSecondary = [
  [
    VirtualKey.character(text: '১', capsText: '1'),
    VirtualKey.character(text: '২', capsText: '2'),
    VirtualKey.character(text: '৩', capsText: '3'),
    VirtualKey.character(text: '৪', capsText: '4'),
    VirtualKey.character(text: '৫', capsText: '5'),
    VirtualKey.character(text: '৬', capsText: '6'),
    VirtualKey.character(text: '৭', capsText: '7'),
    VirtualKey.character(text: '৮', capsText: '8'),
    VirtualKey.character(text: '৯', capsText: '9'),
    VirtualKey.character(text: '০', capsText: '0'),
  ],
  [
    VirtualKey.character(text: 'ঙ'),
    VirtualKey.character(text: 'ঞ'),
    VirtualKey.character(text: 'ড়'),
    VirtualKey.character(text: 'ঢ়'),
    VirtualKey.character(text: 'য়'),
    VirtualKey.character(text: 'ৎ'),
    VirtualKey.character(text: 'ঃ'),
    VirtualKey.character(text: 'ঁ'),
    VirtualKey.character(text: 'ৃ'),
    VirtualKey.character(text: 'ঋ'),
  ],
  [
    VirtualKey.action(
      action: KeyAction.symbolsAlt,
      label: '#+=',
      altLabel: '১২৩',
      flex: 1.5,
    ),
    VirtualKey.character(text: '-'),
    VirtualKey.character(text: '/'),
    VirtualKey.character(text: ':'),
    VirtualKey.character(text: '?'),
    VirtualKey.character(text: '!'),
    VirtualKey.character(text: '"'),
    VirtualKey.character(text: "'"),
    VirtualKey.action(action: KeyAction.backSpace, flex: 1.5),
  ],
  [
    VirtualKey.action(
      action: KeyAction.symbols,
      label: '১২৩',
      altLabel: 'কখগ',
      flex: 1.5,
    ),
    VirtualKey.character(text: ','),
    VirtualKey.character(text: '্'),
    VirtualKey.action(action: KeyAction.space, flex: 3),
    VirtualKey.character(text: '।'),
    VirtualKey.character(text: '॥'),
    VirtualKey.action(action: KeyAction.enter, flex: 1.5),
  ],
];

/// Bengali text layout - tertiary (symbols and punctuation).
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
    VirtualKey.character(text: '৳'),
    VirtualKey.character(text: '₹'),
    VirtualKey.character(text: '\$'),
    VirtualKey.character(text: '•'),
  ],
  [
    VirtualKey.action(
      action: KeyAction.symbolsAlt,
      label: '#+=',
      altLabel: '১২৩',
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
      label: '১২৩',
      altLabel: 'কখগ',
      flex: 2,
    ),
    VirtualKey.character(text: ','),
    VirtualKey.action(action: KeyAction.space, flex: 4),
    VirtualKey.character(text: '।'),
    VirtualKey.action(action: KeyAction.enter, flex: 2),
  ],
];

/// Bengali email keyboard - primary layout.
final KeyboardLayout _emailLayoutPrimary = [
  [
    VirtualKey.character(text: 'অ'),
    VirtualKey.character(text: 'আ', capsText: 'া'),
    VirtualKey.character(text: 'ই', capsText: 'ি'),
    VirtualKey.character(text: 'ঈ', capsText: 'ী'),
    VirtualKey.character(text: 'উ', capsText: 'ু'),
    VirtualKey.character(text: 'ঊ', capsText: 'ূ'),
    VirtualKey.character(text: 'এ', capsText: 'ে'),
    VirtualKey.character(text: 'ঐ', capsText: 'ৈ'),
    VirtualKey.character(text: 'ও', capsText: 'ো'),
    VirtualKey.character(text: 'ঔ', capsText: 'ৌ'),
  ],
  [
    VirtualKey.character(text: 'ক'),
    VirtualKey.character(text: 'খ'),
    VirtualKey.character(text: 'গ'),
    VirtualKey.character(text: 'ঘ'),
    VirtualKey.character(text: 'চ'),
    VirtualKey.character(text: 'ছ'),
    VirtualKey.character(text: 'জ'),
    VirtualKey.character(text: 'ঝ'),
    VirtualKey.character(text: 'ট'),
    VirtualKey.character(text: 'ঠ'),
  ],
  [
    VirtualKey.action(action: KeyAction.shift, flex: 1.5),
    VirtualKey.character(text: 'ড'),
    VirtualKey.character(text: 'ত'),
    VirtualKey.character(text: 'দ'),
    VirtualKey.character(text: 'ন'),
    VirtualKey.character(text: 'প'),
    VirtualKey.character(text: 'ব'),
    VirtualKey.character(text: 'ম'),
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

/// Bengali email keyboard - secondary layout (numbers & symbols).
final KeyboardLayout _emailLayoutSecondary = [
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
    VirtualKey.character(text: '_'),
    VirtualKey.character(text: '.'),
    VirtualKey.character(text: '+'),
    VirtualKey.character(text: '('),
    VirtualKey.character(text: ')'),
    VirtualKey.character(text: '&'),
    VirtualKey.character(text: '@'),
    VirtualKey.character(text: '#'),
    VirtualKey.character(text: '%'),
  ],
  [
    VirtualKey.action(action: KeyAction.symbolsAlt, flex: 1.5),
    VirtualKey.character(text: '!'),
    VirtualKey.character(text: '?'),
    VirtualKey.character(text: "'"),
    VirtualKey.character(text: '"'),
    VirtualKey.character(text: ':'),
    VirtualKey.character(text: ';'),
    VirtualKey.character(text: '/'),
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

/// Bengali number pad layout.
final KeyboardLayout _numberLayout = [
  [
    VirtualKey.character(text: '১', capsText: '1'),
    VirtualKey.character(text: '২', capsText: '2'),
    VirtualKey.character(text: '৩', capsText: '3'),
  ],
  [
    VirtualKey.character(text: '৪', capsText: '4'),
    VirtualKey.character(text: '৫', capsText: '5'),
    VirtualKey.character(text: '৬', capsText: '6'),
  ],
  [
    VirtualKey.character(text: '৭', capsText: '7'),
    VirtualKey.character(text: '৮', capsText: '8'),
    VirtualKey.character(text: '৯', capsText: '9'),
  ],
  [
    VirtualKey.character(text: '.'),
    VirtualKey.character(text: '০', capsText: '0'),
    VirtualKey.action(action: KeyAction.backSpace),
  ],
];

/// Bengali signed number pad layout.
final KeyboardLayout _signedNumberLayout = [
  [
    VirtualKey.character(text: '১', capsText: '1'),
    VirtualKey.character(text: '২', capsText: '2'),
    VirtualKey.character(text: '৩', capsText: '3'),
  ],
  [
    VirtualKey.character(text: '৪', capsText: '4'),
    VirtualKey.character(text: '৫', capsText: '5'),
    VirtualKey.character(text: '৬', capsText: '6'),
  ],
  [
    VirtualKey.character(text: '৭', capsText: '7'),
    VirtualKey.character(text: '৮', capsText: '8'),
    VirtualKey.character(text: '৯', capsText: '9'),
  ],
  [
    VirtualKey.character(text: '-'),
    VirtualKey.character(text: '০', capsText: '0'),
    VirtualKey.character(text: '.'),
  ],
  [
    VirtualKey.action(action: KeyAction.backSpace, flex: 2),
    VirtualKey.action(action: KeyAction.done),
  ],
];

/// Bengali phone dialer layout.
final KeyboardLayout _phoneLayout = [
  [
    VirtualKey.character(text: '১', capsText: '1'),
    VirtualKey.character(text: '২', capsText: '2'),
    VirtualKey.character(text: '৩', capsText: '3'),
  ],
  [
    VirtualKey.character(text: '৪', capsText: '4'),
    VirtualKey.character(text: '৫', capsText: '5'),
    VirtualKey.character(text: '৬', capsText: '6'),
  ],
  [
    VirtualKey.character(text: '৭', capsText: '7'),
    VirtualKey.character(text: '৮', capsText: '8'),
    VirtualKey.character(text: '৯', capsText: '9'),
  ],
  [
    VirtualKey.character(text: '*'),
    VirtualKey.character(text: '০', capsText: '0'),
    VirtualKey.character(text: '#'),
  ],
  [
    VirtualKey.character(text: '+'),
    VirtualKey.action(action: KeyAction.backSpace),
    VirtualKey.action(action: KeyAction.call),
  ],
];

/// Bengali (বাংলা) keyboard language.
final KeyboardLanguage bengaliLanguage = KeyboardLanguage(
  code: 'bn',
  name: 'Bengali',
  nativeName: 'বাংলা',
  textLayouts: KeyboardLayoutSet(
    primary: _textLayoutPrimary,
    secondary: _textLayoutSecondary,
    tertiary: _textLayoutTertiary,
  ),
  emailLayouts: KeyboardLayoutSet(
    primary: _emailLayoutPrimary,
    secondary: _emailLayoutSecondary,
  ),
  numberLayouts: KeyboardLayoutSet.single(_numberLayout),
  numberSignedLayouts: KeyboardLayoutSet.single(_signedNumberLayout),
  numberDecimalLayouts: KeyboardLayoutSet.single(_numberLayout),
  phoneLayouts: KeyboardLayoutSet.single(_phoneLayout),
);
