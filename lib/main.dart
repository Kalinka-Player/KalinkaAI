import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/kiosk_screen.dart';
import 'screens/music_player_screen.dart';
import 'theme/app_theme.dart';
import 'providers/connection_settings_provider.dart';
import 'providers/kiosk_provider.dart';
import 'providers/onboarding_provider.dart';
import 'providers/renderer_host_provider.dart';
import 'providers/web_origin.dart';
import 'widgets/kalinka_toast_overlay.dart';

/// Dev-only (web): `host:port` of a CORS-enabled proxy to use instead of the
/// serving origin. See scripts/run_web_dev.sh.
const _webBackendOverride = String.fromEnvironment('KALINKA_WEB_BACKEND');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'IBM Plex Sans',
      'IBM Plex Mono',
    ], await rootBundle.loadString('assets/fonts/OFL-IBMPlex.txt'));
    yield LicenseEntryWithLineBreaks([
      'Playfair Display',
    ], await rootBundle.loadString('assets/fonts/OFL-PlayfairDisplay.txt'));
  });

  final prefs = await SharedPreferences.getInstance();

  // Web is served by the server itself (same origin as its API): seed the
  // connection from the origin and mark first-run done — there is no mDNS in
  // the browser and nothing local left to ask about. That does not skip
  // setup: MusicPlayerScreen still runs the wizard, minus discovery, when
  // the server reports itself unconfigured.
  if (kIsWeb) {
    var origin = webServingOrigin();
    final sep = _webBackendOverride.lastIndexOf(':');
    final overridePort = sep > 0
        ? int.tryParse(_webBackendOverride.substring(sep + 1))
        : null;
    if (overridePort != null) {
      origin = (
        host: _webBackendOverride.substring(0, sep),
        port: overridePort,
      );
    }
    if (origin != null) {
      await prefs.setString(
        ConnectionSettingsNotifier.sharedPrefName,
        'Kalinka',
      );
      await prefs.setString(
        ConnectionSettingsNotifier.sharedPrefHost,
        origin.host,
      );
      await prefs.setInt(
        ConnectionSettingsNotifier.sharedPrefPort,
        origin.port,
      );
      await prefs.setBool(
        OnboardingStatusNotifier.sharedPrefOobeComplete,
        true,
      );
    }
  }

  runApp(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const KalinkaApp(),
    ),
  );
}

class KalinkaApp extends ConsumerWidget {
  const KalinkaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(rendererHostProvider);
    return MaterialApp(
      title: 'Kalinka',
      theme: AppTheme.dark(),
      debugShowCheckedModeBanner: false,
      builder: (_, child) => KalinkaToastHost(child: child!),
      home: const _Home(),
    );
  }
}

/// The kiosk display, once there is a server to show — until then the full
/// app, which runs the setup wizard and hands over when it finishes.
class _Home extends ConsumerWidget {
  const _Home();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kiosk =
        ref.watch(kioskActiveProvider) &&
        ref.watch(onboardingStatusProvider.select((s) => s.oobeComplete)) &&
        ref.watch(connectionSettingsProvider.select((s) => s.isSet));
    return kiosk ? const KioskScreen() : const MusicPlayerScreen();
  }
}
