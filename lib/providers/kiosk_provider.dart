import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, immutable, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/local_platform.dart';

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

/// Set only by the server's flutter-pi launcher, which runs while the server's
/// display setting is enabled. Browser and desktop launch flags stay separate.
final localDisplayKioskProvider = Provider<bool>(
  (ref) =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.linux &&
      environmentValue('KALINKA_LOCAL_DISPLAY') == 'true' &&
      ref.watch(kioskLaunchProvider),
);

/// Why the display is up, which decides the way out of it.
enum KioskLock {
  /// Opened from the player: the exit button leaves.
  none,

  /// Server display: Home leaves temporarily; inactivity brings it back.
  server,

  /// Started by the launch flag: no way out.
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
  /// Whether this run began on the display, rather than reaching it later.
  bool startedAsDisplay = false;

  @override
  KioskState build() {
    final KioskState initial;
    // Launch options are fixed for this process. Read them once so a provider
    // refresh cannot overwrite the user's temporary return to Home.
    if (ref.read(localDisplayKioskProvider)) {
      initial = const KioskState(active: true, lock: KioskLock.server);
    } else if (ref.read(kioskLaunchProvider)) {
      initial = const KioskState(active: true, lock: KioskLock.launch);
    } else {
      initial = KioskState.inactive;
    }
    startedAsDisplay = initial.active;
    return initial;
  }

  /// Opens the display from the player.
  void enter() {
    if (!state.active) {
      state = KioskState(active: true, lock: state.lock);
    }
  }

  /// Home temporarily leaves a server display without disabling its setting.
  /// Other displays retain their existing exit rules.
  void exit() {
    if (state.lock == KioskLock.none || state.lock == KioskLock.server) {
      state = KioskState(active: false, lock: state.lock);
    }
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
