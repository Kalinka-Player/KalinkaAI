import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/presentation_schema.dart';
import 'package:kalinka/providers/settings_provider.dart';

const _enabled = 'input_modules.localfiles.ai_search.enabled';
const _limit = 'input_modules.localfiles.ai_search.max_results';
const _sources = 'input_modules.localfiles.music_sources';

final _schema = PresentationSchema(
  schemaVersion: '1',
  pages: [
    PageSpec(
      id: 'input_modules',
      title: 'Plugins',
      modules: [
        ModuleSpec(
          id: 'localfiles',
          kind: 'input_module',
          title: 'My Library',
          collections: const [
            CollectionSpec(
              path: _sources,
              title: 'Music sources',
              apply: Apply.instant,
            ),
          ],
          sections: [
            SectionSpec(
              id: 'input_modules.localfiles.ai_search',
              title: 'AI search',
              fields: const [
                FieldSpec(
                  path: _enabled,
                  label: 'Enable AI search',
                  widget: WidgetKind.toggle,
                  type: 'bool',
                  apply: Apply.restartRequired,
                ),
                FieldSpec(
                  path: _limit,
                  label: 'Max results',
                  widget: WidgetKind.text,
                  type: 'int',
                  apply: Apply.instant,
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);

void main() {
  test('a plugin switch whose packages install at the next start restarts', () {
    final state = SettingsState(
      schema: _schema,
      stagedChanges: const {_enabled: true},
    );

    expect(state.onlyLiveChanges, isFalse);
  });

  test('the rest of a plugin page applies as it is saved', () {
    final state = SettingsState(
      schema: _schema,
      stagedChanges: const {_limit: 30},
    );

    expect(state.onlyLiveChanges, isTrue);
  });

  test('a collection applies as it is saved when the server says so', () {
    final state = SettingsState(
      schema: _schema,
      stagedChanges: const {
        _sources: [
          {'id': 'a', 'kind': 'folder', 'path': '/music'},
        ],
      },
    );

    expect(state.onlyLiveChanges, isTrue);
  });

  test('a collection with a field that restarts in the same save restarts', () {
    final state = SettingsState(
      schema: _schema,
      stagedChanges: const {_sources: [], _enabled: true},
    );

    expect(state.onlyLiveChanges, isFalse);
  });

  test('a collection from a server that does not say what it costs restarts', () {
    const collection = {'path': _sources, 'title': 'Music sources'};
    expect(CollectionSpec.fromJson(collection).needsRestart, isTrue);
  });

  test('a server that does not say what a save costs restarts for it', () {
    const field = {
      'path': _limit,
      'label': 'Max results',
      'widget': 'text',
      'type': 'int',
    };
    expect(FieldSpec.fromJson(field).needsRestart, isTrue);
  });
}
