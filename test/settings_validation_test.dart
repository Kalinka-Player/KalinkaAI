// What the settings page does with the server's verdict on what has been
// typed. It asks while the user types rather than only on apply, because
// applying restarts the server.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/data_model/presentation_schema.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/settings_provider.dart';

const _folders = 'input_modules.localfiles.music_folders';

class _FakeApi implements KalinkaPlayerProxy {
  _FakeApi({this.issues = const []});

  List<ConfigIssue> issues;
  Object? saveError;
  Object? validateError;
  Map<String, List<Map<String, dynamic>>> options = const {};
  Map<String, dynamic> values = const {'base_config.server.port': 8000};

  final List<Map<String, dynamic>> validated = [];
  int settingsReads = 0;
  int saves = 0;

  @override
  Future<List<ConfigIssue>> validateSettings({
    required String schemaVersion,
    required Map<String, dynamic> changes,
  }) async {
    validated.add(Map<String, dynamic>.from(changes));
    if (validateError != null) throw validateError!;
    return issues;
  }

  @override
  Future<void> saveSettings({
    required String schemaVersion,
    required Map<String, dynamic> changes,
  }) async {
    saves++;
    if (saveError != null) throw saveError!;
  }

  @override
  Future<Map<String, dynamic>> getSettings() async {
    settingsReads++;
    return {'schema_version': 'v1', 'values': values, 'enum_options': options};
  }

