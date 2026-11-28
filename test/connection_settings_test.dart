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

  test('following the server to another address saves it', () async {
    final (container, prefs) = await _container({});
    final notifier = container.read(connectionSettingsProvider.notifier);
    await notifier.setDevice('Living room', '10.0.0.3', 8000);
    final choice = container.read(connectionSettingsProvider).serverChoice;

    await notifier.moveTo('10.0.0.4', 8001);
    expect(
      container.read(connectionSettingsProvider),
      ConnectionSettings(
        name: 'Living room',
        host: '10.0.0.4',
        port: 8001,
        serverChoice: choice,
      ),
    );
    expect(
      prefs.getString(ConnectionSettingsNotifier.sharedPrefHost),
      '10.0.0.4',
    );
    expect(prefs.getInt(ConnectionSettingsNotifier.sharedPrefPort), 8001);
    expect(
      prefs.getString(ConnectionSettingsNotifier.sharedPrefName),
      'Living room',
    );
  });

  test('a session-only connection follows without saving', () async {
    final (container, prefs) = await _container({});
    final notifier = container.read(connectionSettingsProvider.notifier);
    notifier.setDeviceEphemeral('Kalinka', '10.0.0.3', 8000);

    await notifier.moveTo('10.0.0.4', 8000);
    expect(container.read(connectionSettingsProvider).host, '10.0.0.4');
    expect(prefs.getString(ConnectionSettingsNotifier.sharedPrefHost), isNull);
  });

  test('a move while a connection is being saved is dropped', () async {
    final (container, prefs) = await _container({});
    final notifier = container.read(connectionSettingsProvider.notifier);
    notifier.setDeviceEphemeral('Setup', '10.0.0.3', 8000);
    final choice = container.read(connectionSettingsProvider).serverChoice;

    final saving = notifier.persist();
    await notifier.moveTo('10.0.0.4', 8000);
    await saving;
    expect(
      container.read(connectionSettingsProvider),
      ConnectionSettings(
        name: 'Setup',
        host: '10.0.0.3',
        port: 8000,
        serverChoice: choice,
      ),
    );
    expect(
      prefs.getString(ConnectionSettingsNotifier.sharedPrefHost),
      '10.0.0.3',
    );
  });

  test('pointing the app at another address is another server\'s choice, '
      'and the same address or a rename is not', () async {
    final (container, _) = await _container({
      ConnectionSettingsNotifier.sharedPrefHost: '10.0.0.3',
      ConnectionSettingsNotifier.sharedPrefPort: 8000,
    });
    final notifier = container.read(connectionSettingsProvider.notifier);
    int choice() => container.read(connectionSettingsProvider).serverChoice;
    final first = choice();

    await notifier.setDevice('Living room', '10.0.0.3', 8000);
    await notifier.updateName('Kitchen');
    notifier.setDeviceEphemeral('Kitchen', '10.0.0.3', 8000);
    expect(choice(), first);

    notifier.setDeviceEphemeral('Kitchen', '10.0.0.3', 8443, scheme: 'https');
    expect(choice(), first + 1);
    await notifier.setDevice('Kitchen', '10.0.0.3', 8000);
    expect(choice(), first + 2);
    await notifier.clearDevice();
    expect(choice(), first + 3);
    notifier.reset();
    expect(choice(), first + 3);
  });

  test('no server set, there is nothing to follow', () async {
    final (container, prefs) = await _container({});
    await container
        .read(connectionSettingsProvider.notifier)
        .moveTo('10.0.0.4', 8000);
    expect(container.read(connectionSettingsProvider).isSet, isFalse);
    expect(prefs.getString(ConnectionSettingsNotifier.sharedPrefHost), isNull);
  });
}
