import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/browse_filters.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/search_results.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/catalog_sources_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/modules_state_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/widgets/search/search_zero_state.dart';

/// Minimal fake proxy: only the methods the search session calls are
/// implemented; everything else throws if unexpectedly invoked.
class _FakeApi implements KalinkaPlayerProxy {
  List<ModuleInfo> modules = _modules;
  int moduleCalls = 0;

  @override
  Future<ModulesAndDevices> listModules() async {
    moduleCalls++;
    return ModulesAndDevices(inputModules: modules, devices: const []);
  }

  int aiSearchCalls = 0;
  int matchCalls = 0;
  final List<String> queries = [];
  final List<String> aiSources = [];
  final List<String> matchSources = [];

  @override
  Future<BrowseItemsList> aiSearch(
    String query, {
    int offset = 0,
    int limit = 10,
    List<String>? sources,
  }) async {
    aiSearchCalls++;
    aiSources.add(sources!.single);
    return _inspiredFor(sources.single);
  }

  @override
  Future<BrowseItemsList> searchMatches(
    String query, {
    List<String>? sources,
  }) async {
    matchCalls++;
    queries.add(query);
    matchSources.add(sources!.single);
    return sources.single == 'tidal'
        ? BrowseItemsList(0, 1, 1, [_track('tidal', 't1', 'A Song')])
        : _matchesFor(sources.single);
  }

