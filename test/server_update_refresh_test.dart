// The release check resolves once and is cached for the app session, so an
// answer taken minutes before a release would stand until the app restarts.
// Opening settings has to drop that cache and ask again.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/server_update_provider.dart';
import 'package:kalinka/providers/settings_provider.dart';
import 'package:kalinka/screens/settings_screen.dart';

class _CountingApi implements KalinkaPlayerProxy {
  int updateChecks = 0;

  @override
  Future<Map<String, dynamic>?> getServerUpdateInfo() async {
    updateChecks++;
    return {
      'current_version': '4.1.0',
      'latest_version': '4.2.0',
      'update_available': true,
      'upgrade_supported': true,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeConnectionNotifier extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

/// The screen loads config on open; that path is not what this test drives.
class _InertSettingsNotifier extends SettingsNotifier {
  @override
  SettingsState build() => const SettingsState();

  @override
  Future<void> loadConfig() async {}
}

Future<ProviderContainer> _makeContainer(_CountingApi api) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      kalinkaProxyProvider.overrideWithValue(api),
      connectionStateProvider.overrideWith(_FakeConnectionNotifier.new),
      settingsProvider.overrideWith(_InertSettingsNotifier.new),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _openSettings(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SettingsScreen()),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('opening settings re-checks for a release', (tester) async {
    final api = _CountingApi();
    final container = await _makeContainer(api);

    // The stale answer a long-lived session is left holding.
    await container.read(serverUpdateProvider.future);
    expect(api.updateChecks, 1);

    await _openSettings(tester, container);

    expect(await container.read(serverUpdateProvider.future), isNotNull);
    expect(api.updateChecks, 2);
  });

  // With anything else watching the check when the panel mounts (as the
  // outgoing panel's banner did, back when a resize remounted settings),
  // invalidating it in initState trips a setState-during-build on the
  // ProviderScope.
  testWidgets('opening settings while the check is watched does not throw', (
    tester,
  ) async {
    final api = _CountingApi();
    final container = await _makeContainer(api);

    final sub = container.listen(serverUpdateProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(serverUpdateProvider.future);
    expect(api.updateChecks, 1);

    await _openSettings(tester, container);

    expect(tester.takeException(), isNull);
    expect(await container.read(serverUpdateProvider.future), isNotNull);
    expect(api.updateChecks, 2);
  });
}
