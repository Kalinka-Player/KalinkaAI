import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/zone_aliases.dart';

void main() {
  test('every old name maps to a zone the box offers', () {
    // tzdata's zone.tab, which the box's supervisor offers zones from.
    final offered = {
      for (final line in File('test/fixtures/zone.tab').readAsLinesSync())
        if (!line.startsWith('#')) line.split('\t')[2],
    };
    for (final MapEntry(key: old, value: zone) in zoneAliases.entries) {
      expect(offered, contains(zone), reason: old);
      expect(offered, isNot(contains(old)), reason: old);
    }
  });
}