  @override
  Future<BrowseItemsList> getFavorite(
    SearchType queryType, {
    int offset = 0,
    int limit = 10,
    String filter = '',
  }) async {
    return BrowseItemsList(0, limit, 1, [
      BrowseItem(
        id: 'kalinka:localfiles:track:fav_${queryType.name}',
        canBrowse: false,
        canAdd: true,
        timestamp: 1000,
        track: Track(
          id: 'fav_${queryType.name}',
          title: 'Favourite ${queryType.name}',
          duration: 120,
          performer: Artist(id: 'a', name: 'Someone'),
        ),
      ),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// The search that never answers — neither leg's future ever completes.
class _HangingApi extends _FakeApi {
  @override
  Future<BrowseItemsList> aiSearch(
    String query, {
    int offset = 0,
    int limit = 10,
    List<String>? sources,
  }) {
    aiSearchCalls++;
    return Completer<BrowseItemsList>().future;
  }

  @override
  Future<BrowseItemsList> searchMatches(String query, {List<String>? sources}) {
    matchCalls++;
    return Completer<BrowseItemsList>().future;
  }
}

/// A source whose name-match leg fails on the first ask and answers after.
class _FlakyApi extends _FakeApi {
  @override
  Future<BrowseItemsList> searchMatches(
    String query, {
    List<String>? sources,
  }) async {
    matchCalls++;
    if (matchCalls == 1) throw Exception('upstream down');
    return _matchesFor(sources!.single);
  }
}

/// Every source finds an artist and an album.
class _TwoKindApi extends _FakeApi {
  @override
  Future<BrowseItemsList> searchMatches(
    String query, {
    List<String>? sources,
  }) async {
    final list = await super.searchMatches(query, sources: sources);
    final source = sources!.single;
    return BrowseItemsList(0, 2, 2, [
      ...list.items,
      BrowseItem(
        id: 'kalinka:$source:album:al1',
        name: 'An Album',
        canBrowse: true,
        canAdd: true,
        album: Album(
          id: 'al1',
          title: 'An Album',
          genres: [Genre(id: '42', name: 'Jazz')],
        ),
        match: const NameMatch(tier: MatchTier.partial, score: 60),
      ),
    ]);
  }
}

/// Only qobuz finds an album, and its name-match leg fails the first time.
class _AlbumsLateApi extends _TwoKindApi {
  int _qobuzAsked = 0;

  @override
  Future<BrowseItemsList> searchMatches(
    String query, {
    List<String>? sources,
  }) async {
    if (sources!.single != 'qobuz') {
      matchCalls++;
      matchSources.add(sources.single);
      return _matchesFor(sources.single);
    }
    if (++_qobuzAsked == 1) {
      matchCalls++;
      throw Exception('upstream down');
    }
    return super.searchMatches(query, sources: sources);
  }
}

class _CollectionsApi extends _FakeApi {
  static const shelfId = 'kalinka:collections:catalog:collections';
  static const _rootId = 'kalinka:collections:catalog:root';

  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async {
    final items = switch (id) {
      '' => [
        BrowseItem(
          id: _rootId,
          name: 'Collections',
          canBrowse: true,
          canAdd: false,
          catalog: Catalog(id: _rootId, title: 'Collections'),
        ),
      ],
      _rootId => [
        BrowseItem(
          id: shelfId,
          name: 'Your collections',
          canBrowse: true,
          canAdd: false,
          catalog: Catalog(
            id: shelfId,
            title: 'Your collections',
            previewConfig: Preview(
              type: PreviewType.tile,
              contentType: PreviewContentType.playlist,
            ),
          ),
        ),
      ],
      _ => const <BrowseItem>[],
    };
    return BrowseItemsList(
      offset,
      limit,
      items.length,
      items.skip(offset).take(limit).toList(),
    );
  }
}

/// Pinned connection state — the real notifier arms a retry [Timer] that
/// would outlive widget tests.
class _FixedConnection extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

BrowseItem _track(String source, String id, String title) => BrowseItem(
  id: 'kalinka:$source:track:$id',
  canBrowse: false,
  canAdd: true,
  track: Track(
    id: id,
    title: title,
    duration: 200,
    performer: Artist(id: 'ar', name: 'An Artist'),
  ),
);

BrowseItemsList _matchesFor(String source) => BrowseItemsList(0, 1, 1, [
  BrowseItem(
    id: 'kalinka:$source:artist:a1',
    name: 'An Artist',
    canBrowse: true,
    canAdd: false,
    artist: Artist(id: 'a1', name: 'An Artist'),
    match: const NameMatch(tier: MatchTier.exact, score: 100),
  ),
]);

BrowseItemsList _inspiredFor(String source) => BrowseItemsList(0, 1, 1, [
  BrowseItem(
    id: 'kalinka:$source:catalog:ai',
    name: 'AI SUGGESTIONS',
    canBrowse: false,
    canAdd: false,
    catalog: Catalog(id: 'ai', title: 'AI SUGGESTIONS', sources: [source]),
    sections: [_track(source, 't1', 'Song A'), _track(source, 't2', 'Song B')],
  ),
]);

final _modules = <ModuleInfo>[
  ModuleInfo(
    name: 'qobuz',
    title: 'Qobuz',
    enabled: true,
    state: ModuleState.ready,
    capabilities: const [ModuleCapability.catalogs, ModuleCapability.aiSearch],
  ),
];

/// A source that is searched by name but has no audio of its own to suggest —
/// the shape collections has.
final _nameOnlyModules = <ModuleInfo>[
  ModuleInfo(
    name: 'collections',
    title: 'Collections',
    enabled: true,
    state: ModuleState.ready,
    builtin: true,
  ),
];

final _twoSources = <ModuleInfo>[
  ..._modules,
  ModuleInfo(
    name: 'localfiles',
    title: 'Local Library',
    enabled: true,
    state: ModuleState.ready,
    capabilities: const [ModuleCapability.catalogs, ModuleCapability.aiSearch],
  ),
];

/// Neither source suggests, so the kind facet is hidden.
final _twoNameOnlySources = <ModuleInfo>[
  for (final (name, title) in [('qobuz', 'Qobuz'), ('localfiles', 'Local')])
    ModuleInfo(
      name: name,
      title: title,
      enabled: true,
      state: ModuleState.ready,
      capabilities: const [ModuleCapability.catalogs],
    ),
];

const _genreField = FilterSpec(
  id: 'genre',
  kind: FilterKind.choice,
  label: 'Genre',
  ops: [FilterOp.any],
);
const _textField = FilterSpec(
  id: 'q',
  kind: FilterKind.text,
  label: 'Search albums',
);

/// Longer than the minimum loading hold.
const _settle = Duration(milliseconds: 900);

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

  ProviderContainer makeContainer(
    _FakeApi api, {
    List<ModuleInfo>? modules,
    Duration? modulesAfter,
    bool liveModules = false,
  }) {
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        kalinkaProxyProvider.overrideWithValue(api),
        if (!liveModules && modulesAfter == null)
          sourceModulesProvider.overrideWith((ref) => modules ?? _modules)
        else if (!liveModules)
          sourceModulesProvider.overrideWith(
            (ref) => Future.delayed(modulesAfter!, () => modules ?? _modules),
          ),
        connectionStateProvider.overrideWith(_FixedConnection.new),
        // The real provider opens the wire-event WebSocket (retry timer).
        playerStateProvider.overrideWithValue(PlaybackState.empty),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('SearchSessionNotifier', () {
    test(
      'plugin refresh updates search sources, tracks and source filters',
      () async {
        final api = _FakeApi();
        final container = makeContainer(api, liveModules: true);
        final notifier = container.read(searchSessionProvider.notifier);
        notifier.submit('A Song');
        await Future.delayed(_settle);
        expect(api.matchSources, ['qobuz']);
        expect(api.moduleCalls, 1);

        api.modules = [
          ..._modules,
          ModuleInfo(
            name: 'tidal',
            title: 'TIDAL',
            enabled: true,
            state: ModuleState.ready,
            capabilities: const [ModuleCapability.catalogs],
          ),
        ];
        container.invalidate(modulesStateProvider);
        await container.read(modulesStateProvider.future);
        expect(
          (await container.read(sourceModulesProvider.future))
              .map((m) => m.name),
          ['qobuz', 'tidal'],
        );
        expect(
          container.read(sourceDisplayInfoProvider)['tidal']!.title,
          'TIDAL',
        );
        notifier.submit('A Song');
        await Future.delayed(_settle);
        final results = container.read(searchSessionProvider).results!;
        expect(api.matchSources, contains('tidal'));
        expect(api.aiSources, isNot(contains('tidal')));
        expect(results.sources.map((s) => s.name), contains('tidal'));
        expect(
          results.rankedMatches.any((item) => item.track?.title == 'A Song'),
          isTrue,
        );
        expect(api.moduleCalls, 2);

        api.modules = _modules;
        container.invalidate(modulesStateProvider);
        expect(
          (await container.read(sourceModulesProvider.future))
              .map((m) => m.name),
          ['qobuz'],
        );
      },
    );

    test('refreshing fires no search', () async {
      final api = _FakeApi();
      final container = makeContainer(api);
      final notifier = container.read(searchSessionProvider.notifier);

      notifier.refresh();
      await Future.delayed(const Duration(milliseconds: 50));

      final state = container.read(searchSessionProvider);
      expect(state.activeView, FindMusicView.catalogs);
      expect(state.resultsAvailable, isFalse);
      expect(api.matchCalls + api.aiSearchCalls, 0);
    });

    test(
      'submit asks every source twice and lands each leg on its own',
      () async {
        final api = _FakeApi();
        final container = makeContainer(api);
        final notifier = container.read(searchSessionProvider.notifier);
        notifier.refresh();

        notifier.submit('jazz for a rainy night');
        var state = container.read(searchSessionProvider);
        expect(state.activeView, FindMusicView.results);
        expect(state.resultsAvailable, isTrue);
        expect(state.searchQuery, 'jazz for a rainy night');
        expect(state.searchLoading, isTrue);

        await Future.delayed(const Duration(milliseconds: 900));
        state = container.read(searchSessionProvider);
        final results = state.results!;
        expect(state.searchLoading, isFalse);
        expect(results.matchesSettled, isTrue);
        expect(results.rankedMatches, hasLength(1));
        expect(results.inspiredGroups.single.tracks, hasLength(2));
        expect(api.matchCalls, 1);
        expect(api.aiSearchCalls, 1);
      },
    );

    test('a source with nothing to suggest is asked once, not twice', () async {
      final api = _FakeApi();
      final container = makeContainer(api, modules: _nameOnlyModules);
      final notifier = container.read(searchSessionProvider.notifier);
      notifier.refresh();

      notifier.submit('night');
      await Future.delayed(const Duration(milliseconds: 900));

      final results = container.read(searchSessionProvider).results!;
      expect(api.matchCalls, 1);
      expect(api.aiSearchCalls, 0);
      // No leg was asked of it, so it holds no row waiting for one.
      expect(results.inspiredGroups, isEmpty);
    });

    test('a new submit replaces the previous query', () async {
      final api = _FakeApi();
      final container = makeContainer(api);
      final notifier = container.read(searchSessionProvider.notifier);
      notifier.refresh();

      notifier.submit('one');
      notifier.submit('two');
      await Future.delayed(const Duration(milliseconds: 900));

      final state = container.read(searchSessionProvider);
      expect(state.searchQuery, 'two');
      expect(state.results!.query, 'two');
      // Superseded before its sources were even resolved, the first query
      // never reaches the network.
      expect(api.queries, ['two']);
      // Newest-first history.
      expect(state.history.take(2), ['two', 'one']);
    });

    test('a source that never answers is unavailable, leg by leg', () {
      fakeAsync((async) {
        final api = _HangingApi();
        final container = makeContainer(api);
        final notifier = container.read(searchSessionProvider.notifier);
        notifier.refresh();
        notifier.submit('jazz');
        async.flushMicrotasks();
        var results = container.read(searchSessionProvider).results!;
        expect(results.matches['qobuz'], isA<LegLoading>());
        expect(api.matchCalls, 1);

        // Just short of the cap the legs are still patiently loading…
        async.elapse(const Duration(seconds: 9));
        results = container.read(searchSessionProvider).results!;
        expect(results.matches['qobuz'], isA<LegLoading>());

        // …and past it each leg gives up and says so.
        async.elapse(const Duration(seconds: 2));
        final state = container.read(searchSessionProvider);
        results = state.results!;
        expect(results.matches['qobuz'], isA<LegFailed>());
        expect(results.inspired['qobuz'], isA<LegFailed>());
        expect(state.searchError, isNull);
      });
    });

    test('retry asks that one source for that one leg again', () async {
      final api = _FlakyApi();
      final container = makeContainer(api);
      final notifier = container.read(searchSessionProvider.notifier);
      notifier.refresh();

      notifier.submit('jazz');
      await Future.delayed(const Duration(milliseconds: 900));
      expect(
        container.read(searchSessionProvider).results!.matches['qobuz'],
        isA<LegFailed>(),
      );

      notifier.retry(ResultsLeg.matches, 'qobuz');
      expect(
        container.read(searchSessionProvider).results!.matches['qobuz'],
        isA<LegLoading>(),
      );
      await Future.delayed(const Duration(milliseconds: 900));
      final results = container.read(searchSessionProvider).results!;
      expect(results.matches['qobuz'], isA<LegReady>());
      expect(api.matchCalls, 2);
      expect(api.aiSearchCalls, 1, reason: 'the other leg is left alone');
    });

    test('narrowing keeps the query out of the facets', () async {
      final api = _FakeApi();
      final container = makeContainer(api);
      final notifier = container.read(searchSessionProvider.notifier);
      notifier.refresh();
      notifier.submit('jazz');

      notifier.setResultsFilter(
        const BrowseFilterQuery(text: 'jazz', type: SearchType.album),
      );

      final filter = container.read(searchSessionProvider).resultsFilter;
      expect(filter.type, SearchType.album);
      expect(filter.text, isEmpty);
      await Future.delayed(const Duration(milliseconds: 900));
    });

    test('clearing the search returns to Catalogs with nothing kept', () async {
      final api = _FakeApi();
      final container = makeContainer(api);
      final notifier = container.read(searchSessionProvider.notifier);
      notifier.refresh();
      notifier.submit('jazz');
      await Future.delayed(const Duration(milliseconds: 900));

      notifier.clearSearch();

      final state = container.read(searchSessionProvider);
      expect(state.activeView, FindMusicView.catalogs);
      expect(state.resultsAvailable, isFalse);
      expect(state.results, isNull);
      expect(state.searchQuery, isEmpty);
    });

    test('view switches are gated and layered', () async {
      final api = _FakeApi();
      final container = makeContainer(api);
      final notifier = container.read(searchSessionProvider.notifier);
      notifier.refresh();

      // Results is inert until a search has run.
      notifier.selectView(FindMusicView.results);
      expect(
        container.read(searchSessionProvider).activeView,
        FindMusicView.catalogs,
      );

      notifier.openCatalog(id: 'cat1', title: 'Popular Tracks');
      expect(container.read(searchSessionProvider).catalogPage.isRoot, isFalse);

      // Reselecting Catalogs while on a page returns to its root.
      notifier.selectView(FindMusicView.catalogs);
      expect(container.read(searchSessionProvider).catalogPage.isRoot, isTrue);

      notifier.submit('jazz');
      expect(
        container.read(searchSessionProvider).activeView,
        FindMusicView.results,
      );
      notifier.selectView(FindMusicView.catalogs);
      expect(
        container.read(searchSessionProvider).activeView,
        FindMusicView.catalogs,
      );
      // Results stays reachable once available.
      notifier.selectView(FindMusicView.results);
      expect(
        container.read(searchSessionProvider).activeView,
        FindMusicView.results,
      );
      await Future.delayed(const Duration(milliseconds: 900));
    });

    test('Results keeps its pages until a new search replaces them', () async {
      final api = _FakeApi();
      final container = makeContainer(api);
      final notifier = container.read(searchSessionProvider.notifier);
      SearchSessionState state() => container.read(searchSessionProvider);

      notifier.submit('jazz');
      await Future.delayed(const Duration(milliseconds: 900));
      notifier.setMatchSource('localfiles');
      notifier.openCatalog(
        id: 'kalinka:localfiles:album:a1',
        title: 'Kind of Blue',
      );
      // A page opened from Results is still Results, whatever its source.
      expect(state().destination, BrowseDestination.results);

      notifier.goBack();
      expect(state().activeView, FindMusicView.results);
      expect(state().searchQuery, 'jazz');
      expect(state().results?.settled, isTrue);
      expect(state().matchSource, 'localfiles');

      notifier.openCatalog(
        id: 'kalinka:localfiles:album:a1',
        title: 'Kind of Blue',
      );
      notifier.submit('techno');
      await Future.delayed(const Duration(milliseconds: 900));
      expect(state().searchQuery, 'techno');
      expect(state().previousVisits, isEmpty);

      // Its first page goes Home, not to the search before it.
      notifier.goBack();
      expect(state().atHome, isTrue);
      expect(state().destination, BrowseDestination.home);
      expect(state().previousVisits, isEmpty);
    });

    test('each destination keeps its own history', () {
      final container = makeContainer(_FakeApi());
      final notifier = container.read(searchSessionProvider.notifier);
      SearchSessionState state() => container.read(searchSessionProvider);
      CatalogSource source(String name) => (
        module: ModuleInfo(
          name: name,
          title: name,
          enabled: true,
          state: ModuleState.ready,
        ),
        root: BrowseItem(
          id: 'kalinka:$name:catalog:root',
          name: name,
          canBrowse: true,
          canAdd: false,
        ),
      );
      BrowseItem album(String id) =>
          BrowseItem(id: id, name: id, canBrowse: true, canAdd: false);

      notifier.openSource(source('qobuz'));
      notifier.openBrowseItem(album('kalinka:qobuz:album:a'));
      notifier.openSource(source('tidal'));
      notifier.openBrowseItem(album('kalinka:tidal:album:b'));
      expect(state().destination, BrowseDestination.source('tidal'));

      // Back as it was left, the visit under it included.
      final qobuzAlbum = state().parked[BrowseDestination.source('qobuz')]!;
      notifier.openSource(source('qobuz'));
      expect(state().catalogPage.id, 'kalinka:qobuz:album:a');
      expect(state().visitId, qobuzAlbum.visitId);
      notifier.goBack();
      expect(state().catalogPage.id, 'kalinka:qobuz:catalog:root');

      // Showing the destination shown does nothing.
      notifier.openSource(source('qobuz'));
      expect(state().catalogPage.id, 'kalinka:qobuz:catalog:root');

      // A source's first page goes Home; the source stays where it was.
      notifier.goBack();
      expect(state().atHome, isTrue);
      expect(state().parked, contains(BrowseDestination.source('qobuz')));

      // Without the rail, a source opens at its own page.
      notifier.openSource(source('tidal'), restore: false);
      expect(state().catalogPage.id, 'kalinka:tidal:catalog:root');
      expect(state().previousVisits, isEmpty);
    });

    test('opening a page already in the history goes back to it', () {
      final container = makeContainer(_FakeApi());
      final notifier = container.read(searchSessionProvider.notifier);
      SearchSessionState state() => container.read(searchSessionProvider);
      BrowseItem item(String id) =>
          BrowseItem(id: id, name: id, canBrowse: true, canAdd: false);
      const album = 'kalinka:qobuz:album:a';
      const artist = 'kalinka:qobuz:artist:b';

      notifier.openBrowseItem(item(album));
      notifier.openBrowseItem(item(artist));
      notifier.openBrowseItem(item(album));
      expect(state().catalogPage.id, album);
      expect(state().previousVisits, isEmpty);

      // However often the two link to each other, Back stays one deep.
      for (var i = 0; i < 3; i++) {
        notifier.openBrowseItem(item(artist));
        notifier.openBrowseItem(item(album));
      }
      notifier.openBrowseItem(item(artist));
      expect(state().catalogPage.id, artist);
      expect(state().previousVisits, hasLength(1));
    });

    test('a complete listing is a visit of its own', () async {
      final container = makeContainer(_FakeApi());
      final notifier = container.read(searchSessionProvider.notifier);
      SearchSessionState state() => container.read(searchSessionProvider);

      notifier.submit('jazz');
      await Future.delayed(const Duration(milliseconds: 900));
      notifier.expandBlock((kind: ResultKind.nameMatches, source: null));
      expect(state().expandedBlock, isNotNull);

      notifier.goBack();
      expect(state().activeView, FindMusicView.results);
      expect(state().expandedBlock, isNull);

      // Its chip returns the same way rather than adding a visit.
      notifier.expandBlock((kind: ResultKind.nameMatches, source: null));
      notifier.expandBlock(null);
      expect(state().expandedBlock, isNull);
      expect(state().previousVisits, isEmpty);
    });

    test('a search replaced before it answered is never asked', () async {
      final api = _FakeApi();
      final container = makeContainer(api);
      final notifier = container.read(searchSessionProvider.notifier);
      SearchSessionState state() => container.read(searchSessionProvider);

      notifier.submit('jazz');
      notifier.submit('techno');
      await Future.delayed(const Duration(milliseconds: 900));
      expect(api.queries, isNot(contains('jazz')));

      notifier.goBack();
      expect(state().atHome, isTrue);
      await Future.delayed(const Duration(milliseconds: 900));
      expect(api.queries, isNot(contains('jazz')));
    });

    test('resetting discards the workspace but keeps history', () async {
      final api = _FakeApi();
      final container = makeContainer(api);
      final notifier = container.read(searchSessionProvider.notifier);
      notifier.refresh();
      notifier.submit('jazz');
      notifier.submit('techno');
      await Future.delayed(const Duration(milliseconds: 900));

      notifier.resetToRoot();
      var state = container.read(searchSessionProvider);
      expect(state.resultsAvailable, isFalse);
      expect(state.results, isNull);
      expect(state.catalogPage.isRoot, isTrue);

      notifier.refresh();
      state = container.read(searchSessionProvider);
      // Newest-first history.
      expect(state.history.take(2), ['techno', 'jazz']);
    });
  });

  group('filters', () {
    test('reset clears facets even when all of them are hidden', () async {
      final container = makeContainer(_FakeApi());
      final notifier = container.read(searchSessionProvider.notifier);
      notifier.submit('jazz');
      await Future.delayed(_settle);
      notifier.setResultsFilter(
        const BrowseFilterQuery(type: SearchType.album),
      );
      expect(
        container.read(searchSessionProvider).resultsFilter.isEmpty,
        isTrue,
      );

      notifier.resetResults();

      expect(
        container.read(searchSessionProvider).resultsChoice.isEmpty,
        isTrue,
      );
    });

    test('card reset clears hidden facets', () async {
      final container = makeContainer(_FakeApi());
      final notifier = container.read(searchSessionProvider.notifier);
      notifier.submit('jazz');
      await Future.delayed(_settle);
      notifier.setResultsFilter(
        const BrowseFilterQuery(type: SearchType.album),
      );
      final shown = container.read(searchSessionProvider).resultsFilter;
      expect(shown.isEmpty, isTrue);

      notifier.setResultsFilter(
        const BrowseFilterQuery(order: NameMatchOrder.alphabetical),
        shown: shown,
        reset: true,
      );

      final choice = container.read(searchSessionProvider).resultsChoice;
      expect(choice.type, isNull);
      expect(choice.order, NameMatchOrder.alphabetical);
    });

    test('catalog reset clears hidden facets before applying new edits', () {
      final container = makeContainer(_FakeApi());
      final notifier = container.read(searchSessionProvider.notifier);
      notifier.openCatalog(id: 'a', title: 'A', filters: const [_genreField]);
      notifier.setCatalogFilter(const BrowseFilterQuery(genreIds: ['jazz']));
      notifier.openCatalog(id: 'a', title: 'A', filters: const [_textField]);
      notifier.setCatalogFilter(
        const BrowseFilterQuery(text: 'blue'),
        reset: true,
      );
      notifier.openCatalog(
        id: 'a',
        title: 'A',
        filters: const [_textField, _genreField],
      );

      final filter = container.read(searchSessionProvider).catalogFilter;
      expect(filter.genreIds, isEmpty);
      expect(filter.text, 'blue');
    });

    void expectChosen(BrowseFilterQuery filter) {
      expect(filter.type, SearchType.album);
      expect(filter.kind, ResultKind.nameMatches);
      expect(filter.sources, ['qobuz']);
      expect(filter.text, isEmpty, reason: 'the text is the query');
    }

    test('a filter belongs to the search it narrowed', () async {
      final api = _TwoKindApi();
      final container = makeContainer(api, modules: _twoSources);
      final notifier = container.read(searchSessionProvider.notifier);
      BrowseFilterQuery filter() =>
          container.read(searchSessionProvider).resultsFilter;
      notifier.refresh();
      notifier.submit('jazz');
      await Future.delayed(_settle);
      notifier.setResultsFilter(
        const BrowseFilterQuery(
          type: SearchType.album,
          kind: ResultKind.nameMatches,
          sources: ['qobuz'],
        ),
      );
      expectChosen(filter());

      // Into a page and back, it is still this search's.
      notifier.openCatalog(id: 'a', title: 'A');
      notifier.goBack();
      expectChosen(filter());

      // A new search starts without it, as does the next session.
      notifier.submit('blues');
      expect(filter().isEmpty, isTrue);
      await Future.delayed(_settle);
      expect(filter().isEmpty, isTrue);
      expect(
        makeContainer(
          api,
          modules: _twoSources,
        ).read(searchSessionProvider).resultsFilter.isEmpty,
        isTrue,
      );
    });

    test('a VIEW ALL opens a block without touching the filter', () async {
      final api = _TwoKindApi();
      final container = makeContainer(api, modules: _twoSources);
      final notifier = container.read(searchSessionProvider.notifier);
      SearchSessionState state() => container.read(searchSessionProvider);
      notifier.refresh();
      notifier.submit('jazz');
      await Future.delayed(_settle);

      notifier.expandBlock((kind: ResultKind.nameMatches, source: null));
      expect(state().resultsShown.kind, ResultKind.nameMatches);
      expect(state().resultsFilter.isEmpty, isTrue);

      notifier.submit('blues');
      expect(state().expandedBlock, isNull);
      expect(state().resultsShown.isEmpty, isTrue);
      await Future.delayed(_settle);
      expect(api.aiSearchCalls, 4, reason: 'recommendations asked both times');
    });

    test('an open block stays open while the filter still shows it', () async {
      final api = _TwoKindApi();
      final container = makeContainer(api, modules: _twoSources);
      final notifier = container.read(searchSessionProvider.notifier);
      SearchSessionState state() => container.read(searchSessionProvider);
      notifier.refresh();
      notifier.submit('jazz');
      await Future.delayed(_settle);

      notifier.expandBlock((kind: ResultKind.recommendations, source: 'qobuz'));
      notifier.setResultsFilter(
        const BrowseFilterQuery(type: SearchType.album),
      );
      expect(state().resultsShown.kind, ResultKind.recommendations);
      expect(state().resultsShown.sources, ['qobuz']);
      expect(state().resultsShown.type, SearchType.album);

      notifier.setResultsFilter(
        const BrowseFilterQuery(
          type: SearchType.album,
          sources: ['localfiles'],
        ),
      );
      expect(state().expandedBlock, isNull);

      notifier.expandBlock((kind: ResultKind.nameMatches, source: null));
      notifier.setResultsFilter(
        state().resultsFilter.copyWith(kind: ResultKind.recommendations),
      );
      expect(state().expandedBlock, isNull);
    });

    test('a kind cut for lacking is kept through other changes and a retry brings it back', () async {
      final api = _AlbumsLateApi();
      final container = makeContainer(api, modules: _twoSources);
      final notifier = container.read(searchSessionProvider.notifier);
      SearchSessionState state() => container.read(searchSessionProvider);
      notifier.refresh();
      notifier.submit('jazz');
      await Future.delayed(_settle);
      notifier.setResultsFilter(
        const BrowseFilterQuery(type: SearchType.album),
      );
      expect(state().results!.matches['qobuz'], isA<LegFailed>());
      expect(state().resultsFilter.type, isNull);
      expect(state().resultsChoice.type, SearchType.album);

      notifier.setResultsFilter(
        state().resultsFilter.copyWith(order: NameMatchOrder.alphabetical),
      );
      expect(state().resultsChoice.type, SearchType.album);
      expect(state().resultsChoice.order, NameMatchOrder.alphabetical);

      notifier.retry(ResultsLeg.matches, 'qobuz');
      expect(state().results!.matches['qobuz'], isA<LegLoading>());
      expect(state().resultsFilter.type, isNull);
      expect(
        state().results!.narrow(state().resultsFilter).matches,
        isNotEmpty,
      );

      await Future.delayed(_settle);
      expect(state().results!.matches['qobuz'], isA<LegReady>());
      expect(state().resultsFilter.type, SearchType.album);
      expect(
        state().results!.narrow(state().resultsFilter).matches.single.name,
        'An Album',
      );
      expect(state().resultsFilter.order, NameMatchOrder.alphabetical);
    });

    test('a kind a leg brings back under an open card is not taken from the choice', () async {
      final api = _AlbumsLateApi();
      final container = makeContainer(api, modules: _twoSources);
      final notifier = container.read(searchSessionProvider.notifier);
      SearchSessionState state() => container.read(searchSessionProvider);
      notifier.refresh();
      notifier.submit('jazz');
      await Future.delayed(_settle);
      notifier.setResultsFilter(
        const BrowseFilterQuery(type: SearchType.album),
      );
      expect(state().resultsFilter.type, isNull);

      final opened = state().resultsFilter.copyWith(text: 'jazz');
      notifier.retry(ResultsLeg.matches, 'qobuz');
      await Future.delayed(_settle);
      expect(state().resultsFilter.type, SearchType.album);

      notifier.setResultsFilter(
        opened.copyWith(order: NameMatchOrder.alphabetical),
        shown: opened,
      );
      expect(state().resultsChoice.type, SearchType.album);
      expect(state().resultsFilter.type, SearchType.album);
      expect(state().resultsFilter.order, NameMatchOrder.alphabetical);
    });

    test('a reset drops what the results hid of the choice too', () async {
      final api = _FakeApi();
      final container = makeContainer(api, modules: _twoNameOnlySources);
      final notifier = container.read(searchSessionProvider.notifier);
      notifier.refresh();
      notifier.submit('night');
      await Future.delayed(_settle);
      notifier.setResultsFilter(
        const BrowseFilterQuery(type: SearchType.album, sources: ['qobuz']),
      );
      expect(container.read(searchSessionProvider).resultsFilter.type, isNull);

      notifier.setResultsFilter(const BrowseFilterQuery());

      expect(
        container.read(searchSessionProvider).resultsChoice.isEmpty,
        isTrue,
      );
    });

    test(
      'an empty filter that changes nothing keeps what the results hid',
      () async {
        final api = _FakeApi();
        final container = makeContainer(api, modules: _nameOnlyModules);
        final notifier = container.read(searchSessionProvider.notifier);
        SearchSessionState state() => container.read(searchSessionProvider);
        notifier.refresh();
        notifier.submit('jazz');
        await Future.delayed(_settle);
        notifier.setResultsFilter(
          const BrowseFilterQuery(kind: ResultKind.recommendations),
        );
        expect(state().resultsFilter.isEmpty, isTrue);

        notifier.setResultsFilter(const BrowseFilterQuery());
        expect(state().resultsChoice.kind, ResultKind.recommendations);
      },
    );

    test('recommendations are not chosen where no source can suggest, but stay the choice', () async {
      final api = _FakeApi();
      final container = makeContainer(api, modules: _nameOnlyModules);
      final notifier = container.read(searchSessionProvider.notifier);
      notifier.refresh();
      notifier.submit('jazz');
      await Future.delayed(_settle);
      notifier.setResultsFilter(
        const BrowseFilterQuery(kind: ResultKind.recommendations),
      );

      final state = container.read(searchSessionProvider);
      expect(state.resultsFilterCapabilities.kind, FacetSupport.hidden);
      expect(state.resultsFilter.kind, isNull);
      expect(api.matchCalls, 1, reason: 'the name matches are asked');
      expect(state.results!.narrow(state.resultsFilter).matches, hasLength(1));
      expect(state.resultsChoice.kind, ResultKind.recommendations);

      notifier.expandBlock((kind: ResultKind.nameMatches, source: null));
      expect(
        container.read(searchSessionProvider).resultsShown.kind,
        ResultKind.nameMatches,
      );
    });

    test('a source not searched, or a facet the results hide, does not narrow them', () async {
      final api = _FakeApi();
      final container = makeContainer(api, modules: _twoNameOnlySources);
      final notifier = container.read(searchSessionProvider.notifier);
      notifier.refresh();
      notifier.submit('night');
      await Future.delayed(_settle);
      notifier.setResultsFilter(
        const BrowseFilterQuery(
          type: SearchType.album,
          genreIds: ['jazz'],
          sources: ['jamendo', 'qobuz'],
        ),
      );

      final state = container.read(searchSessionProvider);
      final capabilities = state.resultsFilterCapabilities;
      expect(capabilities.type, FacetSupport.hidden);
      expect(capabilities.genre, FacetSupport.hidden);
      expect(state.resultsFilter.type, isNull);
      expect(state.resultsFilter.genreIds, isEmpty);
      expect(state.resultsFilter.sources, ['qobuz']);
      expect(state.results!.narrow(state.resultsFilter).matches, hasLength(1));
    });

    test('catalog filters this build cannot read are let go', () {
      prefs.setString('Kalinka.catalogFilters', '[not json');
      final container = makeContainer(_FakeApi());

      container
          .read(searchSessionProvider.notifier)
          .openCatalog(id: 'a', title: 'A', filters: const [_genreField]);
      expect(
        container.read(searchSessionProvider).catalogFilter.isEmpty,
        isTrue,
      );
    });

    test('each catalog comes back under its own filter', () {
      final container = makeContainer(_FakeApi());
      final notifier = container.read(searchSessionProvider.notifier);
      BrowseFilterQuery filter() =>
          container.read(searchSessionProvider).catalogFilter;
      notifier.refresh();

      notifier.openCatalog(id: 'a', title: 'A', filters: const [_genreField]);
      notifier.setCatalogFilter(const BrowseFilterQuery(genreIds: ['jazz']));
      notifier.openCatalog(id: 'b', title: 'B', filters: const [_genreField]);
      expect(filter().isEmpty, isTrue);

      notifier.openCatalog(id: 'a', title: 'A', filters: const [_genreField]);
      expect(filter().genreIds, ['jazz']);

      notifier.backToCatalogsRoot();
      expect(filter().isEmpty, isTrue);
      notifier.resetToRoot();
      final restarted = makeContainer(_FakeApi());
      restarted
          .read(searchSessionProvider.notifier)
          .openCatalog(id: 'a', title: 'A', filters: const [_genreField]);
      expect(restarted.read(searchSessionProvider).catalogFilter.genreIds, [
        'jazz',
      ]);
    });

    test('a catalog keeps only the facets its source still declares', () {
      final container = makeContainer(_FakeApi());
      final notifier = container.read(searchSessionProvider.notifier);
      notifier.openCatalog(
        id: 'a',
        title: 'A',
        filters: const [_textField, _genreField],
      );
      notifier.setCatalogFilter(
        const BrowseFilterQuery(text: 'blue', genreIds: ['jazz']),
      );

      notifier.openCatalog(id: 'a', title: 'A', filters: const [_textField]);

      final filter = container.read(searchSessionProvider).catalogFilter;
      expect(filter.text, 'blue');
      expect(filter.genreIds, isEmpty);
    });

    group('of catalogs absent from the root listing', () {
      const kept = 'kalinka:jamendo:catalog:popular';
      const gone = 'kalinka:jamendo:catalog:retired';

      setUp(() {
        prefs.setString(
          'Kalinka.catalogFilters',
          '{"$kept":{"genreIds":["jazz"]},"$gone":{"genreIds":["rock"]}}',
        );
      });

      test('are retained after a refresh', () async {
        final container = makeContainer(_FakeApi());
        container.read(searchSessionProvider.notifier).refresh();
        await Future.delayed(const Duration(milliseconds: 50));

        final saved = prefs.getString('Kalinka.catalogFilters');
        expect(saved, contains(kept));
        expect(saved, contains(gone));
      });

      test(
        'are retained after sources load without a deletion signal',
        () async {
          const collections = _CollectionsApi.shelfId;
          const gone = 'kalinka:collections:catalog:retired';
          prefs.setString(
            'Kalinka.catalogFilters',
            '{"$collections":{"text":"night"},"$gone":{"genreIds":["rock"]}}',
          );
          final container = makeContainer(
            _CollectionsApi(),
            modules: _nameOnlyModules,
            modulesAfter: const Duration(milliseconds: 20),
          );
          container.read(searchSessionProvider.notifier).refresh();
          await Future.delayed(const Duration(milliseconds: 100));

          final saved = prefs.getString('Kalinka.catalogFilters');
          expect(saved, contains(collections));
          expect(saved, contains(gone));
        },
      );
    });
  });

  group('SearchZeroState', () {
    testWidgets('shows no pinned heading without pins', (tester) async {
      final api = _FakeApi();
      final container = makeContainer(api);
      container.read(searchSessionProvider.notifier).refresh();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SearchZeroState(onOpenCatalog: (_, _, {focusItemId}) {}),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('CUSTOMISE HOME'), findsNothing);
      expect(find.text('No catalog sources available.'), findsNothing);
      expect(find.text('RECENTLY FAVOURITED'), findsNothing);
    });
  });
}
