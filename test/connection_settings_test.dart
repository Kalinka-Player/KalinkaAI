import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/providers/connection_settings_provider.dart';

Future<(ProviderContainer, SharedPreferences)> _container(
  Map<String, Object> stored,
) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return (container, prefs);
}

void main() {
  test('a server stored before TLS was possible is plain HTTP', () async {
    final (container, _) = await _container({
      ConnectionSettingsNotifier.sharedPrefHost: 'nas.local',
      ConnectionSettingsNotifier.sharedPrefPort: 8000,
    });
    final settings = container.read(connectionSettingsProvider);
    expect(settings.scheme, 'http');
    expect(settings.baseUrl.toString(), 'http://nas.local:8000');
    expect(settings.wsScheme, 'ws');
    expect(settings.displayAddress, 'nas.local:8000');
  });

  test('a server behind TLS is reached over https and wss', () async {
    final (container, prefs) = await _container({});
    await container
        .read(connectionSettingsProvider.notifier)
        .setDevice('Kalinka demo', 'demo.test', 443, scheme: 'https');

    final settings = container.read(connectionSettingsProvider);
    expect(settings.baseUrl.toString(), 'https://demo.test');
    expect(settings.wsScheme, 'wss');
    expect(settings.displayAddress, 'demo.test');
    expect(
      prefs.getString(ConnectionSettingsNotifier.sharedPrefScheme),
      'https',
    );
  });

  test('a wizard connection keeps its scheme when it is committed', () async {
    final (container, prefs) = await _container({});
    final notifier = container.read(connectionSettingsProvider.notifier);
    notifier.setDeviceEphemeral(
      'Kalinka demo',
      'demo.test',
      443,
      scheme: 'https',
    );
    expect(
      prefs.getString(ConnectionSettingsNotifier.sharedPrefScheme),
      isNull,
    );

    await notifier.persist();
    expect(
      prefs.getString(ConnectionSettingsNotifier.sharedPrefScheme),
      'https',
    );
  });

  test('disconnecting forgets the scheme with the server', () async {
    final (container, prefs) = await _container({});
    final notifier = container.read(connectionSettingsProvider.notifier);
    await notifier.setDevice('Kalinka demo', 'demo.test', 443, scheme: 'https');
    await notifier.clearDevice();
    expect(
      prefs.getString(ConnectionSettingsNotifier.sharedPrefScheme),
      isNull,
    );

    await notifier.setDevice('Kalinka', 'nas.local', 8000);
    expect(container.read(connectionSettingsProvider).scheme, 'http');
  });
}
