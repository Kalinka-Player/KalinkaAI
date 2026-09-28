import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/browse_filters.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/widgets/browse_rows_shimmer.dart';
import 'package:kalinka/widgets/search/catalog_page_view.dart';

const _textField = FilterSpec(
  id: 'q',
  kind: FilterKind.text,
  label: 'Search your library',
);
const _typeField = FilterSpec(
  id: 'type',
  kind: FilterKind.choice,
  label: 'Type',
  ops: [FilterOp.any],
);
const _genreField = FilterSpec(
  id: 'genre',
  kind: FilterKind.choice,
  label: 'Genre',
  ops: [FilterOp.any],
);

BrowseItem _section({
  required String id,
  required String name,
  required PreviewContentType contentType,
  List<FilterSpec> filters = const [_textField, _genreField],
}) {
  return BrowseItem(
    id: id,
    name: name,
    canBrowse: true,
    canAdd: false,
    catalog: Catalog(
      id: id,
      title: name,
      filters: filters,
      previewConfig: Preview(
        type: PreviewType.imageText,
        contentType: contentType,
        itemsCount: 2,
      ),
    ),
  );
}

final _sections = [
  _section(
    id: 'kalinka:localfiles:catalog:artists',
    name: 'Artists',
    contentType: PreviewContentType.artist,
  ),
  _section(
    id: 'kalinka:localfiles:catalog:albums',
    name: 'Albums',
    contentType: PreviewContentType.album,
  ),
];

BrowseItem _album(String id, String title) => BrowseItem(
  id: id,
  name: title,
  canBrowse: true,
  canAdd: false,
  album: Album(id: id, title: title),
);

CatalogPage get _libraryPage => CatalogPage.category(
  id: 'kalinka:localfiles:catalog:library',
  title: 'My Library',
  filters: const [_textField, _typeField, _genreField],
  sections: _sections,
);

/// Answers each browse from a per-catalog script, and records what it was
/// asked, so a test can tell which listing the page actually requested.
class _ScriptedBrowseApi implements KalinkaPlayerProxy {
  final Map<String, List<BrowseItem>> byCatalog;
  final List<({String id, String? filter, int limit})> calls = [];

  /// Held open by a test that wants to see the shelves while they load.
  final Completer<void>? gate;

  /// Whether any filter at all matches nothing.
  final bool filteredOut;

  _ScriptedBrowseApi(this.byCatalog, {this.gate, this.filteredOut = false});

  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async {
    calls.add((id: id, filter: filter, limit: limit));
    if (gate != null) await gate!.future;
    final items = filteredOut && filter != null
        ? const <BrowseItem>[]
        : byCatalog[id] ?? const <BrowseItem>[];
    // A total beyond the page is what makes a shelf worth opening in full.
    return BrowseItemsList(offset, limit, items.length * 10, items);
  }

  @override
  Future<FilterValueList> getFilterValues(
    String catalogId,
    String field, {
    int offset = 0,
    int limit = 50,
    String query = '',
  }) async => const FilterValueList(offset: 0, limit: 50, total: 0, items: []);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

late SharedPreferences _prefs;

typedef _Harness = ({_ScriptedBrowseApi api, ProviderContainer container});

Future<_Harness> _pump(
  WidgetTester tester, {
  Map<String, List<BrowseItem>> catalogs = const {},
  Completer<void>? gate,
  List<BrowseItem>? sections,
  bool filteredOut = false,
}) async {
  final page = CatalogPage.category(
    id: 'kalinka:localfiles:catalog:library',
    title: 'My Library',
    filters: const [_textField, _typeField, _genreField],
    sections: sections ?? _sections,
  );
  final api = _ScriptedBrowseApi(
    catalogs,
    gate: gate,
    filteredOut: filteredOut,
  );
  final container = ProviderContainer(
    overrides: [
      kalinkaProxyProvider.overrideWithValue(api),
      sharedPrefsProvider.overrideWithValue(_prefs),
    ],
  );
  addTearDown(container.dispose);
  container
      .read(searchSessionProvider.notifier)
      .openCatalog(
        id: page.id!,
        title: page.title!,
        filters: page.filters,
        sections: page.sections,
      );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: CatalogPageView(page: page, onBackToCatalogs: () {}),
        ),
      ),
    ),
  );
  if (gate == null) await tester.pumpAndSettle();
  return (api: api, container: container);
}