  @override
  Future<PresentationSchema> getSettingsSchema() async =>
      const PresentationSchema(
        schemaVersion: 'v1',
        pages: [],
        expertFields: [],
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

ProviderContainer _container(_FakeApi api) {
  final container = ProviderContainer(
    overrides: [kalinkaProxyProvider.overrideWithValue(api)],
  );
  addTearDown(container.dispose);
  return container;
}

Future<SettingsNotifier> _loaded(ProviderContainer container) async {
  final notifier = container.read(settingsProvider.notifier);
  await notifier.loadConfig();
  return notifier;
}

void main() {
  group('asking while the user types', () {
    test('a keystroke does not put a request on the wire', () async {
      final api = _FakeApi();
      final notifier = await _loaded(_container(api));

      notifier.stageChange(_folders, ['/mus']);
      notifier.stageChange(_folders, ['/music']);

      expect(api.validated, isEmpty);
    });

    test('a pause does, once, carrying everything staged', () async {
      final api = _FakeApi();
      final container = _container(api);
      final notifier = await _loaded(container);

      notifier.stageChange(_folders, ['/mus']);
      notifier.stageChange(_folders, ['/music']);
      notifier.stageChange('base_config.server.port', 9001);
      await Future<void>.delayed(const Duration(milliseconds: 450));

      expect(api.validated, hasLength(1));
      expect(api.validated.single, {
        _folders: ['/music'],
        'base_config.server.port': 9001,
      });
    });

    test('its answer lands on the field it is about', () async {
      final api = _FakeApi(
        issues: const [
          ConfigIssue(path: _folders, index: 1, message: 'name the share'),
        ],
      );
      final container = _container(api);
      final notifier = await _loaded(container);

      notifier.stageChange(_folders, ['/music', 'smb://nas']);
      await notifier.validateStaged();

      final state = container.read(settingsProvider);
      expect(state.issuesFor(_folders).single.message, 'name the share');
      expect(state.issuesFor('base_config.server.port'), isEmpty);
    });

    test(
      'a later answer replaces an earlier one rather than adding to it',
      () async {
        final api = _FakeApi(
          issues: const [
            ConfigIssue(path: _folders, message: 'name the share'),
          ],
        );
        final container = _container(api);
        final notifier = await _loaded(container);

        notifier.stageChange(_folders, ['smb://nas']);
        await notifier.validateStaged();
        api.issues = const [];
        notifier.stageChange(_folders, ['smb://nas/music']);
        await notifier.validateStaged();

        expect(container.read(settingsProvider).issuesFor(_folders), isEmpty);
      },
    );

    test('taking the last edit back takes the complaint with it', () async {
      final api = _FakeApi(
        issues: const [ConfigIssue(path: _folders, message: 'name the share')],
      );
      final container = _container(api);
      final notifier = await _loaded(container);

      notifier.stageChange(_folders, ['smb://nas']);
      await notifier.validateStaged();
      notifier.unstageChange(_folders);

      expect(container.read(settingsProvider).issuesFor(_folders), isEmpty);
    });

    test(
      'discarding clears what was staged and what was said about it',
      () async {
        final api = _FakeApi(
          issues: const [
            ConfigIssue(path: _folders, message: 'name the share'),
          ],
        );
        final container = _container(api);
        final notifier = await _loaded(container);

        notifier.stageChange(_folders, ['smb://nas']);
        await notifier.validateStaged();
        notifier.discardAll();

        final state = container.read(settingsProvider);
        expect(state.hasPendingChanges, isFalse);
        expect(state.hasBlockingIssues, isFalse);
      },
    );

    test(
      'a server that cannot be reached does not mark the page wrong',
      () async {
        // The save refuses on its own if the value really is unusable, and a
        // page that has lost the server has bigger news to show.
        final api = _FakeApi(
          issues: const [
            ConfigIssue(path: _folders, message: 'name the share'),
          ],
        );
        final container = _container(api);
        final notifier = await _loaded(container);

        notifier.stageChange(_folders, ['smb://nas']);
        await notifier.validateStaged();
        expect(container.read(settingsProvider).hasBlockingIssues, isTrue);

        api.validateError = Exception('connection closed');
        notifier.stageChange(_folders, ['smb://nas/music']);
        await notifier.validateStaged();

        expect(container.read(settingsProvider).hasBlockingIssues, isFalse);
        expect(container.read(settingsProvider).pendingCount, 1);
      },
    );
  });

  group('what stands in the way of applying', () {
    test('an error does', () async {
      final api = _FakeApi(
        issues: const [ConfigIssue(path: _folders, message: 'name the share')],
      );
      final container = _container(api);
      final notifier = await _loaded(container);

      notifier.stageChange(_folders, ['smb://nas']);
      await notifier.validateStaged();

      expect(container.read(settingsProvider).hasBlockingIssues, isTrue);
    });

    test('a warning does not', () async {
      final api = _FakeApi(
        issues: const [
          ConfigIssue(
            path: _folders,
            message: 'it did not answer',
            severity: IssueSeverity.warning,
          ),
        ],
      );
      final container = _container(api);
      final notifier = await _loaded(container);

      notifier.stageChange(_folders, ['smb://nas/music']);
      await notifier.validateStaged();

      final state = container.read(settingsProvider);
      expect(state.issuesFor(_folders), hasLength(1));
      expect(state.hasBlockingIssues, isFalse);
    });

    test('a save the server refuses shows its verdict on the rows', () async {
      final api = _FakeApi()
        ..saveError = const SettingsValidationException([
          ConfigIssue(path: _folders, index: 0, message: 'name the share'),
        ], 'name the share');
      final container = _container(api);
      final notifier = await _loaded(container);
      notifier.stageChange(_folders, ['smb://nas']);

      await expectLater(
        notifier.applyChanges(),
        throwsA(isA<SettingsValidationException>()),
      );

      final state = container.read(settingsProvider);
      expect(state.issuesFor(_folders).single.index, 0);
      // Nothing was saved, so the count still describes what is staged.
      expect(state.pendingCount, 1);
    });

    test(
      'a save that succeeds leaves nothing staged and nothing to fix',
      () async {
        final api = _FakeApi();
        final container = _container(api);
        final notifier = await _loaded(container);
        notifier.stageChange(_folders, ['/music']);

        await notifier.applyChanges();

        final state = container.read(settingsProvider);
        expect(state.hasPendingChanges, isFalse);
        expect(state.hasBlockingIssues, isFalse);
        expect(state.values[_folders], ['/music']);
      },
    );
  });
}
