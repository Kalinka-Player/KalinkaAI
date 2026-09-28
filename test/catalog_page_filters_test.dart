import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/browse_filters.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/widgets/browse_filters/active_filter_chips.dart';
import 'package:kalinka/widgets/search/catalog_page_view.dart';

/// Answers browse with nothing, so the page settles on its empty state and the
/// rows never pull in the player/favourite providers.
class _EmptyBrowseApi implements KalinkaPlayerProxy {
  /// The filter document each browse carried, as the server would see it.
  final List<String?> filtersSeen = [];

  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async {
    filtersSeen.add(filter);
    return BrowseItemsList(offset, limit, 0, const []);
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

const _genreField = FilterSpec(
  id: 'genre',
  kind: FilterKind.choice,
  label: 'Genre',
  ops: [FilterOp.any],
);
const _textField = FilterSpec(
  id: 'q',
  kind: FilterKind.text,
  label: 'Search albums and artists',
);

late SharedPreferences _prefs;

/// The page and the session that owns its filter — the filter control lives in
/// the title bar, so edits arrive through the notifier, not the widget.
typedef _Harness = ({_EmptyBrowseApi api, ProviderContainer container});

Future<_Harness> _pumpPage(WidgetTester tester, CatalogPage page) async {
  final api = _EmptyBrowseApi();
  final container = ProviderContainer(
    overrides: [
      kalinkaProxyProvider.overrideWithValue(api),
      // The page reads the applied filter off the session, whose notifier
      // loads its history from prefs.
      sharedPrefsProvider.overrideWithValue(_prefs),
    ],
  );
  addTearDown(container.dispose);
  if (!page.isRoot) {
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(
          id: page.id!,
          title: page.title!,
          provider: page.provider,
          description: page.description,
          filters: page.filters,
          sections: page.sections,
        );
  }

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
  await tester.pumpAndSettle();
  return (api: api, container: container);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  group('capabilities', () {
    test('a category offers what its source declared, and no kind group', () {
      const page = CatalogPage.category(
        id: 'kalinka:localfiles:catalog:albums',
        title: 'My Albums',
        filters: [_textField, _genreField],
      );
      final caps = page.filterCapabilities;

      // One category holds one kind — nothing to choose between.
      expect(caps.type, FacetSupport.hidden);
      expect(caps.text, FacetSupport.supported);
      expect(caps.genre, FacetSupport.supported);
      expect(caps.genreVocabulary, (
        catalogId: 'kalinka:localfiles:catalog:albums',
        field: 'genre',
      ));
    });

    test('a facet the source did not declare is hidden, not muted', () {
      // The server refuses a field it never offered, so there is no
      // affordance for a placeholder to stand in for.
      const page = CatalogPage.category(
        id: 'kalinka:qobuz:catalog:new',
        title: 'New Releases',
        filters: [_genreField],
      );
      final caps = page.filterCapabilities;

      expect(caps.text, FacetSupport.hidden);
      expect(caps.genre, FacetSupport.supported);
    });

    test('a source that declares nothing offers nothing', () {
      const page = CatalogPage.category(
        id: 'kalinka:jamendo:catalog:popular-artists',
        title: 'Popular Artists',
      );
      expect(page.filterCapabilities.isEmpty, isTrue);
    });

    test('the root has nothing to filter', () {
      expect(const CatalogPage.root().filterCapabilities.isEmpty, isTrue);
    });
  });

  group('page head', () {
    testWidgets('the description stands alone — no repeated provider line', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        const CatalogPage.category(
          id: 'kalinka:localfiles:catalog:recent',
          title: 'Recently Added',
          provider: 'Local library',
          description: 'Recently added tracks',
        ),
      );

      expect(find.text('Recently Added'), findsOneWidget);
      expect(find.text('Recently added tracks'), findsOneWidget);
      expect(find.text('Local library'), findsNothing);
    });

    testWidgets('the provider stands in when there is no description', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        const CatalogPage.category(
          id: 'kalinka:localfiles:catalog:recent',
          title: 'Recently Added',
          provider: 'Local library',
        ),
      );

      expect(find.text('Local library'), findsOneWidget);
    });

