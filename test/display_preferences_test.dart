import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/display_settings_provider.dart';
import 'package:kalinka/utils/display_power_io.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'display defaults and edited timeouts survive a new provider container',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      ProviderContainer container() => ProviderContainer(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      );
      final first = container();
      addTearDown(first.dispose);
      expect(first.read(displaySettingsProvider).kioskSeconds, 30);
      expect(first.read(displaySettingsProvider).blankSeconds, 300);
      await first.read(displaySettingsProvider.notifier).setKioskSeconds(45);
      await first.read(displaySettingsProvider.notifier).setBlankSeconds(0);
      final next = container();
      addTearDown(next.dispose);
      expect(next.read(displaySettingsProvider).kioskSeconds, 45);
      expect(next.read(displaySettingsProvider).blankSeconds, 0);
    },
  );

  test('saved timeouts are bounded; only blanking accepts zero', () async {
    SharedPreferences.setMockInitialValues({
      DisplaySettingsNotifier.kioskKey: 0,
      DisplaySettingsNotifier.blankKey: -30,
    });
    final c = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
      ],
    );
    addTearDown(c.dispose);
    expect(c.read(displaySettingsProvider).kioskSeconds, 1);
    expect(c.read(displaySettingsProvider).blankSeconds, 0);
    await c.read(displaySettingsProvider.notifier).setBlankSeconds(999999999);
    expect(
      c.read(displaySettingsProvider).blankSeconds,
      DisplaySettings.maxSeconds,
    );
  });

  group('backlight hardware adapter', () {
    late Directory directory;
    late File control;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'kalinka-display-test-',
      );
      control = File('${directory.path}/bl_power');
      await control.writeAsString('0\n');
    });
    tearDown(() => directory.delete(recursive: true));

    test('capability checks never change power; blank and wake write the ABI values', () async {
      final power = BacklightDisplayPower(control);
      expect(await power.available, isTrue);
      expect(await control.readAsString(), '0\n');
      expect(await power.setBlanked(true), isTrue);
      expect(await control.readAsString(), '4');
      expect(await power.setBlanked(false), isTrue);
      expect(await control.readAsString(), '0');
    });

    test('a wake queued during blanking always wins', () async {
      final power = BacklightDisplayPower(control);
      final off = power.setBlanked(true);
      final on = power.setBlanked(false);
      expect(await off, isTrue);
      expect(await on, isTrue);
      expect(await control.readAsString(), '0');
    });

    test('repeated blanking retains the original power value', () async {
      await control.writeAsString('1');
      final power = BacklightDisplayPower(control);
      await power.setBlanked(true);
      await power.setBlanked(true);
      await power.setBlanked(false);
      expect(await control.readAsString(), '1');
    });

    test('missing and invalid controls fall back without throwing', () async {
      final power = BacklightDisplayPower(control);
      await control.writeAsString('unsupported');
      expect(await power.available, isFalse);
      expect(await power.setBlanked(true), isFalse);
      await control.delete();
      expect(await power.available, isFalse);
      expect(await power.setBlanked(true), isFalse);
    });
  });
}
