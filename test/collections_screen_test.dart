import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/catalog_cards_provider.dart';
import 'package:kalinka/providers/collections_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/indexer_status_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/row_expansion_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/providers/selection_state_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/widgets/kalinka_button.dart';
import 'package:kalinka/widgets/search_cards/action_pill_button.dart';
import 'package:kalinka/widgets/search_cards/collection_row.dart';
import 'package:kalinka/widgets/search_cards/container_action_header.dart';
import 'package:kalinka/widgets/search/search_session_view.dart';
import 'package:kalinka/widgets/selection_overlay.dart';
import 'package:kalinka/widgets/source_badge.dart';

const _shelfId = 'kalinka:collections:catalog:collections';
const _c1 = 'kalinka:collections:playlist:c1';
const _c2 = 'kalinka:collections:playlist:c2';

BrowseItem _collection(
  String id,
  String name,
  int tracks, {
  int? seconds,
  String? art,
}) => BrowseItem(
  id: id,
  name: name,
  canBrowse: true,
  canAdd: true,
  canEdit: true,
  playlist: Playlist(id: id, name: name, trackCount: tracks, duration: seconds),
  catalog: Catalog(
    id: id,
    title: name,
    sources: const ['localfiles'],
    image: art == null ? null : AlbumImage(small: art, large: art),
  ),
);

BrowseItem _track(String id, String title) => BrowseItem(
  id: id,
  name: title,
  canBrowse: false,
  canAdd: true,
  track: Track(id: id, title: title, duration: 200),
);

/// A server with nothing in any listing: the screen with no collections made
/// yet is the whole point here.
class _EmptyApi implements KalinkaPlayerProxy {
  @override
  Future<BrowseItemsList> getFavorite(
    SearchType queryType, {
    int offset = 0,
    int limit = 10,
    String filter = '',
  }) async => BrowseItemsList(0, limit, 0, const []);

  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async => BrowseItemsList(offset, limit, 0, const []);

  @override
  Future<SearchSuggestionList> searchSuggestions({
    int count = 4,
    int? tzOffsetMin,
  }) async => const SearchSuggestionList(suggestions: []);

  @override
  Future<BrowseItemsList> searchMatches(
    String query, {
    List<String>? sources,
  }) async => BrowseItemsList(0, 10, 0, const []);

  @override
  Future<BrowseItemsList> aiSearch(
    String query, {
    int offset = 0,
    int limit = 10,
    List<String>? sources,
  }) async => BrowseItemsList(offset, limit, 0, const []);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Serves the collections screen: the shelf's rows, and each collection's
/// tracks when a row unrolls. Records what was created.
class _ShelfApi extends _EmptyApi {
  final List<String> created = [];
  final List<(String, String)> renamed = [];
  final List<String> deleted = [];

  @override
  Future<void> deleteCollection(String id) async {
    deleted.add(id);
  }

  @override
  Future<String> createCollection(
    String name, {
    String description = '',
  }) async {
    created.add(name);
    return 'kalinka:collections:playlist:new';
  }

  @override
  Future<void> renameCollection(String id, String name) async {
    renamed.add((id, name));
  }

  /// Only the collections source has anything for this name, which is the
  /// point: a collection is found by searching, like anything else.
  @override
  Future<BrowseItemsList> searchMatches(
    String query, {
    List<String>? sources,
  }) async {
    if (sources?.single != 'collections') {
      return BrowseItemsList(0, 10, 0, const []);
    }
    final hit = _collection(_c1, 'Late Night Signals', 2);
    return BrowseItemsList(0, 1, 1, [hit]);
  }

  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async {
    final items = switch (id) {
      _shelfId => [
        _collection(_c1, 'Late Night Signals', 2),
        _collection(_c2, 'Sunday Morning', 1),
      ],
      _c1 => [_track('t1', 'Night Drive'), _track('t2', 'Signals')],
      _c2 => [_track('t3', 'Hypnotic')],
      _ => const <BrowseItem>[],
    };
    return BrowseItemsList(offset, limit, items.length, items);
  }
}

/// A collection longer than one browse: 99 tracks held, two of them served.
class _PagedApi extends _ShelfApi {
  static const held = 99;
  static const seconds = 22680; // 6 hr 18 min

  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async {
    if (id == _shelfId) {
      final rows = [
        _collection(_c1, 'Late Night Signals', held, seconds: seconds),
      ];
      return BrowseItemsList(offset, limit, rows.length, rows);
    }
    if (id != _c1) return BrowseItemsList(offset, limit, 0, const []);
    final page = [_track('t1', 'Night Drive'), _track('t2', 'Signals')];
    return BrowseItemsList(offset, limit, held, page);
  }
}

/// One empty collection; what is added to it is listed from then on.
class _FreshApi extends _ShelfApi {
  final List<BrowseItem> held = [];
  final List<(String, List<String>)> added = [];

