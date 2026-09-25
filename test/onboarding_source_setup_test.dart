// The setup wizard asks a server with music sources for sources, in the same
// cards and sheet as Settings, and never for the folder list they replace.
// My Library comes from a real server's schema (test/fixtures).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/data_model/presentation_schema.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/settings_provider.dart';
import 'package:kalinka/widgets/kalinka_button.dart';
import 'package:kalinka/widgets/onboarding/onboarding_fields.dart';
import 'package:kalinka/widgets/onboarding/step_source_setup.dart';

const _folders = 'input_modules.localfiles.music_folders';
const _sources = 'input_modules.localfiles.music_sources';

final Map<String, dynamic> _moduleJson =
    (jsonDecode(File('test/fixtures/localfiles_module.json').readAsStringSync())
            as Map)
        .cast<String, dynamic>();

/// My Library as the server sends it, with the folder list tagged [setup].
PresentationSchema _schema({bool withSources = true, String setup = 'prompt'}) {
  final fields = [
    for (final f in (_moduleJson['fields'] as List).cast<Map>())
      {...f.cast<String, dynamic>(), if (f['path'] == _folders) 'setup': setup},
  ];
  final module = ModuleSpec.fromJson({
    ..._moduleJson,
    'fields': fields,
    if (!withSources) 'collections': [],
  });
  return PresentationSchema(
    schemaVersion: 'v1',
    pages: [
      PageSpec(id: 'modules', title: 'Input modules', modules: [module]),
    ],
    expertFields: module.fields,
  );
}

class _Api implements KalinkaPlayerProxy {
  final PresentationSchema schema;

  /// What the server says about any staged change.
  final List<ConfigIssue> refuse;

  _Api(this.schema, {this.refuse = const []});

  @override
  Future<Map<String, dynamic>> getSettings() async => {
    'schema_version': 'v1',
    'values': {
      _folders: ['/srv/music'],
      _sources: [
        {
          'id': 'media',
          'kind': 'local',
          'location': {'path': '/srv/music'},
        },
      ],
    },
  };

  @override
  Future<PresentationSchema> getSettingsSchema() async => schema;

  @override
  Future<List<ConfigIssue>> validateSettings({
    required String schemaVersion,
    required Map<String, dynamic> changes,
  }) async => refuse;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  PresentationSchema schema, {
  List<ConfigIssue> refuse = const [],
}) async {
  tester.view.physicalSize = const Size(500, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      kalinkaProxyProvider.overrideWithValue(_Api(schema, refuse: refuse)),
    ],
  );
  addTearDown(container.dispose);
  await container.read(settingsProvider.notifier).loadConfig();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: OnboardingSourceSetupStep()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('asks for music sources in place of the folder list', (
    tester,
  ) async {
    await _pump(tester, _schema());

    expect(find.text('Music sources'), findsOneWidget);
    expect(find.text('Music folders'), findsNothing);
    expect(find.text('/srv/music'), findsOneWidget);

    await tester.tap(find.widgetWithText(KalinkaButton, 'Add'));
    await tester.pumpAndSettle();
    expect(find.text('ADD TO MUSIC SOURCES'), findsOneWidget);
    expect(find.text('Network share'), findsOneWidget);
  });

  testWidgets('a server without them is asked for its folders', (tester) async {
    await _pump(tester, _schema(withSources: false));

    expect(find.text('Music folders'), findsOneWidget);
    expect(find.text('Music sources'), findsNothing);
  });

  group('a required field a collection replaces', () {
    final schema = _schema(setup: 'required');
    final module = schema.pages.single.modules.single;

    test('is missing while the collection is empty', () {
      final state = SettingsState(
        schema: schema,
        values: const {_sources: <Object>[]},
      );
      expect(moduleMissingFields(state, module), ['Music sources']);
    });

    test('is missing while its entry holds nothing', () {
      final state = SettingsState(
        schema: schema,
        values: const {
          _sources: [
            {
              'id': 'rec_new',
              'kind': 'local',
              'location': {'path': ' '},
            },
          ],
        },
      );
      expect(moduleMissingFields(state, module), ['Music sources']);
    });

    test('is missing while its entry holds only a sign-in and a switch', () {
      final state = SettingsState(
        schema: schema,
        values: const {
          _sources: [
            {
              'id': 'rec_new',
              'kind': 'smb',
              'authentication': {'mode': 'account'},
              'options': {'require_encryption': false},
            },
          ],
        },
      );
      expect(moduleMissingFields(state, module), ['Music sources']);
    });

    test('is answered once it holds an entry', () {
      final state = SettingsState(
        schema: schema,
        values: const {
          _sources: [
            {
              'id': 'nas',
              'kind': 'smb',
              'location': {'host': 'nas', 'path': 'Music'},
            },
          ],
        },
      );
      expect(moduleMissingFields(state, module), isEmpty);
    });
  });
}
