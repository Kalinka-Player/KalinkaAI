import '../../enums.dart';
import '../../models.dart';
import '../keyboard_language.dart';

/// Hindi text layout - primary (vowels and consonants).
final KeyboardLayout _textLayoutPrimary = [
  [
    VirtualKey.character(text: 'अ'),
    VirtualKey.character(text: 'आ', capsText: 'ा'),
    VirtualKey.character(text: 'इ', capsText: 'ि'),
    VirtualKey.character(text: 'ई', capsText: 'ी'),
    VirtualKey.character(text: 'उ', capsText: 'ु'),
    VirtualKey.character(text: 'ऊ', capsText: 'ू'),
    VirtualKey.character(text: 'ए', capsText: 'े'),
    VirtualKey.character(text: 'ऐ', capsText: 'ै'),
    VirtualKey.character(text: 'ओ', capsText: 'ो'),
    VirtualKey.character(text: 'औ', capsText: 'ौ'),
  ],
  [
    VirtualKey.character(text: 'क'),
    VirtualKey.character(text: 'ख'),
    VirtualKey.character(text: 'ग'),
    VirtualKey.character(text: 'घ'),
    VirtualKey.character(text: 'च'),
    VirtualKey.character(text: 'छ'),
    VirtualKey.character(text: 'ज'),
    VirtualKey.character(text: 'झ'),
    VirtualKey.character(text: 'ट'),
    VirtualKey.character(text: 'ठ'),
  ],
  [
    VirtualKey.character(text: 'ड'),
    VirtualKey.character(text: 'ढ'),
    VirtualKey.character(text: 'ण'),
    VirtualKey.character(text: 'त'),
    VirtualKey.character(text: 'थ'),
    VirtualKey.character(text: 'द'),
    VirtualKey.character(text: 'ध'),
    VirtualKey.character(text: 'न'),
    VirtualKey.character(text: 'प'),
    VirtualKey.character(text: 'फ'),
  ],
  [
    VirtualKey.action(action: KeyAction.shift, flex: 1.5),
    VirtualKey.character(text: 'ब'),
    VirtualKey.character(text: 'भ'),
    VirtualKey.character(text: 'म'),
    VirtualKey.character(text: 'य'),
    VirtualKey.character(text: 'र'),
    VirtualKey.character(text: 'ल'),
    VirtualKey.character(text: 'व'),
    VirtualKey.action(action: KeyAction.backSpace, flex: 1.5),
  ],
  [
    VirtualKey.action(
      action: KeyAction.symbols,
      label: '१२३',
      altLabel: 'अआइ',
      flex: 1,
    ),
    VirtualKey.character(text: 'श'),
    VirtualKey.character(text: 'ष'),
    VirtualKey.character(text: '्'),
    VirtualKey.action(action: KeyAction.space, flex: 3),
    VirtualKey.character(text: 'ं'),
    VirtualKey.character(text: '।'),
    VirtualKey.action(action: KeyAction.enter, flex: 1),
  ],
];

/// Hindi text layout - secondary (numbers, extra consonants and signs).
final KeyboardLayout _textLayoutSecondary = [
  [
    VirtualKey.character(text: '१', capsText: '1'),
    VirtualKey.character(text: '२', capsText: '2'),
    VirtualKey.character(text: '३', capsText: '3'),
    VirtualKey.character(text: '४', capsText: '4'),
    VirtualKey.character(text: '५', capsText: '5'),
    VirtualKey.character(text: '६', capsText: '6'),
    VirtualKey.character(text: '७', capsText: '7'),
    VirtualKey.character(text: '८', capsText: '8'),
    VirtualKey.character(text: '९', capsText: '9'),
    VirtualKey.character(text: '०', capsText: '0'),
  ],
  [
    VirtualKey.character(text: 'ङ'),
    VirtualKey.character(text: 'ञ'),
    VirtualKey.character(text: 'ड़'),
    VirtualKey.character(text: 'ढ़'),
    VirtualKey.character(text: 'स'),
    VirtualKey.character(text: 'ह'),
    VirtualKey.character(text: 'ः'),
    VirtualKey.character(text: 'ँ'),
    VirtualKey.character(text: 'ृ'),
    VirtualKey.character(text: 'ऋ'),
  ],
  [
    VirtualKey.action(
      action: KeyAction.symbolsAlt,
      label: '#+=',
      altLabel: '१२३',
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
      label: '१२३',
      altLabel: 'अआइ',
      flex: 1.5,
    ),
    VirtualKey.character(text: ','),
    VirtualKey.character(text: '्'),
    VirtualKey.action(action: KeyAction.space, flex: 3),
    VirtualKey.character(text: '।'),
    VirtualKey.character(text: '॥'),
    VirtualKey.action(action: KeyAction.enter, flex: 1.5),
  ],
];

/// Hindi text layout - tertiary (symbols and punctuation).
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
    VirtualKey.character(text: '₹'),
    VirtualKey.character(text: '\$'),
    VirtualKey.character(text: '€'),
    VirtualKey.character(text: '•'),
  ],
  [
    VirtualKey.action(
      action: KeyAction.symbolsAlt,
      label: '#+=',
      altLabel: '१२३',
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
      label: '१२३',
      altLabel: 'अआइ',
      flex: 2,
    ),
    VirtualKey.character(text: ','),
    VirtualKey.action(action: KeyAction.space, flex: 4),
    VirtualKey.character(text: '।'),
    VirtualKey.action(action: KeyAction.enter, flex: 2),
  ],
];

