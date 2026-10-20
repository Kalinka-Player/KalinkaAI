import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/collection_edit_provider.dart';
import 'package:kalinka/providers/collections_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/indexer_status_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/providers/toast_provider.dart';
import 'package:kalinka/widgets/search/search_session_view.dart';

const _shelfId = 'kalinka:collections:catalog:collections';
const _c1 = 'kalinka:collections:playlist:c1';

BrowseItem _collection(String id, String name, int tracks) => BrowseItem(
  id: id,
  name: name,
  canBrowse: true,
  canAdd: true,
  canEdit: true,
  playlist: Playlist(id: id, name: name, trackCount: tracks),
  catalog: Catalog(id: id, title: name, sources: const ['localfiles']),
);

/// A track as a collection lists it: its own id, and the id of its place in
/// the collection, which is what an edit addresses.
BrowseItem _entry(String trackId, String title, String entryId) => BrowseItem(
  id: trackId,
  name: title,
  canBrowse: false,
  canAdd: true,
  track: Track(
    id: trackId,
    title: title,
    duration: 200,
    playlistTrackId: entryId,
  ),
);

/// Serves one collection of three tracks and remembers what an edit sent.
class _EditApi implements KalinkaPlayerProxy {
  final List<(String, List<String>, List<String>)> edited = [];

  /// Refuses the next edit the way a collection written to underneath does.
  bool refuse = false;

  @override
  Future<({int removed, int moved})> editCollection(
    String id, {
    required List<String> remove,
    required List<String> order,
  }) async {
    if (refuse) throw CollectionChangedException(id);
    edited.add((id, remove, order));
    return (removed: remove.length, moved: 0);
  }

  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async {
    final items = switch (id) {
      _shelfId => [_collection(_c1, 'Night Drive', 3)],
      _c1 => [
        _entry('t1', 'First Light', 'e1'),
        _entry('t2', 'Second Wind', 'e2'),
        _entry('t3', 'Third Rail', 'e3'),
      ],
      _ => const <BrowseItem>[],
    };
    return BrowseItemsList(offset, limit, items.length, items);
  }

  @override
  Future<BrowseItemsList> getFavorite(
    SearchType queryType, {
    int offset = 0,
    int limit = 10,
    String filter = '',
  }) async => BrowseItemsList(0, limit, 0, const []);

  @override
  Future<SearchSuggestionList> searchSuggestions({
    int count = 4,
    int? tzOffsetMin,
  }) async => const SearchSuggestionList(suggestions: []);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
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

