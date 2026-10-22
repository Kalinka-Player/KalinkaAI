import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/catalog_cards_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/collection_art_tile.dart';
import 'package:kalinka/widgets/search/collections_section.dart';
import 'package:kalinka/widgets/search_cards/collection_row.dart';
import 'package:kalinka/widgets/source_badge.dart';

const _shelfId = 'kalinka:collections:catalog:collections';

BrowseItem _root(String source, String title) => BrowseItem(
  id: 'kalinka:$source:catalog:root',
  name: title,
  canBrowse: true,
  canAdd: false,
  catalog: Catalog(id: 'kalinka:$source:catalog:root', title: title),
);

BrowseItem _shelf() => BrowseItem(
  id: _shelfId,
  name: 'Your collections',
  canBrowse: true,
  canAdd: false,
  canEdit: true,
  catalog: Catalog(
    id: _shelfId,
    title: 'Your collections',
    description: 'Your lists, mixed from any source',
    role: CatalogRole.library,
    previewConfig: Preview(
      type: PreviewType.tile,
      contentType: PreviewContentType.playlist,
      itemsCount: 3,
    ),
  ),
);

BrowseItem _collection(
  String local,
  String name,
  int tracks,
  List<String> sources, {
  String? art,
}) {
  final id = 'kalinka:collections:playlist:$local';
  final image = art == null
      ? null
      : AlbumImage(small: art, thumbnail: art, large: art);
  return BrowseItem(
    id: id,
    name: name,
    canBrowse: true,
    canAdd: true,
    canEdit: true,
    playlist: Playlist(id: id, name: name, trackCount: tracks, image: image),
    catalog: Catalog(id: id, title: name, sources: sources, image: image),
  );
}

final _collections = [
  _collection('c1', 'Late Night Focus', 28, ['jamendo', 'localfiles', 'qobuz']),
  _collection('c2', 'Family Favourites', 42, ['localfiles', 'qobuz']),
  _collection('c3', 'Sunday Jazz', 18, ['jamendo', 'localfiles']),
];

/// Serves the browse tree from a script; the shelf reports a total larger
/// than the page it hands back, the way a paged listing does.
class _Api implements KalinkaPlayerProxy {
  final List<BrowseItem> roots;
  final Map<String, List<BrowseItem>> children;
  int shelfTotal;
  final createdNames = <String>[];

  _Api({required this.roots, required this.children, this.shelfTotal = 0});

  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async {
    if (id.isEmpty) {
      return BrowseItemsList(
        offset,
        limit,
        roots.length,
        roots.skip(offset).take(limit).toList(),
      );
    }
    final items = children[id] ?? const <BrowseItem>[];
    final total = id == _shelfId ? shelfTotal : items.length;
    return BrowseItemsList(
      offset,
      limit,
      total,
      items.skip(offset).take(limit).toList(),
    );
  }

  @override
  Future<String> createCollection(
    String name, {
    String description = '',
  }) async {
    createdNames.add(name);
    final item = _collection('new', name, 0, const []);
    children[_shelfId] = [item, ...?children[_shelfId]];
    shelfTotal++;
    return item.id;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FixedConnection extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

ModuleInfo _module(String name, String title, {bool builtin = false}) =>
    ModuleInfo(
      name: name,
      title: title,
      enabled: true,
      state: ModuleState.ready,
      builtin: builtin,
    );

final _withCollections = [
  _module('localfiles', 'Local Library'),
  _module('jamendo', 'Jamendo'),
  _module('qobuz', 'Qobuz'),
  _module('collections', 'Collections', builtin: true),
];

_Api _serverWith(List<BrowseItem> collections, {int total = 0}) => _Api(
  roots: [
    _root('collections', 'Collections'),
    _root('localfiles', 'Local Library'),
  ],
  children: {
    'kalinka:collections:catalog:root': [_shelf()],
    _shelfId: collections,
  },
  shelfTotal: total,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader(KalinkaFonts.sansFamily)
      ..addFont(rootBundle.load('assets/fonts/IBMPlexSans-Medium.ttf'));
    await loader.load();
  });

