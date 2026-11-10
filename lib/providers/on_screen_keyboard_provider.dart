import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connection_settings_provider.dart';
import 'kiosk_provider.dart';

/// This client's input preference, independent of the connected server.
class OnScreenKeyboardNotifier extends Notifier<bool> {
  static const preferenceKey = 'Kalinka.client.onScreenKeyboard';

  @override
  bool build() =>
      ref.read(sharedPrefsProvider).getBool(preferenceKey) ??
      ref.read(localDisplayKioskProvider);

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    await ref.read(sharedPrefsProvider).setBool(preferenceKey, enabled);
  }
}

final onScreenKeyboardProvider =
    NotifierProvider<OnScreenKeyboardNotifier, bool>(
      OnScreenKeyboardNotifier.new,
    );
