import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connection_settings_provider.dart';

class DisplaySettings {
  final int kioskSeconds;
  final int blankSeconds;

  const DisplaySettings({this.kioskSeconds = 30, this.blankSeconds = 300});

  static const maxSeconds = 86400;

  Duration get kioskTimeout => Duration(seconds: kioskSeconds);
  Duration get blankTimeout => Duration(seconds: blankSeconds);
}

/// Preferences for the display running this UI, independent of server config.
class DisplaySettingsNotifier extends Notifier<DisplaySettings> {
  static const kioskKey = 'Kalinka.display.kioskSeconds';
  static const blankKey = 'Kalinka.display.blankSeconds';

  @override
  DisplaySettings build() {
    final prefs = ref.read(sharedPrefsProvider);
    return DisplaySettings(
      kioskSeconds: (prefs.getInt(kioskKey) ?? 30).clamp(
        1,
        DisplaySettings.maxSeconds,
      ),
      blankSeconds: (prefs.getInt(blankKey) ?? 300).clamp(
        0,
        DisplaySettings.maxSeconds,
      ),
    );
  }

  Future<void> setKioskSeconds(int seconds) async {
    final value = seconds.clamp(1, DisplaySettings.maxSeconds);
    state = DisplaySettings(
      kioskSeconds: value,
      blankSeconds: state.blankSeconds,
    );
    await ref.read(sharedPrefsProvider).setInt(kioskKey, value);
  }

  Future<void> setBlankSeconds(int seconds) async {
    final value = seconds.clamp(0, DisplaySettings.maxSeconds);
    state = DisplaySettings(
      kioskSeconds: state.kioskSeconds,
      blankSeconds: value,
    );
    await ref.read(sharedPrefsProvider).setInt(blankKey, value);
  }
}

final displaySettingsProvider =
    NotifierProvider<DisplaySettingsNotifier, DisplaySettings>(
      DisplaySettingsNotifier.new,
    );