/// Hindi email keyboard - primary layout.
final KeyboardLayout _emailLayoutPrimary = [
  [
    VirtualKey.character(text: 'अ'),
    VirtualKey.character(text: 'आ', capsText: 'ा'),
    VirtualKey.character(text: 'इ', capsText: 'ि'),
    VirtualKey.character(text: 'ई', capsText: 'ी'),
    VirtualKey.character(text: 'उ', capsText: 'ु'),
    VirtualKey.character(text: 'ऊ', capsText: 'ू'),
    VirtualKey.character(text: 'ए', capsText: 'े'),
    VirtualKey.character(text: 'ऐ', capsText: 'ै'),
    VirtualKey.character(text: 'ओ', capsText: 'ो'),
    VirtualKey.character(text: 'औ', capsText: 'ौ'),
  ],
  [
    VirtualKey.character(text: 'क'),
    VirtualKey.character(text: 'ख'),
    VirtualKey.character(text: 'ग'),
    VirtualKey.character(text: 'घ'),
    VirtualKey.character(text: 'च'),
    VirtualKey.character(text: 'छ'),
    VirtualKey.character(text: 'ज'),
    VirtualKey.character(text: 'झ'),
    VirtualKey.character(text: 'ट'),
    VirtualKey.character(text: 'ठ'),
  ],
  [
    VirtualKey.action(action: KeyAction.shift, flex: 1.5),
    VirtualKey.character(text: 'ड'),
    VirtualKey.character(text: 'त'),
    VirtualKey.character(text: 'द'),
    VirtualKey.character(text: 'न'),
    VirtualKey.character(text: 'प'),
    VirtualKey.character(text: 'ब'),
    VirtualKey.character(text: 'म'),
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

/// Hindi email keyboard - secondary layout (numbers & symbols).
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

/// Hindi number pad layout.
final KeyboardLayout _numberLayout = [
  [
    VirtualKey.character(text: '१', capsText: '1'),
    VirtualKey.character(text: '२', capsText: '2'),
    VirtualKey.character(text: '३', capsText: '3'),
  ],
  [
    VirtualKey.character(text: '४', capsText: '4'),
    VirtualKey.character(text: '५', capsText: '5'),
    VirtualKey.character(text: '६', capsText: '6'),
  ],
  [
    VirtualKey.character(text: '७', capsText: '7'),
    VirtualKey.character(text: '८', capsText: '8'),
    VirtualKey.character(text: '९', capsText: '9'),
  ],
  [
    VirtualKey.character(text: '.'),
    VirtualKey.character(text: '०', capsText: '0'),
    VirtualKey.action(action: KeyAction.backSpace),
  ],
];

/// Hindi signed number pad layout.
final KeyboardLayout _signedNumberLayout = [
  [
    VirtualKey.character(text: '१', capsText: '1'),
    VirtualKey.character(text: '२', capsText: '2'),
    VirtualKey.character(text: '३', capsText: '3'),
  ],
  [
    VirtualKey.character(text: '४', capsText: '4'),
    VirtualKey.character(text: '५', capsText: '5'),
    VirtualKey.character(text: '६', capsText: '6'),
  ],
  [
    VirtualKey.character(text: '७', capsText: '7'),
    VirtualKey.character(text: '८', capsText: '8'),
    VirtualKey.character(text: '९', capsText: '9'),
  ],
  [
    VirtualKey.character(text: '-'),
    VirtualKey.character(text: '०', capsText: '0'),
    VirtualKey.character(text: '.'),
  ],
  [
    VirtualKey.action(action: KeyAction.backSpace, flex: 2),
    VirtualKey.action(action: KeyAction.done),
  ],
];

/// Hindi phone dialer layout.
final KeyboardLayout _phoneLayout = [
  [
    VirtualKey.character(text: '१', capsText: '1'),
    VirtualKey.character(text: '२', capsText: '2'),
    VirtualKey.character(text: '३', capsText: '3'),
  ],
  [
    VirtualKey.character(text: '४', capsText: '4'),
    VirtualKey.character(text: '५', capsText: '5'),
    VirtualKey.character(text: '६', capsText: '6'),
  ],
  [
    VirtualKey.character(text: '७', capsText: '7'),
    VirtualKey.character(text: '८', capsText: '8'),
    VirtualKey.character(text: '९', capsText: '9'),
  ],
  [
    VirtualKey.character(text: '*'),
    VirtualKey.character(text: '०', capsText: '0'),
    VirtualKey.character(text: '#'),
  ],
  [
    VirtualKey.character(text: '+'),
    VirtualKey.action(action: KeyAction.backSpace),
    VirtualKey.action(action: KeyAction.call),
  ],
];

/// Hindi (हिन्दी) keyboard language.
final KeyboardLanguage hindiLanguage = KeyboardLanguage(
  code: 'hi',
  name: 'Hindi',
  nativeName: 'हिन्दी',
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
