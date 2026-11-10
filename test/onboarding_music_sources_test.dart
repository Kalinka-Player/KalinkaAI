// The setup wizard's music sources draw the artwork and glyph each source
// declares, as Home and the rail do. My Library comes from a real server's
// schema (test/fixtures).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/module_icons.dart';
import 'package:kalinka/data_model/presentation_schema.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/module_icon_cache.dart';
import 'package:kalinka/providers/modules_state_provider.dart';
import 'package:kalinka/providers/settings_provider.dart';
import 'package:kalinka/providers/url_resolver.dart';
import 'package:kalinka/widgets/module_artwork.dart';
import 'package:kalinka/widgets/onboarding/step_music_sources.dart';

final ModuleSpec _localFiles = ModuleSpec.fromJson(
  (jsonDecode(
    File('test/fixtures/localfiles_module.json').readAsStringSync(),
  ) as Map).cast<String, dynamic>(),
);

const _liveIcons = ModuleIcons(
  small: ModuleIconImage(url: '/live/small.png', mimeType: 'image/png'),
  standard: ModuleIconImage(url: '/live/standard.png', mimeType: 'image/png'),
);

ModuleSpec _source(String id, {String? icon}) => ModuleSpec.fromJson({
  'id': id,
  'kind': 'input_module',
  'title': id,
  'icon': ?icon,
});

class _Api implements KalinkaPlayerProxy {
  final PresentationSchema schema;

  _Api(this.schema);

  @override
  Future<Map<String, dynamic>> getSettings() async => {
    'schema_version': 'v1',
    'values': <String, dynamic>{},
  };

  @override
  Future<PresentationSchema> getSettingsSchema() async => schema;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Future<void> _pump(
  WidgetTester tester,
  ModuleSpec module, {
  List<ModuleInfo> live = const [],
}) async {
  final prefs = await SharedPreferences.getInstance();
  final schema = PresentationSchema(
    schemaVersion: 'v1',
    pages: [
      PageSpec(id: 'modules', title: 'Input modules', modules: [module]),
    ],
  );
  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      kalinkaProxyProvider.overrideWithValue(_Api(schema)),
      modulesStateProvider.overrideWithBuild(
        (ref, _) async =>
            ModulesAndDevices(inputModules: live, devices: const []),
      ),
      urlResolverProvider.overrideWithValue(UrlResolver('http://server')),
      moduleIconCacheProvider.overrideWithValue(
        ModuleIconCache(
          client: MockClient((_) async => http.Response('', 404)),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(settingsProvider.notifier).loadConfig();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: OnboardingMusicSourcesStep()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ModuleIcons? _drawnIcons(WidgetTester tester) =>
    tester.widget<ModuleArtwork>(find.byType(ModuleArtwork)).icons;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('draws the glyph a source declares, not one for its id', (
    tester,
  ) async {
    await _pump(tester, _source('radio', icon: 'waves_outlined'));

    expect(find.byIcon(Icons.waves_outlined), findsOneWidget);
    expect(find.byIcon(Icons.extension_outlined), findsNothing);
  });

  testWidgets('takes artwork from the module list when the schema has none', (
    tester,
  ) async {
    await _pump(
      tester,
      _source('upnp', icon: 'lan_outlined'),
      live: [
        ModuleInfo(
          name: 'upnp',
          title: 'UPnP',
          icons: _liveIcons,
          enabled: true,
          state: ModuleState.ready,
        ),
      ],
    );

    expect(_drawnIcons(tester), same(_liveIcons));
  });

  testWidgets('keeps the schema artwork for a source the list lacks', (
    tester,
  ) async {
    expect(_localFiles.icons, isNotNull);

    await _pump(tester, _localFiles);

    expect(_drawnIcons(tester), same(_localFiles.icons));
  });
}
