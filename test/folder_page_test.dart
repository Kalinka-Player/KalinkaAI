import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/providers/selection_state_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/widgets/breadcrumb_crumb.dart';
import 'package:kalinka/widgets/search/catalog_page_view.dart';
import 'package:kalinka/widgets/search/folder_trail.dart';
import 'package:kalinka/widgets/search_cards/search_folder_row.dart';
import 'package:kalinka/widgets/shelf_heading.dart';

class _FixedConnection extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

class _FolderApi implements KalinkaPlayerProxy {
  final Map<String, List<BrowseItem>> byId;

  _FolderApi(this.byId);

  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async {
    final items = byId[id] ?? const <BrowseItem>[];
    final end = (offset + limit).clamp(0, items.length);
    return BrowseItemsList(
      offset,
      limit,
      items.length,
      offset >= items.length ? const [] : items.sublist(offset, end),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

const _libraryId = 'kalinka:localfiles:catalog:files';
const _playlistsId = 'kalinka:localfiles:catalog:playlists';

String _idOf(String name) => 'kalinka:localfiles:catalog:folder.$name';

BrowseItem _folder(String name, {bool canAdd = true}) => BrowseItem(
  id: _idOf(name),
  name: name,
  subname: '2 tracks',
  canBrowse: true,
  canAdd: canAdd,
  catalog: Catalog(
    id: _idOf(name),
    title: name,
    description: '2 folders · 2 tracks · 15 min',
    previewConfig: Preview(type: PreviewType.folder),
  ),
);

BrowseItem _track(String id, String title) => BrowseItem(
  id: 'kalinka:localfiles:track:$id',
  name: title,
  subname: 'Miles Davis',
  canBrowse: false,
  canAdd: true,
  track: Track(id: id, title: title, duration: 450),
);

BrowseItem _playlist(String id, String name) => BrowseItem(
  id: 'kalinka:localfiles:playlist:$id',
  name: name,
  canBrowse: true,
  canAdd: true,
  playlist: Playlist(id: id, name: name, trackCount: 3),
);

final _playlistsShelf = BrowseItem(
  id: _playlistsId,
  name: 'Playlists',
  canBrowse: true,
  canAdd: false,
  catalog: Catalog(
    id: _playlistsId,
    title: 'Playlists',
    previewConfig: Preview(
      type: PreviewType.imageText,
      contentType: PreviewContentType.playlist,
      itemsCount: 3,
    ),
  ),
);

final _listings = <String, List<BrowseItem>>{
  _libraryId: [_folder('Jazz', canAdd: false), _folder('Rock')],
  _idOf('Jazz'): [
    _folder('Kind of Blue'),
    _folder('Blue Train'),
    _folder('Box set'),
  ],
  _idOf('Kind of Blue'): [
    _folder('Bonus tracks'),
    _folder('Other sessions'),
    _track('t1', 'So What'),
    _track('t2', 'Blue in Green'),
  ],
  _playlistsId: [_playlist('p1', 'Evening')],
  _idOf('Box set'): [for (var i = 0; i < 30; i++) _track('b$i', 'Take $i')],
};

const _longName =
    'The Complete Columbia Studio Recordings of the Second Great Quintet';

late SharedPreferences _prefs;

Future<ProviderContainer> _pumpLibrary(
  WidgetTester tester, {
  List<BrowseItem> openedFolders = const [],
}) async {
  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(_prefs),
      kalinkaProxyProvider.overrideWithValue(_FolderApi(_listings)),
      sourceModulesProvider.overrideWith((ref) => const <ModuleInfo>[]),
      connectionStateProvider.overrideWith(_FixedConnection.new),
      playerStateProvider.overrideWithValue(PlaybackState.empty),
    ],
  );
  addTearDown(container.dispose);
  final session = container.read(searchSessionProvider.notifier);
  session.openCatalog(
    id: _libraryId,
    title: 'My Library',
    sections: [_playlistsShelf],
    folderLayout: true,
  );
  for (final folder in openedFolders) {
    session.openFolder(folder);
  }

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => CatalogPageView(
              page: ref.watch(searchSessionProvider).catalogPage,
              onBackToCatalogs: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Finder _heading(String title) =>
    find.byWidgetPredicate((w) => w is ShelfHeading && w.title == title);

int? _tally(WidgetTester tester, String title) =>
    tester.widget<ShelfHeading>(_heading(title)).count;

Finder _inTrail(Finder finder) =>
    find.descendant(of: find.byType(FolderTrail), matching: finder);

final _topCrumb = _inTrail(find.byIcon(Icons.folder_outlined));

final _upButton = find.byIcon(Icons.drive_folder_upload_outlined);

String? _shown(ProviderContainer container) =>
    container.read(searchSessionProvider).shownListing.title;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  testWidgets('a folder groups its subfolders above its tracks, counted', (
    tester,
  ) async {
    await _pumpLibrary(
      tester,
      openedFolders: [_folder('Jazz', canAdd: false), _folder('Kind of Blue')],
    );

    expect(_tally(tester, 'FOLDERS'), 2);
    expect(_tally(tester, 'TRACKS'), 2);
    expect(find.byType(SearchFolderRow), findsNWidgets(2));
    expect(_inTrail(find.text('Kind of Blue')), findsOneWidget);
    expect(find.text('Kind of Blue'), findsNWidgets(2));
    expect(find.text('2 folders · 2 tracks · 15 min'), findsOneWidget);
  });

  testWidgets('tracks directly in a folder can be played or enqueued', (
    tester,
  ) async {
    await _pumpLibrary(
      tester,
      openedFolders: [_folder('Jazz', canAdd: false), _folder('Kind of Blue')],
    );

    expect(find.text('Play all'), findsOneWidget);
    expect(find.text('Enqueue'), findsOneWidget);
  });

  testWidgets('a folder holding only folders offers nothing to play', (
    tester,
  ) async {
    await _pumpLibrary(tester, openedFolders: [_folder('Jazz', canAdd: false)]);

    expect(find.text('Play all'), findsNothing);
    expect(_heading('TRACKS'), findsNothing);
  });

  testWidgets('a folder row shows its folder in place', (tester) async {
    final container = await _pumpLibrary(tester);

    await tester.tap(find.text('Jazz'));
    await tester.pumpAndSettle();

    expect(
      container.read(searchSessionProvider).catalogPage.title,
      'My Library',
    );
    expect(_shown(container), 'Jazz');
    expect(find.text('Kind of Blue'), findsOneWidget);
    expect(find.text('Rock'), findsNothing);
  });

  testWidgets('a crumb shows the folder it names', (tester) async {
    final container = await _pumpLibrary(
      tester,
      openedFolders: [_folder('Jazz', canAdd: false), _folder('Kind of Blue')],
    );

    await tester.tap(find.text('Jazz'));
    await tester.pumpAndSettle();

    expect(_shown(container), 'Jazz');
    expect(find.text('Blue Train'), findsOneWidget);
  });

  testWidgets('the page\'s own crumb returns to the library\'s top', (
    tester,
  ) async {
    final container = await _pumpLibrary(
      tester,
      openedFolders: [_folder('Jazz', canAdd: false), _folder('Kind of Blue')],
    );

    await tester.tap(_topCrumb);
    await tester.pumpAndSettle();

    expect(_shown(container), 'My Library');
    expect(find.text('Rock'), findsOneWidget);
  });

  testWidgets('the library\'s shelves show at its top and nowhere below', (
    tester,
  ) async {
    await _pumpLibrary(tester);
    expect(find.text('PLAYLISTS'), findsOneWidget);
    expect(find.text('Evening'), findsOneWidget);

    await tester.tap(find.text('Jazz'));
    await tester.pumpAndSettle();
    expect(find.text('PLAYLISTS'), findsNothing);
  });

  testWidgets('the trail stays in reach however far a folder scrolls', (
    tester,
  ) async {
    await _pumpLibrary(
      tester,
      openedFolders: [_folder('Jazz', canAdd: false), _folder('Box set')],
    );
    final home = tester.getTopLeft(_topCrumb);

    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pumpAndSettle();

    expect(find.text('Take 0').hitTestable(), findsNothing);
    expect(tester.getTopLeft(_topCrumb), home);
    expect(find.text('Jazz').hitTestable(), findsOneWidget);
  });

  testWidgets('a long folder name is cut short on the trail', (tester) async {
    await _pumpLibrary(
      tester,
      openedFolders: [_folder(_longName), _folder('Disc 1')],
    );

    final crumb = find.ancestor(
      of: find.text(_longName),
      matching: find.byType(BreadcrumbCrumb),
    );
    expect(
      tester.getSize(crumb).width,
      lessThanOrEqualTo(FolderTrail.crumbWidth),
    );
    expect(
      tester.widget<Text>(find.text(_longName)).overflow,
      TextOverflow.ellipsis,
    );
  });

  testWidgets('the trail ends on the folder shown, which it does not open', (
    tester,
  ) async {
    final container = await _pumpLibrary(
      tester,
      openedFolders: [_folder('Jazz', canAdd: false), _folder('Kind of Blue')],
    );

    await tester.tap(_inTrail(find.text('Kind of Blue')));
    await tester.pumpAndSettle();

    expect(_shown(container), 'Kind of Blue');
    expect(container.read(searchSessionProvider).folderPath, hasLength(2));
  });

  testWidgets('a deep trail folds its middle, keeping the page and the folder '
      'shown', (tester) async {
    final container = await _pumpLibrary(
      tester,
      openedFolders: [for (var i = 1; i <= 8; i++) _folder('Level $i folder')],
    );
    bool inTrail(int level) =>
        _inTrail(find.text('Level $level folder')).evaluate().isNotEmpty;

    expect(tester.takeException(), isNull);
    expect(_topCrumb, findsOneWidget);
    expect(inTrail(8), isTrue);
    expect(inTrail(1), isFalse);
    final firstShown = [for (var i = 1; i <= 8; i++) i].firstWhere(inTrail);
    expect(firstShown, greaterThan(2));

    await tester.tap(_inTrail(find.text('…')));
    await tester.pumpAndSettle();

    expect(_shown(container), 'Level ${firstShown - 1} folder');
  });

  testWidgets('a shallow trail folds nothing', (tester) async {
    await _pumpLibrary(
      tester,
      openedFolders: [_folder('Jazz', canAdd: false), _folder('Kind of Blue')],
    );

    expect(_inTrail(find.text('…')), findsNothing);
  });

  group('the crumbs a trail keeps', () {
    int start(List<double> widths, double available) => foldedTailStart(
      widths,
      separator: 10,
      ellipsis: 20,
      available: available,
    );

    test('all of them when they fit', () {
      expect(start([100, 100, 100, 100], 430), 1);
    });

    test('the first and the last, however narrow the room', () {
      expect(start([100, 100], 50), 1);
      expect(start([100, 100, 100, 100], 50), 3);
    });

    test('as many before the last as fit beside the ellipsis', () {
      // 100 first + 10 + 20 ellipsis + 10 + 100 last leaves 150: one more.
      expect(start([100, 100, 100, 100, 100], 390), 3);
    });
  });

  testWidgets('the way up shows the enclosing folder, and stops at the top', (
    tester,
  ) async {
    final container = await _pumpLibrary(
      tester,
      openedFolders: [_folder('Jazz', canAdd: false), _folder('Kind of Blue')],
    );

    // At the far end of the row, clear of Play all.
    expect(
      tester.getTopLeft(_upButton).dx,
      greaterThan(tester.getTopRight(find.text('Enqueue')).dx),
    );
    await tester.tap(_upButton);
    await tester.pumpAndSettle();
    expect(_shown(container), 'Jazz');

    await tester.tap(_upButton);
    await tester.pumpAndSettle();
    expect(_shown(container), 'My Library');
    expect(_upButton, findsNothing);
  });

  testWidgets('a folder\'s actions hold under the trail once scrolled to it', (
    tester,
  ) async {
    final container = await _pumpLibrary(
      tester,
      openedFolders: [_folder('Jazz', canAdd: false), _folder('Box set')],
    );
    final list = find.byType(ListView);

    await tester.drag(list, const Offset(0, -1500));
    await tester.pumpAndSettle();

    final held = _upButton.hitTestable();
    expect(held, findsOneWidget);
    expect(find.text('Play all').hitTestable(), findsOneWidget);
    expect(
      tester.getTopLeft(held).dy,
      lessThan(tester.getBottomLeft(find.byType(FolderTrail)).dy + 20),
    );

    await tester.drag(list, const Offset(0, 1500));
    await tester.pumpAndSettle();
    expect(_upButton, findsOneWidget);

    await tester.drag(list, const Offset(0, -1500));
    await tester.pumpAndSettle();
    await tester.tap(_upButton.hitTestable());
    await tester.pumpAndSettle();
    expect(_shown(container), 'Jazz');

    // Back into the folder it was held in, which opens at its top.
    await tester.tap(find.text('Box set'));
    await tester.pumpAndSettle();
    expect(_shown(container), 'Box set');
    expect(_upButton, findsOneWidget);
  });

  testWidgets('a folder held joins a selection, and a tap then toggles it', (
    tester,
  ) async {
    final container = await _pumpLibrary(
      tester,
      openedFolders: [_folder('Jazz', canAdd: false)],
    );
    Set<String> chosen() =>
        container.read(selectionStateProvider).selectedContainerIds;

    final hold = await tester.startGesture(
      tester.getCenter(find.text('Kind of Blue')),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await hold.up();
    await tester.pump();
    expect(chosen(), {_idOf('Kind of Blue')});

    await tester.tap(find.text('Blue Train'));
    await tester.pump();
    expect(chosen(), {_idOf('Kind of Blue'), _idOf('Blue Train')});
    expect(_shown(container), 'Jazz');

    await tester.tap(find.text('Kind of Blue'));
    await tester.pump();
    expect(chosen(), {_idOf('Blue Train')});
  });
}
