import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/catalog_cards_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/widgets/collection_art_tile.dart';
import 'package:kalinka/widgets/kalinka_button.dart';
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
  final int shelfTotal;

  _Api({required this.roots, required this.children, this.shelfTotal = 0});

  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async {
    if (id.isEmpty) return BrowseItemsList(0, limit, roots.length, roots);
    final items = children[id] ?? const <BrowseItem>[];
    final total = id == _shelfId ? shelfTotal : items.length;
    return BrowseItemsList(offset, limit, total, items.take(limit).toList());
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
  late SharedPreferences prefs;
  final opened = <CatalogCardPlan>[];
  final focused = <String?>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'Kalinka.host': 'localhost',
      'Kalinka.port': 8080,
      'Kalinka.name': 'Test',
    });
    prefs = await SharedPreferences.getInstance();
    opened.clear();
    focused.clear();
  });

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required KalinkaPlayerProxy api,
    required List<ModuleInfo> modules,
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
          home: Scaffold(
            body: ListView(
              children: [
                CollectionsSection(
                  onOpenCatalog: (plan, provider, {focusItemId}) {
                    opened.add(plan);
                    focused.add(focusItemId);
                  },
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
    expect(find.text('VIEW ALL'), findsOneWidget);
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

  testWidgets('VIEW ALL opens the shelf itself', (tester) async {
    await pump(
      tester,
      api: _serverWith(_collections, total: 6),
      modules: _withCollections,
    );

    await tester.tap(find.text('VIEW ALL'));
    await tester.pump();

    expect(opened.map((plan) => plan.id), [_shelfId]);
    expect(opened.single.filters, isEmpty);
    expect(focused, [null]);
  });

  testWidgets('a row is a shortcut into the Collections screen, not a page', (
    tester,
  ) async {
    await pump(
      tester,
      api: _serverWith(_collections, total: 6),
      modules: _withCollections,
    );

    await tester.tap(find.text('Sunday Jazz'));
    await tester.pump();

    // The shelf itself, landing on the row that was tapped — never a screen
    // of the collection's own.
    expect(opened.map((plan) => plan.id), [_shelfId]);
    expect(opened.single.canEdit, isTrue);
    expect(focused, ['kalinka:collections:playlist:c3']);
  });

  testWidgets('with none yet, the invitation stands in and can be taken', (
    tester,
  ) async {
    await pump(tester, api: _serverWith(const []), modules: _withCollections);

    expect(find.text('YOUR COLLECTIONS'), findsOneWidget);
    expect(find.text('No collections yet'), findsOneWidget);
    expect(find.text('VIEW ALL'), findsNothing);
    final button = tester.widget<KalinkaButton>(find.byType(KalinkaButton));
    expect(button.label, 'CREATE COLLECTION');
    expect(button.enabled, isTrue);
  });

  testWidgets('the invitation stays a row on a phone, button under it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pump(tester, api: _serverWith(const []), modules: _withCollections);

    final tile = tester.getRect(find.byType(CollectionArtTile));
    final title = tester.getRect(find.text('No collections yet'));
    final button = tester.getRect(find.byType(KalinkaButton));

    // Tile beside the words, never over them — stacked, the card owns the
    // screen. The button is what gives way, to its own line under the row.
    expect(tile.right, lessThanOrEqualTo(title.left));
    expect(tile.width, lessThan(CollectionsEmptyCard.tileSize));
    expect(button.top, greaterThan(tile.bottom));
    expect(button.width, greaterThan(title.width));
  });

  testWidgets('with room, the button sits beside the tile and stays bounded', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pump(tester, api: _serverWith(const []), modules: _withCollections);

    final tile = tester.getRect(find.byType(CollectionArtTile));
    final button = tester.getRect(find.byType(KalinkaButton));

    expect(tile.width, CollectionsEmptyCard.tileSize);
    expect(button.left, greaterThan(tile.right));
    // A CTA stretched across the card would read as a banner.
    expect(button.width, lessThanOrEqualTo(260.0));
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