    // flutter_test substitutes a font whose every glyph is a square of the
    // font size, so real wrapping cannot be exercised here. Assert the
    // mechanism instead: the width the title gets to lay out in.
    testWidgets('the title column is wide, not the old narrow half', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpPage(
        tester,
        const CatalogPage.category(
          id: 'kalinka:localfiles:catalog:recent',
          title: 'Recently Added',
          description: 'Recently added tracks',
        ),
      );

      // 400 wide, less the banner's 16px insets, times the column factor.
      expect(
        tester.getSize(find.text('Recently Added')).width,
        greaterThan(0.7 * (400 - 32)),
      );
    });

    testWidgets('a wide window does not open a dead zone above the title', (
      tester,
    ) async {
      // The banner block used to be centred in the (much taller) art zone, so
      // every surplus pixel showed up as empty art above the title.
      tester.view.physicalSize = const Size(1010, 1500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpPage(
        tester,
        const CatalogPage.category(
          id: 'kalinka:jamendo:catalog:popular',
          title: 'Popular Tracks',
          description: 'Most played this month',
        ),
      );

      // The block is content-sized, so its offset is the banner inset alone
      // and does not grow with the window. Deliberately a bound, not an exact
      // inset — the spacing itself is free to be tuned.
      final title = tester.getRect(find.text('Popular Tracks'));
      expect(title.top, lessThan(30));
      // Left-aligned at the banner inset: the text column hugs the edge, it
      // is not centred in whatever width it was given.
      expect(title.left, 16);
    });

    testWidgets('the controls live in the title bar, not on the page', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        const CatalogPage.category(
          id: 'kalinka:localfiles:catalog:albums',
          title: 'My Albums',
        ),
      );

      expect(find.byType(TextField), findsNothing);
      expect(find.text('Albums'), findsNothing);
    });
  });

  testWidgets('an empty category reads as empty, not as filtered out', (
    tester,
  ) async {
    final api = (await _pumpPage(
      tester,
      const CatalogPage.category(
        id: 'kalinka:localfiles:catalog:albums',
        title: 'My Albums',
      ),
    )).api;

    // Nothing is filtered yet, so browse is asked plainly.
    expect(api.filtersSeen, [null]);
    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(find.text('Nothing matches these filters'), findsNothing);
    expect(find.text('Reset filters'), findsNothing);
  });

  testWidgets('a filter that empties the list offers to drop it', (
    tester,
  ) async {
    final harness = await _pumpPage(
      tester,
      const CatalogPage.category(
        id: 'kalinka:localfiles:catalog:albums',
        title: 'My Albums',
        filters: [_textField, _genreField],
      ),
    );
    harness.container
        .read(searchSessionProvider.notifier)
        .setCatalogFilter(const BrowseFilterQuery(genreIds: ['jazz']));
    await tester.pumpAndSettle();
    expect(find.text('Nothing matches these filters'), findsOneWidget);

    await tester.tap(find.text('Reset filters'));
    await tester.pumpAndSettle();

    expect(
      harness.container.read(searchSessionProvider).catalogFilter.isEmpty,
      isTrue,
    );
    // The list starts over, asked plainly.
    expect(harness.api.filtersSeen, [null, '{"genre":{"any":["jazz"]}}', null]);
    expect(find.text('Nothing here yet'), findsOneWidget);
  });

  group('applying filters', () {
    testWidgets('a changed filter refetches the list', (tester) async {
      final harness = await _pumpPage(
        tester,
        const CatalogPage.category(
          id: 'kalinka:localfiles:catalog:albums',
          title: 'My Albums',
          filters: [_textField, _genreField],
        ),
      );
      expect(harness.api.filtersSeen, hasLength(1));

      harness.container
          .read(searchSessionProvider.notifier)
          .setCatalogFilter(const BrowseFilterQuery(genreIds: ['jazz']));
      await tester.pumpAndSettle();

      // The list restarts from the top and carries the genre through, in the
      // operation the source said it honours.
      expect(harness.api.filtersSeen, [null, '{"genre":{"any":["jazz"]}}']);
    });

    testWidgets('text travels as the field the source declared', (
      tester,
    ) async {
      final harness = await _pumpPage(
        tester,
        const CatalogPage.category(
          id: 'kalinka:localfiles:catalog:albums',
          title: 'My Albums',
          filters: [_textField, _genreField],
        ),
      );

      harness.container
          .read(searchSessionProvider.notifier)
          .setCatalogFilter(const BrowseFilterQuery(text: 'blue'));
      await tester.pumpAndSettle();

      expect(harness.api.filtersSeen.last, '{"q":{"contains":"blue"}}');
    });

    testWidgets('touching nothing the backend sees costs no refetch', (
      tester,
    ) async {
      final harness = await _pumpPage(
        tester,
        const CatalogPage.category(
          id: 'kalinka:localfiles:catalog:albums',
          title: 'My Albums',
        ),
      );

      // The kind group is hidden here, so a kind never reaches serverKey.
      harness.container
          .read(searchSessionProvider.notifier)
          .setCatalogFilter(const BrowseFilterQuery(type: SearchType.album));
      await tester.pumpAndSettle();
      expect(harness.api.filtersSeen, hasLength(1));
    });

    testWidgets('applied filters show as chips above the rows', (tester) async {
      final harness = await _pumpPage(
        tester,
        const CatalogPage.category(
          id: 'kalinka:localfiles:catalog:albums',
          title: 'My Albums',
          filters: [_textField, _genreField],
        ),
      );
      expect(find.byType(ActiveFilterChips), findsOneWidget);
      expect(find.text('RESET ALL'), findsNothing);

      harness.container
          .read(searchSessionProvider.notifier)
          .setCatalogFilter(
            const BrowseFilterQuery(genreIds: ['jazz', 'rock']),
          );
      await tester.pumpAndSettle();

      // No vocabulary behind the fake, so a chip falls back to the raw id.
      expect(find.text('jazz'), findsOneWidget);
      // Two filters earn the bulk action.
      expect(find.text('RESET ALL'), findsOneWidget);

      await tester.tap(find.text('RESET ALL'));
      await tester.pumpAndSettle();
      expect(
        harness.container.read(searchSessionProvider).catalogFilter.isEmpty,
        isTrue,
      );
      expect(find.text('RESET ALL'), findsNothing);
    });
  });
}
