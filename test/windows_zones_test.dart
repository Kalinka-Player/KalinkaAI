import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/windows_zones.dart';

void main() {
  test('maps a Windows zone to its tzdata zone', () {
    expect(tzdataZoneFor('W. Europe Standard Time'), 'Europe/Berlin');
    expect(
      tzdataZoneFor('W. Europe Standard Time', territory: '001'),
      'Europe/Berlin',
    );
    expect(tzdataZoneFor('Pacific Standard Time'), 'America/Los_Angeles');
    expect(tzdataZoneFor('UTC'), 'Etc/UTC');
  });

  test('prefers the zone of the territory', () {
    expect(
      tzdataZoneFor('W. Europe Standard Time', territory: 'CH'),
      'Europe/Zurich',
    );
    expect(
      tzdataZoneFor('W. Europe Standard Time', territory: 'US'),
      'Europe/Berlin',
    );
    expect(tzdataZoneFor('UTC-11', territory: 'AS'), 'Pacific/Pago_Pago');
  });

  test('keeps Canada on the zone that follows the Windows one', () {
    expect(
      tzdataZoneFor('British Columbia Standard Time', territory: 'CA'),
      'America/Vancouver',
    );
    expect(
      tzdataZoneFor('Pacific Standard Time', territory: 'CA'),
      'America/Los_Angeles',
    );
    expect(
      tzdataZoneFor('Central Standard Time', territory: 'CA'),
      'America/Rankin_Inlet',
    );
  });

  test('names no zone for an ID it does not know', () {
    expect(tzdataZoneFor('Mars Standard Time'), isNull);
    // tzutil appends _dstoff when daylight saving is turned off, which no
    // zone follows.
    expect(tzdataZoneFor('Pacific Standard Time_dstoff'), isNull);
    expect(tzdataZoneFor('UTC-11'), isNull);
  });

  test('every zone it names is one the box offers, in its territory', () {
    // tzdata's zone.tab, which the box's supervisor offers zones from.
    final rows = [
      for (final line in File('test/fixtures/zone.tab').readAsLinesSync())
        if (!line.startsWith('#')) line.split('\t'),
    ];
    final countries = <String, Set<String>>{};
    for (final [country, _, zone, ...] in rows) {
      (countries[zone] ??= {}).add(country);
    }
    // A new box is on Etc/UTC, so its picker lists that too.
    final offered = {'UTC', 'Etc/UTC', ...countries.keys};
    for (final MapEntry(key: id, value: zones) in windowsZones.entries) {
      for (final MapEntry(key: territory, value: zone) in zones.entries) {
        expect(offered, contains(zone), reason: '$id, $territory');
        if (territory != '001') {
          expect(countries[zone], contains(territory), reason: '$id, $zone');
        }
      }
    }
  });
}