  /// A toast retires itself on a timer the tree does not outlive; left
  /// pending, it fails the test after the widgets are gone.
  Future<void> letToastsGo(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 30));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// One collection's page with its editing session running — where every
  /// one of these tests starts.
  Future<ProviderContainer> pumpEditing(
    WidgetTester tester,
    _EditApi api,
  ) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        kalinkaProxyProvider.overrideWithValue(api),
        sourceModulesProvider.overrideWith((ref) => _modules),
        connectionStateProvider.overrideWith(_FixedConnection.new),
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
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(id: _shelfId, title: 'Your collections', canEdit: true);
    await settle(tester);
    await tester.tap(find.text('Night Drive'));
    await settle(tester);
    await tester.tap(find.text('Edit'));
    await settle(tester);
    return container;
  }

  /// Taps the remove mark of the row for [title].
  Future<void> toggleRemoval(WidgetTester tester, String title) async {
    final row = find.ancestor(of: find.text(title), matching: find.byType(Row));
    await tester.tap(
      find.descendant(
        of: row.last,
        matching: find.byIcon(Icons.remove_rounded),
      ),
    );
    await tester.pump();
  }

  Future<void> restore(WidgetTester tester, String title) async {
    final row = find.ancestor(of: find.text(title), matching: find.byType(Row));
    await tester.tap(
      find.descendant(of: row.last, matching: find.byIcon(Icons.undo_rounded)),
    );
    await tester.pump();
  }

  testWidgets('Edit swaps the page actions for the session it opens', (
    tester,
  ) async {
    final container = await pumpEditing(tester, _EditApi());

    expect(container.read(collectionEditProvider).active, isTrue);
    expect(container.read(searchSessionProvider).catalogPage.id, _c1);
    expect(find.text('EDITING'), findsOneWidget);
    expect(find.text('No changes yet'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    // Its tracks are the editable list now, not the one that plays them.
    expect(find.textContaining('Drag to reorder'), findsOneWidget);
    expect(find.text('Play all'), findsNothing);
    expect(find.text('Edit'), findsNothing);
  });

  testWidgets('Back leaves editing, not the page', (tester) async {
    final container = await pumpEditing(tester, _EditApi());

    await tester.tap(find.byTooltip('Back'));
    await settle(tester);

    expect(container.read(collectionEditProvider).active, isFalse);
    expect(container.read(searchSessionProvider).catalogPage.id, _c1);
    expect(find.text('Play all'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
  });

  testWidgets('Back with changes asks first, and stays either way', (
    tester,
  ) async {
    final container = await pumpEditing(tester, _EditApi());
    await toggleRemoval(tester, 'Second Wind');

    await tester.tap(find.byTooltip('Back'));
    await settle(tester);
    expect(find.text('Discard 1 change?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await settle(tester);

    expect(container.read(collectionEditProvider).changes, 1);
    expect(container.read(searchSessionProvider).catalogPage.id, _c1);
  });

  testWidgets('a track marked to go stays on screen and is counted', (
    tester,
  ) async {
    await pumpEditing(tester, _EditApi());

    await toggleRemoval(tester, 'Second Wind');

    // It has not gone anywhere — it goes when the session lands.
    expect(find.text('Second Wind'), findsOneWidget);
    expect(find.text('1 change staged'), findsOneWidget);
  });

  testWidgets('taking the mark back leaves nothing staged', (tester) async {
    await pumpEditing(tester, _EditApi());

    await toggleRemoval(tester, 'Second Wind');
    await restore(tester, 'Second Wind');

    expect(find.text('No changes yet'), findsOneWidget);
    expect(find.textContaining('staged'), findsNothing);
  });

  testWidgets('dragging a row by its handle stages the order it lands in', (
    tester,
  ) async {
    final container = await pumpEditing(tester, _EditApi());
    final handles = find.byIcon(Icons.drag_handle);
    final row = tester.getSize(
      find
          .ancestor(of: find.text('First Light'), matching: find.byType(Row))
          .last,
    );

    // Down past the row below it: one place, by the handle only.
    await tester.drag(handles.first, Offset(0, row.height + 8));
    await tester.pumpAndSettle();

    final edit = container.read(collectionEditProvider).of(_c1)!;
    expect(edit.surviving, ['e2', 'e1', 'e3']);
    expect(edit.moved, {'e1'});
    expect(find.text('1 change staged'), findsOneWidget);
  });

  testWidgets('Reset drops what one collection staged', (tester) async {
    final container = await pumpEditing(tester, _EditApi());

    await toggleRemoval(tester, 'First Light');
    await tester.tap(find.text('Reset'));
    await tester.pump();

    expect(container.read(collectionEditProvider).changes, 0);
    expect(find.text('No changes yet'), findsOneWidget);
  });

  testWidgets('Done names what it would remove before removing it', (
    tester,
  ) async {
    final api = _EditApi();
    await pumpEditing(tester, api);
    await toggleRemoval(tester, 'Second Wind');

    await tester.tap(find.text('Done'));
    await settle(tester);

    expect(find.text('Remove 1 track?'), findsOneWidget);
    expect(find.textContaining('1 from Night Drive'), findsOneWidget);
    // Nothing is written until the question is answered.
    expect(api.edited, isEmpty);
  });

  testWidgets('answering it sends the removals and the order in one write', (
    tester,
  ) async {
    final api = _EditApi();
    final container = await pumpEditing(tester, api);
    await toggleRemoval(tester, 'Second Wind');

    await tester.tap(find.text('Done'));
    await settle(tester);
    await tester.tap(find.text('Remove'));
    await settle(tester);

    expect(api.edited.single.$1, _c1);
    expect(api.edited.single.$2, ['e2']);
    // The order names everything that survives, so the server can tell this
    // collection from one that moved on.
    expect(api.edited.single.$3, ['e1', 'e3']);
    expect(container.read(collectionEditProvider).active, isFalse);
    await letToastsGo(tester);
  });

  testWidgets('a collection written to underneath keeps its changes', (
    tester,
  ) async {
    final api = _EditApi()..refuse = true;
    final container = await pumpEditing(tester, api);
    await toggleRemoval(tester, 'Second Wind');

    await tester.tap(find.text('Done'));
    await settle(tester);
    await tester.tap(find.text('Remove'));
    await settle(tester);

    // The toast overlay is the app shell's, not this view's, so what the user
    // is told is read from the notifier that would draw it.
    expect(
      container.read(toastProvider).single.message,
      'Night Drive changed while you were editing it',
    );
    final session = container.read(collectionEditProvider);
    expect(session.active, isTrue);
    expect(session.changes, 1);
    await letToastsGo(tester);
  });

  testWidgets('Cancel with changes asks first and writes nothing', (
    tester,
  ) async {
    final api = _EditApi();
    final container = await pumpEditing(tester, api);
    await toggleRemoval(tester, 'First Light');

    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(find.text('Discard 1 change?'), findsOneWidget);

    await tester.tap(find.text('Keep editing'));
    await settle(tester);
    expect(container.read(collectionEditProvider).changes, 1);

    await tester.tap(find.text('Cancel'));
    await settle(tester);
    await tester.tap(find.text('Discard'));
    await settle(tester);

    expect(container.read(collectionEditProvider).active, isFalse);
    expect(api.edited, isEmpty);
  });

  group('what a session stages', () {
    const held = (name: 'Night Drive', entryIds: ['e1', 'e2', 'e3']);

    CollectionEditNotifier notifier(ProviderContainer container) =>
        container.read(collectionEditProvider.notifier);

    ProviderContainer session() {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(collectionEditProvider.notifier).begin();
      return container;
    }

    test('a dragged row is the one marked, not the ones it pushed', () {
      final container = session();

      notifier(container).reorder(_c1, held, 2, 0);

      final edit = container.read(collectionEditProvider).of(_c1)!;
      expect(edit.surviving, ['e3', 'e1', 'e2']);
      expect(edit.moved, {'e3'});
      expect(edit.changes, 1);
    });

    test('a row dragged back where it was is not a change', () {
      final container = session();

      notifier(container).reorder(_c1, held, 0, 2);
      notifier(container).reorder(_c1, held, 2, 0);

      final edit = container.read(collectionEditProvider).of(_c1)!;
      expect(edit.surviving, held.entryIds);
      expect(edit.changes, 0);
    });

    test('closing up after a removal is not a move', () {
      final container = session();

      notifier(container).reorder(_c1, held, 2, 0);
      notifier(container).toggleRemoval(_c1, held, 'e3');

      // e3 was dragged, but it is leaving — what it disturbed goes with it.
      final edit = container.read(collectionEditProvider).of(_c1)!;
      expect(edit.surviving, ['e1', 'e2']);
      expect(edit.moved, isEmpty);
      expect(edit.changes, 1);
    });

    test('a removed row keeps its place until the session lands', () {
      final container = session();

      notifier(container).toggleRemoval(_c1, held, 'e2');
      notifier(container).toggleRemoval(_c1, held, 'e2');

      final edit = container.read(collectionEditProvider).of(_c1)!;
      expect(edit.order, held.entryIds);
      expect(edit.changes, 0);
    });
  });
}
