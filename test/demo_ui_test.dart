// What a visitor to the demo server sees: a way in from discovery, a mark on
// the server it is connected to, and a prompt instead of a saved setting.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/presentation_schema.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/demo_mode.dart';
import 'package:kalinka/providers/discovery_provider.dart';
import 'package:kalinka/providers/discovery_types.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/screens/settings_screen.dart';
import 'package:kalinka/widgets/demo_read_only_dialog.dart';
import 'package:kalinka/widgets/discovery_screen.dart';
import 'package:kalinka/widgets/server_sheet.dart';

class _FakeApi implements KalinkaPlayerProxy {
  _FakeApi({this.demo = false});

  final bool demo;
  int restarts = 0;
  int saves = 0;
  int modulesListed = 0;

  @override
  Future<Map<String, dynamic>> getSettings() async => {
    'schema_version': 'v1',
    'values': {demoModeFlagPath: demo},
    'enum_options': const {},
  };

  // What the demo server's General page carries; an ordinary server, nothing.
  @override
  Future<PresentationSchema> getSettingsSchema() async => PresentationSchema(
    schemaVersion: 'v1',
    pages: [
      PageSpec(
        id: 'general',
        title: 'General',
        banners: [
          if (demo)
            const BannerSpec(
              title: 'Demo server',
              text: 'Settings can be explored but not saved.',
              severity: Severity.info,
            ),
        ],
      ),
    ],
    expertFields: const [],
  );

  @override
  Future<Set<String>?> saveSettings({
    required String schemaVersion,
    required Map<String, dynamic> changes,
  }) async {
    saves++;
    return null;
  }

  @override
  Future<void> restartServer() async => restarts++;

  @override
  Future<ModulesAndDevices> listModules() async {
    modulesListed++;
    return ModulesAndDevices(inputModules: [], devices: []);
  }

  @override
  Future<Map<String, dynamic>> getServerVersion() async => {
    'server_version': '5.8.0',
  };

  @override
  Future<Map<String, dynamic>?> getServerUpdateInfo() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _Connection extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

class _NothingFound extends DiscoveryNotifier {
  @override
  DiscoveryState build() => const DiscoveryState();

  @override
  Future<void> startScan() async {}

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> rescan() async {}
}

Future<SharedPreferences> _prefs([Map<String, Object> stored = const {}]) {
  SharedPreferences.setMockInitialValues(stored);
  return SharedPreferences.getInstance();
}

Future<void> _pumpSettings(WidgetTester tester, _FakeApi api) async {
  await tester.binding.setSurfaceSize(const Size(400, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(await _prefs()),
        kalinkaProxyProvider.overrideWithValue(api),
        connectionStateProvider.overrideWith(_Connection.new),
      ],
      child: MaterialApp(home: SettingsScreen(onClose: () {})),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  group('Settings on the demo server', () {
    testWidgets('restarting explains the demo instead', (tester) async {
      final api = _FakeApi(demo: true);
      await _pumpSettings(tester, api);

      expect(find.text('Demo server'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.restart_alt));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(DemoReadOnlyDialog), findsOneWidget);
      expect(find.text('Restart server?'), findsNothing);
      await tester.tap(find.text('Got it'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(DemoReadOnlyDialog), findsNothing);
      expect(api.restarts, 0);
      expect(api.saves, 0);
    });

    testWidgets('an ordinary server still asks to restart', (tester) async {
      await _pumpSettings(tester, _FakeApi());

      await tester.tap(find.byIcon(Icons.restart_alt));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Restart server?'), findsOneWidget);
      expect(find.byType(DemoReadOnlyDialog), findsNothing);
    });
  });

  for (final demo in [true, false]) {
    testWidgets('the server sheet marks a demo server: $demo', (tester) async {
      final prefs = await _prefs({
        ConnectionSettingsNotifier.sharedPrefName: 'Kalinka demo',
        ConnectionSettingsNotifier.sharedPrefHost: 'demo.test',
        ConnectionSettingsNotifier.sharedPrefPort: 443,
        ConnectionSettingsNotifier.sharedPrefScheme: 'https',
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPrefsProvider.overrideWithValue(prefs),
            kalinkaProxyProvider.overrideWithValue(_FakeApi()),
            connectionStateProvider.overrideWith(_Connection.new),
            demoModeProvider.overrideWithValue(demo),
          ],
          child: const MaterialApp(home: Scaffold(body: ServerSheetContent())),
        ),
      );
      await tester.pump();

      expect(find.text('DEMO'), demo ? findsOneWidget : findsNothing);
      expect(find.textContaining('demo.test'), findsOneWidget);
      expect(find.textContaining(':443'), findsNothing);
    });
  }

  testWidgets('discovery offers the demo server when nothing is found', (
    tester,
  ) async {
    final prefs = await _prefs();
    final api = _FakeApi(demo: true);
    var closed = false;
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          kalinkaProxyProvider.overrideWithValue(api),
          connectionStateProvider.overrideWith(_Connection.new),
          discoveryProvider.overrideWith(_NothingFound.new),
        ],
        child: MaterialApp(
          home: Scaffold(body: DiscoveryScreen(onClose: () => closed = true)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('Try demo server'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(DiscoveryScreen)),
    );
    final settings = container.read(connectionSettingsProvider);
    expect(settings.name, demoServerName);
    expect(
      (settings.scheme, settings.host, settings.port),
      ('https', 'demo.kalinkaplayer.com', 443),
    );
    expect(
      prefs.getString(ConnectionSettingsNotifier.sharedPrefScheme),
      'https',
    );
    expect(api.modulesListed, 1);
    expect(closed, isTrue);
  });
}