  @override
  Future<({int added, int alreadyThere})> addToCollection(
    String id,
    List<String> itemIds, {
    bool keepDuplicates = false,
  }) async {
    added.add((id, itemIds));
    held.addAll([for (final id in itemIds) _track(id, 'Queued $id')]);
    return (added: itemIds.length, alreadyThere: 0);
  }

  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async {
    final items = switch (id) {
      _shelfId => [_collection(_c1, 'Fresh Start', held.length)],
      _c1 => [...held],
      _ => const <BrowseItem>[],
    };
    return BrowseItemsList(offset, limit, items.length, items);
  }
}

/// A collection whose cover the server is still composing: the first
/// listings carry no art.
class _ComposingApi extends _ShelfApi {
  static const readyAfter = 3;
  int listings = 0;

  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async {
    if (id != _shelfId) {
      return super.browse(id, offset: offset, limit: limit, filter: filter);
    }
    listings++;
    final rows = [
      _collection(
        _c1,
        'Late Night Signals',
        2,
        art: listings >= readyAfter ? '/catalog/art/late.jpg' : null,
      ),
    ];
    return BrowseItemsList(offset, limit, rows.length, rows);
  }
}

class _FixedConnection extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

class _IdleIndexer extends IndexerStatusNotifier {
  @override
  IndexerStatusState build() => const IndexerStatusState();

  @override
  void acquire() {}