/// Back to the Catalogs root, and into the library again.
void _reopen(ProviderContainer container) {
  final session = container.read(searchSessionProvider.notifier);
  final page = _libraryPage;
  session.backToCatalogsRoot();
  session.openCatalog(
    id: page.id!,
    title: page.title!,
    filters: page.filters,
    sections: page.sections,
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  group('capabilities', () {
    test('the kind field is told apart from the genre one', () {
      final caps = _libraryPage.filterCapabilities;

      expect(caps.typeField?.id, 'type');
      expect(caps.genreField?.id, 'genre');
      expect(caps.genreVocabulary?.field, 'genre');
      expect(caps.type, FacetSupport.supported);
    });

    test('the kinds offered are the ones the sections name', () {
      expect(_libraryPage.filterCapabilities.types, [
        SearchType.artist,
        SearchType.album,
      ]);
    });

    test('a category with no sections offers no kind group', () {
      const page = CatalogPage.category(
        id: 'kalinka:localfiles:catalog:albums',
        title: 'Albums',
        filters: [_textField, _typeField],
      );

      // Nothing to choose between, so the field alone does not light it up.
      expect(page.filterCapabilities.type, FacetSupport.hidden);
    });

    test('the chosen kind travels in the document', () {
      const query = BrowseFilterQuery(type: SearchType.album);

      expect(
        query.encoded(_libraryPage.filterCapabilities),
        '{"type":{"any":["album"]}}',
      );
    });

    test('a query is honoured only where each of its answers is live', () {
      final byNameOnly = BrowseFilterCapabilities.fromSpecs(const [
        _textField,
      ], catalogId: 'kalinka:localfiles:catalog:artists');

      expect(const BrowseFilterQuery().isHonouredBy(byNameOnly), isTrue);
      expect(
        const BrowseFilterQuery(text: 'moon').isHonouredBy(byNameOnly),
        isTrue,
      );
      expect(
        const BrowseFilterQuery(genreIds: ['jazz']).isHonouredBy(byNameOnly),
        isFalse,
      );
      expect(
        const BrowseFilterQuery(
          text: 'moon',
          genreIds: ['jazz'],
        ).isHonouredBy(byNameOnly),
        isFalse,
      );
    });
  });

  group('sections', () {
    testWidgets('each shelf browses its own catalog', (tester) async {
      final harness = await _pump(
        tester,
        catalogs: {
          'kalinka:localfiles:catalog:artists': [_album('a1', 'Air')],
          'kalinka:localfiles:catalog:albums': [_album('b1', 'Moon Safari')],
        },
      );

      expect(harness.api.calls.map((c) => c.id), [
        'kalinka:localfiles:catalog:artists',
        'kalinka:localfiles:catalog:albums',
      ]);
      // The shelf's own preview size, not the page's chunk size.
      expect(harness.api.calls.first.limit, 2);
      expect(find.text('ARTISTS'), findsOneWidget);
      expect(find.text('ALBUMS'), findsOneWidget);
    });

    testWidgets('a shelf shimmers until its items arrive', (tester) async {
      final gate = Completer<void>();
      await _pump(
        tester,
        gate: gate,
        catalogs: {
          'kalinka:localfiles:catalog:albums': [_album('b1', 'Moon Safari')],
        },
      );
      await tester.pump();

      expect(find.byType(BrowseRowsShimmer), findsWidgets);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(BrowseRowsShimmer), findsNothing);
      expect(find.text('Moon Safari'), findsOneWidget);
    });

    testWidgets('an empty shelf is left out entirely', (tester) async {
      await _pump(
        tester,
        catalogs: {
          'kalinka:localfiles:catalog:albums': [_album('b1', 'Moon Safari')],
        },
      );

      expect(find.text('ARTISTS'), findsNothing);
      expect(find.text('ALBUMS'), findsOneWidget);
    });

    testWidgets('View all narrows the page to that shelf\'s kind', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        catalogs: {
          'kalinka:localfiles:catalog:albums': [_album('b1', 'Moon Safari')],
        },
      );
      harness.api.calls.clear();

      await tester.tap(find.text('VIEW ALL').first);
      await tester.pumpAndSettle();

      // The shelves give way to the library itself, narrowed to that kind.
      expect(find.text('ALBUMS'), findsNothing);
      expect(harness.api.calls.first.id, 'kalinka:localfiles:catalog:library');
      expect(harness.api.calls.first.filter, '{"type":{"any":["album"]}}');
    });

    testWidgets('a kind chosen as a filter is kept for the next visit', (
      tester,
    ) async {
      final harness = await _pump(tester);
      final session = harness.container.read(searchSessionProvider.notifier);

      session.setCatalogFilter(const BrowseFilterQuery(type: SearchType.album));
      _reopen(harness.container);

      expect(
        harness.container.read(searchSessionProvider).catalogFilter.type,
        SearchType.album,
      );
    });

    testWidgets('View all is a way in, not a filter kept for next time', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        catalogs: {
          'kalinka:localfiles:catalog:albums': [_album('b1', 'Moon Safari')],
        },
      );

      await tester.tap(find.text('VIEW ALL').first);
      await tester.pumpAndSettle();
      expect(
        harness.container.read(searchSessionProvider).catalogFilter.type,
        SearchType.album,
      );
      _reopen(harness.container);

      expect(
        harness.container.read(searchSessionProvider).catalogFilter.type,
        isNull,
      );
    });

    testWidgets('a filter changed after View all keeps the View all out', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        catalogs: {
          'kalinka:localfiles:catalog:albums': [_album('b1', 'Moon Safari')],
        },
      );
      final session = harness.container.read(searchSessionProvider.notifier);
      BrowseFilterQuery filter() =>
          harness.container.read(searchSessionProvider).catalogFilter;

      await tester.tap(find.text('VIEW ALL').first);
      await tester.pumpAndSettle();
      session.setCatalogFilter(filter().copyWith(genreIds: ['jazz']));
      await tester.pumpAndSettle();
      expect(filter().type, SearchType.album);
      _reopen(harness.container);

      expect(filter().type, isNull);
      expect(filter().genreIds, ['jazz']);
    });

    testWidgets('the page filter reaches each shelf in its own terms', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        catalogs: {
          'kalinka:localfiles:catalog:albums': [_album('b1', 'Moon Safari')],
        },
      );
      harness.api.calls.clear();

      harness.container
          .read(searchSessionProvider.notifier)
          .setCatalogFilter(const BrowseFilterQuery(text: 'moon'));
      await tester.pumpAndSettle();

      // A shelf never sees `type` — it is already one kind, and its source
      // would refuse a field it did not declare.
      expect(harness.api.calls.map((c) => c.filter).toSet(), {
        '{"q":{"contains":"moon"}}',
      });
    });
  });

  group('a shelf the filter cannot reach', () {
    final artistsByName = _section(
      id: 'kalinka:localfiles:catalog:artists',
      name: 'Artists',
      contentType: PreviewContentType.artist,
      filters: const [_textField],
    );
    final albumsByName = _section(
      id: 'kalinka:localfiles:catalog:albums',
      name: 'Albums',
      contentType: PreviewContentType.album,
      filters: const [_textField],
    );
    final catalogs = {
      'kalinka:localfiles:catalog:artists': [_album('a1', 'Air')],
      'kalinka:localfiles:catalog:albums': [_album('b1', 'Moon Safari')],
    };

    testWidgets('is left out rather than listed unfiltered', (tester) async {
      final harness = await _pump(
        tester,
        sections: [artistsByName, _sections[1]],
        catalogs: catalogs,
      );
      harness.api.calls.clear();

      harness.container
          .read(searchSessionProvider.notifier)
          .setCatalogFilter(const BrowseFilterQuery(genreIds: ['jazz']));
      await tester.pumpAndSettle();

      expect(find.text('ARTISTS'), findsNothing);
      expect(find.text('ALBUMS'), findsOneWidget);
      // Not fetched and hidden — never asked for.
      expect(harness.api.calls.map((c) => c.id), [
        'kalinka:localfiles:catalog:albums',
      ]);
    });

    testWidgets('is back once that filter is cleared', (tester) async {
      final harness = await _pump(
        tester,
        sections: [artistsByName, _sections[1]],
        catalogs: catalogs,
      );
      final session = harness.container.read(searchSessionProvider.notifier);

      session.setCatalogFilter(const BrowseFilterQuery(genreIds: ['jazz']));
      await tester.pumpAndSettle();
      session.setCatalogFilter(const BrowseFilterQuery(text: 'air'));
      await tester.pumpAndSettle();

      expect(find.text('ARTISTS'), findsOneWidget);
      expect(find.text('ALBUMS'), findsOneWidget);
    });

    testWidgets('leaves the page saying nothing matches when none is left', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        sections: [artistsByName, albumsByName],
        catalogs: catalogs,
      );
      harness.api.calls.clear();

      harness.container
          .read(searchSessionProvider.notifier)
          .setCatalogFilter(const BrowseFilterQuery(genreIds: ['jazz']));
      await tester.pumpAndSettle();

      expect(find.text('ARTISTS'), findsNothing);
      expect(find.text('ALBUMS'), findsNothing);
      expect(find.text('Nothing matches these filters'), findsOneWidget);
      expect(find.text('Reset filters'), findsOneWidget);
      expect(harness.api.calls, isEmpty);
    });
  });

  testWidgets('every shelf empty under the filter says so, with a reset', (
    tester,
  ) async {
    final harness = await _pump(
      tester,
      filteredOut: true,
      catalogs: {
        'kalinka:localfiles:catalog:artists': [_album('a1', 'Air')],
        'kalinka:localfiles:catalog:albums': [_album('b1', 'Moon Safari')],
      },
    );
    final session = harness.container.read(searchSessionProvider.notifier);

    session.setCatalogFilter(const BrowseFilterQuery(text: 'zzz'));
    await tester.pumpAndSettle();

    // Both shelves took the filter and came back with nothing: the page says
    // so under its header rather than standing as a header alone.
    expect(find.text('ARTISTS'), findsNothing);
    expect(find.text('ALBUMS'), findsNothing);
    expect(find.text('My Library'), findsOneWidget);
    expect(find.text('Nothing matches these filters'), findsOneWidget);

    await tester.tap(find.text('Reset filters'));
    await tester.pumpAndSettle();

    expect(
      harness.container.read(searchSessionProvider).catalogFilter.isEmpty,
      isTrue,
    );
    expect(find.text('Air'), findsOneWidget);
    expect(find.text('Moon Safari'), findsOneWidget);
  });
}
