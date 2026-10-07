import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/catalog_cards_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/indexer_status_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/widgets/browse_filters/search_filter_button.dart';
import 'package:kalinka/widgets/overlay_card.dart';
import 'package:kalinka/widgets/search/folder_trail.dart';
import 'package:kalinka/widgets/search/search_session_view.dart';

/// Mounting the whole Find Music surface is the only thing that exercises its
/// `initState` — where a second AnimationController on a
/// SingleTickerProviderStateMixin threw on the first build.
class _FakeApi implements KalinkaPlayerProxy {
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

class _FixedConnection extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

/// The real notifier polls `/indexer/status` on a repeating timer.
class _IdleIndexer extends IndexerStatusNotifier {
  @override
  IndexerStatusState build() => const IndexerStatusState();

  @override
  void acquire() {}

  @override
  void release() {}
}

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

  ProviderContainer makeContainer({List<ModuleInfo> modules = const []}) {
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        kalinkaProxyProvider.overrideWithValue(_FakeApi()),
        sourceModulesProvider.overrideWith((ref) => modules),
        connectionStateProvider.overrideWith(_FixedConnection.new),
        playerStateProvider.overrideWithValue(PlaybackState.empty),
        catalogCardGroupsProvider.overrideWith(
          (ref) => Future.value(const <CatalogCardGroup>[]),
        ),
        indexerStatusProvider.overrideWith(_IdleIndexer.new),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<ProviderContainer> pumpSurface(
    WidgetTester tester, {
    List<ModuleInfo> modules = const [],
  }) async {
    final container = makeContainer(modules: modules);
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

  testWidgets('the surface mounts without throwing', (tester) async {
    await pumpSurface(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('DISCOVER'), findsOneWidget);
  });

  testWidgets('the Discover root offers no filter control', (tester) async {
    await pumpSurface(tester);
    // Nothing to narrow at the root — the button would be a dead affordance.
    expect(find.byType(SearchFilterButton), findsNothing);
  });

  testWidgets('a catalog page carries the filter control, and it opens', (
    tester,
  ) async {
    final container = await pumpSurface(tester);

    container
        .read(searchSessionProvider.notifier)
        .openCatalog(
          id: 'kalinka:localfiles:catalog:albums',
          title: 'My Albums',
          // The control stands for what the source declared, so a category
          // that declared nothing has none to show.
          filters: const [
            FilterSpec(
              id: 'q',
              kind: FilterKind.text,
              label: 'Search albums and artists',
            ),
          ],
        );
    await tester.pumpAndSettle();

    expect(find.byType(SearchFilterButton), findsOneWidget);

    await tester.tap(find.byType(SearchFilterButton));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('SEARCH & FILTERS'), findsOneWidget);

    // Cancel folds it away again without touching the applied filter.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('SEARCH & FILTERS'), findsNothing);
    expect(container.read(searchSessionProvider).catalogFilter.isEmpty, isTrue);
  });

  testWidgets('the Results view carries the filter control, and it opens', (
    tester,
  ) async {
    final container = await pumpSurface(
      tester,
      modules: [
        ModuleInfo(
          name: 'qobuz',
          title: 'Qobuz',
          enabled: true,
          state: ModuleState.ready,
        ),
      ],
    );
    container.read(searchSessionProvider.notifier).submit('the beatles');
    // Past the minimum loading hold, so the legs have landed.
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byType(SearchFilterButton), findsOneWidget);

    await tester.tap(find.byType(SearchFilterButton));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('REFINE RESULTS'), findsOneWidget);
    // The field re-searches rather than narrowing, and says so.
    expect(find.text('A new query starts a new search.'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('REFINE RESULTS'), findsNothing);
    expect(container.read(searchSessionProvider).resultsFilter.isEmpty, isTrue);
  });

  testWidgets('the smart search card names itself and closes', (tester) async {
    await pumpSurface(tester);

    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == 'Search',
      ),
    );
    await tester.pumpAndSettle();

    // The card carries its own name and dismiss, the same chrome the filter
    // card uses, so the composer inside it needs neither.
    expect(find.text('SMART SEARCH'), findsOneWidget);

    await tester.tap(find.byType(OverlayCloseButton));
    await tester.pumpAndSettle();
    expect(find.text('SMART SEARCH'), findsNothing);
  });

  testWidgets('the DISCOVER crumb goes back, like the arrow', (tester) async {
    final container = await pumpSurface(tester);
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(
          id: 'kalinka:localfiles:catalog:albums',
          title: 'My Albums',
        );
    await tester.pumpAndSettle();
    expect(container.read(searchSessionProvider).catalogPage.isRoot, isFalse);

    await tester.tap(find.text('DISCOVER'));
    await tester.pumpAndSettle();
    expect(container.read(searchSessionProvider).catalogPage.isRoot, isTrue);
  });

  testWidgets('a page of folders keeps the bar\'s crumb, its trail below', (
    tester,
  ) async {
    final container = await pumpSurface(tester);
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(
          id: 'kalinka:localfiles:catalog:files',
          title: 'My Library',
          folderLayout: true,
        );
    await tester.pumpAndSettle();

    expect(find.text('DISCOVER'), findsOneWidget);
    expect(find.text('MY LIBRARY'), findsOneWidget);
    expect(find.byType(FolderTrail), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(container.read(searchSessionProvider).catalogPage.isRoot, isTrue);
  });

  testWidgets('the DISCOVER crumb highlights under the pointer', (
    tester,
  ) async {
    final container = await pumpSurface(tester);
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(
          id: 'kalinka:localfiles:catalog:albums',
          title: 'My Albums',
        );
    await tester.pumpAndSettle();

    Color? crumbFill() {
      final box = tester.widget<AnimatedContainer>(
        find
            .ancestor(
              of: find.text('DISCOVER'),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      return (box.decoration as BoxDecoration).color;
    }

    expect(crumbFill(), Colors.transparent);

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);
    await pointer.moveTo(tester.getCenter(find.text('DISCOVER')));
    await tester.pumpAndSettle();
    expect(crumbFill()!.a, greaterThan(0));
  });

  testWidgets('at the root the crumb names the page, and does not act', (
    tester,
  ) async {
    final container = await pumpSurface(tester);

    // Nowhere to go back to from Discover itself.
    await tester.tap(find.text('DISCOVER'));
    await tester.pumpAndSettle();
    expect(container.read(searchSessionProvider).isOpen, isTrue);
  });
}
