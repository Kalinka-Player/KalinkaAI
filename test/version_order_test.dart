// The server decides whether its bundle is behind with PEP 440's order, so the
// app has to order versions the same way to know whether Core will move.

import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/utils/version_order.dart';

void main() {
  test('versions follow PEP 440\'s own example order', () {
    const ordered = [
      '1.0.dev456',
      '1.0a1',
      '1.0a2.dev456',
      '1.0a12.dev456',
      '1.0a12',
      '1.0b1.dev456',
      '1.0b2',
      '1.0b2.post345.dev456',
      '1.0b2.post345',
      '1.0rc1.dev456',
      '1.0rc1',
      '1.0',
      '1.0+abc.5',
      '1.0+abc.7',
      '1.0+5',
      '1.0.post456.dev34',
      '1.0.post456',
      '1.1.dev1',
    ];
    for (var i = 0; i < ordered.length; i++) {
      for (var j = 0; j < ordered.length; j++) {
        expect(
          isNewerVersion(ordered[j], ordered[i]),
          j > i,
          reason: '${ordered[j]} against ${ordered[i]}',
        );
      }
    }
  });

  for (final (latest, current, newer) in [
    ('5.16.0', '5.17.0rc1', false),
    ('5.17.0rc1', '5.16.0', true),
    ('5.17.0', '5.17.0rc1', true),
    ('5.10.0', '5.9.0', true),
    ('5.16', '5.16.0', false),
    ('5.16.0', '5.16', false),
    ('5.16.1', '5.16.1.dev3+g1a2b3c4.d20261102', true),
    ('5.16.0', '5.16.1.dev3+g1a2b3c4.d20261102', false),
    ('5.16.0', 'v5.16.0', false),
    ('5.17.0RC1', '5.17.0rc1', false),
    ('1.0alpha1', '1.0a1', false),
    ('1.0c1', '1.0rc1', false),
    ('1.0rc1', '1.0c1', false),
    ('5.16.0-1', '5.16.0', true),
    ('1!1.0', '2.0', true),
    ('nightly', '5.16.0', false),
    ('5.16.0', 'nightly', false),
    ('', '5.16.0', false),
  ]) {
    test('$latest is ${newer ? '' : 'not '}newer than $current', () {
      expect(isNewerVersion(latest, current), newer);
    });
  }
}
