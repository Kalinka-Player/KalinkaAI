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
import 'providers/media_notification_provider.dart';
import 'providers/pinned_server.dart';
import 'widgets/kalinka_toast_overlay.dart';
import 'widgets/foreground_volume_overlay.dart';

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

  // Tied to one server — the web app to the one serving it, the display on
  // the server's own screen to its host: seed the connection and mark
  // first-run done, there is nothing to discover. That does not skip setup:
  // MusicPlayerScreen still runs the wizard, minus discovery, when the
  // server reports itself unconfigured.
  final server = pinnedServer();
  if (server != null) {
    await prefs.setString(ConnectionSettingsNotifier.sharedPrefName, 'Kalinka');
    await prefs.setString(
      ConnectionSettingsNotifier.sharedPrefHost,
      server.host,
    );
    await prefs.setInt(ConnectionSettingsNotifier.sharedPrefPort, server.port);
    await prefs.setString(
      ConnectionSettingsNotifier.sharedPrefScheme,
      server.scheme,
    );
    await prefs.setBool(OnboardingStatusNotifier.sharedPrefOobeComplete, true);
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
    ref.watch(mediaNotificationProvider);
    return MaterialApp(
      title: 'Kalinka',
      theme: AppTheme.dark(),
      debugShowCheckedModeBanner: false,
      builder: (_, child) =>
          ForegroundVolumeOverlay(child: KalinkaToastHost(child: child!)),
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