  late SharedPreferences prefs;
  final opened = <CatalogCardPlan>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'Kalinka.host': 'localhost',
      'Kalinka.port': 8080,
      'Kalinka.name': 'Test',
    });
    prefs = await SharedPreferences.getInstance();
    opened.clear();
  });

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required KalinkaPlayerProxy api,
    required List<ModuleInfo> modules,
    double textScale = 1,
  }) async {
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        kalinkaProxyProvider.overrideWithValue(api),
        sourceModulesProvider.overrideWith((ref) => modules),
        connectionStateProvider.overrideWith(_FixedConnection.new),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            backgroundColor: KalinkaColors.background,
            body: ListView(
              children: [
                CollectionsSection(
                  onOpenCatalog: (plan, provider) => opened.add(plan),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // Three browses stand between the mount and the rows; the shimmer in
    // between never settles on its own.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return container;
  }

  testWidgets('the first few collections, the count, and a way to the rest', (
    tester,
  ) async {
    await pump(
      tester,
      api: _serverWith(_collections, total: 6),
      modules: _withCollections,
    );

    expect(find.text('YOUR COLLECTIONS'), findsOneWidget);
    expect(find.text('· 6'), findsOneWidget);
    expect(find.text('Your lists, mixed from any source'), findsOneWidget);
    expect(find.text('View All'), findsOneWidget);
    expect(find.byType(CollectionShelfRow), findsNWidgets(3));
    expect(find.text('Late Night Focus'), findsOneWidget);
    expect(find.text('28 tracks'), findsOneWidget);
    // Which sources it draws on, in their own colours, not how many.
    expect(
      find.descendant(
        of: find.widgetWithText(CollectionShelfRow, 'Late Night Focus'),
        matching: find.byType(SourceTile),
      ),
      findsNWidgets(3),
    );
  });

  testWidgets('an empty collection says so, and offers nothing to play', (
    tester,
  ) async {
    await pump(
      tester,
      api: _serverWith([
        _collection('c1', 'Nothing Yet', 0, const []),
      ], total: 1),
      modules: _withCollections,
    );

    expect(find.text('Empty collection'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
  });

  for (final count in [1, 3]) {
    testWidgets('no VIEW ALL when all $count collections are visible', (
      tester,
    ) async {
      await pump(
        tester,
        api: _serverWith(_collections.take(count).toList(), total: count),
        modules: _withCollections,
      );

      expect(find.byType(CollectionShelfRow), findsNWidgets(count));
      expect(find.text('View All'), findsNothing);
    });
  }

  testWidgets('VIEW ALL opens the shelf itself', (tester) async {
    await pump(
      tester,
      api: _serverWith(_collections, total: 6),
      modules: _withCollections,
    );

    await tester.tap(find.text('View All'));
    await tester.pump();

    expect(opened.map((plan) => plan.id), [_shelfId]);
    expect(opened.single.filters, isEmpty);
  });

  testWidgets("a row opens the collection's own page", (tester) async {
    final container = await pump(
      tester,
      api: _serverWith(_collections, total: 6),
      modules: _withCollections,
    );

    await tester.tap(find.text('Sunday Jazz'));
    await tester.pump();

    // Its page, where it is played and edited — not the listing.
    expect(opened, isEmpty);
    final page = container.read(searchSessionProvider).catalogPage;
    expect(page.id, 'kalinka:collections:playlist:c3');
    expect(page.isPlaylist, isTrue);
    expect(page.canEdit, isTrue);
  });

  testWidgets('the chevron opens the same page as the row', (tester) async {
    final container = await pump(
      tester,
      api: _serverWith(_collections, total: 6),
      modules: _withCollections,
    );

    await tester.tap(find.byTooltip('Open Late Night Focus'));
    await tester.pump();

    expect(opened, isEmpty);
    expect(
      container.read(searchSessionProvider).catalogPage.id,
      'kalinka:collections:playlist:c1',
    );
  });

  testWidgets('with no collections yet, no section and no invitation', (
    tester,
  ) async {
    await pump(tester, api: _serverWith(const []), modules: _withCollections);

    expect(find.text('YOUR COLLECTIONS'), findsNothing);
    expect(find.text('Create your first collection'), findsNothing);
    expect(find.byType(CollectionsEmptyCard), findsNothing);
  });

  testWidgets('a collection shows its collage; an empty one the tile', (
    tester,
  ) async {
    await pump(
      tester,
      api: _serverWith([
        _collection('c1', 'With Art', 5, [
          'localfiles',
        ], art: '/catalog/art/a.jpg'),
        _collection('c2', 'Empty Yet', 0, [], art: '/catalog/art/stale.jpg'),
        _collection('c3', 'No Art Yet', 2, ['qobuz']),
      ], total: 3),
      modules: _withCollections,
    );

    Finder imageIn(String title) => find.descendant(
      of: find.widgetWithText(CollectionShelfRow, title),
      matching: find.byType(Image),
    );

    // Only the one with tracks and art asks for the image at all; the empty
    // one keeps its stale art out of sight, since there is nothing to compose.
    expect(imageIn('With Art'), findsOneWidget);
    expect(imageIn('Empty Yet'), findsNothing);
    expect(imageIn('No Art Yet'), findsNothing);
    expect(find.byType(CollectionArtTile), findsAtLeastNWidgets(2));
  });

  testWidgets('a server without a collections source shows no section', (
    tester,
  ) async {
    await pump(
      tester,
      api: _serverWith(_collections, total: 6),
      modules: _withCollections.where((m) => !m.builtin).toList(),
    );

    expect(find.text('YOUR COLLECTIONS'), findsNothing);
    expect(find.byType(CollectionShelfRow), findsNothing);
  });
}