  @override
  void release() {}
}

final _modules = [
  ModuleInfo(
    name: 'localfiles',
    title: 'Local Library',
    enabled: true,
    state: ModuleState.ready,
  ),
  ModuleInfo(
    name: 'collections',
    title: 'Collections',
    enabled: true,
    state: ModuleState.ready,
    builtin: true,
  ),
];

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'Kalinka.host': 'localhost',
      'Kalinka.port': 8080,
      'Kalinka.name': 'Test',
    });
    prefs = await SharedPreferences.getInstance();
  });

  Future<ProviderContainer> pumpSurface(
    WidgetTester tester, {
    KalinkaPlayerProxy? api,
    List<Track> queue = const [],
  }) async {
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        kalinkaProxyProvider.overrideWithValue(api ?? _EmptyApi()),
        playQueueProvider.overrideWithValue(queue),
        sourceModulesProvider.overrideWith((ref) => _modules),
        connectionStateProvider.overrideWith(_FixedConnection.new),
        playerStateProvider.overrideWithValue(PlaybackState.empty),
        catalogCardGroupsProvider.overrideWith(
          (ref) => Future.value(const <CatalogCardGroup>[]),
        ),
        collectionsShelfProvider.overrideWith((ref) => Future.value(null)),
        indexerStatusProvider.overrideWith(_IdleIndexer.new),
      ],
    );
    addTearDown(container.dispose);
    container.read(searchSessionProvider.notifier).open();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SearchSessionView())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    return container;
  }

  /// Presses and holds long enough to be taken: half a second for the
  /// recogniser to call it a long press, and another for the ring to fill.
  Future<void> hold(WidgetTester tester, Finder finder) async {
    final gesture = await tester.startGesture(tester.getCenter(finder));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await gesture.up();
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('a collection is found by name among the search results', (
    tester,
  ) async {
    final container = await pumpSurface(tester, api: _ShelfApi());

    container.read(searchSessionProvider.notifier).submit('signals');
    // Past the floor the loading state is held for, so the legs have landed.
    await tester.pump(const Duration(milliseconds: 700));
    await settle(tester);

    // Its own row, not a plain playlist's: a collection says what it is made
    // of wherever it is listed.
    expect(find.byType(CollectionRow), findsOneWidget);
    expect(find.text('Late Night Signals'), findsOneWidget);
  });

  testWidgets('the collections screen with none yet shows the invitation', (
    tester,
  ) async {
    final container = await pumpSurface(tester);
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(id: _shelfId, title: 'Your collections', canEdit: true);
    await settle(tester);

    expect(find.text('No collections yet'), findsOneWidget);
    // Making one is what an empty screen is for; rearranging is dead, having
    // nothing to rearrange.
    final pills = tester
        .widgetList<ActionPillButton>(find.byType(ActionPillButton))
        .toList();
    expect(pills.map((b) => b.label), ['New', 'Edit']);
    expect(pills.map((b) => b.enabled), [true, false]);
    // New leads the pair with the outline, Edit follows it plainly.
    expect(pills.map((b) => b.accent), [true, false]);
    // The one fill a screen at rest may carry is the empty state's call, and
    // the outline above it is the same call at a lower weight.
    final invitation = tester.widget<KalinkaButton>(find.byType(KalinkaButton));
    expect(invitation.label, 'CREATE COLLECTION');
    expect(invitation.variant, KalinkaButtonVariant.accent);
  });

  testWidgets('editing comes alive once there are collections to edit', (
    tester,
  ) async {
    final container = await pumpSurface(tester, api: _ShelfApi());
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(id: _shelfId, title: 'Your collections', canEdit: true);
    await settle(tester);

    final edit = tester.widget<ActionPillButton>(
      find.ancestor(
        of: find.text('Edit'),
        matching: find.byType(ActionPillButton),
      ),
    );
    expect(edit.enabled, isTrue);
  });

  testWidgets('New leads the pair, and Edit does not wear the filters glyph', (
    tester,
  ) async {
    final container = await pumpSurface(tester, api: _ShelfApi());
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(id: _shelfId, title: 'Your collections', canEdit: true);
    await settle(tester);

    final pills = {
      for (final pill in tester.widgetList<ActionPillButton>(
        find.byType(ActionPillButton),
      ))
        pill.label: pill,
    };
    expect(pills['New']!.accent, isTrue);
    expect(pills['Edit']!.accent, isFalse);
    expect(pills['Edit']!.icon, isNot(Icons.tune_rounded));
  });

  testWidgets('an unrolled page counts the collection, not the page', (
    tester,
  ) async {
    final container = await pumpSurface(tester, api: _PagedApi());
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(id: _shelfId, title: 'Your collections', canEdit: true);
    await settle(tester);
    await tester.tap(find.text('Late Night Signals'));
    await settle(tester);

    // Play all sends the collection's id, so the line counts what will play
    // rather than the two rows that arrived.
    final header = tester.widget<ContainerActionHeader>(
      find.byType(ContainerActionHeader),
    );
    expect(header.totalTracks, 99);
    expect(header.trackIds.length, 2);
    expect(
      find.text('99 tracks · 6 hr 18 min · tap a track to play from there'),
      findsOneWidget,
    );
    // The row that unrolled and the header under it now say the same number,
    // which is the whole complaint.
    expect(find.textContaining('99 tracks · 6 hr 18 min'), findsNWidgets(2));
    expect(find.textContaining('Showing the first 2 of 99'), findsOneWidget);
  });

  testWidgets('a collection that arrived whole says nothing about pages', (
    tester,
  ) async {
    final container = await pumpSurface(tester, api: _ShelfApi());
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(id: _shelfId, title: 'Your collections', canEdit: true);
    await settle(tester);
    await tester.tap(find.text('Late Night Signals'));
    await settle(tester);

    final header = tester.widget<ContainerActionHeader>(
      find.byType(ContainerActionHeader),
    );
    expect(header.totalTracks, 2);
    expect(find.textContaining('Showing the first'), findsNothing);
  });

  testWidgets('a source catalog with nothing in it stays plain', (
    tester,
  ) async {
    final container = await pumpSurface(tester);
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(id: 'kalinka:localfiles:catalog:albums', title: 'Albums');
    await settle(tester);

    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(find.text('No collections yet'), findsNothing);
    expect(find.byType(ActionPillButton), findsNothing);
  });

  testWidgets('a collection unrolls in place rather than opening a page', (
    tester,
  ) async {
    final container = await pumpSurface(tester, api: _ShelfApi());
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(id: _shelfId, title: 'Your collections', canEdit: true);
    await settle(tester);

    expect(find.text('Late Night Signals'), findsOneWidget);
    expect(find.text('2 tracks'), findsOneWidget);
    // The local library is attributed here, where every other row leaves it
    // unmarked: what a collection is made of is the point of the line.
    expect(
      tester
          .widgetList<SourceTile>(find.byType(SourceTile))
          .map((letter) => letter.source),
      ['localfiles', 'localfiles'],
    );
    expect(find.text('Night Drive'), findsNothing);

    await tester.tap(find.text('Late Night Signals'));
    await settle(tester);

    expect(find.text('Night Drive'), findsOneWidget);
    expect(find.text('Signals'), findsOneWidget);
    // Still the same screen — the collection is not somewhere you went.
    expect(container.read(searchSessionProvider).catalogPage.id, _shelfId);
  });

  testWidgets('an unrolled collection carries the actions every list has', (
    tester,
  ) async {
    final container = await pumpSurface(tester, api: _ShelfApi());
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(id: _shelfId, title: 'Your collections', canEdit: true);
    await settle(tester);
    await tester.tap(find.text('Sunday Morning'));
    await settle(tester);

    // The same pair a section of results carries, named the same way.
    expect(find.text('Play all'), findsOneWidget);
    expect(find.text('Enqueue'), findsOneWidget);
    // Editing is the screen's mode, not a row's action.
    expect(find.text('Edit tracks'), findsNothing);
  });

  testWidgets('a long press takes a collection, and the actions stay put', (
    tester,
  ) async {
    final container = await pumpSurface(tester, api: _ShelfApi());
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(id: _shelfId, title: 'Your collections', canEdit: true);
    await settle(tester);
    await tester.tap(find.text('Late Night Signals'));
    await settle(tester);

    await hold(tester, find.text('Late Night Signals'));
    await settle(tester);

    expect(container.read(selectionStateProvider).selectedContainerIds, {_c1});
    // A header that came and went under a selection would move every row
    // beneath it; what changes is the line, not what is there.
    expect(find.text('Play all'), findsOneWidget);
    expect(find.text('Enqueue'), findsOneWidget);
    expect(find.textContaining('2 selected'), findsOneWidget);
  });

  testWidgets('leaving the listing ends the selection gathered on it', (
    tester,
  ) async {
    final container = await pumpSurface(tester, api: _ShelfApi());
    final session = container.read(searchSessionProvider.notifier);
    session.openCatalog(id: _shelfId, title: 'Your collections', canEdit: true);
    await settle(tester);
    await hold(tester, find.text('Late Night Signals'));
    await settle(tester);
    expect(find.byType(MultiSelectBottomBar), findsOneWidget);

    session.backToCatalogsRoot();
    await settle(tester);

    // The rows it held are not on screen any more, so neither is the bar.
    expect(container.read(selectionStateProvider).isActive, isFalse);
    expect(find.byType(MultiSelectBottomBar), findsNothing);
  });

  testWidgets('taking a track leaves the row where it was', (tester) async {
    final container = await pumpSurface(tester, api: _ShelfApi());
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(id: _shelfId, title: 'Your collections', canEdit: true);
    await settle(tester);
    await tester.tap(find.text('Late Night Signals'));
    await settle(tester);
    final before = tester.getTopLeft(find.text('Night Drive'));

    await hold(tester, find.text('Night Drive'));
    await settle(tester);

    expect(container.read(selectionStateProvider).isActive, isTrue);
    // The mark is drawn over the row, not as a border that pushes it right.
    expect(tester.getTopLeft(find.text('Night Drive')), before);
  });

  testWidgets('renaming an open collection sends the name it was given', (
    tester,
  ) async {
    final api = _ShelfApi();
    final container = await pumpSurface(tester, api: api);
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(id: _shelfId, title: 'Your collections', canEdit: true);
    await settle(tester);
    await tester.tap(find.text('Sunday Morning'));
    await settle(tester);

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await settle(tester);
    await tester.tap(find.text('Rename'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Sunday Mornings');
    await tester.pump();
    await tester.tap(find.text('RENAME'));
    await settle(tester);

    expect(api.renamed, [(_c2, 'Sunday Mornings')]);
    // The overflow is the same control as the pair beside it, not a taller one.
    expect(
      find.descendant(
        of: find.byType(ContainerActionHeader),
        matching: find.byType(ActionPillButton),
      ),
      findsNWidgets(3),
    );
    // The confirmation toast retires itself on a timer the container
    // outlives; left pending, it fails the test after the tree is gone.
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('deleting names what goes with it before it goes', (
    tester,
  ) async {
    final api = _ShelfApi();
    final container = await pumpSurface(tester, api: api);
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(id: _shelfId, title: 'Your collections', canEdit: true);
    await settle(tester);
    await tester.tap(find.text('Sunday Morning'));
    await settle(tester);

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);

    expect(find.text('Delete Sunday Morning?'), findsOneWidget);
    expect(find.textContaining('Its 1 track'), findsOneWidget);
    expect(api.deleted, isEmpty);

    await tester.tap(find.text('Delete'));
    await settle(tester);

    expect(api.deleted, [_c2]);
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('a delete that is called off writes nothing', (tester) async {
    final api = _ShelfApi();
    final container = await pumpSurface(tester, api: api);
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(id: _shelfId, title: 'Your collections', canEdit: true);
    await settle(tester);
    await tester.tap(find.text('Sunday Morning'));
    await settle(tester);

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    await tester.tap(find.text('Cancel'));
    await settle(tester);

    expect(api.deleted, isEmpty);
    expect(find.text('Sunday Morning'), findsWidgets);
  });

  testWidgets('making a collection names it and reloads the listing', (
    tester,
  ) async {
    final api = _ShelfApi();
    final container = await pumpSurface(tester, api: api);
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(id: _shelfId, title: 'Your collections', canEdit: true);
    await settle(tester);
    final before = container.read(collectionsRevisionProvider);

    await tester.tap(find.widgetWithText(ActionPillButton, 'New'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '  Night Drive  ');
    await tester.pump();
    await tester.tap(find.text('CREATE'));
    await settle(tester);

    expect(api.created, ['Night Drive']);
    // The listing refetches off the revision rather than being handed a row.
    expect(container.read(collectionsRevisionProvider), greaterThan(before));
    // The confirmation toast retires itself on a timer the container
    // outlives; left pending, it fails the test after the tree is gone.
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('entering by one collection lands on it, already open', (
    tester,
  ) async {
    final container = await pumpSurface(tester, api: _ShelfApi());
    container.read(rowExpansionProvider.notifier).unroll(_c2);
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(
          id: _shelfId,
          title: 'Your collections',
          canEdit: true,
          focusItemId: _c2,
        );
    await settle(tester);

    expect(find.text('Hypnotic'), findsOneWidget);
    expect(find.text('Night Drive'), findsNothing);
    // Spent on arrival, so a row built again later does not jump the list.
    final page = container.read(searchSessionProvider).catalogPage;
    expect(page.focusItemId, isNull);
    expect(page.canEdit, isTrue);
  });

  testWidgets('an empty collection offers the queue, and takes it in place', (
    tester,
  ) async {
    final api = _FreshApi();
    final container = await pumpSurface(
      tester,
      api: api,
      queue: [
        Track(id: 'q1', title: 'First', duration: 100),
        Track(id: 'q2', title: 'Second', duration: 100),
      ],
    );
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(id: _shelfId, title: 'Your collections', canEdit: true);
    await settle(tester);
    await tester.tap(find.text('Fresh Start'));
    await settle(tester);

    expect(find.text('Nothing in this collection yet'), findsOneWidget);
    // Nothing to play yet, but the collection's own menu is reachable.
    expect(find.text('Play all'), findsNothing);
    expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);

    await tester.tap(find.text('Add 2 tracks from the queue'));
    await settle(tester);

    // The whole queue, in playing order, into this collection: no sheet.
    expect(api.added.single.$1, _c1);
    expect(api.added.single.$2, ['q1', 'q2']);
    // The rows land where the offer stood, the row still unrolled.
    expect(find.text('Queued q1'), findsOneWidget);
    expect(find.text('Queued q2'), findsOneWidget);
    expect(find.textContaining('from the queue'), findsNothing);
    expect(find.text('Play all'), findsOneWidget);
    // Let the confirmation toast's timer run out.
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('an unrolled collection follows a write made elsewhere', (
    tester,
  ) async {
    final api = _FreshApi();
    final container = await pumpSurface(tester, api: api);
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(id: _shelfId, title: 'Your collections', canEdit: true);
    await settle(tester);
    await tester.tap(find.text('Fresh Start'));
    await settle(tester);
    expect(find.text('Nothing in this collection yet'), findsOneWidget);

    // A write from elsewhere (the tray, say) bumps the revision.
    api.held.add(_track('x1', 'Landed Elsewhere'));
    container.read(collectionsRevisionProvider.notifier).bump();
    await settle(tester);

    expect(find.text('Landed Elsewhere'), findsOneWidget);
    expect(find.text('Nothing in this collection yet'), findsNothing);
  });

  testWidgets('a collection is reread each time it is opened', (tester) async {
    final api = _FreshApi();
    final container = await pumpSurface(tester, api: api);
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(id: _shelfId, title: 'Your collections', canEdit: true);
    await settle(tester);
    await tester.tap(find.text('Fresh Start'));
    await settle(tester);
    expect(find.text('Nothing in this collection yet'), findsOneWidget);

    // Rolled up, and changed from somewhere this app never hears of.
    await tester.tap(find.text('Fresh Start'));
    await settle(tester);
    api.held.add(_track('x2', 'Arrived Meanwhile'));

    await tester.tap(find.text('Fresh Start'));
    await settle(tester);
    expect(find.text('Arrived Meanwhile'), findsOneWidget);
  });

  testWidgets('a cover composed after the listing arrives without reopening', (
    tester,
  ) async {
    final api = _ComposingApi();
    final container = await pumpSurface(tester, api: api);
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(id: _shelfId, title: 'Your collections', canEdit: true);
    await settle(tester);

    final cover = find.descendant(
      of: find.byType(CollectionRow),
      matching: find.byType(Image),
    );
    expect(cover, findsNothing);
    expect(api.listings, 1);

    // Asked again a few seconds later, refreshed in place.
    await tester.pump(const Duration(seconds: 4));
    await settle(tester);
    expect(api.listings, 2);
    expect(cover, findsNothing);
    expect(find.text('Late Night Signals'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await settle(tester);
    expect(api.listings, 3);
    expect(cover, findsOneWidget);

    // And not again once it is there.
    await tester.pump(const Duration(seconds: 4));
    await settle(tester);
    expect(api.listings, 3);
  });

  testWidgets('with nothing queued, an empty collection makes no offer', (
    tester,
  ) async {
    final container = await pumpSurface(tester, api: _FreshApi());
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(id: _shelfId, title: 'Your collections', canEdit: true);
    await settle(tester);
    await tester.tap(find.text('Fresh Start'));
    await settle(tester);

    expect(find.text('Nothing in this collection yet'), findsOneWidget);
    expect(find.textContaining('from the queue'), findsNothing);
  });
}
