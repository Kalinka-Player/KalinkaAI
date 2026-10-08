import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/presentation_schema.dart';
import 'package:kalinka/providers/box_control_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/restart_provider.dart';
import 'package:kalinka/providers/settings_provider.dart';

const _status = 'base_config.server.supervisor_status';

class _Api implements KalinkaPlayerProxy {
  bool online = false;
  int restarts = 0;
  int probes = 0;
  int reads = 0;
  String status = 'Installed (0.2.0).';

  @override
  Future<void> restartServer() async => restarts++;

  @override
  Future<ModulesAndDevices> listModules() async {
    probes++;
    if (!online) throw StateError('Core is stopped while packages install');
    return ModulesAndDevices(inputModules: [], devices: []);
  }

  @override
  Future<PresentationSchema> getSettingsSchema() async =>
      const PresentationSchema(
        schemaVersion: 'v1',
        pages: [],
        expertFields: [],
      );

  @override
  Future<Map<String, dynamic>> getSettings() async {
    reads++;
    return {
      'schema_version': 'v1',
      'values': {_status: status},
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    final level = Logger.level;
    Logger.level = Level.off;
    addTearDown(() => Logger.level = level);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  for (final status in [
    'Installed (0.2.0).',
    'Not installed. Installation failed: no connection. Restart to retry.',
  ]) {
    test(
      'waits through package work and reloads its actual result: $status',
      () {
        fakeAsync((clock) {
          final api = _Api()..status = status;
          var probes = 0;
          final container = ProviderContainer(
            overrides: [
              sharedPrefsProvider.overrideWithValue(prefs),
              kalinkaProxyProvider.overrideWithValue(api),
              boxControlProvider.overrideWith((ref) async {
                probes++;
                return null;
              }),
            ],
          );
          final subscription = container.listen(boxControlProvider, (_, _) {});
          clock.flushMicrotasks();
          expect(probes, 1);

          container.read(restartProvider.notifier).executeRestart();
          clock.flushMicrotasks();
          clock.elapse(const Duration(minutes: 2));
          expect(api.restarts, 1);
          expect(container.read(restartProvider).error, isNull);
          expect(container.read(restartProvider).isDone, isFalse);

          api.online = true;
          clock.elapse(const Duration(seconds: 2));
          clock.flushMicrotasks();
          expect(container.read(restartProvider).isDone, isTrue);
          expect(container.read(settingsProvider).values[_status], status);
          expect(api.reads, 1);
          expect(probes, 2);

          subscription.close();
          container.dispose();
        });
      },
    );
  }

  for (final exit in ['dismiss', 'switch server', 'dispose']) {
    test('stops the long wait on $exit without undoing the server request', () {
      fakeAsync((clock) {
        final api = _Api();
        final container = ProviderContainer(
          overrides: [
            sharedPrefsProvider.overrideWithValue(prefs),
            kalinkaProxyProvider.overrideWithValue(api),
          ],
        );
        container.read(restartProvider.notifier).executeRestart();
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 4));
        expect(api.restarts, 1);
        final probes = api.probes;

        switch (exit) {
          case 'dismiss':
            container.read(restartProvider.notifier).dismiss();
          case 'switch server':
            container
                .read(connectionSettingsProvider.notifier)
                .setDeviceEphemeral('Other box', 'other.local', 8000);
          case 'dispose':
            container.dispose();
        }
        clock.flushMicrotasks();
        api.online = true;
        clock.elapse(const Duration(seconds: 10));
        expect(api.probes, probes);
        expect(api.reads, 0);
        expect(api.restarts, 1);
        if (exit != 'dispose') {
          expect(container.read(restartProvider).isRestarting, isFalse);
          container.dispose();
        }
      });
    });
  }
}
