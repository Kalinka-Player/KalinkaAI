import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/local_platform.dart';

/// How the app was launched: as the regular app, or as a full-screen
/// now-playing display that can be left ([switchable]) or not ([locked],
/// for a screen built into a streamer).
enum KioskMode { off, switchable, locked }

/// Reads the launch mode from `--dart-define=KALINKA_KIOSK=true|locked`;
/// failing that from a `KALINKA_KIOSK` environment variable, so an installed
/// build can be started as a display; failing that from `?kiosk` /
/// `?kiosk=locked` on the page URL — the only switch a browser has.
KioskMode parseKioskMode(String define, String? environment, Uri pageUrl) {
  if (define.isNotEmpty) return _modeFrom(define);
  if (environment != null && environment.isNotEmpty) {
    return _modeFrom(environment);
  }
  final query = pageUrl.queryParameters;
  if (!query.containsKey('kiosk')) return KioskMode.off;
  return _modeFrom(query['kiosk']!);
}

KioskMode _modeFrom(String value) {
  switch (value.trim().toLowerCase()) {
    case 'locked':
      return KioskMode.locked;
    case 'false' || '0' || 'off' || 'no':
      return KioskMode.off;
    default:
      return KioskMode.switchable;
  }
}

final kioskLaunchModeProvider = Provider<KioskMode>(
  (ref) => parseKioskMode(
    const String.fromEnvironment('KALINKA_KIOSK'),
    environmentValue('KALINKA_KIOSK'),
    Uri.base,
  ),
);

/// Whether the display is up. Starts as the launch mode says and can be
/// entered from the full app at any time; leaving it is refused when the
/// mode is locked.
class KioskNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(kioskLaunchModeProvider) != KioskMode.off;

  bool get canExit => ref.read(kioskLaunchModeProvider) != KioskMode.locked;

  void enter() => state = true;

  void exit() {
    if (canExit) state = false;
  }
}

final kioskActiveProvider = NotifierProvider<KioskNotifier, bool>(
  KioskNotifier.new,
);

/// Whether the logo still owes its one showing: at the start of a run
/// launched as a display, never on entering the display from the app.
class KioskSplashNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(kioskLaunchModeProvider) != KioskMode.off;

  void shown() => state = false;
}

final kioskSplashPendingProvider = NotifierProvider<KioskSplashNotifier, bool>(
  KioskSplashNotifier.new,
);
