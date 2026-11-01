import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/data_model/storage.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/server_info_provider.dart';
import 'package:kalinka/widgets/settings_controls/folder_picker.dart';

ServerFolder _folder(String path, String name, [String? subname]) =>
    ServerFolder(path: path, name: name, subname: subname);

/// The server's places, one drive with one folder on it, unless [listings]
/// says otherwise. The places are listed under the null path.
class _Api implements KalinkaPlayerProxy {
  final Map<String?, List<ServerFolder>> listings;
  final requests = <({String? path, int offset, int limit})>[];

  _Api([Map<String?, List<ServerFolder>>? listings])
    : listings =
          listings ??
          {
            null: [
              const ServerFolder(
                path: '/srv/kalinka/music',
                name: 'Internal storage',
                subname: 'On this server',
                icon: 'internal_storage',
              ),
              const ServerFolder(
                path: '/media/kalinka/3A1F',
                name: 'SANDISK',
                subname: 'USB drive · 31 GB',
                icon: 'usb_drive',
              ),
            ],
            '/media/kalinka/3A1F': [
              _folder('/media/kalinka/3A1F/Jazz', 'Jazz', '4 folders'),
            ],
          };

  List<String?> get walked => [for (final r in requests) r.path];

  @override
  Future<ServerFolderList> listServerFolders({
    String? path,
    int offset = 0,
    int limit = 50,
  }) async {
    requests.add((path: path, offset: offset, limit: limit));
    final all = listings[path] ?? const <ServerFolder>[];
    return ServerFolderList(
      total: all.length,
      folders: all.skip(offset).take(limit).toList(),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Future<_Api> _pump(
  WidgetTester tester,
  ValueChanged<String?> chosen, [
  _Api? fake,
]) async {
  final api = fake ?? _Api();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [kalinkaProxyProvider.overrideWithValue(api)],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => chosen(await showFolderPicker(context)),
              child: const Text('pick'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('pick'));
  await tester.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('a folder is walked to and chosen by its path', (tester) async {
    String? chosen;
    await _pump(tester, (path) => chosen = path);

    expect(find.text('Internal storage'), findsOneWidget);
    expect(find.text('USB drive · 31 GB'), findsOneWidget);

    await tester.tap(find.text('SANDISK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jazz'));
    await tester.pumpAndSettle();
    expect(find.text('No folders inside.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('folder-picker-choose')));
    await tester.pumpAndSettle();

    expect(chosen, '/media/kalinka/3A1F/Jazz');
  });

  testWidgets('the places themselves are not a folder to choose', (
    tester,
  ) async {
    String? chosen = 'untouched';
    await _pump(tester, (path) => chosen = path);

    await tester.tap(find.byKey(const ValueKey('folder-picker-choose')));
    await tester.pumpAndSettle();

    expect(find.text('Internal storage'), findsOneWidget);
    expect(chosen, 'untouched');
  });

  testWidgets('Up goes back the way the folders were walked', (tester) async {
    final api = await _pump(tester, (_) {});

    await tester.tap(find.text('SANDISK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('folder-picker-up')));
    await tester.pumpAndSettle();

    expect(find.text('Internal storage'), findsOneWidget);
    expect(api.walked, [null, '/media/kalinka/3A1F', null]);
  });

  testWidgets('a long folder is fetched as it scrolls', (tester) async {
    final api = await _pump(
      tester,
      (_) {},
      _Api({
        null: [for (var n = 0; n < 60; n++) _folder('/f$n', 'Folder $n')],
      }),
    );

    expect(api.requests, [(path: null, offset: 0, limit: 50)]);
    expect(find.text('Folder 59'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Folder 59'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    expect(api.requests, [
      (path: null, offset: 0, limit: 50),
      (path: null, offset: 50, limit: 50),
    ]);
  });

  testWidgets('no folder button on a server that cannot be browsed', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storageSupportedProvider.overrideWithValue(false)],
        child: MaterialApp(
          home: Scaffold(body: FolderPickerButton(onPicked: (_) {})),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('folder-picker-button')), findsNothing);
  });
}
