import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'soundcard_fakes.dart';

final _boxOrPi = RegExp(r'\b(box|Pi)\b', caseSensitive: false);

// They name hardware, not the device the app talks to.
final _hardware = [
  'THE PI’S OWN OUTPUTS',
  for (final option in soundcardOptions) option.label,
];

/// Every text on screen.
Iterable<String> shownText(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((text) => text.text.toPlainText());

/// Those of [copy] that call the device the box or the Pi.
Iterable<String> callingItBoxOrPi(Iterable<String> copy) => copy.where(
  (text) => _boxOrPi.hasMatch(
    _hardware.fold(text, (rest, name) => rest.replaceAll(name, '')),
  ),
);
