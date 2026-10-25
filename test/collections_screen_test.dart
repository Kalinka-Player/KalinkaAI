import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/collections_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/indexer_status_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/providers/selection_state_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/widgets/kalinka_button.dart';
import 'package:kalinka/widgets/search_cards/action_pill_button.dart';
import 'package:kalinka/widgets/search_cards/collection_row.dart';
import 'package:kalinka/widgets/search_cards/row_play_button.dart';
import 'package:kalinka/widgets/search/container_page_actions.dart';
import 'package:kalinka/widgets/search/search_session_view.dart';
import 'package:kalinka/widgets/search/track_group_actions.dart';
import 'package:kalinka/widgets/selection_overlay.dart';
import 'package:kalinka/widgets/source_badge.dart';

import 'support/server_answer.dart';

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
/// tracks when its page opens. Records what was written.
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

/// A collection longer than one browse: 99 tracks held, served a page at a
/// time.
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
    final page = [
      for (var i = offset; i < held && i < offset + limit; i++)
        _track('t$i', 'Track $i'),
    ];
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
    capabilities: const [ModuleCapability.catalogs],
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
        serverAnswering('box-1'),
        playerStateProvider.overrideWithValue(PlaybackState.empty),
        collectionsShelfProvider.overrideWith((ref) => Future.value(null)),
        indexerStatusProvider.overrideWith(_IdleIndexer.new),
      ],
    );
    addTearDown(container.dispose);
    container.read(searchSessionProvider.notifier).refresh();

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

  /// The Collections listing, and then [name]'s own page when given.
  Future<void> openListing(
    WidgetTester tester,
    ProviderContainer container, {
    String? name,
  }) async {
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(id: _shelfId, title: 'Your collections', canEdit: true);
    await settle(tester);
    if (name == null) return;
    await tester.tap(find.text(name));
    await settle(tester);
  }

  ActionPillButton pill(WidgetTester tester, String label) => tester
      .widget<ActionPillButton>(find.widgetWithText(ActionPillButton, label));

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
    await openListing(tester, container);

    expect(find.text('No collections yet'), findsOneWidget);
    // Making one is what an empty screen is for, and all the listing offers.
    final pills = tester
        .widgetList<ActionPillButton>(find.byType(ActionPillButton))
        .toList();
    expect(pills.map((b) => b.label), ['New']);
    expect(pills.single.enabled, isTrue);
    expect(pills.single.accent, isTrue);
    // The one fill a screen at rest may carry is the empty state's call, and
    // the outline above it is the same call at a lower weight.
    final invitation = tester.widget<KalinkaButton>(find.byType(KalinkaButton));
    expect(invitation.label, 'CREATE COLLECTION');
    expect(invitation.variant, KalinkaButtonVariant.accent);
  });

  testWidgets('editing comes alive once the collection holds tracks', (
    tester,
  ) async {
    final api = _FreshApi();
    final container = await pumpSurface(tester, api: api);
    await openListing(tester, container, name: 'Fresh Start');

    // Nothing to reorder or drop yet.
    expect(pill(tester, 'Edit').enabled, isFalse);

    api.held.add(_track('x1', 'Landed Elsewhere'));
    container.read(collectionsRevisionProvider.notifier).bump();
    await settle(tester);

    expect(pill(tester, 'Edit').enabled, isTrue);
  });

  testWidgets(
    'the listing offers only New, and Edit is not the filters glyph',
    (tester) async {
      final container = await pumpSurface(tester, api: _ShelfApi());
      await openListing(tester, container);

      // Each collection is edited on its own page, not from the listing.
      final pills = tester
          .widgetList<ActionPillButton>(find.byType(ActionPillButton))
          .map((b) => b.label);
      expect(pills, ['New']);
      expect(pill(tester, 'New').accent, isTrue);

      await tester.tap(find.text('Late Night Signals'));
      await settle(tester);

      expect(pill(tester, 'Edit').accent, isFalse);
      expect(pill(tester, 'Edit').icon, isNot(Icons.tune_rounded));
    },
  );

  testWidgets("a collection's page counts the collection, not the rows", (
    tester,
  ) async {
    final container = await pumpSurface(tester, api: _PagedApi());
    await openListing(tester, container, name: 'Late Night Signals');

    // Play all sends the collection's id, so it counts what will play rather
    // than the rows that arrived.
    final play = tester.widget<PlayAllChip>(find.byType(PlayAllChip));
    expect(play.trackIds, [_c1]);
    expect(play.trackCount, _PagedApi.held);
    final enqueue = tester.widget<AddAllChip>(find.byType(AddAllChip));
    expect(enqueue.trackIds, [_c1]);
    expect(enqueue.trackCount, _PagedApi.held);
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

  testWidgets("a collection row opens the collection's page", (tester) async {
    final container = await pumpSurface(tester, api: _ShelfApi());
    await openListing(tester, container);

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

    final page = container.read(searchSessionProvider).catalogPage;
    expect(page.id, _c1);
    expect(page.isPlaylist, isTrue);
    expect(page.canEdit, isTrue);
    expect(find.text('Late Night Signals'), findsOneWidget);
    expect(find.text('Night Drive'), findsOneWidget);
    expect(find.text('Signals'), findsOneWidget);

    // Back returns to the listing it was opened from.
    await tester.tap(find.byTooltip('Back'));
    await settle(tester);
    expect(container.read(searchSessionProvider).catalogPage.id, _shelfId);
  });

  testWidgets('the chevron opens the same page, and play does not', (
    tester,
  ) async {
    final container = await pumpSurface(tester, api: _ShelfApi());
    await openListing(tester, container);

    // Both rows carry a way to start them without opening them.
    expect(find.byType(RowPlayButton), findsNWidgets(2));

    await tester.tap(find.byTooltip('Open Sunday Morning'));
    await settle(tester);

    expect(container.read(searchSessionProvider).catalogPage.id, _c2);
    expect(find.text('Hypnotic'), findsOneWidget);
  });

  testWidgets("a collection's page carries the actions every list has", (
    tester,
  ) async {
    final container = await pumpSurface(tester, api: _ShelfApi());
    await openListing(tester, container, name: 'Sunday Morning');

    // The same pair a section of results carries, named the same way.
    expect(find.text('Play all'), findsOneWidget);
    expect(find.text('Enqueue'), findsOneWidget);
    // Then what only a collection's page has: editing it, and its menu.
    expect(pill(tester, 'Edit').semanticsLabel, 'Edit Sunday Morning');
    final menu = tester.widget<ActionPillButton>(
      find.descendant(
        of: find.byType(CollectionMenuButton),
        matching: find.byType(ActionPillButton),
      ),
    );
    expect(menu.semanticsLabel, 'More for Sunday Morning');
    expect(find.text('Edit tracks'), findsNothing);
  });

  testWidgets('a long press takes a collection rather than opening it', (
    tester,
  ) async {
    final container = await pumpSurface(tester, api: _ShelfApi());
    await openListing(tester, container);

    await hold(tester, find.text('Late Night Signals'));
    await settle(tester);

    expect(container.read(selectionStateProvider).selectedContainerIds, {_c1});
    expect(container.read(searchSessionProvider).catalogPage.id, _shelfId);
    // While selecting, a tap adds to the selection rather than leaving it,
    // and nothing offers to play over it.
    expect(find.byType(RowPlayButton), findsNothing);
    await tester.tap(find.text('Sunday Morning'));
    await settle(tester);
    expect(container.read(selectionStateProvider).selectedContainerIds, {
      _c1,
      _c2,
    });
    expect(container.read(searchSessionProvider).catalogPage.id, _shelfId);
  });

  testWidgets('leaving the listing ends the selection gathered on it', (
    tester,
  ) async {
    final container = await pumpSurface(tester, api: _ShelfApi());
    await openListing(tester, container);
    await hold(tester, find.text('Late Night Signals'));
    await settle(tester);
    expect(find.byType(MultiSelectBottomBar), findsOneWidget);

    container.read(searchSessionProvider.notifier).backToCatalogsRoot();
    await settle(tester);

    // The rows it held are not on screen any more, so neither is the bar.
    expect(container.read(selectionStateProvider).isActive, isFalse);
    expect(find.byType(MultiSelectBottomBar), findsNothing);
  });

  testWidgets('taking a track leaves the row where it was', (tester) async {
    final container = await pumpSurface(tester, api: _ShelfApi());
    await openListing(tester, container, name: 'Late Night Signals');
    final before = tester.getTopLeft(find.text('Night Drive'));

    await hold(tester, find.text('Night Drive'));
    await settle(tester);

    expect(container.read(selectionStateProvider).isActive, isTrue);
    // The mark is drawn over the row, not as a border that pushes it right.
    expect(tester.getTopLeft(find.text('Night Drive')), before);
  });

  testWidgets('renaming a collection sends the name and retitles its page', (
    tester,
  ) async {
    final api = _ShelfApi();
    final container = await pumpSurface(tester, api: api);
    await openListing(tester, container, name: 'Sunday Morning');

    // The overflow is the same control as the pills beside it, not a taller
    // one.
    expect(
      find.descendant(
        of: find.byType(ContainerPageActions),
        matching: find.byType(ActionPillButton),
      ),
      findsNWidgets(4),
    );

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await settle(tester);
    await tester.tap(find.text('Rename'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Sunday Mornings');
    await tester.pump();
    await tester.tap(find.text('RENAME'));
    await settle(tester);

    expect(api.renamed, [(_c2, 'Sunday Mornings')]);
    expect(
      container.read(searchSessionProvider).catalogPage.title,
      'Sunday Mornings',
    );
    expect(find.text('Sunday Mornings'), findsOneWidget);
    // The confirmation toast retires itself on a timer the container
    // outlives; left pending, it fails the test after the tree is gone.
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('deleting asks before it goes, then leaves the page', (
    tester,
  ) async {
    final api = _ShelfApi();
    final container = await pumpSurface(tester, api: api);
    await openListing(tester, container, name: 'Sunday Morning');

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);

    expect(find.text('Delete Sunday Morning?'), findsOneWidget);
    expect(find.textContaining('cannot be undone'), findsOneWidget);
    expect(find.textContaining('Its 1 track'), findsOneWidget);
    expect(api.deleted, isEmpty);

    await tester.tap(find.text('Delete'));
    await settle(tester);

    expect(api.deleted, [_c2]);
    // Its page has nothing left to show; Back's visit is the listing.
    expect(container.read(searchSessionProvider).catalogPage.id, _shelfId);
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('a delete that is called off writes nothing', (tester) async {
    final api = _ShelfApi();
    final container = await pumpSurface(tester, api: api);
    await openListing(tester, container, name: 'Sunday Morning');

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    await tester.tap(find.text('Cancel'));
    await settle(tester);

    expect(api.deleted, isEmpty);
    expect(container.read(searchSessionProvider).catalogPage.id, _c2);
    expect(find.text('Hypnotic'), findsOneWidget);
  });

  testWidgets('making a collection names it and reloads the listing', (
    tester,
  ) async {
    final api = _ShelfApi();
    final container = await pumpSurface(tester, api: api);
    await openListing(tester, container);
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
    await openListing(tester, container, name: 'Fresh Start');

    expect(find.text('Nothing in this collection yet'), findsOneWidget);
    // Nothing to play yet, but the collection's own menu is reachable.
    expect(find.text('Play all'), findsNothing);
    expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);

    await tester.tap(find.text('Add 2 tracks from the queue'));
    await settle(tester);

    // The whole queue, in playing order, into this collection: no sheet.
    expect(api.added.single.$1, _c1);
    expect(api.added.single.$2, ['q1', 'q2']);
    // The rows land where the offer stood, on the same page.
    expect(container.read(searchSessionProvider).catalogPage.id, _c1);
    expect(find.text('Queued q1'), findsOneWidget);
    expect(find.text('Queued q2'), findsOneWidget);
    expect(find.textContaining('from the queue'), findsNothing);
    expect(find.text('Play all'), findsOneWidget);
    // Let the confirmation toast's timer run out.
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets("a collection's page follows a write made elsewhere", (
    tester,
  ) async {
    final api = _FreshApi();
    final container = await pumpSurface(tester, api: api);
    await openListing(tester, container, name: 'Fresh Start');
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
    await openListing(tester, container, name: 'Fresh Start');
    expect(find.text('Nothing in this collection yet'), findsOneWidget);

    // Left, and changed from somewhere this app never hears of.
    container.read(searchSessionProvider.notifier).goBack();
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
    await openListing(tester, container);

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
    await openListing(tester, container, name: 'Fresh Start');

    expect(find.text('Nothing in this collection yet'), findsOneWidget);
    expect(find.textContaining('from the queue'), findsNothing);
  });
}
