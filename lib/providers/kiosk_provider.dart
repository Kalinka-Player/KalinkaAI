import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/local_platform.dart';
import 'connection_settings_provider.dart';

/// Whether the app was started as a display: `--dart-define=KALINKA_KIOSK=…`;
/// failing that a `KALINKA_KIOSK` environment variable, so an installed build
/// can be started as one; failing that `?kiosk` on the page URL — the only
/// switch a browser has. Any value but an "off" word counts.
bool parseKioskLaunch(String define, String? environment, Uri pageUrl) {
  if (define.isNotEmpty) return _isOn(define);
  if (environment != null && environment.isNotEmpty) return _isOn(environment);
  final query = pageUrl.queryParameters;
  return query.containsKey('kiosk') && _isOn(query['kiosk']!);
}

bool _isOn(String value) =>
    !const {'false', '0', 'off', 'no'}.contains(value.trim().toLowerCase());

final kioskLaunchProvider = Provider<bool>(
  (ref) => parseKioskLaunch(
    const String.fromEnvironment('KALINKA_KIOSK'),
    environmentValue('KALINKA_KIOSK'),
    Uri.base,
  ),
);

/// Why the display is up, which decides the way out of it.
enum KioskLock {
  /// Opened from the player: the exit button leaves.
  none,

  /// This device's setting: five taps on the logo leave, and turn it off.
  device,

  /// Started by the launch flag: no way out. Outranks the setting.
  launch,
}

@immutable
class KioskState {
  final bool active;
  final KioskLock lock;

  const KioskState({required this.active, required this.lock});

  static const inactive = KioskState(active: false, lock: KioskLock.none);

  @override
  bool operator ==(Object other) =>
      other is KioskState && other.active == active && other.lock == lock;

  @override
  int get hashCode => Object.hash(active, lock);
}

class KioskNotifier extends Notifier<KioskState> {
  static const sharedPrefLocked = 'Kalinka.kioskLocked';

  /// Whether this run began on the display, rather than reaching it later.
  bool startedAsDisplay = false;

  @override
  KioskState build() {
    final KioskState initial;
    if (ref.watch(kioskLaunchProvider)) {
      initial = const KioskState(active: true, lock: KioskLock.launch);
    } else if (ref.read(sharedPrefsProvider).getBool(sharedPrefLocked) ??
        false) {
      initial = const KioskState(active: true, lock: KioskLock.device);
    } else {
      initial = KioskState.inactive;
    }
    startedAsDisplay = initial.active;
    return initial;
  }

  /// This device's setting, as stored.
  bool get lockedToDevice =>
      ref.read(sharedPrefsProvider).getBool(sharedPrefLocked) ?? false;

  /// Opens the display from the player.
  void enter() {
    if (!state.active) {
      state = const KioskState(active: true, lock: KioskLock.none);
    }
  }

  /// The exit button: leaves only a display the player opened.
  void exit() {
    if (state.lock == KioskLock.none) state = KioskState.inactive;
  }

  /// Turns this device's setting on: the display comes up now and on every
  /// launch after, until five taps on its logo turn it off.
  Future<void> lockToDevice() async {
    await ref.read(sharedPrefsProvider).setBool(sharedPrefLocked, true);
    state = const KioskState(active: true, lock: KioskLock.device);
  }

  /// Five taps on the logo: leaves a display this device's setting holds, and
  /// turns the setting off. Does nothing to one the launch flag started.
  Future<void> unlockDevice() async {
    if (state.lock != KioskLock.device) return;
    await ref.read(sharedPrefsProvider).setBool(sharedPrefLocked, false);
    state = KioskState.inactive;
  }
}

final kioskProvider = NotifierProvider<KioskNotifier, KioskState>(
  KioskNotifier.new,
);

final kioskActiveProvider = Provider<bool>(
  (ref) => ref.watch(kioskProvider.select((s) => s.active)),
);

/// Whether the logo still owes its one showing: at the start of a run that
/// begins on the display, never on reaching it later.
class KioskSplashNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(kioskProvider.notifier).startedAsDisplay;

  void shown() => state = false;
}

final kioskSplashPendingProvider = NotifierProvider<KioskSplashNotifier, bool>(
  KioskSplashNotifier.new,
);
