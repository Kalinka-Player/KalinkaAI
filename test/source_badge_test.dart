import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/widgets/source_badge.dart';

ModuleInfo _module(
  String name,
  String title, {
  bool builtin = false,
  String? icon,
}) => ModuleInfo(
  name: name,
  title: title,
  icon: icon,
  enabled: true,
  state: ModuleState.ready,
  builtin: builtin,
);

final _twoSources = [
  _module('localfiles', 'My Library'),
  _module('jamendo', 'Jamendo'),
];

Future<void> _pump(
  WidgetTester tester,
  List<ModuleInfo> modules,
  String entityId,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sourceModulesProvider.overrideWith((ref) => modules)],
      child: MaterialApp(
        home: Scaffold(body: SourceBadge(entityId: entityId)),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  /// The listener's own library used to be the unmarked default: no badge,
  /// on the theory that music without a badge was obviously theirs. It reads
  /// as a missing badge instead, so it is attributed like anywhere else.
  testWidgets('the local library is attributed like any other source', (
    tester,
  ) async {
    await _pump(tester, _twoSources, 'kalinka:localfiles:track:1');

    expect(find.text('M'), findsOneWidget);
  });

  testWidgets('a streaming source is attributed the same way', (tester) async {
    await _pump(tester, _twoSources, 'kalinka:jamendo:track:1');

    expect(find.text('J'), findsOneWidget);
  });

  testWidgets('with one source there is nothing to tell apart', (tester) async {
    await _pump(tester, [_twoSources.first], 'kalinka:localfiles:track:1');

    expect(find.byType(Text), findsNothing);
  });

  /// A collection is the app's own list, not a place the music came from.
  testWidgets('the server\'s own source stays unbadged', (tester) async {
    await _pump(tester, [
      ..._twoSources,
      _module('collections', 'Collections', builtin: true),
    ], 'kalinka:collections:playlist:1');

    expect(find.byType(Text), findsNothing);
  });

  testWidgets('an id with no source in it badges nothing', (tester) async {
    await _pump(tester, _twoSources, 'not-an-entity-id');

    expect(find.byType(Text), findsNothing);
  });

  /// [SourceTile] is reached directly now that no source is exempt, so it
  /// answers for every one of them.
  testWidgets('the tile names the library too', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sourceModulesProvider.overrideWith((ref) => _twoSources)],
        child: const MaterialApp(
          home: Scaffold(body: SourceTile(source: 'localfiles')),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('M'), findsOneWidget);
  });

  group('a source that declares an icon', () {
    final withIcons = [
      _module('localfiles', 'My Library', icon: 'folder_outlined'),
      _module('jamendo', 'Jamendo'),
    ];

    testWidgets('wears it on its badge in place of its letter', (tester) async {
      await _pump(tester, withIcons, 'kalinka:localfiles:track:1');

      expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('and on its tile', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sourceModulesProvider.overrideWith((ref) => withIcons)],
          child: const MaterialApp(
            home: Scaffold(body: SourceTile(source: 'localfiles')),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
    });

    testWidgets('one this app has no drawing of keeps its letter', (
      tester,
    ) async {
      await _pump(tester, [
        _module('localfiles', 'My Library', icon: 'not_an_icon'),
        _module('jamendo', 'Jamendo'),
      ], 'kalinka:localfiles:track:1');

      expect(find.text('M'), findsOneWidget);
    });

    test('is read off the module list', () {
      final module = ModuleInfo.fromJson({
        'name': 'localfiles',
        'title': 'My Library',
        'icon': 'folder_outlined',
        'enabled': true,
        'state': 'ready',
      });
      expect(module.icon, 'folder_outlined');
    });
  });
}
